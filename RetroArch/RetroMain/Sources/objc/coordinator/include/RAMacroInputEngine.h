// Copyright © 2026 haharsw. Part of RetroGo, GPL-3.0-or-later.
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
