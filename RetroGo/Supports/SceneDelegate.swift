//
//  SceneDelegate.swift
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

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else {
            fatalError("Could not get window scene instance.")
        }
        window = UIWindow(windowScene: windowScene)
        window?.overrideUserInterfaceStyle = .dark

        if let delegate = UIApplication.shared.delegate as? AppDelegate {
            delegate.window = window
        }

        let controller: UIViewController
        if AppSettings.shared.systemHomePage {
            controller = SystemDocumentBrowser()
        } else {
            controller = UINavigationController(rootViewController: HomePageViewController())
        }

        window?.rootViewController = controller
        window?.makeKeyAndVisible()
    }

    func switchSystemHomepageController() {
        guard let window = self.window else { return }

        let controller: UIViewController
        if AppSettings.shared.systemHomePage {
            controller = SystemDocumentBrowser()
        } else {
            controller = UINavigationController(rootViewController: HomePageViewController())
        }

        window.rootViewController = controller

        UIView.transition(with: window, duration: 0.5, options: .transitionFlipFromRight, animations: nil, completion: nil)
    }
}
