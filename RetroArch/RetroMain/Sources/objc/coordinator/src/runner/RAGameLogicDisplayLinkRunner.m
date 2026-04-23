//
//  RAGameLogicDisplayLinkRunner.m
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

#import "RAGameLogicDisplayLinkRunner.h"

#import <UIKit/UIKit.h>
#import <retroarch_door.h>
#import <main/runloop.h>
#import <audio/audio_driver.h>
#import <input/input_driver.h>
#import <utils/driver_utils.h>
#include <gfx/video_driver.h>
#include <string.h>

#import "../virtual/virtual_joypad.h"

@implementation RAGameLogicDisplayLinkRunner {
    CADisplayLink *d_displayLink;
    NSMutableDictionary<NSString *, RetroArchXEmuFrameAction> *d_emuPrevFrameActions;

    NSInteger d_pauseCounter;
    BOOL d_fastForwardEnabled;
    double d_fastForwardMultiplier;
    double d_fastForwardTickCarry;
    
    uint64_t d_stepSampleCount;
    uint64_t d_iterateSampleCount;
    uint64_t d_budgetStopCount;
    CFTimeInterval d_statsLastLogTimeSec;
    uint64_t d_statsLastStepSampleCount;
    uint64_t d_statsLastIterateSampleCount;
    uint64_t d_statsLastBudgetStopCount;
    BOOL d_statsPaused;
}

static inline double RASanitizeFastForwardMultiplier(double multiplier) {
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

- (instancetype)initWithEmuPrevFrameActions:(NSMutableDictionary<NSString *,RetroArchXEmuFrameAction> *)prevFrameActions {
    self = [super init];
    if(self) {
        d_pauseCounter = 0;
        d_emuPrevFrameActions = prevFrameActions;
        d_fastForwardEnabled = NO;
        d_fastForwardMultiplier = 1.0;
        d_fastForwardTickCarry = 0.0;
        
        d_stepSampleCount = 0;
        d_iterateSampleCount = 0;
        d_budgetStopCount = 0;
        d_statsLastLogTimeSec = 0;
        d_statsLastStepSampleCount = 0;
        d_statsLastIterateSampleCount = 0;
        d_statsLastBudgetStopCount = 0;
        d_statsPaused = NO;
    }
    return self;
}

- (void)dealloc {
    [d_displayLink invalidate];
    d_displayLink = nil;
}

#pragma mark - RAGameLoopDriver

- (CADisplayLink *)displayLink {
    return d_displayLink;
}

- (BOOL)start {
    if(d_displayLink == nil) {
        d_pauseCounter = 0;
        d_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(step:)];
        if(@available(iOS 15.0, tvOS 15.0, *)) {
            [d_displayLink setPreferredFrameRateRange:CAFrameRateRangeDefault];
        }
        [d_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];

        // 开启音频延时逻辑
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            command_event(CMD_EVENT_AUDIO_START, NULL);
        });
    }
    return YES;
}

- (BOOL)stop {
    [self setFastForwardEnabled:NO multiplier:1.0];

    [d_displayLink invalidate];
    d_displayLink = nil;
    d_pauseCounter = 0;

    // @ref: action_ok_close_content in menu_cbs_ok.c
    BOOL ret = command_event(CMD_EVENT_UNLOAD_CORE, NULL);
    apple_platform = nil;
    return ret;
}

- (BOOL)pause {
    if(d_pauseCounter++ == 0) {
        [self maybeLogStatsWithForce:YES reason:"pause"];
        d_statsPaused = YES;
        [d_displayLink removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
        audio_driver_stop();
        return command_event(CMD_EVENT_PAUSE, NULL);
    } else {
        return YES;
    }
}

- (BOOL)resume {
    NSCAssert(d_pauseCounter > 0, @"resume called without matching pause");
    if (d_pauseCounter <= 0) {
        d_pauseCounter = 0;
        return NO;
    }

    d_pauseCounter--;

    if(d_pauseCounter == 0) {
        d_statsPaused = NO;
        [self resetStatsWindow];
        audio_driver_start(false);
        [d_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
        return command_event(CMD_EVENT_UNPAUSE, NULL);
    } else {
        return YES;
    }
}

- (BOOL)reset {
    return command_event(CMD_EVENT_RESET, NULL);
}

- (void)setFastForwardEnabled:(BOOL)enabled multiplier:(double)multiplier {
    double sanitizedMultiplier = enabled ? RASanitizeFastForwardMultiplier(multiplier) : 1.0;
    RARCH_LOG("[DisplayLinkRunner] setFastForwardEnabled enabled=%s multiplier=%.3f sanitized=%.3f\n",
              enabled ? "true" : "false",
              multiplier,
              sanitizedMultiplier);
    void (^applyFastForward)(void) = ^{
        runloop_state_t *runloop_st = runloop_state_get_ptr();
        input_driver_state_t *input_st = input_state_get_ptr();
        video_driver_state_t *video_st = video_state_get_ptr();
        if (runloop_st == NULL || video_st == NULL) {
            RARCH_WARN("[DisplayLinkRunner] setFastForwardEnabled skipped: runloop/video state unavailable\n");
            return;
        }

        [self maybeLogStatsWithForce:YES reason:"fast_forward_toggle"];
        self->d_fastForwardEnabled = enabled;
        self->d_fastForwardMultiplier = sanitizedMultiplier;
        if (!enabled) {
            self->d_fastForwardTickCarry = 0.0;
        }

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

        if (input_st != NULL) {
            if (enabled) {
                input_st->flags |= INP_FLAG_NONBLOCKING;
            } else {
                input_st->flags &= ~INP_FLAG_NONBLOCKING;
            }
        }

        driver_set_nonblock_state();
        command_event(CMD_EVENT_SET_FRAME_LIMIT, NULL);
        audio_driver_set_playback_speed(enabled ? sanitizedMultiplier : 1.0f);
        RARCH_LOG("[DisplayLinkRunner] fast-forward applied enabled=%s ratio=%.3f\n",
                  enabled ? "true" : "false",
                  enabled ? sanitizedMultiplier : 1.0);
    };

    if ([NSThread isMainThread]) {
        applyFastForward();
    } else {
        dispatch_sync(dispatch_get_main_queue(), applyFastForward);
    }
}

- (void)setFastForwardMultiplier:(double)multiplier {
    if(!d_fastForwardEnabled) {
        return;
    }

    double sanitizedMultiplier = RASanitizeFastForwardMultiplier(multiplier);
    RARCH_LOG("[DisplayLinkRunner] setFastForwardMultiplier multiplier=%.3f sanitized=%.3f\n",
              multiplier,
              sanitizedMultiplier);
    void (^applyMultiplier)(void) = ^{
        runloop_state_t *runloop_st = runloop_state_get_ptr();
        video_driver_state_t *video_st = video_state_get_ptr();
        if (runloop_st == NULL || video_st == NULL) {
            RARCH_WARN("[DisplayLinkRunner] setFastForwardMultiplier skipped: runloop/video state unavailable\n");
            return;
        }

        BOOL fastForwardEnabled = (runloop_st->flags & RUNLOOP_FLAG_FASTMOTION) != 0;
        if (!fastForwardEnabled) {
            RARCH_LOG("[DisplayLinkRunner] setFastForwardMultiplier ignored: fast-forward not enabled\n");
            return;
        }

        [self maybeLogStatsWithForce:YES reason:"fast_forward_multiplier_changing"];
        self->d_fastForwardMultiplier = sanitizedMultiplier;

        struct retro_fastforwarding_override fastforwardOverride = {0};
        fastforwardOverride.fastforward = true;
        fastforwardOverride.ratio = (float)sanitizedMultiplier;
        fastforwardOverride.notification = false;
        fastforwardOverride.inhibit_toggle = false;

        runloop_st->fastmotion_override.current = fastforwardOverride;
        runloop_st->fastmotion_override.next = fastforwardOverride;
        runloop_st->fastmotion_override.pending = false;
        runloop_st->flags |= RUNLOOP_FLAG_FASTMOTION;

        command_event(CMD_EVENT_SET_FRAME_LIMIT, NULL);
        audio_driver_set_playback_speed(sanitizedMultiplier);
        RARCH_LOG("[DisplayLinkRunner] fast-forward multiplier updated ratio=%.3f\n", sanitizedMultiplier);
    };

    if ([NSThread isMainThread]) {
        applyMultiplier();
    } else {
        dispatch_sync(dispatch_get_main_queue(), applyMultiplier);
    }
}

- (NSObject *_Nullable)suspendGameLoopAndPerformSync:(RAGameLoopSyncBlock)block runOnLogicThread:(BOOL)runOnLogicThread {
    if (![self pause]) {
        return nil;
    }

    NSObject *obj = block ? block() : nil;

    if (![self resume]) {
        return nil;
    }

    return obj;
}

#pragma mark - Internal

- (void)step:(CADisplayLink*)target {
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
        return;
    }

    NSUInteger targetIterateCount = 1;
    if (d_fastForwardEnabled) {
        double desiredIterations = RASanitizeFastForwardMultiplier(d_fastForwardMultiplier) + d_fastForwardTickCarry;
        NSUInteger integerIterations = (NSUInteger)floor(desiredIterations);
        d_fastForwardTickCarry = desiredIterations - (double)integerIterations;
        if (integerIterations < 1) {
            integerIterations = 1;
        }
        if (integerIterations > 12) {
            integerIterations = 12;
        }
        targetIterateCount = integerIterations;
    }

    /*
     * fast-forward 策略：
     * - 在当前 display tick 内“尽量多跑” runloop_iterate()
     * - 一旦接近本帧时间预算边界就停止，不跨帧追赶，避免拖慢下一次 step 回调
     */
    CFTimeInterval stepStart = target.timestamp;
    CFTimeInterval stepDuration = target.targetTimestamp - target.timestamp;
    if (stepDuration <= 0.0) {
        stepDuration = target.duration;
    }
    if (stepDuration <= 0.0) {
        stepDuration = (1.0 / 60.0);
    }
    CFTimeInterval hardDeadline = stepStart + stepDuration;
    const CFTimeInterval safetyMargin = 0.0003;

    NSUInteger executedIterateCount = 0;
    for (NSUInteger i = 0; i < targetIterateCount; i++) {
        if (i > 0) {
            CFTimeInterval now = CACurrentMediaTime();
            if (now >= (hardDeadline - safetyMargin)) {
                d_budgetStopCount++;
                break;
            }
        }

        [self runEmuPrevFrameActions];
        virtual_joypad_commit_frame_state();

        int ret = runloop_iterate();
        if (ret == -1) {
            main_exit(NULL);
            exit(0);
        }
        task_queue_check();
        executedIterateCount++;
    }
    
    d_stepSampleCount++;
    d_iterateSampleCount += executedIterateCount;
    [self maybeLogStatsWithForce:NO reason:"periodic"];

    uint32_t runloop_flags = runloop_get_flags();
    if (!(runloop_flags & RUNLOOP_FLAG_IDLE)) {
        CFRunLoopWakeUp(CFRunLoopGetMain());
    }
}

- (void)runEmuPrevFrameActions {
    NSArray<RetroArchXEmuFrameAction> *actions = [d_emuPrevFrameActions.allValues copy];
    for (RetroArchXEmuFrameAction action in actions) {
        action();
    }
}

- (NSString *)addEmuPrevFrameAction:(RetroArchXEmuFrameAction)action {
    NSString *token = NSUUID.UUID.UUIDString;
    d_emuPrevFrameActions[token] = [action copy];
    return token;
}

- (void)removeEmuPrevFrameActionForToken:(NSString *)token {
    [d_emuPrevFrameActions removeObjectForKey:token];
}

- (void)maybeLogStatsWithForce:(BOOL)force reason:(const char *)reason {
    BOOL isPauseReason = (reason != NULL && strcmp(reason, "pause") == 0);
    if (d_statsPaused && !isPauseReason) {
        return;
    }

    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (d_statsLastLogTimeSec <= 0) {
        d_statsLastLogTimeSec = now;
        d_statsLastStepSampleCount = d_stepSampleCount;
        d_statsLastIterateSampleCount = d_iterateSampleCount;
        d_statsLastBudgetStopCount = d_budgetStopCount;
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
    
    uint64_t deltaSteps = d_stepSampleCount - d_statsLastStepSampleCount;
    uint64_t deltaIterates = d_iterateSampleCount - d_statsLastIterateSampleCount;
    uint64_t deltaBudgetStops = d_budgetStopCount - d_statsLastBudgetStopCount;
    
    double displayFps = deltaSteps / elapsedSec;
    double iterateFps = deltaIterates / elapsedSec;
    double iteratePerStep = deltaSteps > 0 ? ((double)deltaIterates / (double)deltaSteps) : 0.0;
    
    RARCH_LOG("[DisplayLinkRunner][Stats][%s] window=%.2fs display_fps=%.2f iterate_fps=%.2f iterate_per_step=%.2f budget_stops=%llu fast_forward=%s multiplier=%.3f\n",
              reason,
              elapsedSec,
              displayFps,
              iterateFps,
              iteratePerStep,
              (unsigned long long)deltaBudgetStops,
              d_fastForwardEnabled ? "true" : "false",
              RASanitizeFastForwardMultiplier(d_fastForwardMultiplier));
    
    d_statsLastLogTimeSec = now;
    d_statsLastStepSampleCount = d_stepSampleCount;
    d_statsLastIterateSampleCount = d_iterateSampleCount;
    d_statsLastBudgetStopCount = d_budgetStopCount;
}

- (void)resetStatsWindow {
    d_statsLastLogTimeSec = CFAbsoluteTimeGetCurrent();
    d_statsLastStepSampleCount = d_stepSampleCount;
    d_statsLastIterateSampleCount = d_iterateSampleCount;
    d_statsLastBudgetStopCount = d_budgetStopCount;
}

@end
