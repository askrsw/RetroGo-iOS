//
//  RAInputBindingProfile.h
//  RetroMain
//
//  Created by haharsw on 2026/5/5.
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

#pragma mark - Enums

typedef NS_ENUM(NSInteger, RAInputBindingTargetKind) {
    RAInputBindingTargetKindUnknown         = 0,
    RAInputBindingTargetKindJoypadSingle    = 1, // one RetroArch joypad code
    RAInputBindingTargetKindJoypadComposite = 2, // multiple joypad codes (+ turbo flag)
    RAInputBindingTargetKindSystemAction    = 3, // fast-forward / mute ...
};

typedef NS_ENUM(NSInteger, RAInputSystemActionCode) {
    RAInputSystemActionCodeUnknown      = 0,
    RAInputSystemActionCodeFastForward  = 1,
    RAInputSystemActionCodeMute         = 2,
};

typedef NS_ENUM(NSInteger, RAInputPhysicalSourceKindCode) {
    RAInputPhysicalSourceKindCodeUnknown = 0,
    RAInputPhysicalSourceKindCodeButton  = 1, // sourceCode = joykey
    RAInputPhysicalSourceKindCodeAxis    = 2, // sourceCode = joyaxis (AXIS_POS/NEG encoded)
};

#pragma mark - Models

/// Physical input source: int-only representation.
@interface RAInputPhysicalSourceRef : NSObject <NSSecureCoding>
@property(nonatomic, assign) RAInputPhysicalSourceKindCode sourceKind;
@property(nonatomic, assign) NSInteger sourceCode;
@end

/// Target descriptor: supports single joypad, composite joypad, and system action.
@interface RAInputBindingTarget : NSObject <NSSecureCoding>
@property(nonatomic, assign) RAInputBindingTargetKind targetKind;

/// targetKind == JoypadSingle: joypadCodes.count must be 1
/// targetKind == JoypadComposite: joypadCodes.count >= 1
@property(nonatomic, copy) NSArray<NSNumber *> *joypadCodes; // RetroArchJoypadCode raw values

/// valid when targetKind == JoypadComposite (for turbo/combo behaviors)
@property(nonatomic, assign) BOOL turboEnabled;

/// valid when targetKind == SystemAction
@property(nonatomic, assign) RAInputSystemActionCode systemActionCode;
@end

/// One binding row for one player.
@interface RAInputBindingEntry : NSObject <NSSecureCoding>
@property(nonatomic, strong) RAInputBindingTarget *target;
@property(nonatomic, strong) RAInputPhysicalSourceRef *source;
@property(nonatomic, copy) NSString *actionId;
@end

/// Player-level bindings.
@interface RAInputPlayerBinding : NSObject <NSSecureCoding>
@property(nonatomic, assign) NSInteger port; // 0...3
@property(nonatomic, copy) NSArray<RAInputBindingEntry *> *entries;
@end

/// Whole profile for one game row in sqlite.
@interface RAInputBindingProfile : NSObject <NSSecureCoding>
@property(nonatomic, assign) NSInteger version; // start at 1
@property(nonatomic, copy) NSArray<RAInputPlayerBinding *> *players;

/// archive -> NSData (sqlite BLOB)
- (nullable NSData *)encodedData:(NSError **)error;

/// NSData -> profile
+ (nullable instancetype)decodeFromData:(NSData *)data error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
