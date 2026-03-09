/*  RetroArch - A frontend for libretro.
 *  Copyright (C) 2013-2014 - Jason Fetters
 *  Copyright (C) 2011-2017 - Daniel De Matteis
 *
 *  RetroArch is free software: you can redistribute it and/or modify it under the terms
 *  of the GNU General Public License as published by the Free Software Found-
 *  ation, either version 3 of the License, or (at your option) any later version.
 *
 *  RetroArch is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
 *  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 *  PURPOSE.  See the GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along with RetroArch.
 *  If not, see <http://www.gnu.org/licenses/>.
 */

#include <darwin/cocoa_common.h>
#import <UIKit/UIAccessibility.h>

extern bool RAIsVoiceOverRunning(void)
{
   return UIAccessibilityIsVoiceOverRunning();
}

void *cocoa_screen_get_chosen(void)
{
    unsigned monitor_index;
    settings_t *settings = config_get_ptr();
    NSArray *screens     = [RAScreen screens];
    if (!screens || !settings)
        return NULL;

    monitor_index        = settings->uints.video_monitor_index;

    if (monitor_index >= screens.count)
        return (BRIDGE void*)screens;
    return ((BRIDGE void*)[screens objectAtIndex:monitor_index]);
}

bool cocoa_has_focus(void *data)
{
#if defined(HAVE_COCOATOUCH)
    /* if we are running, we are foregrounded */
    return true;
#else
    return [NSApp isActive];
#endif
}

static float get_from_selector(
      Class obj_class, id obj_id, SEL selector, CGFloat *ret)
{
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:
                                [obj_class instanceMethodSignatureForSelector:selector]];
    [invocation setSelector:selector];
    [invocation setTarget:obj_id];
    [invocation invoke];
    [invocation getReturnValue:ret];
    RELEASE(invocation);
    return *ret;
}

/* NOTE: nativeScale only available on iOS 8.0 and up. */
float cocoa_screen_get_native_scale(void)
{
    SEL selector;
    static CGFloat ret   = 0.0f;
    RAScreen *screen     = NULL;

    if (ret != 0.0f)
        return ret;
    if (!(screen = (BRIDGE RAScreen*)cocoa_screen_get_chosen()))
        return 0.0f;

    selector            = NSSelectorFromString(BOXSTRING("nativeScale"));

    if ([screen respondsToSelector:selector])
        ret                 = (float)get_from_selector(
              [screen class], screen, selector, &ret);
    else
    {
        ret                 = 1.0f;
        selector            = NSSelectorFromString(BOXSTRING("scale"));
        if ([screen respondsToSelector:selector])
            ret              = screen.scale;
    }
    return ret;
}

bool cocoa_get_metrics(
      void *data, enum display_metric_types type,
      float *value)
{
   RAScreen *screen              = (BRIDGE RAScreen*)cocoa_screen_get_chosen();
   float   scale                 = cocoa_screen_get_native_scale();
   CGRect  screen_rect           = [screen bounds];
   float   physical_width        = screen_rect.size.width  * scale;
   float   physical_height       = screen_rect.size.height * scale;
   float   dpi                   = 160                     * scale;
   NSInteger idiom_type          = UI_USER_INTERFACE_IDIOM();

   switch (idiom_type)
   {
      case -1: /* UIUserInterfaceIdiomUnspecified */
         /* TODO */
         break;
      case UIUserInterfaceIdiomPad:
         dpi = 132 * scale;
         break;
      case UIUserInterfaceIdiomPhone:
         {
            CGFloat maxSize = fmaxf(physical_width, physical_height);
            /* Larger iPhones: iPhone Plus, X, XR, XS, XS Max, 11, 11 Pro Max */
            if (maxSize >= 2208.0)
               dpi = 81 * scale;
            else
               dpi = 163 * scale;
         }
         break;
      case UIUserInterfaceIdiomTV:
      case UIUserInterfaceIdiomCarPlay:
         /* TODO */
         break;
   }

   switch (type)
   {
      case DISPLAY_METRIC_MM_WIDTH:
         *value = physical_width;
         break;
      case DISPLAY_METRIC_MM_HEIGHT:
         *value = physical_height;
         break;
      case DISPLAY_METRIC_DPI:
         *value = dpi;
         break;
      case DISPLAY_METRIC_NONE:
      default:
         *value = 0;
         return false;
   }

   return true;
}
