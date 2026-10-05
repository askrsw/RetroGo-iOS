//
//  RAMameCheatEngine.m
//  RetroGo
//
//  Created by haharsw on 2026/9/27.
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

#import "RAMameCheatEngine.h"

#include <dlfcn.h>
#include <stdbool.h>
#include <utils/retro_paths.h>
#include <utils/retrogo_log.h>

typedef int (*mame_cheat_count_fn)(void);
typedef int (*mame_cheat_int_fn)(int);
typedef const char *(*mame_cheat_desc_fn)(int);
typedef bool (*mame_cheat_bool_fn)(int);
typedef bool (*mame_cheat_set_enabled_fn)(int, bool);
typedef bool (*mame_cheat_set_parameter_fn)(int, int);
typedef void (*mame_cheat_set_xml_fn)(const char *, size_t);
typedef bool (*mame_cheat_reload_fn)(void);
typedef unsigned (*mame_cheat_generation_fn)(void);

@interface RAMameCheatEntry ()
@property(nonatomic, assign, readwrite) NSInteger index;
@property(nonatomic, assign, readwrite) RAMameCheatKind kind;
@property(nonatomic, copy, readwrite) NSString *desc;
@property(nonatomic, assign, readwrite) BOOL enabled;
@property(nonatomic, assign, readwrite) NSInteger parameterPosition;
@end

@implementation RAMameCheatEntry

- (NSString *)description {
    return [NSString stringWithFormat:@"#%ld kind=%ld enabled=%d pos=%ld %@",
            (long)_index, (long)_kind, _enabled, (long)_parameterPosition, _desc];
}

@end

@implementation RAMameCheatEngine {
    mame_cheat_count_fn _count;
    mame_cheat_int_fn _kind;
    mame_cheat_desc_fn _desc;
    mame_cheat_bool_fn _isEnabled;
    mame_cheat_int_fn _parameterPosition;
    mame_cheat_set_enabled_fn _setEnabled;
    mame_cheat_set_parameter_fn _setParameter;
    mame_cheat_bool_fn _activate;
    mame_cheat_set_xml_fn _setXML;
    mame_cheat_reload_fn _reload;
    mame_cheat_generation_fn _loadGeneration;
}

+ (nullable instancetype)engineForLoadedCore {
    const char *rawPath = path_get(RARCH_PATH_CORE);
    if (rawPath == NULL || rawPath[0] == '\0') {
        return nil;
    }
    NSString *path = @(rawPath);
    // RARCH_PATH_CORE may name the framework bundle; the loaded image is its executable.
    if ([path.pathExtension isEqualToString:@"framework"]) {
        path = [NSBundle bundleWithPath:path].executablePath
            ?: [path stringByAppendingPathComponent:path.lastPathComponent.stringByDeletingPathExtension];
    }
    // RetroArch loads cores RTLD_LOCAL, so RTLD_DEFAULT cannot see their symbols.
    // RTLD_NOLOAD only returns the image that is already loaded; the extra reference is
    // dropped right away, and the core stays loaded while a game runs.
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_NOLOAD);
    if (handle == NULL) {
        return nil;
    }
    RAMameCheatEngine *engine = [[RAMameCheatEngine alloc] init];
    engine->_count = (mame_cheat_count_fn)dlsym(handle, "retrogo_mame_cheat_count");
    engine->_kind = (mame_cheat_int_fn)dlsym(handle, "retrogo_mame_cheat_kind");
    engine->_desc = (mame_cheat_desc_fn)dlsym(handle, "retrogo_mame_cheat_description");
    engine->_isEnabled = (mame_cheat_bool_fn)dlsym(handle, "retrogo_mame_cheat_is_enabled");
    engine->_parameterPosition = (mame_cheat_int_fn)dlsym(handle, "retrogo_mame_cheat_parameter_position");
    engine->_setEnabled = (mame_cheat_set_enabled_fn)dlsym(handle, "retrogo_mame_cheat_set_enabled");
    engine->_setParameter = (mame_cheat_set_parameter_fn)dlsym(handle, "retrogo_mame_cheat_set_parameter");
    engine->_activate = (mame_cheat_bool_fn)dlsym(handle, "retrogo_mame_cheat_activate");
    engine->_setXML = (mame_cheat_set_xml_fn)dlsym(handle, "retrogo_mame_cheat_set_xml");
    engine->_reload = (mame_cheat_reload_fn)dlsym(handle, "retrogo_mame_cheat_reload");
    engine->_loadGeneration = (mame_cheat_generation_fn)dlsym(handle, "retrogo_mame_cheat_load_generation");
    dlclose(handle);

    if (!engine->_count || !engine->_kind || !engine->_desc || !engine->_isEnabled || !engine->_parameterPosition
        || !engine->_setEnabled || !engine->_setParameter || !engine->_activate || !engine->_setXML || !engine->_reload
        || !engine->_loadGeneration) {
        RETROGO_LOGF(MAME, "Loaded core lacks the retrogo_mame_cheat_* exports: %@", path);
        return nil;
    }
    return engine;
}

- (NSInteger)count {
    return _count();
}

- (NSArray<RAMameCheatEntry *> *)entries {
    int total = _count();
    NSMutableArray<RAMameCheatEntry *> *entries = [NSMutableArray arrayWithCapacity:MAX(total, 0)];
    for (int i = 0; i < total; i++) {
        RAMameCheatEntry *entry = [[RAMameCheatEntry alloc] init];
        entry.index = i;
        entry.kind = (RAMameCheatKind)_kind(i);
        const char *text = _desc(i);
        entry.desc = text ? (@(text) ?: @"") : @"";
        entry.enabled = _isEnabled(i);
        entry.parameterPosition = _parameterPosition(i);
        [entries addObject:entry];
    }
    return entries;
}

- (BOOL)setEnabled:(BOOL)enabled atIndex:(NSInteger)index {
    return _setEnabled((int)index, enabled);
}

- (BOOL)setParameterPosition:(NSInteger)position atIndex:(NSInteger)index {
    return _setParameter((int)index, (int)position);
}

- (BOOL)activateAtIndex:(NSInteger)index {
    return _activate((int)index);
}

- (void)setCheatXML:(nullable NSData *)xml {
    _setXML(xml.length ? (const char *)xml.bytes : NULL, xml.length);
}

- (BOOL)reload {
    return _reload();
}

- (NSUInteger)loadGeneration {
    return _loadGeneration();
}

@end
