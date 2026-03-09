//
//  UIColor+Extension.m
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

#import "UIColor+Extension.h"

@implementation UIColor (Extension)

+ (nullable UIColor *)colorWithHexString:(NSString *)hexStr alpha:(CGFloat)alpha {
    NSString *cString = [[hexStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];

    if ([cString hasPrefix:@"0X"]) {
        cString = [cString substringFromIndex:2];
    }

    if ([cString hasPrefix:@"#"]) {
        cString = [cString substringFromIndex:1];
    }

    if (cString.length != 6 && cString.length != 8) {
        return nil;
    }

    unsigned long long rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:cString];
    [scanner scanHexLongLong:&rgbValue];

    if (cString.length == 6) {
        CGFloat r = ((rgbValue & 0xFF0000) >> 16) / 255.0;
        CGFloat g = ((rgbValue & 0xFF00) >> 8) / 255.0;
        CGFloat b = (rgbValue & 0xFF) / 255.0;
        return [UIColor colorWithRed:r green:g blue:b alpha:alpha];
    } else {
        CGFloat r = ((rgbValue & 0xFF000000) >> 24) / 255.0;
        CGFloat g = ((rgbValue & 0xFF0000) >> 16) / 255.0;
        CGFloat b = ((rgbValue & 0xFF00) >> 8) / 255.0;
        CGFloat a = (rgbValue & 0xFF) / 255.0;
        return [UIColor colorWithRed:r green:g blue:b alpha:a];
    }
}

+ (UIColor *)colorWithHex:(UInt32)hex {
    CGFloat a = ((hex >> 24) & 0xFF) / 255.0;
    CGFloat r = ((hex >> 16) & 0xFF) / 255.0;
    CGFloat g = ((hex >> 8) & 0xFF) / 255.0;
    CGFloat b = (hex & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

+ (UIColor *)colorWithHex:(UInt32)hex alpha:(CGFloat)alpha {
    CGFloat r = ((hex >> 16) & 0xFF) / 255.0;
    CGFloat g = ((hex >> 8) & 0xFF) / 255.0;
    CGFloat b = (hex & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:alpha];
}

- (NSString *)hexString {
    CGFloat a, r, g, b;
    if ([self getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"#%02lX%02lX%02lX%02lX",
                (unsigned long)(a * 255),
                (unsigned long)(r * 255),
                (unsigned long)(g * 255),
                (unsigned long)(b * 255)];
    } else {
        CGFloat white;
        if ([self getWhite:&white alpha:&a]) {
            return [NSString stringWithFormat:@"#%02lX%02lX%02lX%02lX",
                    (unsigned long)(a * 255),
                    (unsigned long)(white * 255),
                    (unsigned long)(white * 255),
                    (unsigned long)(white * 255)];
        }
    }
    return @"#00000000"; // 默认返回透明黑色
}

- (UInt32)hexInteger {
    CGFloat a, r, g, b;
    if ([self getRed:&r green:&g blue:&b alpha:&a]) {
        return ((UInt32)(a * 255) << 24) |
               ((UInt32)(r * 255) << 16) |
               ((UInt32)(g * 255) << 8)  |
               ((UInt32)(b * 255));
    } else {
        CGFloat white;
        if ([self getWhite:&white alpha:&a]) {
            return ((UInt32)(a * 255) << 24) |
                   ((UInt32)(white * 255) << 16) |
                   ((UInt32)(white * 255) << 8)  |
                   ((UInt32)(white * 255));
        }
    }
    return 0x00000000; // 默认返回透明黑色
}

@end
