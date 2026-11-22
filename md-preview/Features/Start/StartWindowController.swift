//
//  StartWindowController.swift
//  md-preview
//
//  The start page: what the app shows when it starts, or comes back from
//  the Dock, with no document to open and no Team Space. One click starts a
//  new document (in Edit Mode), opens a file or folder, goes to the Team
//  Space, or reopens a recent file or folder. It closes as soon as any
//  document opens (MarkdownDocumentController.addDocument).
//

import AppKit
import SwiftUI

@MainActor
final class StartWindowController: NSWindowController {

    static let shared = StartWindowController()

    private init() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        // Rebuilt on every show, so the recent items and the Team Space
        // button are current.
        window.contentViewController = NSHostingController(rootView: StartView(
            recents: Self.recentItems,
            hasTeamSpace: TeamSpace.shared.folderURL?.isExistingDirectory == true,
            perform: { [weak self] action in self?.perform(action) }))
        window.title = Self.appName
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }

    func dismiss() {
        window?.close()
    }

    enum Action {
        case newDocument
        case open
        case teamSpace
        case openRecent(URL)
    }

    private func perform(_ action: Action) {
        switch action {
        case .newDocument:
            NSDocumentController.shared.newDocument(nil)
        case .open:
            NSDocumentController.shared.openDocument(nil)
        case .teamSpace:
            if TeamSpace.shared.folderURL?.isExistingDirectory == true {
                TeamSpace.shared.showInSidebar()
            } else {
                appDelegate?.showSettingsWindow(pane: .teamSpace)
            }
        case .openRecent(let url):
            if url.isExistingDirectory {
                appDelegate?.openFolder(url)
            } else {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { NSAlert(error: error).runModal() }
                }
            }
        }
    }

    /// Recent files first, then recent folders, the newest of each first.
    private static var recentItems: [URL] {
        let files = NSDocumentController.shared.recentDocumentURLs
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let folders = RecentFolders.recorded.filter(\.isExistingDirectory)
        return Array((files.prefix(5) + folders.prefix(3)).prefix(7))
    }

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Markdown Preview"
    }
}

private struct StartView: View {
    let recents: [URL]
    let hasTeamSpace: Bool
    let perform: (StartWindowController.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(StartWindowController.appName)
                        .font(.title2.weight(.semibold))
                    Text(L("Training plans, playbooks, and tactics in Markdown."))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                StartRow(symbol: "square.and.pencil", title: L("New Document"), shortcut: "⌘N") {
                    perform(.newDocument)
                }
                StartRow(symbol: "folder", title: L("Open File or Folder…"), shortcut: "⌘O") {
                    perform(.open)
                }
                StartRow(symbol: "person.2", title: hasTeamSpace ? L("Open Team Space") : L("Set Up Team Space…")) {
                    perform(.teamSpace)
                }
            }

            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Recent"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                        .padding(.bottom, 4)
                    ForEach(recents, id: \.self) { url in
                        StartRow(symbol: url.isExistingDirectory ? "folder" : "doc.text",
                                 title: FileManager.default.displayName(atPath: url.path),
                                 detail: (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath) {
                            perform(.openRecent(url))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(width: 460, alignment: .leading)
    }
}

/// One clickable line: a symbol, a title, and a shortcut or a gray detail.
private struct StartRow: View {
    let symbol: String
    let title: String
    var shortcut: String?
    var detail: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 20)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1).truncationMode(.middle)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer(minLength: 12)
                if let shortcut {
                    Text(shortcut).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6).fill(isHovered ? Color.primary.opacity(0.08) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
