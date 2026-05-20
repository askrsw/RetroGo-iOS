//
//  RAInputActionManager.h
//  RetroGo
//
//  Created by Codex on 2026/4/30.
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
#import "../RetroArchX.h"
#import "../function/RetroArchX+Config.h"

#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

@class RAInputPhysicalSource;
@class RAInputBindingProfile;

typedef NS_ENUM(NSInteger, RAInputActionKind) {
    RAInputActionKindJoypadOutput = 0,
    RAInputActionKindFastForward,
};

typedef NS_ENUM(NSInteger, RAInputActionHandlingResult) {
    RAInputActionHandlingResultIgnored = 0,
    RAInputActionHandlingResultHandled,
};

typedef NS_ENUM(NSInteger, RAInputPhysicalSourceKind) {
    RAInputPhysicalSourceKindButton = 0,
    RAInputPhysicalSourceKindAxis,
};

typedef BOOL (^RAInputPhysicalSourcePressHandler)(RAInputPhysicalSource *source);
typedef double (^RAInputFastForwardMultiplierProvider)(void);
typedef void (^RAInputTopologyChangedHandler)(void);

@interface RAInputActionDescriptor : NSObject <NSCopying>
@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *displayName;
@property(nonatomic, assign, readonly) RAInputActionKind kind;
@property(nonatomic, copy, readonly) NSArray<NSNumber *> *outputJoypadCodes;
@property(nonatomic, assign, readonly) BOOL turboEnabled;

+ (instancetype)joypadOutputActionWithIdentifier:(NSString *)identifier displayName:(NSString *)displayName outputJoypadCodes:(NSArray<NSNumber *> *)outputJoypadCodes turboEnabled:(BOOL)turboEnabled;
+ (instancetype)comboActionWithIdentifier:(NSString *)identifier displayName:(NSString *)displayName outputJoypadCodes:(NSArray<NSNumber *> *)outputJoypadCodes;
+ (instancetype)comboActionWithIdentifier:(NSString *)identifier displayName:(NSString *)displayName outputJoypadCodes:(NSArray<NSNumber *> *)outputJoypadCodes turboEnabled:(BOOL)turboEnabled;
+ (instancetype)turboActionWithIdentifier:(NSString *)identifier displayName:(NSString *)displayName outputJoypadCodes:(NSArray<NSNumber *> *)outputJoypadCodes;
+ (instancetype)fastForwardActionWithIdentifier:(NSString *)identifier displayName:(NSString *)displayName;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface RAInputPhysicalSource : NSObject <NSCopying>
@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *displayName;
@property(nonatomic, assign, readonly) NSInteger playerIndex;
@property(nonatomic, assign, readonly) RAInputPhysicalSourceKind kind;
@property(nonatomic, assign, readonly) uint16_t joykey;
@property(nonatomic, assign, readonly) uint32_t joyaxis;
@property(nonatomic, assign, readonly) float axisValue;

+ (instancetype)sourceWithIdentifier:(NSString *)identifier displayName:(NSString *)displayName playerIndex:(NSInteger)playerIndex;
+ (instancetype)buttonSourceWithJoykey:(uint16_t)joykey displayName:(NSString *)displayName playerIndex:(NSInteger)playerIndex;
+ (instancetype)axisSourceWithJoyaxis:(uint32_t)joyaxis displayName:(NSString *)displayName playerIndex:(NSInteger)playerIndex;
+ (instancetype)axisSourceWithJoyaxis:(uint32_t)joyaxis axisValue:(float)axisValue displayName:(NSString *)displayName playerIndex:(NSInteger)playerIndex;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface RAInputActionManager : NSObject
@property(nonatomic, copy, nullable) RAInputPhysicalSourcePressHandler physicalSourcePressHandler;
@property(nonatomic, copy, nullable) RAInputFastForwardMultiplierProvider fastForwardMultiplierProvider;
@property(nonatomic, copy, nullable) RAInputTopologyChangedHandler topologyChangedHandler;
@property(nonatomic, assign) NSUInteger turboPeriodFrames;
@property(nonatomic, assign) NSUInteger turboDutyFrames;
@property(nonatomic, assign) BOOL allowsAxisSuppression;

+ (instancetype)shared;
- (instancetype)init NS_UNAVAILABLE;

- (void)applyInputBindingProfile:(nullable RAInputBindingProfile *)profile coreCapabilities:(nullable RAInputCoreCapabilities *)capabilities useLock:(BOOL)useLock;
- (void)tickFrame:(BOOL)useLock;

- (void)beginCoreTeardownGuard;
- (void)endCoreTeardownGuard;
@end

NS_ASSUME_NONNULL_END
