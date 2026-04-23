//
//  RetroArchX.h
//  RetroGo
//
//  Created by haharsw on 2026/2/11.
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

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import <EmuCoreInfoItem.h>

NS_ASSUME_NONNULL_BEGIN

NS_ENUM(int, RetroArchJoypadCode) {
    RetroArchJoypadCodeNone   = -1,
    RetroArchJoypadCodeB      = 0,  /* RETRO_DEVICE_ID_JOYPAD_B */
    RetroArchJoypadCodeY      = 1,  /* RETRO_DEVICE_ID_JOYPAD_Y */
    RetroArchJoypadCodeSelect = 2,  /* RETRO_DEVICE_ID_JOYPAD_SELECT */
    RetroArchJoypadCodeStart  = 3,  /* RETRO_DEVICE_ID_JOYPAD_START */
    RetroArchJoypadCodeUp     = 4,  /* RETRO_DEVICE_ID_JOYPAD_UP */
    RetroArchJoypadCodeDown   = 5,  /* RETRO_DEVICE_ID_JOYPAD_DOWN */
    RetroArchJoypadCodeLeft   = 6,  /* RETRO_DEVICE_ID_JOYPAD_LEFT */
    RetroArchJoypadCodeRight  = 7,  /* RETRO_DEVICE_ID_JOYPAD_RIGHT */
    RetroArchJoypadCodeA      = 8,  /* RETRO_DEVICE_ID_JOYPAD_A */
    RetroArchJoypadCodeX      = 9,  /* RETRO_DEVICE_ID_JOYPAD_X */
    RetroArchJoypadCodeL1     = 10, /* RETRO_DEVICE_ID_JOYPAD_L */
    RetroArchJoypadCodeR1     = 11, /* RETRO_DEVICE_ID_JOYPAD_R */
    RetroArchJoypadCodeL2     = 12, /* RETRO_DEVICE_ID_JOYPAD_L2 */
    RetroArchJoypadCodeR2     = 13, /* RETRO_DEVICE_ID_JOYPAD_R2 */
    RetroArchJoypadCodeL3     = 14, /* RETRO_DEVICE_ID_JOYPAD_L3 */
    RetroArchJoypadCodeR3     = 15, /* RETRO_DEVICE_ID_JOYPAD_R3 */
};

NS_ENUM(unsigned, RetroArchJoypadAxis) {
    RetroArchJoypadAxisLeftX  = 0,
    RetroArchJoypadAxisLeftY  = 1,
    RetroArchJoypadAxisRightX = 2,
    RetroArchJoypadAxisRightY = 3
};

extern NSString * const RetroArchXReadyNotification;
typedef void (^RetroArchXEmuFrameCallback)(void);

@interface RetroArchX : NSObject
@property(nonatomic, strong, readonly) NSArray<UTType *> *allSupportedExtensions;
@property(nonatomic, strong, readonly) NSSet<NSString *> *allExtensionsSet;
@property(nonatomic, strong, readonly) NSArray<EmuCoreInfoItem *> *allCores;
@property(nonatomic, strong, nullable, readonly) EmuCoreInfoItem *currentCoreItem;
@property(nonatomic, assign, readonly) BOOL initialized;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)shared;

- (void)handleTouchEvent:(nullable NSSet<UITouch *> *)touches;
- (NSArray<EmuCoreInfoItem *> *)supportedCoresForRom:(NSString *)romPath;

- (BOOL)isCurrentCoreSupportsSavestate;
- (nullable NSString *)getCurrentRomPath;
- (BOOL)canRunOnThisDevice;

- (void)sendJoypadCode:(enum RetroArchJoypadCode)code down:(BOOL)down;
- (void)sendJoypadAxis:(enum RetroArchJoypadAxis)axis value:(CGFloat)value;
- (void)setFastForwardEnabled:(BOOL)enabled multiplier:(double)multiplier;
- (void)setFastForwardMultiplier:(double)multiplier;

- (NSString *)addEmuPrevFrameAction:(RetroArchXEmuFrameCallback)action;
- (void)removeEmuPrevFrameActionForToken:(NSString *)token;

- (void)start:(nullable NSString *)romPath core:(EmuCoreInfoItem *)core completion:(nullable void (^)(BOOL success))completion;
- (BOOL)stop;
- (BOOL)pause;
- (BOOL)resume;
- (BOOL)reset;
- (BOOL)mute:(BOOL)mute;
- (BOOL)saveStateTo:(NSString *)folder imageFolder:(nullable NSString *)imageFolder name:(NSString *)name;
- (BOOL)loadStateFrom:(NSString *)path;
- (BOOL)saveScreenshotTo:(NSString *)path notify:(BOOL)notify;

@end

NS_ASSUME_NONNULL_END
