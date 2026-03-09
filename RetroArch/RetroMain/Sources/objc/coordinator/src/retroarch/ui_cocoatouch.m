/* RetroArch - A frontend for libretro.
 *  Copyright (C) 2011-2016 - Daniel De Matteis
 *
 * RetroArch is free software: you can redistribute it and/or modify it under the terms
 * of the GNU General Public License as published by the Free Software Found-
 * ation, either version 3 of the License, or (at your option) any later version.
 *
 * RetroArch is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
 * without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 * PURPOSE. See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with RetroArch.
 * If not, see <http://www.gnu.org/licenses/>.
 */

#import <darwin/cocoa_common.h>
#import <gfx/metal_common.h>

#if defined(HAVE_COCOA_METAL) || defined(HAVE_COCOATOUCH)
id<ApplePlatform> apple_platform;
#else
static id apple_platform;
#endif

void get_ios_version(int *major, int *minor) {
   static int savedMajor, savedMinor;
   static dispatch_once_t onceToken;

   dispatch_once(&onceToken, ^ {
         NSArray *decomposed_os_version = [[UIDevice currentDevice].systemVersion componentsSeparatedByString:@"."];
         if (decomposed_os_version.count > 0)
            savedMajor = (int)[decomposed_os_version[0] integerValue];
         if (decomposed_os_version.count > 1)
            savedMinor = (int)[decomposed_os_version[1] integerValue];
      });
   if (major) *major = savedMajor;
   if (minor) *minor = savedMinor;
}

bool ios_running_on_ipad(void) {
   return (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
}

#ifdef HAVE_COCOA_METAL
@implementation MetalLayerView

+ (Class)layerClass {
    return [CAMetalLayer class];
}

- (instancetype)init {
    self = [super init];
    if (self)
        [self setupMetalLayer];
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self)
        [self setupMetalLayer];
    return self;
}

- (CAMetalLayer *)metalLayer {
    return (CAMetalLayer *)self.layer;
}

- (void)setupMetalLayer {
    self.metalLayer.device = MTLCreateSystemDefaultDevice();
    self.metalLayer.contentsScale = cocoa_screen_get_native_scale();
    self.metalLayer.opaque = YES;
}

@end
#endif // HAVE_COCOA_METAL

ui_companion_driver_t ui_companion_cocoatouch = {
   NULL, /* init */
   NULL, /* deinit */
   NULL, /* toggle */
   NULL, /* event_command */
   NULL, /* notify_refresh */
   NULL, /* msg_queue_push */
   NULL, /* render_messagebox */
   NULL, /* get_main_window */
   NULL, /* log_msg */
   NULL, /* is_active */
   NULL, /* get_app_icons */
   NULL, /* set_app_icon */
   NULL, /* get_app_icon_texture */
   NULL, /* browser_window */
   NULL, /* msg_window */
   NULL, /* window */
   NULL, /* application */
   "cocoatouch",
};
