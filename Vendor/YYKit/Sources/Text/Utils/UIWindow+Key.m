//
//  UIWindow+Key.m
//  
//
//  Created by haharsw on 2022/11/27.
//

#import "UIWindow+Key.h"

@implementation UIWindow (Key)

+ (nullable UIWindow *)currentKeyWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }

        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }
    }
    return nil;
}

+ (nullable UIWindow *)currentTopWindow {
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if(windowScene.activationState == UISceneActivationStateForegroundActive) {
            return windowScene.windows.lastObject;
        }
    }
    return nil;
}

+ (nullable NSArray<UIWindow *> *)currentWindows {
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if(windowScene.activationState == UISceneActivationStateForegroundActive) {
            return windowScene.windows;
        }
    }
    return nil;
}

+ (nullable UIWindowScene *)foregroundScene {
    NSSet<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes;
    for(UIScene *scene in scenes) {
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if(windowScene.activationState == UISceneActivationStateForegroundActive) {
            return windowScene;
        }
    }
    return nil;
}
@end
