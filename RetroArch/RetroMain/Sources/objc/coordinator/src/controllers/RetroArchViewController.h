//
//  RetroArchViewController.h
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

#import <UIKit/UIKit.h>
#import <darwin/apple_platform.h>

NS_ASSUME_NONNULL_BEGIN

@class EmuCoreInfoItem;
@class EmuInGameMessage;

@interface RetroArchViewController : UIViewController <ApplePlatform, UIPointerInteractionDelegate>
@property(nonatomic, strong, readonly) UIView *hudView;
@property(nonatomic, strong, readonly) UIView *overlayView;
@property(nonatomic, assign, readwrite) BOOL useRetroArchOverlay;
@property(nonatomic, assign, readwrite) BOOL useSpriteKitOverlay;
@property(nonatomic, strong, readonly) EmuCoreInfoItem *core;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCore:(EmuCoreInfoItem *)core;
- (void)showInGameMessage:(EmuInGameMessage *)message NS_SWIFT_NAME(showInGameMessage(_:));
@end

NS_ASSUME_NONNULL_END
