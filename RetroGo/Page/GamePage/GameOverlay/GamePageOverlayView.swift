//
//  GamePageOverlayView.swift
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

import SpriteKit
import ObjcHelper
import RACoordinator

final class GamePageOverlayView: SKView {
    private(set) var coreInfoItem: EmuCoreInfoItem
    private(set) var overlayScene: GamePageOverlayScene?

    init(coreInfoItem: EmuCoreInfoItem ) {
        self.coreInfoItem = coreInfoItem
        super.init(frame: .zero)
        applyCoreMode(coreInfoItem)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateCoreInfoItem(_ coreInfoItem: EmuCoreInfoItem) {
        guard self.coreInfoItem.coreId != coreInfoItem.coreId else {
            return
        }
        self.coreInfoItem = coreInfoItem
        applyCoreMode(coreInfoItem)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if scene !== overlayScene {
            presentScene(overlayScene)
        }
        overlayScene?.updateLayout(for: size)
    }
}

extension GamePageOverlayView {
    enum OverlayName: String {
        case `default` = "default"
        case n64 = "n64"
        case nes = "nes"
        case nds = "nds"
        case gbc = "gbc"
        case gba = "gba"
        case snes = "snes"
        case saturn = "saturn"
        case ps = "ps"
        case psp = "psp"
    }

    private func applyCoreMode(_ coreInfoItem: EmuCoreInfoItem) {
        if coreInfoItem.coreId != "dosbox-pure" {
            allowsTransparency = true
            backgroundColor = .clear
            ignoresSiblingOrder = true
            isMultipleTouchEnabled = true
            isUserInteractionEnabled = true
            isHidden = false
            isPaused = false
            let overlayName = OverlayName(rawValue: coreInfoItem.overlayName ?? "")!
            // let overlayName = OverlayName.psp
            overlayScene = makeOverlayScene(name: overlayName, supportsAnalog: coreInfoItem.supportsAnalog)
        } else {
            isHidden = true
            isUserInteractionEnabled = false
            isPaused = true
            overlayScene = nil
            if scene != nil {
                presentScene(nil)
            }
        }
    }

    private func makeOverlayScene(name: OverlayName, supportsAnalog: Bool) -> GamePageOverlayScene? {
        guard let url = Bundle.main.url(forResource: name.rawValue, withExtension: "json", subdirectory: "Data/overlays/spritekit") else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let data = try Data(contentsOf: url)
            let config = try decoder.decode(GamePageOverlayConfig.self, from: data)
            return GamePageOverlayScene(size: .zero, config: config, supportsAnalog: supportsAnalog)
        } catch {
        #if DEBUG
            fatalError(error.localizedDescription)
        #else
            return nil
        #endif
        }
    }
}
