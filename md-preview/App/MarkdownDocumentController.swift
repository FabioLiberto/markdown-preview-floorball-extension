//
//  MarkdownDocumentController.swift
//  md-preview
//

import Cocoa
import UniformTypeIdentifiers

final class MarkdownDocumentController: NSDocumentController {
    static let recentDocumentsDidClear = Notification.Name("MarkdownDocumentController.recentDocumentsDidClear")

    override func clearRecentDocuments(_ sender: Any?) {
        super.clearRecentDocuments(sender)
        NotificationCenter.default.post(name: Self.recentDocumentsDidClear, object: self)
    }

    private static let markdownFileExtensions = ["md", "markdown", "mdown", "mdx", "txt"]

    override func beginOpenPanel(
        _ openPanel: NSOpenPanel,
        forTypes inTypes: [String]?
    ) async -> Int {
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = true
        openPanel.message = NSLocalizedString(
            "Choose a Markdown file or folder",
            comment: "Open panel prompt"
        )
        openPanel.allowedContentTypes = Self.markdownFileExtensions
            .compactMap { UTType(filenameExtension: $0) }
        return await super.beginOpenPanel(openPanel, forTypes: inTypes)
    }

    override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void
    ) {
        let appDelegate = NSApp.delegate as? AppDelegate
        if url.isExistingDirectory, let appDelegate {
            appDelegate.openFolder(url)
            completionHandler(nil, false, nil)
            return
        }
        appDelegate?.documentOpenDidStart()

        super.openDocument(
            withContentsOf: url,
            display: displayDocument,
            completionHandler: completionHandler
        )
    }

    /// Every way a document opens ends here, so the start page goes away
    /// whatever opened it.
    override func addDocument(_ document: NSDocument) {
        super.addDocument(document)
        StartWindowController.shared.dismiss()
    }

    override func openUntitledDocumentAndDisplay(_ displayDocument: Bool) throws -> NSDocument {
        let document = try super.openUntitledDocumentAndDisplay(displayDocument)
        if displayDocument {
            (document.windowControllers.first as? DocumentWindowController)?
                .enterEditMode(autofocus: true)
        }
        return document
    }
}
