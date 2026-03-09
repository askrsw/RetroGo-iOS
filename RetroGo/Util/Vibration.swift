//
//  Vibration.swift
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
import AudioToolbox

public enum Vibration {
    case none
    case error
    case success
    case warning
    case light
    case medium
    case heavy
    @available(iOS 13.0, *) case soft
    @available(iOS 13.0, *) case rigid
    case selection
    case oldSchool

    // 映射到系统类型
    public func vibrate() {
        guard AppSettings.shared.isUIFeedbackEnabled else { return }

        switch self {
            case .none: break
            case .error:
                FeedbackHelper.notification.notificationOccurred(.error)
            case .success:
                FeedbackHelper.notification.notificationOccurred(.success)
            case .warning:
                FeedbackHelper.notification.notificationOccurred(.warning)
            case .light:
                FeedbackHelper.impact(.light)
            case .medium:
                FeedbackHelper.impact(.medium)
            case .heavy:
                FeedbackHelper.impact(.heavy)
            case .soft:
                FeedbackHelper.impact(.soft)
            case .rigid:
                FeedbackHelper.impact(.rigid)
            case .selection:
                FeedbackHelper.selection.selectionChanged()
            case .oldSchool:
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
}

private class FeedbackHelper {
    static let notification = UINotificationFeedbackGenerator()
    static let selection = UISelectionFeedbackGenerator()

    // 缓存不同风格的 ImpactGenerator
    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        if impactGenerators[style] == nil {
            impactGenerators[style] = UIImpactFeedbackGenerator(style: style)
        }
        let generator = impactGenerators[style]
        generator?.prepare() // 预热
        generator?.impactOccurred()
    }
}
