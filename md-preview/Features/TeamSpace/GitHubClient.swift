//
//  GitHubClient.swift
//  md-preview
//
//  The GitHub calls a Team Space needs: device-flow sign-in, and the Git
//  Data API (refs, commits, trees, blobs) to read a branch and add commits
//  to it. No git binary is involved, so it works in the sandbox. Kept free
//  of AppKit so the SPM helper tests can exercise it without a GUI host.
//

import Foundation

nonisolated struct GitHubClient: Sendable {

    enum Failure: Error, Equatable {
        case unauthorized
        case notFound
        /// The repository has no commits yet.
        case emptyRepository
        /// The branch moved since it was read; read it again and retry.
        case notFastForward
        case rateLimited
        case server(status: Int, message: String?)
        case invalidResponse
    }

    struct Repository: Equatable, Sendable {
        let fullName: String
        let defaultBranch: String
        let canPush: Bool
    }

    enum RefResult: Equatable, Sendable {
        /// The ref still points where the `etag` said; the call did not
        /// count against the rate limit.
        case notModified
        case head(sha: String, etag: String?)
    }

    struct TreeEntry: Equatable, Sendable {
        let path: String
        let mode: String
        let sha: String
        let size: Int?
    }

    /// One change in a new tree: a blob for `path`, or its removal.
    struct TreeChange: Equatable, Sendable {
        let path: String
        let mode: String
        let sha: String?
    }

    let token: String
    let apiURL: URL
    let session: URLSession

    init(token: String, apiURL: URL = URL(string: "https://api.github.com")!,
         session: URLSession = ShareLinkClient.sharedSession) {
        self.token = token
        self.apiURL = apiURL
        self.session = session
    }

    // MARK: - Account

    func login() async throws -> String {
        struct Body: Decodable { let login: String }
        return try decode(Body.self, from: try await send(request("user"))).login
    }

    func repository(_ fullName: String) async throws -> Repository {
        struct Body: Decodable {
            struct Permissions: Decodable { let push: Bool? }
            let full_name: String
            let default_branch: String
            let permissions: Permissions?
        }
        let body = try decode(Body.self, from: try await send(request("repos/\(fullName)")))
        return Repository(fullName: body.full_name, defaultBranch: body.default_branch,
                          canPush: body.permissions?.push ?? false)
    }

    // MARK: - Reading

    func ref(_ repo: String, branch: String, etag: String?) async throws -> RefResult {
        var request = request("repos/\(repo)/git/ref/heads/\(branch)")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, http) = try await exchange(request)
        if http.statusCode == 304 { return .notModified }
        try check(http, data: data)
        struct Body: Decodable { struct Object: Decodable { let sha: String }; let object: Object }
        let body = try decode(Body.self, from: data)
        return .head(sha: body.object.sha, etag: http.value(forHTTPHeaderField: "ETag"))
    }

    /// The commit's tree SHA.
    func tree(ofCommit sha: String, in repo: String) async throws -> String {
        struct Body: Decodable { struct Tree: Decodable { let sha: String }; let tree: Tree }
        return try decode(Body.self, from: try await send(request("repos/\(repo)/git/commits/\(sha)"))).tree.sha
    }

    /// Every blob in the tree, at any depth.
    func blobs(inTree sha: String, in repo: String) async throws -> [TreeEntry] {
        struct Body: Decodable {
            struct Entry: Decodable { let path: String; let mode: String; let type: String; let sha: String; let size: Int? }
            let tree: [Entry]
            let truncated: Bool
        }
        let body = try decode(Body.self, from: try await send(request("repos/\(repo)/git/trees/\(sha)?recursive=1")))
        // A truncated listing would read as deleted files.
        guard !body.truncated else { throw Failure.server(status: 200, message: "Repository tree is too large") }
        return body.tree.filter { $0.type == "blob" }
            .map { TreeEntry(path: $0.path, mode: $0.mode, sha: $0.sha, size: $0.size) }
    }

    func blob(_ sha: String, in repo: String) async throws -> Data {
        var request = request("repos/\(repo)/git/blobs/\(sha)")
        request.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")
        return try await send(request)
    }

    // MARK: - Writing

    func createBlob(_ data: Data, in repo: String) async throws -> String {
        try await post("repos/\(repo)/git/blobs",
                       ["content": data.base64EncodedString(), "encoding": "base64"])
    }

    func createTree(base: String, changes: [TreeChange], in repo: String) async throws -> String {
        let entries: [[String: Any]] = changes.map {
            ["path": $0.path, "mode": $0.mode, "type": "blob", "sha": $0.sha.map { $0 as Any } ?? NSNull()]
        }
        return try await post("repos/\(repo)/git/trees", ["base_tree": base, "tree": entries])
    }

    func createCommit(message: String, tree: String, parent: String, in repo: String) async throws -> String {
        try await post("repos/\(repo)/git/commits", ["message": message, "tree": tree, "parents": [parent]])
    }

    /// Moves the branch to `sha`, only if that is a fast-forward.
    func updateRef(_ repo: String, branch: String, to sha: String) async throws {
        var request = request("repos/\(repo)/git/refs/heads/\(branch)")
        request.httpMethod = "PATCH"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["sha": sha, "force": false])
        let (data, http) = try await exchange(request)
        if http.statusCode == 422 { throw Failure.notFastForward }
        try check(http, data: data)
    }

    /// Creates a file with the Contents API, the only write an empty
    /// repository accepts; it makes the first commit and the branch.
    func createFile(_ path: String, data: Data, message: String, branch: String, in repo: String) async throws {
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        var request = request("repos/\(repo)/contents/\(encodedPath)")
        request.httpMethod = "PUT"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "message": message, "content": data.base64EncodedString(), "branch": branch,
        ])
        let (data, http) = try await exchange(request)
        try check(http, data: data)
    }

    // MARK: - Device flow

    struct DeviceCode: Equatable, Sendable {
        let deviceCode: String
        let userCode: String
        let verificationURL: URL
        let interval: Int
        let expiresIn: Int
    }

    enum TokenPoll: Equatable, Sendable {
        case pending
        /// Wait this many seconds between polls from now on.
        case slowDown(interval: Int)
        case token(String)
        case expired
        case denied
    }

    static let webURL = URL(string: "https://github.com")!

    static func requestDeviceCode(clientID: String, scope: String,
                                  session: URLSession = ShareLinkClient.sharedSession) async throws -> DeviceCode {
        let body = try await postForm(webURL.appending(path: "login/device/code"),
                                      ["client_id": clientID, "scope": scope], session: session)
        guard let deviceCode = body["device_code"]?.string, let userCode = body["user_code"]?.string,
              let uri = body["verification_uri"]?.string.flatMap(URL.init(string:))
        else { throw Failure.invalidResponse }
        return DeviceCode(deviceCode: deviceCode, userCode: userCode, verificationURL: uri,
                          interval: body["interval"]?.int ?? 5, expiresIn: body["expires_in"]?.int ?? 900)
    }

    static func pollToken(clientID: String, deviceCode: String,
                          session: URLSession = ShareLinkClient.sharedSession) async throws -> TokenPoll {
        let body = try await postForm(webURL.appending(path: "login/oauth/access_token"), [
            "client_id": clientID, "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ], session: session)
        if let token = body["access_token"]?.string { return .token(token) }
        switch body["error"]?.string {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown(interval: body["interval"]?.int ?? 10)
        case "expired_token": return .expired
        case "access_denied": return .denied
        default: throw Failure.server(status: 200, message: body["error_description"]?.string)
        }
    }

    // MARK: - Private

    private func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: apiURL)!.absoluteURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    /// POSTs JSON and returns the `sha` of what it created.
    private func post(_ path: String, _ body: [String: Any]) async throws -> String {
        var request = request(path)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        struct Created: Decodable { let sha: String }
        return try decode(Created.self, from: try await send(request)).sha
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, http) = try await exchange(request)
        try check(http, data: data)
        return data
    }

    private func exchange(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        return (data, http)
    }

    private func check(_ http: HTTPURLResponse, data: Data) throws {
        guard !(200..<300).contains(http.statusCode) else { return }
        let message = (try? JSONDecoder().decode([String: AnyDecodable].self, from: data))?["message"]?.string
        switch http.statusCode {
        case 401: throw Failure.unauthorized
        case 404: throw Failure.notFound
        case 409 where message?.localizedCaseInsensitiveContains("empty") == true: throw Failure.emptyRepository
        case 429: throw Failure.rateLimited
        case 403 where http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0": throw Failure.rateLimited
        default: throw Failure.server(status: http.statusCode, message: message)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw Failure.invalidResponse }
    }

    private static func postForm(_ url: URL, _ fields: [String: String],
                                 session: URLSession) async throws -> [String: AnyDecodable] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let body = try? JSONDecoder().decode([String: AnyDecodable].self, from: data)
        else { throw Failure.invalidResponse }
        return body
    }
}

/// A JSON value that is a string or a number, for the few loosely typed
/// fields read above.
nonisolated struct AnyDecodable: Decodable, Sendable {
    let string: String?
    let int: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        string = try? container.decode(String.self)
        int = try? container.decode(Int.self)
    }
}
