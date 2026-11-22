//
//  FileURLHelpers.swift
//  md-preview
//

import Foundation

extension URL {
    nonisolated var isExistingDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// A child of this folder named `base` (plus `ext`), or `base 2`,
    /// `base 3`, … when that name is taken. No extension makes a folder URL.
    nonisolated func uniqueChild(named base: String, extension ext: String?) -> URL {
        func url(_ name: String) -> URL {
            guard let ext, !ext.isEmpty else { return appending(path: name, directoryHint: .isDirectory) }
            return appending(path: "\(name).\(ext)")
        }
        var candidate = url(base)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url("\(base) \(number)")
            number += 1
        }
        return candidate
    }

    nonisolated func isDescendantOrSame(of other: URL) -> Bool {
        let mine = standardizedFileURL.path
        let root = other.standardizedFileURL.path
        return mine == root || mine.hasPrefix(root + "/")
    }
}
