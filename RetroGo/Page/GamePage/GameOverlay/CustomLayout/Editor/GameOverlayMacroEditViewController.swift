// Copyright © 2026 haharsw. Part of RetroGo, GPL-3.0-or-later.
import UIKit
import ObjcHelper

/// Edits a draft only. The outer layout save commits definitions and references
/// in one transaction; cancelling the layout discards every macro edit too.
final class GameOverlayMacroEditViewController: UITableViewController, UIAdaptivePresentationControllerDelegate {
    private var macro: GameOverlayMacro
    private let isNew: Bool
    private var shown: Bool
    private var finished = false
    private let keys: [GameOverlayComboKey]
    private let nameField = UITextField()
    private let iconButton = UIButton(type: .system)
    var onSave: ((GameOverlayMacro, Bool) -> Void)?
    var onDelete: (() -> Void)?

    init(macro: GameOverlayMacro?, keys: [GameOverlayComboKey], shown: Bool, isNew: Bool? = nil,
         usedSymbols: Set<String> = []) {
        self.macro = macro ?? .init(name: Bundle.localizedString(forKey: "overlay_macro_default_name"), steps: [])
        if macro == nil {
            let available = GameOverlayMacroSymbols.categories.flatMap(\.symbols)
                .filter { UIImage(systemName: $0) != nil }
            let unused = available.filter { !usedSymbols.contains($0) }
            self.macro.symbol = (unused.isEmpty ? available : unused).randomElement() ?? GameOverlayMacro.defaultSymbol
        }
        self.isNew = isNew ?? (macro == nil)
        self.keys = keys
        self.shown = shown
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(RGSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: RGSectionHeaderView.className)
        tableView.register(RGSectionFooterView.self, forHeaderFooterViewReuseIdentifier: RGSectionFooterView.className)
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 40
        tableView.estimatedSectionFooterHeight = 60
        tableView.separatorInset = .zero
        tableView.separatorInsetReference = .fromCellEdges
        title = Bundle.localizedString(forKey: "overlay_macro_title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.close() })
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Bundle.localizedString(forKey: "overlay_layout_save"), primaryAction: UIAction { [weak self] _ in self?.save() })
        nameField.text = macro.name
        nameField.clearButtonMode = .whileEditing
        nameField.autocorrectionType = .no
        nameField.returnKeyType = .done
        nameField.addAction(UIAction { [weak self] _ in self?.nameField.resignFirstResponder() }, for: .editingDidEndOnExit)
        nameField.addAction(UIAction { [weak self] _ in
            self?.macro.name = self?.nameField.text ?? ""
            self?.updateSaveState()
        }, for: .editingChanged)
        iconButton.tintColor = .label
        iconButton.addAction(UIAction { [weak self] _ in self?.selectIcon() }, for: .touchUpInside)
        updateIcon()
        updateSaveState()
    }
    private func updateIcon() {
        let text = NSMutableAttributedString(attributedString: macro.buttonTitle.attributedString(
            font: .systemFont(ofSize: 22), joined: false))
        text.addAttribute(.foregroundColor, value: UIColor.label, range: NSRange(location: 0, length: text.length))
        iconButton.setAttributedTitle(text, for: .normal)
        iconButton.accessibilityLabel = Bundle.localizedString(forKey: "overlay_macro_icon")
    }
    private func selectIcon() {
        view.endEditing(true)
        let picker = GameOverlayMacroIconViewController(symbol: macro.resolvedSymbol, direction: macro.direction) { [weak self] symbol, direction in
            self?.macro.symbol = symbol
            self?.macro.direction = direction
            self?.updateIcon()
        }
        let navigation = UINavigationController(rootViewController: picker)
        navigation.sheetPresentationController?.detents = [.large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        navigation.presentationController?.delegate = picker
        present(navigation, animated: true)
    }
    private func updateSaveState() { navigationItem.rightBarButtonItem?.isEnabled = macro.isValid }
    private enum StepRow { case input(Int), gap(Int, Int?) }
    private var stepRows: [StepRow] {
        let inputIndices = macro.steps.indices.filter { !macro.steps[$0].binds.isEmpty }
        return inputIndices.enumerated().flatMap { position, index -> [StepRow] in
            var rows: [StepRow] = [.input(index)]
            if position + 1 < inputIndices.count {
                let next = inputIndices[position + 1]
                rows.append(.gap(index, next > index + 1 ? index + 1 : nil))
            }
            return rows
        }
    }
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let text = headerTitle(for: section) else { return nil }
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionHeaderView.className) as! RGSectionHeaderView
        header.text = text
        return header
    }
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard let text = footerTitle(for: section) else { return nil }
        let footer = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionFooterView.className) as! RGSectionFooterView
        footer.text = text
        return footer
    }

    override func numberOfSections(in tableView: UITableView) -> Int { isNew ? 3 : 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section { case 0, 3: return 1; case 1: return stepRows.count + 1; default: return isNew ? 1 : 2 }
    }
    private func headerTitle(for section: Int) -> String? {
        section == 1 ? String(format: Bundle.localizedString(forKey: "overlay_macro_steps_header"), macro.totalFrames) : nil
    }
    private func footerTitle(for section: Int) -> String? {
        switch section {
        case 0: return Bundle.localizedString(forKey: "overlay_macro_intro_footer")
        case 1: return Bundle.localizedString(forKey: "overlay_macro_steps_footer")
        case 2: return Bundle.localizedString(forKey: "overlay_macro_shared_footer")
        case 3: return Bundle.localizedString(forKey: "overlay_macro_mirror_footer")
        default: return nil
        }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.separatorInset = .zero
        var content = cell.defaultContentConfiguration()
        content.imageProperties.tintColor = .label
        switch indexPath.section {
        case 0:
            let row = UIStackView(arrangedSubviews: [iconButton, nameField])
            row.axis = .horizontal; row.spacing = 12; row.alignment = .center
            cell.contentView.addSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor), row.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor), row.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8), row.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8), nameField.heightAnchor.constraint(greaterThanOrEqualToConstant: 28), iconButton.widthAnchor.constraint(equalToConstant: 76), iconButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)])
            cell.selectionStyle = .none
            return cell
        case 1:
            if indexPath.row == stepRows.count {
                content.text = Bundle.localizedString(forKey: "overlay_macro_add_step")
                content.image = UIImage(systemName: "plus")
                cell.accessoryType = .disclosureIndicator
            } else {
                switch stepRows[indexPath.row] {
                case .input(let index):
                    let parts = macro.steps[index].binds.map { bind in
                        keys.first { $0.bind.rawValue == bind }?.titlePart ?? .text(bind)
                    }
                    let text = NSMutableAttributedString(attributedString: GameOverlayComboTitle(parts: parts)
                        .attributedString(font: content.textProperties.font, joined: false, minimumSpacing: 0.25, compactDirections: false))
                    text.addAttribute(.foregroundColor, value: UIColor.label, range: NSRange(location: 0, length: text.length))
                    content.attributedText = text
                    content.secondaryText = String(format: Bundle.localizedString(forKey: "overlay_macro_hold_frames"), macro.steps[index].frames)
                case .gap(_, let wait):
                    content.text = String(format: Bundle.localizedString(forKey: "overlay_macro_gap_frames"), wait.map { macro.steps[$0].frames } ?? 0)
                    content.image = UIImage(systemName: "pause")
                    content.textProperties.color = .secondaryLabel
                    content.imageProperties.tintColor = .secondaryLabel
                }
                cell.accessoryType = .disclosureIndicator
            }
        case 3:
            content.text = Bundle.localizedString(forKey: "overlay_macro_mirror_copy")
            content.image = UIImage(systemName: "arrow.left.arrow.right")
            cell.accessoryType = .disclosureIndicator
        default:
            if indexPath.row == 0 {
                content.text = Bundle.localizedString(forKey: "overlay_combo_show_current_orientation")
                let toggle = UISwitch()
                toggle.isOn = shown
                toggle.addAction(UIAction { [weak self, weak toggle] _ in self?.shown = toggle?.isOn ?? true }, for: .valueChanged)
                cell.accessoryView = toggle
                cell.selectionStyle = .none
            } else {
                content.text = Bundle.localizedString(forKey: "overlay_macro_remove_button")
                content.textProperties.color = .systemRed
            }
        }
        cell.contentConfiguration = content
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        view.endEditing(true)
        switch indexPath.section {
        case 1:
            if indexPath.row == stepRows.count {
                guard macro.steps.count < GameOverlayMacro.maxSteps else { return }
                editStep(index: nil, gap: false)
            } else {
                switch stepRows[indexPath.row] {
                case .input(let index): editStep(index: index, gap: false)
                case .gap(let after, let wait): editStep(index: wait, gap: true, after: after)
                }
            }
        case 2 where indexPath.row == 1:
            confirmDiscard(title: "overlay_macro_remove_button") { [weak self] in self?.onDelete?(); self?.close() }
        case 3:
            createMirroredCopy()
        default: break
        }
    }
    private func createMirroredCopy() {
        guard let navigation = navigationController else { return }
        let name = String(format: Bundle.localizedString(forKey: "overlay_macro_mirror_name"), macro.name)
        let copy = GameOverlayMacroEditViewController(macro: macro.mirroredCopy(name: name),
            keys: keys, shown: true, isNew: true)
        copy.onSave = onSave
        // Replacing the editor must not autosave changes to the source macro.
        finished = true
        navigation.setViewControllers([copy], animated: true)
        navigation.presentationController?.delegate = copy
    }
    private func editStep(index: Int?, gap: Bool, after: Int? = nil) {
        let initial = index.map { macro.steps[$0] } ?? .init(binds: [], frames: gap ? 0 : 1)
        let controller = GameOverlayMacroStepViewController(step: initial, keys: keys, isGap: gap) { [weak self] step in
            guard let self else { return }
            if let index {
                if step.frames == 0 { self.macro.steps.remove(at: index) } else { self.macro.steps[index] = step }
            } else if gap, let after {
                if step.frames > 0 { self.macro.steps.insert(step, at: after + 1) }
            } else { self.macro.steps.append(step) }
            self.refresh()
        }
        navigationController?.pushViewController(controller, animated: true)
    }
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard indexPath.section == 1, indexPath.row < stepRows.count else { return false }
        if case .input = stepRows[indexPath.row] { return true }
        return false
    }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, case .input(let index) = stepRows[indexPath.row] else { return }
        macro.steps.remove(at: index)
        // Remove/merge orphan waits after deleting their neighboring input.
        var clean: [GameOverlayMacro.Step] = []
        for step in macro.steps {
            if step.binds.isEmpty && clean.isEmpty { continue }
            if step.binds.isEmpty, clean.last?.binds.isEmpty == true { clean[clean.count - 1].frames += step.frames }
            else { clean.append(step) }
        }
        if clean.last?.binds.isEmpty == true { clean.removeLast() }
        macro.steps = clean
        refresh()
    }
    private func refresh() { updateSaveState(); tableView.reloadData() }
    private func confirmDiscard(title: String, action: @escaping () -> Void) {
        let alert = UIAlertController(title: Bundle.localizedString(forKey: title), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "overlay_macro_continue"), style: .destructive) { [weak alert] _ in
            alert?.dismiss(animated: true, completion: action)
        })
        present(alert, animated: true)
    }
    private func save() {
        guard !finished, macro.isValid else { return }
        onSave?(macro, shown)
        close()
    }
    private func close() { finished = true; navigationController?.presentingViewController?.dismiss(animated: true) }
    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        if isNew { return macro.steps.isEmpty }
        return macro.isValid
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard !finished else { return }
        finished = true
        if !isNew, macro.isValid { onSave?(macro, shown) }
    }
    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        let alert = UIAlertController(title: Bundle.localizedString(forKey: "overlay_combo_unsaved_title"), message: Bundle.localizedString(forKey: macro.isValid ? "overlay_combo_unsaved_message" : "overlay_macro_invalid"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "overlay_combo_discard"), style: .destructive) { [weak self] _ in self?.close() })
        if macro.isValid { alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "overlay_layout_save"), style: .default) { [weak self] _ in self?.save() }) }
        present(alert, animated: true)
    }
}

/// Browses saved macros without creating a destination draft until a row is picked.
final class GameOverlayMacroCopyViewController: UITableViewController, UISearchResultsUpdating {
    private let loadCandidates: () -> [GameOverlayMacroStore.Candidate]
    private let makeEditor: (GameOverlayMacro) -> GameOverlayMacroEditViewController?
    private var candidates: [GameOverlayMacroStore.Candidate] = []
    private var groups: [[GameOverlayMacroStore.Candidate]] = []
    private let search = UISearchController(searchResultsController: nil)

    init(loadCandidates: @escaping () -> [GameOverlayMacroStore.Candidate],
         makeEditor: @escaping (GameOverlayMacro) -> GameOverlayMacroEditViewController?) {
        self.loadCandidates = loadCandidates
        self.makeEditor = makeEditor
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Bundle.localizedString(forKey: "overlay_macro_copy_title")
        tableView.register(RGSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: RGSectionHeaderView.className)
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 40
        tableView.separatorInset = .zero
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = search
        definesPresentationContext = true
        reloadCandidates()
    }

    private func reloadCandidates() {
        candidates = loadCandidates()
        updateGroups()
    }

    func updateSearchResults(for searchController: UISearchController) {
        updateGroups()
    }

    private func updateGroups() {
        let query = (search.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        groups = []
        for candidate in candidates where query.isEmpty || candidate.macro.name.localizedStandardContains(query)
            || candidate.layoutName.localizedStandardContains(query) {
            if groups.last?.first?.layoutId == candidate.layoutId {
                groups[groups.count - 1].append(candidate)
            } else {
                groups.append([candidate])
            }
        }
        if candidates.isEmpty {
            var empty = UIContentUnavailableConfiguration.empty()
            empty.image = UIImage(systemName: "rectangle.on.rectangle")
            empty.text = Bundle.localizedString(forKey: "overlay_macro_copy_empty")
            contentUnavailableConfiguration = empty
        } else {
            contentUnavailableConfiguration = groups.isEmpty ? UIContentUnavailableConfiguration.search() : nil
        }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { groups.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { groups[section].count }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let source = groups[section].first else { return nil }
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionHeaderView.className) as! RGSectionHeaderView
        header.text = "\(source.layoutName) · \(source.idiom == .pad ? "iPad" : "iPhone")"
        return header
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let macro = groups[indexPath.section][indexPath.row].macro
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.separatorInset = .zero
        var content = cell.defaultContentConfiguration()
        let title = NSMutableAttributedString(attributedString: macro.buttonTitle.attributedString(
            font: content.textProperties.font, joined: false))
        title.append(NSAttributedString(string: "  \(macro.name)", attributes: [.font: content.textProperties.font]))
        content.attributedText = title
        content.secondaryText = String(format: Bundle.localizedString(forKey: "overlay_macro_copy_details"), macro.steps.count, macro.totalFrames)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let selected = groups[indexPath.section][indexPath.row]
        // Recheck saved data so a removed source never creates a stale copy.
        reloadCandidates()
        guard let current = candidates.first(where: { $0.layoutId == selected.layoutId && $0.macro.id == selected.macro.id }),
              let editor = makeEditor(current.macro.copyForLayout()) else { return }
        search.isActive = false
        navigationController?.setViewControllers([editor], animated: true)
        navigationController?.presentationController?.delegate = editor
    }
}

/// Only the curated, available symbols can be selected; the direction is a
/// visual marker and does not change the sequence's input.
final class GameOverlayMacroIconViewController: UITableViewController, UIAdaptivePresentationControllerDelegate {
    private var symbol: String
    private var direction: GameOverlayMacro.Direction?
    private let onSave: (String, GameOverlayMacro.Direction?) -> Void
    private let categories = GameOverlayMacroSymbols.categories.map { category in
        GameOverlayMacroSymbols.Category(key: category.key, symbols: category.symbols.filter { UIImage(systemName: $0) != nil })
    }.filter { !$0.symbols.isEmpty }
    private let columns = 4
    private var finished = false
    private var collapsed = Set<String>()

    init(symbol: String, direction: GameOverlayMacro.Direction?, onSave: @escaping (String, GameOverlayMacro.Direction?) -> Void) {
        self.symbol = symbol; self.direction = direction; self.onSave = onSave
        super.init(style: .insetGrouped)
        collapsed = Set(categories.filter { !$0.symbols.contains(symbol) }.map(\.key))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = Bundle.localizedString(forKey: "overlay_macro_icon")
        tableView.register(RGSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: RGSectionHeaderView.className)
        tableView.register(RGSectionFooterView.self, forHeaderFooterViewReuseIdentifier: RGSectionFooterView.className)
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 40
        tableView.estimatedSectionFooterHeight = 60
        tableView.separatorStyle = .none
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.finished = true
            self?.dismiss(animated: true)
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.commit()
            self.dismiss(animated: true)
        })
    }
    private func commit() {
        guard !finished else { return }
        finished = true
        onSave(symbol, direction)
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        commit()
    }
    override func numberOfSections(in tableView: UITableView) -> Int { categories.count + 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section > 0 else { return 1 }
        let category = categories[section - 1]
        return 1 + (collapsed.contains(category.key) ? 0 : (category.symbols.count + columns - 1) / columns)
    }
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == 0 else { return nil }
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionHeaderView.className) as! RGSectionHeaderView
        header.text = Bundle.localizedString(forKey: "overlay_macro_direction")
        return header
    }
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == 0 else { return nil }
        let footer = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionFooterView.className) as! RGSectionFooterView
        footer.text = Bundle.localizedString(forKey: "overlay_macro_direction_footer")
        return footer
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        if indexPath.section > 0, indexPath.row == 0 {
            let category = categories[indexPath.section - 1]
            let expanded = !collapsed.contains(category.key)
            var content = cell.defaultContentConfiguration()
            content.text = Bundle.localizedString(forKey: "overlay_macro_symbols_" + category.key)
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            cell.contentConfiguration = content
            let chevron = UIImageView(image: UIImage(systemName: expanded ? "chevron.down" : "chevron.right"))
            chevron.tintColor = .secondaryLabel
            cell.accessoryView = chevron
            cell.selectionStyle = .default
            cell.accessibilityTraits = .button
            cell.accessibilityValue = Bundle.localizedString(forKey: expanded ? "coreoption_expanded" : "coreoption_collapsed")
            return cell
        }
        let row: UIView
        if indexPath.section == 0 {
            let control = UISegmentedControl(items: [Bundle.localizedString(forKey: "overlay_macro_direction_none"),
                UIImage(systemName: "arrow.left")!, UIImage(systemName: "arrow.right")!])
            control.selectedSegmentIndex = direction == nil ? 0 : (direction == .left ? 1 : 2)
            control.accessibilityLabel = Bundle.localizedString(forKey: "overlay_macro_direction")
            control.addAction(UIAction { [weak self, weak control] _ in
                guard let self, let control else { return }
                self.direction = control.selectedSegmentIndex == 0 ? nil : (control.selectedSegmentIndex == 1 ? .left : .right)
                self.tableView.reloadSections(IndexSet(integersIn: 1..<(self.categories.count + 1)), with: .none)
            }, for: .valueChanged)
            row = control
        } else {
            let stack = UIStackView()
            stack.axis = .horizontal; stack.spacing = 8; stack.distribution = .fillEqually
            let symbols = categories[indexPath.section - 1].symbols
            for column in 0..<columns {
                let index = (indexPath.row - 1) * columns + column
                guard index < symbols.count else { stack.addArrangedSubview(UIView()); continue }
                let name = symbols[index]
                let button = UIButton(type: .system)
                let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 26))
                button.setImage(direction == .left ? image?.withHorizontallyFlippedOrientation() : image, for: .normal)
                button.tintColor = .label
                button.backgroundColor = name == symbol ? UIColor.mainColor.withAlphaComponent(0.3) : .clear
                button.layer.cornerRadius = 10
                button.accessibilityLabel = name
                button.accessibilityTraits = name == symbol ? [.button, .selected] : .button
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
                button.addAction(UIAction { [weak self] _ in self?.symbol = name; self?.tableView.reloadData() }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            }
            row = stack
        }
        cell.contentView.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor), row.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor), row.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8), row.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8)])
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section > 0, indexPath.row == 0 else { return }
        let key = categories[indexPath.section - 1].key
        if !collapsed.insert(key).inserted { collapsed.remove(key) }
        tableView.reloadSections(IndexSet(integer: indexPath.section), with: .automatic)
    }
}

final class GameOverlayMacroStepViewController: UITableViewController {
    private var step: GameOverlayMacro.Step
    private let keys: [GameOverlayComboKey]
    private let isGap: Bool
    private let onSave: (GameOverlayMacro.Step) -> Void
    private let frameField = UITextField()
    private let stepper = UIStepper()
    init(step: GameOverlayMacro.Step, keys: [GameOverlayComboKey], isGap: Bool, onSave: @escaping (GameOverlayMacro.Step) -> Void) {
        self.step = step; self.keys = keys; self.isGap = isGap; self.onSave = onSave
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(RGSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: RGSectionHeaderView.className)
        tableView.register(RGSectionFooterView.self, forHeaderFooterViewReuseIdentifier: RGSectionFooterView.className)
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 40
        tableView.estimatedSectionFooterHeight = 60
        tableView.separatorInset = .zero
        tableView.separatorInsetReference = .fromCellEdges
        title = Bundle.localizedString(forKey: isGap ? "overlay_macro_gap_title" : "overlay_macro_step_title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Bundle.localizedString(forKey: "overlay_layout_save"), primaryAction: UIAction { [weak self] _ in
            guard let self, let frames = Int(self.frameField.text ?? ""), (self.isGap ? 0...600 : 1...600).contains(frames), self.isGap || !self.step.binds.isEmpty else { return }
            let binds = Set(self.step.binds)
            guard !binds.isSuperset(of: ["UP", "DOWN"]), !binds.isSuperset(of: ["LEFT", "RIGHT"]) else { return }
            self.step.frames = frames
            self.onSave(self.step)
            self.navigationController?.popViewController(animated: true)
        })
        frameField.keyboardType = .numberPad
        frameField.text = String(step.frames)
        frameField.textAlignment = .center
        frameField.accessibilityLabel = Bundle.localizedString(forKey: "overlay_macro_frames")
        stepper.minimumValue = isGap ? 0 : 1
        stepper.maximumValue = 600
        stepper.value = Double(step.frames)
        stepper.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.frameField.text = String(Int(self.stepper.value))
            self.step.frames = Int(self.stepper.value)
            self.updateSaveState()
        }, for: .valueChanged)
        frameField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if let value = Double(self.frameField.text ?? "") { self.stepper.value = value }
            self.updateSaveState()
        }, for: .editingChanged)
        updateSaveState()
    }
    private func updateSaveState() {
        let binds = Set(step.binds)
        let frames = Int(frameField.text ?? "") ?? -1
        navigationItem.rightBarButtonItem?.isEnabled = (isGap ? 0...600 : 1...600).contains(frames)
            && (isGap || !binds.isEmpty) && !binds.isSuperset(of: ["UP", "DOWN"]) && !binds.isSuperset(of: ["LEFT", "RIGHT"])
    }
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard let text = footerTitle(for: section) else { return nil }
        let footer = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionFooterView.className) as! RGSectionFooterView
        footer.text = text
        return footer
    }

    override func numberOfSections(in tableView: UITableView) -> Int { isGap ? 1 : 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 1 : keys.count }
    private func footerTitle(for section: Int) -> String? {
        section == 0 ? Bundle.localizedString(forKey: isGap ? "overlay_macro_gap_footer" : "overlay_macro_hold_footer") : nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.separatorInset = .zero
        if indexPath.section == 0 {
            let row = UIStackView(arrangedSubviews: [frameField, stepper])
            row.axis = .horizontal; row.spacing = 16
            cell.contentView.addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor), row.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor), row.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8), row.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8), frameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 60)])
            cell.selectionStyle = .none
        } else {
            let key = keys[indexPath.row]
            var content = cell.defaultContentConfiguration()
            content.text = key.symbolReplacesTitle ? nil : key.title
            content.image = key.symbol.flatMap { UIImage(systemName: $0) }
            content.imageProperties.tintColor = .label
            cell.contentConfiguration = content
            cell.accessoryType = step.binds.contains(key.bind.rawValue) ? .checkmark : .none
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 1 else { return }
        let bind = keys[indexPath.row].bind.rawValue
        if let index = step.binds.firstIndex(of: bind) { step.binds.remove(at: index) }
        else { step.binds.append(bind) }
        updateSaveState()
        tableView.reloadData()
    }
}
