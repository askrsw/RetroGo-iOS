//
//  RetroArchX+DiskControl.h
//  RetroGo
//
//  Created by haharsw on 2026/5/31.
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

#import "RetroArchX.h"

NS_ASSUME_NONNULL_BEGIN

@interface RetroArchX (DiskControl)

// YES when the running core implements the libretro disk control interface
// (set_eject_state / set_image_index / get_num_images / get_image_index).
@property(nonatomic, assign, readonly) BOOL diskControlAvailable;

// Total number of disk images registered by the core for the current content.
// For an m3u-based game this is the number of entries listed in the m3u.
// Returns 0 when disk control is unavailable.
@property(nonatomic, assign, readonly) NSUInteger diskImageCount;

// Currently selected disk image index (zero based).
@property(nonatomic, assign, readonly) NSUInteger currentDiskImageIndex;

// Core-provided human label for the disk at `index`, or nil when the core
// does not implement get_image_label or the label is empty.
- (nullable NSString *)labelForDiskImageAtIndex:(NSUInteger)index;

// Switches the active disk image by performing the eject -> set_index -> insert
// sequence required by the libretro disk control protocol.
//
// Must be called while the game loop is paused. The in-game settings view
// (GameConfigViewController) already pauses the loop before presenting, so
// callers from that flow are safe. Calling this while retro_run is executing on
// the game thread races the core's set_image_index handler.
- (BOOL)switchToDiskImageAtIndex:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
