//
//  GamePauseCoordinator.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/15.
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

import UIKit
import ObjectiveC
import RACoordinator
import os

/// Swift-side owner for temporary UI pauses.
///
/// This deliberately does not resume from `Lease.deinit`: the old token model
/// made resume timing depend on ARC, which can collide with game shutdown. UI
/// code must release the lease explicitly from a known lifecycle point.
@MainActor
final class GamePauseCoordinator {
    static let shared = GamePauseCoordinator()

    // Immutable identity; release state is protected by the lock. Teardown
    // fallbacks may release off-main, but coordinator work stays on MainActor.
    final class Lease: @unchecked Sendable {
        fileprivate let id = UUID()
        fileprivate let sessionID: UUID
        private let lock = NSLock()
        fileprivate var isReleased = false
        fileprivate weak var coordinator: GamePauseCoordinator?

        fileprivate init(coordinator: GamePauseCoordinator, sessionID: UUID) {
            self.coordinator = coordinator
            self.sessionID = sessionID
        }

        func release() {
            lock.lock()
            guard !isReleased else {
                lock.unlock()
                return
            }
            isReleased = true
            let coordinator = coordinator
            lock.unlock()

            guard let coordinator else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    coordinator.release(id: id, sessionID: sessionID)
                }
            } else {
                Task { @MainActor in
                    coordinator.release(id: id, sessionID: sessionID)
                }
            }
        }
    }

    private var sessionID: UUID?
    private var activeLeases: [UUID: String] = [:]
    private var ownsRunnerPause = false
    private var applicationIsActive = true
    private var inactiveLease: Lease?
    /// Emulator frame callback of a frame run (`runFramesWhilePaused`); nil when none is going.
    private var frameRunToken: String?
    private var frameRunID: UUID?
    private var frameRunKeepsMuted = false

    private init() {}

    /// True while a UI or application-lifecycle owner requests a pause.
    var isHoldingPause: Bool {
        !activeLeases.isEmpty
    }

    /// Called after the new runner starts. Leases never transfer across games.
    func beginSession(applicationIsActive: Bool) -> UUID {
        if let previous = sessionID {
            endSession(previous)
        }
        let id = UUID()
        sessionID = id
        self.applicationIsActive = true
        setApplicationActive(applicationIsActive, for: id)
        return id
    }

    /// Invalidate owners before stopping the runner. Do not resume a closing game.
    func endSession(_ id: UUID) {
        guard sessionID == id else { return }
        cancelFrameRun(reconcile: false)
        RetroGoLogger.game.debug("Ending pause session with \(self.activeLeases.count, privacy: .public) owners")
        activeLeases.removeAll()
        inactiveLease = nil
        ownsRunnerPause = false
        sessionID = nil
    }

    func setApplicationActive(_ active: Bool, for id: UUID) {
        guard sessionID == id, applicationIsActive != active else { return }
        applicationIsActive = active
        if active {
            let lease = inactiveLease
            inactiveLease = nil
            lease?.release()
        } else {
            // A temporary rotation redraw must not keep the game running behind
            // a system alert or while the application is inactive.
            cancelFrameRun()
            inactiveLease = acquire(reason: "application-inactive")
        }
    }

    func acquire(reason: String) -> Lease? {
        guard shouldPauseGameLoop, let sessionID else { return nil }
        NotificationCenter.default.post(name: .overlayMacroCancel, object: nil)

        let lease = Lease(coordinator: self, sessionID: sessionID)
        activeLeases[lease.id] = reason

        if !reconcilePause() {
            activeLeases.removeValue(forKey: lease.id)
            lease.isReleased = true
            return nil
        }

        RetroGoLogger.game.debug("Acquired pause owner \(reason, privacy: .public); count=\(self.activeLeases.count, privacy: .public)")
        return lease
    }

    private func release(id: UUID, sessionID: UUID) {
        guard self.sessionID == sessionID,
              let reason = activeLeases.removeValue(forKey: id) else { return }
        RetroGoLogger.game.debug("Released pause owner \(reason, privacy: .public); count=\(self.activeLeases.count, privacy: .public)")
        _ = reconcilePause()
    }

    /// Leases describe desired state; the coordinator owns at most one runner
    /// pause, including when owners change during a temporary frame run.
    @discardableResult
    private func reconcilePause() -> Bool {
        guard runtimeAvailable else { return false }
        let shouldPause = !activeLeases.isEmpty && frameRunID == nil
            && !RANetplayCoordinator.shared.isNetplayEnabled
        guard shouldPause != ownsRunnerPause else { return true }
        let ra = RetroArchX.shared()
        let success = shouldPause ? ra.pause() : ra.resume()
        if success {
            ownsRunnerPause = shouldPause
        } else {
            RetroGoLogger.game.error("Failed to reconcile game pause; requested=\(shouldPause, privacy: .public), owners=\(self.activeLeases.count, privacy: .public)")
        }
        return success
    }

    /// Lets the paused game run a few frames, muted, then pauses it again. A paused game
    /// keeps showing its last frame at the old size, so after the screen turns the picture
    /// is stretched; a few frames draw it at the new size. The game moves on by those frames.
    /// Does nothing unless a lease holds the pause.
    func runFramesWhilePaused(_ frames: Int = 6, keepMuted: Bool) {
        guard isHoldingPause, ownsRunnerPause, frameRunID == nil,
              applicationIsActive, shouldPauseGameLoop, let sessionID else { return }
        let ra = RetroArchX.shared()
        let runID = UUID()
        frameRunID = runID
        frameRunKeepsMuted = keepMuted
        ra.mute(true)
        guard reconcilePause() else {
            frameRunID = nil
            ra.mute(keepMuted)
            return
        }
        // Counted on the thread that runs the frames; the end goes back to the main thread once.
        var remaining = max(1, frames)
        frameRunToken = ra.addEmuPrevFrameAction { [weak self] in
            remaining -= 1
            guard remaining == 0 else { return }
            DispatchQueue.main.async {
                self?.finishFrameRun(sessionID: sessionID, runID: runID)
            }
        }
    }

    private func finishFrameRun(sessionID: UUID, runID: UUID) {
        guard self.sessionID == sessionID, frameRunID == runID else { return }
        cancelFrameRun()
    }

    private func cancelFrameRun(reconcile: Bool = true) {
        guard frameRunID != nil else { return }
        let token = frameRunToken
        frameRunID = nil
        frameRunToken = nil
        let ra = RetroArchX.shared()
        if let token { ra.removeEmuPrevFrameAction(forToken: token) }
        // Re-pause before restoring audio so the redraw cannot emit an unmuted frame.
        if reconcile { _ = reconcilePause() }
        ra.mute(frameRunKeepsMuted)
    }

    private var runtimeAvailable: Bool {
        let ra = RetroArchX.shared()
        return sessionID != nil && !ra.gameTransitionInProgress
            && ra.currentCoreItem != nil && !ra.dummyCoreRunning
    }

    private var shouldPauseGameLoop: Bool {
        guard runtimeAvailable else { return false }
        // Never pause emulation during a netplay session: netplay is lockstep and
        // can't pause unilaterally — pausing one side stalls (and would eventually
        // drop) the peer. So UI that normally pauses the game (state list, save
        // dialog, cheat list, config, toolbar layout) keeps the game running while
        // a session is active. The peer stays in sync; loads still broadcast.
        if RANetplayCoordinator.shared.isNetplayEnabled { return false }
        return true
    }
}

private var gamePauseLeaseKey: UInt8 = 0
private var gamePausePresentationObserverKey: UInt8 = 0

/// Retained by the presented controller/navigation controller. It covers the
/// path where a root pause owner has already disappeared because it pushed a
/// child controller, then the user pulls down to dismiss the whole sheet.
@MainActor
private final class GamePausePresentationObserver: NSObject, UIAdaptivePresentationControllerDelegate {
    private let lease: GamePauseCoordinator.Lease

    init(lease: GamePauseCoordinator.Lease) {
        self.lease = lease
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        lease.release()
    }
}

@MainActor
extension UIViewController {
    @discardableResult
    func acquireGamePause(reason: String) -> GamePauseCoordinator.Lease? {
        GamePauseCoordinator.shared.acquire(reason: reason)
    }

    func attachGamePauseLeaseToPresentation(_ lease: GamePauseCoordinator.Lease?) {
        guard let lease else { return }
        let host = navigationController ?? self
        guard let presentationController = host.presentationController else { return }

        let observer = GamePausePresentationObserver(lease: lease)
        presentationController.delegate = observer
        objc_setAssociatedObject(
            host,
            &gamePausePresentationObserverKey,
            observer,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    func isClosingOrBeingDismissedFromGamePauseContext() -> Bool {
        isBeingDismissed ||
            isMovingFromParent ||
            navigationController?.isBeingDismissed == true ||
            navigationController?.isMovingFromParent == true
    }
}

@MainActor
extension UIAlertController {
    static func gamePausedAlert(
        title: String?,
        message: String?,
        preferredStyle: UIAlertController.Style = .alert
    ) -> UIAlertController {
        let alert = UIAlertController(title: title, message: message, preferredStyle: preferredStyle)
        let lease = GamePauseCoordinator.shared.acquire(reason: "alert")
        objc_setAssociatedObject(alert, &gamePauseLeaseKey, lease, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return alert
    }

    func releaseGamePauseIfNeeded() {
        guard let lease = objc_getAssociatedObject(self, &gamePauseLeaseKey) as? GamePauseCoordinator.Lease else {
            return
        }
        lease.release()
        objc_setAssociatedObject(self, &gamePauseLeaseKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
