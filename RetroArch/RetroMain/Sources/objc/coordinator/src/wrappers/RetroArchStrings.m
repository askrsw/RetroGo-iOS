//
//  RetroArchStrings.m
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

#import "RetroArchStrings.h"
#import <intl/msg_hash.h>

@implementation RetroArchStrings

+ (NSString *)stringFromRetroArch:(RetroArchString)v {
    enum msg_hash_enums k = v;
    const char *s = msg_hash_to_str(k);
    return @(s);
}

+ (NSString *)usStringFromRetroArch:(RetroArchString)v {
    enum msg_hash_enums k = v;
    const char *s = msg_hash_to_str_us(k);
    return @(s);
}

@end
