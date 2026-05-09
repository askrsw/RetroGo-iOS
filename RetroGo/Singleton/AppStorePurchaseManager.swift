//
//  AppStorePurchaseManager.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/8.
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

import StoreKit
import Foundation

enum IAPProductID {
    static let monthly: String = {
        guard let dict = inAppPurchaseDict else { return "" }
        return dict["ProMonthly"] ?? ""
    }()

    static let yearly: String = {
        guard let dict = inAppPurchaseDict else { return "" }
        return dict["ProYearly"] ?? ""
    }()

    static let lifetime: String = {
        guard let dict = inAppPurchaseDict else { return "" }
        return dict["ProLifetime"] ?? ""
    }()

    private static let inAppPurchaseDict = Bundle.main.object(forInfoDictionaryKey: "InAppPurchase") as? Dictionary<String, String>
}
