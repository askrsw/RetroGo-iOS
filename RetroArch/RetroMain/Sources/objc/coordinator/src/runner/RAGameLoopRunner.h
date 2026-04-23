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

- (BOOL)start;
- (BOOL)stop;
- (BOOL)pause;
- (BOOL)resume;
- (BOOL)reset;

/*
 * 控制是否启用倍速，以及启用时使用的倍率。
 *
 * 设计约束：
 * - 关闭倍速时会忽略 multiplier，并恢复到 core 原始 fps 对应的调度间隔。
 * - 开启倍速时 runner 应使用 multiplier 缩短逻辑帧间隔，而不是修改 core 本身的 timing 元数据。
 */
- (void)setFastForwardEnabled:(BOOL)enabled multiplier:(double)multiplier;
- (void)setFastForwardMultiplier:(double)multiplier;

- (NSObject *_Nullable)suspendGameLoopAndPerformSync:(RAGameLoopSyncBlock)block runOnLogicThread:(BOOL)runOnLogicThread;
- (NSString *)addEmuPrevFrameAction:(RetroArchXEmuFrameAction)action;
- (void)removeEmuPrevFrameActionForToken:(NSString *)token;
@end

NS_ASSUME_NONNULL_END
