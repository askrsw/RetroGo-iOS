//
//  GameConfigBindingSettingPresenting.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/30.
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

import SpriteKit
import RACoordinator

protocol GameConfigBindingSettingPresenting: AnyObject where Self: SKNode {
    func bindingActionIds() -> [String]
    func bindingJoypadCode(for actionId: String) -> RetroArchJoypadCode
    func bindingBubbleAnchorPoint(for actionId: String) -> CGPoint?
    func bindingBubblePreferredPosition(for actionId: String) -> GameConfigBindingBubbleNode.PreferredPosition
    func bindingBubbleMaxWidth(for actionId: String) -> CGFloat?
    func handleBindingBubbleTouch(_ touching: Bool, for actionId: String)
}

extension GameConfigBindingSettingPresenting {
    func bindingJoypadCode(for actionId: String) -> RetroArchJoypadCode {
        .none
    }

    func bindingBubblePreferredPosition(for actionId: String) -> GameConfigBindingBubbleNode.PreferredPosition {
        .above
    }

    func bindingBubbleMaxWidth(for actionId: String) -> CGFloat? {
        nil
    }

    func handleBindingBubbleTouch(_ touching: Bool, for actionId: String) { }

    func setBindingBubbleText(_ text: String?, systemImageName: String? = nil, for actionId: String) {
        guard bindingActionIds().contains(actionId) else { return }

        if (text?.isEmpty == false) || systemImageName != nil {
            let bubble = bindingBubble(for: actionId) ?? makeBindingBubble(for: actionId)
            bubble.update(text: text ?? "", systemImageName: systemImageName)
            updateBindingBubbleLayout(for: actionId)
        } else {
            removeBindingBubble(for: actionId)
        }
    }

    func setBindingBubbleActive(_ active: Bool, for actionId: String) {
        bindingBubble(for: actionId)?.isActive = active
    }

    func updateBindingBubbleLayout(for actionId: String) {
        guard let bubble = bindingBubble(for: actionId),
              let anchor = bindingBubbleAnchorPoint(for: actionId) else {
            return
        }

        bubble.updateLayout(
            anchor: anchor,
            preferredPosition: bindingBubblePreferredPosition(for: actionId),
            maxWidth: bindingBubbleMaxWidth(for: actionId)
        )
    }

    func updateAllBindingBubbleLayouts() {
        for actionId in bindingActionIds() {
            updateBindingBubbleLayout(for: actionId)
        }
    }

    func removeBindingBubbles() {
        for key in bindingBubbleStore.allKeys {
            guard let actionId = key as? String else { continue }
            removeBindingBubble(for: actionId)
        }
    }
}

private extension GameConfigBindingSettingPresenting {
    var bindingBubbleStore: NSMutableDictionary {
        if let store = objc_getAssociatedObject(self, &bindingBubbleStoreKey) as? NSMutableDictionary {
            return store
        }

        let store = NSMutableDictionary()
        objc_setAssociatedObject(self, &bindingBubbleStoreKey, store, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return store
    }

    func bindingBubble(for actionId: String) -> GameConfigBindingBubbleNode? {
        bindingBubbleStore[actionId] as? GameConfigBindingBubbleNode
    }

    func makeBindingBubble(for actionId: String) -> GameConfigBindingBubbleNode {
        let bubble = GameConfigBindingBubbleNode()
        bubble.name = "binding-bubble-\(actionId)"
        bubble.touchChanged = { [weak self] touching in
            self?.handleBindingBubbleTouch(touching, for: actionId)
        }
        addChild(bubble)
        bindingBubbleStore[actionId] = bubble
        return bubble
    }

    func removeBindingBubble(for actionId: String) {
        bindingBubble(for: actionId)?.removeFromParent()
        bindingBubbleStore.removeObject(forKey: actionId)
    }
}

private var bindingBubbleStoreKey: UInt8 = 0

extension GameOverlayActionButton: GameConfigBindingSettingPresenting {
    func bindingActionIds() -> [String] {
        if element.isCombo {
            let parts = element.binds.map(\.rawValue)
            return ["combo_" + parts.joined(separator: "_")]
        }

        if element.binds.count == 1 {
            return [element.binds[0].rawValue]
        }

        let ids = element.binds.map { $0.rawValue }
        return ids
    }

    func bindingJoypadCode(for actionId: String) -> RetroArchJoypadCode {
        if element.isCombo, bindingActionIds().contains(actionId) {
            return element.binds.first?.code ?? .none
        }

        if element.binds.count == 1, bindingActionIds().contains(actionId) {
            return element.binds[0].code
        }

        return element.binds.first(where: { $0.rawValue == actionId })?.code ?? .none
    }

    func bindingBubbleAnchorPoint(for actionId: String) -> CGPoint? {
        guard bindingActionIds().contains(actionId) else { return nil }
        return CGPoint(x: 0, y: size.height * 0.5)
    }

    func bindingBubbleMaxWidth(for actionId: String) -> CGFloat? {
        guard bindingActionIds().contains(actionId) else { return nil }
        return size.width
    }

    func handleBindingBubbleTouch(_ touching: Bool, for actionId: String) {
        guard bindingActionIds().contains(actionId) else { return }
        applyBindingBubbleTouch(touching)
    }
}

extension GameOverlayDirectionPad: GameConfigBindingSettingPresenting {
    func bindingActionIds() -> [String] {
        ["up", "right", "down", "left"]
    }

    func bindingJoypadCode(for actionId: String) -> RetroArchJoypadCode {
        switch actionId {
        case "up":
            return .up
        case "right":
            return .right
        case "down":
            return .down
        case "left":
            return .left
        default:
            return .none
        }
    }

    func bindingBubbleAnchorPoint(for actionId: String) -> CGPoint? {
        let length = radius
        let delta = length * 0.32
        switch actionId {
        case "up":
            return CGPoint(x: 0, y: length - delta * 0.25)
        case "right":
                return CGPoint(x: length - (length - delta) * 0.5, y: delta * 0.75)
        case "down":
                return CGPoint(x: 0, y: -delta * 1.5)
        case "left":
                return CGPoint(x: -length + delta, y: delta * 0.75)
        default:
            return nil
        }
    }

    func bindingBubblePreferredPosition(for actionId: String) -> GameConfigBindingBubbleNode.PreferredPosition {
        .above
    }

    func bindingBubbleMaxWidth(for actionId: String) -> CGFloat? {
        bindingActionIds().contains(actionId) ? radius : nil
    }

    func handleBindingBubbleTouch(_ touching: Bool, for actionId: String) {
        applyBindingBubbleTouch(touching, actionId: actionId)
    }
}

extension GameOverlayN64CButton: GameConfigBindingSettingPresenting {
    func bindingActionIds() -> [String] {
        ["n64_c_up", "n64_c_right", "n64_c_down", "n64_c_left"]
    }

    func bindingJoypadCode(for actionId: String) -> RetroArchJoypadCode {
        switch actionId {
        case "n64_c_up":
            return .X
        case "n64_c_right":
            return .A
        case "n64_c_down":
            return .B
        case "n64_c_left":
            return .Y
        default:
            return .none
        }
    }

    func bindingBubbleAnchorPoint(for actionId: String) -> CGPoint? {
        let distance = radius * 0.65
        let buttonRadius = radius * 0.35

        switch actionId {
        case "n64_c_up":
            return CGPoint(x: 0, y: distance + buttonRadius)
        case "n64_c_right":
            return CGPoint(x: distance, y: buttonRadius)
        case "n64_c_down":
            return CGPoint(x: 0, y: -distance + buttonRadius)
        case "n64_c_left":
            return CGPoint(x: -distance, y: buttonRadius)
        default:
            return nil
        }
    }

    func bindingBubbleMaxWidth(for actionId: String) -> CGFloat? {
        bindingActionIds().contains(actionId) ? radius * 2 : nil
    }

    func handleBindingBubbleTouch(_ touching: Bool, for actionId: String) {
        applyBindingBubbleTouch(touching, actionId: actionId)
    }
}

extension GameOverlayNDSLayoutButton: GameConfigBindingSettingPresenting {
    func bindingActionIds() -> [String] {
        ["nds_layout_combo"]
    }

    func bindingJoypadCode(for actionId: String) -> RetroArchJoypadCode {
        .none
    }

    func bindingBubbleAnchorPoint(for actionId: String) -> CGPoint? {
        guard bindingActionIds().contains(actionId) else { return nil }
        // let size = calculateAccumulatedFrame().size
        // let radius = min(size.width, size.height) * 0.5
        return CGPoint(x: 0, y: size.height * 0.5)
    }

    func bindingBubbleMaxWidth(for actionId: String) -> CGFloat? {
        let size = element.geometry.size
        let width = CGFloat(size.width)
        return bindingActionIds().contains(actionId) ? width : nil
    }

    func handleBindingBubbleTouch(_ touching: Bool, for actionId: String) {
        guard bindingActionIds().contains(actionId) else { return }
        applyBindingBubbleTouch(touching)
    }
}

extension GameOverLayFastButton: GameConfigBindingSettingPresenting {
    func bindingActionIds() -> [String] {
        ["fast_forward"]
    }

    func bindingBubbleAnchorPoint(for actionId: String) -> CGPoint? {
        guard bindingActionIds().contains(actionId) else { return nil }
        return CGPoint(x: 0, y: size.height * 0.5)
    }

    func bindingBubbleMaxWidth(for actionId: String) -> CGFloat? {
        guard bindingActionIds().contains(actionId) else { return nil }
        return size.width
    }

    func handleBindingBubbleTouch(_ touching: Bool, for actionId: String) {
        guard bindingActionIds().contains(actionId) else { return }
        applyBindingBubbleTouch(touching)
    }
}
