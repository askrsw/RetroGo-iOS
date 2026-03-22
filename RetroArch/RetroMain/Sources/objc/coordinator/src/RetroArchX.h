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

NS_ASSUME_NONNULL_BEGIN

@class EmuCoreInfoItem;

@interface RetroArchX : NSObject
@property(nonatomic, strong, nullable, readonly) CADisplayLink *displayLink;
@property(nonatomic, strong, readonly) NSArray<UTType *> *allSupportedExtensions;
@property(nonatomic, strong, readonly) NSSet<NSString *> *allExtensionsSet;
@property(nonatomic, strong, readonly) NSArray<EmuCoreInfoItem *> *allCores;
@property(nonatomic, strong, nullable, readonly) EmuCoreInfoItem *currentCoreItem;
@property(nonatomic, assign, readonly) BOOL initialized;

+ (instancetype)shared;
- (instancetype)init NS_UNAVAILABLE;

- (void)handleTouchEvent:(nullable NSSet<UITouch *> *)touches;
- (NSArray<EmuCoreInfoItem *> *)supportedCoresForRom:(NSString *)romPath;

- (BOOL)isCurrentCoreSupportsSavestate;
- (nullable NSString *)getCurrentRomPath;
- (BOOL)canRunOnThisDevice;

#pragma mark - Core Control
- (void)start:(nullable NSString *)romPath core:(EmuCoreInfoItem *)core completion:(nullable void (^)(BOOL success))completion;
- (BOOL)close;
- (BOOL)pause;
- (BOOL)resume;
- (BOOL)restart;
- (BOOL)saveStateTo:(NSString *)folder imageFolder:(nullable NSString *)imageFolder name:(NSString *)name;
- (BOOL)loadStateFrom:(NSString *)path;
- (BOOL)saveScreenshotTo:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
