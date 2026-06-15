//
//  RetroArchX+Cheat.h
//  RetroMain
//
//  Created by haharsw on 2026/6/6.
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

#import "RetroArchX.h"

NS_ASSUME_NONNULL_BEGIN

/// Which mechanism applies the cheat. Mirrors `CHEAT_HANDLER_TYPE_*`.
typedef NS_ENUM(NSUInteger, RACheatHandler) {
    /// Code string handed verbatim to the core (`retro_cheat_set`): Game Genie,
    /// PAR, raw "address:value", multiple sub-codes joined by `+`. Only `code`
    /// (and `desc`/`enabled`) are meaningful.
    RACheatHandlerEMU   = 0,
    /// RetroArch writes emulated memory itself every frame. The structured fields
    /// (`address`/`value`/`cheatType`/`memorySearchSize`/…) drive it.
    RACheatHandlerRETRO = 1,
};

/// A full mirror of `struct item_cheat`, so Swift never touches the C state
/// directly. EMU cheats use only `code`; RETRO cheats use the structured fields.
/// The `rumble*` fields are mapped 1:1 for forward-compat but are NOT surfaced or
/// applied in 1.6.0 (the on-screen-pad rumble sink — `virtual_joypad_rumble` — is
/// still a stub). Keeping them here means enabling rumble later needs no model or
/// DB migration.
@interface RACheatItem : NSObject

// Common
@property(nonatomic, assign) RACheatHandler handler;
@property(nonatomic, copy)   NSString      *desc;
@property(nonatomic, assign) BOOL           enabled;

// Optional metadata populated by RACheatCatalogManager. The cheat engine ignores
// these fields; they exist so catalog rows can stay as RACheatItem instead of a
// parallel database-only model.
@property(nonatomic, assign) NSInteger catalogId;
@property(nonatomic, assign) NSInteger catalogGameId;
@property(nonatomic, assign) NSInteger catalogIndex;
@property(nonatomic, assign) NSInteger catalogDescId;
@property(nonatomic, copy, nullable) NSString *descEnglish;
@property(nonatomic, assign) NSInteger descSource; // desc_i18n source enum, 0 when not localized

// EMU
@property(nonatomic, copy)   NSString      *code;

// RETRO (structured memory write)
@property(nonatomic, assign) NSUInteger cheatType;          // enum cheat_type (1=SET_TO_VALUE …)
@property(nonatomic, assign) NSUInteger memorySearchSize;   // 0..5 → 1/2/4/8/16/32 bit
@property(nonatomic, assign) NSUInteger address;
@property(nonatomic, assign) NSUInteger value;
@property(nonatomic, assign) NSUInteger addressMask;        // used when size < 8 bit
@property(nonatomic, assign) BOOL       bigEndian;
@property(nonatomic, assign) NSUInteger repeatCount;        // apply to N consecutive addresses
@property(nonatomic, assign) NSUInteger repeatAddToValue;
@property(nonatomic, assign) NSUInteger repeatAddToAddress;

// Rumble config (reserved — not applied in 1.6.0). Runtime rumble state
// (prev_value/initialized/end_times) is intentionally NOT mirrored here.
@property(nonatomic, assign) NSUInteger rumbleType;
@property(nonatomic, assign) NSUInteger rumbleValue;
@property(nonatomic, assign) NSUInteger rumblePort;
@property(nonatomic, assign) NSUInteger rumblePrimaryStrength;
@property(nonatomic, assign) NSUInteger rumblePrimaryDuration;
@property(nonatomic, assign) NSUInteger rumbleSecondaryStrength;
@property(nonatomic, assign) NSUInteger rumbleSecondaryDuration;

/// Convenience for the common EMU case.
- (instancetype)initWithDesc:(NSString *)desc
                        code:(NSString *)code
                     enabled:(BOOL)enabled;

@end

@interface RetroArchX (Cheat)

/// YES when the running core implements `retro_cheat_set` (EMU cheats can apply).
/// RETRO cheats additionally need the core to expose memory; that is resolved
/// lazily by the engine on first apply.
@property(nonatomic, assign, readonly) BOOL cheatSupported;

/// Snapshot of the cheats currently held by the engine, in order.
- (NSArray<RACheatItem *> *)currentCheats;

/// Replaces the engine cheat list with `items`. Each item is written with its own
/// `handler` and fields. When `apply` is YES the EMU cheats are pushed to the core
/// immediately; RETRO cheats then take effect automatically each frame.
///
/// Safe whether or not the loop is running (mutation runs on the logic thread
/// between frames). Returns NO only on allocation failure or no content loaded.
- (BOOL)setCheats:(NSArray<RACheatItem *> *)items apply:(BOOL)apply;

/// Toggles one cheat's enabled flag (by index) and re-applies.
- (BOOL)setCheatEnabled:(BOOL)enabled atIndex:(NSUInteger)index;

/// Re-pushes the enabled EMU cheats to the core. No-op when no content is loaded.
- (void)applyCheats;

/// Frees every cheat held by the engine. Does NOT touch Swift-side persistence.
- (void)clearCheats;

@end

NS_ASSUME_NONNULL_END
