//
//  RAGameLoopRunner.h
//  RetroGo
//
//  Created by haharsw on 2026/4/12.
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

NS_ASSUME_NONNULL_BEGIN

typedef void (^RetroArchXEmuFrameAction)(void);
typedef NSObject *_Nullable(^RAGameLoopSyncBlock)(void);

@protocol RAGameLoopRunner <NSObject>
@property(nonatomic, readonly, strong) CADisplayLink *displayLink;

@property(nonatomic, assign, getter=isStatsLoggingEnabled) BOOL statsLoggingEnabled;

- (BOOL)start;
- (BOOL)stop;
- (BOOL)pause;
- (BOOL)resume;
- (BOOL)reset;

/*
 * Controls whether fast-forward is on and, when on, which multiplier it uses.
 *
 * Design constraints:
 * - When fast-forward is off, multiplier is ignored and the schedule interval goes back to the one for the core's original fps.
 * - When fast-forward is on, the runner should use multiplier to shorten the logic frame interval instead of changing the core's own timing metadata.
 */
- (void)setFastForwardEnabled:(BOOL)enabled multiplier:(double)multiplier;
- (void)setFastForwardMultiplier:(double)multiplier;

- (NSObject *_Nullable)suspendGameLoopAndPerformSync:(RAGameLoopSyncBlock)block runOnLogicThread:(BOOL)runOnLogicThread;
- (NSString *)addEmuPrevFrameAction:(RetroArchXEmuFrameAction)action;
- (void)removeEmuPrevFrameActionForToken:(NSString *)token;
@end

NS_ASSUME_NONNULL_END
