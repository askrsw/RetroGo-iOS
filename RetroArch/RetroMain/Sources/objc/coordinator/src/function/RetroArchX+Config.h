//
//  RetroArchX+Config.h
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

#import "../RetroArchX.h"

NS_ASSUME_NONNULL_BEGIN

@class RAInputBindingProfile;

@interface RAInputDevice : NSObject
@property(nonatomic, readonly, assign) NSInteger slot;
@property(nonatomic, readonly, copy) NSString *name;
@property(nonatomic, readonly, assign) NSInteger port;
@property(nonatomic, readonly, assign) uint16_t vid;
@property(nonatomic, readonly, assign) uint16_t pid;
@property(nonatomic, readonly, assign) BOOL autoconfigured;
@property(nonatomic, readonly, copy) NSString *joypadDriver;
@end

@interface RAInputCoreCapabilities : NSObject
@property(nonatomic, assign) BOOL allowsDefaultTurboXYHijack;
@property(nonatomic, assign) BOOL supportsAnalog;
@end

@interface RAConfig : NSObject
@property(nonatomic, copy, nullable) NSString *coreOptionsCoreId;
@property(nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *coreOptions;
@property(nonatomic, assign) BOOL logicThread;
@property(nonatomic, copy)   NSString *videoDriver;
@property(nonatomic, copy)   NSString *audioDriver;
@property(nonatomic, assign) double fastForwardMultiplier;
@property(nonatomic, assign) BOOL   muteOnFastForward;
@property(nonatomic, assign) int    overlayTouchPlayer;
@property(nonatomic, assign) BOOL   overlayTurboTapLatch;
@property(nonatomic, assign) int    overlayTurboSpeedTier;
/// Device type for every port, by name (e.g. "dualshock"); nil or empty for the standard RetroPad.
@property(nonatomic, copy, nullable) NSString *portDevice;

@property(nonatomic, strong, nullable) RAInputCoreCapabilities *coreCaps;
@property(nonatomic, strong, nullable) RAInputBindingProfile *inputBindingProfile;
@end

@interface RetroArchX (Config)
// RETRO_LANGUAGE_* matching the App language (English or Simplified Chinese).
+ (unsigned)appRetroLanguage;
- (void)config:(RAConfig *)cfg;

/// Frontend and core log levels: INFO in Debug builds, WARN in Release builds.
/// Call after RetroArch loads its settings, which may reset them.
- (void)applyLogLevels;
- (BOOL)prepareCoreOptionsForCoreId:(NSString *)coreId;
- (void)clearCoreOptionConfiguration;
// Applies a value to the running core from its next frame; also kept for re-registration.
- (BOOL)updateRunningCoreOption:(NSString *)value forKey:(NSString *)key;
// Snapshot of the core options registered by the running core, for offline JSON export.
- (nullable NSDictionary<NSString *, id> *)debugCurrentCoreOptionsSnapshot;
- (void)setFastForwardMultiplier:(double)multiplier;
- (void)setMuteOnFastForward:(BOOL)value;
/// Whether the phone rumbles when the game asks for it, for the player on the on-screen controls.
- (void)setPhoneRumbleEnabled:(BOOL)enabled;

- (NSString *)defaultVideoDriver;
- (NSArray<NSString *> *)availableVideoDrivers;
- (NSString *)defaultAudioDriver;
- (NSArray<NSString *> *)availableAudioDrivers;
- (NSArray<RAInputDevice *> *)availableInputDevices;
- (BOOL)setVirtualDevicePort:(int)port;
- (BOOL)setPhysicalDeviceSlot:(int)slot toPort:(int)port;
@end

NS_ASSUME_NONNULL_END
