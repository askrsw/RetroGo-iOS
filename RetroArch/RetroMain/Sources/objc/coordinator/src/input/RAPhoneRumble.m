//
//  RAPhoneRumble.m
//  RetroGo
//
//  Created by haharsw on 2026/10/9.
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

#import "RAPhoneRumble.h"
#import "virtual_joypad.h"

#import <CoreHaptics/CoreHaptics.h>
#import <QuartzCore/QuartzCore.h>

#include <os/lock.h>
#include <input/input_driver.h>
#include <input/mfi_joypad.h>
#include <defines/input_defines.h>
#include <utils/retrogo_log.h>

enum {
    RA_RUMBLE_STRONG = 0,
    RA_RUMBLE_WEAK   = 1,
    RA_RUMBLE_MOTORS = 2
};

/* Feel of each motor at full strength: the strong one low and dull, the weak one finer. */
static const float ra_rumble_base_intensity[RA_RUMBLE_MOTORS] = { 1.0f, 0.6f };
static const float ra_rumble_sharpness[RA_RUMBLE_MOTORS]      = { 0.2f, 0.6f };

/* A continuous event lasts at most 30 seconds, so a long rumble restarts its player before then. */
static const NSTimeInterval ra_rumble_event_duration = 30.0;
static const NSTimeInterval ra_rumble_restart_after  = 25.0;

/* Last strength each core requested, per pad and motor; written from the game logic thread. */
static os_unfair_lock ra_rumble_lock = OS_UNFAIR_LOCK_INIT;
static uint16_t ra_rumble_requested[DEFAULT_MAX_PADS][RA_RUMBLE_MOTORS];

/* Owns the engine; every method runs on `queue`. */
@interface RAPhoneRumbleDriver : NSObject
@property (nonatomic, readonly) dispatch_queue_t queue;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL suspended;
- (void)apply;
- (void)reset;
@end

@implementation RAPhoneRumbleDriver {
    BOOL _supportsHaptics;
    CHHapticEngine *_engine;
    BOOL _engineRunning;
    BOOL _engineFailureLogged;
    id<CHHapticPatternPlayer> _players[RA_RUMBLE_MOTORS];
    BOOL _running[RA_RUMBLE_MOTORS];
    float _levels[RA_RUMBLE_MOTORS];
    NSTimeInterval _startedAt[RA_RUMBLE_MOTORS];
    dispatch_source_t _restartTimer;
}

+ (instancetype)shared {
    static RAPhoneRumbleDriver *driver;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        driver = [[RAPhoneRumbleDriver alloc] init];
    });
    return driver;
}

- (instancetype)init {
    if (self = [super init]) {
        _queue = dispatch_queue_create("com.retrogo.phone-rumble", DISPATCH_QUEUE_SERIAL);
        _supportsHaptics = CHHapticEngine.capabilitiesForHardware.supportsHaptics;
        _enabled = YES;
    }
    return self;
}

- (void)apply {
    uint16_t requested[RA_RUMBLE_MOTORS] = { 0, 0 };
    unsigned pad = virtual_joypad_get_target_port();
    if (pad < DEFAULT_MAX_PADS) {
        os_unfair_lock_lock(&ra_rumble_lock);
        requested[RA_RUMBLE_STRONG] = ra_rumble_requested[pad][RA_RUMBLE_STRONG];
        requested[RA_RUMBLE_WEAK]   = ra_rumble_requested[pad][RA_RUMBLE_WEAK];
        os_unfair_lock_unlock(&ra_rumble_lock);
    }

    // A controller with its own motors on this pad already rumbles in the player's hands.
    BOOL silent = !_supportsHaptics || !_enabled || _suspended || mfi_joypad_has_rumble(pad);
    for (int motor = 0; motor < RA_RUMBLE_MOTORS; motor++) {
        float level = silent ? 0.0f : (float)requested[motor] / 65535.0f;
        [self driveMotor:motor level:level];
    }
    [self updateRestartTimer];
}

- (void)reset {
    // A game ends as its audio driver shuts down, which can stop the engine
    // before stoppedHandler reaches this queue; only a running engine is touched.
    if (_engineRunning) {
        CHHapticEngine *engine = _engine;
        id<CHHapticPatternPlayer> strong = _players[RA_RUMBLE_STRONG];
        id<CHHapticPatternPlayer> weak = _players[RA_RUMBLE_WEAK];
        [self performHaptics:^{
            [strong stopAtTime:CHHapticTimeImmediate error:nil];
            [weak stopAtTime:CHHapticTimeImmediate error:nil];
            [engine stopWithCompletionHandler:nil];
        }];
    }
    for (int motor = 0; motor < RA_RUMBLE_MOTORS; motor++) {
        _players[motor] = nil;
        _running[motor] = NO;
        _levels[motor] = 0;
    }
    [self updateRestartTimer];
    _engine = nil;
    _engineRunning = NO;
    _suspended = NO;
}

/* Core Haptics raises an exception, not an error, when a call needs a running
 * engine that the system has just stopped (the core's audio driver deactivating
 * the shared audio session, a call, the App going to the background), and that
 * stop reaches this queue only later through stoppedHandler. A raised call
 * marks the engine stopped, so the next request starts it again with new players. */
- (BOOL)performHaptics:(void (NS_NOESCAPE ^)(void))block {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        RETROGO_LOGN(GAME, "Rumble haptics call failed, engine treated as stopped: %{public}@", exception.reason);
        _engineRunning = NO;
        for (int motor = 0; motor < RA_RUMBLE_MOTORS; motor++) {
            _players[motor] = nil;
            _running[motor] = NO;
            _levels[motor] = 0;
        }
        return NO;
    }
}

#pragma mark - Motors

- (void)driveMotor:(int)motor level:(float)level {
    if (level <= 0) {
        if (_running[motor]) {
            id<CHHapticPatternPlayer> player = _players[motor];
            [self performHaptics:^{
                [player stopAtTime:CHHapticTimeImmediate error:nil];
            }];
            _running[motor] = NO;
        }
        _levels[motor] = 0;
        return;
    }

    if (![self startEngineIfNeeded]) {
        return;
    }
    id<CHHapticPatternPlayer> player = [self playerForMotor:motor];
    if (player == nil) {
        return;
    }

    if (!_running[motor]) {
        if (![self startPlayer:player motor:motor level:level]) {
            return;
        }
    } else if (level != _levels[motor]) {
        [self sendLevel:level toPlayer:player];
    }
    _levels[motor] = level;
}

- (BOOL)startPlayer:(id<CHHapticPatternPlayer>)player motor:(int)motor level:(float)level {
    __block NSError *error = nil;
    __block BOOL started = NO;
    // The level goes before and after the start, so the first moment is not at full strength.
    [self sendLevel:level toPlayer:player];
    if (![self performHaptics:^{
        started = [player startAtTime:CHHapticTimeImmediate error:&error];
    }]) {
        return NO;
    }
    if (!started) {
        RETROGO_LOGD(GAME, "Rumble player failed to start: %{public}@", error.localizedDescription);
        // A player from before an engine stop may be stale; build a new one next time.
        _players[motor] = nil;
        _running[motor] = NO;
        return NO;
    }
    [self sendLevel:level toPlayer:player];
    _running[motor] = YES;
    _startedAt[motor] = CACurrentMediaTime();
    return YES;
}

- (void)sendLevel:(float)level toPlayer:(id<CHHapticPatternPlayer>)player {
    CHHapticDynamicParameter *intensity =
        [[CHHapticDynamicParameter alloc] initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl
                                                        value:level
                                                 relativeTime:0];
    [self performHaptics:^{
        [player sendParameters:@[ intensity ] atTime:CHHapticTimeImmediate error:nil];
    }];
}

- (nullable id<CHHapticPatternPlayer>)playerForMotor:(int)motor {
    if (_players[motor] != nil) {
        return _players[motor];
    }

    NSArray<CHHapticEventParameter *> *parameters = @[
        [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity
                                                      value:ra_rumble_base_intensity[motor]],
        [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness
                                                      value:ra_rumble_sharpness[motor]],
    ];
    CHHapticEvent *event = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous
                                                         parameters:parameters
                                                       relativeTime:0
                                                           duration:ra_rumble_event_duration];
    __block NSError *error = nil;
    CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:@[ event ] parameters:@[] error:&error];
    __block id<CHHapticPatternPlayer> player = nil;
    CHHapticEngine *engine = _engine;
    if (pattern != nil && ![self performHaptics:^{
        player = [engine createPlayerWithPattern:pattern error:&error];
    }]) {
        return nil;
    }
    if (player == nil) {
        RETROGO_LOGE(GAME, "Failed to create rumble player: %{public}@", error.localizedDescription);
        return nil;
    }
    _players[motor] = player;
    return player;
}

#pragma mark - Long rumbles

- (void)updateRestartTimer {
    BOOL anyRunning = _running[RA_RUMBLE_STRONG] || _running[RA_RUMBLE_WEAK];
    if (anyRunning && _restartTimer == nil) {
        _restartTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
        dispatch_source_set_timer(_restartTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 10);
        __weak RAPhoneRumbleDriver *weakSelf = self;
        dispatch_source_set_event_handler(_restartTimer, ^{
            [weakSelf restartLongRumbles];
        });
        dispatch_resume(_restartTimer);
    } else if (!anyRunning && _restartTimer != nil) {
        dispatch_source_cancel(_restartTimer);
        _restartTimer = nil;
    }
}

/* A core may hold one strength for longer than an event lasts without a new request. */
- (void)restartLongRumbles {
    NSTimeInterval now = CACurrentMediaTime();
    for (int motor = 0; motor < RA_RUMBLE_MOTORS; motor++) {
        if (!_running[motor] || now - _startedAt[motor] < ra_rumble_restart_after) {
            continue;
        }
        id<CHHapticPatternPlayer> player = _players[motor];
        float level = _levels[motor];
        if (![self performHaptics:^{
            [player stopAtTime:CHHapticTimeImmediate error:nil];
        }]) {
            break;
        }
        _running[motor] = NO;
        [self startPlayer:player motor:motor level:level];
    }
    [self updateRestartTimer];
}

#pragma mark - Engine

- (BOOL)startEngineIfNeeded {
    if (_engineRunning) {
        return YES;
    }

    NSError *error = nil;
    if (_engine == nil) {
        _engine = [self makeEngine:&error];
    }
    if (_engine == nil || ![_engine startAndReturnError:&error]) {
        // Requests keep coming; one line per failure streak is enough.
        if (!_engineFailureLogged) {
            _engineFailureLogged = YES;
            RETROGO_LOGE(GAME, "Rumble haptic engine failed to start: %{public}@", error.localizedDescription);
        }
        return NO;
    }
    _engineRunning = YES;
    _engineFailureLogged = NO;
    return YES;
}

- (nullable CHHapticEngine *)makeEngine:(NSError **)error {
    CHHapticEngine *engine = [[CHHapticEngine alloc] initAndReturnError:error];
    if (engine == nil) {
        return nil;
    }
    // Haptics only, so the engine never touches the audio session the core plays through.
    engine.playsHapticsOnly = YES;
    // Rumble comes in short bursts; an idle shutdown would make every next one late.
    engine.autoShutdownEnabled = NO;

    __weak RAPhoneRumbleDriver *weakSelf = self;
    __weak CHHapticEngine *weakEngine = engine;
    engine.stoppedHandler = ^(CHHapticEngineStoppedReason reason) {
        RETROGO_LOGN(GAME, "Rumble haptic engine stopped, reason %ld", (long)reason);
        RAPhoneRumbleDriver *driver = weakSelf;
        if (driver == nil) return;
        dispatch_async(driver.queue, ^{
            [driver engineStopped:weakEngine];
        });
    };
    engine.resetHandler = ^{
        RETROGO_LOGN(GAME, "Rumble haptic engine reset");
        RAPhoneRumbleDriver *driver = weakSelf;
        if (driver == nil) return;
        dispatch_async(driver.queue, ^{
            [driver engineReset:weakEngine];
        });
    };
    return engine;
}

/* Stopped by the system, e.g. the App went to the background; the next request starts it again. */
- (void)engineStopped:(CHHapticEngine *)engine {
    if (engine == nil || engine != _engine) {
        return;
    }
    _engineRunning = NO;
    for (int motor = 0; motor < RA_RUMBLE_MOTORS; motor++) {
        _running[motor] = NO;
        _levels[motor] = 0;
    }
    [self updateRestartTimer];
}

/* The haptic server restarted and every player is gone; rebuild and play the current state. */
- (void)engineReset:(CHHapticEngine *)engine {
    if (engine == nil || engine != _engine) {
        return;
    }
    _engineRunning = NO;
    for (int motor = 0; motor < RA_RUMBLE_MOTORS; motor++) {
        _players[motor] = nil;
        _running[motor] = NO;
        _levels[motor] = 0;
    }
    [self apply];
}

@end

#pragma mark - C interface

void ra_phone_rumble_set_state(unsigned pad, unsigned effect, uint16_t strength)
{
    if (pad >= DEFAULT_MAX_PADS || effect >= RA_RUMBLE_MOTORS)
        return;

    // Cores that fade a rumble repeat the same value often; only a change goes further.
    os_unfair_lock_lock(&ra_rumble_lock);
    BOOL changed = ra_rumble_requested[pad][effect] != strength;
    ra_rumble_requested[pad][effect] = strength;
    os_unfair_lock_unlock(&ra_rumble_lock);

    // Only the player on the on-screen controls holds the phone.
    if (!changed || pad != virtual_joypad_get_target_port())
        return;

    RAPhoneRumbleDriver *driver = [RAPhoneRumbleDriver shared];
    dispatch_async(driver.queue, ^{
        [driver apply];
    });
}

void ra_phone_rumble_set_enabled(bool enabled)
{
    RAPhoneRumbleDriver *driver = [RAPhoneRumbleDriver shared];
    dispatch_async(driver.queue, ^{
        driver.enabled = enabled;
        [driver apply];
    });
}

void ra_phone_rumble_suspend(void)
{
    RAPhoneRumbleDriver *driver = [RAPhoneRumbleDriver shared];
    dispatch_async(driver.queue, ^{
        driver.suspended = YES;
        [driver apply];
    });
}

void ra_phone_rumble_resume(void)
{
    RAPhoneRumbleDriver *driver = [RAPhoneRumbleDriver shared];
    dispatch_async(driver.queue, ^{
        driver.suspended = NO;
        [driver apply];
    });
}

void ra_phone_rumble_reset(void)
{
    os_unfair_lock_lock(&ra_rumble_lock);
    memset(ra_rumble_requested, 0, sizeof(ra_rumble_requested));
    os_unfair_lock_unlock(&ra_rumble_lock);

    RAPhoneRumbleDriver *driver = [RAPhoneRumbleDriver shared];
    dispatch_async(driver.queue, ^{
        [driver reset];
    });
}
