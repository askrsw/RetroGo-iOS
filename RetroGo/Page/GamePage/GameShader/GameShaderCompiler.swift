//
//  GameShaderCompiler.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/23.
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
import RACoordinator
import os

/// Serializes user-requested compilation. Consumers of the same source can cancel independently.
@MainActor
final class GameShaderCompileQueue {
    private final class Job {
        let source: URL
        var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]

        init(_ source: URL) { self.source = source }
    }

    private let operation: (URL) async throws -> Void
    private var pending: [Job] = []
    private var running: Job?

    init(operation: @escaping (URL) async throws -> Void) { self.operation = operation }

    func prepare(_ source: URL) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                let job: Job
                if let existing = self.job(for: source) {
                    job = existing
                } else {
                    job = Job(source)
                    pending.append(job)
                }
                job.waiters[id] = continuation
                pump()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(source, id: id) }
        }
    }

    private func job(for source: URL) -> Job? {
        if running?.source == source { return running }
        return pending.first { $0.source == source }
    }

    private func cancel(_ source: URL, id: UUID) {
        guard let job = job(for: source) else { return }
        job.waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
        if job.waiters.isEmpty { pending.removeAll { $0 === job } }
    }

    private func pump() {
        guard running == nil, !pending.isEmpty else { return }
        let job = pending.removeFirst()
        running = job
        Task {
            let result: Result<Void, Error>
            do { try await operation(job.source); result = .success(()) }
            catch { result = .failure(error) }
            running = nil
            let waiters = job.waiters.values
            job.waiters.removeAll()
            for waiter in waiters { waiter.resume(with: result) }
            pump()
        }
    }
}

/// Native compiler recursion must not use the cooperative executor's small worker stack.
enum GameShaderCompileWorker {
    static let stackSize = 8 * 1024 * 1024

    static func run(priority: TaskPriority, operation: @escaping @Sendable () throws -> Void) async throws {
        try await result(priority: priority, operation: operation)
    }

    static func result<Value: Sendable>(priority: TaskPriority, operation: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
            let thread = Thread {
                autoreleasepool {
                    do { continuation.resume(returning: try operation()) }
                    catch { continuation.resume(throwing: error) }
                }
            }
            thread.name = "RetroGo.ShaderCompiler"
            thread.stackSize = stackSize
            thread.qualityOfService = priority == .userInitiated ? .userInitiated : .utility
            thread.start()
        }
    }
}

@MainActor
final class GameShaderCompiler {
    static let shared = GameShaderCompiler()
    static let cacheDidChange = Notification.Name("GameShaderCacheDidChange")
    private let folder: URL
    private let queue: GameShaderCompileQueue

    private init() {
        let config = AppConfig.shared
        let folder = URL(fileURLWithPath: config.shaderCacheFolder, isDirectory: true)
        let limit = Int64(config.shaderCacheByteLimit)
        self.folder = folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var cacheFolder = folder
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try cacheFolder.setResourceValues(values)
            RetroArchX.configureShaderCacheDirectory(folder.path)
        } catch { RetroGoLogger.game.error("Failed to initialize Shader compilation cache: \(error)") }
        queue = GameShaderCompileQueue { source in
            try await GameShaderCompileWorker.run(priority: .userInitiated) {
                guard let info = RetroArchX.prepareShaderCacheSource(atPath: source.path),
                      let path = info["path"] as? String else { throw GameShaderError.prepare }
                let compiledFile = URL(fileURLWithPath: path)
                let fm = FileManager.default
                try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: path)
                let files = Self.cacheFiles(in: folder)
                var bytes = files.reduce(Int64(0)) { $0 + $1.size }
                for file in files.sorted(by: { $0.modified < $1.modified }) where bytes > limit && file.url != compiledFile {
                    do {
                        try fm.removeItem(at: file.url)
                        bytes -= file.size
                    } catch { RetroGoLogger.game.error("Shader cache eviction failed: \(error)") }
                }
            }
        }
        let retiredResources = [
            URL(fileURLWithPath: config.shaderFolder, isDirectory: true).appendingPathComponent("library", isDirectory: true),
            folder.appendingPathComponent("index.json"),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
        if !retiredResources.isEmpty {
            Task.detached(priority: .utility) {
                for url in retiredResources {
                    do { try FileManager.default.removeItem(at: url) }
                    catch { RetroGoLogger.game.error("Failed to remove retired Shader resources: \(error)") }
                }
            }
        }
    }

    func prepare(_ preset: GameShaderPreset, compile: Bool) async throws -> [GameShaderParameter] {
        let (parameters, sources) = try await Task.detached(priority: .userInitiated) {
            let parameters = try GameShaderCatalog.parameters(for: preset)
            let sources = compile ? try GameShaderCatalog.sourcePaths(for: preset) : []
            return (parameters, sources)
        }.value
        try Task.checkCancellation()
        if compile {
            defer { NotificationCenter.default.post(name: Self.cacheDidChange, object: nil) }
            for source in sources {
                try await queue.prepare(source)
                try Task.checkCancellation()
            }
        }
        return parameters
    }

    func cacheUsage() async -> Int64 {
        await Task.detached(priority: .utility) { [folder] in
            Self.cacheFiles(in: folder).reduce(0) { $0 + $1.size }
        }.value
    }

    private nonisolated static func cacheFiles(in folder: URL) -> [(url: URL, size: Int64, modified: Date)] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))) ?? []
        return urls.compactMap { url in
            guard url.pathExtension == "spvc", let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, let size = values.fileSize else { return nil }
            return (url, Int64(size), values.contentModificationDate ?? .distantPast)
        }
    }
}
