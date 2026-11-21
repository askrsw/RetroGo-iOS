//
//  GameShaderCatalog.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/19.
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

import Foundation
import os

enum GameShaderCatalog {
    struct ImportIssue: Codable {
        let preset: String
        let reason: String
    }
    struct ImportReport: Codable {
        let presets: [String]
        let skipped: [ImportIssue]
        var folderName: String? = nil
        var deletedPresets: Set<String>? = nil
    }
    struct ImportPackage {
        let id: String
        let folderName: String?
        let presets: [GameShaderPreset]
    }
    private struct DependencyError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    private static let reportName = "import-report.json"
    private static let deletedPackagePrefix = ".deleted-"
    private static let deletionQueue = DispatchQueue(label: "RetroGo.ShaderImportDeletion", qos: .utility)
    static var bundleRoot: URL {
        AppConfig.shared.bundledShaderSourceFolder
    }

    static func builtins() throws -> [GameShaderPreset] {
        let url = AppConfig.shared.bundledShaderCatalogURL
        return try JSONDecoder().decode([GameShaderPreset].self, from: Data(contentsOf: url))
    }

    static func root(for preset: GameShaderPreset) -> URL {
        preset.imported ? GameShaderStore.imports : bundleRoot
    }

    static func url(for preset: GameShaderPreset) throws -> URL {
        guard !preset.isLibrary else { throw GameShaderError.resource }
        if preset.imported {
            let (package, relativePath) = try importedPath(for: preset)
            let url = package.appendingPathComponent(relativePath).standardizedFileURL
            let manifest = try importReport(in: package)
            guard contained(url, in: package), FileManager.default.fileExists(atPath: url.path),
                  manifest?.deletedPresets?.contains(relativePath) != true,
                  manifest?.presets.contains(relativePath) != false else { throw GameShaderError.resource }
            return url
        }
        let root = root(for: preset)
        let url = root.appendingPathComponent(preset.path).standardizedFileURL
        guard contained(url, in: root), FileManager.default.fileExists(atPath: url.path) else { throw GameShaderError.resource }
        return url
    }

    static func importedPackages() throws -> [ImportPackage] {
        let root = GameShaderStore.imports.resolvingSymlinksInPath()
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let directories = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys))
        return try directories.compactMap { package in
            let id = package.lastPathComponent
            guard let values = try? package.resourceValues(forKeys: keys),
                  values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            if id.hasPrefix(deletedPackagePrefix), UUID(uuidString: String(id.dropFirst(deletedPackagePrefix.count))) != nil {
                purgeDeletedPackage(package)
                return nil
            }
            guard UUID(uuidString: id) != nil else { return nil }
            let manifest = try importReport(in: package)
            let paths = try manifest?.presets ?? legacyPresetPaths(in: package)
            guard !paths.isEmpty else { return nil }
            let deleted = manifest?.deletedPresets ?? []
            let presets = paths.sorted().compactMap { relative -> GameShaderPreset? in
                let url = package.appendingPathComponent(relative).standardizedFileURL
                guard !deleted.contains(relative), contained(url, in: package), fm.fileExists(atPath: url.path) else { return nil }
                let path = id + "/" + relative
                return GameShaderPreset(id: "import." + path, name: url.deletingPathExtension().lastPathComponent,
                                        path: path, imported: true, parameters: [:])
            }
            let fallback = paths.first?.split(separator: "/").first == "shaders_slang" ? "shaders_slang" : nil
            return ImportPackage(id: id, folderName: manifest?.folderName ?? fallback, presets: presets)
        }
    }

    static func deleteImportedPreset(_ preset: GameShaderPreset) throws {
        let (package, relativePath) = try importedPath(for: preset)
        var report = try importReport(in: package) ?? ImportReport(presets: legacyPresetPaths(in: package), skipped: [])
        guard report.presets.contains(relativePath) else { throw GameShaderError.resource }
        var deleted = report.deletedPresets ?? []
        guard deleted.insert(relativePath).inserted else { return }
        report.deletedPresets = deleted
        try JSONEncoder().encode(report).write(to: package.appendingPathComponent(reportName), options: .atomic)
    }

    static func deleteImportedPackage(_ id: String) throws {
        let package = try importedPackageURL(id)
        let deleted = package.deletingLastPathComponent()
            .appendingPathComponent(deletedPackagePrefix + id, isDirectory: true)
        // Publish removal as one rename. Recursive cleanup can be retried after interruption.
        try FileManager.default.moveItem(at: package, to: deleted)
        purgeDeletedPackage(deleted)
    }

    private static func purgeDeletedPackage(_ url: URL) {
        deletionQueue.async {
            let fm = FileManager.default
            guard fm.fileExists(atPath: url.path) else { return }
            do { try fm.removeItem(at: url) }
            catch { RetroGoLogger.game.error("Failed to clean up deleted Shader folder: \(error)") }
        }
    }

    private static func importedPath(for preset: GameShaderPreset) throws -> (URL, String) {
        let parts = preset.path.split(separator: "/", maxSplits: 1)
        guard preset.imported, parts.count == 2 else { throw GameShaderError.resource }
        return (try importedPackageURL(String(parts[0])), String(parts[1]))
    }

    private static func importedPackageURL(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw GameShaderError.resource }
        let root = GameShaderStore.imports.resolvingSymlinksInPath().standardizedFileURL
        let package = root.appendingPathComponent(id, isDirectory: true)
        guard let values = try? package.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { throw GameShaderError.resource }
        return package
    }

    private static func importReport(in package: URL) throws -> ImportReport? {
        let url = package.appendingPathComponent(reportName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(ImportReport.self, from: Data(contentsOf: url))
    }

    private static func legacyPresetPaths(in package: URL) throws -> [String] {
        let package = package.resolvingSymlinksInPath()
        return try presetURLs(in: package).compactMap { file in
            let url = file.resolvingSymlinksInPath()
            guard contained(url, in: package) else { return nil }
            return String(url.path.dropFirst(package.path.count + 1))
        }
    }

    @discardableResult
    static func importFolder(_ source: URL, progress: (String) -> Void = { _ in }) throws -> ImportReport {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        // File providers and /var aliases may enumerate canonical URLs. Use the same root for slicing paths.
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let fm = FileManager.default
        progress(shaderText("import_scanning"))
        // Reject links before copying; an imported package must be self contained.
        var enumerationError: Error?
        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], errorHandler: { _, error in
            enumerationError = error
            return false
        }) else { throw GameShaderError.unsafeImport }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw GameShaderError.unsafeImport }
            files.append(url)
        }
        if let enumerationError { throw enumerationError }
        let presets = files.filter { $0.pathExtension.lowercased() == "slangp" }.sorted { $0.path < $1.path }
        guard !presets.isEmpty else { throw GameShaderError.unsafeImport }
        var cache: [URL: Result<Void, Error>] = [:]
        var accepted: [String] = []
        var skipped: [ImportIssue] = []
        func relative(_ url: URL) -> String { String(url.resolvingSymlinksInPath().path.dropFirst(source.path.count + 1)) }
        for (index, preset) in presets.enumerated() {
            if index % 20 == 0 || index == presets.count - 1 {
                progress(String(format: shaderText("import_checking"), index + 1, presets.count))
            }
            do {
                try validate(preset, root: source, visited: [], cache: &cache)
                accepted.append(relative(preset))
            } catch {
                skipped.append(ImportIssue(preset: relative(preset), reason: error.localizedDescription))
            }
        }
        let report = ImportReport(presets: accepted, skipped: skipped, folderName: source.lastPathComponent)
        try fm.createDirectory(at: GameShaderStore.imports, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let destination = GameShaderStore.imports.appendingPathComponent(id, isDirectory: true)
        let staging = GameShaderStore.imports.appendingPathComponent("." + id, isDirectory: true)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            let copying = accepted.isEmpty ? [] : files
            for (index, file) in copying.enumerated() {
                let target = staging.appendingPathComponent(relative(file))
                if try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                    try fm.createDirectory(at: target, withIntermediateDirectories: true)
                } else {
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: file, to: target)
                }
                if index % 50 == 0 || index == copying.count - 1 {
                    progress(String(format: shaderText("import_copying"), index + 1, copying.count))
                }
            }
            // Keep original bytes and the complete dependency tree; publish only validated presets.
            try JSONEncoder().encode(report).write(to: staging.appendingPathComponent(reportName), options: .atomic)
            try fm.moveItem(at: staging, to: destination)
        } catch { try? fm.removeItem(at: staging); throw error }
        return report
    }

    private static func presetURLs(in root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { throw GameShaderError.resource }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "slangp" }.sorted { $0.path < $1.path }
    }

    private static func contained(_ url: URL, in root: URL) -> Bool {
        url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/")
    }

    /// Follow preset, shader, include and texture dependencies without leaving the package.
    private static func validate(_ url: URL, root: URL, visited: Set<URL>, cache: inout [URL: Result<Void, Error>]) throws {
        let url = url.resolvingSymlinksInPath().standardizedFileURL
        guard contained(url, in: root) else { throw DependencyError(message: shaderText("import_outside")) }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DependencyError(message: String(format: shaderText("import_missing"), String(url.path.dropFirst(root.path.count + 1))))
        }
        if let cached = cache[url] { return try cached.get() }
        guard !visited.contains(url) else { throw DependencyError(message: shaderText("import_cycle")) }
        guard ["slangp", "slang", "inc", "h"].contains(url.pathExtension.lowercased()) else { return }
        var visited = visited
        visited.insert(url)
        do {
            let text = try readText(url)
            let lines = text.components(separatedBy: .newlines)
            var textureKeys = Set<String>()
            for line in lines {
                let pair = assignment(line)
                if pair?.0 == "textures" { textureKeys.formUnion(pair!.1.components(separatedBy: ";")) }
            }
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                var relative: String?
                if let path = directive(trimmed) {
                    relative = path
                } else if let (key, value) = assignment(trimmed),
                          textureKeys.contains(key) || key.range(of: #"^shader[0-9]+$"#, options: .regularExpression) != nil {
                    relative = value
                }
                if let relative {
                    guard !relative.hasPrefix("/"), !relative.contains("://") else {
                        throw DependencyError(message: shaderText("import_outside"))
                    }
                    try validate(url.deletingLastPathComponent().appendingPathComponent(relative).standardizedFileURL, root: root, visited: visited, cache: &cache)
                }
            }
            cache[url] = .success(())
        } catch {
            cache[url] = .failure(error)
            throw error
        }
    }

    static func parameters(for preset: GameShaderPreset) throws -> [GameShaderParameter] {
        var seen = Set<URL>()
        var definitions: [GameShaderParameter] = []
        var defaults: [String: Double] = [:]
        let root = root(for: preset)
        func read(_ url: URL) throws {
            guard contained(url, in: root), seen.insert(url).inserted else { return }
            let text = try readText(url)
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let pattern = #"^#pragma\s+parameter\s+(\S+)\s+\"([^\"]+)\"\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)(?:\s+([-+0-9.eE]+))?"#
                if let m = matches(pattern, in: trimmed).first, m.count >= 5,
                   let initial = Double(m[2]), let min = Double(m[3]), let max = Double(m[4]), initial.isFinite, min.isFinite, max.isFinite, max > min {
                    let step = m.count > 5 ? Double(m[5]) ?? (max - min) / 100 : (max - min) / 100
                    if !definitions.contains(where: { $0.id == m[0] }) {
                        definitions.append(GameShaderParameter(id: m[0], title: m[1], initial: initial, minimum: min, maximum: max, step: step))
                    }
                }
                if let path = directive(trimmed) {
                    try read(url.deletingLastPathComponent().appendingPathComponent(path).standardizedFileURL)
                } else if let (key, value) = assignment(trimmed) {
                    if key.range(of: #"^shader[0-9]+$"#, options: .regularExpression) != nil {
                        try read(url.deletingLastPathComponent().appendingPathComponent(value).standardizedFileURL)
                    } else if let value = Double(value.trimmingCharacters(in: .whitespaces)), value.isFinite { defaults[key] = value }
                }
            }
        }
        try read(url(for: preset))
        if preset.id == "builtin.rcas" {
            // The upstream settings heading is a dummy parameter with no visual effect.
            definitions.removeAll { $0.id == "RCAS_SETTINGS" }
        }
        return definitions.map {
            GameShaderParameter(id: $0.id, title: $0.title, initial: $0.normalized(defaults[$0.id] ?? $0.initial),
                                minimum: $0.minimum, maximum: $0.maximum, step: $0.step)
        }
    }

    /// Preset/reference files only; source includes are expanded by the native compiler.
    static func sourcePaths(for preset: GameShaderPreset) throws -> [URL] {
        let root = root(for: preset)
        var visited = Set<URL>()
        var sources: [URL] = []
        var seenSources = Set<URL>()
        func read(_ url: URL) throws {
            let url = url.resolvingSymlinksInPath().standardizedFileURL
            guard contained(url, in: root) else { throw GameShaderError.unsafeImport }
            guard visited.insert(url).inserted else { return }
            for line in try readText(url).components(separatedBy: .newlines) {
                let line = line.trimmingCharacters(in: .whitespaces)
                if let path = directive(line) {
                    try read(url.deletingLastPathComponent().appendingPathComponent(path))
                } else if let (key, path) = assignment(line), key.range(of: #"^shader[0-9]+$"#, options: .regularExpression) != nil {
                    let source = url.deletingLastPathComponent().appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
                    guard contained(source, in: root) else { throw GameShaderError.unsafeImport }
                    if seenSources.insert(source).inserted { sources.append(source) }
                }
            }
        }
        try read(url(for: preset))
        return sources
    }


    private static func assignment(_ line: String) -> (String, String)? {
        guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("#"),
              let equal = line.firstIndex(of: "=") else { return nil }
        let key = line[..<equal].trimmingCharacters(in: .whitespaces)
        guard let value = value(String(line[line.index(after: equal)...])) else { return nil }
        return (key, value)
    }

    /// RetroArch's config_file_extract_value accepts both quoted strings and bare tokens.
    private static func value(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\"") {
            let rest = text.dropFirst()
            guard let end = rest.firstIndex(of: "\"") else { return nil }
            return String(rest[..<end])
        }
        let token = text.prefix { !$0.isWhitespace && $0 != "#" }
        return token.isEmpty ? nil : String(token)
    }

    private static func directive(_ line: String) -> String? {
        guard let match = matches(#"^#(?:include|reference)\s+(.+)$"#, in: line).first else { return nil }
        return value(match[0])
    }

    /// Parse legacy byte-oriented sources without rewriting files handed to RetroArch.
    private static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1252)
                ?? String(data: data, encoding: .isoLatin1) else { throw GameShaderError.resource }
        return text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (1..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : ns.substring(with: match.range(at: $0)) }
        }
    }
}
