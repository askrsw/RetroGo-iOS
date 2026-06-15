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

// Internal mirror of include/RetroArchX+Cheat.h. Imports the *internal*
// RetroArchX.h ("../RetroArchX.h") so the .m can reach `gameLogicRunner` /
// `suspendGameLoopAndPerformSync:` (not exposed publicly). Public and internal
// headers are never imported into the same translation unit, so the duplicated
// declarations do not clash.

#import "../RetroArchX.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, RACheatHandler) {
    RACheatHandlerEMU   = 0,
    RACheatHandlerRETRO = 1,
};

@interface RACheatItem : NSObject

@property(nonatomic, assign) RACheatHandler handler;
@property(nonatomic, copy)   NSString      *desc;
@property(nonatomic, assign) BOOL           enabled;

@property(nonatomic, assign) NSInteger catalogId;
@property(nonatomic, assign) NSInteger catalogGameId;
@property(nonatomic, assign) NSInteger catalogIndex;
@property(nonatomic, assign) NSInteger catalogDescId;
@property(nonatomic, copy, nullable) NSString *descEnglish;
@property(nonatomic, assign) NSInteger descSource;

@property(nonatomic, copy)   NSString      *code;

@property(nonatomic, assign) NSUInteger cheatType;
@property(nonatomic, assign) NSUInteger memorySearchSize;
@property(nonatomic, assign) NSUInteger address;
@property(nonatomic, assign) NSUInteger value;
@property(nonatomic, assign) NSUInteger addressMask;
@property(nonatomic, assign) BOOL       bigEndian;
@property(nonatomic, assign) NSUInteger repeatCount;
@property(nonatomic, assign) NSUInteger repeatAddToValue;
@property(nonatomic, assign) NSUInteger repeatAddToAddress;

@property(nonatomic, assign) NSUInteger rumbleType;
@property(nonatomic, assign) NSUInteger rumbleValue;
@property(nonatomic, assign) NSUInteger rumblePort;
@property(nonatomic, assign) NSUInteger rumblePrimaryStrength;
@property(nonatomic, assign) NSUInteger rumblePrimaryDuration;
@property(nonatomic, assign) NSUInteger rumbleSecondaryStrength;
@property(nonatomic, assign) NSUInteger rumbleSecondaryDuration;

- (instancetype)initWithDesc:(NSString *)desc
                        code:(NSString *)code
                     enabled:(BOOL)enabled;

@end

@interface RetroArchX (Cheat)

@property(nonatomic, assign, readonly) BOOL cheatSupported;

- (NSArray<RACheatItem *> *)currentCheats;
- (BOOL)setCheats:(NSArray<RACheatItem *> *)items apply:(BOOL)apply;
- (BOOL)setCheatEnabled:(BOOL)enabled atIndex:(NSUInteger)index;
- (void)applyCheats;
- (void)clearCheats;

@end

NS_ASSUME_NONNULL_END
