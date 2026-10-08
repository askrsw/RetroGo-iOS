//
//  RATextKey.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Stable key of an English source text, used to look up its translation in
/// a language pack. key = first 8 bytes of SHA-256(UTF-8(text)), big-endian,
/// as a signed 64-bit integer (an SQLite INTEGER). The text is hashed exactly
/// as given: no trimming, case folding or Unicode normalization. The database
/// build scripts (Tools/cheat_db/scripts/text_key.py) use the same algorithm;
/// both are checked against one set of test vectors.
@interface RATextKey : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// Returns 0 for text that cannot be encoded as UTF-8 (lone surrogates).
+ (int64_t)keyForText:(NSString *)text NS_SWIFT_NAME(key(for:));

@end

NS_ASSUME_NONNULL_END
