//
//  EmuInGameMessage.m
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
#import "EmuInGameMessage.h"
#import "RetroArchViewController.h"
#import <main/runloop.h>

NS_ASSUME_NONNULL_BEGIN

@implementation EmuInGameMessage

- (instancetype)initWithMessage:(NSString *)message title:(nullable NSString *)title type:(EmuInGameMessageType)type duration:(CGFloat)duration priority:(NSInteger)priority {
    self = [super init];
    if(self != nil) {
        _message  = message;
        _title    = title;
        _type     = type;
        _duration = 3.5;
        _priority = priority;
    }
    return self;
}

@end

void runloop_msg_queue_push(const char *msg, size_t len, unsigned prio, unsigned duration, bool flush, char *title, enum message_queue_icon icon, enum message_queue_category category) {
    if(string_is_empty(msg)) {
        return;
    }

    if ([(id)apple_platform respondsToSelector:@selector(showInGameMessage:)]) {
        NSString *strMsg   = @(msg);
        NSString *strTitle = string_is_empty(title) ? nil : @(title);
        EmuInGameMessageType type = (EmuInGameMessageType)category;
        EmuInGameMessage *message = [[EmuInGameMessage alloc] initWithMessage:strMsg title:strTitle type:type duration:duration priority:prio];
        [(id)apple_platform showInGameMessage:message];
    }
}

NS_ASSUME_NONNULL_END
