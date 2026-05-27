//
//  UIViewController+Extension.m
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

#import "UIViewController+Extension.h"
#import "UIWindow+Extension.h"
#import "UIView+Extension.h"

@implementation UIViewController (Extension)

+ (UIViewController *)currentActiveViewController {
    UIWindow *keyWindow = [UIWindow currentKeyWindow];
    UIViewController *rootViewController = keyWindow.rootViewController;
    if (rootViewController) {
        return [self getCurrentViewControllerWithRootViewController:rootViewController];
    } else {
        return nil;
    }
}

+ (UIViewController *)getCurrentViewControllerWithRootViewController:(UIViewController *)rootViewController {
    if ([rootViewController isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabBarController = (UITabBarController *)rootViewController;
        UIViewController *selectedController = tabBarController.selectedViewController;
        if (selectedController) {
            return [self getCurrentViewControllerWithRootViewController:selectedController];
        }
    }

    if ([rootViewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navigationController = (UINavigationController *)rootViewController;
        UIViewController *visibleController = navigationController.visibleViewController;
        if (visibleController) {
            return [self getCurrentViewControllerWithRootViewController:visibleController];
        }
    }

    if (rootViewController.presentedViewController) {
        return [self getCurrentViewControllerWithRootViewController:rootViewController.presentedViewController];
    } else {
        return rootViewController;
    }
}

+ (UIView *)makeIconTitleView:(NSString *)title icon:(UIImage *)icon {
    UIImageView *iconView = [[UIImageView alloc] initWithImage:icon];
    iconView.contentMode         = UIViewContentModeScaleAspectFit;
    iconView.layer.cornerRadius  = 6;
    iconView.layer.masksToBounds = YES;
    iconView.clipsToBounds       = YES;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;

    // 用约束锁死尺寸，Stack View 才会遵从
    [NSLayoutConstraint activateConstraints:@[
        [iconView.widthAnchor  constraintEqualToConstant:22],
        [iconView.heightAnchor constraintEqualToConstant:22],
    ]];

    UILabel *titleLabel   = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.text       = title;
    titleLabel.font       = [UIFont boldSystemFontOfSize:17.0];
    titleLabel.textColor  = UIColor.labelColor;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[iconView, titleLabel]];
    stack.axis         = UILayoutConstraintAxisHorizontal;
    stack.alignment    = UIStackViewAlignmentCenter;
    stack.spacing      = 8.0;
    return stack;
}

- (void)setLargeTitleDisplayMode:(UINavigationItemLargeTitleDisplayMode)largeTitleDisplayMode {
    switch (largeTitleDisplayMode) {
        case UINavigationItemLargeTitleDisplayModeAutomatic: {
            UINavigationController *navigationController = self.navigationController;
            if (navigationController) {
                NSUInteger index = [navigationController.viewControllers indexOfObject:self];
                if (index != NSNotFound) {
                    [self setLargeTitleDisplayMode:(index == 0 ? UINavigationItemLargeTitleDisplayModeAlways : UINavigationItemLargeTitleDisplayModeNever)];
                } else {
                    [self setLargeTitleDisplayMode:UINavigationItemLargeTitleDisplayModeAlways];
                }
            }
            break;
        }
        case UINavigationItemLargeTitleDisplayModeAlways:
        case UINavigationItemLargeTitleDisplayModeNever: {
            self.navigationItem.largeTitleDisplayMode = [self isLargeTitleAvailable] ? largeTitleDisplayMode : UINavigationItemLargeTitleDisplayModeNever;
            self.navigationController.navigationBar.prefersLargeTitles = YES;
            break;
        }
        case UINavigationItemLargeTitleDisplayModeInline:
            break;
        default:
            NSAssert(NO, @"Missing handler for largeTitleDisplayMode");
            break;
    }
}

- (BOOL)isLargeTitleAvailable {
    UIContentSizeCategory contentSizeCategory = self.traitCollection.preferredContentSizeCategory;
    if ([contentSizeCategory isEqualToString:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge] ||
        [contentSizeCategory isEqualToString:UIContentSizeCategoryAccessibilityExtraExtraLarge] ||
        [contentSizeCategory isEqualToString:UIContentSizeCategoryAccessibilityExtraLarge] ||
        [contentSizeCategory isEqualToString:UIContentSizeCategoryAccessibilityLarge] ||
        [contentSizeCategory isEqualToString:UIContentSizeCategoryAccessibilityMedium] ||
        [contentSizeCategory isEqualToString:UIContentSizeCategoryExtraExtraExtraLarge]) {
        return NO;
    }

    return [UIScreen mainScreen].bounds.size.height > 568;
}
@end
