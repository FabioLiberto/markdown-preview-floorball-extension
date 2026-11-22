import Foundation
import XCTest
@testable import MarkdownHelpers

final class TeamSpaceMergeTests: XCTestCase {

    func testChangesToDifferentLinesCombine() {
        let base = "a\nb\nc\nd\n"
        XCTAssertEqual(TeamSpaceMerge.merge(base: base, ours: "A\nb\nc\nd\n", theirs: "a\nb\nc\nD\n"), "A\nb\nc\nD\n")
    }

    func testInsertionsOnBothSidesCombine() {
        let base = "one\ntwo\nthree\n"
        XCTAssertEqual(TeamSpaceMerge.merge(base: base, ours: "zero\none\ntwo\nthree\n", theirs: "one\ntwo\nthree\nfour\n"),
                       "zero\none\ntwo\nthree\nfour\n")
    }

    func testChangesToTheSameLineConflict() {
        XCTAssertNil(TeamSpaceMerge.merge(base: "a\nb\n", ours: "a\nX\n", theirs: "a\nY\n"))
    }

    func testTheSameChangeOnBothSidesIsNoConflict() {
        XCTAssertEqual(TeamSpaceMerge.merge(base: "a\nb\nc\n", ours: "a\nB\nc\n", theirs: "a\nB\nc\n"), "a\nB\nc\n")
    }

    func testMovingDifferentPlayersInADiagramCombines() {
        let base = """
        ```floorball
        { "elements": [
          { "id": "p1", "type": "player", "x": 0.1, "y": 0.1 },
          { "id": "p2", "type": "player", "x": 0.2, "y": 0.2 },
          { "id": "p3", "type": "player", "x": 0.3, "y": 0.3 }
        ] }
        ```

        """
        let ours = base.replacingOccurrences(of: #""x": 0.1"#, with: #""x": 0.5"#)
        let theirs = base.replacingOccurrences(of: #""y": 0.3"#, with: #""y": 0.9"#)
        let merged = TeamSpaceMerge.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertEqual(merged, ours.replacingOccurrences(of: #""y": 0.3"#, with: #""y": 0.9"#))
    }

    func testTextWithoutAFinalNewlineSurvives() {
        XCTAssertEqual(TeamSpaceMerge.merge(base: "a\nm\nb", ours: "A\nm\nb", theirs: "a\nm\nB"), "A\nm\nB")
    }
}

final class TeamSpaceSyncPlanTests: XCTestCase {

    func testEachPathGoesWhereItChanged() {
        let plan = TeamSpaceSyncPlan(
            base: ["same": "1", "remoteEdit": "1", "localEdit": "1", "both": "1", "remoteGone": "1", "localGone": "1"],
            local: ["same": "1", "remoteEdit": "1", "localEdit": "2", "both": "2", "remoteGone": "1", "newLocal": "9"],
            remote: ["same": "1", "remoteEdit": "2", "localEdit": "1", "both": "3", "localGone": "1", "newRemote": "8"])
        XCTAssertEqual(plan.inSync, ["same": "1"])
        XCTAssertEqual(plan.download, ["remoteEdit": "2", "newRemote": "8"])
        XCTAssertEqual(plan.upload, ["localEdit", "newLocal"])
        XCTAssertEqual(plan.deleteLocally, ["remoteGone"])
        XCTAssertEqual(plan.deleteRemotely, ["localGone"])
        XCTAssertEqual(plan.bothChanged, ["both"])
    }

    func testBlobSHAMatchesGit() {
        // `printf 'hello\n' | git hash-object --stdin`
        XCTAssertEqual(TeamSpaceSyncEngine.blobSHA(Data("hello\n".utf8)), "ce013625030ba8dba906f756967f9e9ca394464a")
    }
}

final class TeamSpaceSyncEngineTests: XCTestCase {

    private var folder: URL!
    private var stateFolder: URL!
    private var server: FakeGitHub!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "TeamSpaceSyncTests-\(UUID().uuidString)")
        folder = root.appending(path: "folder")
        stateFolder = root.appending(path: "state")
        server = FakeGitHub()
        FakeGitHubProtocol.server = server
    }

    override func tearDownWithError() throws {
        FakeGitHubProtocol.server = nil
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    private func engine() -> TeamSpaceSyncEngine {
        let session = ShareLinkClient.makeSession(protocolClasses: [FakeGitHubProtocol.self])
        return TeamSpaceSyncEngine(
            client: GitHubClient(token: "t", apiURL: URL(string: "https://api.test/")!, session: session),
            repo: "team/playbook", branch: "main", folder: folder, stateFolder: stateFolder, deviceName: "Test Mac")
    }

    private func local(_ path: String) -> String? {
        try? String(contentsOf: folder.appending(path: path), encoding: .utf8)
    }

    private func writeLocal(_ path: String, _ text: String) throws {
        let url = folder.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testFirstSyncDownloadsTheBranchWithoutHiddenFiles() async throws {
        server.commit(["plays/powerplay.md": "# PP\n", ".github/ci.yml": "x"])
        let report = try await engine().sync()
        XCTAssertEqual(report.received, ["plays/powerplay.md"])
        XCTAssertEqual(local("plays/powerplay.md"), "# PP\n")
        XCTAssertNil(local(".github/ci.yml"))
    }

    func testLocalChangesGoUpAsOneCommitAndKeepHiddenRemoteFiles() async throws {
        server.commit(["a.md": "a\n", ".gitignore": "x"])
        let engine = engine()
        _ = try await engine.sync()
        try writeLocal("a.md", "a2\n")
        try writeLocal("new/b.md", "b\n")
        let report = try await engine.sync()
        XCTAssertEqual(Set(report.sent), ["a.md", "new/b.md"])
        XCTAssertEqual(server.files, ["a.md": "a2\n", "new/b.md": "b\n", ".gitignore": "x"])
        XCTAssertEqual(server.commitCount, 2)
    }

    func testAnUnchangedBranchIsNotReadAgain() async throws {
        server.commit(["a.md": "a\n"])
        let engine = engine()
        _ = try await engine.sync()
        server.requests.removeAll()
        _ = try await engine.sync()
        XCTAssertEqual(server.requests, ["GET ref"])
    }

    func testEditsToDifferentLinesMerge() async throws {
        server.commit(["a.md": "1\n2\n3\n"])
        let engine = engine()
        _ = try await engine.sync()
        try writeLocal("a.md", "1\n2\nthree\n")
        server.commit(["a.md": "one\n2\n3\n"])
        _ = try await engine.sync()
        XCTAssertEqual(local("a.md"), "one\n2\nthree\n")
        XCTAssertEqual(server.files["a.md"], "one\n2\nthree\n")
    }

    func testAConflictLeavesBothSidesUntilResolved() async throws {
        server.commit(["a.md": "1\n"])
        let engine = engine()
        _ = try await engine.sync()
        try writeLocal("a.md", "mine\n")
        server.commit(["a.md": "theirs\n"])

        let report = try await engine.sync()
        XCTAssertEqual(report.conflicts.map(\.path), ["a.md"])
        XCTAssertEqual(local("a.md"), "mine\n")
        XCTAssertEqual(server.files["a.md"], "theirs\n")

        try await engine.resolve(report.conflicts[0], with: .keepBoth)
        let next = try await engine.sync()
        XCTAssertEqual(next.conflicts, [])
        XCTAssertEqual(local("a (GitHub).md"), "theirs\n")
        XCTAssertEqual(server.files["a.md"], "mine\n")
        XCTAssertEqual(server.files["a (GitHub).md"], "theirs\n")
    }

    func testKeepRemoteTakesGitHubsVersion() async throws {
        server.commit(["a.md": "1\n"])
        let engine = engine()
        _ = try await engine.sync()
        try writeLocal("a.md", "mine\n")
        server.commit(["a.md": "theirs\n"])
        let conflict = try await engine.sync().conflicts[0]
        try await engine.resolve(conflict, with: .keepRemote)
        let next = try await engine.sync()
        XCTAssertEqual(next.sent, [])
        XCTAssertEqual(local("a.md"), "theirs\n")
    }

    func testDeletionsSyncBothWays() async throws {
        server.commit(["a.md": "a\n", "b.md": "b\n"])
        let engine = engine()
        _ = try await engine.sync()
        try FileManager.default.removeItem(at: folder.appending(path: "a.md"))
        server.commit(["a.md": "a\n"])
        _ = try await engine.sync()
        XCTAssertEqual(server.files, [:])
        XCTAssertNil(local("b.md"))
    }

    func testAPushThatLosesARaceIsRetried() async throws {
        server.commit(["a.md": "a\n", "b.md": "b\n"])
        let engine = engine()
        _ = try await engine.sync()
        try writeLocal("a.md", "a2\n")
        server.beforeNextRefUpdate = { $0.commit(["a.md": "a\n", "b.md": "b2\n"]) }
        _ = try await engine.sync()
        XCTAssertEqual(server.files, ["a.md": "a2\n", "b.md": "b2\n"])
        XCTAssertEqual(local("b.md"), "b2\n")
    }

    func testAnEmptyRepositoryStartsFromTheFolder() async throws {
        try writeLocal("a.md", "a\n")
        try writeLocal("b.md", "b\n")
        _ = try await engine().sync()
        XCTAssertEqual(server.files, ["a.md": "a\n", "b.md": "b\n"])
    }
}

// MARK: - Fake GitHub

/// An in-memory repository behind the Git Data API calls the engine makes.
final class FakeGitHub: @unchecked Sendable {
    private let lock = NSLock()
    private var blobs: [String: Data] = [:]
    private var trees: [String: [String: String]] = [:]
    private var commits: [String: (tree: String, parent: String?)] = [:]
    private var head: String?
    var requests: [String] = []
    var beforeNextRefUpdate: ((FakeGitHub) -> Void)?

    var commitCount: Int { lock.withLock { commits.count } }

    var files: [String: String] {
        lock.withLock {
            guard let head, let tree = trees[commits[head]!.tree] else { return [:] }
            return tree.mapValues { String(decoding: blobs[$0]!, as: UTF8.self) }
        }
    }

    /// Someone else pushes a commit with exactly these files.
    func commit(_ files: [String: String]) {
        lock.withLock {
            var tree: [String: String] = [:]
            for (path, text) in files { tree[path] = storeBlob(Data(text.utf8)) }
            let treeSHA = UUID().uuidString
            trees[treeSHA] = tree
            let sha = UUID().uuidString
            commits[sha] = (treeSHA, head)
            head = sha
        }
    }

    private func storeBlob(_ data: Data) -> String {
        let sha = TeamSpaceSyncEngine.blobSHA(data)
        blobs[sha] = data
        return sha
    }

    func handle(_ request: URLRequest, body: Data?) -> (Int, [String: String], Data) {
        if request.httpMethod == "PATCH", let hook = beforeNextRefUpdate {
            beforeNextRefUpdate = nil
            hook(self)
        }
        return lock.withLock { route(request, body: body) }
    }

    private func route(_ request: URLRequest, body: Data?) -> (Int, [String: String], Data) {
        let parts = request.url!.path.split(separator: "/").map(String.init).dropFirst(3)
        let method = request.httpMethod ?? "GET"
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        func reply(_ object: Any, status: Int = 200, headers: [String: String] = [:]) -> (Int, [String: String], Data) {
            (status, headers, try! JSONSerialization.data(withJSONObject: object))
        }

        switch (method, parts.first, parts.dropFirst().first) {
        case ("GET", "git", "ref"):
            requests.append("GET ref")
            guard let head else { return reply(["message": "Git Repository is empty."], status: 409) }
            let etag = "\"\(head)\""
            if request.value(forHTTPHeaderField: "If-None-Match") == etag { return (304, [:], Data()) }
            return reply(["object": ["sha": head]], headers: ["ETag": etag])
        case ("GET", "git", "commits"):
            requests.append("GET commit")
            return reply(["tree": ["sha": commits[parts.last!]!.tree]])
        case ("GET", "git", "trees"):
            requests.append("GET tree")
            let entries = trees[parts.last!]!.map {
                ["path": $0.key, "mode": "100644", "type": "blob", "sha": $0.value, "size": blobs[$0.value]!.count] as [String: Any]
            }
            return reply(["tree": entries, "truncated": false])
        case ("GET", "git", "blobs"):
            requests.append("GET blob")
            return (200, [:], blobs[parts.last!]!)
        case ("POST", "git", "blobs"):
            return reply(["sha": storeBlob(Data(base64Encoded: json["content"] as! String)!)], status: 201)
        case ("POST", "git", "trees"):
            var tree = trees[json["base_tree"] as! String]!
            for entry in json["tree"] as! [[String: Any]] {
                tree[entry["path"] as! String] = entry["sha"] as? String
            }
            let sha = UUID().uuidString
            trees[sha] = tree
            return reply(["sha": sha], status: 201)
        case ("POST", "git", "commits"):
            let sha = UUID().uuidString
            commits[sha] = (json["tree"] as! String, (json["parents"] as! [String]).first)
            return reply(["sha": sha], status: 201)
        case ("PATCH", "git", "refs"):
            let sha = json["sha"] as! String
            guard commits[sha]?.parent == head else { return reply(["message": "Update is not a fast forward"], status: 422) }
            head = sha
            return reply(["object": ["sha": sha]])
        case ("PUT", "contents", _):
            let path = parts.dropFirst().joined(separator: "/")
            let blob = storeBlob(Data(base64Encoded: json["content"] as! String)!)
            let treeSHA = UUID().uuidString
            trees[treeSHA] = [path: blob]
            let sha = UUID().uuidString
            commits[sha] = (treeSHA, head)
            head = sha
            return reply(["content": ["path": path]], status: 201)
        default:
            return reply(["message": "Not Found"], status: 404)
        }
    }
}

final class FakeGitHubProtocol: URLProtocol {
    nonisolated(unsafe) static var server: FakeGitHub?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let (status, headers, data) = Self.server?.handle(request, body: body) ?? (500, [:], Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
