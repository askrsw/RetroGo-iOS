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

    private init() {}

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
        _ = RetroArchX.shared().resume()
    }

    private var shouldPauseGameLoop: Bool {
        let ra = RetroArchX.shared()
        return ra.currentCoreItem != nil && !ra.dummyCoreRunning
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
