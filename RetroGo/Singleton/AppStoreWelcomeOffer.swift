//
//  AppStoreWelcomeOffer.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/2.
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
import Security

extension Notification.Name {
    static let appStoreWelcomeOfferDidStart = Notification.Name("appStoreWelcomeOfferDidStart")
}

/// One-time welcome price for the lifetime unlock. The window opens the first
/// time the offer is shown on the purchase page and closes for good after
/// `duration`. The start time lives in the (iCloud-synced) Keychain so deleting
/// and reinstalling the app does not open a new window.
@MainActor
enum AppStoreWelcomeOffer {
    static let duration: TimeInterval = 30 * 60

    private static let service = "com.haharsw.pudge.welcome-offer"
    private static let account = "startDate"

    private static var cachedStartDate: Date??

    static var startDate: Date? {
        if let cachedStartDate { return cachedStartDate }
        let date = readStartDate()
        cachedStartDate = .some(date)
        return date
    }

    /// Seconds left in the window; nil before it opens and after it closes.
    static var remaining: TimeInterval? {
        guard let startDate else { return nil }
        let left = duration - Date().timeIntervalSince(startDate)
        return left > 0 ? left : nil
    }

    static var isActive: Bool {
        remaining != nil
    }

    /// Opens the window the first time the offer is shown. Never reopens it.
    static func startIfNeeded() {
        guard startDate == nil else { return }
        let now = Date()
        guard writeStartDate(now) else {
            NSLog("[WelcomeOffer] Failed to store start date in Keychain")
            return
        }
        // Another device may have opened the window already (iCloud Keychain).
        cachedStartDate = .some(readStartDate() ?? now)
        NotificationCenter.default.post(name: .appStoreWelcomeOfferDidStart, object: nil)
    }

    static func formattedRemaining(_ remaining: TimeInterval) -> String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    #if DEBUG
    /// Debug only: run with the `-ResetWelcomeOffer` launch argument to forget the
    /// window on this device and in iCloud Keychain.
    static func resetIfRequestedForTesting() {
        guard ProcessInfo.processInfo.arguments.contains("-ResetWelcomeOffer") else { return }
        var query = baseQuery
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        let status = SecItemDelete(query as CFDictionary)
        cachedStartDate = nil
        NSLog("[WelcomeOffer] Reset for testing, status %d", status)
    }
    #endif

    // MARK: - Keychain

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readStartDate() -> Date? {
        var query = baseQuery
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let interval = Double(String(decoding: data, as: UTF8.self)) else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    private static func writeStartDate(_ date: Date) -> Bool {
        var query = baseQuery
        query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData as String] = Data(String(date.timeIntervalSince1970).utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecDuplicateItem
    }
}
