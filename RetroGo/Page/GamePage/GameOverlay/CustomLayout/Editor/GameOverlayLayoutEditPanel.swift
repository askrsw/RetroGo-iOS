//
//  GameOverlayLayoutEditPanel.swift
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

import UIKit
import SnapKit
import ObjcHelper

/// Floating panel of the control layout editor. It sits over the controls it
/// edits, so it can be dragged anywhere and folded down to its title row.
final class GameOverlayLayoutEditPanel: UIView {
    struct State {
        var isPortrait: Bool
        /// Arcade four-button layout being edited; nil when the layout has no 4/6-button switch.
        var fourButtonLayout: Bool?
        var mode: GameOverlayLayoutEditorScene.SelectionMode
        var canUndo: Bool
        var canReset: Bool
        /// Name and size of the selection; nil when nothing is selected.
        var selectionTitle: String?
        var selectionScale: Double?
        var opacity: Double
        /// Controls the layout may hide, with whether they are shown.
        var extraButtons: [(id: String, title: String, shown: Bool)]
        /// Shown under the title, e.g. that the layout is shared by other games.
        var note: String?
    }

    enum SliderEvent {
        case began
        case changed(Double)
        case ended
    }

    var onModeChanged: ((GameOverlayLayoutEditorScene.SelectionMode) -> Void)?
    var onArcadeLayoutChanged: ((Bool) -> Void)?
    var onUndo: (() -> Void)?
    var onReset: (() -> Void)?
    var onCancel: (() -> Void)?
    var onDone: (() -> Void)?
    var onScaleEditing: ((SliderEvent) -> Void)?
    var onOpacityEditing: ((SliderEvent) -> Void)?
    var onExtraButtonToggled: ((String, Bool) -> Void)?
    /// The panel's content height changed (folded, or a row shown or hidden).
    var onSizeChanged: (() -> Void)?

    static let scaleRange: ClosedRange<Float> = 0.6...1.6

    private let titleLabel = UILabel()
    private let noteLabel = UILabel()
    private let foldButton = UIButton(type: .system)
    private let modeControl = UISegmentedControl(items: [
        Bundle.localizedString(forKey: "overlay_layout_mode_group"),
        Bundle.localizedString(forKey: "overlay_layout_mode_single")
    ])
    private let arcadeLayoutControl = UISegmentedControl(items: [
        Bundle.localizedString(forKey: "overlay_layout_arcade_six"),
        Bundle.localizedString(forKey: "overlay_layout_arcade_four")
    ])
    private let sizeTitleLabel = UILabel()
    private let sizeSlider = UISlider()
    private let sizeValueLabel = UILabel()
    private let opacitySlider = UISlider()
    private let opacityValueLabel = UILabel()
    private let extraButtonsStack = UIStackView()
    private var extraButtonsRow: UIView!
    private let detailStack = UIStackView()
    private lazy var undoButton = makeIconButton("arrow.uturn.backward", label: "overlay_layout_undo") { [weak self] in self?.onUndo?() }
    private lazy var resetButton = makeIconButton("arrow.counterclockwise", label: "overlay_layout_reset") { [weak self] in self?.onReset?() }
    private lazy var cancelButton = makeTextButton("cancel", prominent: false) { [weak self] in self?.onCancel?() }
    private lazy var doneButton = makeTextButton("overlay_layout_done", prominent: true) { [weak self] in self?.onDone?() }

    private var panStartCenter: CGPoint = .zero
    private var isFolded = false
    private var extraButtonIds: [String] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ state: State) {
        let orientation = Bundle.localizedString(forKey: state.isPortrait ? "overlay_layout_portrait" : "overlay_layout_landscape")
        titleLabel.text = "\(Bundle.localizedString(forKey: "overlay_layout_edit_title")) · \(orientation)"
        let arcadeChanged = arcadeLayoutControl.isHidden != (state.fourButtonLayout == nil)
        arcadeLayoutControl.isHidden = state.fourButtonLayout == nil
        arcadeLayoutControl.selectedSegmentIndex = state.fourButtonLayout == true ? 1 : 0
        let noteChanged = noteLabel.isHidden != (state.note == nil)
        noteLabel.text = state.note
        noteLabel.isHidden = state.note == nil

        modeControl.selectedSegmentIndex = state.mode == .group ? 0 : 1
        undoButton.isEnabled = state.canUndo
        resetButton.isEnabled = state.canReset

        if let title = state.selectionTitle, let scale = state.selectionScale {
            sizeTitleLabel.text = "\(Bundle.localizedString(forKey: "overlay_layout_size")) · \(title)"
            sizeSlider.isEnabled = true
            if !sizeSlider.isTracking {
                sizeSlider.value = Float(scale)
            }
            sizeValueLabel.text = String(format: "×%.2f", scale)
        } else {
            sizeTitleLabel.text = Bundle.localizedString(forKey: "overlay_layout_size_hint")
            sizeSlider.isEnabled = false
            sizeSlider.value = 1
            sizeValueLabel.text = nil
        }

        if !opacitySlider.isTracking {
            opacitySlider.value = Float(state.opacity)
        }
        opacityValueLabel.text = "\(Int((state.opacity * 100).rounded()))%"

        let rowsChanged = updateExtraButtons(state.extraButtons)
        if noteChanged || rowsChanged || arcadeChanged {
            onSizeChanged?()
        }
    }

    /// Keeps the panel inside `area` after a drag, a fold or a rotation.
    func keepInside(_ area: CGRect) {
        let half = CGSize(width: bounds.width * 0.5, height: bounds.height * 0.5)
        center = CGPoint(
            x: min(max(center.x, area.minX + half.width), max(area.minX + half.width, area.maxX - half.width)),
            y: min(max(center.y, area.minY + half.height), max(area.minY + half.height, area.maxY - half.height))
        )
    }
}

private extension GameOverlayLayoutEditPanel {
    func setupViews() {
        backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.94)
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)

        let handle = UIView()
        handle.backgroundColor = .tertiaryLabel
        handle.layer.cornerRadius = 2.5

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        noteLabel.font = .systemFont(ofSize: 12)
        noteLabel.textColor = .secondaryLabel
        noteLabel.textAlignment = .center
        noteLabel.numberOfLines = 0
        noteLabel.isHidden = true

        foldButton.setImage(UIImage(systemName: "chevron.up.circle"), for: .normal)
        foldButton.tintColor = .secondaryLabel
        foldButton.addAction(UIAction { [weak self] _ in self?.toggleFold() }, for: .touchUpInside)

        let titleRow = UIView()
        titleRow.addSubview(titleLabel)
        titleRow.addSubview(foldButton)
        titleLabel.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(28)
            make.trailing.lessThanOrEqualTo(foldButton.snp.leading).offset(-4)
        }
        foldButton.snp.makeConstraints { make in
            make.trailing.centerY.equalToSuperview()
            make.size.equalTo(28)
        }

        modeControl.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            Vibration.selection.vibrate()
            onModeChanged?(modeControl.selectedSegmentIndex == 0 ? .group : .single)
        }, for: .valueChanged)

        arcadeLayoutControl.isHidden = true
        arcadeLayoutControl.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            Vibration.selection.vibrate()
            onArcadeLayoutChanged?(arcadeLayoutControl.selectedSegmentIndex == 1)
        }, for: .valueChanged)

        sizeSlider.minimumValue = Self.scaleRange.lowerBound
        sizeSlider.maximumValue = Self.scaleRange.upperBound
        bind(sizeSlider) { [weak self] in self?.onScaleEditing?($0) }
        opacitySlider.minimumValue = Float(GameOverlayLayoutResolver.minimumOpacity)
        opacitySlider.maximumValue = 1
        bind(opacitySlider) { [weak self] in self?.onOpacityEditing?($0) }

        sizeTitleLabel.font = .systemFont(ofSize: 13)
        sizeTitleLabel.textColor = .secondaryLabel
        let sizeBlock = UIStackView(arrangedSubviews: [sizeTitleLabel, makeSliderLine(sizeSlider, value: sizeValueLabel)])
        sizeBlock.axis = .vertical
        sizeBlock.spacing = 2

        let opacityRow = makeRow(title: Bundle.localizedString(forKey: "overlay_layout_opacity"),
                                 content: makeSliderLine(opacitySlider, value: opacityValueLabel))

        extraButtonsStack.axis = .horizontal
        extraButtonsStack.spacing = 6
        extraButtonsStack.alignment = .center
        extraButtonsRow = makeRow(title: Bundle.localizedString(forKey: "overlay_layout_extra_buttons"), content: extraButtonsStack)
        extraButtonsRow.isHidden = true

        detailStack.axis = .vertical
        detailStack.spacing = 8
        [arcadeLayoutControl, modeControl, sizeBlock, opacityRow, extraButtonsRow].forEach(detailStack.addArrangedSubview)

        let toolRow = UIStackView(arrangedSubviews: [undoButton, resetButton, UIView(), cancelButton, doneButton])
        toolRow.axis = .horizontal
        toolRow.spacing = 8
        toolRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [titleRow, noteLabel, detailStack, toolRow])
        stack.axis = .vertical
        stack.spacing = 10

        addSubview(handle)
        addSubview(stack)
        handle.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(6)
            make.centerX.equalToSuperview()
            make.width.equalTo(36)
            make.height.equalTo(5)
        }
        stack.snp.makeConstraints { make in
            make.top.equalTo(handle.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(12)
            make.bottom.equalToSuperview().inset(12)
        }

        // The whole panel is the drag handle; its controls keep their own touches.
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        switch gesture.state {
        case .began:
            panStartCenter = center
        case .changed:
            let translation = gesture.translation(in: superview)
            center = CGPoint(x: panStartCenter.x + translation.x, y: panStartCenter.y + translation.y)
            keepInside(superview.bounds.inset(by: superview.safeAreaInsets))
        default:
            break
        }
    }

    func toggleFold() {
        Vibration.selection.vibrate()
        isFolded.toggle()
        detailStack.isHidden = isFolded
        foldButton.setImage(UIImage(systemName: isFolded ? "chevron.down.circle" : "chevron.up.circle"), for: .normal)
        onSizeChanged?()
    }

    /// Rebuilds the show/hide chips when the set of buttons changes; true when the row appeared or disappeared.
    func updateExtraButtons(_ buttons: [(id: String, title: String, shown: Bool)]) -> Bool {
        let ids = buttons.map(\.id)
        if ids != extraButtonIds {
            extraButtonIds = ids
            extraButtonsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for button in buttons {
                extraButtonsStack.addArrangedSubview(makeChip(id: button.id, title: button.title))
            }
            extraButtonsStack.addArrangedSubview(UIView())
        }
        for (index, button) in buttons.enumerated() {
            (extraButtonsStack.arrangedSubviews[index] as? UIButton)?.isSelected = button.shown
        }
        let hidden = buttons.isEmpty
        guard extraButtonsRow.isHidden != hidden else { return false }
        extraButtonsRow.isHidden = hidden
        return true
    }

    func makeChip(id: String, title: String) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)
        let button = UIButton(configuration: configuration)
        button.changesSelectionAsPrimaryAction = true
        // Shown: brand fill; hidden: a quiet gray chip.
        button.configurationUpdateHandler = { button in
            var configuration = button.configuration
            configuration?.background.backgroundColor = button.isSelected ? .mainColor : .tertiarySystemFill
            configuration?.baseForegroundColor = button.isSelected ? .white : .tertiaryLabel
            button.configuration = configuration
        }
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let button else { return }
            Vibration.selection.vibrate()
            self?.onExtraButtonToggled?(id, button.isSelected)
        }, for: .primaryActionTriggered)
        return button
    }

    func bind(_ slider: UISlider, handler: @escaping (SliderEvent) -> Void) {
        slider.addAction(UIAction { _ in handler(.began) }, for: .touchDown)
        slider.addAction(UIAction { [weak slider] _ in
            guard let slider else { return }
            handler(.changed(Double(slider.value)))
        }, for: .valueChanged)
        slider.addAction(UIAction { _ in handler(.ended) }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    func makeSliderLine(_ slider: UISlider, value: UILabel) -> UIView {
        value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        value.textColor = .secondaryLabel
        value.textAlignment = .right
        value.snp.makeConstraints { make in make.width.equalTo(48) }
        let line = UIStackView(arrangedSubviews: [slider, value])
        line.axis = .horizontal
        line.spacing = 8
        line.alignment = .center
        return line
    }

    func makeRow(title: String, content: UIView) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [label, content])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        return row
    }

    func makeIconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.gray()
        configuration.image = UIImage(systemName: symbol)
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in
            Vibration.selection.vibrate()
            action()
        })
        button.accessibilityLabel = Bundle.localizedString(forKey: label)
        return button
    }

    func makeTextButton(_ key: String, prominent: Bool, action: @escaping () -> Void) -> UIButton {
        var configuration: UIButton.Configuration = prominent ? .filled() : .gray()
        configuration.title = Bundle.localizedString(forKey: key)
        configuration.cornerStyle = .capsule
        if prominent {
            configuration.baseBackgroundColor = .mainColor
        }
        return UIButton(configuration: configuration, primaryAction: UIAction { _ in
            Vibration.selection.vibrate()
            action()
        })
    }
}
