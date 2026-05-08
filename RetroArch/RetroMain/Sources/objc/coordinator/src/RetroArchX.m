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
#import "controllers/RAGameViewController.h"
#import "runner/RAGameLogicThreadRunner.h"
#import "runner/RAGameLogicDisplayLinkRunner.h"
#import "input/RAInputActionManager.h"
#import "virtual/virtual_joypad.h"

#import <retroarch_door.h>
#import <utils/verbosity.h>
#import <cocoa_input.h>
#import <UIKit+Extensions.h>
#import <Foundation+Extensions.h>
#import <CoreFoundation/CoreFoundation.h>
#import <tasks/task_content.h>

#define SHOW_CORE_ROM_TYPE_INFO 0

NSString * const RetroArchXReadyNotification = @"retro_arch_x_ready";

@implementation RetroArchX {
    NSArray<UTType *> *d_allSupportedExtensions;
    NSSet<NSString *> *d_allExtensionsSet;
    NSArray<EmuCoreInfoItem *> *d_coreItems;
    __nullable id<RAGameLoopRunner> d_gameLogicRuner;
    RAInputActionManager *d_inputActionManager;
    NSMutableDictionary<NSString *, RetroArchXEmuFrameAction> *d_emuPrevFrameActions;

    BOOL d_initialized;
    BOOL d_dummyCoreRunning;
    BOOL d_inputDriverOnlyRunning;
}

@synthesize gameLogicRunner    = d_gameLogicRuner;
@synthesize inputActionManager = d_inputActionManager;
@synthesize initialized        = d_initialized;

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
        d_initialized = NO;
        d_dummyCoreRunning = NO;
        d_inputDriverOnlyRunning = NO;
        d_emuPrevFrameActions = [NSMutableDictionary dictionary];
        d_inputActionManager = [[RAInputActionManager alloc] init];

        __weak RetroArchX *weakSelf = self;
        d_emuPrevFrameActions[@"RAInputActionManager.tick"] = ^{
            [weakSelf.inputActionManager tickFrame:YES];
        };

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            // open log
            verbosity_enable();
            verbosity_set_log_level(0);

            //set language
            unsigned language = frontend_driver_get_user_language();
            msg_hash_set_uint(MSG_HASH_USER_LANGUAGE, language);

            char arguments[]   = "retroarch";
            char       *argv[] = {arguments,   NULL};
            int argc           = 1;
            rarch_main(argc, argv, NULL, false);

            [self findAllSupportedExtensions];

            d_initialized = YES;

            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:RetroArchXReadyNotification object:self];
            });
        });
    }
    return self;
}

- (void)dealloc {
    main_exit(NULL);
}

- (BOOL)dummyCoreRunning {
    return d_dummyCoreRunning;
}

- (BOOL)inputDriverOnlyRunning {
    return d_inputDriverOnlyRunning;
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
    return d_gameLogicRuner.displayLink;
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
    if (d_dummyCoreRunning) {
        [self stopDummyCoreIfNeeded];
    }

    if (d_inputDriverOnlyRunning) {
        [self stopInputDriverOnlyIfNeeded];
    }

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
                d_dummyCoreRunning = NO;
                if(video_driver_is_threaded()) {
                    d_gameLogicRuner = [[RAGameLogicThreadRunner alloc] initWithEmuPrevFrameActions:d_emuPrevFrameActions];
                    [d_gameLogicRuner start];
                } else {
                    d_gameLogicRuner = [[RAGameLogicDisplayLinkRunner alloc] initWithEmuPrevFrameActions:d_emuPrevFrameActions];
                    [d_gameLogicRuner start];
                }
                d_gameLogicRuner.statsLoggingEnabled = YES;
            }

            if (completion) {
                completion(load_ret);
            }
        });
    });
}

- (void)startDummyCoreIfNeeded:(nullable void (^)(BOOL success))completion {
    // 已有真实游戏在跑时，不启动 dummy。
    if (self.currentCoreItem != nil || d_gameLogicRuner != nil || d_dummyCoreRunning) {
        if (completion) {
            completion(YES);
        }
        return;
    }

    if (d_inputDriverOnlyRunning) {
        [self stopInputDriverOnlyIfNeeded];
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        content_ctx_info_t content_info;
        memset(&content_info, 0, sizeof(content_ctx_info_t));
        content_info.init_input_driver_only = true;
        BOOL load_ret = task_push_start_dummy_core(&content_info);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (load_ret) {
                d_gameLogicRuner = [[RAGameLogicDisplayLinkRunner alloc] initWithEmuPrevFrameActions:d_emuPrevFrameActions];
                [d_gameLogicRuner start];
                d_gameLogicRuner.statsLoggingEnabled = NO;
                d_dummyCoreRunning = YES;
            }
            if (completion) {
                completion(load_ret);
            }
        });
    });
}

- (BOOL)stopDummyCoreIfNeeded {
    if (!d_dummyCoreRunning) {
        return YES;
    }

    // 防止误停真实游戏
    if (self.currentCoreItem != nil) {
        return YES;
    }

    BOOL ret = YES;
    if (d_gameLogicRuner != nil) {
        ret = [d_gameLogicRuner stop];
        d_gameLogicRuner = nil;
    }

    drivers_deinit_input_only();

    d_dummyCoreRunning = NO;
    return ret;
}

- (BOOL)startInputDriverOnlyIfNeeded {
    // 真实游戏或 dummy loop 运行时，不走 input-only
    if (self.currentCoreItem != nil || d_dummyCoreRunning || d_gameLogicRuner != nil) {
        return YES;
    }
    if (d_inputDriverOnlyRunning) {
        return YES;
    }

    settings_t *settings = config_get_ptr();
    if (!settings) return NO;

    bool ok = drivers_init_input_only(settings, verbosity_is_enabled());
    if (ok) {
        d_inputDriverOnlyRunning = YES;
    }
    return ok;
}

- (BOOL)stopInputDriverOnlyIfNeeded {
    if (!d_inputDriverOnlyRunning) return YES;
    // 防误停：有真实游戏或 dummy loop 时不动
    if (self.currentCoreItem != nil || d_dummyCoreRunning || d_gameLogicRuner != nil) {
        return YES;
    }

    drivers_deinit_input_only();
    d_inputDriverOnlyRunning = NO;
    return YES;
}

- (BOOL)stop {
    EmuCoreInfoItem *runningCore = [self currentCoreItem];
    NSString *coreId = runningCore.coreId.lowercaseString ?: @"";
    BOOL isYabause = [coreId containsString:@"yabause"];
    if (isYabause) {
        /*
         Yabause-specific teardown guard:

         We observed a stable EXC_BAD_ACCESS in emu.yabause (often in Vdp1DrawCommands)
         when exiting a game with a connected MFi controller. The core issue is teardown
         ordering/race: input callbacks may still arrive while core/video state is being
         paused/unloaded, causing use-after-free or inconsistent state access inside the
         framework render path.

         Mitigation strategy:
         1) Stop input callbacks first (quiesce input).
         2) Reset runtime input state.
         3) Pause and give a short quiet window before stop/unload.
         4) Restore callbacks after teardown for next session.

         This does NOT disconnect system Bluetooth controllers; it only detaches the app's
         internal input callback chain during core teardown.
        */

        // A) 先静默输入，避免 teardown 期间收到 mfi 事件
        [d_inputActionManager beginCoreTeardownGuard];

        // B) 尝试先 pause，让 runloop/render 进入稳定态
        if (d_gameLogicRuner != nil) {
            [d_gameLogicRuner pause];
        }

        // C) 给一小段静默窗口，尽量让 Vdp1DrawCommands 收尾
        if ([NSThread isMainThread]) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.08, false);
        } else {
            usleep(80 * 1000);
        }
    }

    BOOL ret = [d_gameLogicRuner stop];
    d_gameLogicRuner = nil;
    d_dummyCoreRunning = NO;
    d_inputDriverOnlyRunning = NO;
    [runningCore cleanupMameSession];

    if (isYabause) {
        // D) 恢复回调链，避免影响下次开局
        [d_inputActionManager endCoreTeardownGuard];
    }

    return ret;
}

- (BOOL)pause {
    if(self.currentCoreItem != nil) {
        return [d_gameLogicRuner pause];
    } else {
        return NO;
    }
}

- (BOOL)resume {
    if(self.currentCoreItem != nil) {
        return [d_gameLogicRuner resume];
    } else {
        return NO;
    }
}

- (BOOL)reset {
    if(self.currentCoreItem != nil) {
        return [d_gameLogicRuner reset];
    } else {
        return NO;
    }
}

- (BOOL)mute:(BOOL)mute {
    bool *muteEnable = audio_get_bool_ptr(AUDIO_ACTION_MUTE_ENABLE);
    if(muteEnable != NULL) {
        *muteEnable = mute;
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)saveStateTo:(NSString *)folder imageFolder:(nullable NSString *)imageFolder name:(NSString *)name {
    if(self.currentCoreItem == nil) {
        return NO;
    }

    NSString *path = [folder stringByAppendingPathComponent:name];
    NSString *statePath = [path stringByAppendingPathExtension:@"state"];

    NSString *pngPath;
    if(imageFolder == nil) {
        pngPath = [path stringByAppendingPathExtension:@"png"];
    } else {
        pngPath = [[imageFolder stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"png"];
    }

    NSNumber *ret1 = (NSNumber *)[d_gameLogicRuner suspendGameLoopAndPerformSync:^{
        video_driver_state_t *video_st = video_state_get_ptr();
        settings_t *settings           = config_get_ptr();
        bool frame_time_counter_reset_after_save_state = settings->bools.frame_time_counter_reset_after_save_state;
        BOOL ret = content_direct_save_state(statePath.UTF8String);
        if (frame_time_counter_reset_after_save_state)
           video_st->frame_time_count = 0;
        return @(ret);
    } runOnLogicThread:YES];

    BOOL ret2 = [self saveScreenshotTo:pngPath notify:NO];

    return ret1.boolValue && ret2;
}

- (BOOL)loadStateFrom:(NSString *)path {
    if(self.currentCoreItem == nil) {
        return NO;
    }

    if(![NSFileManager.defaultManager pathIsFile:path]) {
        return NO;
    }

    NSNumber *ret = (NSNumber *)[d_gameLogicRuner suspendGameLoopAndPerformSync:^{
        bool ret = content_load_state(path.UTF8String, false, false);
        if(ret) {
            command_post_state_loaded();
        }
        return @(ret);
    } runOnLogicThread:YES];
    return ret.boolValue;
}

bool get_screenshot_data(uint8_t **png_data, uint64_t *png_data_size);

- (BOOL)saveScreenshotTo:(NSString *)path notify:(BOOL)notify {
    if(self.currentCoreItem == nil) {
        return NO;
    }

    NSNumber *ret = (NSNumber *)[d_gameLogicRuner suspendGameLoopAndPerformSync:^{
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

                if(notify) {
                    NSString *formatter = [NSBundle localizedStringForKey:@"gamepage_screenshot_saved_at"];
                    NSString *message = [NSString stringWithFormat:formatter, shorten_path_for_log(raw_path, log_raw_path, sizeof(log_raw_path))];
                    EmuInGameMessage *inGameMessage = [[EmuInGameMessage alloc] initWithMessage:message title:nil type:EmuInGameMessageInfo duration:120 priority:1];
                    [(id)apple_platform showInGameMessage:inGameMessage];
                }
            }
            free(png_data);
        }
        return @(ret);
    } runOnLogicThread:NO];

    return ret.boolValue;
}

- (void)sendJoypadCode:(enum RetroArchJoypadCode)code down:(BOOL)down {
    if (code < 0 || code >= RARCH_BIND_LIST_END) {
        return;
    }

    virtual_joypad_set_button((unsigned)code, down);
}

- (void)sendJoypadAxis:(enum RetroArchJoypadAxis)axis value:(CGFloat)value {
    if (axis > RetroArchJoypadAxisRightY) {
        return;
    }

    CGFloat clamped = value;
    if (clamped > 1.0) {
        clamped = 1.0;
    } else if (clamped < -1.0) {
        clamped = -1.0;
    }

    int16_t intValue = (int16_t)(clamped * 0x7fff);
    virtual_joypad_set_axis((unsigned)axis, intValue);
}

- (void)setFastForwardEnabled:(BOOL)enabled multiplier:(double)multiplier {
    if (self.currentCoreItem == nil || d_gameLogicRuner == nil) {
        return;
    }

    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [d_gameLogicRuner setFastForwardEnabled:enabled multiplier:multiplier];
        });
        return;
    } else {
        [d_gameLogicRuner setFastForwardEnabled:enabled multiplier:multiplier];
    }
}

- (NSString *)addEmuPrevFrameAction:(RetroArchXEmuFrameAction)action {
    if(d_gameLogicRuner == nil) {
        NSString *token = NSUUID.UUID.UUIDString;
        d_emuPrevFrameActions[token] = [action copy];
        return token;
    } else {
        return [d_gameLogicRuner addEmuPrevFrameAction:action];
    }
}

- (void)removeEmuPrevFrameActionForToken:(NSString *)token {
    if(d_gameLogicRuner == nil) {
        [d_emuPrevFrameActions removeObjectForKey:token];
    } else {
        [d_gameLogicRuner removeEmuPrevFrameActionForToken:token];
    }
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

    [set addObject:@"gdi"];

    d_allExtensionsSet       = [set copy];
    d_allSupportedExtensions = [array copy];
}

@end
