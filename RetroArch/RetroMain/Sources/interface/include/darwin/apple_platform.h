#ifndef COCOA_APPLE_PLATFORM_H
#define COCOA_APPLE_PLATFORM_H

#include <gfx/video_driver.h>

#if __OBJC__
#import <UIKit/UIKit.h>
#endif

extern bool RAIsVoiceOverRunning(void);
extern bool ios_running_on_ipad(void);

#ifdef __OBJC__

typedef enum apple_view_type
{
    APPLE_VIEW_TYPE_NONE = 0,
    APPLE_VIEW_TYPE_OPENGL_ES,
    APPLE_VIEW_TYPE_OPENGL,
    APPLE_VIEW_TYPE_VULKAN,
    APPLE_VIEW_TYPE_METAL
} apple_view_type_t;

#if defined(HAVE_COCOA_METAL) || defined(HAVE_COCOATOUCH)
@protocol ApplePlatform

/*! @brief renderView returns the current render view based on the viewType */
@property(nonatomic, readonly, strong) UIView *renderView;

@property(nonatomic, strong, readonly) CADisplayLink *displayLink;
@property(nonatomic, assign) BOOL shouldLockCurrentInterfaceOrientation;
@property(nonatomic, assign) UIInterfaceOrientation lockInterfaceOrientation;
@property(nonatomic, assign, readonly) CGRect viewBounds;

/*! @brief isActive returns true if the application has focus */
@property(nonatomic, readonly, assign) bool hasFocus;
@property(nonatomic, assign) apple_view_type_t viewType;

/*! @brief setVideoMode adjusts the video display to the specified mode */
- (void)setVideoMode:(gfx_ctx_mode_t)mode;
/*! @brief setCursorVisible specifies whether the cursor is visible */
- (void)setCursorVisible:(bool)v;
/*! @brief controls whether the screen saver should be disabled and
 * the displays should not sleep.
 */
- (bool)setDisableDisplaySleep:(bool)disable;

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 160000
- (void)setNeedsUpdateOfSupportedInterfaceOrientations;
#endif
- (void)setNeedsUpdateOfPrefersPointerLocked;
@end

#endif // defined(HAVE_COCOA_METAL) || defined(HAVE_COCOATOUCH)

#if defined(HAVE_COCOA_METAL) || defined(HAVE_COCOATOUCH)
extern id<ApplePlatform> apple_platform;
#else
extern id apple_platform;
#endif

#if defined(HAVE_COCOATOUCH) && defined(HAVE_COCOA_METAL)
@interface MetalLayerView : UIView
@property (nonatomic, readonly) CAMetalLayer *metalLayer;
@end
#endif

#endif // __OBJC__

#endif // !COCOA_APPLE_PLATFORM_H
