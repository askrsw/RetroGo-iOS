//
//  RetroArchX.m
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

#import "RetroArchX.h"
#import "models/EmuCoreInfoItem.h"
#import "models/EmuInGameMessage.h"
#import "controllers/RetroArchViewController.h"

#import <retroarch_door.h>
#import <utils/verbosity.h>
#import <cocoa_input.h>
#import <UIKit+Extensions.h>
#import <CoreFoundation/CoreFoundation.h>

#define SHOW_CORE_ROM_TYPE_INFO 0

NSString * const RetroArchXReadyNotification = @"retro_arch_x_ready";

@implementation RetroArchX {
    NSArray<UTType *> *d_allSupportedExtensions;
    NSSet<NSString *> *d_allExtensionsSet;

    NSArray<EmuCoreInfoItem *> *d_coreItems;

    CADisplayLink *d_displayLink;
    NSInteger d_pauseCounter;

    BOOL d_initialized;
}

@synthesize initialized = d_initialized;

+ (instancetype)shared {
    static RetroArchX *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if(self != nil) {
        d_pauseCounter = 0;
        d_initialized = NO;

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            double init_start = CFAbsoluteTimeGetCurrent();

            // open log
            verbosity_enable();
            verbosity_set_log_level(0);
            RARCH_LOG("[RetroArchX] init start\n");

            //set language
            unsigned language = frontend_driver_get_user_language();
            msg_hash_set_uint(MSG_HASH_USER_LANGUAGE, language);

            char arguments[]   = "retroarch";
            char       *argv[] = {arguments,   NULL};
            int argc           = 1;
            RARCH_LOG("[RetroArchX] rarch_main begin (t=%.3fs)\n", CFAbsoluteTimeGetCurrent() - init_start);
            rarch_main(argc, argv, NULL, false);
            RARCH_LOG("[RetroArchX] rarch_main end (t=%.3fs)\n", CFAbsoluteTimeGetCurrent() - init_start);

            RARCH_LOG("[RetroArchX] findAllSupportedExtensions begin (t=%.3fs)\n", CFAbsoluteTimeGetCurrent() - init_start);
            [self findAllSupportedExtensions];
            RARCH_LOG("[RetroArchX] findAllSupportedExtensions end (t=%.3fs)\n", CFAbsoluteTimeGetCurrent() - init_start);

            d_initialized = YES;
            RARCH_LOG("[RetroArchX] init done (t=%.3fs)\n", CFAbsoluteTimeGetCurrent() - init_start);

            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:RetroArchXReadyNotification object:self];
                RARCH_LOG("[RetroArchX] posted ready notification\n");
            });
        });
    }
    return self;
}

- (void)dealloc {
    [d_displayLink invalidate];
    d_displayLink = nil;

    main_exit(NULL);
}

- (NSArray<UTType *> *)allSupportedExtensions {
    return d_allSupportedExtensions;
}

- (NSSet<NSString *> *)allExtensionsSet {
    return d_allExtensionsSet;
}

- (NSArray<EmuCoreInfoItem *> *)allCores {
    if(d_coreItems == nil) {
        d_coreItems = [EmuCoreInfoItem findAllCores];
    }
    return d_coreItems;
}

- (nullable EmuCoreInfoItem *)currentCoreItem {
    const char * cstr = path_get(RARCH_PATH_CORE);
    if(cstr != nil && strlen(cstr) > 0) {
        NSString *corePath = @(cstr);
        for(EmuCoreInfoItem *item in  d_coreItems) {
            if([corePath isEqualToString:item.corePath]) {
                return item;
            }
        }
    }
    return nil;
}

- (NSArray<EmuCoreInfoItem *> *)supportedCoresForRom:(NSString *)romPath {
    const char *filePath = romPath.UTF8String;
    core_info_list_t *list = NULL;
    const core_info_t *info = NULL;
    size_t supported = 0;

    core_info_get_list(&list);
    core_info_list_get_supported_cores(list, filePath, &info, &supported);

    NSMutableArray *array = [NSMutableArray array];
    for(int i = 0; i < supported; i++) {
        NSString *corePath = @(info[i].path);
        NSUInteger index = [self.allCores indexOfObjectPassingTest:^BOOL(EmuCoreInfoItem * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            return [obj.corePath isEqualToString:corePath];
        }];
        if(index != NSNotFound) {
            [array addObject:self.allCores[index]];
        }
    }

    return [array copy];
}

- (CADisplayLink *)displayLink {
    return d_displayLink;
}

- (BOOL)isCurrentCoreSupportsSavestate {
    if(self.currentCoreItem != nil) {
        return core_info_current_supports_savestate();
    } else {
        return NO;
    }
}

- (nullable NSString *)getCurrentRomPath {
    if(self.currentCoreItem == nil) {
        return nil;
    }

    const char *romPath = path_get(RARCH_PATH_CONTENT);
    if(string_is_empty(romPath)) {
        return nil;
    }

    return @(romPath);
}

- (BOOL)canRunOnThisDevice {
#if TARGET_OS_SIMULATOR
#if CORE_IN_FRAMEWORKS
    return YES;
#else
    return NO;
#endif
#else
    return YES;
#endif
}

#pragma mark - Core Control

- (void)start:(nullable NSString *)romPath core:(EmuCoreInfoItem *)core completion:(nullable void (^)(BOOL success))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        content_ctx_info_t content_info;
        NSString *corePath = core.corePath;
        NSString *finalRomPath = [core checkIsMameCore:romPath];

        content_info.argc         = 0;
        content_info.argv         = NULL;
        content_info.args         = NULL;
        content_info.environ_get  = NULL;
        content_info.init_drivers = true;

        BOOL load_ret = NO;

        if(finalRomPath != nil) {
            // 这个函数内部包含了 dlopen 和大量的 IO 操作
            load_ret = task_push_load_content_with_new_core_from_menu(corePath.UTF8String, finalRomPath.UTF8String, &content_info, CORE_TYPE_PLAIN, NULL, NULL);
        } else {
            path_clear(RARCH_PATH_CONTENT);
            path_clear(RARCH_PATH_BASENAME);
            path_set(RARCH_PATH_CORE, corePath.UTF8String);
            command_event(CMD_EVENT_LOAD_CORE, NULL);
            runloop_set_current_core_type(CORE_TYPE_PLAIN, true);
            load_ret = task_push_start_current_core(&content_info);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if(load_ret) {
                // 开启音频延时逻辑
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    command_event(CMD_EVENT_AUDIO_START, NULL);
                });

                // 开启主线程渲染循环
                if (!self->d_displayLink) {
                    self->d_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(step:)];
                    if (@available(iOS 15.0, tvOS 15.0, *)) {
                        [self->d_displayLink setPreferredFrameRateRange:CAFrameRateRangeDefault];
                    }
                    [self->d_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
                }
            }

            if (completion) {
                completion(load_ret);
            }
        });
    });
}

- (BOOL)close {
    [d_displayLink invalidate];
    d_displayLink = nil;

    EmuCoreInfoItem *runningCore = [self currentCoreItem];

    // @ref: action_ok_close_content in menu_cbs_ok.c
    BOOL ret = command_event(CMD_EVENT_UNLOAD_CORE, NULL);
    apple_platform = nil;

    [runningCore cleanupMameSession];

    return ret;
}

- (BOOL)pause {
    if(self.currentCoreItem != nil) {
        if(d_pauseCounter++ == 0) {
            audio_driver_stop();
            BOOL ret = command_event(CMD_EVENT_PAUSE, NULL);
            [d_displayLink removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
            return ret;
        } else {
            return YES;
        }
    } else {
        return NO;
    }
}

- (BOOL)resume {
    if(self.currentCoreItem != nil) {
        if(--d_pauseCounter == 0) {
            audio_driver_start(false);
            [d_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
            return command_event(CMD_EVENT_UNPAUSE, NULL);
        } else {
            return YES;
        }
    } else {
        return NO;
    }
}

- (BOOL)restart {
    if(self.currentCoreItem != nil) {
        return command_event(CMD_EVENT_RESET, NULL);
    } else {
        return NO;
    }
}

-(void)step:(CADisplayLink*)target {
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
        return;
    }

    int ret = runloop_iterate();

    if (ret == -1) {
        main_exit(NULL);
        exit(0);
    }

    task_queue_check();

    uint32_t runloop_flags = runloop_get_flags();
    if (!(runloop_flags & RUNLOOP_FLAG_IDLE)) {
        CFRunLoopWakeUp(CFRunLoopGetMain());
    }
}

- (BOOL)saveStateTo:(NSString *)folder imageFolder:(nullable NSString *)imageFolder name:(NSString *)name {
    if(self.currentCoreItem == nil) {
        return NO;
    }

    video_driver_state_t *video_st = video_state_get_ptr();
    settings_t *settings           = config_get_ptr();
    bool frame_time_counter_reset_after_save_state = settings->bools.frame_time_counter_reset_after_save_state;

    [self pause];

    NSString *path = [folder stringByAppendingPathComponent:name];
    NSString *statePath = [path stringByAppendingPathExtension:@"state"];
    BOOL ret = content_direct_save_state(statePath.UTF8String);
    if (frame_time_counter_reset_after_save_state)
       video_st->frame_time_count = 0;

    NSString *pngPath;
    if(imageFolder == nil) {
        pngPath = [path stringByAppendingPathExtension:@"png"];
    } else {
        pngPath = [[imageFolder stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"png"];
    }

    [self saveScreenshotTo:pngPath];

    [self resume];

    return ret;
}

- (BOOL)loadStateFrom:(NSString *)path {
    if(self.currentCoreItem == nil) {
        return NO;
    }

    [self pause];

    bool ret = content_load_state(path.UTF8String, false, false);
    if(ret) {
        command_post_state_loaded();
    }

    [self resume];

    return ret;
}

bool get_screenshot_data(uint8_t **png_data, uint64_t *png_data_size);

- (BOOL)saveScreenshotTo:(NSString *)path {
    if(self.currentCoreItem == nil) {
        return NO;
    }

    [self pause];

    uint8_t *png_data = NULL;
    uint64_t png_data_size = 0;

    BOOL ret = get_screenshot_data(&png_data, &png_data_size);
    if(png_data && png_data_size > 0) {
        const char *raw_path = [path fileSystemRepresentation];
        char log_raw_path[PATH_MAX_LENGTH] = { 0 };
        FILE *fp = fopen(raw_path, "wb");
        if (fp) {
            size_t written = fwrite(png_data, 1, png_data_size, fp);
            fclose(fp);

            NSString *message = [NSString stringWithFormat:@"截图保存在 %s。", shorten_path_for_log(raw_path, log_raw_path, sizeof(log_raw_path))];
            EmuInGameMessage *inGameMessage = [[EmuInGameMessage alloc] initWithMessage:message title:nil type:EmuInGameMessageInfo duration:120 priority:1];
            [(id)apple_platform showInGameMessage:inGameMessage];
        }

        free(png_data);
    }

    [self resume];

    return ret;
}

#pragma mark - RetroArch Utils

- (void)handleTouchEvent:(nullable NSSet<UITouch *> *)touches {
    NSArray *touchArray = touches.allObjects;
    if(touchArray.count < 0) {
        return;
    }

#if !TARGET_OS_TV
    unsigned i;
    cocoa_input_data_t *apple = (cocoa_input_data_t*)
    input_state_get_ptr()->current_data;
    float scale               = cocoa_screen_get_native_scale();

    if (!apple)
        return;

    apple->touch_count = 0;
    
    for (i = 0; i < touches.count && (apple->touch_count < MAX_TOUCHES); i++) {
        UITouch      *touch = [touchArray objectAtIndex:i];
        CGPoint       coord = [touch locationInView:[touch view]];
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) {
            apple->touches[apple->touch_count   ].screen_x = coord.x * scale;
            apple->touches[apple->touch_count ++].screen_y = coord.y * scale;
        }
    }
#endif // !TARGET_OS_TV
}

#pragma mark - utils

- (void)findAllSupportedExtensions {
    core_info_list_t *list = nil;
    core_info_get_list(&list);
    if(list == nil) {
        return;
    }

    NSMutableSet *set = [NSMutableSet set];

#if SHOW_CORE_ROM_TYPE_INFO
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSMutableArray *dynamicTypes = [NSMutableArray array];
#endif

    for(size_t i = 0; i < list->info_count; i++) {
        core_info_t *info = &list->list[i];
        struct string_list *extensions = info->supported_extensions_list;
        if(extensions == nil) {
            continue;
        }

#if SHOW_CORE_ROM_TYPE_INFO
        dict[@(info->core_name)] = [NSMutableArray array];
#endif

        for(int j = 0; j < extensions->size; j++) {
            char *value = extensions->elems[j].data;
            NSString *strValue = @(value).lowercaseString;
            [set addObject:strValue];

#if SHOW_CORE_ROM_TYPE_INFO
            [dict[@(info->core_name)] addObject:@(value)];
#endif
        }
    }

    NSMutableArray *array = [NSMutableArray array];
    for(NSString *ext in set) {
        UTType *type = [UTType typeWithTag:ext tagClass:UTTagClassFilenameExtension conformingToType:nil];
        if(type != nil) {
            [array addObject:type];
        }
#if SHOW_CORE_ROM_TYPE_INFO
        if(type.isDynamic) {
            [dynamicTypes addObject:ext];
        }
#endif
    }

#if SHOW_CORE_ROM_TYPE_INFO
    for(NSString *key in dict) {
        NSArray *value = dict[key];
        NSString *string = [value componentsJoinedByString:@","];
        NSLog(@"\t%@: %@", key, string);
    }
    NSLog(@"Dynamic Types: %@", [dynamicTypes componentsJoinedByString:@","]);
#endif // SHOW_CORE_ROM_TYPE_INFO

    d_allExtensionsSet       = [set copy];
    d_allSupportedExtensions = [array copy];
}

@end
