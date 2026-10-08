//
//  OnDemandResourceLoader.swift
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

import Foundation
import Network
import ObjcHelper
import RACoordinator
import SQLite3
import UIKit
import os

extension Notification.Name {
    /// Posted (on main) when an ODR resource finishes installing or is deleted.
    /// `object` = the resource id (String).
    static let odrResourceStateDidChange = Notification.Name("RetroGoODRResourceStateDidChange")
    /// Posted (on main) when the language pack used for translations changes:
    /// the App language changed, or its pack was installed, updated or deleted.
    static let activeLanguagePackDidChange = Notification.Name("RetroGoActiveLanguagePackDidChange")
    /// Posted (on main, at most once per launch) when resources the App needs
    /// can't be downloaded because RetroGo isn't allowed to use the network.
    /// `object` = [ODRResource] still missing.
    static let odrNetworkAccessDenied = Notification.Name("RetroGoODRNetworkAccessDenied")
    /// Posted (on main) when the network becomes usable again, so a denied
    /// alert that is still on screen can go away.
    static let odrNetworkAccessRestored = Notification.Name("RetroGoODRNetworkAccessRestored")
}

/// One downloadable On-Demand Resource: a prebuilt SQLite file shipped as an ODR
/// tag. Base resources are English (the game database, the cheat library);
/// a language pack holds every translation for one App language (game names,
/// cheat descriptions, arcade cheat texts). Every fact is hardcoded in
/// `OnDemandResourceLoader`; adding a language pack is one entry plus its ODR tag.
struct ODRResource: Hashable {
    enum Kind {
        case base
        case languagePack
    }

    let id: String
    let kind: Kind
    /// On-Demand Resource tag (set in the Xcode resource's ODR tags).
    let odrTag: String
    /// Resource name + extension inside the app bundle.
    let bundleResource: String
    let bundleExtension: String
    /// File name written into the app's database folder.
    let installedFileName: String
    /// Hardcoded approximate byte size, for display before any download.
    let approxByteSize: Int64
    /// meta.db_version of the file this App version ships. An installed file
    /// with another db_version (or none) is updated; the same one is kept, so
    /// an App update alone never downloads a database again.
    let dbVersion: Int
    /// PRAGMA user_version this App can read. An installed file of another
    /// schema can't be used until it is replaced.
    let schemaVersion: Int
    /// Required = downloaded at launch and not user-deletable (the game DB).
    let isRequired: Bool
    /// Localized string keys (Localizable.strings odr_*).
    let titleKey: String
    let descKey: String
    /// Language packs: the pack's BCP-47 id and the App languages it serves.
    let language: String?
    let appLanguages: [String]
    /// Language packs: the language's own name, shown untranslated.
    let nativeName: String?

    static func base(id: String, odrTag: String, bundleResource: String, installedFileName: String,
                     approxByteSize: Int64, dbVersion: Int, schemaVersion: Int, isRequired: Bool,
                     titleKey: String, descKey: String) -> ODRResource {
        ODRResource(id: id, kind: .base, odrTag: odrTag,
                    bundleResource: bundleResource, bundleExtension: "sqlite",
                    installedFileName: installedFileName, approxByteSize: approxByteSize,
                    dbVersion: dbVersion, schemaVersion: schemaVersion, isRequired: isRequired,
                    titleKey: titleKey, descKey: descKey,
                    language: nil, appLanguages: [], nativeName: nil)
    }

    /// A pack is `lang-<language>.sqlite` under the ODR tag `lang-<language>`.
    static func languagePack(language: String, appLanguages: [String], nativeName: String,
                             approxByteSize: Int64, dbVersion: Int) -> ODRResource {
        let name = "lang-\(language)"
        return ODRResource(id: name, kind: .languagePack, odrTag: name,
                           bundleResource: name, bundleExtension: "sqlite",
                           installedFileName: "\(name).sqlite", approxByteSize: approxByteSize,
                           dbVersion: dbVersion, schemaVersion: languagePackSchemaVersion, isRequired: false,
                           titleKey: "", descKey: "odr_langpack_desc",
                           language: language, appLanguages: appLanguages, nativeName: nativeName)
    }

    /// Schema of the language pack files (RALanguagePackSchemaVersion).
    static let languagePackSchemaVersion = 1

    static func == (l: ODRResource, r: ODRResource) -> Bool { l.id == r.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Install / download state of an ODR resource.
enum ODRResourceState {
    case ready                    // installed, readable, and the db_version in code
    case outdated                 // installed, but another db_version or schema
    case notDownloaded            // not installed
    case downloading(Double)      // fractionCompleted 0…1
}

final class OnDemandResourceLoader: NSObject {

    static let shared = OnDemandResourceLoader()

    // MARK: - Hardcoded resource catalog
    //
    // dbVersion must equal meta.db_version of the shipped file and
    // Tools/cheat_db/db_versions.json (scripts/build/verify_db_versions.py).

    static let gamerdb = ODRResource.base(
        id: "gamerdb", odrTag: "game-db", bundleResource: "gamerdb",
        installedFileName: "gamerdb.db", approxByteSize: 77_332_480,
        dbVersion: 5, schemaVersion: 4, isRequired: true,
        titleKey: "odr_gamerdb_title", descKey: "odr_gamerdb_desc")

    static let cheat = ODRResource.base(
        id: "cheat", odrTag: "cheat-db", bundleResource: "cheat",
        installedFileName: "cheat.sqlite", approxByteSize: 88_608_768,
        dbVersion: 5, schemaVersion: 5, isRequired: false,
        titleKey: "odr_cheat_title", descKey: "odr_cheat_desc")

    static let baseResources: [ODRResource] = [gamerdb, cheat]

    /// Every language pack. The App's own languages may be ahead of this list;
    /// an App language without a pack simply shows English data.
    static let languagePacks: [ODRResource] = [
        .languagePack(language: "zh-Hans", appLanguages: ["zh-Hans"], nativeName: "简体中文",
                      approxByteSize: 13_258_752, dbVersion: 1),
    ]

    static var resources: [ODRResource] { baseResources + languagePacks }

    static func resource(id: String) -> ODRResource? {
        resources.first { $0.id == id }
    }

    /// The language pack serving an App language (an lproj name such as
    /// "zh-Hans"), if one exists.
    static func languagePack(forAppLanguage language: String) -> ODRResource? {
        languagePacks.first { $0.appLanguages.contains(language) }
    }

    // MARK: - State

    /// `true` once the (required) game database is open and queryable.
    @objc private(set) dynamic var rdbReady = false

    /// What was read from an installed file.
    private struct InstalledInfo {
        let dbVersion: Int?
        let usable: Bool
    }

    /// Guards `installed` and `appliedLanguagePackPath`, read from any thread.
    private let lock = NSLock()
    private var installed: [String: InstalledInfo] = [:]
    private var appliedLanguagePackPath: String??

    /// Live requests keyed by resource id (kept alive while downloading) + their
    /// progress observers. Touched only on the main thread.
    private var activeRequests: [String: NSBundleResourceRequest] = [:]
    private var progressObservers: [String: NSKeyValueObservation] = [:]
    /// Downloads waiting to retry after a transient failure. Main thread only.
    private var retryingDownloads: Set<String> = []
    /// Delays before the retries of a transient failure (automatic downloads only).
    private static let retryDelays: [TimeInterval] = [3, 10]

    /// Serial queue for file copy / version bookkeeping — never the main thread.
    private let importQueue = DispatchQueue(label: "com.retrogo.odr.install", qos: .utility)

    /// Language packs the user deleted or declined: never downloaded
    /// automatically again, only from the resource page or when asked.
    private static let declinedPacksKey = "RetroGoDeclinedLanguagePacks"

    /// Automatic downloads (launch, language change) that failed, retried when
    /// the network comes back or the App becomes active again — e.g. after the
    /// user answers the system's network permission alert on first launch.
    /// Main thread only.
    private var pendingAutomaticDownloads: Set<String> = []
    private var automaticQueue: [ODRResource] = []
    private var automaticInFlight: String?
    private let pathMonitor = NWPathMonitor()
    private var lastPathStatus: NWPath.Status?
    private var networkAccessDenied = false
    private var reportedNetworkDenied = false
    /// A denied report is waiting for its check (see reportNetworkDeniedIfNeeded).
    private var deniedReportPending = false
    private var deniedReportWaitsForActive = false
    /// Time for the path to update after the system permission alert closes.
    private static let deniedReportDelay: TimeInterval = 2

    private var databaseFolder: String {
        (AppConfig.shared.gameRdbDatabasePath as NSString).deletingLastPathComponent + "/"
    }

    func targetPath(_ r: ODRResource) -> String { databaseFolder + r.installedFileName }

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(appLanguageChanged),
                                               name: .languageChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        startNetworkMonitor()
        importQueue.async { [weak self] in self?.launch() }
    }

    // MARK: - Public API

    func state(for r: ODRResource) -> ODRResourceState {
        if Thread.isMainThread, let req = activeRequests[r.id] {
            return .downloading(req.progress.fractionCompleted)
        }
        if Thread.isMainThread, retryingDownloads.contains(r.id) {
            return .downloading(0)
        }
        guard let info = installedInfo(r) else { return .notDownloaded }
        return info.usable && info.dbVersion == r.dbVersion ? .ready : .outdated
    }

    /// Installed and readable by this App, whatever its db_version. An outdated
    /// but readable file stays in use until its update is installed.
    func isUsable(_ r: ODRResource) -> Bool {
        installedInfo(r)?.usable == true
    }

    /// The pack of the current App language, whether installed or not.
    var currentLanguagePack: ODRResource? {
        Self.languagePack(forAppLanguage: Bundle.currentLanguage())
    }

    /// Path of the language pack to read translations from: the current App
    /// language's pack when it is installed and readable, else nil (English).
    var activeLanguagePackPath: String? {
        guard let pack = currentLanguagePack, isUsable(pack) else { return nil }
        return targetPath(pack)
    }

    /// BCP-47 id of the active language pack, or nil.
    var activeLanguage: String? {
        activeLanguagePackPath == nil ? nil : currentLanguagePack?.language
    }

    /// After the user switches the App language: the pack to offer when that
    /// language has one that is not installed. Nil otherwise.
    func languagePackToOffer() -> ODRResource? {
        guard let pack = currentLanguagePack, case .notDownloaded = state(for: pack) else { return nil }
        return pack
    }

    /// The user turned down a pack: don't download it on our own any more.
    func declineLanguagePack(_ r: ODRResource) {
        guard r.kind == .languagePack else { return }
        var declined = Set(UserDefaults.standard.stringArray(forKey: Self.declinedPacksKey) ?? [])
        declined.insert(r.id)
        UserDefaults.standard.set(Array(declined).sorted(), forKey: Self.declinedPacksKey)
    }

    private func isDeclined(_ r: ODRResource) -> Bool {
        (UserDefaults.standard.stringArray(forKey: Self.declinedPacksKey) ?? []).contains(r.id)
    }

    private func clearDeclined(_ r: ODRResource) {
        let declined = (UserDefaults.standard.stringArray(forKey: Self.declinedPacksKey) ?? []).filter { $0 != r.id }
        UserDefaults.standard.set(declined, forKey: Self.declinedPacksKey)
    }

    /// Begin (or resume) downloading + installing a resource. `progress` and
    /// `completion` are delivered on the main thread. The ODR download runs while
    /// the app is in the foreground holding the request (not a true background
    /// task — keep the progress UI up). A failed download keeps the old file.
    /// `retryTransientFailures` is for downloads the App starts on its own; a
    /// download the user started reports its first failure right away.
    func startDownload(_ r: ODRResource,
                       retryTransientFailures: Bool = false,
                       progress: @escaping (Double) -> Void,
                       completion: @escaping (Bool, Error?) -> Void) {
        assert(Thread.isMainThread)
        if r.kind == .languagePack { clearDeclined(r) }
        if case .ready = state(for: r) { completion(true, nil); return }
        if activeRequests[r.id] != nil || retryingDownloads.contains(r.id) { return }   // already downloading
        beginRequest(r, attempt: 0, retries: retryTransientFailures ? Self.retryDelays : [],
                     progress: progress, completion: completion)
    }

    /// Main thread. One NSBundleResourceRequest; with `retries`, transient
    /// failures (the system's streaming unzip service dropping its connection,
    /// network errors) are retried after those delays before the caller hears
    /// about them.
    private func beginRequest(_ r: ODRResource, attempt: Int, retries: [TimeInterval],
                              progress: @escaping (Double) -> Void,
                              completion: @escaping (Bool, Error?) -> Void) {
        let request = NSBundleResourceRequest(tags: [r.odrTag])
        request.loadingPriority = NSBundleResourceRequestLoadingPriorityUrgent
        activeRequests[r.id] = request
        progressObservers[r.id] = request.progress.observe(\.fractionCompleted) { p, _ in
            DispatchQueue.main.async { progress(p.fractionCompleted) }
        }

        request.beginAccessingResources { [weak self] error in
            guard let self else { return }
            if let error {
                let nsError = error as NSError
                RetroGoLogger.odr.error("Download of \(r.id, privacy: .public) failed (attempt \(attempt + 1)): \(nsError.domain, privacy: .public) \(nsError.code) \(nsError.localizedDescription, privacy: .public)")
                DispatchQueue.main.async {
                    self.cleanup(r.id)
                    if attempt < retries.count, Self.isTransient(nsError), !self.networkAccessDenied {
                        let delay = retries[attempt]
                        self.retryingDownloads.insert(r.id)
                        RetroGoLogger.odr.info("Retrying download of \(r.id, privacy: .public) in \(Int(delay))s")
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self.retryingDownloads.remove(r.id)
                            self.beginRequest(r, attempt: attempt + 1, retries: retries,
                                              progress: progress, completion: completion)
                        }
                    } else {
                        completion(false, error)
                    }
                }
                return
            }
            self.importQueue.async {
                let ok = self.installFromBundle(r)
                request.endAccessingResources()
                if ok {
                    self.refreshInstalledInfo(r)
                    self.closeReaders(of: r)
                    if r.kind == .languagePack { self.applyActiveLanguagePack(force: true) }
                    if r == Self.gamerdb { self.openGameDatabase() }
                }
                DispatchQueue.main.async {
                    self.cleanup(r.id)
                    if ok {
                        NotificationCenter.default.post(name: .odrResourceStateDidChange, object: r.id)
                    }
                    completion(ok, ok ? nil : NSError(
                        domain: "OnDemandResourceLoader", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "install failed"]))
                }
            }
        }
    }

    /// Failures worth another try: the ODR daemon's XPC connection to its
    /// streaming unzip service was interrupted/invalidated, or a network error.
    /// Not: out of space, unknown tag, resource too large.
    private static func isTransient(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain {
            return error.code == NSXPCConnectionInterrupted || error.code == NSXPCConnectionInvalid
        }
        return error.domain == NSURLErrorDomain
    }

    /// Delete an optional resource's installed file to reclaim space. Required
    /// resources can't be deleted. A deleted language pack is not downloaded
    /// automatically again. Returns `true` if anything was removed.
    @discardableResult
    func delete(_ r: ODRResource) -> Bool {
        guard !r.isRequired else { return false }
        let fm = FileManager.default
        var removed = false
        for suffix in ["", "-wal", "-shm"] {
            let p = targetPath(r) + suffix
            if fm.fileExists(atPath: p), (try? fm.removeItem(atPath: p)) != nil {
                removed = true
            }
        }
        if r.kind == .languagePack { declineLanguagePack(r) }
        refreshInstalledInfo(r)
        closeReaders(of: r)
        if r.kind == .languagePack { applyActiveLanguagePack(force: false) }
        if removed {
            NotificationCenter.default.post(name: .odrResourceStateDidChange, object: r.id)
        }
        return removed
    }

    private func cleanup(_ id: String) {
        progressObservers[id]?.invalidate()
        progressObservers[id] = nil
        activeRequests[id] = nil
    }

    // MARK: - Launch

    /// importQueue. Read what is installed, open the game DB right away when it
    /// is readable (an update replaces it later), and download only what has a
    /// different db_version than this App ships.
    private func launch() {
        migrateLegacyFiles()
        for r in Self.resources { refreshInstalledInfo(r) }
        let gamerdbUsable = isUsable(Self.gamerdb)
        if gamerdbUsable { openGameDatabase() }
        applyActiveLanguagePack(force: true)
        verifyInstalledCheatCatalogIfNeeded()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Without a readable game DB nothing is opened: rdbReady stays false
            // (Discover shows its loading state) until the download succeeds.
            // A missing game DB goes first (Discover waits for it); an outdated
            // one keeps working, so the small language pack goes first instead.
            if !gamerdbUsable {
                RetroGoLogger.odr.info("Game database not installed yet, downloading it")
                self.downloadAutomatically(Self.gamerdb)
                self.updateLanguagePackIfNeeded(allowFirstInstall: true)
            } else {
                self.updateLanguagePackIfNeeded(allowFirstInstall: true)
                self.downloadAutomatically(Self.gamerdb)
            }
        }
    }

    /// Main thread. A download the App starts on its own (not from a page the
    /// user is looking at). They run one at a time, so a large asset pack
    /// doesn't compete with another for the system's ODR services; a failure
    /// is remembered and retried later.
    private func downloadAutomatically(_ r: ODRResource) {
        if case .ready = state(for: r) {
            pendingAutomaticDownloads.remove(r.id)
            return
        }
        guard automaticInFlight != r.id, !automaticQueue.contains(r) else { return }
        automaticQueue.append(r)
        startNextAutomaticDownload()
    }

    private func startNextAutomaticDownload() {
        guard automaticInFlight == nil, !automaticQueue.isEmpty else { return }
        let r = automaticQueue.removeFirst()
        if case .ready = state(for: r) {
            pendingAutomaticDownloads.remove(r.id)
            startNextAutomaticDownload()
            return
        }
        // Already being downloaded from a page: that download covers it.
        if activeRequests[r.id] != nil || retryingDownloads.contains(r.id) {
            startNextAutomaticDownload()
            return
        }
        automaticInFlight = r.id
        startDownload(r, retryTransientFailures: true, progress: { _ in }) { [weak self] ok, _ in
            guard let self else { return }
            self.automaticInFlight = nil
            if ok {
                self.pendingAutomaticDownloads.remove(r.id)
            } else {
                self.pendingAutomaticDownloads.insert(r.id)
                self.reportNetworkDeniedIfNeeded()
            }
            self.startNextAutomaticDownload()
        }
    }

    // MARK: - Network

    private func startNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let denied = path.status != .satisfied &&
                (path.unsatisfiedReason == .wifiDenied || path.unsatisfiedReason == .cellularDenied)
            let status = path.status
            DispatchQueue.main.async { self?.networkPathChanged(status: status, denied: denied) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.retrogo.odr.network", qos: .utility))
    }

    /// Main thread.
    private func networkPathChanged(status: NWPath.Status, denied: Bool) {
        let previous = lastPathStatus
        lastPathStatus = status
        networkAccessDenied = denied
        if denied {
            RetroGoLogger.odr.notice("Network access is denied for RetroGo")
            reportNetworkDeniedIfNeeded()
        } else if status == .satisfied, previous != nil, previous != .satisfied {
            RetroGoLogger.odr.info("Network is available again")
            NotificationCenter.default.post(name: .odrNetworkAccessRestored, object: nil)
            retryAutomaticDownloads()
        }
    }

    @objc private func appDidBecomeActive() {
        retryAutomaticDownloads()
        if deniedReportWaitsForActive {
            deniedReportWaitsForActive = false
            scheduleDeniedReportCheck()
        }
    }

    /// Main thread. Restart the automatic downloads that failed, for resources
    /// that still need them.
    private func retryAutomaticDownloads() {
        guard !pendingAutomaticDownloads.isEmpty, !networkAccessDenied else { return }
        for id in pendingAutomaticDownloads {
            guard let r = Self.resource(id: id), activeRequests[id] == nil else { continue }
            if r.kind == .languagePack, r != currentLanguagePack || isDeclined(r) {
                pendingAutomaticDownloads.remove(id)
                continue
            }
            RetroGoLogger.odr.info("Retrying download of \(id, privacy: .public)")
            downloadAutomatically(r)
        }
    }

    /// Main thread. Once per launch, when the network is denied while resources
    /// the App downloads on its own are still missing, let the UI explain it.
    /// On first launch the path reads as denied while the system's network
    /// permission alert is still unanswered (the App is inactive then), so the
    /// decision waits until the App is active again and the path had a moment
    /// to update; a user who allows access sees no false alarm.
    private func reportNetworkDeniedIfNeeded() {
        guard networkAccessDenied, !reportedNetworkDenied, !deniedReportPending,
              !missingAutomaticResources.isEmpty else { return }
        deniedReportPending = true
        scheduleDeniedReportCheck()
    }

    private func scheduleDeniedReportCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.deniedReportDelay) { [weak self] in
            guard let self else { return }
            guard UIApplication.shared.applicationState == .active else {
                self.deniedReportWaitsForActive = true
                return
            }
            self.deniedReportPending = false
            let missing = self.missingAutomaticResources
            guard self.networkAccessDenied, !self.reportedNetworkDenied, !missing.isEmpty else { return }
            self.reportedNetworkDenied = true
            NotificationCenter.default.post(name: .odrNetworkAccessDenied, object: missing)
        }
    }

    /// Resources whose automatic download failed and that can't be used yet.
    private var missingAutomaticResources: [ODRResource] {
        Self.resources.filter { pendingAutomaticDownloads.contains($0.id) && !isUsable($0) }
    }

    /// Main thread. The current App language's pack: update it when installed
    /// with another db_version; install it when `allowFirstInstall` (launch)
    /// and the user hasn't deleted or declined it.
    private func updateLanguagePackIfNeeded(allowFirstInstall: Bool) {
        guard let pack = currentLanguagePack, !isDeclined(pack) else { return }
        switch state(for: pack) {
        case .outdated:
            break
        case .notDownloaded where allowFirstInstall:
            break
        default:
            return
        }
        RetroGoLogger.odr.info("Downloading language pack \(pack.id, privacy: .public)")
        downloadAutomatically(pack)
    }

    /// Main thread. Hand the new language's pack to the game database right
    /// away: this observer is registered at launch, before any page's, so the
    /// attach is queued ahead of the queries pages make for the new language.
    @objc private func appLanguageChanged() {
        applyActiveLanguagePack(force: false)
        // A pack that is not installed is offered by the settings page.
        updateLanguagePackIfNeeded(allowFirstInstall: false)
    }

    /// Hand the active pack to the game database and tell everyone else. Cheat
    /// catalog users pass `activeLanguagePackPath` when they open it.
    private func applyActiveLanguagePack(force: Bool) {
        let path = activeLanguagePackPath
        lock.lock()
        let changed = appliedLanguagePackPath == nil || appliedLanguagePackPath! != path
        appliedLanguagePackPath = .some(path)
        lock.unlock()
        guard changed || force else { return }
        RAGameRDBManager.shared().setLanguagePack(path: path, completion: nil)
        RetroGoLogger.odr.info("Active language pack: \(self.activeLanguage ?? "none", privacy: .public)")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .activeLanguagePackDidChange, object: nil)
        }
    }

    /// Open (or reopen, after an update) the game SQLite.
    private func openGameDatabase() {
        RAGameRDBManager.shared().initialize(AppConfig.shared.gameRdbDatabasePath) { [weak self] in
            self?.rdbReady = true
            RetroGoLogger.odr.info("Game database ready")
        }
    }

    // MARK: - Installed files

    private func installedInfo(_ r: ODRResource) -> InstalledInfo? {
        lock.lock(); defer { lock.unlock() }
        return installed[r.id]
    }

    private func refreshInstalledInfo(_ r: ODRResource) {
        let info = Self.readInfo(path: targetPath(r), resource: r)
        lock.lock()
        installed[r.id] = info
        lock.unlock()
    }

    /// Reads db_version and checks the schema (and, for packs, the language) of
    /// a database file. Nil when there is no file. A file that can't be opened,
    /// has no db_version or is of another schema is reported as not usable or
    /// without a version, which makes it "outdated".
    private static func readInfo(path: String, resource r: ODRResource) -> InstalledInfo? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let url = URL(string: URL(fileURLWithPath: path).absoluteString + "?immutable=1") else {
            return InstalledInfo(dbVersion: nil, usable: false)
        }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(url.absoluteString, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            return InstalledInfo(dbVersion: nil, usable: false)
        }
        let schema = queryInt(db, "PRAGMA user_version;")
        let dbVersion = queryText(db, "SELECT value FROM meta WHERE key = 'db_version';").flatMap { Int($0) }
        var usable = schema == r.schemaVersion
        if r.kind == .languagePack {
            usable = usable && queryText(db, "SELECT value FROM meta WHERE key = 'lang';") == r.language
        }
        return InstalledInfo(dbVersion: dbVersion, usable: usable)
    }

    private static func queryInt(_ db: OpaquePointer?, _ sql: String) -> Int? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private static func queryText(_ db: OpaquePointer?, _ sql: String) -> String? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW,
              let text = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: text)
    }

    /// Copy the bundled prebuilt file next to the install path, check it, then
    /// swap it in with one rename so readers never see a half-written file.
    /// A file whose db_version, schema or language isn't what this App ships is
    /// refused and the old one kept. Runs on importQueue.
    private func installFromBundle(_ r: ODRResource) -> Bool {
        guard let srcURL = Bundle.main.url(forResource: r.bundleResource,
                                           withExtension: r.bundleExtension) else {
            RetroGoLogger.odr.error("Resource \(r.bundleResource, privacy: .public).\(r.bundleExtension, privacy: .public) not found in bundle")
            return false
        }
        guard let shipped = Self.readInfo(path: srcURL.path, resource: r),
              shipped.usable, shipped.dbVersion == r.dbVersion else {
            let found = Self.readInfo(path: srcURL.path, resource: r)?.dbVersion.map(String.init) ?? "none"
            RetroGoLogger.odr.fault("Downloaded \(r.id, privacy: .public) has db_version \(found, privacy: .public), expected \(r.dbVersion)")
            return false
        }
        let fm = FileManager.default
        let dst = URL(fileURLWithPath: targetPath(r))
        let tmp = URL(fileURLWithPath: targetPath(r) + ".installing")
        do {
            try fm.createDirectory(at: dst.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            if fm.fileExists(atPath: tmp.path) { try fm.removeItem(at: tmp) }
            try fm.copyItem(at: srcURL, to: tmp)

            let srcSize = (try fm.attributesOfItem(atPath: srcURL.path)[.size] as? NSNumber)?.int64Value ?? -1
            let tmpSize = (try fm.attributesOfItem(atPath: tmp.path)[.size] as? NSNumber)?.int64Value ?? -2
            guard srcSize > 0, srcSize == tmpSize else {
                try? fm.removeItem(at: tmp)
                RetroGoLogger.odr.error("Copied resource \(r.id, privacy: .public) is incomplete: \(tmpSize) of \(srcSize) bytes")
                return false
            }

            for suffix in ["-wal", "-shm"] {
                let p = targetPath(r) + suffix
                if fm.fileExists(atPath: p) { try fm.removeItem(atPath: p) }
            }
            if fm.fileExists(atPath: dst.path) {
                _ = try fm.replaceItemAt(dst, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: dst)
            }
            // The user is already waiting on the download; scan the new file
            // here rather than on the first catalog query.
            if r == Self.cheat, !RACheatCatalogManager.verifyCatalogFile(atPath: dst.path) {
                try? fm.removeItem(at: dst)
                RetroGoLogger.odr.error("Installed resource \(r.id, privacy: .public) failed verification")
                return false
            }
            RetroGoLogger.odr.info("Installed \(r.id, privacy: .public) db_version \(r.dbVersion), \(srcSize) bytes")
            return true
        } catch {
            try? fm.removeItem(at: tmp)
            RetroGoLogger.odr.error("Failed to install resource \(r.id, privacy: .public): \(error.localizedDescription)")
            return false
        }
    }

    /// Readers holding the replaced or deleted file must reopen it.
    private func closeReaders(of r: ODRResource) {
        if r == Self.cheat {
            RACheatCatalogManager.shared().closeDatabase()
        }
    }

    /// A cheat catalog installed before verification existed was never scanned.
    /// Do it once in the background; an unreadable file is removed so the cheat
    /// page downloads a fresh copy instead of showing an empty catalog.
    private func verifyInstalledCheatCatalogIfNeeded() {
        let path = targetPath(Self.cheat)
        guard isUsable(Self.cheat), !RACheatCatalogManager.isCatalogFileVerified(atPath: path) else { return }
        guard !RACheatCatalogManager.verifyCatalogFile(atPath: path) else { return }
        RetroGoLogger.odr.error("Installed cheat catalog failed verification, removing it")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.activeRequests[Self.cheat.id] == nil else { return }
            self.delete(Self.cheat)
        }
    }

    // MARK: - Migration from per-App-version snapshots (1.11 and earlier)

    private static let layoutVersionKey = "RetroGoODRLayoutVersion"

    /// 1.11 and earlier shipped gameloc.sqlite and mame_cheat_i18n.sqlite as
    /// their own resources and tracked installs by an App-side version number.
    /// Their content now lives in the language packs; installs are tracked by
    /// db_version inside each file. An old gamerdb keeps working until its
    /// update arrives; an old cheat.sqlite can't be read and is replaced the
    /// next time the cheat page needs it.
    private func migrateLegacyFiles() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Self.layoutVersionKey) < 2 else { return }
        let fm = FileManager.default
        for name in ["gameloc.sqlite", "mame_cheat_i18n.sqlite"] {
            for suffix in ["", "-wal", "-shm"] {
                let path = databaseFolder + name + suffix
                if fm.fileExists(atPath: path) { try? fm.removeItem(atPath: path) }
            }
        }
        for id in ["gamerdb", "gameloc", "cheat", "mamecheat-i18n"] {
            defaults.removeObject(forKey: "RetroGoODRInstalledVersion_\(id)")
        }
        defaults.set(2, forKey: Self.layoutVersionKey)
        RetroGoLogger.odr.info("Removed the 1.11 localization databases; translations now come from language packs")
    }
}

extension OnDemandResourceLoader {
    /// Opens (or keeps open) the cheat catalog together with the language pack
    /// of the current App language. `completion` runs on main with whether the
    /// catalog can be read; false for a missing, outdated-schema or damaged file.
    func openCheatCatalog(completion: @escaping (Bool) -> Void) {
        guard isUsable(Self.cheat) else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        RACheatCatalogManager.shared().initialize(
            withCheatPath: targetPath(Self.cheat),
            languagePackPath: activeLanguagePackPath
        ) {
            completion(RACheatCatalogManager.shared().isDatabaseReady)
        }
    }
}

#if DEBUG
// MARK: - DEBUG: build the prebuilt database offline from the .rdb files in the bundle

extension OnDemandResourceLoader {

    /// .rdb resource names used for the offline export (bundle resource names, without extension).
    static let debugRdbNames: [String] = [
        "DOS",
        "Nintendo - Family Computer Disk System",
        "Nintendo - Game Boy",
        "Nintendo - Game Boy Advance",
        "Nintendo - Game Boy Color",
        "MAME",
        "Nintendo - Nintendo 64",
        "Nintendo - Nintendo DS",
        "Nintendo - Nintendo Entertainment System",
        "Sony - PlayStation",
        "Sony - PlayStation Portable",
        "Sega - 32X",
        "Sega - Game Gear",
        "Sega - Master System - Mark III",
        "Sega - Mega Drive - Genesis",
        "Sega - Mega-CD - Sega CD",
        "Sega - PICO",
        "Sega - Saturn",
        "Nintendo - Super Nintendo Entertainment System",
        "Sega - Dreamcast",
        "Sega - Naomi",
        "Sega - Naomi 2",
        "Atomiswave",
        "Sega - SG-1000",
    ]

    /// DEBUG: merge the .rdb files in the bundle into a finished prebuilt database,
    /// write it to <Documents>/gamerdb.sqlite and pass the path back so it can be pulled from the simulator container.
    func debugExportCombinedDatabase(completion: @escaping (String?, Error?) -> Void) {
        // Resources/Data is a blue folder reference, packaged with its hierarchy,
        // so the rdb files live in <bundle>/Data/rdb/ at runtime and need the subdirectory to be found.
        let rdbPaths: [String] = OnDemandResourceLoader.debugRdbNames.compactMap {
            Bundle.main.url(forResource: $0,
                            withExtension: "rdb",
                            subdirectory: "Data/rdb")?.path
        }
        guard !rdbPaths.isEmpty else {
            completion(nil, NSError(domain: "OnDemandResourceLoader", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey:
                                                "Bundle 内找不到任何 .rdb 文件，请确认它们仍包含在 Debug target 的资源中"]))
            return
        }

        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory,
                                                       .userDomainMask, true).first!
        let dest = (docs as NSString).appendingPathComponent("gamerdb.sqlite")

        RAGameRDBManager.shared().exportCombinedDatabase(toPath: dest,
                                                         fromRdbPaths: rdbPaths) { total, error in
            if let error {
                completion(nil, error)
            } else {
                RetroGoLogger.odr.debug("Debug export: \(total) games written to \(dest)")
                completion(dest, nil)
            }
        }
    }
}
#endif
