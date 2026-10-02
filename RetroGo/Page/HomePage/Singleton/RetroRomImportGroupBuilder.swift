//
//  RetroRomImportGroupBuilder.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/4.
//  Copyright © 2026 haharsw. All rights reserved.
//
//  ---------------------------------------------------------------------------------
//  This file is part of RetroGo.
//  ---------------------------------------------------------------------------------
//
//  RetroGo is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  RetroGo is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import UIKit
import ObjcHelper

final class RetroRomImportGroupBuilder {
    struct SourceFile {
        let relativePath: String
        let url: URL
        let fileSize: Int
        /// True for files the builder wrote itself (e.g. a synthesized multi-disc m3u).
        /// `relativePath` is then virtual: copy from `url`, not from the import source.
        let isGenerated: Bool

        init(relativePath: String, url: URL, fileSize: Int, isGenerated: Bool = false) {
            self.relativePath = RetroRomImportGroupBuilder.normalize(relativePath)
            self.url = url
            self.fileSize = fileSize
            self.isGenerated = isGenerated
        }

        init(relativePath: String, url: URL) throws {
            let normalizedPath = RetroRomImportGroupBuilder.normalize(relativePath)
            let resources = try url.resourceValues(forKeys: [.fileSizeKey])
            self.relativePath = normalizedPath
            self.url = url
            self.fileSize = resources.fileSize ?? 0
            self.isGenerated = false
        }

        func sha256() throws -> String {
            let shouldStopAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try (url as NSURL).computeSHA256String()
        }

        func crc32() throws -> String {
            let shouldStopAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try (url as NSURL).computeCRC32String()
        }
    }

    enum GroupMatchMode {
        case exact
        case caseInsensitive
        case cueBaseNameFallback
        case mixed
    }

    struct Group {
        let type: RetroRomFileGroupType
        let entryPath: String
        let memberPaths: [String]
        let matchMode: GroupMatchMode
    }

    struct IncompleteGroup {
        let type: RetroRomFileGroupType
        let entryPath: String
        let missingPaths: [String]
    }

    struct AnalysisResult {
        let groups: [Group]
        let incompleteGroups: [IncompleteGroup]
        let map: [String: SourceFile]
    }

    enum BuildError: Error {
        case keyCreationFailed
        case missingEntryFile(path: String)
        case missingMemberFile(path: String)
        case duplicatedRelativePath(path: String)
    }

    unowned let indicatorView: RetroRomActivityView
    /// Holds files synthesized during analysis; removed by `cleanupGeneratedFiles()`.
    private var generatedDirectory: URL?

    init(indicatorView: RetroRomActivityView) {
        self.indicatorView = indicatorView
    }

    deinit {
        cleanupGeneratedFiles()
    }

    func cleanupGeneratedFiles() {
        guard let generatedDirectory else { return }
        try? FileManager.default.removeItem(at: generatedDirectory)
        self.generatedDirectory = nil
    }

    func buildGroups(from files: [SourceFile]) throws -> [Group] {
        try buildGroups(from: files, selectedRelativePaths: nil)
    }

    func buildGroups(from files: [SourceFile], selectedRelativePaths: Set<String>?) throws -> [Group] {
        try analyzeGroups(from: files, selectedRelativePaths: selectedRelativePaths).groups
    }

    func analyzeGroups(from files: [SourceFile], selectedRelativePaths: Set<String>? = nil) throws -> AnalysisResult {
        let map = try makeFileMap(files)
        let orderedPaths = files.map(\.relativePath)
        let normalizedSelected = selectedRelativePaths?.map { Self.normalize($0) }
        let analysis = try buildAllGroups(fileMap: map, orderedPaths: orderedPaths)

        guard let normalizedSelected, !normalizedSelected.isEmpty else {
            return analysis
        }

        let selectedSet = Set(normalizedSelected)
        let groups = analysis.groups.filter { group in
            !selectedSet.isDisjoint(with: Set(group.memberPaths))
        }
        let incompleteGroups = analysis.incompleteGroups.filter { group in
            selectedSet.contains(group.entryPath)
        }
        return AnalysisResult(groups: groups, incompleteGroups: incompleteGroups, map: analysis.map)
    }

    func buildFileItems(groups: [Group], map: [String: SourceFile], parent: String, createAt: Date = Date(), updateAt: Date = Date(), keyProvider: () -> String?) throws -> [RetroRomFileItem] {
        var items: [RetroRomFileItem] = []
        items.reserveCapacity(groups.count)

        for group in groups {
            let format = Bundle.localizedString(forKey: "homepage_import_group_checking")
            let message = String(format: format, group.entryPath)
            showProgress(message: message)
            guard let key = keyProvider() else {
                throw BuildError.keyCreationFailed
            }

            let subItems = try buildSubItems(group: group, key: key, fileMap: map)
            let totalFileSize = subItems.reduce(0) { $0 + $1.fileSize }
            guard let entrySubItem = subItems.first(where: { $0.rawName == group.entryPath }) else {
                throw BuildError.missingEntryFile(path: group.entryPath)
            }
            let gameSHA256 = try contentSHA256(for: group, entrySubItem: entrySubItem, subItems: subItems)
            let gameCRC32  = try contentCRC32(for: group, entrySubItem: entrySubItem, subItems: subItems)
            let item = RetroRomFileItem(
                key: key,
                rawName: group.entryPath,
                parent: parent,
                createAt: createAt,
                updateAt: updateAt,
                fileSize: totalFileSize,
                sha256: gameSHA256,
                crc32: gameCRC32,
                fileGroupType: group.type,
                subItems: subItems
            )
            items.append(item)
        }

        return items
    }
}

extension RetroRomImportGroupBuilder {
    static func normalize(_ path: String) -> String {
        let replaced = path.replacingOccurrences(of: "\\", with: "/")
        let components = replaced.split(separator: "/").filter { $0 != "." && !$0.isEmpty }
        return components.joined(separator: "/")
    }

    func makeFileMap(_ files: [SourceFile]) throws -> [String: SourceFile] {
        var map: [String: SourceFile] = [:]
        map.reserveCapacity(files.count)
        for file in files {
            if map[file.relativePath] != nil {
                throw BuildError.duplicatedRelativePath(path: file.relativePath)
            }
            map[file.relativePath] = file
        }
        return map
    }

    func buildAllGroups(fileMap inputFileMap: [String: SourceFile], orderedPaths: [String]) throws -> AnalysisResult {
        var fileMap = inputFileMap
        var consumed = Set<String>()
        var groups: [Group] = []
        var incompleteGroups: [IncompleteGroup] = []
        let orderIndex = Dictionary(uniqueKeysWithValues: orderedPaths.enumerated().map { ($1, $0) })

        let descriptorPaths = orderedPaths.filter { descriptorType(for: fileExtension(of: $0)) != nil }
            .sorted { lhs, rhs in
                let lhsPriority = descriptorPriority(for: fileExtension(of: lhs))
                let rhsPriority = descriptorPriority(for: fileExtension(of: rhs))
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                let lhsIndex = orderIndex[lhs] ?? .max
                let rhsIndex = orderIndex[rhs] ?? .max
                return lhsIndex < rhsIndex
            }

        for path in descriptorPaths {
            if consumed.contains(path) {
                continue
            }

            let format = Bundle.localizedString(forKey: "homepage_import_file_checking")
            let message = String(format: format, path)
            showProgress(message: message)
            let ext = fileExtension(of: path)
            if let type = descriptorType(for: ext), let resolved = try resolveMembers(for: path, type: type, fileMap: fileMap) {
                let orderedMembers = uniqueOrdered([path] + resolved.memberPaths).filter { fileMap[$0] != nil }
                consumed.formUnion(orderedMembers)
                if resolved.missingPaths.isEmpty {
                    groups.append(Group(type: type, entryPath: path, memberPaths: orderedMembers, matchMode: resolved.matchMode))
                } else {
                    incompleteGroups.append(IncompleteGroup(type: type, entryPath: path, missingPaths: resolved.missingPaths))
                }
            }
        }

        for path in orderedPaths {
            if consumed.contains(path) {
                continue
            }
            consumed.insert(path)
            if isPotentialMultiFileComponent(path) {
                incompleteGroups.append(IncompleteGroup(type: .single, entryPath: path, missingPaths: []))
            } else {
                groups.append(Group(type: .single, entryPath: path, memberPaths: [path], matchMode: .exact))
            }
        }

        groups = try mergeMultiDiscGroups(groups, fileMap: &fileMap)
        return AnalysisResult(groups: groups, incompleteGroups: incompleteGroups, map: fileMap)
    }

    func descriptorPriority(for ext: String) -> Int {
        switch ext {
        case "m3u":
            return 0
        case "cue", "gdi", "mds", "ccd":
            return 1
        default:
            return 2
        }
    }

    struct ResolvedMembers {
        let memberPaths: [String]
        let matchMode: GroupMatchMode
        let missingPaths: [String]
    }

    func buildSubItems(group: Group, key: String, fileMap: [String: SourceFile]) throws -> [RetroRomFileSubItem] {
        var subItems: [RetroRomFileSubItem] = []
        subItems.reserveCapacity(group.memberPaths.count)

        for (index, path) in group.memberPaths.enumerated() {
            guard let file = fileMap[path] else {
                throw BuildError.missingMemberFile(path: path)
            }
            let role = subRole(for: path, entryPath: group.entryPath, groupType: group.type)
            let item = RetroRomFileSubItem(
                key: key,
                rawName: path,
                fileRole: role,
                sha256: try file.sha256(),
                crc32: try file.crc32(),
                fileSize: file.fileSize,
                sortIndex: index
            )
            subItems.append(item)
        }

        return subItems
    }

    func descriptorType(for ext: String) -> RetroRomFileGroupType? {
        switch ext {
        case "cue":
            return .cue
        case "mds":
            return .mds
        case "m3u":
            return .m3u
        case "gdi":
            return .gdi
        case "ccd":
            return .ccd
        default:
            return nil
        }
    }

    func resolveMembers(for entryPath: String, type: RetroRomFileGroupType, fileMap: [String: SourceFile]) throws -> ResolvedMembers? {
        switch type {
        case .cue:
            return try parseCueMembers(for: entryPath, fileMap: fileMap)
        case .mds:
            let members = parseSiblingMembers(for: entryPath, extensions: ["mdf", "iso"], fileMap: fileMap)
            let missingPaths = members.isEmpty ? [siblingPath(for: entryPath, ext: "mdf")] : []
            return ResolvedMembers(memberPaths: members, matchMode: .exact, missingPaths: missingPaths)
        case .m3u:
            return try parseM3UMembers(for: entryPath, fileMap: fileMap)
        case .gdi:
            return try parseGDIMembers(for: entryPath, fileMap: fileMap)
        case .ccd:
            let imgMembers = parseSiblingMembers(for: entryPath, extensions: ["img"], fileMap: fileMap)
            let subMembers = parseSiblingMembers(for: entryPath, extensions: ["sub"], fileMap: fileMap)
            let members = uniqueOrdered(imgMembers + subMembers)
            let missingPaths = imgMembers.isEmpty ? [siblingPath(for: entryPath, ext: "img")] : []
            return ResolvedMembers(memberPaths: members, matchMode: .exact, missingPaths: missingPaths)
        case .single:
            return nil
        }
    }

    func parseCueMembers(for entryPath: String, fileMap: [String: SourceFile]) throws -> ResolvedMembers {
        guard let file = fileMap[entryPath] else {
            throw BuildError.missingEntryFile(path: entryPath)
        }
        let content = try readTextFile(at: file.url)
        let directory = parentDirectory(of: entryPath)
        let cueBaseName = (entryPath as NSString).deletingPathExtension
        var members: [String] = []
        var modes: [GroupMatchMode] = []
        var missingPaths: [String] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.uppercased().hasPrefix("FILE ") else {
                continue
            }
            if let reference = extractQuotedValue(from: trimmed) ?? extractCueFallbackReference(from: trimmed) {
                if let resolved = resolveCueReference(reference, directory: directory, cueBaseName: cueBaseName, fileMap: fileMap) {
                    members.append(resolved.path)
                    modes.append(resolved.mode)
                } else {
                    missingPaths.append(join(directory: directory, relativePath: reference))
                }
            }
        }
        return ResolvedMembers(memberPaths: uniqueOrdered(members), matchMode: mergeMatchModes(modes), missingPaths: uniqueOrdered(missingPaths))
    }

    func parseGDIMembers(for entryPath: String, fileMap: [String: SourceFile]) throws -> ResolvedMembers {
        guard let file = fileMap[entryPath] else {
            throw BuildError.missingEntryFile(path: entryPath)
        }
        let content = try readTextFile(at: file.url)
        let directory = parentDirectory(of: entryPath)
        var members: [String] = []
        var missingPaths: [String] = []
        for line in content.components(separatedBy: .newlines).dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            let tokens = gdiTokens(from: trimmed)
            guard tokens.count >= 5 else {
                continue
            }
            let memberPath = join(directory: directory, relativePath: tokens[4])
            if fileMap[memberPath] != nil {
                members.append(memberPath)
            } else {
                missingPaths.append(memberPath)
            }
        }
        return ResolvedMembers(memberPaths: uniqueOrdered(members), matchMode: .exact, missingPaths: uniqueOrdered(missingPaths))
    }

    func parseM3UMembers(for entryPath: String, fileMap: [String: SourceFile]) throws -> ResolvedMembers {
        guard let file = fileMap[entryPath] else {
            throw BuildError.missingEntryFile(path: entryPath)
        }
        let content = try readTextFile(at: file.url)
        let directory = parentDirectory(of: entryPath)
        var members: [String] = []
        var modes: [GroupMatchMode] = []
        var missingPaths: [String] = []
        var visited = Set<String>()

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            let childPath = join(directory: directory, relativePath: trimmed)
            if fileMap[childPath] != nil {
                members.append(childPath)
                modes.append(.exact)
                let nested = try expandNestedMembers(for: childPath, fileMap: fileMap, visited: &visited)
                members.append(contentsOf: nested.memberPaths)
                modes.append(nested.matchMode)
                missingPaths.append(contentsOf: nested.missingPaths)
            } else {
                missingPaths.append(childPath)
            }
        }

        return ResolvedMembers(memberPaths: uniqueOrdered(members), matchMode: mergeMatchModes(modes), missingPaths: uniqueOrdered(missingPaths))
    }

    func expandNestedMembers(for path: String, fileMap: [String: SourceFile], visited: inout Set<String>) throws -> ResolvedMembers {
        if visited.contains(path) {
            return ResolvedMembers(memberPaths: [], matchMode: .exact, missingPaths: [])
        }
        visited.insert(path)

        let ext = fileExtension(of: path)
        guard let type = descriptorType(for: ext), type != .m3u else {
            return ResolvedMembers(memberPaths: [], matchMode: .exact, missingPaths: [])
        }
        return try resolveMembers(for: path, type: type, fileMap: fileMap) ?? ResolvedMembers(memberPaths: [], matchMode: .exact, missingPaths: [])
    }

    func parseSiblingMembers(for entryPath: String, extensions: [String], fileMap: [String: SourceFile]) -> [String] {
        let prefix = (entryPath as NSString).deletingPathExtension
        var members: [String] = []
        for ext in extensions {
            let candidate = prefix + "." + ext
            if fileMap[candidate] != nil {
                members.append(candidate)
            }
            let upperCandidate = prefix + "." + ext.uppercased()
            if upperCandidate != candidate, fileMap[upperCandidate] != nil {
                members.append(upperCandidate)
            }
        }
        return uniqueOrdered(members)
    }

    func siblingPath(for entryPath: String, ext: String) -> String {
        (entryPath as NSString).deletingPathExtension + "." + ext
    }

    func subRole(for path: String, entryPath: String, groupType: RetroRomFileGroupType) -> RetroRomFileSubRole {
        if path == entryPath {
            return .entry
        }

        let ext = fileExtension(of: path)
        switch groupType {
        case .m3u, .cue, .gdi, .mds, .ccd:
            if ["m3u", "cue", "gdi", "mds", "ccd"].contains(ext) {
                return .descriptor
            }
            return .resource
        case .single:
            return .entry
        }
    }

    func fileExtension(of path: String) -> String {
        (path as NSString).pathExtension.lowercased()
    }

    func parentDirectory(of path: String) -> String {
        let directory = (path as NSString).deletingLastPathComponent
        return Self.normalize(directory)
    }

    func join(directory: String, relativePath: String) -> String {
        let normalizedRelative = Self.normalize(relativePath)
        if directory.isEmpty {
            return normalizedRelative
        }
        if normalizedRelative.isEmpty {
            return directory
        }
        return Self.normalize(directory + "/" + normalizedRelative)
    }

    func resolveCueReference(_ reference: String, directory: String, cueBaseName: String, fileMap: [String: SourceFile]) -> (path: String, mode: GroupMatchMode)? {
        let directPath = join(directory: directory, relativePath: reference)
        if fileMap[directPath] != nil {
            return (directPath, .exact)
        }

        if let matched = findCaseInsensitiveMatch(for: directPath, fileMap: fileMap) {
            return (matched, .caseInsensitive)
        }

        let referenceExt = fileExtension(of: reference)
        if !referenceExt.isEmpty {
            let sameExtCandidate = cueBaseName + "." + referenceExt
            if fileMap[sameExtCandidate] != nil {
                return (sameExtCandidate, .cueBaseNameFallback)
            }
            if let matched = findCaseInsensitiveMatch(for: sameExtCandidate, fileMap: fileMap) {
                return (matched, .cueBaseNameFallback)
            }
        }

        let fallbackExtensions = ["bin", "iso", "img", "wav", "mp3", "flac", "ape"]
        var candidates: [String] = []
        for ext in fallbackExtensions {
            let candidate = cueBaseName + "." + ext
            if fileMap[candidate] != nil {
                candidates.append(candidate)
                continue
            }
            if let matched = findCaseInsensitiveMatch(for: candidate, fileMap: fileMap) {
                candidates.append(matched)
            }
        }

        let uniqueCandidates = uniqueOrdered(candidates)
        if uniqueCandidates.count == 1, let first = uniqueCandidates.first {
            return (first, .cueBaseNameFallback)
        }

        return nil
    }

    func findCaseInsensitiveMatch(for path: String, fileMap: [String: SourceFile]) -> String? {
        let lowercased = path.lowercased()
        return fileMap.keys.first(where: { $0.lowercased() == lowercased })
    }

    func mergeMatchModes(_ modes: [GroupMatchMode]) -> GroupMatchMode {
        let filtered = modes.filter {
            switch $0 {
            case .exact, .caseInsensitive, .cueBaseNameFallback:
                return true
            case .mixed:
                return false
            }
        }
        guard let first = filtered.first else {
            return .exact
        }
        if filtered.dropFirst().allSatisfy({ $0 == first }) {
            return first
        }
        return .mixed
    }

    func extractQuotedValue(from line: String) -> String? {
        guard let firstQuote = line.firstIndex(of: "\"") else {
            return nil
        }
        let afterFirst = line.index(after: firstQuote)
        guard let secondQuote = line[afterFirst...].firstIndex(of: "\"") else {
            return nil
        }
        return String(line[afterFirst..<secondQuote])
    }

    func extractCueFallbackReference(from line: String) -> String? {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard tokens.count >= 2 else {
            return nil
        }
        return tokens[1]
    }

    func gdiTokens(from line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var insideQuote = false

        for char in line {
            if char == "\"" {
                insideQuote.toggle()
                continue
            }
            if !insideQuote && (char == " " || char == "\t") {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }
            current.append(char)
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    func uniqueOrdered(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for path in paths {
            if seen.insert(path).inserted {
                result.append(path)
            }
        }
        return result
    }

    func contentSHA256(for group: Group, entrySubItem: RetroRomFileSubItem, subItems: [RetroRomFileSubItem]) throws -> String {
        if group.type == .single {
            return entrySubItem.sha256
        }

        let payload = subItems
            .sorted { lhs, rhs in
                lhs.rawName.localizedCaseInsensitiveCompare(rhs.rawName) == .orderedAscending
            }
            .map { "\($0.rawName)|\($0.sha256)" }
            .joined(separator: "\n")

        guard let data = payload.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return (data as NSData).sha256Hash()
    }

    func contentCRC32(for group: Group, entrySubItem: RetroRomFileSubItem, subItems: [RetroRomFileSubItem]) throws -> String? {
        if group.type == .single {
            return entrySubItem.crc32
        }

        let sortedItems = subItems.sorted { lhs, rhs in
            lhs.rawName.localizedCaseInsensitiveCompare(rhs.rawName) == .orderedAscending
        }

        guard sortedItems.allSatisfy({ $0.crc32?.isEmpty == false }) else {
            return nil
        }

        let payload = sortedItems
            .map { "\($0.rawName)|\($0.crc32!)" }
            .joined(separator: "\n")

        guard let data = payload.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }

        return (data as NSData).crc32Hash()
    }

    func isPotentialMultiFileComponent(_ path: String) -> Bool {
        let ext = fileExtension(of: path)
        return ["cue", "mds", "m3u", "gdi", "ccd", "sub", "mdf", "wav", "mp3", "flac", "ape"].contains(ext)
    }

    func readTextFile(at url: URL) throws -> String {
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        for encoding in textEncodings() {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    func textEncodings() -> [String.Encoding] {
        var encodings: [String.Encoding] = [.utf8]

        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue)
        ))

        encodings.append(.unicode)
        encodings.append(.utf16LittleEndian)
        encodings.append(.utf16BigEndian)
        encodings.append(.shiftJIS)
        encodings.append(gb18030)
        encodings.append(big5)
        encodings.append(.isoLatin1)
        encodings.append(.ascii)

        var seen = Set<String.Encoding>()
        return encodings.filter { seen.insert($0).inserted }
    }

    func showProgress(message: String) {
        indicatorView.activeMessage(message, title: Bundle.localizedString(forKey: "homepage_import_importing"))
    }
}

// MARK: - Multi-disc merge

extension RetroRomImportGroupBuilder {
    /// Single-file disc images that can be one disc of a multi-disc game.
    private static let singleDiscExtensions: Set<String> = ["chd", "iso", "cso", "pbp"]

    private static let discNumberRegex = try! NSRegularExpression(
        pattern: #"\(\s*(?:disc|disk|cd)\s*(\d+)(?:\s*of\s*(\d+))?\s*\)"#,
        options: [.caseInsensitive]
    )

    struct DiscTag {
        let title: String
        let number: Int
        let total: Int?
    }

    /// Parses "(Disc N)", "(Disk N)", "(CD N)" or "(Disc N of M)" from a file name.
    /// Returns nil unless the name carries exactly one such tag.
    static func discTag(forFileName fileName: String) -> DiscTag? {
        let baseName = (fileName as NSString).deletingPathExtension
        let range = NSRange(baseName.startIndex..., in: baseName)
        let matches = discNumberRegex.matches(in: baseName, range: range)
        guard matches.count == 1, let match = matches.first,
              let tagRange = Range(match.range, in: baseName),
              let numberRange = Range(match.range(at: 1), in: baseName),
              let number = Int(baseName[numberRange]) else {
            return nil
        }
        var total: Int?
        if let totalRange = Range(match.range(at: 2), in: baseName) {
            total = Int(baseName[totalRange])
        }
        var title = baseName
        title.removeSubrange(tagRange)
        title = title.split(whereSeparator: { $0 == " " }).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            return nil
        }
        return DiscTag(title: title, number: number, total: total)
    }

    /// Combines complete per-disc groups of one game into a synthesized m3u group.
    /// Groups that do not form a clean 1...N disc set are returned untouched.
    func mergeMultiDiscGroups(_ groups: [Group], fileMap: inout [String: SourceFile]) throws -> [Group] {
        var buckets: [String: [(index: Int, tag: DiscTag)]] = [:]
        var bucketOrder: [String] = []
        for (index, group) in groups.enumerated() {
            guard isMergeableDisc(group), let tag = discTag(for: group) else {
                continue
            }
            if buckets[tag.title] == nil {
                bucketOrder.append(tag.title)
            }
            buckets[tag.title, default: []].append((index, tag))
        }

        var replacements: [Int: Group] = [:]
        var removed = Set<Int>()
        for title in bucketOrder {
            guard let discs = buckets[title], discs.count >= 2 else {
                continue
            }
            let sorted = discs.sorted { $0.tag.number < $1.tag.number }
            guard sorted.enumerated().allSatisfy({ $0.offset + 1 == $0.element.tag.number }),
                  sorted.allSatisfy({ $0.tag.total == nil || $0.tag.total == sorted.count }) else {
                NSLog("[Import] Discs of %@ are not a contiguous set, imported separately", title)
                continue
            }
            let discGroups = sorted.map { groups[$0.index] }
            guard let merged = try makeMultiDiscGroup(title: title, discGroups: discGroups, fileMap: &fileMap) else {
                continue
            }
            replacements[sorted.map(\.index).min()!] = merged
            removed.formUnion(sorted.map(\.index))
        }

        guard !replacements.isEmpty else {
            return groups
        }
        var result: [Group] = []
        for (index, group) in groups.enumerated() {
            if let merged = replacements[index] {
                result.append(merged)
            } else if !removed.contains(index) {
                result.append(group)
            }
        }
        return result
    }

    /// Disc tag from the entry file name, falling back to the data files of a
    /// descriptor group (e.g. "FF7CD1.cue" referencing "... (Disc 1).bin") when
    /// every data file carries the same tag.
    private func discTag(for group: Group) -> DiscTag? {
        if let tag = Self.discTag(forFileName: (group.entryPath as NSString).lastPathComponent) {
            return tag
        }
        guard group.type != .single else {
            return nil
        }
        let descriptorExtensions: Set<String> = ["m3u", "cue", "gdi", "mds", "ccd"]
        let resources = group.memberPaths.filter { !descriptorExtensions.contains(fileExtension(of: $0)) }
        let tags = resources.map { Self.discTag(forFileName: ($0 as NSString).lastPathComponent) }
        guard let first = tags.first ?? nil,
              tags.allSatisfy({ $0?.title == first.title && $0?.number == first.number && $0?.total == first.total }) else {
            return nil
        }
        return first
    }

    private func isMergeableDisc(_ group: Group) -> Bool {
        switch group.type {
        case .cue, .gdi, .mds, .ccd:
            return true
        case .single:
            return Self.singleDiscExtensions.contains(fileExtension(of: group.entryPath))
        case .m3u:
            return false
        }
    }

    private func makeMultiDiscGroup(title: String, discGroups: [Group], fileMap: inout [String: SourceFile]) throws -> Group? {
        let directory = commonParentDirectory(of: discGroups.map(\.entryPath))
        let playlistPath = join(directory: directory, relativePath: title + ".m3u")
        if fileMap[playlistPath] != nil || findCaseInsensitiveMatch(for: playlistPath, fileMap: fileMap) != nil {
            NSLog("[Import] %@ already exists, discs of %@ imported separately", playlistPath, title)
            return nil
        }

        let lines = discGroups.map { relativePath(of: $0.entryPath, fromDirectory: directory) }
        let content = lines.joined(separator: "\n") + "\n"
        guard let data = content.data(using: .utf8) else {
            return nil
        }
        let url = try makeGeneratedFileURL(fileName: title + ".m3u")
        try data.write(to: url, options: .atomic)
        fileMap[playlistPath] = SourceFile(relativePath: playlistPath, url: url, fileSize: data.count, isGenerated: true)

        let members = uniqueOrdered([playlistPath] + discGroups.flatMap(\.memberPaths))
        let matchMode = mergeMatchModes(discGroups.map(\.matchMode))
        NSLog("[Import] Merged %d discs into %@", discGroups.count, playlistPath)
        return Group(type: .m3u, entryPath: playlistPath, memberPaths: members, matchMode: matchMode)
    }

    private func makeGeneratedFileURL(fileName: String) throws -> URL {
        let directory: URL
        if let generatedDirectory {
            directory = generatedDirectory
        } else {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("RetroGoImport-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            generatedDirectory = directory
        }
        // One subfolder per file keeps equal titles from different buckets apart.
        let fileDirectory = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: fileDirectory, withIntermediateDirectories: true)
        return fileDirectory.appendingPathComponent(fileName)
    }

    private func commonParentDirectory(of paths: [String]) -> String {
        let directories = paths.map { parentDirectory(of: $0).split(separator: "/").map(String.init) }
        guard var shared = directories.first else {
            return ""
        }
        for components in directories.dropFirst() {
            var prefix: [String] = []
            for (lhs, rhs) in zip(shared, components) {
                guard lhs == rhs else { break }
                prefix.append(lhs)
            }
            shared = prefix
        }
        return shared.joined(separator: "/")
    }

    private func relativePath(of path: String, fromDirectory directory: String) -> String {
        guard !directory.isEmpty else {
            return path
        }
        let prefix = directory + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}
