//
//  GamePageLoadingView.swift
//  RetroGo
//
//  Created by haharsw on 2026/3/15.
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

final class GamePageLoadingView: UIView {
    let indicator = UIActivityIndicatorView(style: .large)
    let messageLabel = UILabel(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = UIColor.black.withAlphaComponent(0.25)
        isUserInteractionEnabled = false

        configUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func install() {
        guard let window = UIWindow.currentKey() else {
            return
        }

        self.frame = window.bounds
        window.addSubview(self)

        indicator.startAnimating()
    }

    func uninstall() {
        indicator.stopAnimating()
        removeFromSuperview()
    }
}

extension GamePageLoadingView {
    private func configUI() {
        indicator.color = .white
        indicator.sizeToFit()
        addSubview(indicator)
        indicator.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().multipliedBy(0.75)
            make.size.equalTo(indicator.size)
        }

        messageLabel.text = Bundle.localizedString(forKey: "gamepage_game_loading")
        messageLabel.textColor = .label
        messageLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        messageLabel.textAlignment = .center
        addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.top.equalTo(indicator.snp.bottom).offset(20)
            make.centerX.equalToSuperview()
        }
    }
}
