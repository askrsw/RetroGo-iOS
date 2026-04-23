//
//  virtual_video_driver.h
//  RetroGo
//
//  Created by haharsw on 2026/4/10.
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
#include <rthreads/rthreads.h>
#include <defines/video_defines.h>
#include <gfx/video_driver.h>
#include <gfx/font_driver.h>

NS_ASSUME_NONNULL_BEGIN

/* A main-thread render-side proxy video driver for a separated logic/render model. */
@interface RAVirtualVideoDriver : NSObject
@property (nonatomic, strong, readonly) CADisplayLink *displayLink;
@end

NS_ASSUME_NONNULL_END
