//
//  TeamSpace.swift
//  md-preview
//
//  A Team Space is a folder in the app's container that syncs with a
//  GitHub repository: sign-in with GitHub's device flow, a sync round every
//  few seconds and when the app comes to the front, and a prompt for each
//  file that changed on the same lines here and on GitHub. The sidebar's
//  folder menu lists the folder; opening it there shows it like any other.
//

import AppKit
import SystemConfiguration

@MainActor @Observable
final class TeamSpace {

    static let shared = TeamSpace()

    /// The public Client ID of the GitHub OAuth App with device flow on.
    /// It is not a secret; device flow needs no client secret.
    static let clientID = "Ov23li97wPym8aCJy70F"

    /// The token's Keychain item: this service, account "token".
    static let keychainService = "doc.md-preview.github"
    private static let keychainAccount = "token"

    enum Status: Equatable {
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    enum Interval: Int, CaseIterable, Identifiable {
        case fifteenSeconds = 15, thirtySeconds = 30, oneMinute = 60, fiveMinutes = 300
        var id: Int { rawValue }
    }

    private(set) var login: String?
    /// "owner/name" of the connected repository.
    private(set) var repository: String?
    private(set) var branch: String?
    private(set) var status: Status = .idle
    private(set) var conflicts: [TeamSpaceConflict] = []
    /// Shown while the user confirms the code on github.com.
    private(set) var deviceCode: GitHubClient.DeviceCode?
    private(set) var isConnecting = false

    var interval: Interval {
        didSet {
            UserDefaults.standard.set(interval.rawValue, forKey: Keys.interval)
            restartLoop()
        }
    }

    var isSignedIn: Bool { token != nil }

    /// Signed in with a repository connected.
    var canSync: Bool { engine != nil }

    /// The synced folder; nil until a repository is connected.
    var folderURL: URL? {
        repository.map { Self.root.appending(path: String($0.split(separator: "/").last ?? "")) }
    }

    private enum Keys {
        static let repository = "TeamSpace.Repository"
        static let branch = "TeamSpace.Branch"
        static let login = "TeamSpace.Login"
        static let interval = "TeamSpace.SyncInterval"
    }

    private static let root = URL.applicationSupportDirectory.appending(path: "Team Space")
    private static let stateRoot = URL.applicationSupportDirectory.appending(path: "Team Space State")

    private var token: String?
    private var engine: TeamSpaceSyncEngine?
    private var loopTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var signInTask: Task<Void, Never>?
    /// Conflicts the user was already asked about.
    private var prompted: Set<TeamSpaceConflict> = []
    private var isPrompting = false

    private init() {
        let defaults = UserDefaults.standard
        repository = defaults.string(forKey: Keys.repository)
        branch = defaults.string(forKey: Keys.branch)
        login = defaults.string(forKey: Keys.login)
        interval = Interval(rawValue: defaults.integer(forKey: Keys.interval)) ?? .thirtySeconds
    }

    /// Called once, with the other services that wait for the first frame.
    func start() {
        token = (try? ShareLinkKeychain.read(account: Self.keychainAccount, service: Self.keychainService))
            .flatMap { String(data: $0, encoding: .utf8) }
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        makeEngine()
    }

    // MARK: - Sign in

    func signIn() {
        signInTask?.cancel()
        signInTask = Task {
            defer { deviceCode = nil }
            do {
                let code = try await GitHubClient.requestDeviceCode(clientID: Self.clientID, scope: "repo")
                deviceCode = code
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.userCode, forType: .string)
                NSWorkspace.shared.open(code.verificationURL)
                let token = try await pollForToken(code)
                try ShareLinkKeychain.write(Data(token.utf8), account: Self.keychainAccount, service: Self.keychainService)
                self.token = token
                let login = try await GitHubClient(token: token).login()
                self.login = login
                UserDefaults.standard.set(login, forKey: Keys.login)
                status = .idle
                makeEngine()
            } catch is CancellationError {
            } catch {
                status = .failed(Self.message(for: error))
            }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        deviceCode = nil
    }

    /// Forgets the token. The folder and its files stay.
    func signOut() {
        ShareLinkKeychain.delete(account: Self.keychainAccount, service: Self.keychainService)
        token = nil
        login = nil
        UserDefaults.standard.removeObject(forKey: Keys.login)
        status = .idle
        makeEngine()
    }

    private func pollForToken(_ code: GitHubClient.DeviceCode) async throws -> String {
        var interval = code.interval
        let deadline = Date.now.addingTimeInterval(TimeInterval(code.expiresIn))
        while Date.now < deadline {
            try await Task.sleep(for: .seconds(interval))
            switch try await GitHubClient.pollToken(clientID: Self.clientID, deviceCode: code.deviceCode) {
            case .pending: continue
            case .slowDown(let newInterval): interval = newInterval
            case .token(let token): return token
            case .denied: throw SignInFailure.denied
            case .expired: throw SignInFailure.expired
            }
        }
        throw SignInFailure.expired
    }

    private enum SignInFailure: Error { case denied, expired }

    // MARK: - Repository

    /// Connects "owner/name" or a github.com URL of the repository.
    func connect(_ input: String) {
        guard let token, let name = Self.repositoryName(from: input) else {
            status = .failed(NSLocalizedString("Enter the repository as owner/name.", comment: "Team Space error"))
            return
        }
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                let repo = try await GitHubClient(token: token).repository(name)
                guard repo.canPush else {
                    status = .failed(NSLocalizedString("Your GitHub account cannot push to this repository.", comment: "Team Space error"))
                    return
                }
                repository = repo.fullName
                branch = repo.defaultBranch
                UserDefaults.standard.set(repo.fullName, forKey: Keys.repository)
                UserDefaults.standard.set(repo.defaultBranch, forKey: Keys.branch)
                conflicts = []
                prompted = []
                makeEngine()
            } catch {
                status = .failed(Self.message(for: error))
            }
        }
    }

    /// Stops syncing. The folder and its files stay.
    func disconnect() {
        repository = nil
        branch = nil
        UserDefaults.standard.removeObject(forKey: Keys.repository)
        UserDefaults.standard.removeObject(forKey: Keys.branch)
        conflicts = []
        status = .idle
        makeEngine()
    }

    static func repositoryName(from input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://github.com/", "http://github.com/", "github.com/"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        if text.hasSuffix(".git") { text.removeLast(4) }
        if text.hasSuffix("/") { text.removeLast() }
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({
            !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains)
        }) else { return nil }
        return text
    }

    // MARK: - Syncing

    func syncNow() {
        guard syncTask == nil, let engine else { return }
        status = .syncing
        syncTask = Task {
            defer { syncTask = nil }
            do {
                let report = try await engine.sync()
                conflicts = report.conflicts
                status = .synced(.now)
                promptForNextConflict()
            } catch {
                status = .failed(Self.message(for: error))
                if error as? GitHubClient.Failure == .unauthorized { signOut() }
            }
        }
    }

    func showInSidebar() {
        guard let folderURL else { return }
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        appDelegate?.openFolder(folderURL)
    }

    func resolve(_ conflict: TeamSpaceConflict, with resolution: TeamSpaceSyncEngine.Resolution) {
        guard let engine else { return }
        Task {
            // A round running now would write the old base back.
            await syncTask?.value
            do {
                try await engine.resolve(conflict, with: resolution)
                conflicts.removeAll { $0.path == conflict.path }
                syncNow()
            } catch {
                status = .failed(Self.message(for: error))
            }
        }
    }

    @objc private func appDidBecomeActive(_ notification: Notification) {
        syncNow()
    }

    private func makeEngine() {
        engine = if let token, let repository, let branch, let folderURL {
            TeamSpaceSyncEngine(
                client: GitHubClient(token: token), repo: repository, branch: branch, folder: folderURL,
                stateFolder: Self.stateRoot.appending(path: repository.replacingOccurrences(of: "/", with: "-")),
                deviceName: SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "a Mac")
        } else {
            nil
        }
        restartLoop()
    }

    private func restartLoop() {
        loopTask?.cancel()
        guard engine != nil else { return }
        loopTask = Task { [interval] in
            while !Task.isCancelled {
                syncNow()
                try? await Task.sleep(for: .seconds(interval.rawValue))
            }
        }
    }

    // MARK: - Conflicts

    /// Asks about one conflict at a time, each only once.
    private func promptForNextConflict() {
        guard !isPrompting, let conflict = conflicts.first(where: { !prompted.contains($0) }) else { return }
        prompted.insert(conflict)
        isPrompting = true

        let alert = NSAlert()
        alert.messageText = String(
            format: NSLocalizedString("“%@” changed here and on GitHub", comment: "Team Space conflict alert; file name"),
            (conflict.path as NSString).lastPathComponent)
        alert.informativeText = NSLocalizedString(
            "Both versions changed the same lines, so they could not be combined. Choose the version to keep. Keep Both saves GitHub’s version as a copy next to yours.",
            comment: "Team Space conflict alert")
        let resolutions = TeamSpaceSyncEngine.Resolution.allCases
        for resolution in resolutions { alert.addButton(withTitle: resolution.title) }
        alert.addButton(withTitle: NSLocalizedString("Decide Later", comment: "Team Space conflict alert button"))

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            isPrompting = false
            let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            if resolutions.indices.contains(index) {
                resolve(conflict, with: resolutions[index])
            } else {
                promptForNextConflict()
            }
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    // MARK: - Errors

    static func message(for error: Error) -> String {
        switch error {
        case GitHubClient.Failure.unauthorized:
            NSLocalizedString("GitHub sign-in expired. Sign in again.", comment: "Team Space error")
        case GitHubClient.Failure.notFound:
            NSLocalizedString("Repository not found, or your account has no access to it.", comment: "Team Space error")
        case GitHubClient.Failure.rateLimited:
            NSLocalizedString("GitHub’s rate limit was reached. Syncing resumes shortly.", comment: "Team Space error")
        case TeamSpaceSyncEngine.Failure.emptyRepository:
            NSLocalizedString("The repository is empty. Add a file to the Team Space folder to start it.", comment: "Team Space error")
        case TeamSpaceSyncEngine.Failure.busy:
            NSLocalizedString("The repository kept changing. Trying again shortly.", comment: "Team Space error")
        case SignInFailure.denied:
            NSLocalizedString("Sign-in was declined on GitHub.", comment: "Team Space error")
        case SignInFailure.expired:
            NSLocalizedString("The sign-in code expired. Try again.", comment: "Team Space error")
        case GitHubClient.Failure.server(_, let message?):
            String(format: NSLocalizedString("GitHub: %@", comment: "Team Space error; GitHub's message"), message)
        case is URLError:
            NSLocalizedString("GitHub could not be reached.", comment: "Team Space error")
        default:
            error.localizedDescription
        }
    }
}
