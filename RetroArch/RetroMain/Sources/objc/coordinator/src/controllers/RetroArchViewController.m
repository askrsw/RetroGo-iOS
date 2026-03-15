//
//  RetroArchViewController.m
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

#import "RetroArchViewController.h"
#import "../RetroArchX.h"
#import <cocoa_input.h>
#import <gfx/metal_common.h>
#import <retroarch_door.h>

#ifdef HAVE_MFI
#import <GameController/GCMouse.h>
#import <GameController/GCMouseInput.h>
#import <GameController/GCControllerButtonInput.h>
#endif

@implementation RetroArchViewController {
    UIView *d_renderView;
    apple_view_type_t d_vt;
    NSArray<NSLayoutConstraint *> *d_viewConstraints;
    CGSize d_layoutViewSize;

    BOOL d_shouldLockCurrentInterfaceOrientation;
    UIInterfaceOrientation d_lockInterfaceOrientation;
}

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if(self != nil) {
        d_shouldLockCurrentInterfaceOrientation = NO;
        d_lockInterfaceOrientation = UIInterfaceOrientationUnknown;

        apple_platform = self;

        d_layoutViewSize = CGSizeZero;
    }
    return self;
}

- (void)dealloc {
    apple_platform = nil;
}

-(BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (@available(iOS 16, *)) {
        if (self.shouldLockCurrentInterfaceOrientation)
            return 1 << self.lockInterfaceOrientation;
        return UIInterfaceOrientationMaskAll;
    }
    return UIInterfaceOrientationMaskAll;
}

-(BOOL)shouldAutorotate {
    if (self.shouldLockCurrentInterfaceOrientation)
        return NO;
    return YES;
}

- (BOOL)shouldAutorotateToInterfaceOrientation: (UIInterfaceOrientation)interfaceOrientation {
    return YES;
}

-(BOOL) prefersPointerLocked API_AVAILABLE(ios(14.0)) {
    cocoa_input_data_t *apple = (cocoa_input_data_t*) input_state_get_ptr()->current_data;
    if (!apple)
        return NO;
    return apple->mouse_grabbed;
}

- (void)loadView {
    [super loadView];

    self.hudView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.hudView];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [NSLayoutConstraint activateConstraints:@[
        [self.hudView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.hudView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [self.hudView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [self.hudView.heightAnchor constraintEqualToConstant:44]
    ]];

#ifdef HAVE_MFI
    [self initMouseHandler];
#endif // HAVE_MFI
}

- (void)viewDidAppear:(BOOL)animated {
    [self setNeedsUpdateOfHomeIndicatorAutoHidden];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    if(!CGSizeEqualToSize(size, d_layoutViewSize)) {
        d_layoutViewSize = size;
        [self updateMyViewConstraints];
    }
}

#pragma mark - Interface

- (UIView *)hudView {
    return nil;
}

- (void)showInGameMessage:(EmuInGameMessage *)message { }

#pragma mark - Utils

#ifdef HAVE_MFI
- (void)initMouseHandler {
    if (@available(macOS 11, iOS 14, tvOS 14, *)) {
        [[NSNotificationCenter defaultCenter] addObserverForName:GCMouseDidConnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            GCMouse *mouse = note.object;
            mouse.mouseInput.mouseMovedHandler = ^(GCMouseInput * _Nonnull mouse, float delta_x, float delta_y) {
                cocoa_input_data_t *apple = (cocoa_input_data_t*) input_state_get_ptr()->current_data;
                if (!apple)
                    return;
                apple->window_pos_x      += (int16_t)delta_x;
                apple->window_pos_y      -= (int16_t)delta_y;
            };
            mouse.mouseInput.leftButton.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
                cocoa_input_data_t *apple = (cocoa_input_data_t*) input_state_get_ptr()->current_data;
                if (!apple)
                    return;
                if (pressed)
                    apple->mouse_buttons |= (1 << 0);
                else
                    apple->mouse_buttons &= ~(1 << 0);
            };
            mouse.mouseInput.rightButton.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
                cocoa_input_data_t *apple = (cocoa_input_data_t*) input_state_get_ptr()->current_data;
                if (!apple)
                    return;
                if (pressed)
                    apple->mouse_buttons |= (1 << 1);
                else
                    apple->mouse_buttons &= ~(1 << 1);
            };
        }];
    }
}
#endif // HAVE_MFI

- (void)updateMyViewConstraints {
    [NSLayoutConstraint deactivateConstraints:d_viewConstraints];

    if(d_layoutViewSize.width < d_layoutViewSize.height) {
        d_viewConstraints = @[
            [d_renderView.topAnchor constraintEqualToAnchor:self.hudView.bottomAnchor],
            [d_renderView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
            [d_renderView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
            [d_renderView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
        ];
    } else {
        d_viewConstraints = @[
            [d_renderView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [d_renderView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
            [d_renderView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
            [d_renderView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
        ];
    }

    [NSLayoutConstraint activateConstraints:d_viewConstraints];
    [d_renderView layoutIfNeeded];
}

#pragma mark - ApplePlatform

-(id)renderView { return d_renderView; }

-(CADisplayLink *)displayLink {
    return [[RetroArchX shared] displayLink];
}

-(BOOL)shouldLockCurrentInterfaceOrientation {
    return d_shouldLockCurrentInterfaceOrientation;
}

-(void)setShouldLockCurrentInterfaceOrientation:(BOOL)v {
    d_shouldLockCurrentInterfaceOrientation = v;
}

-(UIInterfaceOrientation)lockInterfaceOrientation {
    return d_lockInterfaceOrientation;
}

-(void)setLockInterfaceOrientation:(UIInterfaceOrientation)v {
    d_lockInterfaceOrientation = v;
}

-(CGRect)viewBounds {
    return self.view.bounds;
}

-(bool)hasFocus {
    return [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive;
}

- (apple_view_type_t)viewType { return d_vt; }

#ifdef HAVE_COCOATOUCH
void *glkitview_init(void);
#endif

- (void)setViewType:(apple_view_type_t)vt {
    if (vt == d_vt)
        return;

    d_vt = vt;
    if (d_renderView != nil) {
        [d_renderView removeFromSuperview];
        d_renderView = nil;
    }

    switch (vt) {
#ifdef HAVE_COCOA_METAL
        case APPLE_VIEW_TYPE_VULKAN:
            d_renderView = [MetalLayerView new];
            d_renderView.multipleTouchEnabled = YES;
            break;
        case APPLE_VIEW_TYPE_METAL: {
            MetalView *v = [MetalView new];
            v.paused                = YES;
            v.enableSetNeedsDisplay = NO;
            v.multipleTouchEnabled  = YES;
            d_renderView = v;
        }
            break;
#endif // HAVE_COCOA_METAL
        case APPLE_VIEW_TYPE_OPENGL_ES:
            d_renderView = (BRIDGE GLKView*)glkitview_init();
            break;

        case APPLE_VIEW_TYPE_NONE:
        default:
            return;
    }

    [d_renderView addInteraction:[[UIPointerInteraction alloc] initWithDelegate:self]];
    d_renderView.userInteractionEnabled = YES;
    d_renderView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view insertSubview:d_renderView belowSubview:self.hudView];

    d_layoutViewSize = self.view.frame.size;
    [self updateMyViewConstraints];
}

- (void)setVideoMode:(gfx_ctx_mode_t)mode {
#ifdef HAVE_COCOA_METAL
    MetalView *metalView = (MetalView*) d_renderView;
    CGFloat scale        = [[UIScreen mainScreen] scale];
    CGFloat width        = d_renderView.bounds.size.width * scale;
    CGFloat height       = d_renderView.bounds.size.height * scale;
    [metalView setDrawableSize:CGSizeMake(width, height)];
#endif // HAVE_COCOA_METAL
}

- (void)setCursorVisible:(bool)v { /* no-op for iOS */ }
- (bool)setDisableDisplaySleep:(bool)disable {
    return NO;
}

#pragma mark - UIPointerInteractionDelegate

- (UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction styleForRegion:(UIPointerRegion *)region API_AVAILABLE(ios(13.4)) {
    cocoa_input_data_t *apple = (cocoa_input_data_t*) input_state_get_ptr()->current_data;
    if (!apple)
        return nil;
    if (apple->mouse_grabbed)
        return [UIPointerStyle hiddenPointerStyle];
    return nil;
}

- (UIPointerRegion *)pointerInteraction:(UIPointerInteraction *)interaction regionForRequest:(UIPointerRegionRequest *)request defaultRegion:(UIPointerRegion *)defaultRegion API_AVAILABLE(ios(13.4)) {
    cocoa_input_data_t *apple = (cocoa_input_data_t*) input_state_get_ptr()->current_data;
    if (!apple || apple->mouse_grabbed)
        return nil;
    CGPoint location = [apple_platform.renderView convertPoint:[request location] fromView:nil];
    apple->touches[0].screen_x = (int16_t)(location.x * [[UIScreen mainScreen] scale]);
    apple->touches[0].screen_y = (int16_t)(location.y * [[UIScreen mainScreen] scale]);
    apple->window_pos_x = (int16_t)(location.x * [[UIScreen mainScreen] scale]);
    apple->window_pos_y = (int16_t)(location.y * [[UIScreen mainScreen] scale]);
    return [UIPointerRegion regionWithRect:[apple_platform.renderView bounds] identifier:@"game view"];
}

@end
