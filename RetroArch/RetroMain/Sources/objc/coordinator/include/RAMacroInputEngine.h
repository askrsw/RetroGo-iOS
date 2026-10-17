//
//  RAMacroInputEngine.h
//  RetroGo
//
//  Created by haharsw on 2026/10/16.
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

#ifndef RETROGO_RA_MACRO_INPUT_ENGINE_H
#define RETROGO_RA_MACRO_INPUT_ENGINE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One complete RetroPad input state held for a number of emulated frames.
@interface RAMacroInputStep : NSObject <NSSecureCoding>
@property(nonatomic, readonly) uint32_t buttons;
@property(nonatomic, readonly) NSUInteger frames;
- (instancetype)initWithButtons:(uint32_t)buttons frames:(NSUInteger)frames;
@end

/// Thread-safe player. Call advanceFrame once before committing frame
/// input, after other input producers. Output belongs to its own mixer source.
@interface RAMacroInputEngine : NSObject
@property(nonatomic, readonly, getter=isPlaying) BOOL playing;
@property(nonatomic, readonly) NSUInteger elapsedFrames;
- (instancetype)initWithOutput:(void (^)(uint32_t))output;
- (BOOL)playSteps:(NSArray<RAMacroInputStep *> *)steps;
- (void)cancel;
- (void)advanceFrame;
@end

NS_ASSUME_NONNULL_END

#endif // RETROGO_RA_MACRO_INPUT_ENGINE_H
