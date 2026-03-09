//
//  UIWindow+Key.h
//  
//
//  Created by haharsw on 2022/11/27.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIWindow (Key)
+ (UIWindow *)currentKeyWindow;
+ (UIWindow *)currentTopWindow;
+ (NSArray<UIWindow *> *)currentWindows;
+ (UIWindowScene *)foregroundScene;
@end

NS_ASSUME_NONNULL_END
