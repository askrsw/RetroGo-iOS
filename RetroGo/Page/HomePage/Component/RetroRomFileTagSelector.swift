//
//  RetroRomFileTagSelector.swift
//  RetroGo
//
//  Created by haharsw on 2026/2/11.
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

final fileprivate class RetroRomTagTableViewCell: UITableViewCell, UITextFieldDelegate, UIColorPickerViewControllerDelegate {
    static let circleImage = UIImage(systemName: "circle")
    static let filledCircleImage = UIImage(systemName: "circle.fill")
    static let checkmarkCircleImage = UIImage(systemName: "checkmark.circle.fill")
    static let plusCircleImage = UIImage(systemName: "plus.circle")
    static let plusCircleFillImage = UIImage(systemName: "plus.circle.fill")

    let preImageView  = UIImageView(frame: .zero)
    let postImageView = UIImageView(frame: .zero)
    let titleLabel    = UITextField(frame: .zero)

    var retroTag: RetroRomFileTag? {
        didSet {
            titleLabel.text = retroTag?.showTitle
            titleLabel.isUserInteractionEnabled = !(retroTag?.isSystemTag ?? true)

            if let color = retroTag?.showColor {
                if retroTag!.isSystemTag {
                    postImageView.image = Self.filledCircleImage
                } else {
                    postImageView.image = Self.plusCircleFillImage
                }
                postImageView.tintColor = color
            } else {
                postImageView.image = Self.plusCircleImage
                postImageView.tintColor = .label
            }

            postImageView.isUserInteractionEnabled = !(retroTag?.isSystemTag ?? true)
        }
    }

    var check: Bool {
        didSet {
            if check {
                preImageView.image = Self.checkmarkCircleImage
                preImageView.tintColor = .mainColor
            } else {
                preImageView.image = Self.circleImage
                preImageView.tintColor = .label
            }
        }
    }

    private(set) var titleEditing: Bool = false

    weak var holder: RetroRomTagSelector?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        self.check = false
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        preImageView.contentMode = .scaleAspectFill
        contentView.addSubview(preImageView)

        titleLabel.font = UIFont.systemFont(ofSize: 17)
        titleLabel.delegate = self
        titleLabel.returnKeyType = .done
        titleLabel.inputAccessoryView = nil
        contentView.addSubview(titleLabel)

        postImageView.contentMode = .scaleAspectFill
        contentView.addSubview(postImageView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tagColorSelect(_:)))
        postImageView.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        preImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(18)
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: 24, height: 24))
        }

        postImageView.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-20)
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: 30, height: 30))
        }

        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(preImageView.snp.trailing).offset(10)
            make.trailing.equalTo(postImageView.snp.leading).offset(-10)
            make.centerY.equalToSuperview()
        }
    }

    @objc
    private func tagColorSelect(_ tap: UITapGestureRecognizer) {
        guard let tag = retroTag, !tag.isSystemTag, tag.stored, let holder = holder, holder.endUpdateTagTitlte() else {
            return
        }

        Vibration.medium.vibrate()

        let colorPicker = UIColorPickerViewController()
        colorPicker.delegate = self
        if let color = tag.showColor {
            colorPicker.selectedColor = color
        }
        holder.present(colorPicker, animated: true)
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        guard let holder = holder else {
            return false
        }

        textField.inputAccessoryView = nil
        return holder.shouldBeginUpdateTagTitle(self)
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        self.titleEditing = true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let holder = holder else {
            self.titleEditing = false
            self.titleLabel.resignFirstResponder()
            return true
        }
        textField.inputAccessoryView = nil
        if holder.shouldEndUpdateTagTitle(self) {
            self.titleEditing = false
            self.titleLabel.resignFirstResponder()
            return true
        } else {
            return false
        }
    }

    func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
        self.titleEditing = false
        holder?.didEndUpdateTagTitle(self)
    }

    // MARK: - UIColorPickerViewControllerDelegate

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        let selectedColor = viewController.selectedColor
        if retroTag?.update(title: nil, colorValue: Int(selectedColor.hexInteger())) ?? false {
            postImageView.image = Self.plusCircleFillImage
            postImageView.tintColor = selectedColor
        }
    }
}

final private class RetroRomAddNewTagTableViewCell: UITableViewCell {
    static let plusCircleImage = UIImage(systemName: "plus.circle.fill")

    let preImageView  = UIImageView(frame: .zero)
    let titleLabel    = UILabel(frame: .zero)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        preImageView.image = Self.plusCircleImage
        preImageView.contentMode = .scaleAspectFill
        preImageView.tintColor = .systemGreen
        contentView.addSubview(preImageView)

        titleLabel.text = Bundle.localizedString(forKey: "homepage_new_tag")
        titleLabel.font = UIFont.systemFont(ofSize: 17)
        contentView.addSubview(titleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        preImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: 24, height: 24))
        }

        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(preImageView.snp.trailing).offset(10)
            make.trailing.equalToSuperview().offset(-20)
            make.centerY.equalToSuperview()
        }
    }
}

final class RetroRomTagSelector: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private let fileItem: RetroRomFileItem
    private var tags: [RetroRomFileTag]
    private var itemTagIdArray: [Int]

    private var editingTitleCell: RetroRomTagTableViewCell?

    init(fileItem: RetroRomFileItem) {
        self.fileItem       = fileItem
        self.tags           = RetroRomFileManager.shared.getAllFileTags()
        self.itemTagIdArray = fileItem.tagIdArray
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = Bundle.localizedString(forKey: "tags")
        view.backgroundColor = .systemBackground

        tableView.dataSource = self
        tableView.delegate   = self
        tableView.rowHeight  = 50
        tableView.allowsSelection = true
        tableView.allowsMultipleSelection = false
        tableView.separatorInset = .init(top: 0, left: 20, bottom: 0, right: 20)
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.leading.equalTo(view.safeAreaLayoutGuide.snp.leading)
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.trailing.equalTo(view.safeAreaLayoutGuide.snp.trailing)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark.circle"), landscapeImagePhone: UIImage(systemName: "xmark.circle"), style: .plain, target: self, action: #selector(closeAction(_:)))
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        let set1 = Set(fileItem.tagIdArray)
        let set2 = Set(itemTagIdArray)

        if set1 != set2  {
            fileItem.updateFileTags(set2, oldTags: set1)
        }
    }

    fileprivate func shouldBeginUpdateTagTitle(_ cell: RetroRomTagTableViewCell) -> Bool {
        if let active = editingTitleCell, let tag = active.retroTag   {
            if let text = active.titleLabel.text?.trimmingCharacters(in: .whitespacesAndNewlines), text.count > 0 {
                let ret: Bool
                if !tag.stored {
                    ret = tag.store(title: text, colorValue: nil)
                } else {
                    ret = tag.update(title: text, colorValue: nil)
                }
                if ret {

                }
                editingTitleCell = cell
                return true
            } else {
                emptyTitleWarning()
                return false
            }
        } else {
            editingTitleCell = cell
            return true
        }
    }

    fileprivate func shouldEndUpdateTagTitle(_ cell: RetroRomTagTableViewCell) -> Bool {
        if let text = cell.titleLabel.text?.trimmingCharacters(in: .whitespacesAndNewlines), text.count > 0 {
            if let tag = cell.retroTag {
                let ret: Bool
                if !tag.stored {
                    ret = tag.store(title: text, colorValue: nil)
                } else {
                    ret = tag.update(title: text, colorValue: nil)
                }
                if ret {

                }
                editingTitleCell = nil
            }
            return true
        } else {
            if let tag = cell.retroTag, !tag.stored {
                if let indexPath = tableView.indexPath(for: cell) {
                    tags.removeAll(where: { $0.id == tag.id })
                    tableView.deleteRows(at: [indexPath], with: .automatic)
                }
                editingTitleCell = nil
                return true
            } else {
                emptyTitleWarning()
                return false
            }
        }
    }

    fileprivate func didEndUpdateTagTitle(_ cell: RetroRomTagTableViewCell) {
        if let tag = cell.retroTag, !tag.stored {
            if let indexPath = tableView.indexPath(for: cell) {
                tags.removeAll(where: { $0.id == tag.id })
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }
        }

        if cell == editingTitleCell {
            editingTitleCell = nil
        }
    }

    fileprivate func endUpdateTagTitlte() -> Bool {
        guard let cell = editingTitleCell else {
            return true
        }

        if let text = cell.titleLabel.text?.trimmingCharacters(in: .whitespacesAndNewlines), text.count > 0 {
            if let tag = cell.retroTag {
                let ret: Bool
                if !tag.stored {
                    ret = tag.store(title: text, colorValue: nil)
                } else {
                    ret = tag.update(title: text, colorValue: nil)
                }
                if ret {

                }
                editingTitleCell?.titleLabel.resignFirstResponder()
                editingTitleCell = nil
            }
            return true
        } else {
            emptyTitleWarning()
            return false
        }
    }

    @objc
    private func closeAction(_ sender: UIBarButtonItem) {
        navigationController?.dismiss(animated: true)
    }

    private func emptyTitleWarning() {
        let title = Bundle.localizedString(forKey: "warning")
        let message = Bundle.localizedString(forKey: "homepage_tag_title_cannot_null")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default)
        alert.addAction(okAction)
        present(alert, animated: true)
    }
}

extension RetroRomTagSelector: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
            case 0: return tags.count
            case 1: return 1
            default: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        if indexPath.section == 1 {
            let cell = { () -> RetroRomAddNewTagTableViewCell in
                let id = "RetroRomAddNewTagTableViewCell"
                if let cell = tableView.dequeueReusableCell(withIdentifier: id) as? RetroRomAddNewTagTableViewCell {
                    return cell
                } else {
                    return RetroRomAddNewTagTableViewCell(style: .default, reuseIdentifier: id)
                }
            }()
            return cell
        }

        let cell = { () -> RetroRomTagTableViewCell in
            let id = "RetroRomTagTableViewCell"
            if let cell = tableView.dequeueReusableCell(withIdentifier: id) as? RetroRomTagTableViewCell {
                return cell
            } else {
                return RetroRomTagTableViewCell(style: .default, reuseIdentifier: id)
            }
        }()

        let tag = tags[indexPath.row]
        cell.retroTag = tag
        cell.check    = itemTagIdArray.contains(tag.id)
        cell.holder   = self

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        Vibration.medium.vibrate()

        if let cell = editingTitleCell {
            if tableView.indexPath(for: cell) == indexPath {
                return
            }
            if let tag = cell.retroTag {
                if !tag.stored {
                    if let indexPath = tableView.indexPath(for: cell) {
                        tags.removeAll(where: { $0.id == tag.id })
                        tableView.deleteRows(at: [indexPath], with: .automatic)
                    }
                } else {
                    if let text = cell.titleLabel.text?.trimmingCharacters(in: .whitespacesAndNewlines), text.count > 0 {
                        _ = tag.update(title: text, colorValue: nil)
                    } else {
                        return emptyTitleWarning()
                    }
                }
            }
            editingTitleCell?.titleLabel.resignFirstResponder()
            editingTitleCell = nil
        }

        if indexPath.section == 0 {
            let cell = tableView.cellForRow(at: indexPath) as? RetroRomTagTableViewCell
            let tag = tags[indexPath.row]
            if itemTagIdArray.contains(tag.id) {
                itemTagIdArray.removeAll(where: { $0 == tag.id })
                cell?.check = false
            } else {
                itemTagIdArray.append(tag.id)
                cell?.check = true
            }
        } else {
            guard let newId = RetroRomFileManager.shared.getUniqueFileTagId() else {
                return
            }

            let newIndexPath = IndexPath(item: tags.count, section: 0)
            let newTag = RetroRomFileTag(id: newId, title: nil, color: nil, createAt: Date(), isHidden: false, stored: false)
            tags.append(newTag)
            tableView.insertRows(at: [newIndexPath], with: .automatic)
            DispatchQueue.main.async {
                guard let cell = tableView.cellForRow(at: newIndexPath) as? RetroRomTagTableViewCell else {
                    return
                }
                cell.titleLabel.becomeFirstResponder()
                self.editingTitleCell = cell
            }
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        if indexPath.section == 0 {
            let tag = tags[indexPath.row]
            if tag.isSystemTag {
                return nil
            }

            let deleteAction = UIContextualAction(style: .destructive, title: Bundle.localizedString(forKey: "delete")) { [weak self] _, _, completionHandler in
                RetroRomFileManager.shared.deleteFileTag(tag)
                self?.itemTagIdArray.removeAll(where: { $0 == tag.id })
                self?.tags.remove(at: indexPath.row)
                tableView.deleteRows(at: [indexPath], with: .automatic)
                completionHandler(true)
            }
            deleteAction.backgroundColor = .red
            let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
            configuration.performsFirstActionWithFullSwipe = true
            return configuration
        } else {
            return nil
        }
    }
}
