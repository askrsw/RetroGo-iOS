//
//  RetroArchX+Config.m
//  RetroGo
//
//  Created by haharsw on 2026/4/19.
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

#import "RetroArchX+Config.h"

#include <gfx/video_driver.h>
#include <utils/configuration.h>
#include <main/runloop.h>
#include <audio/audio_driver.h>
#include <string.h>

@implementation RetroArchConfig
@end

@implementation RetroArchX (Config)

- (void)config:(RetroArchConfig *)cfg {
    video_driver_set_threaded(cfg.logicThread);

    settings_t *settings = config_get_ptr();
    if(settings != nil) {
        [self writeCString:settings->arrays.video_driver cap:sizeof(settings->arrays.video_driver) value:cfg.videoDriver];
        [self writeCString:settings->arrays.audio_driver cap:sizeof(settings->arrays.audio_driver) value:cfg.audioDriver];
        [self setMuteOnFastForward:cfg.muteOnFastForward];
    }
}

- (void)setFastForwardMultiplier:(double)multiplier {
    if (self.currentCoreItem == nil || self.gameLogicRunner == nil) {
        return;
    }

    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.gameLogicRunner setFastForwardMultiplier:multiplier];
        });
        return;
    } else {
        [self.gameLogicRunner setFastForwardMultiplier:multiplier];
    }
}

- (void)setMuteOnFastForward:(BOOL)value {
    settings_t *settings = config_get_ptr();
    if (settings == nil) {
        return;
    }

    settings->bools.audio_fastforward_mute = value;
    [self applyFastForwardMuteState:value];
}

- (NSArray<NSString *> *)availableVideoDrivers {
    const char *rawOptions = config_get_video_driver_options();
    if (rawOptions == NULL || rawOptions[0] == '\0') {
        return @[];
    }

    NSString *options = @(rawOptions);
    return [self convertDriverStringToArray:options];
}

- (NSString *)defaultVideoDriver {
    const char *ident = config_get_default_video();
    if (ident == NULL || ident[0] == '\0') {
        return @"";
    }
    return @(ident);
}

- (NSArray<NSString *> *)availableAudioDrivers {
    const char *rawOptions = config_get_audio_driver_options();
    if (rawOptions == NULL || rawOptions[0] == '\0') {
        return @[];
    }

    NSString *options = @(rawOptions);
    return [self convertDriverStringToArray:options];
}

- (NSString *)defaultAudioDriver {
    const char *ident = config_get_default_audio();
    if (ident == NULL || ident[0] == '\0') {
        return @"";
    }
    return @(ident);
}

#pragma mark - Utils

- (void)applyFastForwardMuteState:(BOOL)muteOnFastForward {
    runloop_state_t *runloop_st = runloop_state_get_ptr();
    audio_driver_state_t *audio_st = audio_state_get_ptr();
    if (runloop_st == nil || audio_st == nil) {
        return;
    }

    if ((runloop_st->flags & RUNLOOP_FLAG_FASTMOTION) == 0) {
        return;
    }

    if (muteOnFastForward) {
        audio_st->flags |= AUDIO_FLAG_MUTED;
    } else {
        audio_st->flags &= ~AUDIO_FLAG_MUTED;
    }
}

- (void)writeCString:(char *)dst cap:(size_t)cap value:(NSString *)value {
    if (!dst || cap == 0) return;
    memset(dst, 0, cap);
    if (value.length == 0) return;
    const char *src = value.UTF8String;
    if (!src) return;
    strncpy(dst, src, cap - 1);
    dst[cap - 1] = '\0';
}

- (NSArray<NSString *> *)convertDriverStringToArray:(NSString *)options {
    NSArray<NSString *> *parts = [options componentsSeparatedByString:@"|"];
    NSMutableArray<NSString *> *result = [NSMutableArray array];

    for (NSString *item in parts) {
        NSString *trimmed = [item stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length == 0) {
            continue;
        }
        if (![result containsObject:trimmed]) {
            [result addObject:trimmed];
        }
    }

    return [result copy];
}

@end
