//
//  RANetplayCoordinator.m
//  RetroMain
//
//  Created by haharsw on 2026/6/17.
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

#import "RANetplayCoordinator.h"
// Importing the internal RetroArchX.h exposes `gameLogicRunner` and the
// RAGameLoopRunner protocol used to marshal mutations onto the game-logic
// execution domain.
#import "../RetroArchX.h"
#import "../models/EmuInGameMessage.h"

#include <network/netplay/netplay.h>
#include <defines/netplay_defines.h>
#include <defines/command_defines.h>
#include <emu/command.h>
#include <emu/cheat_manager.h>
#include <emu/content.h>
#include <utils/configuration.h>

// Defined in netplay_nsnetservice.m. Builds "RetroGo/<app-version>/<cpu-arch>".
extern void netplay_retrogo_ident(char *buf, size_t len);

NS_ASSUME_NONNULL_BEGIN

#pragma mark - RANetplayHost

@interface RANetplayHost ()
- (instancetype)initWithCHost:(const struct netplay_host *)host;
@end

@implementation RANetplayHost

- (instancetype)initWithCHost:(const struct netplay_host *)host {
    self = [super init];
    if (self) {
        _address             = host->address[0] ? @(host->address) : @"";
        _port                = (uint16_t)host->port;
        _nickname            = host->nick[0] ? @(host->nick) : @"";
        _coreName            = host->core[0] ? @(host->core) : @"";
        _coreVersion         = host->core_version[0] ? @(host->core_version) : @"";
        _contentName         = host->content[0] ? @(host->content) : @"";
        _contentCRC          = (uint32_t)host->content_crc;
        _hasPassword         = host->has_password;
        _hasSpectatePassword = host->has_spectate_password;
        _appIdentity         = host->frontend[0] ? @(host->frontend) : @"";
    }
    return self;
}

@end

#pragma mark - RANetplayPlayer

@interface RANetplayPlayer ()
- (instancetype)initWithName:(NSString *)name
                      pingMs:(NSInteger)pingMs
                      isSelf:(BOOL)isSelf
                      isHost:(BOOL)isHost
                  spectating:(BOOL)spectating;
@end

@implementation RANetplayPlayer

- (instancetype)initWithName:(NSString *)name
                      pingMs:(NSInteger)pingMs
                      isSelf:(BOOL)isSelf
                      isHost:(BOOL)isHost
                  spectating:(BOOL)spectating {
    self = [super init];
    if (self) {
        _name       = [name copy] ?: @"";
        _pingMs     = pingMs;
        _isSelf     = isSelf;
        _isHost     = isHost;
        _spectating = spectating;
    }
    return self;
}

@end

#pragma mark - RANetplayCoordinator

@implementation RANetplayCoordinator {
    BOOL d_scanInFlight;
    NSString *d_remoteHostNick;
    // Session monitor (main thread): polls netplay state to surface peer-left /
    // session-ended toasts without the peer ever freezing.
    NSTimer *d_sessionTimer;
    BOOL d_prevEnabled;
    BOOL d_prevConnected;
    BOOL d_userInitiatedDisconnect;
}

+ (RANetplayCoordinator *)shared {
    static RANetplayCoordinator *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initPrivate];
    });
    return instance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        d_scanInFlight = NO;
        // A netplay session cannot survive the app being suspended (iOS suspends
        // backgrounded apps; the lockstep peer would just stall then time out).
        // On entering the background we proactively leave the session so the peer
        // gets a clean "player left" instead of a multi-second freeze.
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(ra_appDidEnterBackground)
                   name:UIApplicationDidEnterBackgroundNotification
                 object:nil];
    }
    return self;
}

#pragma mark - App lifecycle

- (void)ra_appDidEnterBackground {
    if (![self isNetplayEnabled]) {
        return;
    }
    // Hold a short background task so the "leave" packet flushes to the peer
    // before iOS suspends us.
    UIApplication *app = [UIApplication sharedApplication];
    __block UIBackgroundTaskIdentifier task =
        [app beginBackgroundTaskWithName:@"netplay.leave" expirationHandler:^{}];

    NSLog(@"[Netplay] App entering background during a session -> leaving netplay.");
    [self disconnect];

    if (task != UIBackgroundTaskInvalid) {
        [app endBackgroundTask:task];
        task = UIBackgroundTaskInvalid;
    }
}

#pragma mark - Session monitor

// netplay tears down / removes peers inside runloop_iterate on the logic thread;
// the staying side never freezes (a lone host keeps running, a client whose host
// left falls back to solo). We poll on the main thread purely to surface a toast
// so the user understands why the session changed.
- (void)ra_startSessionMonitor {
    [self ra_stopSessionMonitor];
    d_userInitiatedDisconnect = NO;
    d_prevEnabled   = [self isNetplayEnabled];
    d_prevConnected = [self isConnected];
    d_sessionTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                      target:self
                                                    selector:@selector(ra_pollSession)
                                                    userInfo:nil
                                                     repeats:YES];
    // Session just became active — refresh any "netplay active" UI (toolbar dot).
    [self ra_postNetplayStateChanged];
}

// Lets UI (e.g. the toolbar's "netplay active" green dot) refresh on session
// start/end and peer changes. GamePageToolbarView observes `.netplayStateChanged`.
- (void)ra_postNetplayStateChanged {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self ra_postNetplayStateChanged]; });
        return;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"notif_netplayStateChanged"
                                                        object:nil];
}

- (void)ra_stopSessionMonitor {
    [d_sessionTimer invalidate];
    d_sessionTimer = nil;
}

- (void)ra_pollSession {
    BOOL enabled   = [self isNetplayEnabled];
    BOOL connected = [self isConnected];

    if (enabled != d_prevEnabled || connected != d_prevConnected) {
        [self ra_postNetplayStateChanged];
    }

    if (d_prevEnabled && !enabled) {
        // Session fully ended.
        if (!d_userInitiatedDisconnect) {
            [self ra_postToast:NSLocalizedString(@"netplay_session_ended", nil)];
        }
        d_userInitiatedDisconnect = NO;
        [self ra_stopSessionMonitor];
    } else if (enabled && d_prevConnected && !connected) {
        // Still hosting, but the (only) peer left — keep waiting for rejoins.
        [self ra_postToast:NSLocalizedString(@"netplay_peer_left", nil)];
    }

    d_prevEnabled   = enabled;
    d_prevConnected = connected;
}

// Netplay determinism: cheats are not synced between peers and the savestate sync
// does not carry them, so force all active cheats OFF at runtime when a session
// starts. Only clears the live cheat_manager; the user's saved romcheat enabled
// flags are untouched (they re-enable manually after the session). Must run on the
// logic thread (called from inside the host/join logic block). The engine boundary
// `setCheats` also forces-off during a session, covering any later re-push.
- (void)ra_forceDisableCheatsForSession {
    unsigned n = cheat_manager_get_size();
    if (n == 0) {
        return;
    }
    for (unsigned i = 0; i < n; i++) {
        cheat_manager_state.cheats[i].state = false;
    }
    cheat_manager_apply_cheats(false);
}

- (void)ra_postToast:(NSString *)text {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self ra_postToast:text]; });
        return;
    }
    EmuInGameMessage *msg = [[EmuInGameMessage alloc] initWithMessage:text
                                                                title:nil
                                                                 type:EmuInGameMessageInfo
                                                             duration:3.5
                                                             priority:0];
    // Matches NotificationNames.swift `.showInGameMessage` which GamePageViewController observes.
    [[NSNotificationCenter defaultCenter] postNotificationName:@"notif_showInGameMessage"
                                                        object:msg];
}

#pragma mark - Logic-thread marshalling

// Runs a state-mutating C netplay call on the game-logic execution domain so it
// never races `runloop_iterate()`. Mirrors the cheat bridge's mutation pattern.
// Returns NO (and no-ops) when there is no active game loop runner.
- (BOOL)ra_runControlOnLogicThread:(BOOL (^)(void))block label:(NSString *)label {
    id<RAGameLoopRunner> runner = [RetroArchX shared].gameLogicRunner;
    if (runner == nil) {
        NSLog(@"[Netplay] %@ skipped: no active game loop runner (no game running).",
              label);
        return NO;
    }
    NSObject *ret = [runner suspendGameLoopAndPerformSync:^NSObject * _Nullable {
        return @(block());
    } runOnLogicThread:YES];
    return [(NSNumber *)ret boolValue];
}

#pragma mark - LAN Discovery

// iOS discovery runs over Bonjour (NSNetService, type "_ra_netplay._tcp"). The
// engine browses asynchronously while discovery is initialized and only harvests
// resolved services into `discovered_hosts` on deinit (netplay_mdns_finish_discovery).
// So a scan is inherently: start browse -> wait -> finish/harvest -> read. The
// Bonjour browser lives on the main run loop, so the whole lifecycle is driven on
// the main queue to avoid racing the browser's delegate callbacks.
//
// The legacy raw IPv4 UDP broadcast is also kicked off for cross-platform hosts,
// but it is largely sandboxed on iOS; Bonjour is the path that works here.
- (void)scanForHostsWithTimeout:(NSTimeInterval)timeout
                     completion:(void (^)(NSArray<RANetplayHost *> *hosts))completion {
    void (^finish)(NSArray<RANetplayHost *> *) = ^(NSArray<RANetplayHost *> *hosts) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(hosts); });
        }
    };

    dispatch_async(dispatch_get_main_queue(), ^{
#ifdef HAVE_NETPLAYDISCOVERY
        if (self->d_scanInFlight) {
            NSLog(@"[Netplay] LAN scan ignored: a scan is already in flight.");
            finish(@[]);
            return;
        }
        self->d_scanInFlight = YES;

        // Start a fresh browse session (Bonjour) plus a best-effort UDP query.
        netplay_discovery_driver_ctl(RARCH_NETPLAY_DISCOVERY_CTL_LAN_CLEAR_RESPONSES, NULL);
        if (!init_netplay_discovery()) {
            NSLog(@"[Netplay] LAN discovery init failed.");
            self->d_scanInFlight = NO;
            finish(@[]);
            return;
        }
        netplay_discovery_driver_ctl(RARCH_NETPLAY_DISCOVERY_CTL_LAN_SEND_QUERY, NULL);
        NSLog(@"[Netplay] LAN scan started (%.1fs)...", timeout);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(timeout * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            // Drain any UDP responses (cross-platform hosts), then deinit, which
            // harvests resolved Bonjour services into discovered_hosts.
            netplay_discovery_driver_ctl(RARCH_NETPLAY_DISCOVERY_CTL_LAN_GET_RESPONSES, NULL);
            deinit_netplay_discovery();

            net_driver_state_t *net_st = networking_state_get_ptr();
            struct netplay_host_list *list = &net_st->discovered_hosts;
            NSMutableArray<RANetplayHost *> *arr =
                [NSMutableArray arrayWithCapacity:list->size];
            for (size_t i = 0; i < list->size; i++) {
                [arr addObject:[[RANetplayHost alloc] initWithCHost:&list->hosts[i]]];
            }
            NSArray<RANetplayHost *> *result = [arr copy];

            netplay_discovery_driver_ctl(RARCH_NETPLAY_DISCOVERY_CTL_LAN_CLEAR_RESPONSES, NULL);
            self->d_scanInFlight = NO;
            NSLog(@"[Netplay] LAN scan finished: %lu host(s).",
                  (unsigned long)result.count);
            finish(result);
        });
#else
        NSLog(@"[Netplay] LAN discovery unavailable (HAVE_NETPLAYDISCOVERY off).");
        finish(@[]);
#endif
    });
}

#pragma mark - Session Control

- (BOOL)startHostOnPort:(uint16_t)port {
    return [self ra_runControlOnLogicThread:^BOOL {
        settings_t *settings = config_get_ptr();
        if (port != 0) {
            settings->uints.netplay_port = port;
        }
        // Netplay sessions must keep running even when unfocused (e.g. while the
        // netplay room panel is up). The pause came from RetroArch's
        // pause-when-unfocused logic firing while netplay was still off (then
        // ALLOW_PAUSE is true). Clear it now, BEFORE netplay exists, because once
        // netplay is up ALLOW_PAUSE becomes false and CMD_EVENT_UNPAUSE no-ops.
        // After init, the same ALLOW_PAUSE==false skips the focus-pause entirely,
        // so this single unpause sticks for the whole session.
        settings->bools.netplay_allow_pausing = false;
        // The host is always a player (player 1).
        settings->bools.netplay_start_as_spectator = false;
        // LAN-only: don't attempt UPnP/NAT traversal (it's for internet hosting and
        // only produces a misleading "UPnP port mapping failed" toast on LAN).
        settings->bools.netplay_nat_traversal = false;
        command_event(CMD_EVENT_UNPAUSE, NULL);
        netplay_driver_ctl(RARCH_NETPLAY_CTL_ENABLE_SERVER, NULL);
        bool ok = command_event(CMD_EVENT_NETPLAY_INIT, NULL);
        NSLog(@"[Netplay] startHost port=%u -> %s (enabled=%d server=%d)",
              settings->uints.netplay_port, ok ? "ok" : "FAILED",
              netplay_driver_ctl(RARCH_NETPLAY_CTL_IS_ENABLED, NULL),
              netplay_driver_ctl(RARCH_NETPLAY_CTL_IS_SERVER, NULL));
        if (ok) {
            [self ra_forceDisableCheatsForSession];
            // The session monitor uses an NSTimer + posts UI notifications, so it
            // must live on the main thread (this block may run on the logic thread
            // under the thread runner).
            dispatch_async(dispatch_get_main_queue(), ^{ [self ra_startSessionMonitor]; });
        }
        return ok;
    } label:@"startHost"];
}

- (BOOL)joinHostAddress:(NSString *)address port:(uint16_t)port asSpectator:(BOOL)asSpectator {
    if (address.length == 0) {
        NSLog(@"[Netplay] join skipped: empty address.");
        return NO;
    }
    NSString *hostStr = (port != 0)
        ? [NSString stringWithFormat:@"%@|%u", address, port]
        : [address copy];
    return [self ra_runControlOnLogicThread:^BOOL {
        // Keep the session running while unfocused (see startHost for rationale).
        config_get_ptr()->bools.netplay_allow_pausing = false;
        // Role is fixed at join time (no mid-session play/spectate toggling, which
        // had broken slot semantics): start as player or spectator per the choice.
        config_get_ptr()->bools.netplay_start_as_spectator = asSpectator;
        command_event(CMD_EVENT_UNPAUSE, NULL);
        // init_netplay() early-returns unless NETPLAY_ENABLED is set, and branches
        // server/client on the IS_CLIENT flag. Mark this side as a client first
        // (mirrors RetroArch's own '-C' connect path), then connect directly.
        netplay_driver_ctl(RARCH_NETPLAY_CTL_ENABLE_CLIENT, NULL);
        // CMD_EVENT_NETPLAY_INIT_DIRECT decodes the "address|port" string
        // synchronously via netplay_decode_hostname, so a transient buffer is fine.
        bool ok = command_event(CMD_EVENT_NETPLAY_INIT_DIRECT,
                                (void *)hostStr.UTF8String);
        NSLog(@"[Netplay] join %@ -> %s (enabled=%d connected=%d)",
              hostStr, ok ? "ok" : "FAILED",
              netplay_driver_ctl(RARCH_NETPLAY_CTL_IS_ENABLED, NULL),
              netplay_driver_ctl(RARCH_NETPLAY_CTL_IS_CONNECTED, NULL));
        if (ok) {
            [self ra_forceDisableCheatsForSession];
            // See startHost: monitor must run on the main thread.
            dispatch_async(dispatch_get_main_queue(), ^{ [self ra_startSessionMonitor]; });
        }
        return ok;
    } label:@"join"];
}

- (void)disconnect {
    // Mark this teardown as user/app-initiated so the session monitor stays quiet
    // (no "session ended" toast) — that toast is only for peer-initiated drops.
    d_userInitiatedDisconnect = YES;
    [self ra_runControlOnLogicThread:^BOOL {
        bool ok = command_event(CMD_EVENT_NETPLAY_DISCONNECT, NULL);
        NSLog(@"[Netplay] disconnect -> %s", ok ? "ok" : "noop");
        return ok;
    } label:@"disconnect"];
}

- (void)setRemoteHostNick:(NSString *)nick {
    d_remoteHostNick = [nick copy];
}

- (NSArray<RANetplayPlayer *> *)players {
    if (![self isNetplayEnabled]) {
        return @[];
    }
    net_driver_state_t *net_st = networking_state_get_ptr();
    BOOL server        = netplay_driver_ctl(RARCH_NETPLAY_CTL_IS_SERVER, NULL);
    BOOL selfSpectate  = netplay_driver_ctl(RARCH_NETPLAY_CTL_IS_SPECTATING, NULL);
    settings_t *settings = config_get_ptr();
    NSString *selfName = settings->paths.username[0] ? @(settings->paths.username) : @"";

    NSMutableArray<RANetplayPlayer *> *result = [NSMutableArray array];

    if (server) {
        // Host's own slot first, then each connected peer from the engine roster.
        [result addObject:[[RANetplayPlayer alloc] initWithName:selfName pingMs:-1
                                                         isSelf:YES isHost:YES
                                                     spectating:selfSpectate]];
        netplay_driver_ctl(RARCH_NETPLAY_CTL_REFRESH_CLIENT_INFO, NULL);
        for (size_t i = 0; i < net_st->client_info_count; i++) {
            netplay_client_info_t *c = &net_st->client_info[i];
            NSString *name = c->name[0] ? @(c->name) : @"";
            BOOL spec      = (c->mode == NETPLAY_CONNECTION_SPECTATING);
            [result addObject:[[RANetplayPlayer alloc] initWithName:name
                                                             pingMs:(NSInteger)c->ping
                                                             isSelf:NO isHost:NO
                                                         spectating:spec]];
        }
    } else {
        // Client: the engine doesn't expose the full roster, so show host + self.
        // Host name comes from the join (setRemoteHostNick:); ping from the link.
        NSString *hostName = d_remoteHostNick.length > 0 ? d_remoteHostNick : @"";
        [result addObject:[[RANetplayPlayer alloc] initWithName:hostName
                                                         pingMs:(NSInteger)net_st->latest_ping
                                                         isSelf:NO isHost:YES
                                                     spectating:NO]];
        [result addObject:[[RANetplayPlayer alloc] initWithName:selfName pingMs:-1
                                                         isSelf:YES isHost:NO
                                                     spectating:selfSpectate]];
    }
    return result;
}

#pragma mark - State Queries

// These read simple engine flags; cheap enough to run on the caller thread,
// matching the existing cheat-bridge read pattern.
- (BOOL)isNetplayEnabled {
    return netplay_driver_ctl(RARCH_NETPLAY_CTL_IS_ENABLED, NULL);
}

- (BOOL)isConnected {
    return netplay_driver_ctl(RARCH_NETPLAY_CTL_IS_CONNECTED, NULL);
}

- (BOOL)isServer {
    return netplay_driver_ctl(RARCH_NETPLAY_CTL_IS_SERVER, NULL);
}

- (BOOL)isSpectating {
    return netplay_driver_ctl(RARCH_NETPLAY_CTL_IS_SPECTATING, NULL);
}

- (NSString *)localAppIdentity {
    char buf[128];
    netplay_retrogo_ident(buf, sizeof(buf));
    return @(buf);
}

- (uint32_t)localContentCRC {
    return (uint32_t)content_get_crc();
}

#pragma mark - Nickname

- (void)setNickname:(NSString *)nickname {
    if (nickname.length == 0) {
        return;
    }
    // netplay copies settings->paths.username into netplay->nick at init, which is
    // what peers see / Bonjour advertises. Persisting the user's choice is the
    // UI's job; here we just push it into settings before host/join.
    settings_t *settings = config_get_ptr();
    [nickname getCString:settings->paths.username
              maxLength:sizeof(settings->paths.username)
               encoding:NSUTF8StringEncoding];
}

- (NSString *)nickname {
    settings_t *settings = config_get_ptr();
    return settings->paths.username[0] ? @(settings->paths.username) : @"";
}

@end

NS_ASSUME_NONNULL_END
