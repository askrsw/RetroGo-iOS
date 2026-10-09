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
    enum SelectionMode {
        /// Group members (the face buttons) move and scale together.
        case group
        /// Every control moves on its own; moving a group member takes it out of the group.
        case single
    }

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
    private(set) var selectionMode: SelectionMode = .group
    private(set) var selection: Selection?
    /// Which arcade layout is edited; the four- and six-button layouts keep separate data.
    private(set) var usesFourButtonLayout = false

    /// Called whenever the layout, the selection or the undo state changes.
    var onChange: (() -> Void)?

    private var nodes: [GameOverlayElementLayout] = []
    private var arcadeLayoutButton: GameOverlayArcadeLayoutButton?
    private let selectionFrame = SKShapeNode()
    private let verticalGuide = SKShapeNode()
    private let horizontalGuide = SKShapeNode()
    private var undoStack: [GameOverlayLayoutData] = []
    /// Layout before a slider drag; the whole drag becomes one undo step.
    private var continuousEditStart: GameOverlayLayoutData?
    private var drag: DragState?

    private struct DragState {
        let touch: ObjectIdentifier
        let startPoint: CGPoint
        let startRect: CGRect
        let startData: GameOverlayLayoutData
        /// Data the drag applies offsets to (a group member taken out of its group already has its own scale).
        let baseData: GameOverlayLayoutData
        var moved = false
        var snappedX: CGFloat?
        var snappedY: CGFloat?
    }

    private static let hitSlop: CGFloat = 10
    private static let snapDistance: CGFloat = 8
    private static let screenMargin: CGFloat = 4
    private static let hiddenAlpha: CGFloat = 0.3
    private static let dragThreshold: CGFloat = 4

    init(size: CGSize, config: GamePageOverlayConfig, supportsAnalog: Bool, layoutData: GameOverlayLayoutData,
         fourButtonLayout: Bool = false) {
        self.baseConfig = config
        self.config = config.withCombos(from: layoutData)
        self.supportsAnalog = supportsAnalog
        self.layoutData = layoutData
        self.overlayLayoutResolver = GameOverlayLayoutResolver(config: config)
        self.overlayLayoutResolver.layoutData = layoutData
        self.usesFourButtonLayout = fourButtonLayout && config.hasArcadeLayoutSwitch
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        anchorPoint = .zero
        isUserInteractionEnabled = true

        updateOverlayLayout(for: size)
        buildNodes()
        buildDecorations()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateLayout(for size: CGSize) {
        let orientationChanged = (size.width < size.height) != (self.size.width < self.size.height)
        updateOverlayLayout(for: size)
        if orientationChanged {
            // Another orientation has its own data; the old selection and undo steps no longer apply.
            cancelDrag()
            selection = nil
            undoStack.removeAll()
        }
        refresh()
    }

    var isPortrait: Bool { overlayLayoutResolver.mode == .portrait }
    var canUndo: Bool { !undoStack.isEmpty }
    var hasArcadeLayoutSwitch: Bool { config.hasArcadeLayoutSwitch }

    /// Edits the arcade four- or six-button layout. Undo steps stay: they hold the whole layout.
    func setFourButtonLayout(_ fourButtons: Bool) {
        guard hasArcadeLayoutSwitch, usesFourButtonLayout != fourButtons else { return }
        cancelDrag()
        selection = nil
        usesFourButtonLayout = fourButtons
        arcadeLayoutButton?.applyFourButtonLayout(fourButtons)
        refresh()
    }

    /// Custom data of what is being edited: this orientation, this arcade layout.
    var editedOrientation: GameOverlayLayoutData.Orientation? {
        layoutData.orientation(portrait: isPortrait, fourButton: usesFourButtonLayout)
    }

    func setSelectionMode(_ mode: SelectionMode) {
        guard selectionMode != mode else { return }
        selectionMode = mode
        cancelDrag()
        // A group selection means nothing in single mode, and the other way round.
        if case .group = selection, mode == .single { selection = nil }
        if mode == .group, case .element(let id) = selection, let element = element(id: id),
           let group = element.group, !hasCustomPosition(element) {
            selection = .group(group)
        }
        refresh()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        cancelDrag()
        setLayoutData(previous)
        refresh()
    }

    /// Back to the built-in layout for the orientation (and arcade layout) being edited.
    func resetCurrentOrientation() {
        guard editedOrientation != nil else { return }
        var data = layoutData
        data.setOrientation(nil, portrait: isPortrait, fourButton: usesFourButtonLayout)
        commit(data)
    }

    /// Records an edit made outside the scene (panel controls) as one undo step.
    func commit(_ data: GameOverlayLayoutData) {
        guard data != layoutData else { return }
        undoStack.append(layoutData)
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
        case .ndsLayoutButton, .arcadeLayoutButton:
            return Bundle.localizedString(forKey: "overlay_layout_element_layout_switch")
        case .button, .combo:
            return element.buttonTitle
        }
    }

    var opacity: Double {
        Double(overlayLayoutResolver.customOpacity)
    }

    /// Whether the selected control is hidden; nil for a group or a control that always stays.
    var selectionHidden: Bool? {
        guard case .element(let id) = selection, let element = element(id: id), element.isHideableInCustomLayout else { return nil }
        return isHiddenInLayout(element)
    }

    /// Hides the selected control or shows it again; a hidden one stays faintly drawn so it can be picked.
    func toggleSelectionHidden() {
        guard case .element(let id) = selection, let hidden = selectionHidden else { return }
        setHidden(!hidden, element: id)
    }

    /// The platform's combos, then the user's, shown or not.
    var comboElements: [GamePageOverlayElement] {
        config.elements.filter { $0.type == .combo && isAvailable($0) }
    }

    func isHiddenInLayout(_ element: GamePageOverlayElement) -> Bool {
        overlayLayoutResolver.isHiddenByCustomLayout(element, fourButtonLayout: usesFourButtonLayout)
    }

    func setHidden(_ hidden: Bool, element id: String) {
        guard let element = element(id: id) else { return }
        // Combos are hidden unless the layout says otherwise; other controls are shown.
        if element.type == .combo, !hidden, !hasCustomPosition(element) {
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
        data.setOrientation(orientation, portrait: isPortrait, fourButton: usesFourButtonLayout)
        commit(data)
    }

    // MARK: Combos

    var comboKeys: [GameOverlayComboKey] { baseConfig.comboKeys }

    /// The selection's combo title when it draws Start/Select as symbols.
    var selectionComboTitle: GameOverlayComboTitle? {
        guard case .element(let id) = selection, let title = element(id: id)?.comboTitle, title.hasSymbols else { return nil }
        return title
    }

    func userCombo(id: String) -> GameOverlayLayoutData.Combo? {
        layoutData.combos?.first { $0.id == id }
    }

    /// The selection when it is a combo the user made.
    var selectedUserCombo: GameOverlayLayoutData.Combo? {
        guard case .element(let id) = selection else { return nil }
        return userCombo(id: id)
    }

    /// Another combo, built-in or the user's, that already presses these buttons. Turbo does not
    /// make a second one: A+B and turbo A+B count as the same combo.
    func combo(binds: [String], excluding id: String?) -> GamePageOverlayElement? {
        let keys = Set(binds)
        return config.elements.first {
            $0.type == .combo && $0.id != id && Set($0.binds.map(\.rawValue)) == keys
        }
    }

    /// Saves a combo; a new one is shown in the orientation being edited, at a free spot, and selected.
    func saveCombo(_ combo: GameOverlayLayoutData.Combo) {
        cancelDrag()
        var data = layoutData
        let isNew = userCombo(id: combo.id) == nil
        data.saveCombo(combo)
        if isNew {
            data = placingCombo(combo.id, in: data)
            selection = .element(combo.id)
        }
        commit(data)
    }

    /// Turns turbo on or off for a combo in this layout: a user combo changes itself,
    /// a built-in one keeps the change only where it differs from the overlay JSON.
    func setComboTurbo(_ turbo: Bool, combo id: String) {
        cancelDrag()
        var data = layoutData
        if var combo = userCombo(id: id) {
            combo.turbo = turbo
            data.saveCombo(combo)
        } else if let preset = baseConfig.elements.first(where: { $0.id == id && $0.type == .combo }) {
            var overrides = data.presetComboTurbo ?? [:]
            overrides[id] = turbo == preset.isTurbo ? nil : turbo
            data.presetComboTurbo = overrides.isEmpty ? nil : overrides
        }
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
            undoStack.append(start)
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
        data.setOrientation(orientation, portrait: isPortrait, fourButton: usesFourButtonLayout)
        applyContinuous(keptOnScreen(data, selection: selection))
    }

    /// Growing a selection about its center can push it past a screen edge; move it back in.
    private func keptOnScreen(_ data: GameOverlayLayoutData, selection: Selection) -> GameOverlayLayoutData {
        var resolver = overlayLayoutResolver
        resolver.layoutData = data
        let rects = selectedElements(selection).map {
            resolver.resolveRect($0.arcadeLayoutElement(fourButtons: usesFourButtonLayout), usePolarLayout: usePolarLayout,
                                 fourButtonLayout: usesFourButtonLayout)
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
            guard let element = element(id: id), resolver.hasCustomPosition(element, fourButtonLayout: usesFourButtonLayout) else { return data }
        }
        var orientation = data.orientation(portrait: isPortrait, fourButton: usesFourButtonLayout) ?? GameOverlayLayoutData.Orientation()
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
        result.setOrientation(orientation, portrait: isPortrait, fourButton: usesFourButtonLayout)
        return result
    }

    /// Opacity belongs to the whole layout, both orientations.
    func setOpacity(_ opacity: Double) {
        var data = layoutData
        data.opacity = opacity >= 0.995 ? nil : opacity
        applyContinuous(data)
    }

    private func applyContinuous(_ data: GameOverlayLayoutData) {
        guard data != layoutData else { return }
        if continuousEditStart == nil {
            undoStack.append(layoutData)
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
        case .button, .combo:
            return GameOverlayActionButton(element: element, isTurboSupported: false, autoKeepTurbo: false, digitalChangeHandler: nil)
        case .fastButton:
            return GameOverLayFastButton(element: element, fastStateChangeHander: nil)
        case .overlayCollapse:
            return GameOverlayCollapseButton(element: element, handler: nil)
        case .n64CButton:
            return GameOverlayN64CButton(element: element, digitalHandler: nil)
        case .ndsLayoutButton:
            return GameOverlayNDSLayoutButton(element: element, digitalChangeHandler: nil)
        case .arcadeLayoutButton:
            let node = GameOverlayArcadeLayoutButton(element: element) { }
            node.applyFourButtonLayout(usesFourButtonLayout)
            arcadeLayoutButton = node
            return node
        }
    }

    func buildDecorations() {
        selectionFrame.strokeColor = .mainColor
        selectionFrame.lineWidth = 2
        selectionFrame.fillColor = SKColor.mainColor.withAlphaComponent(0.12)
        selectionFrame.zPosition = 100
        selectionFrame.isHidden = true
        addChild(selectionFrame)

        for guide in [verticalGuide, horizontalGuide] {
            guide.strokeColor = SKColor.mainColor.withAlphaComponent(0.8)
            guide.lineWidth = 1
            guide.zPosition = 99
            guide.isHidden = true
            addChild(guide)
        }
    }

    func setLayoutData(_ data: GameOverlayLayoutData) {
        let combosChanged = data.combos != layoutData.combos || data.presetComboTurbo != layoutData.presetComboTurbo
        layoutData = data
        overlayLayoutResolver.layoutData = data
        if combosChanged {
            updateComboNodes()
        }
    }

    /// Rebuilds the combo nodes after the user's combos changed (made, edited, removed, undone).
    func updateComboNodes() {
        config = baseConfig.withCombos(from: layoutData)
        nodes.removeAll { node in
            guard node.element.type == .combo else { return false }
            node.removeFromParent()
            return true
        }
        for element in config.elements where element.type == .combo {
            let node = makeNode(for: element)
            disableInteraction(node)
            addChild(node)
            nodes.append(node)
        }
    }

    func refresh() {
        // A selected combo that was hidden or removed is no longer there to edit.
        if case .element(let id) = selection, let element = element(id: id), !isShown(element) {
            selection = nil
        } else if case .element(let id) = selection, element(id: id) == nil {
            selection = nil
        }
        let opacity = overlayLayoutResolver.customOpacity
        for node in nodes {
            let element = node.element.arcadeLayoutElement(fourButtons: usesFourButtonLayout)
            _ = node.updateRect(resolveOverlayRect(element), shouldUpdatePosition: true)
            let rotates = node is GameOverlayActionButton || node is GameOverLayFastButton
            node.zRotation = resolveOverlayRotation(element, rotatesWithPolarLayout: rotates)

            // Hidden controls stay faintly visible so they can be picked and shown again;
            // hidden combos are shown again from the panel.
            if !isShown(element) {
                node.isHidden = true
            } else {
                node.isHidden = false
                node.alpha = isHiddenInLayout(element) ? opacity * Self.hiddenAlpha : opacity
            }
        }
        updateSelectionFrame()
        onChange?()
    }

    func updateSelectionFrame() {
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
    /// Frame of a control in the arcade layout being edited.
    func frame(_ element: GamePageOverlayElement) -> CGRect {
        resolveOverlayRect(element.arcadeLayoutElement(fourButtons: usesFourButtonLayout))
    }

    /// Not hidden by the JSON, nor a six-button-only key in the four-button layout.
    func isAvailable(_ element: GamePageOverlayElement) -> Bool {
        !element.isHidden && !(usesFourButtonLayout && element.isSixButtonOnly)
    }

    /// Drawn and selectable: available, and for a combo, shown by the layout.
    func isShown(_ element: GamePageOverlayElement) -> Bool {
        isAvailable(element) && !(element.type == .combo && isHiddenInLayout(element))
    }

    func hasCustomPosition(_ element: GamePageOverlayElement) -> Bool {
        overlayLayoutResolver.hasCustomPosition(element, fourButtonLayout: usesFourButtonLayout)
    }

    func selectedElements(_ selection: Selection) -> [GamePageOverlayElement] {
        switch selection {
        case .group(let name):
            return config.elements.filter { $0.group == name && isShown($0) && !hasCustomPosition($0) }
        case .element(let id):
            return element(id: id).map { [$0] } ?? []
        }
    }

    func selectionRect(_ selection: Selection) -> CGRect? {
        let rects = selectedElements(selection).map(frame)
        guard !rects.isEmpty else { return nil }
        return rects.reduce(CGRect.null) { $0.union($1) }
    }

    private func hitSelection(at point: CGPoint) -> Selection? {
        let hits = config.elements
            .filter(isShown)
            .map { ($0, frame($0)) }
            .filter { $0.1.insetBy(dx: -Self.hitSlop, dy: -Self.hitSlop).contains(point) }
        // The smallest frame wins, so a small button over a large control stays reachable.
        guard let element = hits.min(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height })?.0 else {
            return nil
        }
        // A hidden group member is picked on its own, so it can be shown again without leaving group mode.
        if selectionMode == .group, let group = element.group, !hasCustomPosition(element), !isHiddenInLayout(element) {
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

        selection = hitSelection(at: point)
        guard let selection, let rect = selectionRect(selection) else {
            updateSelectionFrame()
            onChange?()
            return
        }

        drag = DragState(touch: ObjectIdentifier(touch), startPoint: point, startRect: rect,
                         startData: layoutData, baseData: dataForMoving(selection))
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

        var rect = drag.startRect.offsetBy(dx: point.x - drag.startPoint.x, dy: point.y - drag.startPoint.y)
        let snap = snapTargets(excluding: selection)
        let snappedX = Self.snap(values: [rect.minX, rect.midX, rect.maxX], to: snap.x)
        let snappedY = Self.snap(values: [rect.minY, rect.midY, rect.maxY], to: snap.y)
        rect.origin.x += snappedX?.delta ?? 0
        rect.origin.y += snappedY?.delta ?? 0
        rect = clamped(rect)

        if (snappedX?.line != nil && snappedX?.line != drag.snappedX) || (snappedY?.line != nil && snappedY?.line != drag.snappedY) {
            // Through Vibration, so the UI haptics switch in Settings covers it too.
            Vibration.selection.vibrate()
        }
        drag.snappedX = snappedX?.line
        drag.snappedY = snappedY?.line
        self.drag = drag
        showGuides(x: snappedX?.line, y: snappedY?.line)

        setLayoutData(moved(drag.baseData, selection: selection, from: drag.startRect, to: rect))
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
        showGuides(x: nil, y: nil)
        if drag.moved, layoutData != drag.startData {
            undoStack.append(drag.startData)
        } else {
            setLayoutData(drag.startData)
        }
        refresh()
    }

    private func cancelDrag() {
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

    /// The layout before a drag of the selection: a group member moved on its
    /// own first takes the group's scale into its own, so it keeps its size.
    func dataForMoving(_ selection: Selection) -> GameOverlayLayoutData {
        guard case .element(let id) = selection, let element = element(id: id),
              let group = element.group, !hasCustomPosition(element),
              let groupScale = currentOrientation.groups[group]?.scale, groupScale != 1 else {
            return layoutData
        }
        var orientation = currentOrientation
        var custom = orientation.elements[id] ?? GameOverlayLayoutData.Element()
        custom.scale = (custom.scale ?? 1) * groupScale
        orientation.elements[id] = custom
        var data = layoutData
        data.setOrientation(orientation, portrait: isPortrait, fourButton: usesFourButtonLayout)
        return data
    }

    func moved(_ base: GameOverlayLayoutData, selection: Selection, from start: CGRect, to rect: CGRect) -> GameOverlayLayoutData {
        var orientation = base.orientation(portrait: isPortrait, fourButton: usesFourButtonLayout) ?? GameOverlayLayoutData.Orientation()
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
        data.setOrientation(orientation, portrait: isPortrait, fourButton: usesFourButtonLayout)
        return data
    }

    /// Shows a combo in the orientation being edited at a free spot near the face buttons.
    func placingCombo(_ id: String, in data: GameOverlayLayoutData) -> GameOverlayLayoutData {
        var resolver = overlayLayoutResolver
        resolver.layoutData = data
        guard let element = baseConfig.withCombos(from: data).elements.first(where: { $0.id == id }) else { return data }
        let size = resolver.resolveRect(element, usePolarLayout: usePolarLayout, fourButtonLayout: usesFourButtonLayout).size
        let rect = freeRect(size: size, excluding: id)

        var orientation = data.orientation(portrait: isPortrait, fourButton: usesFourButtonLayout) ?? GameOverlayLayoutData.Orientation()
        var custom = orientation.elements[id] ?? GameOverlayLayoutData.Element()
        custom.layout = resolver.plainInsets(for: rect)
        custom.hidden = false
        orientation.elements[id] = custom
        var result = data
        result.setOrientation(orientation, portrait: isPortrait, fourButton: usesFourButtonLayout)
        return result
    }

    /// The spot closest to the face buttons where a control of `size` covers no other
    /// control; the screen center when the controls leave no room.
    func freeRect(size: CGSize, excluding id: String) -> CGRect {
        let gap: CGFloat = 6
        // Hidden controls leave their space free; that is what hiding them is for.
        let occupied = config.elements
            .filter { isShown($0) && !isHiddenInLayout($0) && $0.id != id }
            .map { frame($0).insetBy(dx: -gap, dy: -gap) }
        let faceButtons = selectedElements(.group("action")).map(frame).reduce(CGRect.null) { $0.union($1) }
        let target = faceButtons.isNull
            ? CGRect(x: self.size.width * 0.75, y: self.size.height * 0.25, width: 0, height: 0)
            : faceButtons.insetBy(dx: -gap, dy: -gap)

        let margin = Self.screenMargin
        let step: CGFloat = 6
        var best: (rect: CGRect, distance: CGFloat)?
        var y = margin
        while y + size.height <= self.size.height - margin {
            var x = margin
            while x + size.width <= self.size.width - margin {
                let rect = CGRect(origin: CGPoint(x: x, y: y), size: size)
                // Not between the face buttons either: a combo there is easy to press by mistake.
                if !rect.intersects(target), !occupied.contains(where: { $0.intersects(rect) }) {
                    let dx = max(target.minX - rect.maxX, 0, rect.minX - target.maxX)
                    let dy = max(target.minY - rect.maxY, 0, rect.minY - target.maxY)
                    let distance = hypot(dx, dy)
                    if distance < best?.distance ?? .greatestFiniteMagnitude {
                        best = (rect, distance)
                    }
                }
                x += step
            }
            y += step
        }
        return best?.rect ?? CGRect(x: (self.size.width - size.width) * 0.5, y: (self.size.height - size.height) * 0.5,
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
