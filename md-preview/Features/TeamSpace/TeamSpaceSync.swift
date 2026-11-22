//
//  TeamSpaceSync.swift
//  md-preview
//
//  Two-way sync between a local folder and one branch of a GitHub
//  repository. Each round compares three snapshots of path → git blob SHA:
//  the last synced commit (the base), the folder, and the branch.
//
//  - Changed on one side only: copied to the other side.
//  - Changed on both: merged line by line (TeamSpaceMerge); when the same
//    lines changed, the file is a conflict and stays as it is on both sides
//    until the user picks a version.
//
//  Local changes go up as one commit, made with the Git Data API and moved
//  onto the branch only as a fast-forward, so a commit someone pushed in
//  the meantime is never overwritten. Hidden files (any path component
//  starting with ".") are not synced, on either side.
//
//  The base's file contents are kept in `stateFolder/base`, for merging.
//  Kept free of AppKit so the SPM helper tests can exercise it.
//

import CryptoKit
import Foundation

nonisolated struct TeamSpaceSyncState: Codable, Equatable, Sendable {
    var commit: String?
    var tree: String?
    var etag: String?
    /// Path → blob SHA at `commit`.
    var files: [String: String] = [:]
}

nonisolated struct TeamSpaceConflict: Hashable, Sendable {
    let path: String
    /// The branch's version; nil when it deleted the file.
    let remoteSHA: String?
    /// The folder's version; nil when it deleted the file.
    let localSHA: String?
}

/// What one round does with each path. Pure, so it is tested on its own.
nonisolated struct TeamSpaceSyncPlan: Equatable, Sendable {
    var download: [String: String] = [:]
    var deleteLocally: Set<String> = []
    var upload: Set<String> = []
    var deleteRemotely: Set<String> = []
    /// Changed on both sides; the engine tries a line merge.
    var bothChanged: Set<String> = []
    /// The same on both sides already.
    var inSync: [String: String] = [:]

    init(base: [String: String], local: [String: String], remote: [String: String]) {
        for path in Set(base.keys).union(local.keys).union(remote.keys) {
            let b = base[path], l = local[path], r = remote[path]
            if l == r {
                if let r { inSync[path] = r }
            } else if l == b {
                if let r { download[path] = r } else { deleteLocally.insert(path) }
            } else if r == b {
                if l != nil { upload.insert(path) } else { deleteRemotely.insert(path) }
            } else {
                bothChanged.insert(path)
            }
        }
    }

    var hasRemoteChanges: Bool { !upload.isEmpty || !deleteRemotely.isEmpty }
}

actor TeamSpaceSyncEngine {

    enum Failure: Error, Equatable {
        /// The branch kept moving while this round tried to push.
        case busy
        /// The repository has no commits and the folder no files to start it.
        case emptyRepository
    }

    struct Report: Equatable, Sendable {
        var received: [String] = []
        var sent: [String] = []
        var conflicts: [TeamSpaceConflict] = []
    }

    enum Resolution: CaseIterable, Sendable {
        case keepLocal
        case keepRemote
        /// The branch's version is saved next to the file as a copy.
        case keepBoth

        nonisolated var title: String {
            switch self {
            case .keepLocal: NSLocalizedString("Keep Mine", comment: "Team Space conflict button")
            case .keepRemote: NSLocalizedString("Keep GitHub’s", comment: "Team Space conflict button")
            case .keepBoth: NSLocalizedString("Keep Both", comment: "Team Space conflict button")
            }
        }
    }

    /// GitHub's blob limit is 100 MB; larger files stay local.
    nonisolated static let maxFileSize = 50 * 1024 * 1024

    let client: GitHubClient
    let repo: String
    let branch: String
    let folder: URL
    let stateFolder: URL
    /// Names the device in commit messages.
    let deviceName: String
    private var state: TeamSpaceSyncState
    /// Path → (size, modified, SHA), so unchanged files are not hashed again.
    private var hashCache: [String: (Int, Date, String)] = [:]

    init(client: GitHubClient, repo: String, branch: String, folder: URL, stateFolder: URL, deviceName: String) {
        self.client = client
        self.repo = repo
        self.branch = branch
        self.folder = folder
        self.stateFolder = stateFolder
        self.deviceName = deviceName
        state = (try? Data(contentsOf: stateFolder.appending(path: "state.json")))
            .flatMap { try? JSONDecoder().decode(TeamSpaceSyncState.self, from: $0) } ?? TeamSpaceSyncState()
    }

    func sync() async throws -> Report {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A push that lost a race reads the branch again.
        for _ in 0..<3 {
            do { return try await syncOnce() } catch GitHubClient.Failure.notFastForward { state.etag = nil }
        }
        throw Failure.busy
    }

    func resolve(_ conflict: TeamSpaceConflict, with resolution: Resolution) async throws {
        var remote: Data?
        if let sha = conflict.remoteSHA { remote = try await client.blob(sha, in: repo) }
        let url = fileURL(conflict.path)
        switch resolution {
        case .keepLocal:
            break
        case .keepRemote:
            if let remote { try write(remote, to: url) } else { try? FileManager.default.removeItem(at: url) }
        case .keepBoth:
            if let remote { try write(remote, to: copyURL(for: url)) }
        }
        // Taking the branch's version as the base makes the next round see
        // a change on one side only: the folder's (keep local, keep both)
        // or none (keep remote).
        state.files[conflict.path] = conflict.remoteSHA
        if let remote { try write(remote, to: baseURL(conflict.path)) }
        try saveState()
    }

    // MARK: - Round

    private func syncOnce() async throws -> Report {
        let local = try scan()
        let ref: GitHubClient.RefResult
        do {
            ref = try await client.ref(repo, branch: branch, etag: state.etag)
        } catch GitHubClient.Failure.emptyRepository {
            return try await startRepository(local)
        }

        var movedTo: String?
        if case .head(let sha, let etag) = ref {
            state.etag = etag
            if sha != state.commit { movedTo = sha }
        } else if local == state.files {
            return Report()
        }

        let head: String, tree: String, remote: [String: String], modes: [String: String]
        if let movedTo {
            head = movedTo
            tree = try await client.tree(ofCommit: movedTo, in: repo)
            let entries = Dictionary(try await client.blobs(inTree: tree, in: repo).filter {
                ($0.mode == "100644" || $0.mode == "100755") && !Self.isHidden($0.path)
                    && ($0.size ?? 0) <= Self.maxFileSize
            }.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
            remote = entries.mapValues(\.sha)
            modes = entries.mapValues(\.mode)
        } else {
            // The branch is where the last round left it.
            guard let commit = state.commit, let lastTree = state.tree else {
                state.etag = nil
                return Report()
            }
            head = commit; tree = lastTree; remote = state.files; modes = [:]
        }

        var plan = TeamSpaceSyncPlan(base: state.files, local: local, remote: remote)
        var report = Report()
        // Starts as the last base; each path changes only once it synced.
        var newBase = state.files.merging(plan.inSync) { $1 }
        for path in state.files.keys where local[path] == nil && remote[path] == nil { newBase[path] = nil }
        var localContents: [String: Data] = [:]

        for path in plan.bothChanged.sorted() {
            if let merged = try await merge(path, local: local[path], remote: remote[path]) {
                try write(merged, to: fileURL(path))
                localContents[path] = merged
                plan.upload.insert(path)
                report.received.append(path)
            } else {
                report.conflicts.append(TeamSpaceConflict(path: path, remoteSHA: remote[path], localSHA: local[path]))
            }
        }

        let downloads = plan.download.sorted { $0.key < $1.key }
        let blobs = try await concurrently(downloads) { [client, repo] in try await client.blob($0.value, in: repo) }
        for ((path, sha), data) in zip(downloads, blobs) {
            // Edited since the scan: the next round sees it as both changed.
            guard currentSHA(path) == local[path] else { continue }
            try write(data, to: fileURL(path))
            try write(data, to: baseURL(path))
            newBase[path] = sha
            report.received.append(path)
        }
        for path in plan.deleteLocally.sorted() where currentSHA(path) == local[path] {
            try? FileManager.default.removeItem(at: fileURL(path))
            try? FileManager.default.removeItem(at: baseURL(path))
            newBase[path] = nil
            report.received.append(path)
        }

        var newHead = head, newTree = tree
        if plan.hasRemoteChanges {
            let uploads = plan.upload.sorted()
            for path in uploads where localContents[path] == nil {
                localContents[path] = try Data(contentsOf: fileURL(path))
            }
            let contents = uploads.map { localContents[$0]! }
            let shas = try await concurrently(contents) { [client, repo] in try await client.createBlob($0, in: repo) }
            var changes: [GitHubClient.TreeChange] = []
            for (path, sha) in zip(uploads, shas) {
                changes.append(.init(path: path, mode: modes[path] ?? "100644", sha: sha))
                newBase[path] = sha
            }
            for path in plan.deleteRemotely.sorted() {
                changes.append(.init(path: path, mode: modes[path] ?? "100644", sha: nil))
                newBase[path] = nil
            }
            newTree = try await client.createTree(base: tree, changes: changes, in: repo)
            newHead = try await client.createCommit(
                message: Self.commitMessage(for: changes.map(\.path), device: deviceName),
                tree: newTree, parent: head, in: repo)
            try await client.updateRef(repo, branch: branch, to: newHead)
            report.sent = changes.map(\.path)
            state.etag = nil
        }

        // The base keeps the content each synced file has now.
        for (path, data) in localContents { try write(data, to: baseURL(path)) }
        for path in plan.inSync.keys where state.files[path] != plan.inSync[path] {
            try? write(Data(contentsOf: fileURL(path)), to: baseURL(path))
        }
        state.commit = newHead
        state.tree = newTree
        state.files = newBase
        try saveState()
        return report
    }

    /// GitHub calls for many files, a few at a time; results in input order.
    private func concurrently<Item: Sendable, Result: Sendable>(
        _ items: [Item], _ call: @escaping @Sendable (Item) async throws -> Result
    ) async throws -> [Result] {
        try await withThrowingTaskGroup(of: (Int, Result).self) { group in
            var results = [Result?](repeating: nil, count: items.count)
            for (index, item) in items.enumerated() {
                if index >= 6, let (done, result) = try await group.next() { results[done] = result }
                group.addTask { (index, try await call(item)) }
            }
            for try await (done, result) in group { results[done] = result }
            return results.map { $0! }
        }
    }

    /// An empty repository takes no Git Data API calls; its first file goes
    /// up through the Contents API, and the next round syncs the rest.
    private func startRepository(_ local: [String: String]) async throws -> Report {
        guard let first = local.keys.sorted().first else { throw Failure.emptyRepository }
        try await client.createFile(first, data: Data(contentsOf: fileURL(first)),
                                    message: Self.commitMessage(for: [first], device: deviceName),
                                    branch: branch, in: repo)
        state = TeamSpaceSyncState()
        return try await syncOnce()
    }

    private func merge(_ path: String, local: String?, remote: String?) async throws -> Data? {
        guard let local, let remote,
              let base = try? String(contentsOf: baseURL(path), encoding: .utf8),
              let ours = try? String(contentsOf: fileURL(path), encoding: .utf8),
              Self.blobSHA(Data(ours.utf8)) == local,
              let theirs = String(data: try await client.blob(remote, in: repo), encoding: .utf8),
              let merged = TeamSpaceMerge.merge(base: base, ours: ours, theirs: theirs)
        else { return nil }
        return Data(merged.utf8)
    }

    // MARK: - Files

    private func scan() throws -> [String: String] {
        var result: [String: String] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return result }
        // Resolved on both sides: the enumerator reports a folder under
        // /private/var as /var, even when given the resolved path.
        let rootLength = folder.resolvingSymlinksInPath().path.count + 1
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            let path = String(url.resolvingSymlinksInPath().path.dropFirst(rootLength))
            let size = values.fileSize ?? 0, modified = values.contentModificationDate ?? .distantPast
            // Too large to sync: left as it was, so it does not read as deleted.
            guard size <= Self.maxFileSize else {
                if let base = state.files[path] { result[path] = base }
                continue
            }
            if let cached = hashCache[path], cached.0 == size, cached.1 == modified {
                result[path] = cached.2
            } else {
                let sha = Self.blobSHA(try Data(contentsOf: url))
                hashCache[path] = (size, modified, sha)
                result[path] = sha
            }
        }
        return result
    }

    private func currentSHA(_ path: String) -> String? {
        guard let data = try? Data(contentsOf: fileURL(path)) else { return nil }
        return Self.blobSHA(data)
    }

    private func fileURL(_ path: String) -> URL { folder.appending(path: path) }
    private func baseURL(_ path: String) -> URL { stateFolder.appending(path: "base").appending(path: path) }

    private func copyURL(for url: URL) -> URL {
        url.deletingLastPathComponent().uniqueChild(
            named: url.deletingPathExtension().lastPathComponent + " (GitHub)", extension: url.pathExtension)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func saveState() throws {
        try FileManager.default.createDirectory(at: stateFolder, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: stateFolder.appending(path: "state.json"), options: .atomic)
    }

    // MARK: - Helpers

    nonisolated static func isHidden(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// Git's object ID for a blob: SHA-1 of "blob <size>\0" and the bytes.
    nonisolated static func blobSHA(_ data: Data) -> String {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(data.count)\0".utf8))
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func commitMessage(for paths: [String], device: String) -> String {
        let names = paths.map { ($0 as NSString).lastPathComponent }
        let listed = names.count <= 3 ? names.joined(separator: ", ")
                                      : names.prefix(2).joined(separator: ", ") + " and \(names.count - 2) more"
        return "Update \(listed)\n\nSynced from Markdown Preview on \(device)."
    }
}
