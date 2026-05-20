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
#import "../input/RAInputBindingProfile.h"
#import "../input/RAInputActionManager.h"
#import "../virtual/virtual_joypad.h"

#include <gfx/video_driver.h>
#include <utils/configuration.h>
#include <main/runloop.h>
#include <audio/audio_driver.h>
#include <input/input_driver.h>
#include <defines/input_defines.h>
#include <string.h>

@interface RAInputDevice()
@property(nonatomic, readwrite, assign) NSInteger slot;
@property(nonatomic, readwrite, copy) NSString *name;
@property(nonatomic, readwrite, assign) NSInteger port;
@property(nonatomic, readwrite, assign) uint16_t vid;
@property(nonatomic, readwrite, assign) uint16_t pid;
@property(nonatomic, readwrite, assign) BOOL autoconfigured;
@property(nonatomic, readwrite, copy) NSString *joypadDriver;
@end

@implementation RAConfig
@end

@implementation RAInputDevice
@end

@implementation RAInputCoreCapabilities
@end

@implementation RetroArchX (Config)

- (void)config:(RAConfig *)cfg {
    video_driver_set_threaded(cfg.logicThread);

    [self setVirtualDevicePort:cfg.overlayTouchPlayer];

    settings_t *settings = config_get_ptr();
    if(settings != nil) {
        [self writeCString:settings->arrays.video_driver cap:sizeof(settings->arrays.video_driver) value:cfg.videoDriver];
        [self writeCString:settings->arrays.audio_driver cap:sizeof(settings->arrays.audio_driver) value:cfg.audioDriver];
        [self setMuteOnFastForward:cfg.muteOnFastForward];
    }

    [[RAInputActionManager shared] applyInputBindingProfile:cfg.inputBindingProfile coreCapabilities:cfg.coreCaps useLock:YES];
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

- (NSArray<RAInputDevice *> *)availableInputDevices {
    settings_t *settings = config_get_ptr();
    NSMutableArray<RAInputDevice *> *result = [NSMutableArray array];

    NSMutableDictionary<NSNumber *, NSNumber *> *deviceSlotToPlayerPort = [NSMutableDictionary dictionary];
    if (settings != nil) {
        for (unsigned playerPort = 0; playerPort < MAX_USERS; playerPort++) {
            unsigned deviceSlot = settings->uints.input_joypad_index[playerPort];
            if (deviceSlot < MAX_INPUT_DEVICES) {
                deviceSlotToPlayerPort[@(deviceSlot)] = @(playerPort);
            }
        }
    }

    for (unsigned deviceSlot = 0; deviceSlot < MAX_INPUT_DEVICES; deviceSlot++) {
        const char *displayName = input_config_get_device_display_name(deviceSlot);
        const char *name = input_config_get_device_name(deviceSlot);
        const char *resolvedName = (displayName != NULL && displayName[0] != '\0') ? displayName : name;
        if (resolvedName == NULL || resolvedName[0] == '\0') {
            continue;
        }

        NSString *deviceName = @(resolvedName);

        NSNumber *mappedPort = deviceSlotToPlayerPort[@(deviceSlot)];
        NSString *joypadDriver = @"";
        const char *rawJoypadDriver = input_config_get_device_joypad_driver(deviceSlot);
        if (rawJoypadDriver != NULL && rawJoypadDriver[0] != '\0') {
            joypadDriver = @(rawJoypadDriver);
        }

        RAInputDevice *device = [[RAInputDevice alloc] init];
        device.slot = (NSInteger)deviceSlot;
        device.name = deviceName;
        device.port = mappedPort != nil ? mappedPort.integerValue : -1;
        device.vid = input_config_get_device_vid(deviceSlot);
        device.pid = input_config_get_device_pid(deviceSlot);
        device.autoconfigured = input_config_get_device_autoconfigured(deviceSlot);
        device.joypadDriver = joypadDriver;
        [result addObject:device];
    }

    return result;
}

- (BOOL)setVirtualDevicePort:(int)port {
    if (port < 0 || port >= (int)MAX_USERS) {
        return NO;
    }
    return virtual_joypad_set_target_port((unsigned)port);
}

- (BOOL)setPhysicalDeviceSlot:(int)slot toPort:(int)port {
    settings_t *settings = config_get_ptr();
    if (settings == nil) {
        return NO;
    }
    if (port < 0 || port >= (int)MAX_USERS) {
        return NO;
    }
    if (slot < 0 || slot >= (int)MAX_INPUT_DEVICES) {
        return NO;
    }

    const char *displayName = input_config_get_device_display_name((unsigned)slot);
    const char *name = input_config_get_device_name((unsigned)slot);
    const char *resolvedName = (displayName != NULL && displayName[0] != '\0') ? displayName : name;
    if (resolvedName == NULL || resolvedName[0] == '\0') {
        return NO;
    }

    unsigned targetPort = (unsigned)port;
    unsigned targetSlot = (unsigned)slot;
    unsigned currentSlot = settings->uints.input_joypad_index[targetPort];

    if (currentSlot == targetSlot) {
        return YES;
    }

    int occupiedPort = -1;
    for (unsigned candidatePort = 0; candidatePort < MAX_USERS; candidatePort++) {
        if ((int)candidatePort == port) {
            continue;
        }
        if (settings->uints.input_joypad_index[candidatePort] == targetSlot) {
            occupiedPort = (int)candidatePort;
            break;
        }
    }

    settings->uints.input_joypad_index[targetPort] = targetSlot;
    if (occupiedPort >= 0) {
        settings->uints.input_joypad_index[(unsigned)occupiedPort] = currentSlot;
    }

    return YES;
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
