// Copyright © 2026 haharsw. Part of RetroGo, GPL-3.0-or-later.
import Foundation
import RACoordinator
import os

extension Notification.Name {
    static let overlayMacroCancel = Notification.Name("RetroGo.overlayMacroCancel")
}

final class GameOverlayMacroPlayer {
    let engine: RAMacroInputEngine
    private var activeId: String?

    init(mixer: GameOverlayInputMixer) {
        let source = mixer.makeSource()
        engine = RAMacroInputEngine(output: { mask in
            for index in 0..<16 {
                guard let code = RetroArchJoypadCode(rawValue: Int32(index)) else { continue }
                mixer.send(code, down: mask & (UInt32(1) << index) != 0, from: source)
            }
        })
    }

    deinit { engine.cancel() }

    func toggle(_ macro: GameOverlayMacro) {
        if activeId == macro.id && engine.isPlaying { cancel(); return }
        play(macro)
    }

    @discardableResult func play(_ macro: GameOverlayMacro) -> Bool {
        guard macro.isValid else { return false }
        activeId = macro.id
        let accepted = engine.play(macro.steps.map { RAMacroInputStep(buttons: Self.mask($0.binds), frames: UInt($0.frames)) })
        if accepted { RetroGoLogger.game.info("Started overlay input macro \(macro.id), frames \(macro.totalFrames, privacy: .public)") }
        return accepted
    }

    func cancel() { activeId = nil; engine.cancel() }

    static func mask(_ binds: [String]) -> UInt32 {
        binds.reduce(0) { mask, bind in
            let code = Int(GamePageOverlayAction(bind).code.rawValue)
            return (0..<16).contains(code) ? mask | (UInt32(1) << code) : mask
        }
    }

}
