//
//  GameOverlayLayoutEditorScene.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/8.
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
import UIKit
import ObjcHelper

/// Scene for moving the on-screen controls of a custom layout.
///
/// Kept apart from `GamePageOverlayScene` like the binding scene: it builds the
/// same control nodes so the layout looks exactly as in game, but switches off
/// their touch handling and sends no input. The scene owns the touches: a tap
/// selects, a drag moves the selection with snapping and stays on screen.
///
/// Only the orientation the scene is showing is edited; rotating the device
/// switches to the other orientation's data. The edited layout is `layoutData`;
/// nothing is saved here.
final class GameOverlayLayoutEditorScene: SKScene, GameOverlaySceneLayouting {
    enum Selection: Equatable {
        case group(String)
        case element(String)
    }

    /// The overlay JSON; `config` adds the combos of the layout being edited.
    private let baseConfig: GamePageOverlayConfig
    private var config: GamePageOverlayConfig
    private let supportsAnalog: Bool

    var overlayLayoutResolver: GameOverlayLayoutResolver
    let usePolarLayout = true

    private(set) var layoutData: GameOverlayLayoutData
    var macroDefinitions: [GameOverlayMacro] { layoutData.macros ?? [] }
    var macrosToSave: [GameOverlayMacro] { macroDefinitions }
    private(set) var selectedSlotId: String?
    private(set) var selection: Selection?

    /// Called whenever the layout, the selection or the undo state changes.
    var onChange: (() -> Void)?
    var onEditSlot: ((String) -> Void)?

    private var nodes: [GameOverlayElementLayout] = []
    private let selectionFrame = SKShapeNode()
    private let memberFrame = SKShapeNode()
    private let emptySlotsNode = SKNode()
    private let verticalGuide = SKShapeNode()
    private let horizontalGuide = SKShapeNode()
    private let grid = SKShapeNode()
    private struct UndoState {
        let data: GameOverlayLayoutData
        let macros: [GameOverlayMacro]
    }
    private var undoStack: [UndoState] = []
    /// Layout before a slider drag; the whole drag becomes one undo step.
    private var continuousEditStart: GameOverlayLayoutData?
    private var drag: DragState?

    private struct DragState {
        let touch: ObjectIdentifier
        let startPoint: CGPoint
        let startRect: CGRect
        let startData: GameOverlayLayoutData
        var moved = false
        var snappedX: CGFloat?
        var snappedY: CGFloat?
    }

    private static let hitSlop: CGFloat = 10
    private static let snapDistance: CGFloat = 8
    private static let screenMargin: CGFloat = 4
    private static let hiddenAlpha: CGFloat = 0.3
    private static let dragThreshold: CGFloat = 4

    init(size: CGSize, config: GamePageOverlayConfig, supportsAnalog: Bool, layoutData: GameOverlayLayoutData) {
        self.baseConfig = config
        self.config = config.withCombos(from: layoutData)
        self.supportsAnalog = supportsAnalog
        self.layoutData = layoutData
        self.overlayLayoutResolver = GameOverlayLayoutResolver(config: self.config)
        self.overlayLayoutResolver.layoutData = layoutData
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        anchorPoint = .zero
        isUserInteractionEnabled = true

        updateOverlayLayout(for: size)
        updateGrid()
        buildNodes()
        buildDecorations()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateLayout(for size: CGSize) {
        let orientationChanged = (size.width < size.height) != (self.size.width < self.size.height)
        updateOverlayLayout(for: size)
        updateGrid()
        if orientationChanged {
            // Another orientation has its own data; the old selection and undo steps no longer apply.
            cancelDrag()
            selection = nil
            selectedSlotId = nil
            undoStack.removeAll()
        }
        refresh()
    }

    var isPortrait: Bool { overlayLayoutResolver.mode == .portrait }
    var canUndo: Bool { !undoStack.isEmpty }
    /// Custom data of what is being edited: this orientation.
    var editedOrientation: GameOverlayLayoutData.Orientation? {
        layoutData.orientation(portrait: isPortrait)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        cancelDrag()
        setLayoutData(previous.data)
        updateComboNodes()
        refresh()
    }

    /// Back to the built-in layout for the orientation being edited.
    func resetCurrentOrientation() {
        guard editedOrientation != nil else { return }
        var data = layoutData
        data.setOrientation(nil, portrait: isPortrait)
        commit(data)
    }

    /// Records an edit made outside the scene (panel controls) as one undo step.
    func commit(_ data: GameOverlayLayoutData) {
        guard data != layoutData else { return }
        undoStack.append(.init(data: layoutData, macros: macroDefinitions))
        setLayoutData(data)
        refresh()
    }

    // MARK: Panel edits

    /// Size multiplier of the selection as the user sees it.
    var selectionScale: Double? {
        switch selection {
        case .group(let name):
            return currentOrientation.groups[name]?.scale ?? 1
        case .element(let id):
            return currentOrientation.elements[id]?.scale ?? 1
        case nil:
            return nil
        }
    }

    /// What the panel calls the selection.
    var selectionTitle: String? {
        switch selection {
        case .group(let name):
            return Self.groupTitle(name)
        case .element(let id):
            guard let element = element(id: id) else { return nil }
            return Self.elementTitle(element)
        case nil:
            return nil
        }
    }

    static func groupTitle(_ name: String) -> String {
        name == "action" ? Bundle.localizedString(forKey: "overlay_layout_group_action") : name
    }

    static func elementTitle(_ element: GamePageOverlayElement) -> String {
        switch element.type {
        case .dpad, .directional:
            return Bundle.localizedString(forKey: "overlay_layout_element_dpad")
        case .stick:
            return Bundle.localizedString(forKey: "overlay_layout_element_stick")
        case .fastButton:
            return Bundle.localizedString(forKey: "overlay_layout_element_fast")
        case .overlayCollapse:
            return Bundle.localizedString(forKey: "overlay_layout_element_collapse")
        case .n64CButton:
            return "C"
        case .ndsLayoutButton:
            return Bundle.localizedString(forKey: "overlay_layout_element_layout_switch")
        case .button, .combo, .macro:
            return element.buttonTitle
        }
    }

    /// Whether the selected control is hidden; nil for a group or a control that always stays.
    var selectionHidden: Bool? {
        guard case .element(let id) = selection, let element = element(id: id), element.isHideableInCustomLayout else { return nil }
        return isHiddenInLayout(element)
    }

    struct FanSlot {
        let id: String
        let element: GamePageOverlayElement?
        let rect: CGRect
        let rotation: CGFloat
        let hidden: Bool
    }
    var selectedGroupName: String? {
        guard case .group(let name) = selection else { return nil }
        return name
    }
    var fanSlots: [FanSlot] {
        guard let name = selectedGroupName else { return [] }
        return overlayLayoutResolver.fanSlotElements.filter { $0.group == name }.compactMap { slot in
            guard let rect = overlayLayoutResolver.slotRect(slot.id) else { return nil }
            let occupant = overlayLayoutResolver.occupant(of: slot.id)
            return FanSlot(id: slot.id, element: occupant, rect: occupant.map(frame) ?? rect,
                rotation: occupant.map { resolveOverlayRotation($0, rotatesWithPolarLayout: true) } ?? 0,
                hidden: occupant.map(isHiddenInLayout) ?? false)
        }
    }
    var canEditFan: Bool { !fanSlots.isEmpty }
    var selectedFan: GameOverlayLayoutData.Fan {
        selectedGroupName.flatMap { currentOrientation.groups[$0]?.fan } ?? .init()
    }
    var fanHasOuterRing: Bool {
        let radii = overlayLayoutResolver.fanSlotElements.compactMap {
            isPortrait ? $0.geometry.polarPortraitLayout?.radius : $0.geometry.polarLandscapeLayout?.radius
        }
        return (radii.max() ?? 0) - (radii.min() ?? 0) > 1
    }
    func selectFanSlot(_ id: String) {
        guard let slot = overlayLayoutResolver.fanSlotElements.first(where: { $0.id == id }), let name = slot.group else { return }
        cancelDrag()
        selectedSlotId = id
        selection = .group(name)
        refresh()
    }
    func slotCandidates(_ id: String) -> [GamePageOverlayElement] {
        config.elements.filter { isAvailable($0) && GameOverlayLayoutResolver.canEnterFan($0)
            && (overlayLayoutResolver.slot(for: $0) == nil || overlayLayoutResolver.slot(for: $0)?.id == id) }
    }
    func toggleGroupMemberHidden() {
        guard let id = selectedSlotId, let member = overlayLayoutResolver.occupant(of: id), member.isHideableInCustomLayout else { return }
        setHidden(!isHiddenInLayout(member), element: member.id)
    }
    func removeSelectedSlot() {
        guard let id = selectedSlotId else { return }
        assignSlot(id, elementId: nil)
    }
    func assignSlot(_ slotId: String, elementId: String?) {
        guard let slot = overlayLayoutResolver.fanSlotElements.first(where: { $0.id == slotId }) else { return }
        let old = overlayLayoutResolver.occupant(of: slotId)
        guard old?.id != elementId else { return }
        if let elementId, !slotCandidates(slotId).contains(where: { $0.id == elementId }) { return }
        cancelDrag()
        var data = layoutData
        var orientation = currentOrientation
        if orientation.slots == nil {
            orientation.slots = Dictionary(uniqueKeysWithValues: overlayLayoutResolver.fanSlotElements.map {
                ($0.id, overlayLayoutResolver.occupant(of: $0.id)?.id ?? "")
            })
        }
        orientation.slots?[slotId] = elementId ?? ""
        if let elementId {
            var custom = orientation.elements[elementId] ?? .init()
            custom.layout = nil; custom.rotation = nil
            custom.scale = nil; custom.hidden = false
            orientation.elements[elementId] = custom
        }
        data.setOrientation(orientation, portrait: isPortrait)
        if let old {
            // The fan's group scale is only a presentation transform. Restore
            // the element's default size when it leaves the fan.
            var detached = orientation.elements[old.id] ?? .init()
            detached.scale = nil
            detached.rotation = nil
            detached.hidden = false
            orientation.elements[old.id] = detached
            data.setOrientation(orientation, portrait: isPortrait)
            data = placingCombo(old.id, in: data)
        }
        selection = .group(slot.group ?? "action")
        selectedSlotId = slotId
        if continuousEditStart != nil { applyContinuous(data) } else { commit(data) }
    }
    func setFan(_ fan: GameOverlayLayoutData.Fan) {
        guard canEditFan, let name = selectedGroupName else { return }
        var orientation = currentOrientation
        var group = orientation.groups[name] ?? .init()
        group.fan = fan.isDefault ? nil : fan
        orientation.groups[name] = group.isEmpty ? nil : group
        var data = layoutData
        data.setOrientation(orientation, portrait: isPortrait)
        applyContinuous(keptOnScreen(data, selection: .group(name)))
    }
    func fanPreview() -> [FanSlot] { fanSlots }

    /// Hides the selected control or shows it again; a hidden one stays faintly drawn so it can be picked.
    func toggleSelectionHidden() {
        guard case .element(let id) = selection, let hidden = selectionHidden else { return }
        setHidden(!hidden, element: id)
    }

    /// The platform's combos, then the user's, shown or not.
    var comboElements: [GamePageOverlayElement] {
        config.elements.filter { ($0.type == .combo || $0.type == .macro) && isAvailable($0) }
    }

    func isHiddenInLayout(_ element: GamePageOverlayElement) -> Bool {
        overlayLayoutResolver.isHiddenByCustomLayout(element)
    }

    func setHidden(_ hidden: Bool, element id: String) {
        guard let element = element(id: id) else { return }
        // Combos are hidden unless the layout says otherwise; other controls are shown.
        if (element.type == .combo || element.type == .macro), !hidden, !hasCustomPosition(element), overlayLayoutResolver.slot(for: element) == nil {
            commit(placingCombo(id, in: layoutData))
            selection = .element(id)
            refresh()
            return
        }
        var orientation = currentOrientation
        var custom = orientation.elements[id] ?? GameOverlayLayoutData.Element()
        custom.hidden = hidden == element.isHiddenByDefaultInCustomLayout ? nil : hidden
        orientation.elements[id] = custom.isEmpty ? nil : custom
        var data = layoutData
        data.setOrientation(orientation, portrait: isPortrait)
        commit(data)
    }

    // MARK: Combos

    var comboKeys: [GameOverlayComboKey] { baseConfig.comboKeys }

    var suggestedComboBinds: [String] {
        guard layoutData.combos?.isEmpty ?? true else { return [] }
        let available = Set(comboKeys.map(\.bind.rawValue))
        let recommendation = baseConfig.recommendedCombo?.binds.map(\.rawValue)
            ?? ["A", "B"]
        return recommendation.filter(available.contains)
    }

    var suggestedComboTurbo: Bool { baseConfig.recommendedCombo?.isTurbo ?? true }

    /// Every combo title uses compact labels in the layout panel, including
    /// text-only combos that would otherwise fall back to a joined title.
    var selectionComboTitle: GameOverlayComboTitle? {
        guard case .element(let id) = selection, let element = element(id: id),
              let title = element.comboTitle else { return nil }
        return title
    }

    func userCombo(id: String) -> GameOverlayLayoutData.Combo? {
        layoutData.combos?.first { $0.id == id }
    }

    func userMacro(id: String) -> GameOverlayMacro? {
        layoutData.macros?.first { $0.id == id }
    }

    func saveMacro(_ definition: GameOverlayMacro, shown: Bool) {
        cancelDrag()
        undoStack.append(.init(data: layoutData, macros: macroDefinitions))
        var macro = definition
        if macro.id.isEmpty {
            let reserved = Set(config.elements.map(\.id) + macroDefinitions.map(\.id))
            macro.id = GameOverlayMacro.makeId(reservedIds: reserved)
        }
        let buttonId = macro.id
        let isNew = userMacro(id: buttonId) == nil
        var data = layoutData
        var macros = data.macros ?? []
        macros.removeAll { $0.id == macro.id }
        macros.append(macro)
        data.macros = macros
        if isNew {
            data = placingCombo(buttonId, in: data)
            data = placingCombo(buttonId, in: data, portrait: !isPortrait)
        }
        var orientation = data.orientation(portrait: isPortrait) ?? .init()
        var custom = orientation.elements[buttonId] ?? .init()
        custom.hidden = !shown
        orientation.elements[buttonId] = custom
        data.setOrientation(orientation, portrait: isPortrait)
        selection = .element(buttonId)
        selectedSlotId = nil
        setLayoutData(data)
        updateComboNodes()
        refresh()
    }

    func removeMacro(id: String) {
        var data = layoutData
        data.removeMacro(id: id)
        if selection == .element(id) { selection = nil }
        commit(data)
        refresh()
    }

    /// The selection when it is a combo the user made.
    var selectedUserCombo: GameOverlayLayoutData.Combo? {
        guard case .element(let id) = selection else { return nil }
        return userCombo(id: id)
    }

    var selectedMacroButtonId: String? {
        guard case .element(let id) = selection, userMacro(id: id) != nil else { return nil }
        return id
    }

    /// Another combo, built-in or the user's, that already presses these buttons. Turbo does not
    /// make a second one: A+B and turbo A+B count as the same combo.
    func combo(binds: [String], excluding id: String?) -> GamePageOverlayElement? {
        let keys = Set(binds)
        return config.elements.first {
            ($0.type == .combo || ($0.type == .button && $0.isTurbo)) && $0.id != id && Set($0.binds.map(\.rawValue)) == keys
        }
    }

    /// A new combo gets independent free positions in both orientations and is selected.
    func saveCombo(_ combo: GameOverlayLayoutData.Combo, shown: Bool = true) {
        cancelDrag()
        var data = layoutData
        let isNew = userCombo(id: combo.id) == nil
        data.saveCombo(combo)
        if isNew {
            data = placingCombo(combo.id, in: data)
            data = placingCombo(combo.id, in: data, portrait: !isPortrait)
            selection = .element(combo.id)
            selectedSlotId = nil
        }
        if shown, !isNew, element(id: combo.id).map(isShown) != true,
           element(id: combo.id).flatMap({ overlayLayoutResolver.slot(for: $0) }) == nil,
           data.orientation(portrait: isPortrait)?.elements[combo.id]?.layout == nil {
            data = placingCombo(combo.id, in: data)
        }
        var orientation = data.orientation(portrait: isPortrait) ?? .init()
        var custom = orientation.elements[combo.id] ?? .init()
        custom.hidden = !shown
        orientation.elements[combo.id] = custom
        data.setOrientation(orientation, portrait: isPortrait)
        commit(data)
    }

    func removeCombo(id: String) {
        cancelDrag()
        var data = layoutData
        data.removeCombo(id: id)
        if selection == .element(id) {
            selection = nil
        }
        commit(data)
    }


    /// Slider edits: begin once, change many times, end once for a single undo step.
    func beginContinuousEdit() {
        cancelDrag()
        continuousEditStart = layoutData
    }

    func endContinuousEdit() {
        guard let start = continuousEditStart else { return }
        continuousEditStart = nil
        if start != layoutData {
            undoStack.append(.init(data: start, macros: macroDefinitions))
        }
        onChange?()
    }

    func setSelectionScale(_ scale: Double) {
        guard let selection else { return }
        let value = abs(scale - 1) < 0.005 ? nil : scale
        var orientation = currentOrientation
        switch selection {
        case .group(let name):
            var group = orientation.groups[name] ?? GameOverlayLayoutData.Group()
            group.scale = value
            orientation.groups[name] = group.isEmpty ? nil : group
        case .element(let id):
            var custom = orientation.elements[id] ?? GameOverlayLayoutData.Element()
            custom.scale = value
            orientation.elements[id] = custom.isEmpty ? nil : custom
        }
        var data = layoutData
        data.setOrientation(orientation, portrait: isPortrait)
        applyContinuous(keptOnScreen(data, selection: selection))
    }

    /// Growing a selection about its center can push it past a screen edge; move it back in.
    private func keptOnScreen(_ data: GameOverlayLayoutData, selection: Selection) -> GameOverlayLayoutData {
        var resolver = overlayLayoutResolver
        resolver.layoutData = data
        let rects: [CGRect]
        if case .group(let name) = selection {
            rects = resolver.fanSlotElements.filter { $0.group == name }.compactMap { resolver.slotRect($0.id) }
        } else {
            rects = selectedElements(selection).map { resolver.resolveRect($0, usePolarLayout: usePolarLayout) }
        }
        guard !rects.isEmpty else { return data }
        let rect = rects.reduce(CGRect.null) { $0.union($1) }
        let inside = clamped(rect)
        guard inside != rect else { return data }

        // Only movable selections can be moved back: a group, or a control with its own position.
        switch selection {
        case .group:
            break
        case .element(let id):
            guard let element = element(id: id), resolver.hasCustomPosition(element) else { return data }
        }
        var orientation = data.orientation(portrait: isPortrait) ?? GameOverlayLayoutData.Orientation()
        switch selection {
        case .group(let name):
            let scale = max(resolver.scaleFactor, 0.001)
            var group = orientation.groups[name] ?? GameOverlayLayoutData.Group()
            group.offsetX += Double((inside.minX - rect.minX) / scale)
            group.offsetY += Double((inside.minY - rect.minY) / scale)
            orientation.groups[name] = group
        case .element(let id):
            var custom = orientation.elements[id] ?? GameOverlayLayoutData.Element()
            custom.layout = resolver.plainInsets(for: inside)
            orientation.elements[id] = custom
        }
        var result = data
        result.setOrientation(orientation, portrait: isPortrait)
        return result
    }

    private func applyContinuous(_ data: GameOverlayLayoutData) {
        guard data != layoutData else { return }
        if continuousEditStart == nil {
            undoStack.append(.init(data: layoutData, macros: macroDefinitions))
        }
        setLayoutData(data)
        refresh()
    }
}

// MARK: - Nodes

private extension GameOverlayLayoutEditorScene {
    func buildNodes() {
        for element in config.elements {
            let node = makeNode(for: element)
            disableInteraction(node)
            addChild(node)
            nodes.append(node)
        }
    }

    /// The controls keep their look but never receive touches; the scene handles them.
    func disableInteraction(_ node: SKNode) {
        node.isUserInteractionEnabled = false
        node.children.forEach(disableInteraction)
    }

    func makeNode(for element: GamePageOverlayElement) -> GameOverlayElementLayout {
        switch element.type {
        case .dpad:
            return GameOverlayDirectionPad(element: element, digitalHandler: nil)
        case .stick:
            return GameOverlayThumbStick(element: element)
        case .directional:
            return GameOverlayDirectionalControl(element: element, supportsAnalog: supportsAnalog, digitalHandler: nil, analogHandler: nil)
        case .button, .combo, .macro:
            return GameOverlayActionButton(element: element, isTurboSupported: false, autoKeepTurbo: false, digitalChangeHandler: nil)
        case .fastButton:
            return GameOverLayFastButton(element: element, fastStateChangeHander: nil)
        case .overlayCollapse:
            return GameOverlayCollapseButton(element: element, handler: nil)
        case .n64CButton:
            return GameOverlayN64CButton(element: element, digitalHandler: nil)
        case .ndsLayoutButton:
            return GameOverlayNDSLayoutButton(element: element, digitalChangeHandler: nil)

        }
    }

    func buildDecorations() {
        grid.strokeColor = SKColor.white.withAlphaComponent(0.16)
        grid.lineWidth = 0.5
        grid.zPosition = -1
        grid.isHidden = true
        addChild(grid)
        updateGrid()
        selectionFrame.strokeColor = .mainColor
        selectionFrame.lineWidth = 2
        selectionFrame.fillColor = SKColor.mainColor.withAlphaComponent(0.12)
        selectionFrame.zPosition = 100
        selectionFrame.isHidden = true
        addChild(selectionFrame)
        memberFrame.strokeColor = .mainColor
        memberFrame.lineWidth = 3
        memberFrame.fillColor = .clear
        memberFrame.zPosition = 101
        memberFrame.isHidden = true
        addChild(memberFrame)
        emptySlotsNode.zPosition = 50
        addChild(emptySlotsNode)

        for guide in [verticalGuide, horizontalGuide] {
            guide.strokeColor = SKColor.mainColor.withAlphaComponent(0.8)
            guide.lineWidth = 1
            guide.zPosition = 99
            guide.isHidden = true
            addChild(guide)
        }
    }

    func setLayoutData(_ data: GameOverlayLayoutData) {
        let combosChanged = data.combos != layoutData.combos || data.macros != layoutData.macros
        layoutData = data
        overlayLayoutResolver.layoutData = data
        if combosChanged {
            updateComboNodes()
        }
    }

    /// Rebuilds the combo nodes after the user's combos changed (made, edited, removed, undone).
    func updateComboNodes() {
        config = baseConfig.withCombos(from: layoutData)
        let previousResolver = overlayLayoutResolver
        overlayLayoutResolver = GameOverlayLayoutResolver(config: config)
        overlayLayoutResolver.update(size: previousResolver.size, contentOffset: previousResolver.contentOffset)
        overlayLayoutResolver.layoutData = layoutData
        nodes.removeAll { node in
            guard node.element.type == .combo || node.element.type == .macro else { return false }
            node.removeFromParent()
            return true
        }
        for element in config.elements where element.type == .combo || element.type == .macro {
            let node = makeNode(for: element)
            disableInteraction(node)
            addChild(node)
            nodes.append(node)
        }
    }

    func refresh() {
        emptySlotsNode.removeAllChildren()
        for slot in overlayLayoutResolver.fanSlotElements where overlayLayoutResolver.occupant(of: slot.id) == nil {
            guard let rect = overlayLayoutResolver.slotRect(slot.id) else { continue }
            let node = SKShapeNode(ellipseOf: rect.size)
            node.position = CGPoint(x: rect.midX, y: rect.midY)
            node.strokeColor = SKColor.white.withAlphaComponent(0.45)
            node.fillColor = .clear
            node.lineWidth = 1
            let plus = SKLabelNode(text: "+")
            plus.fontName = "Helvetica"
            plus.fontSize = min(rect.height * 0.7, 28)
            plus.fontColor = .mainColor
            plus.verticalAlignmentMode = .center
            node.addChild(plus)
            emptySlotsNode.addChild(node)
        }
        // Hidden controls stay selectable in the editor; unavailable/removed ones do not.
        if case .element(let id) = selection, let element = element(id: id), !isAvailable(element) {
            selection = nil
        } else if case .element(let id) = selection, element(id: id) == nil {
            selection = nil
        }
        for node in nodes {
            let element = node.element
            if let actionButton = node as? GameOverlayActionButton {
                let group = overlayLayoutResolver.fanGroup(for: element)
                actionButton.usesFanStyle = group != nil
            }
            _ = node.updateRect(resolveOverlayRect(element), shouldUpdatePosition: true)
            let rotates = node is GameOverlayActionButton || node is GameOverLayFastButton
            node.zRotation = resolveOverlayRotation(element, rotatesWithPolarLayout: rotates)

            // Hidden controls, including combos, stay faintly visible and movable.
            if !isAvailable(element) {
                node.isHidden = true
            } else {
                node.isHidden = false
                node.alpha = isHiddenInLayout(element) ? Self.hiddenAlpha : 1
            }
        }
        updateSelectionFrame()
        onChange?()
    }

    func updateSelectionFrame() {
        memberFrame.isHidden = true
        if case .group = selection, let id = selectedSlotId, let member = overlayLayoutResolver.occupant(of: id) {
            let rect = frame(member).insetBy(dx: -3, dy: -3)
            memberFrame.path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            memberFrame.isHidden = false
        }
        guard let rect = selection.flatMap(selectionRect) else {
            selectionFrame.isHidden = true
            return
        }
        let frame = rect.insetBy(dx: -4, dy: -4)
        selectionFrame.path = CGPath(roundedRect: frame, cornerWidth: 8, cornerHeight: 8, transform: nil)
        selectionFrame.isHidden = false
    }
}

// MARK: - Selection

extension GameOverlayLayoutEditorScene {
    func element(id: String) -> GamePageOverlayElement? {
        config.elements.first { $0.id == id }
    }

    /// Elements the selection moves: a group's members still in the group, or one element.
    /// Frame of a control in the orientation being edited.
    func frame(_ element: GamePageOverlayElement) -> CGRect {
        resolveOverlayRect(element)
    }

    /// Not hidden by the built-in JSON.
    func isAvailable(_ element: GamePageOverlayElement) -> Bool {
        !element.isHidden
    }

    /// Enabled in the layout; hidden controls are still drawn/selectable in the editor.
    func isShown(_ element: GamePageOverlayElement) -> Bool {
        isAvailable(element) && !((element.type == .combo || element.type == .macro) && isHiddenInLayout(element))
    }

    func hasCustomPosition(_ element: GamePageOverlayElement) -> Bool {
        overlayLayoutResolver.hasCustomPosition(element)
    }

    func selectedElements(_ selection: Selection) -> [GamePageOverlayElement] {
        switch selection {
        case .group(let name):
            return config.elements.filter { overlayLayoutResolver.fanGroup(for: $0) == name && isAvailable($0) }
        case .element(let id):
            return element(id: id).map { [$0] } ?? []
        }
    }

    func selectionRect(_ selection: Selection) -> CGRect? {
        if case .group(let name) = selection {
            let rects = overlayLayoutResolver.fanSlotElements.filter { $0.group == name }.compactMap { overlayLayoutResolver.slotRect($0.id) }
            if !rects.isEmpty { return rects.reduce(CGRect.null) { $0.union($1) } }
        }
        let rects = selectedElements(selection).map(frame)
        guard !rects.isEmpty else { return nil }
        return rects.reduce(CGRect.null) { $0.union($1) }
    }

    private func hitSelection(at point: CGPoint) -> Selection? {
        let hits = config.elements
            .filter(isAvailable)
            .map { ($0, frame($0)) }
            .filter { $0.1.insetBy(dx: -Self.hitSlop, dy: -Self.hitSlop).contains(point) }
        // The smallest frame wins, so a small button over a large control stays reachable.
        guard let element = hits.min(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height })?.0 else {
            selectedSlotId = nil
            if let rect = selectionRect(.group("action")), rect.contains(point),
               let member = overlayLayoutResolver.fanSlotElements.first {
                selectedSlotId = member.id
                return .group("action")
            }
            return nil
        }
        // A hidden group member is picked on its own, so it can be shown again without leaving group mode.
        selectedSlotId = overlayLayoutResolver.slot(for: element)?.id
        if let group = overlayLayoutResolver.fanGroup(for: element) {
            return .group(group)
        }
        return .element(element.id)
    }
}

// MARK: - Touches

extension GameOverlayLayoutEditorScene {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard drag == nil, let touch = touches.first else { return }
        let point = touch.location(in: self)
        if let slot = overlayLayoutResolver.fanSlotElements.first(where: {
            overlayLayoutResolver.occupant(of: $0.id) == nil && overlayLayoutResolver.slotRect($0.id)?.contains(point) == true
        }) {
            selectFanSlot(slot.id)
            onEditSlot?(slot.id)
            return
        }

        selection = hitSelection(at: point)
        guard let selection, let rect = selectionRect(selection) else {
            updateSelectionFrame()
            onChange?()
            return
        }

        drag = DragState(touch: ObjectIdentifier(touch), startPoint: point, startRect: rect,
                         startData: layoutData)
        refresh()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard var drag, let selection,
              let touch = touches.first(where: { ObjectIdentifier($0) == drag.touch }) else { return }
        let point = touch.location(in: self)
        // A tap only selects; small jitter must not take a member out of its group.
        if !drag.moved, hypot(point.x - drag.startPoint.x, point.y - drag.startPoint.y) < Self.dragThreshold {
            return
        }
        drag.moved = true
        grid.isHidden = false

        var rect = drag.startRect.offsetBy(dx: point.x - drag.startPoint.x, dy: point.y - drag.startPoint.y)
        let snap = snapTargets(excluding: selection)
        let snappedX = Self.snap(values: [rect.minX, rect.midX, rect.maxX], to: snap.x)
        let snappedY = Self.snap(values: [rect.minY, rect.midY, rect.maxY], to: snap.y)
        let step = gridStep
        rect.origin.x += snappedX?.delta ?? ((rect.midX / step).rounded() * step - rect.midX)
        rect.origin.y += snappedY?.delta ?? ((rect.midY / step).rounded() * step - rect.midY)
        rect = clamped(rect)

        if (snappedX?.line != nil && snappedX?.line != drag.snappedX) || (snappedY?.line != nil && snappedY?.line != drag.snappedY) {
            // Through Vibration, so the UI haptics switch in Settings covers it too.
            Vibration.selection.vibrate()
        }
        drag.snappedX = snappedX?.line
        drag.snappedY = snappedY?.line
        self.drag = drag
        showGuides(x: snappedX?.line, y: snappedY?.line)

        setLayoutData(moved(drag.startData, selection: selection, from: drag.startRect, to: rect))
        refresh()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let drag, touches.contains(where: { ObjectIdentifier($0) == drag.touch }) else { return }
        finishDrag(drag)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let drag, touches.contains(where: { ObjectIdentifier($0) == drag.touch }) else { return }
        finishDrag(drag)
    }

    private func finishDrag(_ drag: DragState) {
        self.drag = nil
        grid.isHidden = true
        showGuides(x: nil, y: nil)
        if drag.moved, layoutData != drag.startData {
            undoStack.append(.init(data: drag.startData, macros: macroDefinitions))
        } else {
            setLayoutData(drag.startData)
        }
        refresh()
    }

    private func cancelDrag() {
        grid.isHidden = true
        guard let drag else { return }
        self.drag = nil
        showGuides(x: nil, y: nil)
        setLayoutData(drag.startData)
    }
}

// MARK: - Moving

extension GameOverlayLayoutEditorScene {
    fileprivate var currentOrientation: GameOverlayLayoutData.Orientation {
        editedOrientation ?? GameOverlayLayoutData.Orientation()
    }
}

private extension GameOverlayLayoutEditorScene {

    var gridStep: CGFloat { max(4, 10 * overlayLayoutResolver.scaleFactor) }

    func updateGrid() {
        let path = CGMutablePath()
        var x: CGFloat = 0
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += gridStep
        }
        var y: CGFloat = 0
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += gridStep
        }
        grid.path = path
    }

    func moved(_ base: GameOverlayLayoutData, selection: Selection, from start: CGRect, to rect: CGRect) -> GameOverlayLayoutData {
        var orientation = base.orientation(portrait: isPortrait) ?? GameOverlayLayoutData.Orientation()
        switch selection {
        case .group(let name):
            let scale = max(overlayLayoutResolver.scaleFactor, 0.001)
            var group = orientation.groups[name] ?? GameOverlayLayoutData.Group()
            group.offsetX += Double((rect.minX - start.minX) / scale)
            group.offsetY += Double((rect.minY - start.minY) / scale)
            orientation.groups[name] = group.isEmpty ? nil : group
        case .element(let id):
            var custom = orientation.elements[id] ?? GameOverlayLayoutData.Element()
            custom.layout = overlayLayoutResolver.plainInsets(for: rect)
            orientation.elements[id] = custom
        }
        var data = base
        data.setOrientation(orientation, portrait: isPortrait)
        return data
    }

    /// Give each orientation its own position without rotating the editor.
    func placingCombo(_ id: String, in data: GameOverlayLayoutData, portrait: Bool? = nil) -> GameOverlayLayoutData {
        let portrait = portrait ?? isPortrait
        var resolver = overlayLayoutResolver
        if portrait != isPortrait {
            resolver.update(size: CGSize(width: self.size.height, height: self.size.width))
        }
        resolver.layoutData = data
        let elements = baseConfig.withCombos(from: data).elements
        guard let element = elements.first(where: { $0.id == id }) else { return data }
        let size = resolver.resolveRect(element, usePolarLayout: usePolarLayout).size
        let rect = freeRect(size: size, for: element, resolver: resolver, elements: elements)

        var orientation = data.orientation(portrait: portrait) ?? GameOverlayLayoutData.Orientation()
        var custom = orientation.elements[id] ?? GameOverlayLayoutData.Element()
        custom.layout = resolver.plainInsets(for: rect)
        custom.hidden = false
        orientation.elements[id] = custom
        var result = data
        result.setOrientation(orientation, portrait: portrait)
        return result
    }

    /// Prefer the nearest free spot to the combo's first native button. Hidden
    /// controls still occupy space in the editor, where they can be moved.
    func freeRect(size: CGSize, for combo: GamePageOverlayElement,
                  resolver: GameOverlayLayoutResolver, elements: [GamePageOverlayElement]) -> CGRect {
        let gap: CGFloat = 14
        func rect(_ element: GamePageOverlayElement) -> CGRect {
            resolver.resolveRect(element,
                                 usePolarLayout: usePolarLayout)
        }
        let existing = elements.filter { isAvailable($0) && $0.id != combo.id }
        var occupied = existing.map { (rect: rect($0).insetBy(dx: -gap, dy: -gap), combo: $0.type == .combo || $0.type == .macro) }
        let fanBounds = resolver.fanSlotElements.compactMap { resolver.slotRect($0.id) }.reduce(CGRect.null) { $0.union($1) }
        if !fanBounds.isNull { occupied.append((rect: fanBounds.insetBy(dx: -gap, dy: -gap), combo: false)) }
        let macroId: String? = {
            if case .string(let id) = combo.meta?["macro_id"] { return id }
            return nil
        }()
        let macroBind = macroDefinitions.first { $0.id == macroId }?.steps.first(where: { !$0.binds.isEmpty })?.binds.first
        let initialBind = combo.binds.first ?? macroBind.map(GamePageOverlayAction.init)
        let firstButton = initialBind.flatMap { bind in
            elements.first { $0.type == .button && $0.isNative && $0.binds == [bind] && isAvailable($0) }
        }
        let target = firstButton.map(rect).map { CGPoint(x: $0.midX, y: $0.midY) }
            ?? CGPoint(x: resolver.size.width * 0.75, y: resolver.size.height * 0.25)

        let margin = Self.screenMargin
        let step: CGFloat = 6
        var best: (rect: CGRect, distance: CGFloat)?
        var fallback: (rect: CGRect, fanOverlap: CGFloat, comboOverlap: CGFloat, overlap: CGFloat, distance: CGFloat)?
        var y = margin
        while y + size.height <= resolver.size.height - margin {
            var x = margin
            while x + size.width <= resolver.size.width - margin {
                let rect = CGRect(origin: CGPoint(x: x, y: y), size: size)
                let distance = hypot(rect.midX - target.x, rect.midY - target.y)
                let fanIntersection = fanBounds.insetBy(dx: -gap, dy: -gap).intersection(rect)
                let fanOverlap = fanIntersection.isNull ? 0 : fanIntersection.width * fanIntersection.height
                var overlap: CGFloat = 0
                var comboOverlap: CGFloat = 0
                for obstacle in occupied {
                    let intersection = obstacle.rect.intersection(rect)
                    if !intersection.isNull {
                        let area = intersection.width * intersection.height
                        overlap += area
                        if obstacle.combo { comboOverlap += area }
                    }
                }
                if overlap == 0 {
                    if distance < best?.distance ?? .greatestFiniteMagnitude {
                        best = (rect, distance)
                    }
                }
                // Keep displaced buttons outside the fan, even on crowded screens.
                if fallback == nil || fanOverlap < fallback!.fanOverlap ||
                    (fanOverlap == fallback!.fanOverlap && comboOverlap < fallback!.comboOverlap) ||
                    (fanOverlap == fallback!.fanOverlap && comboOverlap == fallback!.comboOverlap && overlap < fallback!.overlap) ||
                    (fanOverlap == fallback!.fanOverlap && comboOverlap == fallback!.comboOverlap && overlap == fallback!.overlap && distance < fallback!.distance) {
                    fallback = (rect, fanOverlap, comboOverlap, overlap, distance)
                }
                x += step
            }
            y += step
        }
        return best?.rect ?? fallback?.rect ?? CGRect(
            x: min(max(margin, target.x - size.width * 0.5), max(margin, resolver.size.width - margin - size.width)),
            y: min(max(margin, target.y - size.height * 0.5), max(margin, resolver.size.height - margin - size.height)),
            width: size.width, height: size.height)
    }


    /// Lines the selection's edges or center snap to: the screen center and
    /// edges, and the centers of the other visible controls.
    func snapTargets(excluding selection: Selection) -> (x: [CGFloat], y: [CGFloat]) {
        let moving = Set(selectedElements(selection).map(\.id))
        let others = config.elements
            .filter { isShown($0) && !isHiddenInLayout($0) && !moving.contains($0.id) }
            .map(frame)
        let margin = Self.screenMargin
        let xs = [size.width * 0.5, margin, size.width - margin] + others.map(\.midX)
        let ys = [margin, size.height - margin] + others.map(\.midY)
        return (xs, ys)
    }

    /// The smallest shift that puts one of `values` on a target line, if any is close enough.
    static func snap(values: [CGFloat], to targets: [CGFloat]) -> (delta: CGFloat, line: CGFloat)? {
        var best: (delta: CGFloat, line: CGFloat)?
        for value in values {
            for target in targets {
                let delta = target - value
                if abs(delta) <= snapDistance, abs(delta) < abs(best?.delta ?? .greatestFiniteMagnitude) {
                    best = (delta, target)
                }
            }
        }
        return best
    }

    func clamped(_ rect: CGRect) -> CGRect {
        let margin = Self.screenMargin
        var rect = rect
        rect.origin.x = min(max(rect.minX, margin), max(margin, size.width - margin - rect.width))
        rect.origin.y = min(max(rect.minY, margin), max(margin, size.height - margin - rect.height))
        return rect
    }

    func showGuides(x: CGFloat?, y: CGFloat?) {
        if let x {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            verticalGuide.path = path
        }
        verticalGuide.isHidden = x == nil

        if let y {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            horizontalGuide.path = path
        }
        horizontalGuide.isHidden = y == nil
    }
}
