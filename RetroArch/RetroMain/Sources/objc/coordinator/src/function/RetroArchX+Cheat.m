//
//  RetroArchX+Cheat.m
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

// Resolves (same-directory first) to the internal src/function/RetroArchX+Cheat.h,
// which pulls in the internal RetroArchX.h exposing `gameLogicRunner`.
#import "RetroArchX+Cheat.h"

#include <string.h>
#include <core/core.h>
#include <main/runloop.h>
#include <emu/cheat_manager.h>

@implementation RACheatItem

- (instancetype)init {
    self = [super init];
    if (self) {
        // Defaults mirror cheat_manager_realloc's per-item defaults, so a plain
        // EMU item still carries valid RETRO fields.
        _handler            = RACheatHandlerEMU;
        _desc               = @"";
        _code               = @"";
        _enabled            = NO;
        _cheatType          = 1;  // CHEAT_TYPE_SET_TO_VALUE
        _memorySearchSize   = 3;  // 8-bit / 1 byte
        _repeatCount        = 1;
        _repeatAddToAddress = 1;
    }
    return self;
}

- (instancetype)initWithDesc:(NSString *)desc
                        code:(NSString *)code
                     enabled:(BOOL)enabled {
    self = [self init];
    if (self) {
        _handler = RACheatHandlerEMU;
        _desc    = [desc copy];
        _code    = [code copy];
        _enabled = enabled;
    }
    return self;
}

@end

@implementation RetroArchX (Cheat)

- (BOOL)cheatSupported {
    runloop_state_t *st = runloop_state_get_ptr();
    return st != NULL && st->current_core.retro_cheat_set != NULL;
}

// Runs `block` (which mutates the global `cheat_manager_state` and/or calls into
// the core) safely with respect to the game loop. When the loop is live the
// mutation is marshalled onto the logic thread between frames so it never races
// `retro_run`; when there is no runner (no game) it runs inline.
- (void)ra_performCheatMutation:(void (^)(void))block {
    if (block == nil) {
        return;
    }
    id<RAGameLoopRunner> runner = self.gameLogicRunner;
    if (runner != nil) {
        [runner suspendGameLoopAndPerformSync:^NSObject * _Nullable {
            block();
            return nil;
        } runOnLogicThread:YES];
    } else {
        block();
    }
}

- (NSArray<RACheatItem *> *)currentCheats {
    NSMutableArray<RACheatItem *> *result = [NSMutableArray array];
    unsigned count = cheat_manager_get_size();
    for (unsigned i = 0; i < count; i++) {
        struct item_cheat *c = &cheat_manager_state.cheats[i];

        RACheatItem *item = [[RACheatItem alloc] init];
        item.handler            = (RACheatHandler)c->handler;
        item.desc               = c->desc ? @(c->desc) : @"";
        item.code               = c->code ? @(c->code) : @"";
        item.enabled            = c->state;
        item.cheatType          = c->cheat_type;
        item.memorySearchSize   = c->memory_search_size;
        item.address            = c->address;
        item.value              = c->value;
        item.addressMask        = c->address_mask;
        item.bigEndian          = c->big_endian;
        item.repeatCount        = c->repeat_count;
        item.repeatAddToValue   = c->repeat_add_to_value;
        item.repeatAddToAddress = c->repeat_add_to_address;
        item.rumbleType              = c->rumble_type;
        item.rumbleValue             = c->rumble_value;
        item.rumblePort              = c->rumble_port;
        item.rumblePrimaryStrength   = c->rumble_primary_strength;
        item.rumblePrimaryDuration   = c->rumble_primary_duration;
        item.rumbleSecondaryStrength = c->rumble_secondary_strength;
        item.rumbleSecondaryDuration = c->rumble_secondary_duration;

        [result addObject:item];
    }
    return result;
}

- (BOOL)setCheats:(NSArray<RACheatItem *> *)items apply:(BOOL)apply {
    if (self.currentCoreItem == nil) {
        return NO;
    }
    __block BOOL ok = NO;
    [self ra_performCheatMutation:^{
        unsigned n = (unsigned)items.count;

        // realloc(0) intentionally returns false while leaving the manager empty;
        // only treat a non-empty alloc failure as an error.
        BOOL alloced = cheat_manager_realloc(n, CHEAT_HANDLER_TYPE_EMU);
        if (n > 0 && !alloced) {
            ok = NO;
            return;
        }
        if (n == 0) {
            // cheat_manager_apply_cheats() returns early when the manager has no
            // backing array, so reset the core explicitly. This clears enabled
            // EMU cheats from the previous snapshot without touching Swift
            // persistence.
            if (apply) {
                core_reset_cheat();
            }
            ok = YES;
            return;
        }

        for (unsigned i = 0; i < n; i++) {
            RACheatItem *item    = items[i];
            struct item_cheat *c = &cheat_manager_state.cheats[i];

            if (c->desc) { free(c->desc); c->desc = NULL; }
            if (c->code) { free(c->code); c->code = NULL; }

            const char *desc = item.desc.UTF8String ?: "";
            const char *code = item.code.UTF8String ?: "";
            c->desc = strdup(desc);
            c->code = strdup(code);

            c->state                 = item.enabled;
            c->handler               = (unsigned)item.handler;
            c->cheat_type            = (unsigned)item.cheatType;
            c->memory_search_size    = (unsigned)item.memorySearchSize;
            c->address               = (unsigned)item.address;
            c->value                 = (unsigned)item.value;
            c->address_mask          = (unsigned)item.addressMask;
            c->big_endian            = item.bigEndian;
            c->repeat_count          = (unsigned)item.repeatCount;
            c->repeat_add_to_value   = (unsigned)item.repeatAddToValue;
            c->repeat_add_to_address = (unsigned)item.repeatAddToAddress;

            // Reserved (not applied in 1.6.0; see header). Stored so the engine
            // round-trips them if ever read back.
            c->rumble_type               = (unsigned)item.rumbleType;
            c->rumble_value              = (unsigned)item.rumbleValue;
            c->rumble_port               = (unsigned)item.rumblePort;
            c->rumble_primary_strength   = (unsigned)item.rumblePrimaryStrength;
            c->rumble_primary_duration   = (unsigned)item.rumblePrimaryDuration;
            c->rumble_secondary_strength = (unsigned)item.rumbleSecondaryStrength;
            c->rumble_secondary_duration = (unsigned)item.rumbleSecondaryDuration;
        }

        if (apply) {
            // Pushes enabled EMU cheats (or resets the core's cheats when empty).
            // RETRO cheats then apply automatically each frame via runloop_iterate.
            cheat_manager_apply_cheats(false);
        }
        ok = YES;
    }];
    return ok;
}

- (BOOL)setCheatEnabled:(BOOL)enabled atIndex:(NSUInteger)index {
    if (self.currentCoreItem == nil) {
        return NO;
    }
    __block BOOL ok = NO;
    [self ra_performCheatMutation:^{
        if (index >= cheat_manager_get_size()) {
            ok = NO;
            return;
        }
        cheat_manager_state.cheats[index].state = enabled;
        cheat_manager_apply_cheats(false);
        ok = YES;
    }];
    return ok;
}

- (void)applyCheats {
    if (self.currentCoreItem == nil) {
        return;
    }
    [self ra_performCheatMutation:^{
        cheat_manager_apply_cheats(false);
    }];
}

- (void)clearCheats {
    // Safe to call even after the game stopped (runner/content gone) — frees the
    // global cheat list inline in that case.
    [self ra_performCheatMutation:^{
        cheat_manager_state_free();
    }];
}

@end
