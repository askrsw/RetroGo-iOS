//
//  RAGameLogicThreadRunner.m
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

#import "RAGameLogicThreadRunner.h"

#import <UIKit/UIKit.h>
#import <retroarch_door.h>
#import <main/runloop.h>
#import <audio/audio_driver.h>
#import <input/input_driver.h>
#import <utils/driver_utils.h>
#include <gfx/video_driver.h>
#import <mach/mach_time.h>
#import <sched.h>
#import <stdatomic.h>
#import <math.h>
#include <string.h>

typedef _Atomic double atomic_double;

#import "../virtual/virtual_joypad.h"
#import "../virtual/virtual_video_driver.h"

@interface RAGameLogicThreadCommand : NSObject {
@public
    atomic_bool completed;
}
@property(nonatomic, copy) RAGameLoopSyncBlock block;
@property(nonatomic, strong, nullable) NSObject *result;
@property(nonatomic, strong, nullable) dispatch_semaphore_t semaphore;
@end

@implementation RAGameLogicThreadCommand

- (instancetype)init {
    self = [super init];
    if (self) {
        atomic_init(&completed, false);
    }
    return self;
}

@end

@implementation RAGameLogicThreadRunner {
    NSThread *d_thread;
    atomic_bool d_shouldStop;
    atomic_bool d_paused;
    atomic_bool d_fastForwardEnabled;
    atomic_double d_fastForwardMultiplier;

    double   d_baseFPS;
    uint64_t d_baseIntervalUsec;
    uint64_t d_baseIntervalMachTime;

    double   d_fps;
    uint64_t d_intervalUsec;
    uint64_t d_intervalMachTime;
    uint64_t d_jitterSampleCount;
    uint64_t d_jitterAccumulatedUsec;
    uint64_t d_jitterMaxUsec;
    uint64_t d_deadlineMissCount;
    uint64_t d_runloopSampleCount;
    uint64_t d_runloopAccumulatedUsec;
    uint64_t d_runloopMaxUsec;
    
    CFTimeInterval d_statsLastLogTimeSec;
    uint64_t d_statsLastJitterSampleCount;
    uint64_t d_statsLastJitterAccumulatedUsec;
    uint64_t d_statsLastRunloopSampleCount;
    uint64_t d_statsLastRunloopAccumulatedUsec;
    uint64_t d_statsLastDeadlineMissCount;
    BOOL d_statsPaused;

    NSMutableDictionary<NSString *, RetroArchXEmuFrameAction> *d_emuPrevFrameActions;
    NSLock *d_actionsLock;

    NSMutableArray<RAGameLogicThreadCommand *> *d_pendingCommands;
    NSLock *d_commandLock;
    NSLock *d_pauseLock;

    NSInteger d_pauseCounter;

    __weak CADisplayLink *d_displayLink;
}

- (instancetype)initWithEmuPrevFrameActions:(NSMutableDictionary<NSString *,RetroArchXEmuFrameAction> *)prevFrameActions {
    self = [super init];
    if (self) {
        d_emuPrevFrameActions = prevFrameActions;
        d_actionsLock         = [[NSLock alloc] init];
        d_pendingCommands     = [NSMutableArray array];
        d_commandLock         = [[NSLock alloc] init];
        d_pauseLock           = [[NSLock alloc] init];
        d_pauseCounter        = 0;

        atomic_init(&d_shouldStop, false);
        atomic_init(&d_paused, false);
        atomic_init(&d_fastForwardEnabled, false);
        atomic_init(&d_fastForwardMultiplier, 1.0);

        d_baseFPS = 60.0;
        d_baseIntervalUsec = (uint64_t)llround(1000000.0 / d_baseFPS);
        d_baseIntervalMachTime = [self nanosToMach:(d_baseIntervalUsec * NSEC_PER_USEC)];
        d_fps = d_baseFPS;
        d_intervalUsec = d_baseIntervalUsec;
        d_intervalMachTime = d_baseIntervalMachTime;
        d_jitterSampleCount = 0;
        d_jitterAccumulatedUsec = 0;
        d_jitterMaxUsec = 0;
        d_deadlineMissCount = 0;
        d_runloopSampleCount = 0;
        d_runloopAccumulatedUsec = 0;
        d_runloopMaxUsec = 0;
        
        d_statsLastLogTimeSec = 0;
        d_statsLastJitterSampleCount = 0;
        d_statsLastJitterAccumulatedUsec = 0;
        d_statsLastRunloopSampleCount = 0;
        d_statsLastRunloopAccumulatedUsec = 0;
        d_statsLastDeadlineMissCount = 0;
        d_statsPaused = NO;
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

#pragma mark - RAGameLoopRunner

- (CADisplayLink *)displayLink {
    if(d_displayLink == nil) {
        RAGameLoopSyncBlock resolveDisplayLink = ^NSObject * _Nullable{
            video_driver_state_t *video_st = video_state_get_ptr();
            RAVirtualVideoDriver *driver = video_st ? (__bridge RAVirtualVideoDriver *)video_st->data : nil;
            return driver.displayLink;
        };

        if ([NSThread currentThread] == d_thread) {
            d_displayLink = (CADisplayLink *)resolveDisplayLink();
        } else {
            d_displayLink = (CADisplayLink *)[self performLogicBlockSync:resolveDisplayLink useBlockingSemaphore:YES];
        }
    }
    return d_displayLink;
}

- (BOOL)start {
    if (d_thread != nil && !d_thread.finished && !d_thread.cancelled) {
        return YES;
    }
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];

    atomic_store(&d_shouldStop, false);
    atomic_store(&d_paused, false);
    [d_pauseLock lock];
    d_pauseCounter = 0;
    [d_pauseLock unlock];

    d_thread = [[NSThread alloc] initWithTarget:self selector:@selector(runThreadLoop) object:nil];
    d_thread.name = [NSString stringWithFormat:@"%@.game_logic", bundleID];
    d_thread.qualityOfService = NSQualityOfServiceUserInteractive;
    [d_thread start];

    __weak __typeof__(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        __strong __typeof__(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf performLogicBlockSync:^NSObject * _Nullable{
            return @(command_event(CMD_EVENT_AUDIO_START, NULL));
        } useBlockingSemaphore:YES];
    });

    return YES;
}

- (BOOL)stop {
    [self setFastForwardEnabled:NO multiplier:1.0];

    BOOL unloadRet = YES;
    if (d_thread != nil && !d_thread.finished) {
        NSNumber *ret = (NSNumber *)[self performLogicBlockSync:^NSObject * _Nullable{
            return @(command_event(CMD_EVENT_UNLOAD_CORE, NULL));
        } useBlockingSemaphore:NO];
        if(ret != nil) {
            unloadRet = ret.boolValue;
        }
    }

    atomic_store(&d_shouldStop, true);
    atomic_store(&d_paused, false);
    atomic_store(&d_fastForwardEnabled, false);
    atomic_store(&d_fastForwardMultiplier, 1.0);

    while (d_thread != nil && !d_thread.finished) {
        [NSThread sleepForTimeInterval:0.001];
    }

    d_thread       = nil;
    [d_pauseLock lock];
    d_pauseCounter = 0;
    [d_pauseLock unlock];
    apple_platform = nil;
    return unloadRet;
}

- (BOOL)pause {
    return [self pause:YES];
}

- (BOOL)resume {
    return [self resume:YES];
}

- (BOOL)reset {
    NSNumber *ret = (NSNumber *)[self performLogicBlockSync:^NSObject * _Nullable{
        return @(command_event(CMD_EVENT_RESET, NULL));
    } useBlockingSemaphore:YES];
    return ret.boolValue;
}

/*
 * 倍速只影响 GameLogicThread 的调度间隔，不修改 core 原始 timing 元数据。
 *
 * 实现要点：
 * - base timing 始终来自 av_info.timing.fps，反映 core 的真实基准帧率
 * - effective timing 在 base timing 的基础上按倍率缩短间隔
 * - 这里只更新原子状态；真正的生效 timing 由逻辑线程在安全点调用 updateLogicTiming 计算
 */
- (void)setFastForwardEnabled:(BOOL)enabled multiplier:(double)multiplier {
    double sanitizedMultiplier = enabled ? [self sanitizedFastForwardMultiplier:multiplier] : 1.0;

    /*
     * 这里只更新 runner 的原子状态还不够。RetroArch 的 fastmotion / audio / video /
     * input 状态都属于运行中的 emu 线程域，必须和 runloop_iterate() 放在同一条
     * logic thread 上同步修改，否则主线程会和核心线程并发读写同一批状态。
     *
     * 这个同步块既要支持：
     * - 游戏运行中动态开启 / 关闭 fast-forward
     * - 游戏运行中动态切换倍率
     * - 从 logic thread 或外部线程进入
     */
    [self performLogicBlockSync:^NSObject * _Nullable{
        [self maybeLogStatsWithForce:YES reason:"fast_forward_toggle"];
        atomic_store(&d_fastForwardEnabled, enabled);
        atomic_store(&d_fastForwardMultiplier, sanitizedMultiplier);

        runloop_state_t *runloop_st = runloop_state_get_ptr();
        input_driver_state_t *input_st = input_state_get_ptr();
        video_driver_state_t *video_st = video_state_get_ptr();

        if (runloop_st != NULL && video_st != NULL) {
            struct retro_fastforwarding_override fastforwardOverride = {0};
            fastforwardOverride.fastforward = enabled;
            fastforwardOverride.ratio = enabled ? (float)sanitizedMultiplier : 1.0f;
            fastforwardOverride.notification = false;
            fastforwardOverride.inhibit_toggle = false;

            runloop_st->fastmotion_override.current = fastforwardOverride;
            runloop_st->fastmotion_override.next = fastforwardOverride;
            runloop_st->fastmotion_override.pending = false;

            if (enabled) {
                runloop_st->flags |= RUNLOOP_FLAG_FASTMOTION;
            } else {
                runloop_st->flags &= ~RUNLOOP_FLAG_FASTMOTION;
                runloop_st->fastforward_after_frames = 1;
            }

            /*
             * RetroArch 的 fast-forward 依赖 input nonblocking 来解除常规阻塞路径，
             * driver_set_nonblock_state() 会进一步把 audio/video driver 切到对应状态。
             */
            if (input_st != NULL) {
                if (enabled) {
                    input_st->flags |= INP_FLAG_NONBLOCKING;
                } else {
                    input_st->flags &= ~INP_FLAG_NONBLOCKING;
                }
            }

            driver_set_nonblock_state();
            runloop_set_frame_limit(&video_st->av_info, enabled ? (float)sanitizedMultiplier : 1.0f);
            audio_driver_set_playback_speed(enabled ? sanitizedMultiplier : 1.0f);
        }

        /*
         * runner 自己的调度间隔也和 RetroArch 内部状态在同一个线程里一起更新，
         * 这样倍率切换从下一帧开始就是一致的。
         */
        [self updateLogicTiming];
        return nil;
    } useBlockingSemaphore:YES];
}

- (void)setFastForwardMultiplier:(double)multiplier {
    BOOL fastForwardEnabled = atomic_load(&self->d_fastForwardEnabled);
    if (!fastForwardEnabled) {
        return nil;
    }

    double sanitizedMultiplier = [self sanitizedFastForwardMultiplier:multiplier];

    /*
     * 允许在 fast-forward 已开启时单独调整倍率。
     * 为了避免跨线程并发修改 runloop/audio/video 状态，仍然统一切到 logic thread 生效。
     *
     * 如果当前没有开启 fast-forward，则只更新“下次启用时使用的倍率”即可，
     * 不主动改动 RetroArch 的 fastmotion/nonblock 状态。
     */
    [self performLogicBlockSync:^NSObject * _Nullable{
        [self maybeLogStatsWithForce:YES reason:"fast_forward_multiplier_changing"];
        atomic_store(&d_fastForwardMultiplier, sanitizedMultiplier);

        runloop_state_t *runloop_st = runloop_state_get_ptr();
        video_driver_state_t *video_st = video_state_get_ptr();
        if (runloop_st != NULL && video_st != NULL) {
            struct retro_fastforwarding_override fastforwardOverride = {0};
            fastforwardOverride.fastforward = true;
            fastforwardOverride.ratio = (float)sanitizedMultiplier;
            fastforwardOverride.notification = false;
            fastforwardOverride.inhibit_toggle = false;

            runloop_st->fastmotion_override.current = fastforwardOverride;
            runloop_st->fastmotion_override.next = fastforwardOverride;
            runloop_st->fastmotion_override.pending = false;
            runloop_st->flags |= RUNLOOP_FLAG_FASTMOTION;

            runloop_set_frame_limit(&video_st->av_info, (float)sanitizedMultiplier);
            audio_driver_set_playback_speed(sanitizedMultiplier);
        }

        [self updateLogicTiming];
        return nil;
    } useBlockingSemaphore:YES];
}

/*
 * 只供内部流程使用的“临时挂起 + 执行同步任务”入口。
 *
 * 使用约束：
 * - 这里对应的是 save/load state、启动阶段恢复状态等内部时序控制；
 * - pause/resume 必须使用非 semaphore 模式，避免和 video init / render reply /
 *   main-thread pumping 形成强同步等待环；
 * - 因为这里本身就是复杂流程中的嵌套控制点，优先保证“不死锁”，其次才是“立即返回”。
 *
 * 与之相对：
 * - 用户可感知的外部 pause/resume（进入后台、打开设置页等）仍然走 semaphore
 *   模式，保持明确的完成语义。
 */
- (NSObject *_Nullable)suspendGameLoopAndPerformSync:(RAGameLoopSyncBlock)block runOnLogicThread:(BOOL)runOnLogicThread {
    if (![self pause: NO]) {
        return nil;
    }

    NSObject *obj;
    if(runOnLogicThread) {
        obj = block ? [self performLogicBlockSync:block useBlockingSemaphore:YES] : nil;
    } else {
        obj = block ? block() : nil;
    }

    if (![self resume: NO]) {
        return nil;
    }

    return obj;
}

- (NSString *)addEmuPrevFrameAction:(RetroArchXEmuFrameAction)action {
    NSString *token = NSUUID.UUID.UUIDString;
    [d_actionsLock lock];
    d_emuPrevFrameActions[token] = [action copy];
    [d_actionsLock unlock];
    return token;
}

- (void)removeEmuPrevFrameActionForToken:(NSString *)token {
    [d_actionsLock lock];
    [d_emuPrevFrameActions removeObjectForKey:token];
    [d_actionsLock unlock];
}

#pragma mark - Internal

- (BOOL)pause:(BOOL)useBlockingSemaphore {
    /*
     * pause 的两种等待模式有明确分工：
     * - useBlockingSemaphore == YES
     *   用于用户触发的外部控制流，调用方需要拿到“已完成暂停”的强语义。
     * - useBlockingSemaphore == NO
     *   仅用于内部 suspend 包装流程，避免在复杂初始化/状态恢复链路中形成等待环。
     */
    NSAssert([NSThread isMainThread] || [NSThread currentThread] == d_thread,
             @"pause must be called on main thread or logic thread");

    [d_pauseLock lock];
    if (d_pauseCounter++ != 0) {
        [d_pauseLock unlock];
        return YES;
    }
    [d_pauseLock unlock];

    NSNumber *ret = (NSNumber *)[self performLogicBlockSync:^NSObject * _Nullable{
        [self maybeLogStatsWithForce:YES reason:"pause"];
        audio_driver_stop();
        BOOL pauseRet = command_event(CMD_EVENT_PAUSE, NULL);
        if (pauseRet) {
            atomic_store(&self->d_paused, true);
            self->d_statsPaused = YES;
        }
        return @(pauseRet);
    } useBlockingSemaphore:useBlockingSemaphore];

    if (!ret.boolValue) {
        [d_pauseLock lock];
        d_pauseCounter = 0;
        [d_pauseLock unlock];
    }
    return ret.boolValue;
}

- (BOOL)resume:(BOOL)useBlockingSemaphore {
    /*
     * 与 pause 一样，resume 也分两类：
     * - 外部用户控制流：使用 semaphore 强同步恢复；
     * - 内部 suspend 包装：使用轮询完成，避免 startup / load-state 等阶段的互等。
     */
    NSAssert([NSThread isMainThread] || [NSThread currentThread] == d_thread,
             @"resume must be called on main thread or logic thread");

    [d_pauseLock lock];
    NSCAssert(d_pauseCounter > 0, @"resume called without matching pause");
    if (d_pauseCounter <= 0) {
        d_pauseCounter = 0;
        [d_pauseLock unlock];
        return NO;
    }

    d_pauseCounter--;
    if (d_pauseCounter != 0) {
        [d_pauseLock unlock];
        return YES;
    }
    [d_pauseLock unlock];

    NSNumber *ret = (NSNumber *)[self performLogicBlockSync:^NSObject * _Nullable{
        [self updateLogicTiming];
        BOOL resumeRet = command_event(CMD_EVENT_UNPAUSE, NULL);
        if (resumeRet) {
            atomic_store(&self->d_paused, false);
            self->d_statsPaused = NO;
            [self resetStatsWindow];
            audio_driver_start(false);
        } else {
            atomic_store(&self->d_paused, true);
        }
        return @(resumeRet);
    } useBlockingSemaphore:useBlockingSemaphore];

    if (!ret.boolValue) {
        [d_pauseLock lock];
        d_pauseCounter = 1;
        [d_pauseLock unlock];
    }
    return ret.boolValue;
}

- (NSObject *_Nullable)performLogicBlockSync:(RAGameLoopSyncBlock)block useBlockingSemaphore:(BOOL)useBlockingSemaphore {
    if (!block) {
        return nil;
    }

    NSThread *thread = d_thread;
    if (thread == nil || thread.finished) {
        return nil;
    }

    if ([NSThread currentThread] == thread) {
        return block();
    }

    RAGameLogicThreadCommand *command = [[RAGameLogicThreadCommand alloc] init];
    command.block = block;

    if (useBlockingSemaphore) {
        command.semaphore = dispatch_semaphore_create(0);
    }

    [d_commandLock lock];
    [d_pendingCommands addObject:command];
    [d_commandLock unlock];

    if (useBlockingSemaphore) {
        dispatch_semaphore_wait(command.semaphore, DISPATCH_TIME_FOREVER);
        return command.result;
    }

    /*
     * 非 semaphore 模式只用于内部“避免等待环”的场景。
     * 这里保持短间隔轮询，同时输出慢等待日志，便于观察启动阶段、
     * load-state、video init 等链路是否出现异常阻塞。
     */
    uint64_t waitStartMach = mach_absolute_time();
    uint64_t nextLogAfterUsec = 100000;

    while (!atomic_load(&command->completed)) {
        if (thread.finished || atomic_load(&d_shouldStop)) {
            return nil;
        }

        uint64_t waitedUsec = [self machToNanos:(mach_absolute_time() - waitStartMach)] / NSEC_PER_USEC;
        if (waitedUsec >= nextLogAfterUsec) {
            RARCH_WARN("[GameThread] performLogicBlockSync(nonblocking) still waiting: waited=%lluus paused=%s should_stop=%s main_thread=%s\n",
                       (unsigned long long)waitedUsec,
                       atomic_load(&d_paused) ? "true" : "false",
                       atomic_load(&d_shouldStop) ? "true" : "false",
                       [NSThread isMainThread] ? "true" : "false");
            nextLogAfterUsec += 100000;
        }

        if ([NSThread isMainThread]) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.0005, true);
        } else {
            [NSThread sleepForTimeInterval:0.0005];
        }
    }

    return command.result;
}

- (void)runThreadLoop {
    @autoreleasepool {
        [self updateLogicTiming];
        uint64_t expectedFrameStart = mach_absolute_time();

        while (!atomic_load(&d_shouldStop)) {
            /*
             * 每一帧开始前都刷新一次 timing。
             * 这样倍速开关和倍率修改不需要额外中断逻辑线程，下一帧就会自然生效。
             */
            [self updateLogicTiming];
            [self drainPendingCommands];

            if (atomic_load(&d_paused)) {
                uint64_t skip = [self nanosToMach:1000000];
                expectedFrameStart = mach_absolute_time();
                [self waitUntilMachDeadline:expectedFrameStart + skip];
                continue;
            }

            /*
             * 使用绝对 deadline 调度，而不是“这一帧跑完再 sleep 剩余时间”。
             * 这样可以避免 sleep 抖动逐帧累积，降低音频 burst / underrun 风险。
             */
            uint64_t frameStartMach = mach_absolute_time();
            [self recordJitterWithActualFrameStart:frameStartMach expectedFrameStart:expectedFrameStart];

            [self runEmuPrevFrameActions];

            virtual_joypad_commit_frame_state();

            /*
             * 单独统计 runloop_iterate() 的执行耗时。
             * jitter 反映的是“这一帧是否按时开始”，而这里反映的是“这一帧具体跑了多久”。
             * 两者结合起来，才能区分是调度抖动导致的音频问题，还是核心执行时间本身过长。
             */
            uint64_t runloopStartMach = mach_absolute_time();
            int ret = runloop_iterate();
            uint64_t runloopEndMach = mach_absolute_time();
            uint64_t runloopDurationUsec = [self machToNanos:(runloopEndMach - runloopStartMach)] / NSEC_PER_USEC;
            [self recordRunloopDurationUsec:runloopDurationUsec];
            if (ret == -1) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    main_exit(NULL);
                    exit(0);
                });
                break;
            }

            task_queue_check();

            uint32_t runloop_flags = runloop_get_flags();
            if (!(runloop_flags & RUNLOOP_FLAG_IDLE)) {
                CFRunLoopWakeUp(CFRunLoopGetMain());
            }

            uint64_t frameEndMach = mach_absolute_time();
            uint64_t nextExpectedFrameStart = expectedFrameStart + d_intervalMachTime;

            /*
             * 如果当前帧已经错过了下一帧 deadline，就重置调度基线。
             * 这比盲目“补帧赶进度”更稳，能减少连续抖动导致的音频杂音。
             */
            if (frameEndMach >= nextExpectedFrameStart) {
                d_deadlineMissCount++;
                expectedFrameStart = frameEndMach;
            } else {
                [self waitUntilMachDeadline:nextExpectedFrameStart];
                expectedFrameStart = nextExpectedFrameStart;
            }
        }

        [self drainPendingCommands];
    }
}

- (void)drainPendingCommands {
    while (true) {
        RAGameLogicThreadCommand *command = nil;

        [d_commandLock lock];
        if (d_pendingCommands.count > 0) {
            command = d_pendingCommands.firstObject;
            [d_pendingCommands removeObjectAtIndex:0];
        }
        [d_commandLock unlock];

        if (command == nil) {
            break;
        }

        command.result = command.block ? command.block() : nil;
        atomic_store(&command->completed, true);

        if (command.semaphore) {
            dispatch_semaphore_signal(command.semaphore);
        }
    }
}

- (void)updateLogicTiming {
    video_driver_state_t *video_st = video_state_get_ptr();
    double fps = video_st ? video_st->av_info.timing.fps : 0.0;
    if (!(fps > 0.0)) {
        fps = 60.0;
    }

    d_baseFPS = fps;
    d_baseIntervalUsec = (uint64_t)llround(1000000.0 / fps);
    d_baseIntervalMachTime = [self nanosToMach:(d_baseIntervalUsec * NSEC_PER_USEC)];

    BOOL fastForwardEnabled = atomic_load(&d_fastForwardEnabled);
    double fastForwardMultiplier = [self sanitizedFastForwardMultiplier:atomic_load(&d_fastForwardMultiplier)];

    /*
     * effective timing 才是调度真正使用的值。
     * 开启倍速时只缩短逻辑帧间隔，让 runloop_iterate() 更频繁地推进模拟；
     * base timing 仍然保留，便于日志、调试和后续回退到 1x。
     */
    if (fastForwardEnabled && fastForwardMultiplier > 1) {
        d_fps = d_baseFPS * fastForwardMultiplier;
        d_intervalUsec = MAX(1, d_baseIntervalUsec / (uint64_t)fastForwardMultiplier);
        d_intervalMachTime = MAX((uint64_t)1, d_baseIntervalMachTime / (uint64_t)fastForwardMultiplier);
    } else {
        d_fps = d_baseFPS;
        d_intervalUsec = d_baseIntervalUsec;
        d_intervalMachTime = d_baseIntervalMachTime;
    }
}

- (void)runEmuPrevFrameActions {
    [d_actionsLock lock];
    NSArray<RetroArchXEmuFrameAction> *actions = [d_emuPrevFrameActions.allValues copy];
    [d_actionsLock unlock];

    for (RetroArchXEmuFrameAction action in actions) {
        action();
    }
}

/*
 * 等待直到指定的绝对 mach deadline。
 *
 * 这是 GameLogicThread 帧调度的核心等待函数，用来替代简单的
 * NSThread sleepForTimeInterval，从而降低帧间隔抖动。
 *
 * 设计目标：
 * - 尽量在目标 deadline 附近被唤醒
 * - 避免普通 sleep 带来的较大尾部误差
 * - 同时控制 CPU 开销，不做整段忙等
 *
 * 实现策略：两段式等待
 *
 * 1. 粗等待（coarse wait）
 *    - 如果距离 deadline 还比较远，就使用 mach_wait_until()
 *    - 这是内核级的绝对时间等待，精度通常比 NSThread sleep 更高
 *    - 可以显著减少长时间 busy-wait 带来的 CPU 浪费
 *
 * 2. 细等待（fine wait）
 *    - 当只剩最后一个很小的时间窗口时，不再继续用 mach_wait_until()
 *    - 因为越接近 deadline，普通阻塞等待的唤醒误差越容易超过剩余时间本身
 *    - 所以改用短轮询 + sched_yield() 逼近 deadline
 *
 * 为什么需要 spinThreshold：
 * - 如果从很早就开始 busy-wait，会浪费 CPU
 * - 如果一直用阻塞等待到最后，唤醒点又可能偏晚
 * - 所以这里用一个阈值（当前是约 300 微秒）做折中：
 *   前面节能，最后精调
 *
 * 注意：
 * - 这个函数并不能提供硬实时保证
 * - 系统调度、QoS、其他线程竞争仍然会影响实际唤醒时间
 * - 但相比单纯 sleep，它能明显改善 frame pacing 稳定性，从而减少音频杂音
 */
- (void)waitUntilMachDeadline:(uint64_t)deadline {
    /*
     * 两段式等待：
     * 1. 距离 deadline 还远时，使用 mach_wait_until 做粗等待，降低 CPU 占用。
     * 2. 剩余最后一小段时间时，使用短轮询逼近 deadline，减少 sleep 唤醒抖动。
     */
    const uint64_t spinThresholdMach = [self nanosToMach:(300 * NSEC_PER_USEC)];

    while (true) {
        uint64_t now = mach_absolute_time();
        if (now >= deadline) {
            return;
        }

        uint64_t remaining = deadline - now;
        if (remaining <= spinThresholdMach) {
            break;
        }

        mach_wait_until(deadline - spinThresholdMach);
    }

    while (mach_absolute_time() < deadline) {
        sched_yield();
    }
}

/*
 * 记录逻辑线程帧开始时刻的抖动（jitter）统计信息。
 *
 * 为什么要记录 jitter，而不是只看平均 FPS：
 * - 平均 FPS 只能说明“长期平均速度”是否接近目标
 * - 但音频杂音、爆音、卡顿往往不是由平均值引起的
 * - 真正的问题通常来自少数几帧：
 *   它们开始得过晚、间隔抖动过大，导致音频缓冲供给不连续
 *
 * 所以这里统计的重点是：
 * - 实际帧开始时间 actualFrameStart
 * - 相对于理想 deadline / 期望开始时间 expectedFrameStart 的偏差
 *
 * 统计项包括：
 * - sample count：累计样本数
 * - accumulated jitter：累计抖动，便于算平均值
 * - max jitter：观察最坏情况，定位长尾帧
 * - missed deadlines：记录已经晚到超过 deadline 的次数
 *
 * 为什么使用绝对偏差：
 * - 无论是“早到”还是“晚到”，本质上都说明 pacing 不稳定
 * - 对音频来说，尤其要关注晚到，但整体稳定性也可以先看绝对偏差
 *
 * 日志策略：
 * - 每 600 帧输出一次，避免每帧打日志影响性能
 * - 这些日志主要用于对比：
 *   GameLogicThread vs CADisplayLink
 * - 如果 avg_jitter / max_jitter / missed_deadlines 明显下降，
 *   一般也会伴随音频稳定性改善
 *
 * 注意：
 * - 这里记录的是“帧起点调度抖动”
 * - 它不等同于 runloop_iterate() 的执行耗时
 * - 如果后面还要进一步诊断，可以再单独统计 core run time / runloop_iterate() duration
 */
- (void)recordJitterWithActualFrameStart:(uint64_t)actualFrameStart expectedFrameStart:(uint64_t)expectedFrameStart {
    uint64_t actualNanos = [self machToNanos:actualFrameStart];
    uint64_t expectedNanos = [self machToNanos:expectedFrameStart];
    uint64_t jitterUsec = llabs((long long)actualNanos - (long long)expectedNanos) / NSEC_PER_USEC;

    d_jitterSampleCount++;
    d_jitterAccumulatedUsec += jitterUsec;
    d_jitterMaxUsec = MAX(d_jitterMaxUsec, jitterUsec);

}

/*
 * 记录 runloop_iterate() 的执行耗时统计。
 *
 * 为什么要单独统计这个 method：
 * - jitter 只能告诉我们“帧开始时间准不准”
 * - 但如果 runloop_iterate() 自身偶尔跑得很久，音频同样会断续或爆音
 * - 因此这里单独观察逻辑帧的执行成本，用来定位 core / task queue / 渲染协同带来的长尾帧
 *
 * 统计项包括：
 * - sample count：累计多少帧参与了 runloop 耗时统计
 * - accumulated usec：累计执行耗时，用于计算平均值
 * - max usec：记录最慢的一帧，方便定位偶发长尾
 *
 * 日志策略：
 * - 默认按时间窗口输出：每 30 秒输出一次
 * - 当 fast-forward 开关变化或 multiplier 变化时，会立即输出一次
 * - 立即输出后会重置统计窗口，后续重新开始 30 秒计时
 * - 一次性同时输出 jitter 和 runloop 的窗口平均值 / 全局最大值，便于直接对比
 *
 * 解释方式：
 * - avg/max jitter 高：通常是调度或等待机制不稳
 * - avg/max runloop 高：通常是单帧模拟、任务处理或图形协同过重
 * - missed_deadlines 高：说明已经实质性错过目标帧起点
 */
- (void)recordRunloopDurationUsec:(uint64_t)durationUsec {
    d_runloopSampleCount++;
    d_runloopAccumulatedUsec += durationUsec;
    d_runloopMaxUsec = MAX(d_runloopMaxUsec, durationUsec);
    [self maybeLogStatsWithForce:NO reason:"periodic"];
}

/*
 * 统一的统计输出入口。
 *
 * 输出时机：
 * - force == NO：按 30 秒窗口输出一次（周期统计）
 * - force == YES：立即输出一次（用于 fast-forward 状态变化）
 *
 * 窗口语义：
 * - 日志中的 avg/fps/frames/missed_deadlines 都是“自上次输出以来”的窗口增量
 * - max_jitter / max_runloop 目前保持全局最大值，便于观察整个运行期的最坏情况
 *
 * 首次调用行为：
 * - 第一次进入时只建立统计基线
 * - 如果 force==YES，会在建立基线后立即输出一次
 */
- (void)maybeLogStatsWithForce:(BOOL)force reason:(const char *)reason {
    BOOL isPauseReason = (reason != NULL && strcmp(reason, "pause") == 0);
    if (d_statsPaused && !isPauseReason) {
        return;
    }

    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (d_statsLastLogTimeSec <= 0) {
        d_statsLastLogTimeSec = now;
        d_statsLastJitterSampleCount = d_jitterSampleCount;
        d_statsLastJitterAccumulatedUsec = d_jitterAccumulatedUsec;
        d_statsLastRunloopSampleCount = d_runloopSampleCount;
        d_statsLastRunloopAccumulatedUsec = d_runloopAccumulatedUsec;
        d_statsLastDeadlineMissCount = d_deadlineMissCount;
        if (!force) {
            return;
        }
    }

    CFTimeInterval elapsedSec = now - d_statsLastLogTimeSec;
    if (!force && elapsedSec < 30.0) {
        return;
    }
    if (elapsedSec <= 0.0) {
        elapsedSec = 0.000001;
    }

    uint64_t deltaJitterSamples = d_jitterSampleCount - d_statsLastJitterSampleCount;
    uint64_t deltaJitterAccumulatedUsec = d_jitterAccumulatedUsec - d_statsLastJitterAccumulatedUsec;
    uint64_t deltaRunloopSamples = d_runloopSampleCount - d_statsLastRunloopSampleCount;
    uint64_t deltaRunloopAccumulatedUsec = d_runloopAccumulatedUsec - d_statsLastRunloopAccumulatedUsec;
    uint64_t deltaDeadlineMissCount = d_deadlineMissCount - d_statsLastDeadlineMissCount;

    uint64_t averageJitterUsec = deltaJitterSamples > 0 ? (deltaJitterAccumulatedUsec / deltaJitterSamples) : 0;
    uint64_t averageRunloopUsec = deltaRunloopSamples > 0 ? (deltaRunloopAccumulatedUsec / deltaRunloopSamples) : 0;
    double framesPerSec = deltaRunloopSamples / elapsedSec;

    RARCH_LOG("[GameThread][Stats][%s] window=%.2fs fps=%.2f frames=%llu fast_forward=%s multiplier=%.3f avg_jitter=%lluus max_jitter=%lluus avg_runloop=%lluus max_runloop=%lluus missed_deadlines=%llu\n",
              reason,
              elapsedSec,
              framesPerSec,
              (unsigned long long)deltaRunloopSamples,
              atomic_load(&d_fastForwardEnabled) ? "true" : "false",
              [self sanitizedFastForwardMultiplier:atomic_load(&d_fastForwardMultiplier)],
              (unsigned long long)averageJitterUsec,
              (unsigned long long)d_jitterMaxUsec,
              (unsigned long long)averageRunloopUsec,
              (unsigned long long)d_runloopMaxUsec,
              (unsigned long long)deltaDeadlineMissCount);

    d_statsLastLogTimeSec = now;
    d_statsLastJitterSampleCount = d_jitterSampleCount;
    d_statsLastJitterAccumulatedUsec = d_jitterAccumulatedUsec;
    d_statsLastRunloopSampleCount = d_runloopSampleCount;
    d_statsLastRunloopAccumulatedUsec = d_runloopAccumulatedUsec;
    d_statsLastDeadlineMissCount = d_deadlineMissCount;
}

- (void)resetStatsWindow {
    d_statsLastLogTimeSec = CFAbsoluteTimeGetCurrent();
    d_statsLastJitterSampleCount = d_jitterSampleCount;
    d_statsLastJitterAccumulatedUsec = d_jitterAccumulatedUsec;
    d_statsLastRunloopSampleCount = d_runloopSampleCount;
    d_statsLastRunloopAccumulatedUsec = d_runloopAccumulatedUsec;
    d_statsLastDeadlineMissCount = d_deadlineMissCount;
}

/*
 * 将 mach_absolute_time() 返回的原始时钟单位转换为纳秒。
 *
 * 背景：
 * - mach_absolute_time() 返回的不是“纳秒”或“微秒”，而是机器相关的硬件时钟 tick。
 * - 这个 tick 的时间基准在不同设备上并不固定，因此不能直接拿来当真实时间单位使用。
 *
 * 为什么需要转换：
 * - 我们要统计 frame jitter、deadline 偏差、等待时长时，必须使用统一且可读的时间单位。
 * - 纳秒是最合适的中间单位，后面可以再方便地换算成微秒或毫秒。
 *
 * 实现方式：
 * - mach_timebase_info() 会返回 numer/denom，用于把 mach tick 映射到纳秒：
 *     nanoseconds = machTime * numer / denom
 * - 这个 timebase 在当前设备上是固定的，所以只需要查询一次。
 * - 这里用 dispatch_once 缓存 timebase，避免每帧重复调用系统接口。
 *
 * 注意：
 * - 这个函数本身不做睡眠，也不保证实时性，它只是时间单位换算。
 * - 统计抖动时我们依赖这个函数，把实际帧开始时间与期望 deadline 都转换到统一单位。
 */
- (uint64_t)machToNanos:(uint64_t) machTime {
    static mach_timebase_info_data_t timebaseInfo;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mach_timebase_info(&timebaseInfo);
    });

    return machTime * timebaseInfo.numer / timebaseInfo.denom;
}

/*
 * 将纳秒转换回 mach_absolute_time() / mach_wait_until() 所使用的 mach 时钟单位。
 *
 * 背景：
 * - mach_wait_until() 接收的参数不是纳秒，而是 mach 绝对时钟单位。
 * - 因此如果我们先按“纳秒”计算好了目标 deadline，真正调用 mach_wait_until() 前，
 *   还必须把纳秒转换回 mach tick。
 *
 * 为什么需要这个函数：
 * - 我们的逻辑帧间隔（例如 16.67ms）更适合先按微秒/纳秒计算；
 * - 但等待 API 使用的是 mach tick；
 * - 所以调度路径里需要一对可逆的换算函数：
 *     mach -> nanos
 *     nanos -> mach
 *
 * 实现方式：
 * - 根据同一个 timebase 做反向换算：
 *     mach = nanoseconds * denom / numer
 * - 同样使用 dispatch_once 缓存 timebase，避免高频路径重复获取。
 *
 * 典型用途：
 * - 把 d_intervalUsec 换算成 d_intervalMachTime
 * - 计算绝对 deadline
 * - 传给 mach_wait_until() 做高精度等待
 *
 * 注意：
 * - 因为是整数换算，会有极小的舍入误差；
 * - 但相比 NSThread sleepForTimeInterval 的调度抖动，这个误差可以忽略。
 */
- (uint64_t)nanosToMach:(uint64_t)nanos {
    static mach_timebase_info_data_t timebaseInfo;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mach_timebase_info(&timebaseInfo);
    });

    return nanos * timebaseInfo.denom / timebaseInfo.numer;
}

/*
 * 只允许协议定义的几档倍速。
 * 这样 runner 内部不会出现任意值，日志节奏、UI 选项和调度间隔都能保持一致。
 */
- (double)sanitizedFastForwardMultiplier:(double)multiplier {
    if (!isfinite(multiplier)) {
        return 1.0;
    }
    if (multiplier < 1.0) {
        return 1.0;
    }
    if (multiplier > 6.0) {
        return 6.0;
    }
    return multiplier;
}

@end
