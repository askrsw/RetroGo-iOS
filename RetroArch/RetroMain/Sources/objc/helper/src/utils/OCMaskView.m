//
//  OCMaskView.m
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

#import "OCMaskView.h"

#import <UIKit+Extensions.h>

@implementation OCMaskView {
    OCMaskViewTapHandler _Nullable d_tapHandler;
}

- (instancetype)initWithTapHandler:(OCMaskViewTapHandler _Nullable)tapHander {
    CGSize size = [[UIScreen mainScreen] bounds].size;
    self = [super initWithFrame:CGRectMake(0, 0, size.width, size.height)];
    if(self != nil) {
        d_tapHandler = tapHander;

        _bkColor = [UIColor colorWithHex:0x000000 alpha:0.05];
        self.backgroundColor = _bkColor;

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapAction:)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)setBkColor:(UIColor *)bkColor {
    _bkColor = bkColor;
    self.backgroundColor = bkColor;
}

- (void)tapAction:(UITapGestureRecognizer *)tap {
    if(d_tapHandler != nil && d_tapHandler()) {
        [self removeFromSuperview];
    }
}

- (void)install {
    UIWindow *window = [UIWindow currentKeyWindow];
    if(window == nil) {
        return;
    }

    self.translatesAutoresizingMaskIntoConstraints = NO;
    [window addSubview:self];
    [NSLayoutConstraint activateConstraints:@[
        [self.leadingAnchor constraintEqualToAnchor:window.leadingAnchor],
        [self.topAnchor constraintEqualToAnchor:window.topAnchor],
        [self.rightAnchor constraintEqualToAnchor:window.rightAnchor],
        [self.bottomAnchor constraintEqualToAnchor:window.bottomAnchor]
    ]];
}

@end
