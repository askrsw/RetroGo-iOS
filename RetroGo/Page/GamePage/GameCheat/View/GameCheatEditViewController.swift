//
//  GameCheatEditViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/6/6.
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
import RACoordinator
import XMLTextRenderKit

/// Create or edit a single user cheat. The `类型 (Type)` row is the top-level
/// choice — three independent kinds (a cheat is exactly one):
/// - **数值 (numeric, EMU)**: an `address:value` code string, e.g. `05C6:02`.
/// - **秘籍 (secret, EMU)**: an encrypted letter code (Game Genie / PAR / GameShark).
/// - **内存 (memory, RETRO)**: structured address/value with write mode, size, etc.
///
/// numeric ⇄ memory are linked (both are address+value); secret never links. The
/// `i` button explains the formats; the checkmark validates and persists.
final class GameCheatEditViewController: UIViewController {
    private let session: GameCheatSession
    private let editingItem: GameCheatItem?

    // Type
    private let typeSegment = UISegmentedControl(items: [
        Bundle.localizedString(forKey: "cheat_kind_numeric"),
        Bundle.localizedString(forKey: "cheat_kind_secret"),
        Bundle.localizedString(forKey: "cheat_kind_memory"),
    ])

    // Fields
    private let nameField = UITextField(frame: .zero)
    private let numericCodeField = UITextField(frame: .zero)
    private let secretCodeField = UITextField(frame: .zero)
    private let addressField = UITextField(frame: .zero)
    private let valueField = UITextField(frame: .zero)
    private let writeTypeButton = UIButton(type: .system)
    private let memSizeButton = UIButton(type: .system)
    private let advancedSwitch = UISwitch(frame: .zero)
    private let bigEndianSwitch = UISwitch(frame: .zero)
    private let maskField = UITextField(frame: .zero)
    private let repeatCountField = UITextField(frame: .zero)
    private let repeatValueField = UITextField(frame: .zero)
    private let repeatAddressField = UITextField(frame: .zero)

    // Rows that toggle visibility
    private var numericRow: UIView!
    private var secretRow: UIView!
    private var retroRows: [UIView] = []
    private var advancedRows: [UIView] = []
    private var maskRow: UIView!
    private var rowLabels: [UILabel] = []

    private let contentStack = UIStackView()

    // State
    private var currentKind: GameCheatKind = .numeric
    private var cheatType: GameCheatType = .setToValue
    private var memorySize: GameCheatMemorySize = .byte1

    init(session: GameCheatSession, editing: GameCheatItem?) {
        self.session = session
        self.editingItem = editing
        self.currentKind = editing?.kind ?? .numeric
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        let pageTitle = Bundle.localizedString(forKey: editingItem == nil ? "cheat_create_title" : "cheat_edit_title")
        navigationItem.title = pageTitle
        let titleIcon = IconRender.shared.settingsIcon(symbol: "star.circle", background: .cheatIconColor, size: CGSize(width: 22, height: 22))
        navigationItem.titleView = Self.makeIconTitleView(pageTitle, icon: titleIcon)

        let info = UIBarButtonItem(image: UIImage(systemName: "info.circle"), style: .plain, target: self, action: #selector(infoAction))
        let save = UIBarButtonItem(image: UIImage(systemName: "checkmark"), style: .plain, target: self, action: #selector(saveAction))
        info.tintColor = .label
        save.tintColor = .label
        navigationItem.rightBarButtonItems = [save, info]

        buildForm()
        loadEditingValues()
        applyKind()
        applyAdvancedVisibility()
    }
}

// MARK: - Form construction

extension GameCheatEditViewController {
    private func buildForm() {
        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        scrollView.addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalToSuperview()
        }

        // Type (first — picking the kind drives everything below it)
        typeSegment.selectedSegmentIndex = currentKind.rawValue
        typeSegment.selectedSegmentTintColor = .mainColor
        typeSegment.addTarget(self, action: #selector(typeChanged), for: .valueChanged)
        contentStack.addArrangedSubview(makeRow(labelKey: "cheat_field_type", control: typeSegment))

        // Name
        configTextField(nameField, placeholder: Bundle.localizedString(forKey: "cheat_field_name_placeholder"))
        nameField.autocapitalizationType = .words
        contentStack.addArrangedSubview(makeRow(labelKey: "cheat_field_name", control: nameField))

        // numeric: code
        configCodeField(numericCodeField, placeholder: Bundle.localizedString(forKey: "cheat_numeric_placeholder"))
        numericRow = makeRow(labelKey: "cheat_field_code", control: numericCodeField)
        contentStack.addArrangedSubview(numericRow)

        // secret: code
        configCodeField(secretCodeField, placeholder: Bundle.localizedString(forKey: "cheat_secret_placeholder"))
        secretRow = makeRow(labelKey: "cheat_field_code", control: secretCodeField)
        contentStack.addArrangedSubview(secretRow)

        // memory: address / value
        configHexField(addressField, placeholder: Bundle.localizedString(forKey: "cheat_field_address_placeholder"))
        configHexField(valueField, placeholder: Bundle.localizedString(forKey: "cheat_field_value_placeholder"))
        let addressRow = makeRow(labelKey: "cheat_field_address", control: addressField)
        let valueRow = makeRow(labelKey: "cheat_field_value", control: valueField)

        // memory: write type / memory size (menus)
        configMenuButton(writeTypeButton)
        configMenuButton(memSizeButton)
        let writeRow = makeRow(labelKey: "cheat_field_write_type", control: writeTypeButton)
        let sizeRow = makeRow(labelKey: "cheat_field_mem_size", control: memSizeButton)

        // memory: advanced toggle
        advancedSwitch.onTintColor = .mainColor
        advancedSwitch.addTarget(self, action: #selector(advancedToggled), for: .valueChanged)
        let advancedToggleRow = makeRow(labelKey: "cheat_field_advanced", control: advancedSwitch)

        retroRows = [addressRow, valueRow, writeRow, sizeRow, advancedToggleRow]
        retroRows.forEach { contentStack.addArrangedSubview($0) }

        // memory: advanced fields
        bigEndianSwitch.onTintColor = .mainColor
        let bigEndianRow = makeRow(labelKey: "cheat_field_big_endian", control: bigEndianSwitch)

        configHexField(maskField, placeholder: "0x")
        maskRow = makeRow(labelKey: "cheat_field_address_mask", control: maskField)

        configIntField(repeatCountField)
        configHexField(repeatValueField, placeholder: "0x")
        configIntField(repeatAddressField)
        let repeatCountRow = makeRow(labelKey: "cheat_field_repeat_count", control: repeatCountField)
        let repeatValueRow = makeRow(labelKey: "cheat_field_repeat_value", control: repeatValueField)
        let repeatAddressRow = makeRow(labelKey: "cheat_field_repeat_address", control: repeatAddressField)

        advancedRows = [bigEndianRow, maskRow, repeatCountRow, repeatValueRow, repeatAddressRow]
        advancedRows.forEach { contentStack.addArrangedSubview($0) }

        rebuildWriteTypeMenu()
        rebuildMemSizeMenu()
        equalizeLabelWidths()
    }

    private func makeRow(labelKey: String, control: UIView) -> UIView {
        let label = UILabel()
        label.text = Bundle.localizedString(forKey: labelKey)
        label.font = UIFont.systemFont(ofSize: UIFont.labelFontSize)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        rowLabels.append(label)

        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        control.snp.makeConstraints { $0.height.greaterThanOrEqualTo(40) }
        return row
    }

    /// Gives every row label the same width (the widest label's natural width,
    /// capped) so titles never truncate and controls stay aligned.
    private func equalizeLabelWidths() {
        let widest = rowLabels.map { $0.intrinsicContentSize.width }.max() ?? 92
        let columnWidth = min(ceil(widest) + 2, Self.maxLabelColumnWidth)
        rowLabels.forEach { label in
            label.snp.makeConstraints { $0.width.equalTo(columnWidth) }
        }
    }

    private static let maxLabelColumnWidth: CGFloat = 120

    private func configTextField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.backgroundColor = .secondarySystemBackground
        field.clearButtonMode = .whileEditing
    }

    private func configCodeField(_ field: UITextField, placeholder: String) {
        configTextField(field, placeholder: placeholder)
        field.autocapitalizationType = .allCharacters
        field.autocorrectionType = .no
        field.font = UIFont.monospacedSystemFont(ofSize: UIFont.labelFontSize, weight: .regular)
    }

    private func configHexField(_ field: UITextField, placeholder: String) {
        configCodeField(field, placeholder: placeholder)
    }

    private func configIntField(_ field: UITextField) {
        configTextField(field, placeholder: "")
        field.keyboardType = .numberPad
    }

    private func configMenuButton(_ button: UIButton) {
        button.showsMenuAsPrimaryAction = true
        button.contentHorizontalAlignment = .leading

        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = .label
        config.background.backgroundColor = .secondarySystemBackground
        config.background.cornerRadius = 8
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        button.configuration = config
    }

    private func setMenuButtonTitle(_ button: UIButton, _ title: String) {
        button.configuration?.title = title
    }
}

// MARK: - Menus

extension GameCheatEditViewController {
    private func rebuildWriteTypeMenu() {
        var types: [GameCheatType] = [.setToValue, .increase, .decrease]
        if advancedSwitch.isOn {
            types += [.runNextIfEq, .runNextIfNeq, .runNextIfLt, .runNextIfGt]
        }
        if !types.contains(cheatType) { cheatType = .setToValue }

        let actions = types.map { type in
            UIAction(title: Self.writeTypeName(type), state: type == cheatType ? .on : .off) { [weak self] _ in
                self?.cheatType = type
                self?.rebuildWriteTypeMenu()
            }
        }
        writeTypeButton.menu = UIMenu(children: actions)
        setMenuButtonTitle(writeTypeButton, Self.writeTypeName(cheatType))
    }

    private func rebuildMemSizeMenu() {
        var sizes: [GameCheatMemorySize] = [.byte1, .byte2, .byte4]
        if advancedSwitch.isOn {
            sizes = [.byte1, .byte2, .byte4, .bit1, .bit2, .bit4]
        }
        if !sizes.contains(memorySize) { memorySize = .byte1 }

        let actions = sizes.map { size in
            UIAction(title: Self.memSizeName(size), state: size == memorySize ? .on : .off) { [weak self] _ in
                self?.memorySize = size
                self?.rebuildMemSizeMenu()
                self?.applyAdvancedVisibility()
            }
        }
        memSizeButton.menu = UIMenu(children: actions)
        setMenuButtonTitle(memSizeButton, Self.memSizeName(memorySize))
    }

    static func writeTypeName(_ type: GameCheatType) -> String {
        let key: String
        switch type {
        case .setToValue:   key = "cheat_write_set"
        case .increase:     key = "cheat_write_increase"
        case .decrease:     key = "cheat_write_decrease"
        case .runNextIfEq:  key = "cheat_write_if_eq"
        case .runNextIfNeq: key = "cheat_write_if_neq"
        case .runNextIfLt:  key = "cheat_write_if_lt"
        case .runNextIfGt:  key = "cheat_write_if_gt"
        }
        return Bundle.localizedString(forKey: key)
    }

    static func memSizeName(_ size: GameCheatMemorySize) -> String {
        let key: String
        switch size {
        case .bit1:  key = "cheat_size_1bit"
        case .bit2:  key = "cheat_size_2bit"
        case .bit4:  key = "cheat_size_4bit"
        case .byte1: key = "cheat_size_1byte"
        case .byte2: key = "cheat_size_2byte"
        case .byte4: key = "cheat_size_4byte"
        }
        return Bundle.localizedString(forKey: key)
    }
}

// MARK: - Type switching / visibility

extension GameCheatEditViewController {
    @objc private func typeChanged() {
        Vibration.selection.vibrate()

        view.endEditing(true)
        let newKind = GameCheatKind(rawValue: typeSegment.selectedSegmentIndex) ?? .numeric
        syncOnKindSwitch(from: currentKind, to: newKind)
        currentKind = newKind
        applyKind()
    }

    @objc private func advancedToggled() {
        rebuildWriteTypeMenu()
        rebuildMemSizeMenu()
        applyAdvancedVisibility()
    }

    /// Only numeric ⇄ memory carry data across — they are the same address+value
    /// in two forms. secret is an opaque encrypted code and never links.
    private func syncOnKindSwitch(from old: GameCheatKind, to new: GameCheatKind) {
        if old == .numeric && new == .memory {
            if let parsed = Self.parseAddressValueCode(numericCodeField.text) {
                addressField.text = Self.hexString(parsed.address)
                valueField.text   = Self.hexString(parsed.value)
                memorySize = parsed.size
                cheatType  = .setToValue
                rebuildMemSizeMenu()
                rebuildWriteTypeMenu()
            }
        } else if old == .memory && new == .numeric {
            if let address = Self.parseHex(addressField.text) {
                let value = Self.parseHex(valueField.text) ?? 0
                numericCodeField.text = Self.addressValueCode(address: address, value: value, size: memorySize)
            }
        }
    }

    private func applyKind() {
        numericRow.isHidden = currentKind != .numeric
        secretRow.isHidden  = currentKind != .secret
        retroRows.forEach { $0.isHidden = currentKind != .memory }
        applyAdvancedVisibility()
    }

    private func applyAdvancedVisibility() {
        let show = currentKind == .memory && advancedSwitch.isOn
        advancedRows.forEach { $0.isHidden = !show }
        // RetroArch only uses the address mask for sub-byte sizes (it's ignored
        // for whole-byte sizes), and its menu only exposes it then — mirror that.
        maskRow.isHidden = !(show && isSubByteSize)
    }

    /// True for the sub-byte memory sizes (1/2/4 bit), where the address mask
    /// selects which bits to write.
    private var isSubByteSize: Bool {
        memorySize.rawValue <= GameCheatMemorySize.bit4.rawValue
    }
}

// MARK: - Load / save

extension GameCheatEditViewController {
    private func loadEditingValues() {
        guard let item = editingItem else { return }

        typeSegment.selectedSegmentIndex = item.kind.rawValue
        nameField.text = item.desc

        switch item.kind {
        case .numeric: numericCodeField.text = item.code
        case .secret:  secretCodeField.text = item.code
        case .memory:  break
        }

        cheatType = item.cheatType
        memorySize = item.memorySize
        addressField.text = Self.hexString(item.address)
        valueField.text = Self.hexString(item.value)

        let advanced = item.addressMask != 0 || item.bigEndian
            || item.repeatCount != 1 || item.repeatAddToValue != 0 || item.repeatAddToAddress != 1
            || item.cheatType.rawValue >= GameCheatType.runNextIfEq.rawValue
            || item.memorySize.rawValue <= GameCheatMemorySize.bit4.rawValue
        advancedSwitch.isOn = advanced

        bigEndianSwitch.isOn = item.bigEndian
        maskField.text = item.addressMask == 0 ? nil : Self.hexString(item.addressMask)
        repeatCountField.text = String(item.repeatCount)
        repeatValueField.text = Self.hexString(item.repeatAddToValue)
        repeatAddressField.text = String(item.repeatAddToAddress)
    }

    @objc private func infoAction() {
        Vibration.selection.vibrate()

        view.endEditing(true)

        let languageKey = Bundle.currentSimpleLanguageKey()
        guard let url = Bundle.main.url(forResource: "cheat", withExtension: "xml", subdirectory: "Data/xmls/\(languageKey)") else { return }

        let config = XMLRenderConfig()
        config.mainColor = .label
        let title = Bundle.localizedString(forKey: "cheat_help_title")
        let icon = IconRender.shared.settingsIcon(symbol: "info.circle", background: .systemIndigo, size: CGSize(width: 22, height: 22))
        let controller = XMLTextRenderViewController(xmlUrl: url, title: title, icon: icon, showCloseButton: true, config: config)
        let navController = UINavigationController(rootViewController: controller)
        present(navController, animated: true)
    }

    @objc private func saveAction() {
        Vibration.selection.vibrate()

        view.endEditing(true)

        var name = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var draft = editingItem ?? GameCheatItem(
            romKey: session.game.key,
            coreId: session.core.coreId,
            desc: "",
            enabled: false,
            sortIndex: 0
        )
        draft.kind = currentKind

        switch currentKind {
        case .numeric, .secret:
            let field = currentKind == .numeric ? numericCodeField : secretCodeField
            let code = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { showInvalid("cheat_invalid_empty_code"); return }
            if name.isEmpty { name = code }
            draft.code = code
            Self.resetRetroFields(&draft)   // EMU kind — keep the inactive RETRO fields clean

        case .memory:
            guard let address = Self.parseHex(addressField.text) else { showInvalid("cheat_invalid_address"); return }
            let value = Self.parseHex(valueField.text) ?? 0
            if name.isEmpty { name = Self.hexString(address) }
            draft.code = ""   // inactive for RETRO
            draft.address = address
            // Clamp to the memory size so an over-wide value never silently turns
            // into something else (the engine masks on write — match that here).
            draft.value = Self.clampValue(value, to: memorySize)
            draft.cheatType = cheatType
            draft.memorySize = memorySize
            draft.bigEndian = advancedSwitch.isOn ? bigEndianSwitch.isOn : false
            // The mask is only meaningful (and only shown) for sub-byte sizes.
            draft.addressMask = (advancedSwitch.isOn && isSubByteSize) ? ((Self.parseHex(maskField.text) ?? 0) & 0xFF) : 0
            draft.repeatCount = advancedSwitch.isOn ? max(1, Int(repeatCountField.text ?? "") ?? 1) : 1
            draft.repeatAddToValue = advancedSwitch.isOn ? (Self.parseHex(repeatValueField.text) ?? 0) : 0
            draft.repeatAddToAddress = advancedSwitch.isOn ? (Int(repeatAddressField.text ?? "") ?? 1) : 1
        }
        draft.desc = name

        let saved: Bool
        if editingItem != nil {
            saved = session.updateCheat(draft)
        } else {
            saved = session.addCheat(draft) != nil
        }
        guard saved else {
            showInvalid("cheat_save_failed")
            return
        }

        navigationController?.popViewController(animated: true)
    }

    private func showInvalid(_ messageKey: String) {
        let alert = UIAlertController(title: nil, message: Bundle.localizedString(forKey: messageKey), preferredStyle: .alert)
        let okAcion = UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default)
        alert.addAction(okAcion)
        alert.view.tintColor = .label
        present(alert, animated: true)
    }
}

// MARK: - Hex / code helpers

extension GameCheatEditViewController {
    /// Parses `0x05C6` / `05C6` / `  5c6 ` → Int. nil when empty or non-hex.
    static func parseHex(_ text: String?) -> Int? {
        var s = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        guard !s.isEmpty, let v = UInt32(s, radix: 16) else { return nil }
        return Int(v)
    }

    static func hexString(_ value: Int) -> String {
        String(format: "0x%X", value)
    }

    /// Masks `value` to the bit-width of `size` (1/2/4/8/16/32 bits), mirroring how
    /// RetroArch's engine masks the value when it writes memory.
    static func clampValue(_ value: Int, to size: GameCheatMemorySize) -> Int {
        let bits: Int
        switch size {
        case .bit1:  bits = 1
        case .bit2:  bits = 2
        case .bit4:  bits = 4
        case .byte1: bits = 8
        case .byte2: bits = 16
        case .byte4: bits = 32
        }
        if bits >= 32 { return value & 0xFFFFFFFF }
        return value & ((1 << bits) - 1)
    }

    /// Resets the RETRO structured fields to defaults — used when saving an EMU
    /// (numeric/secret) cheat so the inactive field set carries no stale data.
    static func resetRetroFields(_ item: inout GameCheatItem) {
        item.address = 0
        item.value = 0
        item.cheatType = .setToValue
        item.memorySize = .byte1
        item.addressMask = 0
        item.bigEndian = false
        item.repeatCount = 1
        item.repeatAddToValue = 0
        item.repeatAddToAddress = 1
    }

    /// Parses a single `address:value` code (e.g. `05C6:02`) into structured
    /// fields, inferring memory size from the value's hex-digit count. nil for
    /// `+`-joined, colon-less, or non-hex strings.
    static func parseAddressValueCode(_ text: String?) -> (address: Int, value: Int, size: GameCheatMemorySize)? {
        let raw = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains("+") else { return nil }

        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let valueString = String(parts[1])
        guard let address = parseHex(String(parts[0])), let value = parseHex(valueString) else { return nil }

        var valueDigits = valueString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if valueDigits.hasPrefix("0x") { valueDigits.removeFirst(2) }
        let size: GameCheatMemorySize = valueDigits.count <= 2 ? .byte1 : (valueDigits.count <= 4 ? .byte2 : .byte4)

        return (address, value, size)
    }

    /// Builds an `address:value` code, padding the value to the memory size and
    /// the address to at least 4 hex digits (the common NES convention).
    static func addressValueCode(address: Int, value: Int, size: GameCheatMemorySize) -> String {
        let valueWidth: Int
        switch size {
        case .byte4: valueWidth = 8
        case .byte2: valueWidth = 4
        default:     valueWidth = 2
        }
        return String(format: "%04X:%0\(valueWidth)X", address, value)
    }
}

extension GameCheatEditViewController: UITextFieldDelegate {}
