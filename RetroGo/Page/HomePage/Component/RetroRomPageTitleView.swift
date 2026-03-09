//
//  RetroRomPageTitleView.swift
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

final class RetroRomPageTitleView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    // 创建一个容器，用于包裹 icon 和 label，方便整体居中
    private let contentView = UIView()

    init() {
        // 在导航栏中使用 titleView，通常不需要设置具体的 frame
        // 系统会根据约束或 intrinsicContentSize 来布局
        super.init(frame: .zero)
        configUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configUI() {
        addSubview(contentView)
        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)

        // 1. 容器约束：水平居中，上下撑开
        contentView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.top.bottom.equalToSuperview()
            // 限制最大宽度，防止导航栏左右按钮重叠
            make.width.lessThanOrEqualToSuperview()
        }

        // 2. 图标约束
        iconView.tintColor = .label
        iconView.contentMode = .scaleAspectFit
        iconView.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
            make.size.equalTo(20)
        }

        // 3. 标签约束
        titleLabel.font = UIFont.boldSystemFont(ofSize: 17) // 导航栏标准字号
        titleLabel.textAlignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(iconView.snp.right).offset(6) // 间距
            make.right.equalToSuperview()
            make.centerY.equalToSuperview()
        }
    }

    func updatePageTitle() {
        let state = RetroRomHomePageState.shared
        let image: UIImage?
        let titleText: String

        if state.homeBrowserType == .tree {
            image = UIImage(systemName: "folder")
            titleText = "Retro Go"
        } else {
            switch state.homeOrganizeType {
            case .byFolder:
                image = UIImage(systemName: "folder")
                titleText = state.homeCurrentFolderItem.itemPageTitle
            case .byTag:
                image = UIImage(systemName: "tag")
                titleText = "Retro Go"
            case .byCore:
                image = UIImage(systemName: "cpu")
                titleText = "Retro Go"
            }
        }

        iconView.image = image
        titleLabel.text = titleText

        // 关键：通知系统布局已改变，重新计算 titleView 的大小
        self.invalidateIntrinsicContentSize()
    }

    // 让导航栏知道这个 View 应该有多大
    override var intrinsicContentSize: CGSize {
        // 自动计算内容宽度
        contentView.layoutIfNeeded()
        let size = contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: size.width, height: 44)
    }
}
