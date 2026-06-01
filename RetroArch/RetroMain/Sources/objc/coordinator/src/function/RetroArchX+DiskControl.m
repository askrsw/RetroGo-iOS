//
//  RetroArchX+DiskControl.m
//  RetroMain
//
//  Created by haharsw on 2026/5/31.
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

#import "RetroArchX+DiskControl.h"

#include <main/runloop.h>
#include <emu/disk_control_interface.h>

static disk_control_interface_t *ra_disk_control(void) {
    runloop_state_t *st = runloop_state_get_ptr();
    if (st == NULL) {
        return NULL;
    }
    return &st->system.disk_control;
}

@implementation RetroArchX (DiskControl)

- (BOOL)diskControlAvailable {
    disk_control_interface_t *d = ra_disk_control();
    if (d == NULL) {
        return NO;
    }
    return disk_control_enabled(d);
}

- (NSUInteger)diskImageCount {
    disk_control_interface_t *d = ra_disk_control();
    if (d == NULL || !disk_control_enabled(d)) {
        return 0;
    }
    return (NSUInteger)disk_control_get_num_images(d);
}

- (NSUInteger)currentDiskImageIndex {
    disk_control_interface_t *d = ra_disk_control();
    if (d == NULL || !disk_control_enabled(d)) {
        return 0;
    }
    return (NSUInteger)disk_control_get_image_index(d);
}

- (nullable NSString *)labelForDiskImageAtIndex:(NSUInteger)index {
    disk_control_interface_t *d = ra_disk_control();
    if (d == NULL || !disk_control_enabled(d)) {
        return nil;
    }
    if (index >= (NSUInteger)disk_control_get_num_images(d)) {
        return nil;
    }
    if (!disk_control_image_label_enabled(d)) {
        return nil;
    }
    char buf[256] = {0};
    disk_control_get_image_label(d, (unsigned)index, buf, sizeof(buf));
    if (buf[0] == '\0') {
        return nil;
    }
    return [NSString stringWithUTF8String:buf];
}

- (BOOL)switchToDiskImageAtIndex:(NSUInteger)index {
    disk_control_interface_t *d = ra_disk_control();
    if (d == NULL || !disk_control_enabled(d)) {
        return NO;
    }
    if (index >= (NSUInteger)disk_control_get_num_images(d)) {
        return NO;
    }
    unsigned target = (unsigned)index;

    if (!disk_control_get_eject_state(d)) {
        if (!disk_control_set_eject_state(d, true, false)) {
            return NO;
        }
    }
    if (!disk_control_set_index(d, target, false)) {
        // Best-effort re-insert so the tray does not stay open after a failure.
        disk_control_set_eject_state(d, false, false);
        return NO;
    }
    return disk_control_set_eject_state(d, false, false);
}

@end
