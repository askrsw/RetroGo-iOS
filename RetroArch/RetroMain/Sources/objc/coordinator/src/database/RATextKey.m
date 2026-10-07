//
//  RATextKey.m
//  RetroGo
//
//  Created by haharsw on 2026/10/7.
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

#import "RATextKey.h"

#include <CommonCrypto/CommonDigest.h>

@implementation RATextKey

+ (int64_t)keyForText:(NSString *)text {
    NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
    if (!utf8) {
        return 0;
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(utf8.length > 0 ? utf8.bytes : "", (CC_LONG)utf8.length, digest);
    uint64_t value = 0;
    for (int i = 0; i < 8; i++) {
        value = (value << 8) | digest[i];
    }
    return (int64_t)value;
}

@end
