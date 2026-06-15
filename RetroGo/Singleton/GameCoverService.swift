//
//  GameCoverService.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/20.
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
import Kingfisher
import RACoordinator

// ---------------------------------------------------------------------------
// MARK: - GameCoverService
//
// Centralized cover art loader for all surfaces (Discover detail, ROM browser).
//
// Data source: LibRetro Thumbnails CDN — free, no API key, CDN-backed.
//   https://thumbnails.libretro.com/{platform}/Named_Boxarts/
//
// Strategy (same as Manic EMU):
//   1. Fetch the HTML directory listing for the platform to get real filenames.
//   2. Cache the filename list to disk for 7 days.
//   3. Fuzzy-match the game name against the list (Levenshtein similarity ≥ 0.72).
//   4. Load the matched file via Kingfisher (memory + disk image cache).
//
// Threading rule — NOTHING slow runs on the main thread:
//   • Disk cache read  → Task.detached (background)
//   • Network fetch    → Task.detached (background, async suspend)
//   • Levenshtein loop → Task.detached (background)
//   • Kingfisher load  → MainActor (UI only)
// ---------------------------------------------------------------------------

@MainActor
final class GameCoverService {

    // MARK: - Shared instance

    static let shared = GameCoverService()

    private init() {
        loadMatchCacheFromDisk()
    }

    // MARK: - Kingfisher image cache

    private let imageCache: ImageCache = {
        let c = ImageCache(name: "RetroGoGameCovers")
        c.diskStorage.config.sizeLimit        = 200 * 1024 * 1024  // 200 MB
        c.diskStorage.config.expiration       = .days(30)
        c.memoryStorage.config.totalCostLimit =  40 * 1024 * 1024  //  40 MB
        return c
    }()

    // MARK: - File-list in-memory cache (rdbName → [String])
    //
    // Eliminates repeated disk reads for the same platform within a session.
    // The underlying txt files are the persistent store (7-day TTL).

    private var fileListMemoryCache: [String: [String]] = [:]

    // MARK: - Match result cache (imgKey → matched CDN filename)
    //
    // Persists across launches as a JSON file so Levenshtein never runs twice
    // for the same game. Empty-string value = known no-match (negative cache).
    //
    // Format: { "cover|rdbName|gameName": "Contra (USA).png", ... }

    private var matchCache: [String: String] = [:]
    private var matchCachePersistTask: Task<Void, Never>?

    // MARK: - In-flight file-list tasks (rdbName → Task)
    //
    // Prevents duplicate CDN requests when multiple games on the same platform
    // enter the slow path concurrently (both have matchCache miss).
    // Once the task completes its result is stored in fileListMemoryCache and
    // the entry here is removed — future calls use the memory cache directly.

    private var fileListInFlight: [String: Task<[String], Never>] = [:]

    private let matchCacheFile: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("RetroGoCoversMatchCache.json")
    }()

    // MARK: - File-list cache directory (path built on main, I/O done off-main)

    private let fileListCacheDir: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("RetroGoCoversFileLists", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let fileListTTL: TimeInterval = 7 * 24 * 3600   // 7 days

    // MARK: - Public: quick-checks (no I/O)

    /// Returns true if we already know from in-memory state that this game
    /// has no cover art (negative match-cache entry).
    /// Use this BEFORE showing a loading indicator so you can skip it — and
    /// the failure toast — when the result is already certain.
    func isDefinitelyUnavailable(for game: RAGameEntry,
                                 platform: RAPlatformItem) -> Bool {
        isDefinitelyUnavailable(gameName: game.name, rdbName: platform.rdbName)
    }

    func isDefinitelyUnavailable(gameName: String, rdbName: String) -> Bool {
        matchCache[Self.imageCacheKey(gameName: gameName, rdbName: rdbName)] == ""
    }

    /// Returns the cover image synchronously if it is already in the **memory** cache,
    /// nil otherwise. Zero latency — safe to call on the main thread before showing any UI.
    func memoryCachedImage(for game: RAGameEntry, platform: RAPlatformItem) -> UIImage? {
        memoryCachedImage(gameName: game.name, rdbName: platform.rdbName)
    }

    /// Explicit-key variant. Lets callers look up by an arbitrary name (e.g. a group
    /// name shared by all variants) instead of a specific game's name.
    func memoryCachedImage(gameName: String, rdbName: String) -> UIImage? {
        let imgKey = Self.imageCacheKey(gameName: gameName, rdbName: rdbName)
        return imageCache.retrieveImageInMemoryCache(forKey: imgKey, options: nil)
    }

    /// Checks the **memory** cache first (synchronous), then the **disk** cache (async I/O).
    /// Returns the image if found in either layer; nil otherwise.
    ///
    /// Never triggers any network request — safe to call from list cells that
    /// must not initiate remote fetches on their own.
    ///
    /// Kingfisher automatically promotes a disk hit into the memory cache, so
    /// subsequent calls for the same key become zero-latency synchronous hits.
    func localCachedImage(for game: RAGameEntry, platform: RAPlatformItem) async -> UIImage? {
        let imgKey = Self.imageCacheKey(gameName: game.name, rdbName: platform.rdbName)

        // Memory hit — synchronous, return immediately.
        if let mem = imageCache.retrieveImageInMemoryCache(forKey: imgKey, options: nil) {
            return mem
        }

        // Disk hit — async I/O, no network.
        // Kingfisher calls the completion on the main queue (callbackQueue = .mainCurrentOrAsync),
        // so the continuation resumes on the main actor automatically.
        return await withCheckedContinuation { continuation in
            imageCache.retrieveImage(forKey: imgKey) { result in
                if case .success(let cached) = result, cached.cacheType != .none {
                    continuation.resume(returning: cached.image)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Public: Discover flow

    func loadCover(for game: RAGameEntry,
                   platform: RAPlatformItem,
                   into imageView: UIImageView,
                   completion: (@Sendable (UIImage?) -> Void)? = nil) {
        load(gameName: game.name, rdbName: platform.rdbName,
             into: imageView, completion: completion)
    }

    // MARK: - Public: ROM browser flow

    func loadCover(gameName: String,
                   rdbName:  String,
                   into imageView: UIImageView,
                   completion: (@Sendable (UIImage?) -> Void)? = nil) {
        load(gameName: gameName, rdbName: rdbName,
             into: imageView, completion: completion)
    }

    // MARK: - Cache management

    func clearCache(completion: (@MainActor @Sendable () -> Void)? = nil) {
        imageCache.clearCache {
            guard let completion else { return }
            Task { @MainActor in completion() }
        }
        fileListMemoryCache.removeAll()
        matchCache.removeAll()
        matchCachePersistTask?.cancel()
        // Cancel any in-flight file-list fetches so their MainActor.run completions
        // don't re-populate the caches we just cleared.
        fileListInFlight.values.forEach { $0.cancel() }
        fileListInFlight.removeAll()
        // FileManager I/O off the main thread — removing a cache directory with many files
        // can take non-trivial time.
        let dirToRemove  = fileListCacheDir
        let fileToRemove = matchCacheFile
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: dirToRemove)
            try? FileManager.default.removeItem(at: fileToRemove)
            try? FileManager.default.createDirectory(at: dirToRemove,
                                                      withIntermediateDirectories: true)
        }
    }

    func diskCacheSize(completion: @escaping (Int64) -> Void) {
        imageCache.calculateDiskStorageSize { result in
            let bytes = (try? result.get()).map { Int64($0) } ?? 0
            Task { @MainActor in completion(bytes) }
        }
    }

    // MARK: - Private: load pipeline

    private func load(gameName: String,
                      rdbName:  String,
                      into imageView: UIImageView,
                      completion: (@Sendable (UIImage?) -> Void)?) {

        // Stable image cache key — does NOT depend on the CDN URL.
        // This lets us query Kingfisher's cache before running any pipeline work.
        let imgKey = Self.imageCacheKey(gameName: gameName, rdbName: rdbName)

        // ── Fast path: memory cache (synchronous, zero latency) ─────────────
        if let memImage = imageCache.retrieveImageInMemoryCache(forKey: imgKey, options: nil) {
            imageView.image = memImage
            completion?(memImage)
            return
        }

        // ── Medium path: disk cache (fast async read, no network/matching) ──
        //
        // Kingfisher's completion is @Sendable, so we cannot access @MainActor-isolated
        // properties (matchCache, fetchAndLoad, …) directly inside it.
        // imageView is captured weakly: if the owning VC is dismissed before the
        // disk read returns, we skip further I/O while still calling completion so
        // the caller can clean up its loading state.
        imageCache.retrieveImage(forKey: imgKey) { [weak imageView] result in
            Task { @MainActor [weak self, weak imageView] in
                guard let self else { return }

                // Kingfisher compatibility note:
                //   • Kingfisher 7 (strict): .failure for cache miss, .success for hit.
                //   • Some builds/forks: .success with cacheType == .none for miss.
                // Guard both cases so we never call completion(nil) silently here.
                if case .success(let cached) = result, cached.cacheType != .none {
                    imageView?.image = cached.image   // no-op if VC already gone
                    completion?(cached.image)
                    return
                }

                // If imageView is nil the VC was dismissed — no point downloading.
                guard let imageView else {
                    completion?(nil)
                    return
                }

                // ── Match cache: CDN filename known, skip file list + Levenshtein ──
                if let cachedFilename = self.matchCache[imgKey] {
                    if cachedFilename.isEmpty {
                        // Negative cache: confirmed no cover for this game.
                        completion?(nil)
                    } else {
                        self.downloadCover(filename: cachedFilename, rdbName: rdbName,
                                           imgKey: imgKey, into: imageView, completion: completion)
                    }
                    return
                }

                // ── Slow path: file list → fuzzy match → download ────────────
                self.fetchAndLoad(gameName: gameName, rdbName: rdbName,
                                  imgKey: imgKey, into: imageView, completion: completion)
            }
        }
    }

    /// Runs entirely on a background thread: reads/fetches file list, fuzzy-matches,
    /// then downloads the image via Kingfisher (using the stable `imgKey`).
    private func fetchAndLoad(gameName:   String,
                               rdbName:   String,
                               imgKey:    String,
                               into imageView: UIImageView,
                               completion: (@Sendable (UIImage?) -> Void)?) {

        // ── Resolve the file-list Task on the main actor ────────────────────
        // Concurrent calls for the same platform share one network request.
        // All three branches produce a Task<[String], Never> that the detached
        // task below awaits; the actual network fetch (if needed) runs inside
        // that task on the background thread.
        let fileListTask: Task<[String], Never>
        if let mem = fileListMemoryCache[rdbName], !mem.isEmpty {
            // Already loaded this session — wrap in a completed Task.
            fileListTask = Task { mem }
        } else if let inflight = fileListInFlight[rdbName] {
            // Another fetchAndLoad for this platform is already fetching — reuse it.
            fileListTask = inflight
        } else {
            // First request for this platform in this session.
            let cacheFile = fileListCacheDir.appendingPathComponent(
                                Self.fileListCacheFileName(for: rdbName))
            let listURL   = Self.fileListDirectoryURL(for: rdbName)
            let ttl       = fileListTTL
            let newTask   = Task.detached(priority: .userInitiated) {
                await Self.fetchFileList(cacheFile: cacheFile, listURL: listURL, ttl: ttl)
            }
            fileListInFlight[rdbName] = newTask
            fileListTask = newTask
        }

        let imageCache = self.imageCache

        Task.detached(priority: .userInitiated) {
            // 1. Await file list (instant from memory, or from the shared network task).
            let fileList = await fileListTask.value

            // 2. Populate memory cache and remove the in-flight entry.
            await MainActor.run { [fileList] in
                if !fileList.isEmpty,
                   GameCoverService.shared.fileListMemoryCache[rdbName] == nil {
                    GameCoverService.shared.fileListMemoryCache[rdbName] = fileList
                }
                GameCoverService.shared.fileListInFlight.removeValue(forKey: rdbName)
            }

            // 3. Levenshtein fuzzy match — CPU-bound, background thread.
            let matchedFile = Self.findBestMatch(for: gameName, in: fileList)

            // 4. Persist match result.
            //    Only when file list is non-empty — an empty list means a network
            //    failure, not a confirmed "no cover"; leave absent so we retry.
            if !fileList.isEmpty {
                await MainActor.run { [matchedFile] in
                    GameCoverService.shared.matchCache[imgKey] = matchedFile ?? ""
                    GameCoverService.shared.scheduleMatchCachePersist()
                }
            }

            guard let matchedFile else {
                await MainActor.run { completion?(nil) }
                return
            }

            // 5. Build CDN URL from matched filename.
            guard let url = Self.coverURL(rdbName: rdbName, filename: matchedFile) else {
                await MainActor.run { completion?(nil) }
                return
            }

            // 6. Kingfisher download + cache under the stable key.
            //    Capture imageView weakly — if the VC was dismissed while we were
            //    matching, skip the download (matchCache is already populated, so
            //    the next visit will use downloadCover directly).
            await MainActor.run { [weak imageView] in
                guard let imageView else { return }
                let resource = KF.ImageResource(downloadURL: url, cacheKey: imgKey)
                let options: KingfisherOptionsInfo = [
                    .targetCache(imageCache),
                    .transition(.fade(0.2)),
                    .cacheOriginalImage,
                ]
                imageView.kf.setImage(with: resource, options: options) { result in
                    completion?(try? result.get().image)
                }
            }
        }
    }

    // MARK: - Download (matched filename already known)

    /// Called when `matchCache` has the filename but the image isn't in Kingfisher yet.
    /// Skips file-list fetch and Levenshtein entirely.
    private func downloadCover(filename:  String,
                                rdbName:  String,
                                imgKey:   String,
                                into imageView: UIImageView,
                                completion: (@Sendable (UIImage?) -> Void)?) {
        guard let url = Self.coverURL(rdbName: rdbName, filename: filename) else {
            completion?(nil)
            return
        }
        let resource = KF.ImageResource(downloadURL: url, cacheKey: imgKey)
        let options: KingfisherOptionsInfo = [
            .targetCache(imageCache),
            .transition(.fade(0.2)),
            .cacheOriginalImage,
        ]
        imageView.kf.setImage(with: resource, options: options) { result in
            completion?(try? result.get().image)
        }
    }

    // MARK: - Match cache persistence

    /// Loads the match cache JSON from disk into memory (called once at init).
    private func loadMatchCacheFromDisk() {
        let file = matchCacheFile
        Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: file),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            else { return }
            await MainActor.run {
                // Merge so in-memory entries written before load completes aren't lost.
                GameCoverService.shared.matchCache.merge(dict) { current, _ in current }
            }
        }
    }

    /// Debounced write — coalesces rapid successive matches into one disk write.
    private func scheduleMatchCachePersist() {
        matchCachePersistTask?.cancel()
        matchCachePersistTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            persistMatchCacheNow()
        }
    }

    private func persistMatchCacheNow() {
        let snapshot = matchCache
        let file     = matchCacheFile
        Task.detached(priority: .utility) {
            guard let data = try? JSONSerialization.data(withJSONObject: snapshot) else { return }
            try? data.write(to: file, options: .atomic)
        }
    }

    // MARK: - Helpers (fast, no I/O)

    /// Stable Kingfisher cache key independent of the CDN URL.
    nonisolated private static func imageCacheKey(gameName: String, rdbName: String) -> String {
        "cover|\(rdbName)|\(gameName)"
    }

    nonisolated private static func fileListCacheFileName(for rdbName: String) -> String {
        rdbName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .appending(".txt")
    }

    // MARK: - File list: disk cache + network  (nonisolated — runs on background)

    /// Loads the filename list from disk cache if fresh, otherwise fetches from CDN.
    /// Must be called from a background thread (does synchronous disk I/O).
    nonisolated private static func fetchFileList(cacheFile: URL,
                                                  listURL:   URL?,
                                                  ttl:       TimeInterval) async -> [String] {
        // ── Disk cache ──────────────────────────────────────────────────────
        let fm = FileManager.default
        if fm.fileExists(atPath: cacheFile.path),
           let attrs   = try? fm.attributesOfItem(atPath: cacheFile.path),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) < ttl,
           let content = try? String(contentsOf: cacheFile, encoding: .utf8) {
            let files = content.components(separatedBy: "\n").filter { !$0.isEmpty }
            if !files.isEmpty { return files }
        }

        // ── Network fetch ────────────────────────────────────────────────────
        guard let url = listURL else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let html = String(data: data, encoding: .utf8) else { return [] }
            let files = parseFileList(from: html)

            // Only write to disk if we got a real non-empty list.
            // An empty result (404, wrong path, network issue) must NOT be
            // cached — otherwise it permanently blocks future retries.
            if !files.isEmpty {
                try? files.joined(separator: "\n").write(
                    to: cacheFile, atomically: true, encoding: .utf8)
            }
            return files
        } catch {
            NSLog("[GameCoverService] fetchFileList error: %@  url=%@",
                  error.localizedDescription, url.absoluteString)
            return []
        }
    }

    nonisolated private static func fileListDirectoryURL(for rdbName: String) -> URL? {
        guard let enc = rdbName.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://thumbnails.libretro.com/\(enc)/Named_Boxarts/")
    }

    // MARK: - HTML parsing  (nonisolated — pure, no state)

    // Pre-compiled regexes — NSRegularExpression construction is expensive; share instances.
    // nonisolated: NSRegularExpression is Sendable — safe to access from any context.
    nonisolated private static let fileListRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"href="([^"]+\.png)""#)
    }()

    /// Matches parenthesised / bracketed region/revision tags, e.g. "(USA)", "[!]".
    /// Pre-compiled and shared across all normalise() calls (~3 000 per match session).
    nonisolated private static let regionTagRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\s*[\(\[][^\)\]]*[\)\]]"#)
    }()

    nonisolated private static func parseFileList(from html: String) -> [String] {
        let range = NSRange(html.startIndex..., in: html)
        return fileListRegex.matches(in: html, range: range).compactMap { match -> String? in
            guard let r = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[r]).removingPercentEncoding ?? String(html[r])
        }
    }

    // MARK: - URL construction  (nonisolated — pure, no state)

    nonisolated private static func coverURL(rdbName: String, filename: String) -> URL? {
        guard
            let p = rdbName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let f = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://thumbnails.libretro.com/\(p)/Named_Boxarts/\(f)")
    }

    // MARK: - Fuzzy matching  (nonisolated — CPU-bound, no state)

    // Pre-computed character set used by normalise() — avoids rebuilding on every call.
    // Called up to ~3000 times per platform during Levenshtein matching.
    // nonisolated: CharacterSet is a Sendable value type; safe from any context.
    nonisolated private static let normCharset: CharacterSet = .letters.union(.decimalDigits).union(.whitespaces)

    nonisolated private static func findBestMatch(for gameName: String,
                                                  in candidates: [String]) -> String? {
        guard !candidates.isEmpty else { return nil }

        let query = normalise(gameName)

        let pairs: [(file: String, norm: String)] = candidates.map { file in
            let base = file.hasSuffix(".png") ? String(file.dropLast(4)) : file
            return (file: file, norm: normalise(base))
        }

        // Exact normalised match (fast path).
        if let exact = pairs.first(where: { $0.norm == query }) {
            return exact.file
        }

        // Best Levenshtein match.
        var bestFile  = ""
        var bestScore = 0.0
        for pair in pairs {
            let s = similarity(query, pair.norm)
            if s > bestScore { bestScore = s; bestFile = pair.file }
        }
        return bestScore >= 0.72 ? bestFile : nil
    }

    nonisolated private static func normalise(_ name: String) -> String {
        var s = name.lowercased()
        // Use the pre-compiled regionTagRegex instead of recompiling on every call.
        let nsRange = NSRange(s.startIndex..., in: s)
        s = regionTagRegex.stringByReplacingMatches(in: s, range: nsRange, withTemplate: "")
        // Build filtered string in one pass — avoids allocating a String per scalar (old approach).
        s = String(String.UnicodeScalarView(s.unicodeScalars.filter { normCharset.contains($0) }))
        for article in ["the ", "a ", "an "] where s.hasPrefix(article) {
            s = String(s.dropFirst(article.count)); break
        }
        return s.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    nonisolated private static func similarity(_ a: String, _ b: String) -> Double {
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 1 }
        return 1 - Double(levenshtein(Array(a), Array(b))) / Double(maxLen)
    }

    nonisolated private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        // Pre-allocate two rows and swap in place — avoids one heap allocation per iteration
        // (previously `[i] + Array(repeating:)` allocated a new array on every pass).
        var prev = Array(0...b.count)
        var curr = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                curr[j] = a[i-1] == b[j-1]
                    ? prev[j-1]
                    : 1 + min(prev[j], prev[j-1], curr[j-1])
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }
}
