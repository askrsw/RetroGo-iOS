//
//  OCPopupBaseView.m
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

#import "OCPopupBaseView.h"
#import "../utils/OCMaskView.h"

#import <CoreGraphics/CoreGraphics.h>
#import <UIKit+Extensions.h>

@implementation OCPopupViewConfig

- (instancetype)initWithCornerRadius:(CGFloat)cornerRadius deltaHeight:(CGFloat)deltaHeight sharpWidth:(CGFloat)sharpWidth sharpRadius:(CGFloat)sharpRadius {
    self = [super init];
    if(self != nil) {
        _cornerRadius = cornerRadius;
        _deltaHeight  = deltaHeight;
        _sharpWidth   = sharpWidth;
        _sharpRadius  = sharpRadius;
    }
    return self;
}

+ (instancetype)defaultConfig {
    static OCPopupViewConfig *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OCPopupViewConfig alloc] initWithCornerRadius:8 deltaHeight:10 sharpWidth:8 sharpRadius:3];
    });
    return instance;
}

@end

@implementation OCPopupBaseView {
    OCPopupViewAnchorPosition d_anchorPosition;
    OCPopupViewConfig        *d_viewConfig;

    CAShapeLayer *d_shapeLayer;
    UIView       *d_containerView;
    OCMaskView   *d_maskView;
}

- (instancetype)initWithSize:(CGSize)size anchorPosition:(OCPopupViewAnchorPosition)position {
    return [self initWithSize:size anchorPosition:position viewConfig:[OCPopupViewConfig defaultConfig]];
}

- (instancetype)initWithSize:(CGSize)size anchorPosition:(OCPopupViewAnchorPosition)position viewConfig:(OCPopupViewConfig *)config {
    self = [super initWithFrame:CGRectMake(0, 0, size.width, size.height)];
    if(self != nil) {
        d_anchorPosition = position;
        d_viewConfig     = config;

        d_shapeLayer = [[CAShapeLayer alloc] init];
        d_shapeLayer.frame = CGRectMake(0, 0, size.width, size.height);
        d_shapeLayer.fillColor = [[UIColor systemBackgroundColor] CGColor];
        d_shapeLayer.shadowColor = [[UIColor labelColor] CGColor];
        d_shapeLayer.shadowRadius = 4.0;
        d_shapeLayer.shadowOffset = CGSizeMake(0, 0);
        d_shapeLayer.shadowOpacity = 0.2;
        [self.layer addSublayer:d_shapeLayer];

        d_containerView = [[UIView alloc] initWithFrame:CGRectZero];
        d_containerView.layer.cornerRadius = [d_viewConfig cornerRadius];
        d_containerView.layer.masksToBounds = YES;
        d_containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:d_containerView];
        if(position == OCPopupViewAnchorPositionTop) {
            [NSLayoutConstraint activateConstraints:@[
                [d_containerView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:0],
                [d_containerView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:0],
                [d_containerView.topAnchor constraintEqualToAnchor:self.topAnchor constant:[d_viewConfig deltaHeight]],
                [d_containerView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:0],
            ]];
        } else {
            [NSLayoutConstraint activateConstraints:@[
                [d_containerView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:0],
                [d_containerView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:0],
                [d_containerView.topAnchor constraintEqualToAnchor:self.topAnchor constant:0],
                [d_containerView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-[d_viewConfig deltaHeight]],
            ]];
        }

        __weak OCPopupBaseView *weakSelf = self;
        d_maskView = [[OCMaskView alloc] initWithTapHandler:^BOOL{
            __strong OCPopupBaseView *strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf uninstall];
            }
            return YES;
        }];
    }
    return self;
}

- (CGPathRef)shapePath {
    return [d_shapeLayer path];
}

- (UIView *)containerView {
    return d_containerView;
}

- (void)install:(CGRect)anchorRect {
    [d_maskView install];

    CGFloat midX = CGRectGetMidX(anchorRect);
    CGFloat x    = [self calculateAnchorX:midX];
    CGPoint anchorPoint = CGPointZero;
    CGFloat y    = 0;
    if(d_anchorPosition == OCPopupViewAnchorPositionTop) {
        anchorPoint = CGPointMake(midX - x, 0);
        y = CGRectGetMaxY(anchorRect) + 1.0;
    } else {
        anchorPoint = CGPointMake(midX - x, CGRectGetMaxY(self.bounds));
        y = CGRectGetMinY(anchorRect) - 1.0 - CGRectGetHeight(self.bounds);
    }

    CGFloat cornerRadius = [d_viewConfig cornerRadius];
    CGFloat deltaHeight  = [d_viewConfig deltaHeight];
    CGFloat sharpWidth   = [d_viewConfig sharpWidth];
    CGFloat sharpRadius  = [d_viewConfig sharpRadius];

    CGPathRef path = [self makeContextShapeWithAnchor:anchorPoint bounds:self.bounds cornerRadius:cornerRadius deltaHeight:deltaHeight sharpWidth:sharpWidth sharpRadius:sharpRadius];
    d_shapeLayer.path = path;

    self.frame = CGRectMake(x, y, self.bounds.size.width, self.bounds.size.height);

    [[UIWindow currentKeyWindow] addSubview:self];
}

- (void)uninstall {
    [self removeFromSuperview];
    [d_maskView removeFromSuperview];
}

#pragma mark - Utils

- (CGFloat)calculateAnchorX:(CGFloat)midX {
    CGFloat screenWidth = [[UIScreen mainScreen] bounds].size.width;
    CGFloat width = self.bounds.size.width;
    if (midX + width * 0.5 > screenWidth - 10) {
        return screenWidth - 10 - width;
    } else if (midX - width * 0.5 < 10) {
        return 10.0;
    } else {
        return midX - width * 0.5;
    }
}

- (CGPathRef)makeContextShapeWithAnchor:(CGPoint)anchor bounds:(CGRect)bounds cornerRadius:(CGFloat)r deltaHeight:(CGFloat)dh sharpWidth:(CGFloat)d sharpRadius:(CGFloat)sr {
    CGMutablePathRef path = CGPathCreateMutable();
    CGFloat w = CGRectGetWidth(bounds);

    if (anchor.y > CGRectGetMidY(bounds)) {
        CGFloat h = CGRectGetHeight(bounds) - dh;
        CGPathMoveToPoint(path, NULL, 0, r);
        CGPathAddArc(path, NULL, r, r, r, M_PI, M_PI_2 * 3, false);
        CGPathAddLineToPoint(path, NULL, w - r, 0);
        CGPathAddArc(path, NULL, w - r, r, r, M_PI_2 * 3, M_PI * 2, false);
        CGPathAddLineToPoint(path, NULL, w, h - r);
        CGPathAddArc(path, NULL, w - r, h - r, r, 0, M_PI_2, false);

        CGPathAddLineToPoint(path, NULL, anchor.x + d, h);
        CGPathAddLineToPoint(path, NULL, anchor.x + sr, h + (dh - sr));
        CGPathAddQuadCurveToPoint(path, NULL, anchor.x, anchor.y, anchor.x - sr, h + (dh - sr));
        CGPathAddLineToPoint(path, NULL, anchor.x - d, h);

        CGPathAddLineToPoint(path, NULL, r, h);
        CGPathAddArc(path, NULL, r, h - r, r, M_PI_2, M_PI, false);
        CGPathCloseSubpath(path);
    } else {
        CGFloat s = dh;
        CGFloat h = CGRectGetHeight(bounds);

        CGPathMoveToPoint(path, NULL, 0, s + r);
        CGPathAddArc(path, NULL, r, s + r, r, M_PI, M_PI_2 * 3, false);

        CGPathAddLineToPoint(path, NULL, anchor.x - d, s);
        CGPathAddLineToPoint(path, NULL, anchor.x - sr, sr);
        CGPathAddQuadCurveToPoint(path, NULL, anchor.x, anchor.y, anchor.x + sr, sr);
        CGPathAddLineToPoint(path, NULL, anchor.x + d, s);

        CGPathAddLineToPoint(path, NULL, w - r, s);
        CGPathAddArc(path, NULL, w - r, s + r, r, M_PI_2 * 3, M_PI * 2, false);
        CGPathAddLineToPoint(path, NULL, w, h - r);
        CGPathAddArc(path, NULL, w - r, h - r, r, 0, M_PI_2, false);
        CGPathAddLineToPoint(path, NULL, r, h);
        CGPathAddArc(path, NULL, r, h - r, r, M_PI_2, M_PI, false);
        CGPathCloseSubpath(path);
    }

    return path;
}

@end
