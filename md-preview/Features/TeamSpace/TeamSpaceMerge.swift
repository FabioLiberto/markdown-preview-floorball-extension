//
//  TeamSpaceMerge.swift
//  md-preview
//
//  A line-based three-way merge, like `git merge-file`: changes to
//  different lines of a file combine, changes to the same lines are a
//  conflict. Floorball diagrams put one element per line, so two people
//  moving different players merge cleanly.
//

import Foundation

nonisolated enum TeamSpaceMerge {

    /// Above this many lines in the changed middle of a file, the merge
    /// gives up and the file is a conflict.
    static let maxDiffCells = 4_000_000

    /// The merged text, or nil when both sides changed the same lines.
    static func merge(base: String, ours: String, theirs: String) -> String? {
        if ours == theirs { return ours }
        if ours == base { return theirs }
        if theirs == base { return ours }
        let baseLines = lines(base), ourLines = lines(ours), theirLines = lines(theirs)
        guard let toOurs = matches(baseLines, ourLines),
              let toTheirs = matches(baseLines, theirLines)
        else { return nil }

        var result: [Substring] = []
        var i = 0, a = 0, b = 0
        while true {
            // The next base line both sides kept.
            var k = i
            while k < baseLines.count, toOurs[k] == nil || toTheirs[k] == nil { k += 1 }
            let endA = k < baseLines.count ? toOurs[k]! : ourLines.count
            let endB = k < baseLines.count ? toTheirs[k]! : theirLines.count

            let baseChunk = baseLines[i..<k], ourChunk = ourLines[a..<endA], theirChunk = theirLines[b..<endB]
            if ourChunk.elementsEqual(baseChunk) {
                result += theirChunk
            } else if theirChunk.elementsEqual(baseChunk) || ourChunk.elementsEqual(theirChunk) {
                result += ourChunk
            } else {
                return nil
            }

            guard k < baseLines.count else { break }
            result.append(baseLines[k])
            i = k + 1; a = endA + 1; b = endB + 1
        }
        return result.joined()
    }

    /// Splits after each newline, so joining gives the text back exactly.
    static func lines(_ text: String) -> [Substring] {
        var lines: [Substring] = []
        var start = text.startIndex
        for index in text.indices where text[index] == "\n" {
            let end = text.index(after: index)
            lines.append(text[start..<end])
            start = end
        }
        if start < text.endIndex { lines.append(text[start...]) }
        return lines
    }

    /// For each line of `old`, its index in `new` when it is part of a
    /// longest common subsequence; nil when the diff would be too large.
    static func matches(_ old: [Substring], _ new: [Substring]) -> [Int?]? {
        var result = [Int?](repeating: nil, count: old.count)
        // The common start and end need no table.
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] {
            result[prefix] = prefix
            prefix += 1
        }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            result[old.count - 1 - suffix] = new.count - 1 - suffix
            suffix += 1
        }
        let n = old.count - prefix - suffix, m = new.count - prefix - suffix
        guard n > 0, m > 0 else { return result }
        guard n * m <= maxDiffCells else { return nil }

        // lengths[x][y]: the LCS length of old[prefix + x...] and new[prefix + y...].
        let width = m + 1
        var lengths = [Int32](repeating: 0, count: (n + 1) * width)
        for x in stride(from: n - 1, through: 0, by: -1) {
            for y in stride(from: m - 1, through: 0, by: -1) {
                lengths[x * width + y] = old[prefix + x] == new[prefix + y]
                    ? lengths[(x + 1) * width + y + 1] + 1
                    : max(lengths[(x + 1) * width + y], lengths[x * width + y + 1])
            }
        }
        var x = 0, y = 0
        while x < n, y < m {
            if old[prefix + x] == new[prefix + y] {
                result[prefix + x] = prefix + y
                x += 1; y += 1
            } else if lengths[(x + 1) * width + y] >= lengths[x * width + y + 1] {
                x += 1
            } else {
                y += 1
            }
        }
        return result
    }
}
