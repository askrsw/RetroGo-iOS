//
//  EmuCoreItem.m
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

#import "EmuCoreInfoItem.h"
#import "EmuCoreFirmware.h"

#include <utils/configuration.h>
#include <file/archive_file.h>
#include <file/file_path.h>
#include <retro_miscellaneous.h>

NS_ASSUME_NONNULL_BEGIN

@implementation EmuCoreInfoItem {
    NSString *d_systemShowPath;

    NSDictionary *d_extraInfo;
}

#define ASSIGN_ARRAY_FROM_COREINFO(_ivar, _coreInfo, _field) \
    if((_coreInfo)->_field##_list != nil) { \
        NSMutableArray *array = [NSMutableArray array]; \
        for(int i = 0; i < (_coreInfo)->_field##_list->size; i++) { \
            char *value = (_coreInfo)->_field##_list->elems[i].data; \
            [array addObject:@(value)]; \
        } \
        _ivar = [array copy]; \
    } else if((_coreInfo)->_field != nil) { \
        _ivar = @[@((_coreInfo)->_field)]; \
    }

- (instancetype)initWithCoreInfo:(const core_info_t *)coreInfo {
    self = [super init];
    if (self) {
        _corePath = @(coreInfo->path);
        _displayName = @(coreInfo->display_name);
        _coreName = @(coreInfo->core_name);
        _systemName = coreInfo->systemname ? @(coreInfo->systemname) : nil;
        _systemID = coreInfo->system_id ? @(coreInfo->system_id) : nil;
        _version = coreInfo->display_version ? @(coreInfo->display_version) : nil;
        ASSIGN_ARRAY_FROM_COREINFO(_categories, coreInfo, categories)
        ASSIGN_ARRAY_FROM_COREINFO(_licenses, coreInfo, licenses)
        _manufacturer = coreInfo->system_manufacturer ? @(coreInfo->system_manufacturer) : nil;
        ASSIGN_ARRAY_FROM_COREINFO(_extensions, coreInfo, supported_extensions)
        ASSIGN_ARRAY_FROM_COREINFO(_authors, coreInfo, authors)
        _supportNoContent = coreInfo->supports_no_game;
        _experimental = coreInfo->is_experimental;
        _singlePurpose = coreInfo->single_purpose;
        ASSIGN_ARRAY_FROM_COREINFO(_permissions, coreInfo, permissions)
        ASSIGN_ARRAY_FROM_COREINFO(_databases, coreInfo, databases)
        ASSIGN_ARRAY_FROM_COREINFO(_hwApis, coreInfo, required_hw_api)
        _desc = coreInfo->description ? @(coreInfo->description) : nil;
        ASSIGN_ARRAY_FROM_COREINFO(_notes, coreInfo, notes)

        if(string_starts_with(coreInfo->core_file_id.str, "emu_")) {
            _coreId = @(coreInfo->core_file_id.str + 4);
        } else {
            _coreId = @(coreInfo->core_file_id.str);
        }

        d_systemShowPath = [self getSystemShowPathWithCoreInfo:coreInfo];

        if(![_coreId isEqualToString:@"mame"]) {
            _firmwares = [self loadCoreFrimwaresWithCoreInfo:coreInfo];
        } else {
            _firmwares = [self loadMameFirmwares];
        }

        // 如果 ppsspp 的 ppge_atlas.zim 不存在，则认为 ppsspp 的 assets 还没有被提取。
        if([_coreId isEqualToString:@"ppsspp"] && ![_firmwares.firstObject fileExists]) {
            [self extractPPSSPPAssets];
        }

        _expanded  = NO;
        _isHidden  = NO;
        _itemCount = 0;
    }
    return self;
}

#undef ASSIGN_ARRAY_FROM_COREINFO

- (nullable NSString *)licensesLine {
    if(_licenses.count <= 0) {
        return nil;
    } else {
        return [_licenses componentsJoinedByString:@","];
    }
}

- (NSString *)frameworkName {
    return self.corePath.lastPathComponent;
}

+ (NSArray<EmuCoreInfoItem *> *)findAllCores {
    NSMutableArray *array = [NSMutableArray array];

    settings_t *config = config_get_ptr();
    const char *path   = config->paths.directory_libretro;
    struct string_list *str_list = string_list_new();
    bool ok = dir_list_append(str_list, path, "framework", true, false, false, false);
    size_t list_size = str_list->size;

    if (!ok ||  list_size == 0 ) {
        string_list_free(str_list);
        str_list = NULL;
        return [array copy];
    }

    core_info_list_t *list = NULL;
    core_info_get_list(&list);

    for(size_t i = 0; i < list_size; i++) {
        if(str_list->elems[i].attr.i != RARCH_PLAIN_FILE) {
            continue;
        }

        const char *file_path = str_list->elems[i].data;
        const char *file_name = file_path;
        if (!string_is_empty(file_name))
            file_name = path_basename_nocompression(file_name);
#ifdef IOS
      /* For various reasons on iOS/tvOS, MoltenVK shows up
       * in the cores directory; exclude it here */
      if (string_starts_with(file_name, "MoltenVK"))
         continue;
#endif // IOS

        core_info_t info;
        if(core_info_list_get_info(list, &info, file_name)) {
            EmuCoreInfoItem *item = [[EmuCoreInfoItem alloc] initWithCoreInfo:&info];
            [array addObject:item];
        }
    }

    string_list_free(str_list);

    NSArray *sortedArray = [array sortedArrayUsingComparator:^NSComparisonResult(EmuCoreInfoItem *obj1, EmuCoreInfoItem *obj2) {
        return [obj1.displayName compare:obj2.displayName options:NSCaseInsensitiveSearch];
    }];

    return sortedArray;
}

+ (instancetype)noneCore {
    static EmuCoreInfoItem *none = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        none = [[self alloc] init];
        none->_coreId      = @"0";
        none->_displayName = @"";
        none->_corePath    = @"";
        none->_expanded    = NO;
        none->_isHidden    = NO;
        none->_itemCount   = 0;
    });
    return none;
}

- (void)scanFirmwareFolder:(NSURL *)url match:(BOOL)match processing:(void (^)(NSString *fileName))processing errorHandler:(void (^)(NSError *error))errorHandler completion:(void (^)(NSArray<EmuCoreFirmware *> *))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [url startAccessingSecurityScopedResource];

        NSArray *keys = @[NSURLIsDirectoryKey];
        NSFileManager *manager = NSFileManager.defaultManager;
        NSError *error = nil;
        NSArray<NSURL *> *contents = [manager contentsOfDirectoryAtURL:url includingPropertiesForKeys:keys options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];

        if (error) {
            [url stopAccessingSecurityScopedResource];
            return errorHandler(error);
        }

        NSMutableArray *updatedFirmwares = [NSMutableArray array];

        for(NSURL *fileUrl in contents) {
            NSNumber *isDirectory = nil;
            [fileUrl getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
            if(isDirectory.boolValue) {
                continue;
            }

            NSString *fileName = fileUrl.lastPathComponent;
            processing(fileName);

            if(match) {
                for (EmuCoreFirmware *firmware in self.firmwares) {
                    if ([firmware.name isEqualToString:fileName]) {
                        if ([firmware copyFile:fileUrl]) {
                            [updatedFirmwares addObject:firmware];
                        }
                        break;
                    }
                }
            } else {
                BOOL found = NO;
                for(EmuCoreFirmware *f in self.firmwares) {
                    if([f.name isEqual:fileName]) {
                        [f copyFile:fileUrl];
                        found = YES;
                        break;
                    }
                }
                if(found == NO) {
                    NSString *showPath = [d_systemShowPath stringByAppendingPathComponent:fileName];
                    EmuCoreFirmware *firmware = [[EmuCoreFirmware alloc] initWithPath:showPath desc:nil optional:YES md5:nil];
                    if([firmware copyFile:fileUrl]) {
                        [updatedFirmwares addObject:firmware];
                    }
                }
            }
        }

        if(!match) {
            if(_firmwares != nil) {
                NSMutableArray *newArray = [NSMutableArray arrayWithArray:_firmwares];
                [newArray addObjectsFromArray:updatedFirmwares];
                _firmwares = [newArray copy];
            } else {
                _firmwares = [updatedFirmwares copy];
            }
        }

        completion(updatedFirmwares);
        [url stopAccessingSecurityScopedResource];
    });
}

- (nullable EmuCoreFirmware *)importFirmwareFile:(NSURL *)url {
    [url startAccessingSecurityScopedResource];

    NSNumber *isDirectory = nil;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
    if(isDirectory.boolValue) {
        return nil;
    }

    [url stopAccessingSecurityScopedResource];

    NSString *fileName = url.lastPathComponent;
    EmuCoreFirmware *exist = nil;
    for(EmuCoreFirmware *f in self.firmwares) {
        if([f.name isEqual:fileName]) {
            [f copyFile:url];
            exist = f;
            break;
        }
    }

    if(!exist) {
        NSString *showPath = [d_systemShowPath stringByAppendingPathComponent:fileName];
        EmuCoreFirmware *firmware = [[EmuCoreFirmware alloc] initWithPath:showPath desc:nil optional:YES md5:nil];
        if([firmware copyFile:url]) {
            if(_firmwares == nil) {
                _firmwares = @[firmware];
            } else {
                NSMutableArray *newArray = [NSMutableArray arrayWithArray:_firmwares];
                [newArray addObject: firmware];
                _firmwares = [newArray copy];
            }
            return firmware;
        } else {
            return nil;
        }
    } else {
        return exist;
    }
}

- (BOOL)deleteFirmware:(EmuCoreFirmware *)firmware {
    BOOL ret = [firmware deleteFile];

    if (ret) {
        NSMutableArray *mutableFirmwares = [_firmwares mutableCopy];
        [mutableFirmwares removeObject:firmware];
        _firmwares = [mutableFirmwares copy];
    }

    return ret;
}

- (nullable NSString *)checkIsMameCore:(NSString *)romPath {
    if(romPath == nil || ![_coreId isEqualToString:@"mame"]) {
        return romPath;
    }

    NSMutableArray *array = [NSMutableArray array];
    for(EmuCoreFirmware *f in self.firmwares) {
        if([f isValid]) {
            [array addObject:[NSURL fileURLWithPath:f.fullPath]];
        }
    }

    if(array.count == 0) {
        return romPath;
    }

    NSURL *romUrl = [NSURL fileURLWithPath:romPath];

    NSError *error = nil;
    NSURL *result = [self prepareMameStagingDirectoryForGame:romUrl biosFiles:[array copy] error:&error];

    if(error == nil) {
        return result.path;
    } else {
        return romPath;
    }
}

- (void)cleanupMameSession {
    if(![_coreId isEqualToString:@"mame"]) {
        return;
    }

    NSString *tempDir = NSTemporaryDirectory();
    NSURL *stagingDir = [NSURL fileURLWithPath:[tempDir stringByAppendingPathComponent:@"MameSession"]];

    NSFileManager *manager = [NSFileManager defaultManager];

    // 判断是否存在
    if ([manager fileExistsAtPath:stagingDir.path]) {
        NSError *error = nil;
        // 注意：removeItemAtURL 删除目录时，会递归删除里面的所有内容
        // 对于硬链接，这只会删除“链接”，绝对不会影响 Documents 里的源文件，非常安全。
        [manager removeItemAtURL:stagingDir error:&error];

        if (error) {
            NSLog(@"Cleanup warning: %@", error);
        } else {
            NSLog(@"MAME session cleaned up.");
        }
    }
}

- (nullable NSString *)getLocalDesc:(NSString *)language {
    if(d_extraInfo == nil) {
        d_extraInfo = [self loadExtraCoreInfo];
    }
    return d_extraInfo[@"desc"][language];
}

- (nullable NSArray<NSDictionary<NSString *, NSString *> *> *)getLicenseDictionaryArray {
    if(d_extraInfo == nil) {
        d_extraInfo = [self loadExtraCoreInfo];
    }
    return d_extraInfo[@"licenses"];
}

- (nullable NSString *)getSourceURL {
    if(d_extraInfo == nil) {
        d_extraInfo = [self loadExtraCoreInfo];
    }
    return d_extraInfo[@"src_url"];
}

- (BOOL)supportsAnalog {
    if(d_extraInfo == nil) {
        d_extraInfo = [self loadExtraCoreInfo];
    }
    NSNumber *obj = d_extraInfo[@"supports_analog"];
    return [obj boolValue];
}

- (nullable NSString *)overlayName {
    if(d_extraInfo == nil) {
        d_extraInfo = [self loadExtraCoreInfo];
    }
    return d_extraInfo[@"overlay"];
}

- (BOOL)supportsLogicThread {
    if(d_extraInfo == nil) {
        d_extraInfo = [self loadExtraCoreInfo];
    }
    NSNumber *obj = d_extraInfo[@"supports_logic_thread"];
    return [obj boolValue];
}

// 完整的解压回调，支持空文件夹创建和父目录自动补全
static int file_archive_extract_cb(const char *name, const char *valid_exts, const uint8_t *cdata, unsigned cmode, uint32_t csize, uint32_t size, uint32_t crc32, struct archive_extract_userdata *userdata) {

    char out_path[PATH_MAX_LENGTH];

    // 1. 拼接完整绝对路径
    if (userdata->extraction_directory) {
        fill_pathname_join(out_path, userdata->extraction_directory, name, sizeof(out_path));
    } else {
        strlcpy(out_path, name, sizeof(out_path));
    }

    // 2. 判断是否为目录条目 (以 / 或 \ 结尾)
    size_t len = strlen(name);
    bool is_directory = (len > 0 && (name[len-1] == '/' || name[len-1] == '\\'));

    if (is_directory) {
        // [关键点] 如果是文件夹条目，直接创建目录
        // 这样就能保留空文件夹了
        if (!path_is_directory(out_path)) {
            path_mkdir(out_path);
        }
        return 1; // 继续处理下一个，不执行后面的写文件逻辑
    }

    // 3. 处理文件条目

    // 3.1 防御性编程：检查父目录是否存在
    // 虽然上面处理了目录条目，但有些 ZIP 可能会省略父目录条目直接给文件，
    // 或者乱序，所以每次写文件前检查父目录是必要的保险。
    char parent_dir[PATH_MAX_LENGTH];
    fill_pathname_parent_dir_name(parent_dir, out_path, sizeof(parent_dir));

    if (!path_is_directory(parent_dir)) {
        // 尝试创建父目录
        path_mkdir(parent_dir);
    }

    // 3.2 写入文件数据
    // file_archive_perform_mode 负责将内存中的 cdata 写入磁盘
    bool success = file_archive_perform_mode(out_path, valid_exts, cdata, cmode, csize, size, crc32, userdata);

    return success ? 1 : 0;
}

- (BOOL)extractPPSSPPAssets {
    if(![_coreId isEqualToString:@"ppsspp"]) {
        return NO;
    }

    NSString *assetsPath = [[NSBundle mainBundle] pathForResource:@"ppsspp-assets" ofType:@"zip" inDirectory:@"Data/assets"];
    NSString *destPath = d_systemShowPath;
    if ([destPath hasPrefix:@"~"]) {
        NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        destPath = [destPath stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:docsPath];
    }

    // 1. 准备 C 风格字符串
    const char *cZipPath = [assetsPath fileSystemRepresentation];
    const char *cDestDir = [destPath fileSystemRepresentation];

    // 2. 初始化 userdata
    // struct archive_extract_userdata 是传给回调函数的数据结构
    // file_archive_perform_mode 会利用这个结构体中的 extraction_directory 来决定文件写到哪
    struct archive_extract_userdata userdata;
    memset(&userdata, 0, sizeof(userdata));
    userdata.extraction_directory = cDestDir;

    // [推荐] 将 zip 路径复制到 userdata 中，某些 callback 可能会用到
    // 注意：archive_path 是定长数组，需使用 strlcpy
    strlcpy(userdata.archive_path, cZipPath, sizeof(userdata.archive_path));

    // 3. 初始化传输状态
    file_archive_transfer_t state;
    memset(&state, 0, sizeof(state));
    state.type = ARCHIVE_TRANSFER_INIT;

    bool success = true;
    int ret = 0;

    do {
        // 3. 路径是在这里作为第三个参数 (cZipPath) 传入的
        ret = file_archive_parse_file_iterate(
            &state,
            &success,
            cZipPath,   // <--- 这里才是传入路径的地方
            NULL,       // valid_exts
            file_archive_extract_cb,
            &userdata
        );

        // ret == 0 : 继续迭代
        // ret == 1 : 完成
    } while (ret == 0);

    file_archive_parse_file_iterate_stop(&state);

    if (!success) {
        return NO;
    } else {
        // --- 补充：动态生成合规声明文件 ---
        NSString *readmePath = [destPath stringByAppendingPathComponent:@"README.txt"];
        NSString *readmeContent = @"RetroGo - PPSSPP Assets Setup:\n\n"
            "These UI assets are extracted from the official PPSSPP project. "
            "For detailed licensing information, please refer to the 'LICENSE' file "
            "included in 'PPSSPP' directory, which outlines the GPL/open-source terms "
            "governing these assets.\n\n"
            "No proprietary or copyrighted Sony firmware is included.";
        NSError *error = nil;
        [readmeContent writeToFile:readmePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (error) {
            NSLog(@"Note: Failed to create README.txt, but assets were extracted.");
        }
        return YES;
    }
}

#pragma mark - Utils

- (nullable NSDictionary *)loadExtraCoreInfo {
    NSString *jsonFileName = [NSString stringWithFormat:@"%@_extra", _coreId];
    NSString *jsonFilePath = [[NSBundle mainBundle] pathForResource:jsonFileName ofType:@"json" inDirectory:@"Data/jsons"];

    NSData *jsonData = [NSData dataWithContentsOfFile:jsonFilePath];

    if(jsonData == nil) {
        return nil;
    }

    NSError *error = nil;
    NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if(error) {
        NSLog(@"Parse %@ file error: %@", jsonFileName, error.localizedDescription);
        return nil;
    } else {
        return jsonDict;
    }
}

- (NSURL *)prepareMameStagingDirectoryForGame:(NSURL *)gameURL biosFiles:(NSArray<NSURL *> *)biosFiles error:(NSError **)error {
    NSFileManager *manager = [NSFileManager defaultManager];

    // 1. 在临时目录创建一个专门的文件夹，例如 tmp/MameSession
    NSString *tempDir = NSTemporaryDirectory();
    NSURL *stagingDir = [NSURL fileURLWithPath:[tempDir stringByAppendingPathComponent:@"MameSession"]];

    // 2. 清理旧的会话目录（确保环境干净）
    if ([manager fileExistsAtPath:stagingDir.path]) {
        [manager removeItemAtURL:stagingDir error:nil];
    }
    [manager createDirectoryAtURL:stagingDir withIntermediateDirectories:YES attributes:nil error:error];

    // 3. 将目标游戏 ROM 硬链接到该目录
    NSURL *stagedGameURL = [stagingDir URLByAppendingPathComponent:gameURL.lastPathComponent];
    // 注意：linkItemAtURL 创建的是硬链接
    if (![manager linkItemAtURL:gameURL toURL:stagedGameURL error:error]) {
        NSLog(@"Failed to link game ROM: %@", *error);
        return nil;
    }

    // 4. 将所有 BIOS 文件硬链接到该目录

    for (NSURL *biosFile in biosFiles) {
        if (![manager fileExistsAtPath:biosFile.path]) {
            continue;
        }

        NSURL *destination = [stagingDir URLByAppendingPathComponent:biosFile.lastPathComponent];

        // 忽略错误（比如文件已存在），继续链接下一个
        [manager linkItemAtURL:biosFile toURL:destination error:nil];
    }

    NSLog(@"MAME Staging complete at: %@", stagingDir.path);

    // 5. 返回位于临时目录中的游戏 ROM 路径给核心使用
    return stagedGameURL;
}

- (NSString *)getSystemShowPathWithCoreInfo:(const core_info_t *)coreInfo {
    NSString *systemDirPath = @(core_info_get_firmwares_path((core_info_t *)coreInfo, true));
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSRange range = [systemDirPath rangeOfString:documentsPath];
    NSString *systemShowPath;
    if(range.location != -1) {
        systemShowPath = [systemDirPath stringByReplacingCharactersInRange:NSMakeRange(0, range.location + range.length) withString:@"~"];
    } else {
        systemShowPath = systemDirPath;
    }

    return systemShowPath;
}

- (nullable NSArray<EmuCoreFirmware *> *)loadMameFirmwares {
    NSString *path = d_systemShowPath;
    if ([path hasPrefix:@"~"]) {
        NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        path = [path stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:docsPath];
    }

    NSURL *url = [NSURL fileURLWithPath:path];
    NSArray *keys = @[NSURLIsDirectoryKey];
    NSFileManager *manager = NSFileManager.defaultManager;
    NSError *error = nil;
    NSArray<NSURL *> *contents = [manager contentsOfDirectoryAtURL:url includingPropertiesForKeys:keys options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];

    NSMutableArray *array = [NSMutableArray array];
    for(NSURL *fileUrl in contents) {
        NSNumber *isDirectory = nil;
        [fileUrl getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        if(isDirectory.boolValue) {
            continue;
        }

        NSString *fileName = fileUrl.lastPathComponent;
        NSString *showPath = [d_systemShowPath stringByAppendingPathComponent:fileName];
        EmuCoreFirmware *firmware = [[EmuCoreFirmware alloc] initWithPath:showPath desc:nil optional:YES md5:nil];
        [array addObject:firmware];
    }

    if(array.count > 0) {
        return [array copy];
    } else {
        return nil;
    }
}

- (nullable NSArray<EmuCoreFirmware *> *)loadCoreFrimwaresWithCoreInfo:(const core_info_t *)coreInfo {
    NSString *systemShowPath = d_systemShowPath;

    NSMutableArray *array = [NSMutableArray array];
    for(int i = 0; i < coreInfo->firmware_count; i++) {
        core_info_firmware_t f = coreInfo->firmware[i];
        NSString *fileName = @(f.path);

        NSString *showPath = [systemShowPath stringByAppendingPathComponent:fileName];
        NSString *desc = @(f.desc);
        BOOL optional = f.optional;

        NSString *md5;
        if(coreInfo->notes_list != nil) {
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\S+)\\s+\\(md5\\):\\s*([a-fA-F0-9]{32})" options:0 error:nil];
            struct string_list *notes = coreInfo->notes_list;
            for(int j = 0; j < notes->size; j++) {
                struct string_list_elem elem = notes->elems[j];
                NSString *line = @(elem.data);
                NSTextCheckingResult *match = [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
                NSString *m1 = [line substringWithRange:[match rangeAtIndex:1]];
                NSString *m2 = [line substringWithRange:[match rangeAtIndex:2]];
                if([fileName isEqualToString:m1]) {
                    md5 = m2;
                    break;
                }
            }
        }

        EmuCoreFirmware *firmware = [[EmuCoreFirmware alloc] initWithPath:showPath desc:desc optional:optional md5:md5];
        [array addObject:firmware];
    }

    if(array.count > 0) {
        return [array copy];
    } else {
        return nil;
    }
}

@end

NS_ASSUME_NONNULL_END
