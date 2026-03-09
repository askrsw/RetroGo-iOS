//
//  UIWindow+Key.m
//  
//
//  Created by haharsw on 2022/11/27.
//

#import "UIWindow+Key.h"

@implementation UIWindow (Key)

+ (UIWindow *)currentKeyWindow {
    if (@available(iOS 13.0, *)) {
        for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if(windowScene.activationState == UISceneActivationStateForegroundActive) {
                return windowScene.windows.firstObject;
            }
            return UIApplication.sharedApplication.windows.firstObject;
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return UIApplication.sharedApplication.keyWindow;
#pragma clang diagnostic pop
    }
}

+ (UIWindow *)currentTopWindow {
    if (@available(iOS 13.0, *)) {
        for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if(windowScene.activationState == UISceneActivationStateForegroundActive) {
                return windowScene.windows.lastObject;
            }
            return UIApplication.sharedApplication.windows.lastObject;
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return UIApplication.sharedApplication.windows.lastObject;
#pragma clang diagnostic pop
    }
}

+ (NSArray<UIWindow *> *)currentWindows {
    if (@available(iOS 13.0, *)) {
        for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if(windowScene.activationState == UISceneActivationStateForegroundActive) {
                return windowScene.windows;
            }
            return UIApplication.sharedApplication.windows;
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return UIApplication.sharedApplication.windows;
#pragma clang diagnostic pop
    }
}

+ (UIWindowScene *)foregroundScene {
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes;
        for(UIScene *scene in scenes) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if(windowScene.activationState == UISceneActivationStateForegroundActive) {
                return windowScene;
            }
            return (UIWindowScene *)[scenes anyObject];
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return nil;
#pragma clang diagnostic pop
    }
}
@end
