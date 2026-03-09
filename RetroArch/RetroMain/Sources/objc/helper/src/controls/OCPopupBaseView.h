//
//  OCPopupBaseView.h
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

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OCPopupViewAnchorPosition) {
    OCPopupViewAnchorPositionTop,
    OCPopupViewAnchorPositionBottom
};

@interface OCPopupViewConfig : NSObject
@property(nonatomic, assign, readonly) CGFloat cornerRadius;
@property(nonatomic, assign, readonly) CGFloat deltaHeight;
@property(nonatomic, assign, readonly) CGFloat sharpWidth;
@property(nonatomic, assign, readonly) CGFloat sharpRadius;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCornerRadius:(CGFloat)cornerRadius deltaHeight:(CGFloat)deltaHeight sharpWidth:(CGFloat)sharpWidth sharpRadius:(CGFloat)sharpRadius;

+ (instancetype)defaultConfig;
@end

@interface OCPopupBaseView : UIView
@property(nonatomic, assign, nullable, readonly) CGPathRef shapePath;
@property(nonatomic, strong, readonly) UIView *containerView;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithSize:(CGSize)size anchorPosition:(OCPopupViewAnchorPosition)position;
- (instancetype)initWithSize:(CGSize)size anchorPosition:(OCPopupViewAnchorPosition)position viewConfig:(OCPopupViewConfig *)config;

- (void)install:(CGRect)anchorRect;
- (void)uninstall;
@end

NS_ASSUME_NONNULL_END
