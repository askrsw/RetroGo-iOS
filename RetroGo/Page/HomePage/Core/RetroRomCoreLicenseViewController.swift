//
//  RetroRomCoreLicenseViewController.swift
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

final class RetroRomCoreLicenseViewController: UIViewController {
    let textView = UITextView(frame: .zero)

    let showName: String
    let fileName: String

    init(showName: String, fileName: String) {
        self.showName = showName
        self.fileName = fileName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = showName
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark.circle"), style: .plain, target: self, action: #selector(close))
        view.backgroundColor = .systemBackground

        setupTextView()
        loadLicenseContent()
    }

    @objc
    private func close() {
        navigationController?.dismiss(animated: true)
    }

    private func setupTextView() {
        view.addSubview(textView)
        textView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // Native UITextView 配置
        // 1. 设置等宽字体，适合代码/协议展示
        textView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .label

        // 2. 交互属性
        textView.isEditable = false       // 不可编辑
        textView.isSelectable = true      // 可选中复制

        // 3. 布局属性
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 32, right: 16)
        textView.showsVerticalScrollIndicator = true
        textView.backgroundColor = .clear // 跟随 self.view

        // 4. 自动高亮链接 (原生支持)
        textView.dataDetectorTypes = .link
    }

    private func loadLicenseContent() {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: "Data/licenses") else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            textView.text = text
        } catch {
            textView.text = "Error reading license file:\n\(error.localizedDescription)"
            textView.textColor = .systemRed
        }
    }
}
