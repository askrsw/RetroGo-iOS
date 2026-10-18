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
        var canUndo: Bool
        var canReset: Bool
        /// Name and size of the selection; nil when nothing is selected.
        var selectionTitle: String?
        /// The selection's combo title when it has Start/Select symbols to draw.
        var selectionComboTitle: GameOverlayComboTitle?
        var selectionScale: Double?
        /// Whether the selected control is hidden; nil when it cannot be hidden.
        var selectionHidden: Bool?
        /// Combos of the platform and of the user, with whether they are shown.
        var combos: [Combo]
        /// The selection when it is a combo the user made, which can be edited.
        var selectedUserComboId: String?
        /// Shown under the title, e.g. that the layout is shared by other games.
        var note: String?
        var groupMembers: [GroupMember]
        var selectedSlotId: String?
        var selectedSlotOccupied: Bool
        var memberHidden: Bool?
        var canEditFan: Bool
    }

    struct GroupMember {
        let id: String
        let title: GameOverlayComboTitle
        let hidden: Bool
    }

    struct Combo: Equatable {
        let id: String
        let title: GameOverlayComboTitle
        let shown: Bool
        /// Marked with a bolt, so A+B and turbo A+B can be told apart.
        let isTurbo: Bool
        /// Made by the user: can be edited and deleted.
        let isUserCombo: Bool
        var isMacro = false
    }

    enum SliderEvent {
        case began
        case changed(Double)
        case ended
    }

    /// The user picked portrait (true) or landscape to edit.
    var onOrientationChanged: ((Bool) -> Void)?
    var onUndo: (() -> Void)?
    var onReset: (() -> Void)?
    var onCancel: (() -> Void)?
    var onDone: (() -> Void)?
    var onScaleEditing: ((SliderEvent) -> Void)?
    var onToggleSelectionHidden: (() -> Void)?
    var onAddCombo: ((UIButton) -> Void)?
    var onEditCombo: ((String) -> Void)?
    var onSelectMember: ((String) -> Void)?
    var onEditFan: (() -> Void)?
    /// The panel's content height changed (folded, or a row shown or hidden).
    var onSizeChanged: (() -> Void)?

    static let scaleRange: ClosedRange<Float> = 0.6...1.6
    private static let editSymbol = "square.and.pencil"
    private static let macroDirectionScale: CGFloat = 1.4

    private let titleLabel = UILabel()
    private let noteLabel = UILabel()
    private let foldButton = UIButton(type: .system)
    private let orientationButton = UIButton(type: .custom)
    private var isPortrait = true
    private let sizeTitleLabel = UILabel()
    private let sizeSlider = UISlider()
    private let sizeValueLabel = UILabel()
    private let combosScroll = UIScrollView()
    private let combosStack = UIStackView()
    /// First in the combos row, so making one's own combo reads as the main action, not an extra after the presets.
    private lazy var addComboButton: UIButton = {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = Bundle.localizedString(forKey: "overlay_combo_new_short")
        configuration.image = UIImage(systemName: "plus")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(scale: .small)
        configuration.imagePadding = 3
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .mainColor
        configuration.baseForegroundColor = .mainColor
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 12)
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            Vibration.selection.vibrate()
            onAddCombo?(addComboButton)
        })
        button.accessibilityLabel = Bundle.localizedString(forKey: "overlay_combo_new")
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }()
    /// Hides the selected control, or shows a hidden one again.
    private lazy var hideButton = makeIconButton("eye", label: "overlay_layout_hide_control") { [weak self] in
        self?.onToggleSelectionHidden?()
    }
    private lazy var editComboButton = makeIconButton(Self.editSymbol, label: "overlay_combo_edit_title") { [weak self] in
        guard let self, let id = selectedUserComboId else { return }
        onEditCombo?(id)
    }
    private let detailStack = UIStackView()
    private let contentStack = UIStackView()
    private static let contentInsets = UIEdgeInsets(top: 19, left: 12, bottom: 12, right: 12)
    private let groupBlock = UIStackView()
    private let membersStack = UIStackView()
    private lazy var fanButton = makeIconButton(Self.editSymbol, label: "overlay_layout_edit_fan") { [weak self] in self?.onEditFan?() }
    private lazy var undoButton = makeIconButton("arrow.uturn.backward", label: "overlay_layout_undo") { [weak self] in self?.onUndo?() }
    private lazy var resetButton = makeIconButton("arrow.counterclockwise", label: "overlay_layout_reset") { [weak self] in self?.onReset?() }
    private lazy var cancelButton = makeTextButton("cancel", prominent: false) { [weak self] in self?.onCancel?() }
    private lazy var doneButton = makeTextButton("overlay_layout_done", prominent: true) { [weak self] in self?.onDone?() }

    private var panStartCenter: CGPoint = .zero
    private var isFolded = false
    /// Chips are rebuilt only when this changes; their shown state is updated in place.
    private var comboChipKeys: [Combo] = []
    private var selectedUserComboId: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ state: State) {
        titleLabel.text = Bundle.localizedString(forKey: "overlay_layout_edit_title")
        isPortrait = state.isPortrait
        orientationButton.setImage(UIImage(systemName: state.isPortrait ? "rectangle.portrait.rotate" : "rectangle.landscape.rotate"), for: .normal)
        let currentOrientation = Bundle.localizedString(forKey: state.isPortrait ? "overlay_layout_portrait" : "overlay_layout_landscape")
        let nextOrientation = Bundle.localizedString(forKey: state.isPortrait ? "overlay_layout_landscape" : "overlay_layout_portrait")
        orientationButton.accessibilityValue = currentOrientation
        orientationButton.accessibilityLabel = String(format: Bundle.localizedString(forKey: "overlay_layout_rotate_to"), nextOrientation)
        let noteChanged = noteLabel.isHidden != (state.note == nil)
        noteLabel.text = state.note
        noteLabel.isHidden = state.note == nil

        undoButton.isEnabled = state.canUndo
        resetButton.isEnabled = state.canReset

        if let title = state.selectionTitle, let scale = state.selectionScale {
            if let comboTitle = state.selectionComboTitle {
                let text = NSMutableAttributedString(string: "\(Bundle.localizedString(forKey: "overlay_layout_size")) · ")
                let isMacro = state.combos.first { $0.id == state.selectedUserComboId }?.isMacro == true
                text.append(comboTitle.attributedString(font: sizeTitleLabel.font, joined: false, symbolScale: isMacro ? 1.4 : 1, directionScale: Self.macroDirectionScale))
                text.addAttributes([.font: sizeTitleLabel.font as Any, .foregroundColor: sizeTitleLabel.textColor as Any],
                                   range: NSRange(location: 0, length: text.length))
                sizeTitleLabel.attributedText = text
            } else {
                sizeTitleLabel.text = "\(Bundle.localizedString(forKey: "overlay_layout_size")) · \(title)"
            }
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


        selectedUserComboId = state.selectedUserComboId
        editComboButton.isHidden = state.selectedUserComboId == nil
        updateCombos(state.combos)

        if let hidden = state.selectionHidden {
            hideButton.isHidden = false
            hideButton.configuration?.image = UIImage(systemName: hidden ? "eye.slash" : "eye")
            hideButton.accessibilityLabel = Bundle.localizedString(forKey: hidden ? "overlay_layout_show_control" : "overlay_layout_hide_control")
        } else {
            hideButton.isHidden = true
        }

        let groupChanged = groupBlock.isHidden != state.groupMembers.isEmpty
        groupBlock.isHidden = state.groupMembers.isEmpty
        membersStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for member in state.groupMembers {
            var configuration = UIButton.Configuration.tinted()
            configuration.cornerStyle = .capsule
            let text = NSMutableAttributedString(attributedString: member.title.attributedString(font: .preferredFont(forTextStyle: .body), joined: false, directionScale: Self.macroDirectionScale))
            text.addAttribute(.foregroundColor, value: member.hidden ? UIColor.tertiaryLabel : UIColor.label, range: NSRange(location: 0, length: text.length))
            configuration.attributedTitle = AttributedString(text)
            configuration.baseBackgroundColor = member.id == state.selectedSlotId ? .mainColor : .tertiarySystemFill
            configuration.contentInsets = .init(top: 4, leading: 10, bottom: 4, trailing: 10)
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in Vibration.selection.vibrate(); self?.onSelectMember?(member.id) })
            button.accessibilityLabel = member.title.plainText
            if member.id == state.selectedSlotId { button.accessibilityTraits.insert(.selected) }
            membersStack.addArrangedSubview(button)
        }
        fanButton.isHidden = !state.canEditFan
        if noteChanged || groupChanged {
            onSizeChanged?()
        }
    }

    /// Measure the content independently of the panel's previous frame height.
    func fittingHeight(for width: CGFloat) -> CGFloat {
        // Match the horizontal constraints before measuring after a rotation.
        bounds.size.width = width
        let insets = Self.contentInsets
        let contentHeight = contentStack.systemLayoutSizeFitting(
            CGSize(width: max(1, width - insets.left - insets.right), height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        return insets.top + ceil(contentHeight) + insets.bottom
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
        titleRow.addSubview(orientationButton)
        titleRow.addSubview(foldButton)
        titleLabel.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(28)
            make.trailing.lessThanOrEqualTo(orientationButton.snp.leading).offset(-4)
        }
        foldButton.snp.makeConstraints { make in
            make.trailing.centerY.equalToSuperview()
            make.size.equalTo(28)
        }
        orientationButton.tintColor = .secondaryLabel
        orientationButton.backgroundColor = .clear
        orientationButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 18), forImageIn: .normal)
        orientationButton.snp.makeConstraints { make in
            make.trailing.equalTo(foldButton.snp.leading).offset(-6)
            make.centerY.equalToSuperview()
            make.size.equalTo(28)
        }

        orientationButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            Vibration.selection.vibrate()
            onOrientationChanged?(!isPortrait)
        }, for: .touchUpInside)

        sizeSlider.minimumValue = Self.scaleRange.lowerBound
        sizeSlider.maximumValue = Self.scaleRange.upperBound
        bind(sizeSlider) { [weak self] in self?.onScaleEditing?($0) }

        sizeTitleLabel.font = .systemFont(ofSize: 13)
        sizeTitleLabel.textColor = .secondaryLabel
        editComboButton.isHidden = true
        editComboButton.configuration?.buttonSize = .mini
        hideButton.isHidden = true
        hideButton.configuration?.buttonSize = .mini
        fanButton.configuration?.buttonSize = .mini
        fanButton.isHidden = true
        let sizeHeader = UIStackView(arrangedSubviews: [sizeTitleLabel, UIView(), editComboButton, hideButton, fanButton])
        sizeHeader.spacing = 6
        sizeHeader.axis = .horizontal
        sizeHeader.alignment = .center
        // Fixed height, so showing the edit button never resizes the panel.
        sizeHeader.snp.makeConstraints { make in make.height.equalTo(24) }
        let sizeBlock = UIStackView(arrangedSubviews: [sizeHeader, makeSliderLine(sizeSlider, value: sizeValueLabel)])
        sizeBlock.axis = .vertical
        sizeBlock.spacing = 2

        membersStack.axis = .horizontal
        membersStack.spacing = 6
        let memberScroll = UIScrollView()
        memberScroll.showsHorizontalScrollIndicator = false
        memberScroll.addSubview(membersStack)
        membersStack.snp.makeConstraints { make in
            make.edges.equalTo(memberScroll.contentLayoutGuide)
            make.height.equalTo(memberScroll.frameLayoutGuide)
        }
        memberScroll.snp.makeConstraints { make in make.height.equalTo(32) }
        let membersRow = makeRow(title: Bundle.localizedString(forKey: "overlay_layout_members"), content: memberScroll)
        groupBlock.axis = .vertical
        groupBlock.spacing = 6
        groupBlock.addArrangedSubview(membersRow)
        groupBlock.isHidden = true


        combosStack.axis = .horizontal
        combosStack.spacing = 6
        combosStack.alignment = .center
        combosScroll.showsHorizontalScrollIndicator = false
        combosScroll.alwaysBounceHorizontal = false
        combosScroll.addSubview(combosStack)
        combosStack.snp.makeConstraints { make in
            make.edges.equalTo(combosScroll.contentLayoutGuide)
            make.height.equalTo(combosScroll.frameLayoutGuide)
        }
        combosScroll.snp.makeConstraints { make in make.height.equalTo(32) }
        combosStack.addArrangedSubview(addComboButton)
        let combosRow = makeRow(title: Bundle.localizedString(forKey: "overlay_layout_combos"), content: combosScroll)

        detailStack.axis = .vertical
        detailStack.spacing = 8
        // Portrait and landscape keep separate positions; switching here saves leaving the editor to rotate.
        [sizeBlock, groupBlock, combosRow].forEach(detailStack.addArrangedSubview)

        let toolRow = UIStackView(arrangedSubviews: [undoButton, resetButton, UIView(), cancelButton, doneButton])
        toolRow.axis = .horizontal
        toolRow.spacing = 8
        toolRow.alignment = .center

        let stack = contentStack
        [titleRow, noteLabel, detailStack, toolRow].forEach(stack.addArrangedSubview)
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
            make.top.equalToSuperview().offset(Self.contentInsets.top)
            make.leading.equalToSuperview().offset(Self.contentInsets.left)
            make.trailing.equalToSuperview().inset(Self.contentInsets.right)
            // Height follows the stack's content. A bottom constraint would tie
            // unfolding content to the panel's still-collapsed frame height.
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

    /// Created buttons stay discoverable when hidden; tapping opens their details.
    func updateCombos(_ combos: [Combo]) {
        // Compare symbol identities as well as text; visibility is updated below.
        let keys = combos.map { Combo(id: $0.id, title: $0.title, shown: true, isTurbo: $0.isTurbo, isUserCombo: $0.isUserCombo, isMacro: $0.isMacro) }
        if keys != comboChipKeys {
            comboChipKeys = keys
            combosStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            combosStack.addArrangedSubview(addComboButton)
            for combo in combos {
                let chip = makeChip(title: combo.title.plainText, symbol: combo.isTurbo ? "bolt.fill" : nil,
                                    comboTitle: combo.title, symbolScale: combo.isMacro ? 1.4 : 1) { [weak self] _ in
                    self?.onEditCombo?(combo.id)
                }
                combosStack.addArrangedSubview(chip)
            }
            // Takes any width the row has left, so no chip is stretched.
            combosStack.addArrangedSubview(UIView())
        }
        // The New button comes first.
        for (index, combo) in combos.enumerated() {
            (combosStack.arrangedSubviews[index + 1] as? UIButton)?.isSelected = combo.shown
        }
    }

    func makeChip(title: String, symbol: String? = nil, comboTitle: GameOverlayComboTitle? = nil, symbolScale: CGFloat = 1,
                  onToggle: @escaping (Bool) -> Void) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        if let symbol, comboTitle == nil {
            configuration.image = UIImage(systemName: symbol)
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(scale: .small)
            configuration.imagePlacement = .trailing
            configuration.imagePadding = 3
        }
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)
        let button = UIButton(configuration: configuration)
        button.changesSelectionAsPrimaryAction = false
        // Shown: brand fill; hidden: a quiet gray chip.
        button.configurationUpdateHandler = { button in
            var configuration = button.configuration
            let foreground: UIColor = button.isSelected ? .white : .tertiaryLabel
            configuration?.background.backgroundColor = button.isSelected ? .mainColor : .tertiarySystemFill
            configuration?.baseForegroundColor = foreground
            if let comboTitle {
                // The symbols are text attachments; they take the color of the text around them.
                // Side by side like on the button.
                let parts = comboTitle.parts + (symbol.map { [GameOverlayComboTitle.Part.symbol($0, text: "⚡")] } ?? [])
                let displayTitle = GameOverlayComboTitle(parts: parts)
                let text = NSMutableAttributedString(attributedString: displayTitle.attributedString(font: .preferredFont(forTextStyle: .body), joined: false, symbolScale: symbolScale, directionScale: Self.macroDirectionScale))
                text.addAttribute(.foregroundColor, value: foreground, range: NSRange(location: 0, length: text.length))
                configuration?.attributedTitle = AttributedString(text)
            }
            button.configuration = configuration
        }
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addAction(UIAction { [weak button] _ in
            guard let button else { return }
            Vibration.selection.vibrate()
            onToggle(button.isSelected)
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
