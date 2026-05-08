//
//  RAInputBindingProfile.m
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

#import "RAInputBindingProfile.h"
#import "../RetroArchX.h"

#include <defines/input_defines.h>

static NSString *RAInputPhysicalSourceKindCodeString(RAInputPhysicalSourceKindCode kind) {
    switch (kind) {
        case RAInputPhysicalSourceKindCodeButton: return @"button";
        case RAInputPhysicalSourceKindCodeAxis:   return @"axis";
        case RAInputPhysicalSourceKindCodeUnknown:
        default:                                  return @"unknown";
    }
}

static NSString *RAInputBindingTargetKindString(RAInputBindingTargetKind kind) {
    switch (kind) {
        case RAInputBindingTargetKindJoypadSingle:    return @"joypad_single";
        case RAInputBindingTargetKindJoypadComposite: return @"joypad_composite";
        case RAInputBindingTargetKindSystemAction:    return @"system_action";
        case RAInputBindingTargetKindUnknown:
        default:                                      return @"unknown";
    }
}

static NSString *RAInputSystemActionCodeString(RAInputSystemActionCode code) {
    switch (code) {
        case RAInputSystemActionCodeFastForward: return @"fast_forward";
        case RAInputSystemActionCodeMute:        return @"mute";
        case RAInputSystemActionCodeUnknown:
        default:                                 return @"unknown";
    }
}

static NSString *RAInputJoypadCodeString(NSInteger code) {
    switch ((enum RetroArchJoypadCode)code) {
        case RetroArchJoypadCodeB:      return @"B";
        case RetroArchJoypadCodeY:      return @"Y";
        case RetroArchJoypadCodeSelect: return @"Select";
        case RetroArchJoypadCodeStart:  return @"Start";
        case RetroArchJoypadCodeUp:     return @"Up";
        case RetroArchJoypadCodeDown:   return @"Down";
        case RetroArchJoypadCodeLeft:   return @"Left";
        case RetroArchJoypadCodeRight:  return @"Right";
        case RetroArchJoypadCodeA:      return @"A";
        case RetroArchJoypadCodeX:      return @"X";
        case RetroArchJoypadCodeL1:     return @"L1";
        case RetroArchJoypadCodeR1:     return @"R1";
        case RetroArchJoypadCodeL2:     return @"L2";
        case RetroArchJoypadCodeR2:     return @"R2";
        case RetroArchJoypadCodeL3:     return @"L3";
        case RetroArchJoypadCodeR3:     return @"R3";
        case RetroArchJoypadCodeNone:   return @"None";
        default:                        return [NSString stringWithFormat:@"Joypad(%ld)", (long)code];
    }
}

static NSString *RAInputJoyaxisString(NSInteger axisCode) {
    uint32_t joyaxis = (uint32_t)axisCode;
    BOOL isNegative = AXIS_NEG_GET(joyaxis) != 0xFFFFU;
    BOOL isPositive = AXIS_POS_GET(joyaxis) != 0xFFFFU;

    if (!isNegative && !isPositive) {
        return [NSString stringWithFormat:@"Axis(raw:%u)", joyaxis];
    }

    uint32_t axis = isNegative ? AXIS_NEG_GET(joyaxis) : AXIS_POS_GET(joyaxis);

    switch (axis) {
        case 0: return isNegative ? @"L-Stick-Left"  : @"L-Stick-Right";
        case 1: return isNegative ? @"L-Stick-Down"  : @"L-Stick-Up";
        case 2: return isNegative ? @"R-Stick-Left"  : @"R-Stick-Right";
        case 3: return isNegative ? @"R-Stick-Down"  : @"R-Stick-Up";
        case 4: return isNegative ? @"L2-Axis-Neg"   : @"L2-Axis-Pos";
        case 5: return isNegative ? @"R2-Axis-Neg"   : @"R2-Axis-Pos";
        default:
            return [NSString stringWithFormat:@"Axis%u-%@", axis, isNegative ? @"Neg" : @"Pos"];
    }
}

static NSString *RAInputPhysicalSourceCodeString(RAInputPhysicalSourceKindCode kind, NSInteger sourceCode) {
    switch (kind) {
        case RAInputPhysicalSourceKindCodeButton:
            return RAInputJoypadCodeString(sourceCode);
        case RAInputPhysicalSourceKindCodeAxis:
            return RAInputJoyaxisString(sourceCode);
        default:
            return [NSString stringWithFormat:@"code:%ld", (long)sourceCode];
    }
}

#pragma mark - RAInputPhysicalSourceRef

@implementation RAInputPhysicalSourceRef

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.sourceKind forKey:@"sourceKind"];
    [coder encodeInteger:self.sourceCode forKey:@"sourceCode"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _sourceKind = [coder decodeIntegerForKey:@"sourceKind"];
        _sourceCode = [coder decodeIntegerForKey:@"sourceCode"];
    }
    return self;
}

- (NSString *)description {
    NSMutableString *desc = [NSMutableString stringWithString:@"<RAInputPhysicalSourceRef"];
    if(self.sourceKind != RAInputPhysicalSourceKindCodeUnknown) {
        [desc appendFormat:@" kind=%@", RAInputPhysicalSourceKindCodeString(self.sourceKind)];
    }
    [desc appendFormat:@" source=%@>", RAInputPhysicalSourceCodeString(self.sourceKind, self.sourceCode)];
    return [desc copy];
}

@end

#pragma mark - RAInputBindingTarget

@implementation RAInputBindingTarget

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.targetKind forKey:@"targetKind"];
    [coder encodeObject:self.joypadCodes forKey:@"joypadCodes"];
    [coder encodeBool:self.turboEnabled forKey:@"turboEnabled"];
    [coder encodeInteger:self.systemActionCode forKey:@"systemActionCode"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _targetKind = [coder decodeIntegerForKey:@"targetKind"];
        NSSet *classes = [NSSet setWithObjects:NSArray.class, NSNumber.class, nil];
        _joypadCodes = [coder decodeObjectOfClasses:classes forKey:@"joypadCodes"] ?: @[];
        _turboEnabled = [coder decodeBoolForKey:@"turboEnabled"];
        _systemActionCode = [coder decodeIntegerForKey:@"systemActionCode"];
    }
    return self;
}

- (NSString *)description {
    NSMutableArray<NSString *> *codeStrings = [NSMutableArray arrayWithCapacity:self.joypadCodes.count];
    for (NSNumber *n in self.joypadCodes) {
        [codeStrings addObject:RAInputJoypadCodeString(n.integerValue)];
    }

    NSMutableString *desc = [NSMutableString stringWithString:@"<RAInputBindingTarget"];
    if(self.targetKind != RAInputBindingTargetKindUnknown) {
        [desc appendFormat:@" kind=%@", RAInputBindingTargetKindString(self.targetKind)];
    }
    if(codeStrings.count > 0) {
        [desc appendFormat:@" joypad-code=[%@]", [codeStrings componentsJoinedByString:@", "]];
    }
    if(self.turboEnabled) {
        [desc appendString:@" turbo"];
    }
    if(self.systemActionCode != RAInputSystemActionCodeUnknown) {
        [desc appendFormat:@" system-action=%@>", RAInputSystemActionCodeString(self.systemActionCode)];
    } else {
        [desc appendString:@">"];
    }
    return [desc copy];
}

@end

#pragma mark - RAInputBindingEntry

@implementation RAInputBindingEntry

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.target forKey:@"target"];
    [coder encodeObject:self.source forKey:@"source"];
    [coder encodeObject:self.actionId forKey:@"actionId"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _target = [coder decodeObjectOfClass:RAInputBindingTarget.class forKey:@"target"];
        _source = [coder decodeObjectOfClass:RAInputPhysicalSourceRef.class forKey:@"source"];
        _actionId = [coder decodeObjectOfClass:NSString.class forKey:@"actionId"] ?: @"";
        if (!_target) {
            _target = [RAInputBindingTarget new];
        }
        if (!_source) {
            _source = [RAInputPhysicalSourceRef new];
        }
    }
    return self;
}

- (NSString *)description {
    NSMutableString *desc = [NSMutableString stringWithString:@"\t<RAInputBindingEntry"];
    if(self.actionId.length > 0) {
        [desc appendFormat:@" actionId=%@", self.actionId];
    }
    if(self.source) {
        [desc appendFormat:@"\n\t\t\tsource=%@", self.source];
    }
    if(self.target) {
        [desc appendFormat:@"\n\t\t\ttarget=%@>", self.target];
    } else {
        [desc appendString:@"\n\t\t>"];
    }
    return [desc copy];
}

@end

#pragma mark - RAInputPlayerBinding

@implementation RAInputPlayerBinding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.port forKey:@"port"];
    [coder encodeObject:self.entries forKey:@"entries"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _port = [coder decodeIntegerForKey:@"port"];
        NSSet *classes = [NSSet setWithObjects:NSArray.class, RAInputBindingEntry.class, nil];
        _entries = [coder decodeObjectOfClasses:classes forKey:@"entries"] ?: @[];
    }
    return self;
}

- (NSString *)description {
    NSMutableString *desc = [NSMutableString stringWithString:@"<RAInputPlayerBinding"];
    [desc appendFormat:@" port=%ld", self.port];
    [desc appendFormat:@" entries=[\n"];
    for(RAInputBindingEntry *entry in self.entries) {
        [desc appendFormat:@"\t%@\n", entry];
    }
    [desc appendString:@"\t]>"];
    return [desc copy];
}

@end

#pragma mark - RAInputBindingProfile

@implementation RAInputBindingProfile

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.version forKey:@"version"];
    [coder encodeObject:self.players forKey:@"players"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _version = [coder decodeIntegerForKey:@"version"];
        NSSet *classes = [NSSet setWithObjects:NSArray.class, RAInputPlayerBinding.class, nil];
        _players = [coder decodeObjectOfClasses:classes forKey:@"players"] ?: @[];
    }
    return self;
}

- (NSData *)encodedData:(NSError **)error {
    return [NSKeyedArchiver archivedDataWithRootObject:self requiringSecureCoding:YES error:error];
}

+ (instancetype)decodeFromData:(NSData *)data error:(NSError **)error {
    return [NSKeyedUnarchiver unarchivedObjectOfClass:self fromData:data error:error];
}

- (NSString *)description {
    NSMutableString *desc = [NSMutableString stringWithString:@"<RAInputBindingProfile"];
    [desc appendFormat:@" %ld", self.version];
    [desc appendString:@" players=[\n"];
    for(RAInputPlayerBinding *player in self.players) {
        [desc appendFormat:@"\t%@\n", player];
    }
    [desc appendString:@"]>"];
    return [desc copy];
}

@end
