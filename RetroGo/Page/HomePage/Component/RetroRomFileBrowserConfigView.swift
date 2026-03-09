//
//  RetroRomFileBrowserConfigView.swift
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
import ObjcHelper

enum RetroRomConfigButtonName: Int {
    case icon, list, tree
    case folder, tag, core
    case name, lastPlay, addDate, gameDuration
    case refresh

    var title: String {
        switch self {
            case .icon:
                return Bundle.localizedString(forKey: "homepage_config_icon")
            case .list:
                return Bundle.localizedString(forKey: "homepage_config_list")
            case .tree:
                return Bundle.localizedString(forKey: "homepage_config_tree")
            case .folder:
                return Bundle.localizedString(forKey: "homepage_config_by_folder")
            case .tag:
                return Bundle.localizedString(forKey: "Homepage_config_by_tag")
            case .core:
                return Bundle.localizedString(forKey: "homepage_config_by_core")
            case .name:
                return Bundle.localizedString(forKey: "homepage_config_name")
            case .lastPlay:
                return Bundle.localizedString(forKey: "homepage_config_last_play")
            case .addDate:
                return Bundle.localizedString(forKey: "homepage_config_add_date")
            case .gameDuration:
                return Bundle.localizedString(forKey: "homepage_config_game_duration")
            case .refresh:
                return Bundle.localizedString(forKey: "refresh")
        }
    }

    var lineType: RetroRomConfigButtonLineType {
        switch self {
            case .icon: return .bottom
            case .list: return .bottom
            case .tree: return .none
            case .folder: return .bottom
            case .tag: return .none
            case .core: return .bottom
            case .name: return .bottom
            case .lastPlay: return .bottom
            case .addDate: return .bottom
            case .gameDuration: return .bottom
            case .refresh: return .none
        }
    }

    var smallPost: Bool {
        switch self {
            case .icon, .list, .tree, .folder, .tag, .core: return false
            case .name, .lastPlay, .addDate, .gameDuration: return true
            case .refresh: return false
        }
    }
}

enum RetroRomConfigButtonLineType {
    case none, top, bottom, both
}

final class RetroRomConfigButton: UIView {
    private let preImageView = UIImageView(frame: .zero)
    private let titleLabel = UILabel(frame: .zero)
    private let postImageView = UIImageView(frame: .zero)
    private let topLine = UIImageView(frame: .zero)
    private let bottomLine = UIImageView(frame: .zero)

    var checked: Bool = false {
        didSet {
            if checked {
                if preImageView.image == nil {
                    preImageView.image = UIImage(systemName: "checkmark")
                }
                preImageView.isHidden = false
            } else {
                preImageView.isHidden = true
            }
        }
    }

    var title: String? {
        didSet {
            if let title = title {
                let attributes = Self.textAttributes()
                titleLabel.attributedText = NSAttributedString(string: title, attributes: attributes)
            } else {
                titleLabel.attributedText = nil
            }
        }
    }

    var icon: UIImage? {
        didSet {
            postImageView.image = icon
        }
    }

    var lineType: RetroRomConfigButtonLineType = .both {
        didSet {
            switch lineType {
                case .none:
                    topLine.isHidden = true
                    bottomLine.isHidden = true
                case .top:
                    bottomLine.isHidden = true
                case .bottom:
                    topLine.isHidden = true
                case .both:
                    break
            }
        }
    }

    var isCurrent: Bool = false {
        didSet {
            if isCurrent {
                backgroundColor = UIColor(hex: 0x444444, alpha: 1.0)
            } else {
                backgroundColor = UIColor(hex: 0x222222, alpha: 1.0)
            }
        }
    }

    var smallPost: Bool = false
    let buttonName: RetroRomConfigButtonName
    let buttonAction: () -> Void

    init(buttonName: RetroRomConfigButtonName, buttonAction: @escaping () -> Void) {
        self.buttonName = buttonName
        self.buttonAction = buttonAction
        super.init(frame: .zero)

        backgroundColor = UIColor(hex: 0x222222, alpha: 1.0)

        preImageView.tintColor = .label
        preImageView.contentMode = .scaleAspectFit
        addSubview(preImageView)

        addSubview(titleLabel)

        postImageView.tintColor = .label
        postImageView.contentMode = .scaleAspectFit
        addSubview(postImageView)

        let lineColor = UIColor(hex: 0xAAAAAA, alpha: 1.0)
        topLine.image = UIImage.fill(lineColor, with: CGSize(width: 400, height: 0.2), factor: 3.0)
        addSubview(topLine)

        bottomLine.image = UIImage.fill(lineColor, with: CGSize(width: 400, height: 0.2), factor: 3.0)
        addSubview(bottomLine)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let titleWidth = width - (20 + 30 + 10 + 30)
        preImageView.frame = CGRect(x: 10, y: (height - 15) * 0.5 + 1, width: 15, height: 15)
        titleLabel.frame = CGRect(x: 35, y: 0, width: titleWidth, height: height)

        if smallPost {
            postImageView.frame = CGRect(x: titleLabel.maxX + 25, y: (height - 15) * 0.5, width: 15, height: 15)
        } else {
            postImageView.frame = CGRect(x: titleLabel.maxX + 20, y: (height - 20) * 0.5, width: 20, height: 20)
        }

        topLine.frame = CGRect(x: 0, y: 0, width: width, height: 0.2)
        bottomLine.frame = CGRect(x: 0, y: height - 0.2, width: width, height: 0.2)
    }

    func config() {
        self.title = buttonName.title
        self.lineType = buttonName.lineType
        self.smallPost = buttonName.smallPost
    }

    func act() {
        buttonAction()
    }
}


extension RetroRomConfigButton {
    static let rowHeight: CGFloat = 44.0

    static let textAttributes = { () -> [NSAttributedString.Key: Any] in
        [
            .font: UIFont.systemFont(ofSize: UIFont.labelFontSize),
            .foregroundColor: UIColor.label
        ]
    }

    static func rekonMaxTitleWidth() -> CGFloat {
        let maxWidth = DeviceConfig.screenWidth * 0.667 - (20 + 30 + 30 + 30)
        let keys = [
            "homepage_config_icon",
            "homepage_config_list",
            "homepage_config_tree",
            "homepage_config_by_folder",
            "Homepage_config_by_tag",
            "homepage_config_by_core",
            "homepage_config_name",
            "homepage_config_last_play",
            "homepage_config_add_date",
            "homepage_config_game_duration",
            "refresh"
        ]

        let attributes = Self.textAttributes()

        var width: CGFloat = 0
        for key in keys {
            let title = Bundle.localizedString(forKey: key)
            let attributed = NSAttributedString(string: title, attributes: attributes)
            let w = attributed.calculateDrawingSize(withWidth: maxWidth, height: 0, option: .usesLineFragmentOrigin).width
            if width < w {
                width = w
            }
        }
        return width
    }
}

final class RetroRomFileBrowserConfigView: UIView {
    private(set) lazy var maskedView: OCMaskView? = OCMaskView { [weak self] in
        guard let self = self else { return true }
        UIView.animate(withDuration: 0.125, animations: {
            self.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        }, completion: { _ in
            self.removeFromSuperview()
            self.maskedView?.removeFromSuperview()
            self.maskedView = nil
        })
        return false
    }

    private(set) lazy var buttonDict: [RetroRomConfigButtonName: RetroRomConfigButton] = [
        .icon: .init(buttonName: .icon, buttonAction: { [weak self] in
            HomePageViewController.instance?.iconOption()
            self?.dismiss()
        }),
        .list: .init(buttonName: .list, buttonAction: { [weak self] in
            HomePageViewController.instance?.listOption()
            self?.dismiss()
        }),
        .tree: .init(buttonName: .tree, buttonAction: { [weak self] in
            HomePageViewController.instance?.treeOption()
            self?.dismiss()
        }),
        .folder: .init(buttonName: .folder, buttonAction: { [weak self] in
            HomePageViewController.instance?.folderOption()
            self?.dismiss()
        }),
        .tag: .init(buttonName: .tag, buttonAction: { [weak self] in
            HomePageViewController.instance?.tagOption()
            self?.dismiss()
        }),
        .core: .init(buttonName: .core, buttonAction: { [weak self] in
            HomePageViewController.instance?.coreOption()
            self?.dismiss()
        }),
        .name: .init(buttonName: .name, buttonAction: { [weak self] in
            HomePageViewController.instance?.nameOption()
            self?.dismiss()
        }),
        .lastPlay: .init(buttonName: .lastPlay, buttonAction: { [weak self] in
            HomePageViewController.instance?.lastPlayOption()
            self?.dismiss()
        }),
        .addDate: .init(buttonName: .addDate, buttonAction: { [weak self] in
            HomePageViewController.instance?.addDateOption()
            self?.dismiss()
        }),
        .gameDuration: .init(buttonName: .gameDuration, buttonAction: { [weak self] in
            HomePageViewController.instance?.gameDurationOption()
            self?.dismiss()
        }),
        .refresh: .init(buttonName: .refresh, buttonAction: { [weak self] in
            HomePageViewController.instance?.refresh()
            self?.dismiss()
        })
    ]

    let barButtonItem: UIBarButtonItem

    private var currentButton: RetroRomConfigButtonName? {
        didSet {
            if currentButton != oldValue {
                if let v = oldValue {
                    buttonDict[v]?.isCurrent = false
                }
                if let v = currentButton {
                    buttonDict[v]?.isCurrent = true
                }
            }
        }
    }

    init(barButtonItem: UIBarButtonItem) {
        self.barButtonItem = barButtonItem
        super.init(frame: .zero)

        configUI()
        configButtons()
        addSubViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addSubViews() {
        for (_, v) in buttonDict {
            v.removeFromSuperview()
        }

        let width = RetroRomConfigButton.rekonMaxTitleWidth() + (20 + 30 + 30 + 35)
        let buttonHeight = RetroRomConfigButton.rowHeight
        var y: CGFloat = 0

        do {
            let array1: [RetroRomConfigButtonName] = [.icon, .list, .tree]
            for k in array1 {
                guard let button = buttonDict[k] else { continue }
                button.frame = CGRect(x: 0, y: y, width: width, height: buttonHeight)
                button.config()
                addSubview(button)
                y += buttonHeight
            }
            y += 10
        }

        if RetroRomHomePageState.shared.homeBrowserType != .tree {
            let array2: [RetroRomConfigButtonName] = [.folder, .core, .tag]
            for k in array2 {
                guard let button = buttonDict[k] else { continue }
                button.frame = CGRect(x: 0, y: y, width: width, height: buttonHeight)
                button.config()
                addSubview(button)
                y += buttonHeight
            }
            y += 10
        }

        do {
            let array3: [RetroRomConfigButtonName] = [.name, .lastPlay, .addDate, .gameDuration, .refresh]
            for k in array3 {
                guard let button = buttonDict[k] else { continue }
                button.frame = CGRect(x: 0, y: y, width: width, height: buttonHeight)
                button.config()
                addSubview(button)
                y += buttonHeight
            }
        }

        let height = y
        self.frame = CGRect(origin: self.origin, size: CGSize(width: width, height: height))
    }

    func install() {
        guard let maskedView = maskedView, let window = UIWindow.currentKey() else {
            return
        }

        let sourceFrame = self.barButtonItem.frameInView(window) ?? .zero
        let x = sourceFrame.maxX - width
        self.origin = CGPoint(x: x, y: sourceFrame.maxY)
        maskedView.install()
        window.addSubview(self)

        let y: CGFloat = self.frame.origin.y
        self.layer.anchorPoint = CGPoint(x: 1, y: 0)
        self.center = CGPoint(x: sourceFrame.maxX , y: y)

        self.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        UIView.animate(withDuration: 0.125) {
            self.transform = CGAffineTransform.identity
        }
    }

    func updateState() {
        switch RetroRomHomePageState.shared.homeBrowserType {
            case .icon:
                buttonDict[.icon]?.checked = true
                buttonDict[.list]?.checked = false
                buttonDict[.tree]?.checked = false
            case .list:
                buttonDict[.icon]?.checked = false
                buttonDict[.list]?.checked = true
                buttonDict[.tree]?.checked = false
            case .tree:
                buttonDict[.icon]?.checked = false
                buttonDict[.list]?.checked = false
                buttonDict[.tree]?.checked = true
        }

        switch RetroRomHomePageState.shared.homeOrganizeType {
            case .byFolder:
                buttonDict[.folder]?.checked = true
                buttonDict[.tag]?.checked    = false
                buttonDict[.core]?.checked   = false
            case .byTag:
                buttonDict[.folder]?.checked = false
                buttonDict[.tag]?.checked    = true
                buttonDict[.core]?.checked   = false
            case .byCore:
                buttonDict[.folder]?.checked = false
                buttonDict[.tag]?.checked    = false
                buttonDict[.core]?.checked   = true
        }

        let array: [RetroRomConfigButtonName] = [.name, .lastPlay, .addDate, .gameDuration]
        array.forEach { k in
            buttonDict[k]?.icon = nil
            buttonDict[k]?.checked = false
        }

        switch RetroRomHomePageState.shared.homeFileSortType {
            case .fileNameAsc:
                buttonDict[.name]?.icon =  UIImage(systemName: "chevron.up")
                buttonDict[.name]?.checked = true
            case .fileNameDesc:
                buttonDict[.name]?.icon =  UIImage(systemName: "chevron.down")
                buttonDict[.name]?.checked = true
            case .lastPlay:
                buttonDict[.lastPlay]?.checked = true
            case .addDateAsc:
                buttonDict[.addDate]?.icon = UIImage(systemName: "chevron.up")
                buttonDict[.addDate]?.checked = true
            case .addDateDesc:
                buttonDict[.addDate]?.icon = UIImage(systemName: "chevron.down")
                buttonDict[.addDate]?.checked = true
            case .playTime:
                buttonDict[.gameDuration]?.checked = true
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        let touchPoint = touch.location(in: self)
        for (k, v) in buttonDict {
            if v.frame.contains(touchPoint) {
                currentButton = k
                break
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first else { return }
        let touchPoint = touch.location(in: self)
        for (k, v) in buttonDict {
            if v.frame.contains(touchPoint) {
                currentButton = k
                break
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if let k = currentButton, let v = buttonDict[k] {
            v.act()
        }
        currentButton = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        currentButton = nil
    }
}

extension RetroRomFileBrowserConfigView {
    private func dismiss() {
        UIView.animate(withDuration: 0.25, delay: 0.1, animations: {
            self.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        }, completion: { _ in
            self.removeFromSuperview()
            self.maskedView?.removeFromSuperview()
            self.maskedView = nil
        })
    }

    private func configButtons() {
        buttonDict[.icon]?.icon = UIImage(systemName: "square.grid.2x2")
        buttonDict[.list]?.icon = UIImage(systemName: "list.bullet")
        buttonDict[.tree]?.icon = UIImage(named: "Icon_tree")
        buttonDict[.folder]?.icon = UIImage(systemName: "folder")
        buttonDict[.tag]?.icon = UIImage(systemName: "tag")
        buttonDict[.core]?.icon = UIImage(systemName: "cpu")
        buttonDict[.refresh]?.icon = UIImage(systemName: "arrow.clockwise")

        updateState()
    }

    private func configUI() {
        self.backgroundColor = UIColor(hex: 0x111111, alpha: 1.0)

        self.layer.cornerRadius = 12
        self.layer.masksToBounds = true
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOpacity = 0.3
        self.layer.shadowOffset = CGSize(width: 0, height: 2)
        self.layer.shadowRadius = 4
    }
}

extension UIBarButtonItem {
    fileprivate func frameInView(_ view: UIView) -> CGRect? {
        guard let view = self.value(forKey: "view") as? UIView else {
            return nil
        }
        return view.superview?.convert(view.frame, to: nil)
    }
}
