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

/// Swift-side owner for temporary UI pauses.
///
/// This deliberately does not resume from `Lease.deinit`: the old token model
/// made resume timing depend on ARC, which can collide with game shutdown. UI
/// code must release the lease explicitly from a known lifecycle point.
@MainActor
final class GamePauseCoordinator {
    static let shared = GamePauseCoordinator()

    final class Lease {
        fileprivate let id = UUID()
        private let lock = NSLock()
        fileprivate var isReleased = false
        fileprivate weak var coordinator: GamePauseCoordinator?

        fileprivate init(coordinator: GamePauseCoordinator) {
            self.coordinator = coordinator
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
                    coordinator.release(id: id)
                }
            } else {
                Task { @MainActor in
                    coordinator.release(id: id)
                }
            }
        }
    }

    private var activeLeaseIDs: Set<UUID> = []
    /// Emulator frame callback of a frame run (`runFramesWhilePaused`); nil when none is going.
    private var frameRunToken: String?
    private var frameRunKeepsMuted = false

    private init() {}

    /// True while any UI lease keeps the game paused.
    var isHoldingPause: Bool {
        !activeLeaseIDs.isEmpty
    }

    func acquire(reason: String) -> Lease? {
        guard shouldPauseGameLoop else { return nil }

        let lease = Lease(coordinator: self)
        let wasEmpty = activeLeaseIDs.isEmpty
        activeLeaseIDs.insert(lease.id)

        if wasEmpty, !RetroArchX.shared().pause() {
            activeLeaseIDs.remove(lease.id)
            lease.isReleased = true
            return nil
        }

        return lease
    }

    private func release(id: UUID) {
        guard activeLeaseIDs.remove(id) != nil else { return }
        guard activeLeaseIDs.isEmpty else { return }
        guard shouldPauseGameLoop else { return }
        // A frame run has the game going already; it ends without pausing again.
        guard frameRunToken == nil else { return }
        _ = RetroArchX.shared().resume()
    }

    /// Lets the paused game run a few frames, muted, then pauses it again. A paused game
    /// keeps showing its last frame at the old size, so after the screen turns the picture
    /// is stretched; a few frames draw it at the new size. The game moves on by those frames.
    /// Does nothing unless a lease holds the pause.
    func runFramesWhilePaused(_ frames: Int = 6, keepMuted: Bool) {
        guard isHoldingPause, frameRunToken == nil, shouldPauseGameLoop else { return }
        let ra = RetroArchX.shared()
        ra.mute(true)
        guard ra.resume() else {
            ra.mute(keepMuted)
            return
        }
        frameRunKeepsMuted = keepMuted
        // Counted on the thread that runs the frames; the end goes back to the main thread once.
        var remaining = max(1, frames)
        frameRunToken = ra.addEmuPrevFrameAction { [weak self] in
            remaining -= 1
            guard remaining == 0 else { return }
            DispatchQueue.main.async {
                self?.finishFrameRun()
            }
        }
    }

    private func finishFrameRun() {
        guard let token = frameRunToken else { return }
        let ra = RetroArchX.shared()
        ra.removeEmuPrevFrameAction(forToken: token)
        frameRunToken = nil
        // Paused again only if something still holds the pause; a lease released meanwhile left it running.
        if !activeLeaseIDs.isEmpty {
            _ = ra.pause()
        }
        ra.mute(frameRunKeepsMuted)
    }

    private var shouldPauseGameLoop: Bool {
        let ra = RetroArchX.shared()
        guard ra.currentCoreItem != nil, !ra.dummyCoreRunning else { return false }
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
