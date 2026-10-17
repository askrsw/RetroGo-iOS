#!/usr/bin/env python3
"""Exercise production page-close methods with retained pages and deferred UIKit transitions."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]


def member(source, declaration):
    start = source.index(declaration)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


SWIFT = r'''
import Foundation
import os
extension Bundle { static func localizedString(forKey key: String) -> String { key } }
enum RetroGoLogger { static let game = Logger(subsystem: "PageLifecycleTest", category: "Game") }
extension Notification.Name { static let overlayMacroCancel = Self("overlayMacroCancel") }
@MainActor final class RetroArchX {
    static let sharedInstance = RetroArchX()
    static func shared() -> RetroArchX { sharedInstance }
    var gameTransitionInProgress = false
    var stops = 0
    func clearCheats() {}
    func stop() { stops += 1 }
}
@MainActor final class GamePauseCoordinator {
    static let shared = GamePauseCoordinator()
    func endSession(_ id: UUID) {}
}
@MainActor final class GameHapticEngine {
    static let shared = GameHapticEngine()
    var stops = 0
    func stop() { stops += 1 }
}
@MainActor final class AppSettings {
    static let shared = AppSettings()
    let autoSaveLoadState = false
}
struct Core { let coreId = "test-core" }
final class Rom { var pulseImage = false; let sha256 = "hash"; let key = "key" }
enum RetroRomGameStateItem {
    static func getAutoSaveStateName(romItem: Rom?) -> String { "auto" }
}
final class RetroRomFileManager {
    static let shared = RetroRomFileManager()
    func saveState(rawName: String, showName: String?, sha256: String?, romKey: String?, autoSave: Bool) -> Bool { true }
}
final class MameCheatSession { func endSession() {} }
final class Control { var isEnabled = true; var isUserInteractionEnabled = true }
final class Toolbar { let closeButton = Control(); var isUserInteractionEnabled = true }
final class Overlay {
    var isUserInteractionEnabled = true
    var endings = 0
    func endGame() { endings += 1 }
}
final class Label { var text: String? }
final class LoadingView { let messageLabel = Label(); func uninstall() {} }
@MainActor final class Transition {
    var completion: ((Bool) -> Void)?
    func animate(alongsideTransition: ((Bool) -> Void)?, completion: ((Bool) -> Void)?) { self.completion = completion }
    func finish() { let callback = completion; completion = nil; callback?(true) }
}
@MainActor class BasePage {
    var isBeingPresented = false
    var isBeingDismissed = false
    var isMovingFromParent = false
    var presentingViewController: NSObject?
    var transitionCoordinator: Transition?
    var dismissalCompletion: (() -> Void)?
    var dismissals = 0
    var platformReleases = 0
    func releasePlatformOwnership() { platformReleases += 1 }
    func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        dismissals += 1
        isBeingDismissed = true
        dismissalCompletion = completion
    }
    func viewDidDisappear(_ animated: Bool) {}
    func finishDismissal() {
        presentingViewController = nil
        viewDidDisappear(true)
        isBeingDismissed = false
        let callback = dismissalCompletion
        dismissalCompletion = nil
        callback?()
    }
}
@MainActor final class GamePageViewController: BasePage {
    static weak var instance: GamePageViewController?
    var loaded = false
    var closeRequested = false
    var closeFinished = false
    var hasLeftPresentation = false
    var pauseSessionID: UUID? = UUID()
    let myToolbarView = Toolbar()
    let myOverlayView = Overlay()
    var myLoadingView: LoadingView? = LoadingView()
    var mameCheatSession: MameCheatSession?
    var romItem: Rom?
    let core = Core()
    override init() { super.init(); Self.instance = self }
    // PRODUCTION_METHODS
}

@main struct Checks {
    @MainActor static func main() async {
        let runtime = RetroArchX.shared()
        // A page retained by UIKit must stop blocking launch after actual dismissal.
        let old = GamePageViewController()
        old.loaded = true
        old.presentingViewController = NSObject()
        old.closeGame()
        precondition(old.closeFinished && old.myOverlayView.endings == 1 && old.platformReleases == 1)
        precondition(GamePageViewController.instance === old, "Dismissal still reserves launch")
        old.closeGame()
        precondition(old.dismissals == 1 && runtime.stops == 1)
        old.finishDismissal()
        precondition(GamePageViewController.instance == nil, "ARC lifetime must not govern launch availability")
        let next = GamePageViewController()
        old.releaseLaunchReservationIfClosed()
        let haptics = GameHapticEngine.shared.stops
        old.isBeingDismissed = true
        old.viewDidDisappear(true)
        precondition(GamePageViewController.instance === next && GameHapticEngine.shared.stops == haptics)
        next.closeGame()
        precondition(GamePageViewController.instance == nil)

        // Cancelled loading keeps its reservation even if UIKit already removed the page.
        let loading = GamePageViewController()
        runtime.gameTransitionInProgress = true
        loading.closeGame()
        loading.isBeingDismissed = true
        loading.viewDidDisappear(true)
        precondition(!loading.closeFinished && GamePageViewController.instance === loading)
        precondition(loading.myOverlayView.endings == 0 && loading.platformReleases == 0)
        runtime.gameTransitionInProgress = false
        loading.finishClosing()
        precondition(GamePageViewController.instance == nil && loading.platformReleases == 1)

        // A load failure during presentation waits for UIKit before dismissing.
        let failed = GamePageViewController()
        failed.isBeingPresented = true
        failed.presentingViewController = NSObject()
        failed.transitionCoordinator = Transition()
        failed.finishClosing()
        precondition(failed.dismissals == 0 && GamePageViewController.instance === failed)
        failed.isBeingPresented = false
        failed.transitionCoordinator?.finish()
        precondition(failed.dismissals == 1 && GamePageViewController.instance === failed)
        failed.finishDismissal()
        precondition(GamePageViewController.instance == nil)

        // A rejected presentation has no disappearance callback to clear the reservation.
        let rejected = GamePageViewController()
        rejected.verifyPresentationWasAccepted()
        try? await Task.sleep(nanoseconds: 20_000_000)
        precondition(rejected.closeFinished && GamePageViewController.instance == nil)
        let accepted = GamePageViewController()
        accepted.presentingViewController = NSObject()
        accepted.verifyPresentationWasAccepted()
        try? await Task.sleep(nanoseconds: 20_000_000)
        precondition(!accepted.closeRequested && GamePageViewController.instance === accepted)
        accepted.closeGame()
        accepted.finishDismissal()
        Swift.print("Retained-page relaunch, late callbacks, cancellation, failed/rejected presentations and duplicate close passed")
    }
}
'''

OBJC = r'''
#import <Foundation/Foundation.h>
#include <assert.h>
static id apple_platform;
@interface RAGameViewController: NSObject
- (void)releasePlatformOwnership;
@end
@implementation RAGameViewController
// PRODUCTION_METHODS
@end
int main(void) {
    @autoreleasepool {
        RAGameViewController *old = [RAGameViewController new];
        __weak id weakOld = old;
        apple_platform = old;
        [old releasePlatformOwnership];
        assert(apple_platform == nil);
        RAGameViewController *next = [RAGameViewController new];
        apple_platform = next;
        [old releasePlatformOwnership];
        assert(apple_platform == next);
        old = nil;
        assert(weakOld == nil && apple_platform == next);
        [next releasePlatformOwnership];
        assert(apple_platform == nil);
    }
    puts("Late old-page deallocation preserves the next game's render owner");
    return 0;
}
'''

page = (ROOT / "RetroGo/Page/GamePage/GamePageViewController.swift").read_text()
declarations = ["    func closeGame()", "    private func finishClosing()", "    private func dismissClosedPage()",
                "    private func releaseLaunchReservationIfClosed()", "    fileprivate func verifyPresentationWasAccepted()",
                "    private func endPauseSession()", "    override func viewDidDisappear("]
methods = "\n".join(member(page, declaration).replace("fileprivate func", "func", 1).replace("private func", "func", 1) for declaration in declarations)
base = (ROOT / "RetroArch/RetroMain/Sources/objc/coordinator/src/controllers/RAGameViewController.m").read_text()
objc_methods = "\n".join(member(base, declaration) for declaration in ["- (void)dealloc", "- (void)releasePlatformOwnership"])
with tempfile.TemporaryDirectory(prefix="retrogo-page-lifecycle-") as folder:
    folder = Path(folder)
    swift = folder / "Checks.swift"
    swift.write_text(SWIFT.replace("// PRODUCTION_METHODS", methods))
    binary = folder / "swift-checks"
    subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", "-module-cache-path", str(folder / "Modules"),
                    str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
    objc = folder / "Checks.m"
    objc.write_text(OBJC.replace("// PRODUCTION_METHODS", objc_methods))
    binary = folder / "objc-checks"
    subprocess.run(["clang", "-fobjc-arc", "-fsanitize=address,undefined", "-framework", "Foundation",
                    str(objc), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
