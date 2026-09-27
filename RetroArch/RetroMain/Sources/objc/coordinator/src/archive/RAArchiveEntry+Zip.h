//
//  RAArchiveEntry+Zip.h
//  RetroGo
//
//  Created by haharsw on 2026/9/27.
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

#import "RAArchiveReader.h"

NS_ASSUME_NONNULL_BEGIN

/// Raw location of a zip entry, recorded while listing so RAZipWriter can copy the
/// compressed data without inflating and deflating it again. Internal to the archive
/// layer; not part of the public header.
@interface RAArchiveEntry ()
/// YES when the fields below describe a zip entry.
@property (nonatomic, assign) BOOL hasZipLocation;
/// Offset of the entry's local file header.
@property (nonatomic, assign) uint64_t zipHeaderOffset;
@property (nonatomic, assign) uint32_t zipCompressedSize;
/// 0 = stored, 8 = deflate.
@property (nonatomic, assign) uint16_t zipMethod;
@end

NS_ASSUME_NONNULL_END
