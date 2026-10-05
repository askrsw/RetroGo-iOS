//
//  RetroGoLogger.swift
//  RetroGo
//
//  Unified logging (os.Logger). Subsystem is the bundle identifier; each module
//  has its own category so Console.app can filter by subsystem / category / level.
//
//  Levels:
//    debug  - per-frame / per-file details
//    info   - flow milestones
//    notice - noteworthy state changes
//    error  - failed but recoverable
//    fault  - should never happen
//
//  Privacy: interpolated values are private by default. Mark core IDs, error
//  codes and similar non-user data with `privacy: .public`; keep game file
//  names and paths private.
//
//  Category names must match retrogo_log.c in RetroMain/interface.
//

import Foundation
import os

enum RetroGoLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.retrogo"

    static let general    = Logger(subsystem: subsystem, category: "General")
    static let `import`   = Logger(subsystem: subsystem, category: "Import")
    static let cheat      = Logger(subsystem: subsystem, category: "Cheat")
    static let mame       = Logger(subsystem: subsystem, category: "Mame")
    static let iap        = Logger(subsystem: subsystem, category: "IAP")
    static let odr        = Logger(subsystem: subsystem, category: "ODR")
    static let game       = Logger(subsystem: subsystem, category: "Game")
    static let runner     = Logger(subsystem: subsystem, category: "Runner")
    static let coreOption = Logger(subsystem: subsystem, category: "CoreOption")
    static let database   = Logger(subsystem: subsystem, category: "Database")
    static let netplay    = Logger(subsystem: subsystem, category: "Netplay")
}
