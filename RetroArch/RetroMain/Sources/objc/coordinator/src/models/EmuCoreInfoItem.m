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
#import <dlfcn.h>

#include <utils/configuration.h>
#include <file/archive_file.h>
#include <file/file_path.h>
#include <retro_miscellaneous.h>
#include <utils/retrogo_log.h>

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
        ASSIGN_ARRAY_FROM_COREINFO(_categories, coreInfo, categories);
        ASSIGN_ARRAY_FROM_COREINFO(_licenses, coreInfo, licenses);
        _manufacturer = coreInfo->system_manufacturer ? @(coreInfo->system_manufacturer) : nil;
        ASSIGN_ARRAY_FROM_COREINFO(_extensions, coreInfo, supported_extensions);
        ASSIGN_ARRAY_FROM_COREINFO(_authors, coreInfo, authors);
        _supportNoContent = coreInfo->supports_no_game;
        _experimental = coreInfo->is_experimental;
        _singlePurpose = coreInfo->single_purpose;
        _isHWRender = coreInfo->is_hw_render;
        /* Netplay requires deterministic savestate support. Mirrors the
         * threshold used by core_info_current_supports_netplay(). */
        _supportsNetplay = coreInfo->savestate_support_level >= CORE_INFO_SAVESTATE_DETERMINISTIC;
        ASSIGN_ARRAY_FROM_COREINFO(_permissions, coreInfo, permissions);
        ASSIGN_ARRAY_FROM_COREINFO(_databases, coreInfo, databases);
        ASSIGN_ARRAY_FROM_COREINFO(_hwApis, coreInfo, required_hw_api);
        _desc = coreInfo->description ? @(coreInfo->description) : nil;
        ASSIGN_ARRAY_FROM_COREINFO(_notes, coreInfo, notes);

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

        // If ppsspp's ppge_atlas.zim doesn't exist, ppsspp's assets are assumed not to be extracted yet.
        if([_coreId isEqualToString:@"ppsspp"] && ![_firmwares.firstObject fileExists]) {
            [self extractPPSSPPAssets];
        }
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

    // Taken once: a later launch of another game must not inherit these links.
    NSDictionary<NSString *, NSString *> *links = self.pendingMameSessionLinks;
    NSString *gameName = self.pendingMameSessionGameName;
    self.pendingMameSessionLinks = nil;
    self.pendingMameSessionGameName = nil;

    if(array.count == 0 && links.count == 0 && gameName.length == 0) {
        return romPath;
    }

    NSURL *romUrl = [NSURL fileURLWithPath:romPath];

    NSError *error = nil;
    NSURL *result = [self prepareMameStagingDirectoryForGame:romUrl stagedName:gameName biosFiles:[array copy] links:links error:&error];

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

    // Check whether it exists
    if ([manager fileExistsAtPath:stagingDir.path]) {
        NSError *error = nil;
        // Note: when removeItemAtURL removes a directory, it recursively removes everything inside
        // For hard links this only removes the "link" and never touches the source files in Documents, so it is perfectly safe.
        [manager removeItemAtURL:stagingDir error:&error];

        if (error) {
            RETROGO_LOGN(MAME, "Session cleanup failed: %@", error);
        } else {
            RETROGO_LOGD(MAME, "Session cleaned up");
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

- (BOOL)allowsDefaultTurboXYHijack {
    if(d_extraInfo == nil) {
        d_extraInfo = [self loadExtraCoreInfo];
    }
    NSNumber *obj = d_extraInfo[@"allows_default_turbo_xy_hijack"];
    return [obj boolValue];
}

- (nullable NSArray<NSDictionary<NSString *, id> *> *)portDevices {
    if(d_extraInfo == nil) {
        d_extraInfo = [self loadExtraCoreInfo];
    }
    NSArray *devices = d_extraInfo[@"port_devices"];
    return [devices isKindOfClass:[NSArray class]] && devices.count > 0 ? devices : nil;
}

// Full extraction callback, supporting empty folder creation and automatic parent directory creation
static int file_archive_extract_cb(const char *name, const char *valid_exts, const uint8_t *cdata, unsigned cmode, uint32_t csize, uint32_t size, uint32_t crc32, struct archive_extract_userdata *userdata) {

    char out_path[PATH_MAX_LENGTH];

    // 1. Build the full absolute path
    if (userdata->extraction_directory) {
        fill_pathname_join(out_path, userdata->extraction_directory, name, sizeof(out_path));
    } else {
        strlcpy(out_path, name, sizeof(out_path));
    }

    // 2. Check whether this is a directory entry (ends with / or \)
    size_t len = strlen(name);
    bool is_directory = (len > 0 && (name[len-1] == '/' || name[len-1] == '\\'));

    if (is_directory) {
        // [Key point] For a folder entry, create the directory directly
        // so empty folders are preserved
        if (!path_is_directory(out_path)) {
            path_mkdir(out_path);
        }
        return 1; // Move on to the next entry, skipping the file writing below
    }

    // 3. Handle file entries

    // 3.1 Defensive: check that the parent directory exists
    // Directory entries are handled above, but some ZIPs omit the parent directory entry and give the file directly,
    // or list entries out of order, so checking the parent before each write is a necessary safeguard.
    char parent_dir[PATH_MAX_LENGTH];
    fill_pathname_parent_dir_name(parent_dir, out_path, sizeof(parent_dir));

    if (!path_is_directory(parent_dir)) {
        // Try to create the parent directory
        path_mkdir(parent_dir);
    }

    // 3.2 Write the file data
    // file_archive_perform_mode writes the in-memory cdata to disk
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

    // 1. Prepare the C strings
    const char *cZipPath = [assetsPath fileSystemRepresentation];
    const char *cDestDir = [destPath fileSystemRepresentation];

    // 2. Initialize userdata
    // struct archive_extract_userdata is the data structure passed to the callback
    // file_archive_perform_mode uses its extraction_directory to decide where files are written
    struct archive_extract_userdata userdata;
    memset(&userdata, 0, sizeof(userdata));
    userdata.extraction_directory = cDestDir;

    // [Recommended] Copy the zip path into userdata; some callbacks may use it
    // Note: archive_path is a fixed-size array, so use strlcpy
    strlcpy(userdata.archive_path, cZipPath, sizeof(userdata.archive_path));

    // 3. Initialize the transfer state
    file_archive_transfer_t state;
    memset(&state, 0, sizeof(state));
    state.type = ARCHIVE_TRANSFER_INIT;

    bool success = true;
    int ret = 0;

    do {
        // 3. The path is passed in here as the third argument (cZipPath)
        ret = file_archive_parse_file_iterate(
            &state,
            &success,
            cZipPath,   // <--- This is where the path is actually passed in
            NULL,       // valid_exts
            file_archive_extract_cb,
            &userdata
        );

        // ret == 0 : keep iterating
        // ret == 1 : done
    } while (ret == 0);

    file_archive_parse_file_iterate_stop(&state);

    if (!success) {
        return NO;
    } else {
        // --- Also: generate the compliance notice file dynamically ---
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
            RETROGO_LOGN(GENERAL, "PPSSPP assets extracted, but README.txt could not be created");
        }
        return YES;
    }
}

- (BOOL)exportMameListXMLToPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error {
    void (^fail)(NSString *) = ^(NSString *message) {
        if (error) {
            *error = [NSError errorWithDomain:@"RetroGo.MameListXML" code:-1 userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        RETROGO_LOGE(MAME, "listxml export: %@", message);
    };

    if (![_coreId isEqualToString:@"mame"] || path.length == 0) {
        fail(@"Not the MAME core or empty output path");
        return NO;
    }

    // corePath may point at the framework bundle or directly at its executable.
    NSString *binaryPath = self.corePath;
    if ([binaryPath.pathExtension isEqualToString:@"framework"]) {
        NSString *executable = [NSBundle bundleWithPath:binaryPath].executablePath;
        binaryPath = executable ?: [binaryPath stringByAppendingPathComponent:binaryPath.lastPathComponent.stringByDeletingPathExtension];
    }

    // Same image RetroArch loads for games; dlopen/dlclose only adjust its reference count.
    // Callers must make sure no game is running.
    void *handle = dlopen(binaryPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        const char *reason = dlerror();
        fail([NSString stringWithFormat:@"dlopen failed: %s", reason ? reason : "unknown"]);
        return NO;
    }

    typedef bool (*write_listxml_fn)(const char *path);
    write_listxml_fn writeListXML = (write_listxml_fn)dlsym(handle, "retrogo_mame_write_listxml");
    if (writeListXML == NULL) {
        fail(@"retrogo_mame_write_listxml not exported by this MAME build");
        dlclose(handle);
        return NO;
    }

    NSDate *start = [NSDate date];
    BOOL written = writeListXML(path.fileSystemRepresentation);
    dlclose(handle);
    if (!written) {
        fail([NSString stringWithFormat:@"retrogo_mame_write_listxml failed for %@", path]);
        return NO;
    }

    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    RETROGO_LOGD(MAME, "listxml export: wrote %llu bytes to %@ in %.1fs", [attributes fileSize], path, -[start timeIntervalSinceNow]);
    return YES;
}

#pragma mark - Utils

- (nullable NSDictionary *)loadExtraCoreInfo {
    NSString *jsonFileName = [NSString stringWithFormat:@"%@_extra", _coreId];
    NSString *jsonFilePath = [[NSBundle mainBundle] pathForResource:jsonFileName ofType:@"json" inDirectory:@"Data/jsons/core"];

    NSData *jsonData = [NSData dataWithContentsOfFile:jsonFilePath];

    if(jsonData == nil) {
        return nil;
    }

    NSError *error = nil;
    NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if(error) {
        RETROGO_LOGF(GENERAL, "Failed to parse %{public}@: %{public}@", jsonFileName, error.localizedDescription);
        return nil;
    } else {
        return jsonDict;
    }
}

- (NSURL *)prepareMameStagingDirectoryForGame:(NSURL *)gameURL stagedName:(nullable NSString *)stagedName biosFiles:(NSArray<NSURL *> *)biosFiles links:(nullable NSDictionary<NSString *, NSString *> *)links error:(NSError **)error {
    NSFileManager *manager = [NSFileManager defaultManager];

    // 1. Create a dedicated folder in the temporary directory, e.g. tmp/MameSession
    NSString *tempDir = NSTemporaryDirectory();
    NSURL *stagingDir = [NSURL fileURLWithPath:[tempDir stringByAppendingPathComponent:@"MameSession"]];

    // 2. Clean up the old session directory (to start from a clean state)
    if ([manager fileExistsAtPath:stagingDir.path]) {
        [manager removeItemAtURL:stagingDir error:nil];
    }
    [manager createDirectoryAtURL:stagingDir withIntermediateDirectories:YES attributes:nil error:error];

    // 3. Hard-link the target game ROM into that directory
    NSURL *stagedGameURL = [stagingDir URLByAppendingPathComponent:stagedName.length > 0 ? stagedName : gameURL.lastPathComponent];
    // Note: linkItemAtURL creates a hard link
    if (![manager linkItemAtURL:gameURL toURL:stagedGameURL error:error]) {
        RETROGO_LOGE(MAME, "Failed to link game ROM: %@", *error);
        return nil;
    }

    // 4. Hard-link all BIOS files into that directory

    for (NSURL *biosFile in biosFiles) {
        if (![manager fileExistsAtPath:biosFile.path]) {
            continue;
        }

        NSURL *destination = [stagingDir URLByAppendingPathComponent:biosFile.lastPathComponent];

        // Ignore errors (e.g. the file already exists) and go on to the next link
        [manager linkItemAtURL:biosFile toURL:destination error:nil];
    }

    // 5. Archives found elsewhere in the Library (e.g. the parent set), under the set name MAME looks for.
    //    A BIOS file or the game itself already staged under that name wins.
    [links enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *sourcePath, BOOL *stop) {
        NSURL *destination = [stagingDir URLByAppendingPathComponent:name];
        if ([manager fileExistsAtPath:destination.path]) {
            return;
        }
        // Loose files go into a folder named after their set.
        [manager createDirectoryAtURL:destination.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        NSError *linkError = nil;
        if ([manager linkItemAtURL:[NSURL fileURLWithPath:sourcePath] toURL:destination error:&linkError]) {
            RETROGO_LOGD(MAME, "Session linked %{public}@ from %@", name, sourcePath);
        } else {
            RETROGO_LOGE(MAME, "Session failed to link %{public}@: %@", name, linkError.localizedDescription);
        }
    }];

    RETROGO_LOGI(MAME, "Session staging complete at %@", stagingDir.path);

    // 5. Return the game ROM path in the temporary directory for the core to use
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

- (nullable NSString *)systemDirectoryPath {
    NSString *path = d_systemShowPath;
    if (path.length == 0) {
        return nil;
    }
    if ([path hasPrefix:@"~"]) {
        NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        path = [path stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:docsPath];
    }

    NSFileManager *manager = NSFileManager.defaultManager;
    if (![manager fileExistsAtPath:path]) {
        NSError *error = nil;
        if (![manager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {
            RETROGO_LOGE(IMPORT, "Failed to create system directory %@: %@", path, error.localizedDescription);
            return nil;
        }
    }

    return path;
}

- (BOOL)importSystemFileAtURL:(NSURL *)url fileName:(NSString *)fileName {
    NSString *directory = [self systemDirectoryPath];
    if (directory == nil || fileName.length == 0) {
        return NO;
    }

    NSString *destPath = [directory stringByAppendingPathComponent:fileName];
    NSFileManager *manager = NSFileManager.defaultManager;
    BOOL accessGranted = [url startAccessingSecurityScopedResource];

    if ([manager fileExistsAtPath:destPath]) {
        [manager removeItemAtPath:destPath error:nil];
    }

    NSError *error = nil;
    BOOL success = [manager copyItemAtPath:url.path toPath:destPath error:&error];

    if (accessGranted) {
        [url stopAccessingSecurityScopedResource];
    }

    if (!success) {
        RETROGO_LOGE(IMPORT, "Failed to import BIOS %@ as %{public}@: %@", url.lastPathComponent, fileName, error.localizedDescription);
    }

    return success;
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
