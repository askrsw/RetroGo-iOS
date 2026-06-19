//
//  RANetplayCoordinator.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A LAN-discovered netplay host, exposed as a Swift-friendly value object.
/// Mirrors the fields of RetroArch's `struct netplay_host`.
@interface RANetplayHost : NSObject
@property(nonatomic, copy, readonly) NSString *address;
@property(nonatomic, assign, readonly) uint16_t port;
@property(nonatomic, copy, readonly) NSString *nickname;
@property(nonatomic, copy, readonly) NSString *coreName;
@property(nonatomic, copy, readonly) NSString *coreVersion;
@property(nonatomic, copy, readonly) NSString *contentName;
@property(nonatomic, assign, readonly) uint32_t contentCRC;
@property(nonatomic, assign, readonly) BOOL hasPassword;
@property(nonatomic, assign, readonly) BOOL hasSpectatePassword;
/// RetroGo build identity ("RetroGo/<app-version>/<cpu-arch>"). Netplay requires
/// this to match `RANetplayCoordinator.localAppIdentity` exactly.
@property(nonatomic, copy, readonly) NSString *appIdentity;
@end

/// A participant in the current netplay session (self, host, or a connected peer).
@interface RANetplayPlayer : NSObject
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, assign, readonly) NSInteger pingMs;   // -1 when unknown (e.g. self)
@property(nonatomic, assign, readonly) BOOL isSelf;
@property(nonatomic, assign, readonly) BOOL isHost;
@property(nonatomic, assign, readonly) BOOL spectating;
@end

/// Bridges RetroGo's Swift/UIKit layer to RetroArch's C netplay engine.
///
/// Design contract (see LocalDocs/15_netplay.md):
///   - This is the ONLY object that talks to the C netplay API.
///   - State-mutating calls (host/join/disconnect/spectate) are marshalled onto
///     the game-logic execution domain via the active RAGameLoopRunner, so they
///     never race `runloop_iterate()`. When no game is running they no-op.
///   - LAN discovery is independent of the running core and runs on a private
///     serial queue (socket I/O only; it does not touch core/runloop state).
///   - Lightweight state queries read engine flags directly on the caller thread,
///     matching the existing cheat-bridge pattern.
@interface RANetplayCoordinator : NSObject

@property(class, nonatomic, readonly) RANetplayCoordinator *shared;

- (instancetype)init NS_UNAVAILABLE;

#pragma mark - LAN Discovery

/// Scan the local network for netplay hosts for @c timeout seconds, then call
/// @c completion on the main queue with the discovered hosts.
///
/// On iOS this runs over Bonjour ("_ra_netplay._tcp"): the engine browses
/// asynchronously and only harvests resolved hosts when the scan finishes, so
/// discovery is one-shot rather than a live poll. Call it again (e.g. on a timer
/// or a pull-to-refresh) to get an updated list. Scans are serialized; a call
/// made while another scan is in flight completes immediately with an empty list.
- (void)scanForHostsWithTimeout:(NSTimeInterval)timeout
                     completion:(void (^)(NSArray<RANetplayHost *> *hosts))completion;

#pragma mark - Nickname

/// The netplay nickname peers see (backed by RetroArch `settings.paths.username`).
/// Persisting the user's choice across launches is the caller's responsibility;
/// call `setNickname:` before host/join so the advertised name is current.
@property(nonatomic, copy) NSString *nickname;

#pragma mark - Session Control

/// Start hosting a netplay session on @c port for the currently running game.
/// Returns NO when there is no active game or the engine failed to start.
- (BOOL)startHostOnPort:(uint16_t)port;
/// Connect to a host at @c address : @c port for the currently running game.
/// Role is fixed at join: @c asSpectator NO joins as a player (the server assigns
/// a free slot, or you spectate if the game is full), YES joins to watch only.
- (BOOL)joinHostAddress:(NSString *)address port:(uint16_t)port asSpectator:(BOOL)asSpectator;
/// Disconnect from / stop the current netplay session.
- (void)disconnect;

/// Remember the host being joined so the client's player list can show its name
/// (the engine only exposes the full client roster to the host). Call before join.
- (void)setRemoteHostNick:(NSString *)nick;

/// Current participants. Host side returns self + connected peers (names/ping/mode
/// from the engine). Client side returns the host (name from `setRemoteHostNick:`,
/// ping from the link) + self. Empty when no session.
- (NSArray<RANetplayPlayer *> *)players;

#pragma mark - State Queries

@property(nonatomic, readonly) BOOL isNetplayEnabled;
@property(nonatomic, readonly) BOOL isConnected;
@property(nonatomic, readonly) BOOL isServer;
@property(nonatomic, readonly) BOOL isSpectating;

/// This build's netplay identity ("RetroGo/<app-version>/<cpu-arch>"). Compare a
/// discovered host's `appIdentity` against this; mismatches must not be joined.
@property(nonatomic, copy, readonly) NSString *localAppIdentity;

/// CRC32 of the content currently running locally (0 if unknown). Compare against a
/// discovered host's `contentCRC`; the engine only warns on a mismatch, so the UI
/// must block joins to a different game.
@property(nonatomic, readonly) uint32_t localContentCRC;

@end

NS_ASSUME_NONNULL_END
