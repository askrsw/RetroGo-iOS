//
//  RAMameCheatEngine.h
//  RetroGo
//
//  Created by haharsw on 2026/9/27.
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Mirrors the kinds reported by `retrogo_mame_cheat_kind` (MAME's cheat_entry::is_*).
typedef NS_ENUM(NSInteger, RAMameCheatKind) {
    /// Description only: a heading, separator or note. Cannot be switched on.
    RAMameCheatKindText             = 0,
    /// Runs once when activated; has no on/off state.
    RAMameCheatKindOneShot          = 1,
    /// Toggled on/off.
    RAMameCheatKindOnOff            = 2,
    /// On at a chosen value (item list or min/max/step range), or off.
    RAMameCheatKindParameter        = 3,
    /// Pick a value, then activate to apply it once.
    RAMameCheatKindOneShotParameter = 4,
};

/// Snapshot of one entry of MAME's native cheat engine, in engine order.
@interface RAMameCheatEntry : NSObject
@property(nonatomic, assign, readonly) NSInteger index;
@property(nonatomic, assign, readonly) RAMameCheatKind kind;
@property(nonatomic, copy, readonly) NSString *desc;
@property(nonatomic, assign, readonly) BOOL enabled;
/// 0-based item index, or steps from the minimum; -1 for non-parameter entries.
@property(nonatomic, assign, readonly) NSInteger parameterPosition;
@end

/// Talks to the MAME core's own cheat engine through the `retrogo_mame_cheat_*` exports.
/// Cheats come from the XML handed over with `setCheatXML:` (MAME's `<cheatpath>/<set>.xml`
/// only when none is set) and load when the machine starts or on `reload`.
/// Changes are queued inside the core and applied at the start of the next frame on the
/// emulation thread, so reading back right after a change still returns the old state.
@interface RAMameCheatEngine : NSObject

/// Engine bound to the currently loaded core, or nil when it is not a MAME core with the
/// cheat exports (e.g. an older core build).
+ (nullable instancetype)engineForLoadedCore NS_SWIFT_NAME(forLoadedCore());

/// -1 while the engine is off or the machine is not running yet; 0 when no file loaded.
@property(nonatomic, assign, readonly) NSInteger count;

- (NSArray<RAMameCheatEntry *> *)entries;

/// On/off entries toggle; disabling also turns parameter entries off.
- (BOOL)setEnabled:(BOOL)enabled atIndex:(NSInteger)index;
/// Switches a parameter entry on at `position` (see `parameterPosition`).
- (BOOL)setParameterPosition:(NSInteger)position atIndex:(NSInteger)index;
/// Runs a one-shot entry, or applies a one-shot parameter entry at its current position.
- (BOOL)activateAtIndex:(NSInteger)index;

/// Cheat XML used from the next `reload` (or machine start) on; nil clears it. The core keeps
/// it for the whole process, so clear it when the game ends.
- (void)setCheatXML:(nullable NSData *)xml;
/// Reloads the cheats of the running machine at the start of the next frame; every entry is
/// off again and pending changes are dropped. NO when no machine runs.
- (BOOL)reload;
/// Increases each time the core (re)loaded its cheat list; when it passes the value read
/// before `reload`, the new cheats are in.
@property(nonatomic, assign, readonly) NSUInteger loadGeneration;

@end

NS_ASSUME_NONNULL_END
