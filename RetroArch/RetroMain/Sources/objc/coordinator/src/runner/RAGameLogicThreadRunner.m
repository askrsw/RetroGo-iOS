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
#import <gfx/video_driver.h>
#import <mach/mach_time.h>
#import <sched.h>
#import <stdatomic.h>
#import <math.h>
#import <string.h>

typedef _Atomic double atomic_double;

#import "../input/virtual_joypad.h"
#import "../video/virtual_video_driver.h"

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
    /* Set on the logic thread right after retrogo_unload_core_full_stop(); no frame may run afterwards. */
    atomic_bool d_coreUnloaded;
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
        atomic_init(&d_coreUnloaded, false);
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
    atomic_store(&d_coreUnloaded, false);
    atomic_store(&d_paused, false);
    [d_pauseLock lock];
    d_pauseCounter = 0;
    [d_pauseLock unlock];

    d_thread = [[NSThread alloc] initWithTarget:self selector:@selector(runThreadLoop) object:nil];
    d_thread.name = [NSString stringWithFormat:@"%@.game_logic", bundleID];
    d_thread.qualityOfService = NSQualityOfServiceUserInteractive;
    [d_thread start];

    __weak __typeof__(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        __strong __typeof__(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf performLogicBlockSync:^NSObject * _Nullable{
            return @(command_event(CMD_EVENT_AUDIO_START, NULL));
        } useBlockingSemaphore:NO];
    });

    return YES;
}

- (BOOL)stop {
    [self setFastForwardEnabled:NO multiplier:1.0];

    BOOL unloadRet = YES;
    if (d_thread != nil && !d_thread.finished) {
        NSNumber *ret = (NSNumber *)[self performLogicBlockSync:^NSObject * _Nullable{
            BOOL unloaded = retrogo_unload_core_full_stop();
            /*
             * The full stop deinits the core and frees all drivers (input included), while d_shouldStop is
             * only set after the main thread observes completion. Mark it here so runThreadLoop never calls
             * runloop_iterate() again on the unloaded core.
             */
            atomic_store(&d_coreUnloaded, true);
            return @(unloaded);
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
    } useBlockingSemaphore:NO];
    return ret.boolValue;
}

/*
 * Fast-forward only changes the GameLogicThread schedule interval, never the core's original timing metadata.
 *
 * Implementation notes:
 * - base timing always comes from av_info.timing.fps and reflects the core's real base frame rate
 * - effective timing shortens the base timing interval by the multiplier
 * - only the atomic state is updated here; the logic thread computes the effective timing by calling updateLogicTiming at a safe point
 */
- (void)setFastForwardEnabled:(BOOL)enabled multiplier:(double)multiplier {
    double sanitizedMultiplier = enabled ? [self sanitizedFastForwardMultiplier:multiplier] : 1.0;

    /*
     * Updating the runner's atomic state alone isn't enough. RetroArch's fastmotion / audio / video /
     * input state all belong to the running emu thread and must be changed on the same
     * logic thread as runloop_iterate(), or the main thread and the core thread read and write the same state concurrently.
     *
     * This sync block has to support:
     * - turning fast-forward on / off while a game is running
     * - changing the multiplier while a game is running
     * - being entered from the logic thread or from another thread
     */
    [self performLogicBlockSync:^NSObject * _Nullable{
        [self maybeLogStatsWithForce:YES reason:"fast_forward_toggle"];
        atomic_store(&d_fastForwardEnabled, enabled);
        atomic_store(&d_fastForwardMultiplier, sanitizedMultiplier);

        runloop_state_t *runloop_st = runloop_state_get_ptr();
        input_driver_state_t *input_st = input_state_get_ptr();
        video_driver_state_t *video_st = video_state_get_ptr();
        audio_driver_state_t *audio_st = audio_state_get_ptr();
        settings_t *settings = config_get_ptr();

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
             * RetroArch's fast-forward relies on input nonblocking to lift the regular blocking path;
             * driver_set_nonblock_state() then switches the audio/video drivers to the matching state.
             */
            if (input_st != NULL) {
                if (enabled) {
                    input_st->flags |= INP_FLAG_NONBLOCKING;
                } else {
                    input_st->flags &= ~INP_FLAG_NONBLOCKING;
                }
            }

            if (audio_st != NULL) {
                BOOL shouldMuteOnFastForward = settings != NULL && settings->bools.audio_fastforward_mute;
                if (enabled && shouldMuteOnFastForward) {
                    audio_st->flags |= AUDIO_FLAG_MUTED;
                } else {
                    audio_st->flags &= ~AUDIO_FLAG_MUTED;
                }
            }

            driver_set_nonblock_state();
            runloop_set_frame_limit(&video_st->av_info, enabled ? (float)sanitizedMultiplier : 1.0f);
            audio_driver_set_playback_speed(enabled ? sanitizedMultiplier : 1.0f);
        }

        /*
         * The runner's own schedule interval is updated on the same thread as RetroArch's internal state,
         * so a multiplier change is consistent from the next frame on.
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
     * Allows changing the multiplier on its own while fast-forward is already on.
     * To avoid changing runloop/audio/video state concurrently across threads, it still takes effect on the logic thread.
     *
     * If fast-forward is currently off, only "the multiplier to use next time it is turned on" is updated,
     * and RetroArch's fastmotion/nonblock state is left alone.
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
 * An internal-only entry point for "temporarily suspend + run a synchronous task".
 *
 * Usage constraints:
 * - this is for internal sequencing such as save/load state and restoring state at startup;
 * - pause/resume must use the non-semaphore mode, to avoid a hard wait cycle with video init / render reply /
 *   main-thread pumping;
 * - since this is itself a nested control point inside a complex flow, "never deadlock" comes first and "return immediately" second.
 *
 * By contrast:
 * - user-visible external pause/resume (going to the background, opening the settings page, etc.) still uses
 *   the semaphore mode to keep clear completion semantics.
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
     * pause has two wait modes with clearly separate roles:
     * - useBlockingSemaphore == YES
     *   For user-triggered external control flow, where the caller needs the strong "pause has completed" semantics.
     * - useBlockingSemaphore == NO
     *   Only for the internal suspend wrapper, to avoid wait cycles in complex init/state-restore chains.
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
     * Like pause, resume comes in two kinds:
     * - external user control flow: resume with strong semaphore synchronization;
     * - internal suspend wrapper: complete by polling, to avoid mutual waits during startup / load-state, etc.
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
        if ([NSThread isMainThread]) {
            /*
             * The logic thread can be inside runloop_iterate() waiting for the main thread to answer a
             * video packet (video_alive while RetroArch is paused, for one) before it ever reaches this
             * command. Waiting forever here would leave both threads stuck, so keep answering video
             * packets between short waits, as the display link would.
             */
            const int64_t sliceNanos = 2 * NSEC_PER_MSEC;
            while (dispatch_semaphore_wait(command.semaphore, dispatch_time(DISPATCH_TIME_NOW, sliceNanos)) != 0) {
                virtual_video_service_main_thread();
            }
        } else {
            dispatch_semaphore_wait(command.semaphore, DISPATCH_TIME_FOREVER);
        }
        return command.result;
    }

    /*
     * The non-semaphore mode is only for internal "avoid a wait cycle" cases.
     * Poll at short intervals here and log slow waits, so we can see whether the startup,
     * load-state, video init and similar chains block abnormally.
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
             * Refresh the timing before every frame.
             * That way turning fast-forward on/off or changing the multiplier needs no extra interruption of the logic thread; it takes effect on the next frame.
             */
            [self updateLogicTiming];
            [self drainPendingCommands];
            if (atomic_load(&d_coreUnloaded)) {
                break;
            }

            if (atomic_load(&d_paused)) {
                uint64_t skip = [self nanosToMach:1000000];
                expectedFrameStart = mach_absolute_time();
                [self waitUntilMachDeadline:expectedFrameStart + skip];
                continue;
            }

            /*
             * Schedule against an absolute deadline rather than "finish this frame, then sleep for the rest".
             * This keeps sleep jitter from accumulating frame by frame and lowers the risk of audio bursts / underruns.
             */
            uint64_t frameStartMach = mach_absolute_time();
            [self recordJitterWithActualFrameStart:frameStartMach expectedFrameStart:expectedFrameStart];

            [self runEmuPrevFrameActions];

            virtual_joypad_commit_frame_state();

            /*
             * Measure the time spent in runloop_iterate() separately.
             * Jitter shows "whether this frame started on time", while this shows "how long this frame actually ran".
             * Together they tell whether an audio problem comes from scheduling jitter or from the core simply running too long.
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
             * If the current frame has already missed the next frame's deadline, reset the scheduling baseline.
             * This is steadier than blindly "catching up on frames" and reduces audio noise from repeated jitter.
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
     * effective timing is the value the scheduler actually uses.
     * With fast-forward on, only the logic frame interval is shortened so runloop_iterate() advances emulation more often;
     * base timing is kept for logging, debugging and falling back to 1x later.
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
 * Waits until the given absolute mach deadline.
 *
 * This is the core wait function of GameLogicThread frame scheduling, replacing a plain
 * NSThread sleepForTimeInterval to reduce frame interval jitter.
 *
 * Design goals:
 * - wake up as close to the target deadline as possible
 * - avoid the large tail error of a plain sleep
 * - keep CPU cost in check without busy-waiting the whole time
 *
 * Strategy: a two-phase wait
 *
 * 1. Coarse wait
 *    - while the deadline is still far away, use mach_wait_until()
 *    - it is a kernel-level absolute-time wait, usually more precise than NSThread sleep
 *    - it greatly cuts the CPU wasted by a long busy-wait
 *
 * 2. Fine wait
 *    - once only a small window is left, stop using mach_wait_until()
 *    - because closer to the deadline, the wake-up error of a blocking wait easily exceeds the remaining time itself
 *    - so switch to short polling + sched_yield() to close in on the deadline
 *
 * Why spinThreshold is needed:
 * - busy-waiting from too early wastes CPU
 * - blocking until the very end may wake up too late
 * - so a threshold (currently about 300 microseconds) is the compromise:
 *   save power first, fine-tune at the end
 *
 * Note:
 * - this function gives no hard real-time guarantee
 * - system scheduling, QoS and other threads still affect the actual wake-up time
 * - but compared with a plain sleep it clearly improves frame pacing stability, which reduces audio noise
 */
- (void)waitUntilMachDeadline:(uint64_t)deadline {
    /*
     * Two-phase wait:
     * 1. While the deadline is far away, use mach_wait_until for a coarse wait to keep CPU use low.
     * 2. For the last short stretch, poll at short intervals to close in on the deadline and reduce sleep wake-up jitter.
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
 * Records jitter statistics for the logic thread's frame start time.
 *
 * Why record jitter instead of just looking at the average FPS:
 * - average FPS only shows whether the "long-term average speed" is close to the target
 * - but audio noise, pops and stutters usually aren't caused by the average
 * - the real problem usually comes from a few frames:
 *   they start too late or their intervals jitter too much, so the audio buffer isn't fed steadily
 *
 * So the statistics focus on:
 * - the actual frame start time actualFrameStart
 * - its deviation from the ideal deadline / expected start time expectedFrameStart
 *
 * The statistics include:
 * - sample count: total number of samples
 * - accumulated jitter: total jitter, for computing the average
 * - max jitter: shows the worst case and locates long-tail frames
 * - missed deadlines: how many times a frame started later than its deadline
 *
 * Why the absolute deviation:
 * - whether a frame is "early" or "late", both mean pacing is unstable
 * - for audio, late frames matter most, but the absolute deviation is a good first look at overall stability
 *
 * Logging strategy:
 * - log once every 600 frames, to avoid hurting performance with per-frame logs
 * - these logs are mainly for comparing:
 *   GameLogicThread vs CADisplayLink
 * - if avg_jitter / max_jitter / missed_deadlines drop noticeably,
 *   audio stability usually improves too
 *
 * Note:
 * - this records "frame start scheduling jitter"
 * - it is not the same as the time spent in runloop_iterate()
 * - for further diagnosis, core run time / runloop_iterate() duration can be measured separately
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
 * Records timing statistics for runloop_iterate().
 *
 * Why measure this method separately:
 * - jitter only tells us "whether the frame started on time"
 * - but if runloop_iterate() itself occasionally runs long, audio still stutters or pops
 * - so the cost of each logic frame is observed separately, to locate long-tail frames caused by the core / task queue / render coordination
 *
 * The statistics include:
 * - sample count: how many frames took part in the runloop timing
 * - accumulated usec: total run time, for computing the average
 * - max usec: the slowest frame, to locate occasional long tails
 *
 * Logging strategy:
 * - by default logs per time window: once every 30 seconds
 * - logs immediately when fast-forward is toggled or the multiplier changes
 * - an immediate log resets the window, and the 30-second count starts over
 * - jitter and runloop window averages / global maximums are logged together for direct comparison
 *
 * How to read it:
 * - high avg/max jitter: usually unstable scheduling or waiting
 * - high avg/max runloop: usually a single frame's emulation, task processing or graphics coordination is too heavy
 * - high missed_deadlines: target frame starts are actually being missed
 */
- (void)recordRunloopDurationUsec:(uint64_t)durationUsec {
    d_runloopSampleCount++;
    d_runloopAccumulatedUsec += durationUsec;
    d_runloopMaxUsec = MAX(d_runloopMaxUsec, durationUsec);
    [self maybeLogStatsWithForce:NO reason:"periodic"];
}

/*
 * The single entry point for logging statistics.
 *
 * When it logs:
 * - force == NO: once per 30-second window (periodic statistics)
 * - force == YES: immediately (for fast-forward state changes)
 *
 * Window semantics:
 * - avg/fps/frames/missed_deadlines in the log are window deltas "since the last log"
 * - max_jitter / max_runloop currently stay global maximums, to show the worst case over the whole run
 *
 * First call:
 * - the first call only sets up the statistics baseline
 * - if force==YES, it logs once right after setting up the baseline
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

    if(self.isStatsLoggingEnabled) {
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
    }

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
 * Converts the raw clock units returned by mach_absolute_time() to nanoseconds.
 *
 * Background:
 * - mach_absolute_time() returns neither "nanoseconds" nor "microseconds" but machine-dependent hardware clock ticks.
 * - The tick time base isn't fixed across devices, so it can't be used directly as a real time unit.
 *
 * Why convert:
 * - Measuring frame jitter, deadline deviation and wait durations needs a uniform, readable time unit.
 * - Nanoseconds are the best intermediate unit and convert easily to microseconds or milliseconds.
 *
 * Implementation:
 * - mach_timebase_info() returns numer/denom, which map mach ticks to nanoseconds:
 *     nanoseconds = machTime * numer / denom
 * - This timebase is fixed on a given device, so it only needs to be queried once.
 * - dispatch_once caches the timebase here to avoid calling the system API every frame.
 *
 * Note:
 * - This function doesn't sleep and makes no real-time guarantee; it only converts time units.
 * - Jitter statistics rely on it to bring the actual frame start time and the expected deadline into the same unit.
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
 * Converts nanoseconds back to the mach clock units used by mach_absolute_time() / mach_wait_until().
 *
 * Background:
 * - mach_wait_until() takes mach absolute clock units, not nanoseconds.
 * - So if the target deadline is first computed in "nanoseconds", it must be converted back
 *   to mach ticks before actually calling mach_wait_until().
 *
 * Why this function is needed:
 * - Our logic frame interval (e.g. 16.67ms) is easier to compute in microseconds/nanoseconds first;
 * - but the wait API uses mach ticks;
 * - so the scheduling path needs a pair of inverse conversion functions:
 *     mach -> nanos
 *     nanos -> mach
 *
 * Implementation:
 * - Convert back using the same timebase:
 *     mach = nanoseconds * denom / numer
 * - It also caches the timebase with dispatch_once to avoid fetching it repeatedly on a hot path.
 *
 * Typical uses:
 * - converting d_intervalUsec to d_intervalMachTime
 * - computing the absolute deadline
 * - passing it to mach_wait_until() for a high-precision wait
 *
 * Note:
 * - Integer conversion introduces a tiny rounding error;
 * - but compared with the scheduling jitter of NSThread sleepForTimeInterval, it is negligible.
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
 * Only the multiplier steps defined by the protocol are allowed.
 * That way the runner never sees arbitrary values, and the log cadence, UI options and schedule intervals stay consistent.
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
