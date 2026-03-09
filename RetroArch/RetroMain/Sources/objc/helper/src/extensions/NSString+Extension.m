//
//  NSString+Extension.m
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

#import "NSString+Extension.h"

@implementation NSString (Extension)

- (CGSize)renderedSizeWithFont:(UIFont *)font constrainedToSize:(CGSize)constrainedSize {
    NSDictionary *attributes = @{NSFontAttributeName: font};
    CGRect boundingRect = [self boundingRectWithSize:constrainedSize options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:attributes context:nil];
    return boundingRect.size;
}

+ (NSString *)randomString:(NSInteger)count caseInsensitive:(BOOL)caseInsensitive {
    if (count <= 0) {
        return @"";
    }

    // Define the character sets
    NSString *letters = @"abcdefghijklmnopqrstuvwxyz";
    NSString *numbers = @"0123456789";
    NSString *allCharacters = [letters stringByAppendingString:numbers];

        // If case insensitive, use only lowercase letters
    if (!caseInsensitive) {
        letters = [letters stringByAppendingString:[letters uppercaseString]];
        allCharacters = [letters stringByAppendingString:numbers];
    }

    // Ensure the first character is a letter
    NSMutableString *result = [NSMutableString stringWithCapacity:count];
    [result appendFormat:@"%C", [letters characterAtIndex:arc4random_uniform((uint32_t)[letters length])]];

    // Generate the remaining characters
    for (NSInteger i = 1; i < count; i++) {
        [result appendFormat:@"%C", [allCharacters characterAtIndex:arc4random_uniform((uint32_t)[allCharacters length])]];
    }

    return result;
}

@end
