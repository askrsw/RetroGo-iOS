//
//  RAInputActionManager.m
//  RetroGo
//
//  Created by Codex on 2026/4/30.
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

#import "RAInputActionManager.h"
#import "RAInputBindingProfile.h"
#import "../RetroArchX.h"

#include <defines/input_defines.h>
#include <input/mfi_joypad.h>
#include <stdatomic.h>
#include <math.h>
#include <os/lock.h>

@interface RAInputActionManager ()
@property(nonatomic, strong) NSMutableDictionary<NSString *, RAInputActionDescriptor *> *actionDescriptors;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *actionIdentifierBySourceIdentifier;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *sourceIdentifierByActionIdentifier;
@property(nonatomic, strong) NSMutableSet<NSString *> *pressedSourceIdentifiers;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastJoypadOutputByActionIdentifier;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *turboFrameIndexByActionIdentifier;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *activePlayerIndexByActionIdentifier;

- (BOOL)hasActionBindingForPhysicalSource:(RAInputPhysicalSource *)source useLock:(BOOL)useLock;
- (RAInputActionHandlingResult)handlePhysicalSource:(RAInputPhysicalSource *)source pressed:(BOOL)pressed useLock:(BOOL)useLock;
- (void)markPendingReconcile;
- (void)notifyTopologyChanged;
@end

static NSInteger RAInputActionManagerResolvePlayerPort(unsigned physicalSlot) {
    settings_t *settings = config_get_ptr();
    if (settings != NULL) {
        for (unsigned playerPort = 0; playerPort < MAX_USERS; playerPort++) {
            if (settings->uints.input_joypad_index[playerPort] == physicalSlot) {
                return (NSInteger)playerPort;
            }
        }
    }

    if (physicalSlot < MAX_USERS) {
        return (NSInteger)physicalSlot;
    }
    return 0;
}

static void RAInputActionManagerMFIButtonEventCallback(unsigned port, uint16_t joykey, bool pressed, const char *display_name, void *userdata) {
    RAInputActionManager *manager = (__bridge RAInputActionManager *)userdata;
    if (manager == nil) {
        return;
    }

    NSString *displayName = display_name != NULL ? @(display_name) : @"";
    NSInteger playerPort = RAInputActionManagerResolvePlayerPort(port);
    RAInputPhysicalSource *source = [RAInputPhysicalSource buttonSourceWithJoykey:joykey displayName:displayName playerIndex:playerPort];
    [manager handlePhysicalSource:source pressed:pressed useLock:YES];
}

static void RAInputActionManagerMFIAxisEventCallback(unsigned port, uint32_t joyaxis, int16_t axis_value, bool pressed, const char *display_name, void *userdata) {
    RAInputActionManager *manager = (__bridge RAInputActionManager *)userdata;
    if (manager == nil) {
        return;
    }

    NSString *displayName = display_name != NULL ? @(display_name) : @"";
    NSInteger playerPort = RAInputActionManagerResolvePlayerPort(port);
    RAInputPhysicalSource *source = [RAInputPhysicalSource axisSourceWithJoyaxis:joyaxis axisValue:(float)axis_value / 32767.0f displayName:displayName playerIndex:playerPort];
    [manager handlePhysicalSource:source pressed:pressed useLock:YES];
}

static bool RAInputActionManagerMFIButtonSuppressionCallback(unsigned port, uint16_t joykey, void *userdata) {
    RAInputActionManager *manager = (__bridge RAInputActionManager *)userdata;
    if (manager == nil) {
        return false;
    }

    NSInteger playerPort = RAInputActionManagerResolvePlayerPort(port);
    RAInputPhysicalSource *source = [RAInputPhysicalSource buttonSourceWithJoykey:joykey displayName:@"" playerIndex:playerPort];
    return [manager hasActionBindingForPhysicalSource:source useLock:YES];
}

static bool RAInputActionManagerMFIAxisSuppressionCallback(unsigned port, uint32_t joyaxis, void *userdata) {
    RAInputActionManager *manager = (__bridge RAInputActionManager *)userdata;
    if (manager == nil) {
        return false;
    }
    if (!manager.allowsAxisSuppression) {
        return false;
    }

    NSInteger playerPort = RAInputActionManagerResolvePlayerPort(port);
    RAInputPhysicalSource *source = [RAInputPhysicalSource axisSourceWithJoyaxis:joyaxis displayName:@"" playerIndex:playerPort];
    return [manager hasActionBindingForPhysicalSource:source useLock:YES];
}

static void RAInputActionManagerMFITopologyChangedCallback(void *userdata) {
    RAInputActionManager *manager = (__bridge RAInputActionManager *)userdata;
    if (!manager) return;
    [manager markPendingReconcile];
    dispatch_async(dispatch_get_main_queue(), ^{
        [manager notifyTopologyChanged];
    });
}

@interface RAInputActionDescriptor ()
@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *displayName;
@property(nonatomic, assign, readwrite) RAInputActionKind kind;
@property(nonatomic, copy, readwrite) NSArray<NSNumber *> *outputJoypadCodes;
@property(nonatomic, assign, readwrite) BOOL turboEnabled;
@end

@implementation RAInputActionDescriptor

+ (instancetype)joypadOutputActionWithIdentifier:(NSString *)identifier displayName:(NSString *)displayName outputJoypadCodes:(NSArray<NSNumber *> *)outputJoypadCodes turboEnabled:(BOOL)turboEnabled {
    RAInputActionDescriptor *descriptor = [[RAInputActionDescriptor alloc] initWithIdentifier:identifier displayName:displayName kind:RAInputActionKindJoypadOutput];
    descriptor.outputJoypadCodes = [outputJoypadCodes copy];
    descriptor.turboEnabled = turboEnabled;
    return descriptor;
}

+ (instancetype)comboActionWithIdentifier:(NSString *)identifier displayName:(NSString *)displayName outputJoypadCodes:(NSArray<NSNumber *> *)outputJoypadCodes {
    return [self comboActionWithIdentifier:identifier displayName:displayName outputJoypadCodes:outputJoypadCodes turboEnabled:YES];
}

+ (instancetype)comboActionWithIdentifier:(NSString *)identifier displayName:(NSString *)displayName outputJoypadCodes:(NSArray<NSNumber *> *)outputJoypadCodes turboEnabled:(BOOL)turboEnabled {
    return [self joypadOutputActionWithIdentifier:identifier displayName:displayName outputJoypadCodes:outputJoypadCodes turboEnabled:turboEnabled];
}

+ (instancetype)turboActionWithIdentifier:(NSString *)identifier displayName:(NSString *)displayName outputJoypadCodes:(NSArray<NSNumber *> *)outputJoypadCodes {
    return [self joypadOutputActionWithIdentifier:identifier displayName:displayName outputJoypadCodes:outputJoypadCodes turboEnabled:YES];
}

+ (instancetype)fastForwardActionWithIdentifier:(NSString *)identifier displayName:(NSString *)displayName {
    RAInputActionDescriptor *descriptor = [[RAInputActionDescriptor alloc] initWithIdentifier:identifier displayName:displayName kind:RAInputActionKindFastForward];
    return descriptor;
}

- (instancetype)initWithIdentifier:(NSString *)identifier displayName:(NSString *)displayName kind:(RAInputActionKind)kind {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _displayName = [displayName copy];
        _kind = kind;
        _outputJoypadCodes = @[];
        _turboEnabled = NO;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    RAInputActionDescriptor *descriptor = [[[self class] allocWithZone:zone] initWithIdentifier:self.identifier displayName:self.displayName kind:self.kind];
    descriptor.outputJoypadCodes = self.outputJoypadCodes;
    descriptor.turboEnabled = self.turboEnabled;
    return descriptor;
}

@end

@interface RAInputPhysicalSource ()
@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *displayName;
@property(nonatomic, assign, readwrite) NSInteger playerIndex;
@property(nonatomic, assign, readwrite) RAInputPhysicalSourceKind kind;
@property(nonatomic, assign, readwrite) uint16_t joykey;
@property(nonatomic, assign, readwrite) uint32_t joyaxis;
@property(nonatomic, assign, readwrite) float axisValue;

+ (uint16_t)joykeyFromIdentifier:(NSString *)identifier;
+ (uint32_t)joyaxisFromIdentifier:(NSString *)identifier;
@end

@implementation RAInputPhysicalSource

+ (instancetype)sourceWithIdentifier:(NSString *)identifier displayName:(NSString *)displayName playerIndex:(NSInteger)playerIndex {
    RAInputPhysicalSourceKind kind = RAInputPhysicalSourceKindButton;
    uint16_t joykey = NO_BTN;
    uint32_t joyaxis = AXIS_NONE;

    if ([identifier hasPrefix:@"mfi:axis:"]) {
        kind = RAInputPhysicalSourceKindAxis;
        joyaxis = [self joyaxisFromIdentifier:identifier];
    } else if ([identifier hasPrefix:@"mfi:button:"]) {
        kind = RAInputPhysicalSourceKindButton;
        joykey = [self joykeyFromIdentifier:identifier];
    }

    RAInputPhysicalSource *source = [[RAInputPhysicalSource alloc] initWithIdentifier:identifier displayName:displayName playerIndex:playerIndex kind:kind joykey:joykey joyaxis:joyaxis axisValue:0];
    return source;
}

+ (instancetype)buttonSourceWithJoykey:(uint16_t)joykey displayName:(NSString *)displayName playerIndex:(NSInteger)playerIndex {
    NSString *identifier = [NSString stringWithFormat:@"mfi:button:%u", joykey];
    return [[RAInputPhysicalSource alloc] initWithIdentifier:identifier displayName:displayName playerIndex:playerIndex kind:RAInputPhysicalSourceKindButton joykey:joykey joyaxis:AXIS_NONE axisValue:0];
}

+ (instancetype)axisSourceWithJoyaxis:(uint32_t)joyaxis displayName:(NSString *)displayName playerIndex:(NSInteger)playerIndex {
    return [self axisSourceWithJoyaxis:joyaxis axisValue:0 displayName:displayName playerIndex:playerIndex];
}

+ (instancetype)axisSourceWithJoyaxis:(uint32_t)joyaxis axisValue:(float)axisValue displayName:(NSString *)displayName playerIndex:(NSInteger)playerIndex {
    NSString *direction = AXIS_NEG_GET(joyaxis) != 0xFFFFU ? @"negative" : @"positive";
    uint32_t axis = AXIS_NEG_GET(joyaxis) != 0xFFFFU ? AXIS_NEG_GET(joyaxis) : AXIS_POS_GET(joyaxis);
    NSString *identifier = [NSString stringWithFormat:@"mfi:axis:%u:%@", axis, direction];
    return [[RAInputPhysicalSource alloc] initWithIdentifier:identifier displayName:displayName playerIndex:playerIndex kind:RAInputPhysicalSourceKindAxis joykey:NO_BTN joyaxis:joyaxis axisValue:axisValue];
}

+ (uint16_t)joykeyFromIdentifier:(NSString *)identifier {
    static NSString * const prefix = @"mfi:button:";
    if (![identifier hasPrefix:prefix]) {
        return NO_BTN;
    }

    NSString *value = [identifier substringFromIndex:prefix.length];
    NSInteger joykey = value.integerValue;
    if (joykey < 0 || joykey >= 32) {
        return NO_BTN;
    }

    return (uint16_t)joykey;
}

+ (uint32_t)joyaxisFromIdentifier:(NSString *)identifier {
    static NSString * const prefix = @"mfi:axis:";
    if (![identifier hasPrefix:prefix]) {
        return AXIS_NONE;
    }

    NSString *payload = [identifier substringFromIndex:prefix.length];
    NSArray<NSString *> *components = [payload componentsSeparatedByString:@":"];
    if (components.count != 2) {
        return AXIS_NONE;
    }

    NSInteger axis = components[0].integerValue;
    if (axis < 0 || axis >= 32) {
        return AXIS_NONE;
    }

    NSString *direction = components[1].lowercaseString;
    if ([direction isEqualToString:@"negative"] || [direction isEqualToString:@"neg"] || [direction isEqualToString:@"-"]) {
        return AXIS_NEG((uint32_t)axis);
    }
    if ([direction isEqualToString:@"positive"] || [direction isEqualToString:@"pos"] || [direction isEqualToString:@"+"]) {
        return AXIS_POS((uint32_t)axis);
    }

    return AXIS_NONE;
}

- (instancetype)initWithIdentifier:(NSString *)identifier displayName:(NSString *)displayName playerIndex:(NSInteger)playerIndex kind:(RAInputPhysicalSourceKind)kind joykey:(uint16_t)joykey joyaxis:(uint32_t)joyaxis axisValue:(float)axisValue {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _displayName = [displayName copy];
        _playerIndex = playerIndex;
        _kind = kind;
        _joykey = joykey;
        _joyaxis = joyaxis;
        _axisValue = axisValue;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] allocWithZone:zone] initWithIdentifier:self.identifier displayName:self.displayName playerIndex:self.playerIndex kind:self.kind joykey:self.joykey joyaxis:self.joyaxis axisValue:self.axisValue];
}

@end

@implementation RAInputActionManager {
    RAInputBindingProfile * _Nullable d_activeBindingProfile;
    RAInputCoreCapabilities * _Nullable d_activeCoreCapabilities;

    os_unfair_lock d_stateLock;
    _Atomic(bool) d_pendingReconcile;
}

+ (instancetype)shared {
    static RAInputActionManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        atomic_store_explicit(&d_pendingReconcile, false, memory_order_relaxed);
        d_stateLock = OS_UNFAIR_LOCK_INIT;

        _actionDescriptors = [NSMutableDictionary dictionary];
        _actionIdentifierBySourceIdentifier = [NSMutableDictionary dictionary];
        _sourceIdentifierByActionIdentifier = [NSMutableDictionary dictionary];
        _pressedSourceIdentifiers = [NSMutableSet set];
        _lastJoypadOutputByActionIdentifier = [NSMutableDictionary dictionary];
        _turboFrameIndexByActionIdentifier = [NSMutableDictionary dictionary];
        _activePlayerIndexByActionIdentifier = [NSMutableDictionary dictionary];
        _turboPeriodFrames = 4;
        _turboDutyFrames = 2;
        _allowsAxisSuppression = YES;
        mfi_joypad_set_button_event_callback(RAInputActionManagerMFIButtonEventCallback, (__bridge void *)self);
        mfi_joypad_set_axis_event_callback(RAInputActionManagerMFIAxisEventCallback, (__bridge void *)self);
        mfi_joypad_set_button_suppression_callback(RAInputActionManagerMFIButtonSuppressionCallback, (__bridge void *)self);
        mfi_joypad_set_axis_suppression_callback(RAInputActionManagerMFIAxisSuppressionCallback, (__bridge void *)self);
        mfi_joypad_set_topology_changed_callback(RAInputActionManagerMFITopologyChangedCallback, (__bridge void *)self);
    }
    return self;
}

- (void)dealloc {
    mfi_joypad_stop_button_event_monitor();
    mfi_joypad_set_axis_suppression_callback(NULL, NULL);
    mfi_joypad_set_button_suppression_callback(NULL, NULL);
    mfi_joypad_set_axis_event_callback(NULL, NULL);
    mfi_joypad_set_button_event_callback(NULL, NULL);
    mfi_joypad_set_topology_changed_callback(NULL, NULL);
}

- (void)beginCoreTeardownGuard {
    // 1) 不再接收“配置页按键捕获”
    self.physicalSourcePressHandler = nil;

    // 2) 清理运行态，确保没有按下残留（turbo/fast-forward 持续态）
    [self resetRuntimeState:YES];

    // 3) 彻底静默 mfi 回调，避免 core unload 期间并发输入
    mfi_joypad_set_axis_suppression_callback(NULL, NULL);
    mfi_joypad_set_button_suppression_callback(NULL, NULL);
    mfi_joypad_set_axis_event_callback(NULL, NULL);
    mfi_joypad_set_button_event_callback(NULL, NULL);
    mfi_joypad_set_topology_changed_callback(NULL, NULL);
}

- (void)endCoreTeardownGuard {
    // 恢复 mfi 回调链，供下次开局使用
    mfi_joypad_set_button_event_callback(RAInputActionManagerMFIButtonEventCallback, (__bridge void *)self);
    mfi_joypad_set_axis_event_callback(RAInputActionManagerMFIAxisEventCallback, (__bridge void *)self);
    mfi_joypad_set_button_suppression_callback(RAInputActionManagerMFIButtonSuppressionCallback, (__bridge void *)self);
    mfi_joypad_set_axis_suppression_callback(RAInputActionManagerMFIAxisSuppressionCallback, (__bridge void *)self);
    mfi_joypad_set_topology_changed_callback(RAInputActionManagerMFITopologyChangedCallback, (__bridge void *)self);
}

- (void)setPhysicalSourcePressHandler:(RAInputPhysicalSourcePressHandler)physicalSourcePressHandler {
    _physicalSourcePressHandler = [physicalSourcePressHandler copy];
    if (_physicalSourcePressHandler != nil) {
        mfi_joypad_start_button_event_monitor();
    } else {
        mfi_joypad_stop_button_event_monitor();
    }
}

- (void)setActionDescriptor:(RAInputActionDescriptor *)descriptor useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (descriptor.identifier.length == 0) {
            return;
        }

        self.actionDescriptors[descriptor.identifier] = [descriptor copy];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (void)removeActionDescriptorForIdentifier:(NSString *)actionIdentifier useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (actionIdentifier.length == 0) {
            return;
        }

        [self unbindActionIdentifier:actionIdentifier useLock:NO];
        [self.actionDescriptors removeObjectForKey:actionIdentifier];
        [self.lastJoypadOutputByActionIdentifier removeObjectForKey:actionIdentifier];
        [self.turboFrameIndexByActionIdentifier removeObjectForKey:actionIdentifier];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (nullable RAInputActionDescriptor *)actionDescriptorForIdentifier:(NSString *)actionIdentifier useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (actionIdentifier.length == 0) {
            return nil;
        }

        return self.actionDescriptors[actionIdentifier];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (void)bindPhysicalSourceIdentifier:(NSString *)sourceIdentifier toActionIdentifier:(NSString *)actionIdentifier useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (sourceIdentifier.length == 0 || actionIdentifier.length == 0) {
            return;
        }

        [self unbindPhysicalSourceIdentifier:sourceIdentifier useLock:NO];
        [self unbindActionIdentifier:actionIdentifier useLock:NO];

        self.actionIdentifierBySourceIdentifier[sourceIdentifier] = actionIdentifier;
        self.sourceIdentifierByActionIdentifier[actionIdentifier] = sourceIdentifier;
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (void)bindPhysicalSource:(RAInputPhysicalSource *)source toActionIdentifier:(NSString *)actionIdentifier useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (source.identifier.length == 0 || actionIdentifier.length == 0) {
            return;
        }

        [self clearJoypadBindingsUsingPhysicalSourceIdentifier:[self bindingIdentifierForPhysicalSource:source] forPort:(int)source.playerIndex useLock:NO];
        [self bindPhysicalSourceIdentifier:[self bindingIdentifierForPhysicalSource:source] toActionIdentifier:actionIdentifier useLock:NO];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (void)unbindPhysicalSourceIdentifier:(NSString *)sourceIdentifier useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (sourceIdentifier.length == 0) {
            return;
        }

        NSString *actionIdentifier = self.actionIdentifierBySourceIdentifier[sourceIdentifier];
        if (actionIdentifier != nil) {
            [self releaseActionIfNeededForIdentifier:actionIdentifier useLock:NO];
            [self.sourceIdentifierByActionIdentifier removeObjectForKey:actionIdentifier];
        }

        [self.actionIdentifierBySourceIdentifier removeObjectForKey:sourceIdentifier];
        [self.pressedSourceIdentifiers removeObject:sourceIdentifier];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (void)unbindActionIdentifier:(NSString *)actionIdentifier useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (actionIdentifier.length == 0) {
            return;
        }

        NSString *sourceIdentifier = self.sourceIdentifierByActionIdentifier[actionIdentifier];
        if (sourceIdentifier != nil) {
            [self.pressedSourceIdentifiers removeObject:sourceIdentifier];
            [self.actionIdentifierBySourceIdentifier removeObjectForKey:sourceIdentifier];
        }

        [self releaseActionIfNeededForIdentifier:actionIdentifier useLock:NO];
        [self.sourceIdentifierByActionIdentifier removeObjectForKey:actionIdentifier];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (void)removeAllBindings:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        [self resetRuntimeState:NO];
        [self.actionIdentifierBySourceIdentifier removeAllObjects];
        [self.sourceIdentifierByActionIdentifier removeAllObjects];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (nullable NSString *)actionIdentifierForPhysicalSourceIdentifier:(NSString *)sourceIdentifier useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (sourceIdentifier.length == 0) {
            return nil;
        }

        return self.actionIdentifierBySourceIdentifier[sourceIdentifier];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (nullable NSString *)physicalSourceIdentifierForActionIdentifier:(NSString *)actionIdentifier useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (actionIdentifier.length == 0) {
            return nil;
        }

        return self.sourceIdentifierByActionIdentifier[actionIdentifier];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (nullable NSString *)physicalSourceDisplayNameForActionIdentifier:(NSString *)actionIdentifier useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        NSString *sourceIdentifier = [self physicalSourceIdentifierForActionIdentifier:actionIdentifier useLock:NO];
        if (sourceIdentifier.length == 0) {
            return nil;
        }

        return [self displayNameForPhysicalSourceIdentifier:sourceIdentifier];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (BOOL)isPhysicalSourceIdentifierUsedByJoypadBindings:(NSString *)sourceIdentifier forPort:(int)port useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (sourceIdentifier.length == 0) {
            return NO;
        }
        if (port < 0 || port >= (int)MAX_USERS) {
            return NO;
        }

        uint16_t joykey = [self joykeyForPhysicalSourceIdentifier:sourceIdentifier];
        uint32_t joyaxis = [self joyaxisForPhysicalSourceIdentifier:sourceIdentifier];
        if ((joykey == NO_BTN || joykey >= 32) && joyaxis == AXIS_NONE) {
            return NO;
        }

        const unsigned playerPort = (unsigned)port;
        for (unsigned code = 0; code < RARCH_FIRST_CUSTOM_BIND; code++) {
            struct retro_keybind *bind = &input_config_binds[playerPort][code];
            const struct retro_keybind *autoBind = input_config_get_bind_auto(playerPort, code);
            if ([self keybind:bind autoBind:autoBind usesJoykey:joykey joyaxis:joyaxis]) {
                return YES;
            }
        }

        return NO;
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (BOOL)isPhysicalSourceIdentifier:(NSString *)sourceIdentifier usedByJoypadCode:(enum RetroArchJoypadCode)joypadCode forPort:(int)port useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (sourceIdentifier.length == 0) {
            return NO;
        }
        if (port < 0 || port >= (int)MAX_USERS) {
            return NO;
        }
        if ((int)joypadCode < 0 || joypadCode >= RARCH_FIRST_CUSTOM_BIND) {
            return NO;
        }

        uint16_t joykey = [self joykeyForPhysicalSourceIdentifier:sourceIdentifier];
        uint32_t joyaxis = [self joyaxisForPhysicalSourceIdentifier:sourceIdentifier];
        if ((joykey == NO_BTN || joykey >= 32) && joyaxis == AXIS_NONE) {
            return NO;
        }

        struct retro_keybind *bind = &input_config_binds[(unsigned)port][(unsigned)joypadCode];
        const struct retro_keybind *autoBind = input_config_get_bind_auto((unsigned)port, (unsigned)joypadCode);
        return [self keybind:bind autoBind:autoBind usesJoykey:joykey joyaxis:joyaxis];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (RAInputActionHandlingResult)handlePhysicalSource:(RAInputPhysicalSource *)source pressed:(BOOL)pressed useLock:(BOOL)useLock {
    if (source.identifier.length == 0) {
        return RAInputActionHandlingResultIgnored;
    }

    if (pressed && self.physicalSourcePressHandler != nil) {
        BOOL consumed = self.physicalSourcePressHandler(source);
        if (consumed) {
            return RAInputActionHandlingResultHandled;
        }
    }

    [self ra_lockState:useLock];
    @try {
        NSString *sourceIdentifier = [self bindingIdentifierForPhysicalSource:source];
        NSString *actionIdentifier = self.actionIdentifierBySourceIdentifier[sourceIdentifier];
        if (actionIdentifier.length == 0) {
            sourceIdentifier = source.identifier;
            actionIdentifier = self.actionIdentifierBySourceIdentifier[sourceIdentifier];
        }
        if (actionIdentifier.length == 0) {
            return RAInputActionHandlingResultIgnored;
        }

        RAInputActionDescriptor *descriptor = self.actionDescriptors[actionIdentifier];
        if (descriptor == nil) {
            return RAInputActionHandlingResultIgnored;
        }

        BOOL wasPressed = [self.pressedSourceIdentifiers containsObject:sourceIdentifier];
        if (wasPressed == pressed) {
            return RAInputActionHandlingResultHandled;
        }

        if (pressed) {
            [self.pressedSourceIdentifiers addObject:sourceIdentifier];
            [self pressAction:descriptor playerIndex:source.playerIndex useLock:NO];
        } else {
            [self.pressedSourceIdentifiers removeObject:sourceIdentifier];
            [self releaseAction:descriptor useLock:NO];
        }
    } @finally {
        [self ra_unlockState:useLock];
    }

    return RAInputActionHandlingResultHandled;
}

- (void)tickFrame:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (d_activeCoreCapabilities && [self consumePendingReconcile]) {
            [self applyInputBindingProfile:d_activeBindingProfile coreCapabilities:d_activeCoreCapabilities useLock:NO];
        }

        if (self.turboPeriodFrames == 0 || self.turboDutyFrames == 0) {
            return;
        }

        NSArray<NSString *> *activeActionIdentifiers = self.turboFrameIndexByActionIdentifier.allKeys;
        for (NSString *actionIdentifier in activeActionIdentifiers) {
            RAInputActionDescriptor *descriptor = self.actionDescriptors[actionIdentifier];
            if (descriptor == nil || !descriptor.turboEnabled) {
                continue;
            }

            NSInteger playerIndex = self.activePlayerIndexByActionIdentifier[actionIdentifier].integerValue;
            NSUInteger frameIndex = self.turboFrameIndexByActionIdentifier[actionIdentifier].unsignedIntegerValue;
            BOOL outputDown = frameIndex < self.turboDutyFrames;
            [self emitExtendedJoypadCodes:descriptor.outputJoypadCodes playerIndex:playerIndex down:outputDown];
            self.lastJoypadOutputByActionIdentifier[actionIdentifier] = @(outputDown);

            NSUInteger nextFrameIndex = (frameIndex + 1) % self.turboPeriodFrames;
            self.turboFrameIndexByActionIdentifier[actionIdentifier] = @(nextFrameIndex);
        }
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (void)resetRuntimeState:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        NSArray<NSString *> *pressedSourceIdentifiers = self.pressedSourceIdentifiers.allObjects;
        for (NSString *sourceIdentifier in pressedSourceIdentifiers) {
            NSString *actionIdentifier = self.actionIdentifierBySourceIdentifier[sourceIdentifier];
            [self releaseActionIfNeededForIdentifier:actionIdentifier useLock:NO];
        }

        [self.pressedSourceIdentifiers removeAllObjects];
        [self.lastJoypadOutputByActionIdentifier removeAllObjects];
        [self.turboFrameIndexByActionIdentifier removeAllObjects];
        [self.activePlayerIndexByActionIdentifier removeAllObjects];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (void)pressAction:(RAInputActionDescriptor *)descriptor playerIndex:(NSInteger)playerIndex useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        self.activePlayerIndexByActionIdentifier[descriptor.identifier] = @(playerIndex);

        switch (descriptor.kind) {
        case RAInputActionKindJoypadOutput:
            if (descriptor.turboEnabled) {
                self.turboFrameIndexByActionIdentifier[descriptor.identifier] = @0;
                [self tickFrame:NO];
            } else {
                [self emitExtendedJoypadCodes:descriptor.outputJoypadCodes playerIndex:playerIndex down:YES];
                self.lastJoypadOutputByActionIdentifier[descriptor.identifier] = @(YES);
            }
            break;
        case RAInputActionKindFastForward:
            if(playerIndex == 0) {
                [self emitFastForward:YES];
            } else {
                [self.activePlayerIndexByActionIdentifier removeObjectForKey:descriptor.identifier];
            }
            break;
        }
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (void)releaseAction:(RAInputActionDescriptor *)descriptor useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        switch (descriptor.kind) {
        case RAInputActionKindJoypadOutput:
        {
            NSInteger playerIndex = self.activePlayerIndexByActionIdentifier[descriptor.identifier].integerValue;
            if (descriptor.turboEnabled || self.lastJoypadOutputByActionIdentifier[descriptor.identifier] != nil) {
                [self emitExtendedJoypadCodes:descriptor.outputJoypadCodes playerIndex:playerIndex down:NO];
            }
            [self.lastJoypadOutputByActionIdentifier removeObjectForKey:descriptor.identifier];
            [self.turboFrameIndexByActionIdentifier removeObjectForKey:descriptor.identifier];
            [self.activePlayerIndexByActionIdentifier removeObjectForKey:descriptor.identifier];
            break;
        }
        case RAInputActionKindFastForward:
            {
                NSInteger playerIndex = self.activePlayerIndexByActionIdentifier[descriptor.identifier].integerValue;
                if (playerIndex == 0) {
                    [self emitFastForward:NO];
                }
                [self.activePlayerIndexByActionIdentifier removeObjectForKey:descriptor.identifier];
                break;
            }
        }
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (void)releaseActionIfNeededForIdentifier:(nullable NSString *)actionIdentifier useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (actionIdentifier.length == 0) {
            return;
        }

        RAInputActionDescriptor *descriptor = self.actionDescriptors[actionIdentifier];
        if (descriptor == nil) {
            return;
        }

        [self releaseAction:descriptor useLock:NO];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (void)emitExtendedJoypadCodes:(NSArray<NSNumber *> *)joypadCodes playerIndex:(NSInteger)playerIndex down:(BOOL)down {
    if (playerIndex < 0) return;

    for (NSNumber *value in joypadCodes) {
        enum RetroArchJoypadCode code = (enum RetroArchJoypadCode)value.intValue;
        if (code == RetroArchJoypadCodeNone) {
            continue;
        }
        virtual_joypad_set_button_for_port((unsigned)playerIndex, (unsigned)code, down);
    }
}

- (void)emitFastForward:(BOOL)enabled {
    double value = enabled ? 2.0 : 1.0;
    if (enabled) {
        RAInputFastForwardMultiplierProvider provider = self.fastForwardMultiplierProvider;
        if (provider != nil) {
            value = provider();
        }

        if (!isfinite(value) || value <= 0) {
            value = 2.0;
        }
    }

    [[RetroArchX shared] setFastForwardEnabled:enabled multiplier:value];
}

- (BOOL)bindJoypadCode:(enum RetroArchJoypadCode)joypadCode toPhysicalSource:(RAInputPhysicalSource *)source forPort:(int)port useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (source.identifier.length == 0) {
            return NO;
        }
        if (port < 0 || port >= (int)MAX_USERS) {
            return NO;
        }
        if ((int)source.playerIndex != port) {
            return NO;
        }
        if ((int)joypadCode < 0 || joypadCode >= RARCH_FIRST_CUSTOM_BIND) {
            return NO;
        }

        uint16_t joykey = source.kind == RAInputPhysicalSourceKindButton ? source.joykey : NO_BTN;
        uint32_t joyaxis = source.kind == RAInputPhysicalSourceKindAxis ? source.joyaxis : AXIS_NONE;
        if ((joykey == NO_BTN || joykey >= 32) && joyaxis == AXIS_NONE) {
            return NO;
        }

        const unsigned playerPort = (unsigned)port;
        const unsigned targetCode = (unsigned)joypadCode;

        [self unbindPhysicalSourceIdentifier:[self bindingIdentifierForPhysicalSource:source] useLock:NO];
        [self unbindPhysicalSourceIdentifier:source.identifier useLock:NO];

        for (unsigned code = 0; code < RARCH_FIRST_CUSTOM_BIND; code++) {
            if (code == targetCode) {
                continue;
            }

            struct retro_keybind *bind = &input_config_binds[playerPort][code];
            const struct retro_keybind *autoBind = input_config_get_bind_auto(playerPort, code);
            if ([self keybind:bind autoBind:autoBind usesJoykey:joykey joyaxis:joyaxis]) {
                input_config_binds[playerPort][code].joykey = NO_BTN;
                input_config_binds[playerPort][code].joyaxis = AXIS_NONE;
                input_config_binds[playerPort][code].valid = false;
            }
        }

        input_config_binds[playerPort][targetCode].joykey = joyaxis == AXIS_NONE ? joykey : NO_BTN;
        input_config_binds[playerPort][targetCode].joyaxis = joyaxis;
        input_config_binds[playerPort][targetCode].valid = true;
        return YES;
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (NSString *)bindingIdentifierForPhysicalSource:(RAInputPhysicalSource *)source {
    return [NSString stringWithFormat:@"port:%ld:%@", (long)source.playerIndex, source.identifier];
}

- (BOOL)hasActionBindingForPhysicalSource:(RAInputPhysicalSource *)source useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (source.identifier.length == 0) {
            return NO;
        }

        NSString *sourceIdentifier = [self bindingIdentifierForPhysicalSource:source];
        NSString *actionIdentifier = self.actionIdentifierBySourceIdentifier[sourceIdentifier];
        if (actionIdentifier.length > 0 && self.actionDescriptors[actionIdentifier] != nil) {
            return YES;
        }

        actionIdentifier = self.actionIdentifierBySourceIdentifier[source.identifier];
        return actionIdentifier.length > 0 && self.actionDescriptors[actionIdentifier] != nil;
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (BOOL)keybind:(const struct retro_keybind *)bind autoBind:(const struct retro_keybind *)autoBind usesJoykey:(uint16_t)joykey joyaxis:(uint32_t)joyaxis {
    if (bind == NULL || !bind->valid) {
        return NO;
    }

    BOOL hasExplicitJoykey = bind->joykey != NO_BTN;
    BOOL hasExplicitJoyaxis = bind->joyaxis != AXIS_NONE;
    if (hasExplicitJoykey || hasExplicitJoyaxis) {
        BOOL usesJoykey = joykey != NO_BTN && hasExplicitJoykey && bind->joykey == joykey;
        BOOL usesJoyaxis = joyaxis != AXIS_NONE && hasExplicitJoyaxis && bind->joyaxis == joyaxis;
        return usesJoykey || usesJoyaxis;
    }

    if (autoBind == NULL) {
        return NO;
    }

    BOOL usesAutoJoykey = joykey != NO_BTN && autoBind->joykey == joykey;
    BOOL usesAutoJoyaxis = joyaxis != AXIS_NONE && autoBind->joyaxis == joyaxis;
    return usesAutoJoykey || usesAutoJoyaxis;
}

- (NSString *)rawSourceIdentifierFromBindingIdentifier:(NSString *)bindingIdentifier {
    static NSString * const prefix = @"port:";
    if (![bindingIdentifier hasPrefix:prefix]) {
        return bindingIdentifier;
    }

    NSRange separatorRange = [bindingIdentifier rangeOfString:@":" options:0 range:NSMakeRange(prefix.length, bindingIdentifier.length - prefix.length)];
    if (separatorRange.location == NSNotFound || separatorRange.location + 1 >= bindingIdentifier.length) {
        return bindingIdentifier;
    }

    return [bindingIdentifier substringFromIndex:separatorRange.location + 1];
}

- (NSDictionary<NSNumber *, NSString *> *)joypadBindingDisplayNamesForPort:(int)port useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        settings_t *settings = config_get_ptr();
        if (settings == nil) {
            return @{};
        }
        if (port < 0 || port >= (int)MAX_USERS) {
            return @{};
        }

        NSMutableDictionary<NSNumber *, NSString *> *result = [NSMutableDictionary dictionary];
        const unsigned playerPort = (unsigned)port;
        const unsigned joypadCodes[] = {
            RETRO_DEVICE_ID_JOYPAD_B,
            RETRO_DEVICE_ID_JOYPAD_Y,
            RETRO_DEVICE_ID_JOYPAD_SELECT,
            RETRO_DEVICE_ID_JOYPAD_START,
            RETRO_DEVICE_ID_JOYPAD_UP,
            RETRO_DEVICE_ID_JOYPAD_DOWN,
            RETRO_DEVICE_ID_JOYPAD_LEFT,
            RETRO_DEVICE_ID_JOYPAD_RIGHT,
            RETRO_DEVICE_ID_JOYPAD_A,
            RETRO_DEVICE_ID_JOYPAD_X,
            RETRO_DEVICE_ID_JOYPAD_L,
            RETRO_DEVICE_ID_JOYPAD_R,
            RETRO_DEVICE_ID_JOYPAD_L2,
            RETRO_DEVICE_ID_JOYPAD_R2,
            RETRO_DEVICE_ID_JOYPAD_L3,
            RETRO_DEVICE_ID_JOYPAD_R3
        };

        for (size_t i = 0; i < sizeof(joypadCodes) / sizeof(joypadCodes[0]); i++) {
            const unsigned code = joypadCodes[i];
            if (code >= RARCH_BIND_LIST_END) {
                continue;
            }

        char buffer[128];
        buffer[0] = '\0';
        const struct retro_keybind *bind = &input_config_binds[playerPort][code];
        const struct retro_keybind *autoBind = input_config_get_bind_auto(playerPort, code);
        if (!bind->valid) {
            continue;
        }

        if (bind->joykey != NO_BTN) {
            NSString *displayName = [self displayNameForMFIJoykey:bind->joykey];
            if (displayName.length > 0) {
                result[@((NSInteger)code)] = displayName;
                continue;
            }
        }

        uint32_t joyaxis = bind->joyaxis;
        if (joyaxis == AXIS_NONE && autoBind != NULL) {
            joyaxis = autoBind->joyaxis;
        }
        if (joyaxis != AXIS_NONE) {
            NSString *displayName = [self displayNameForMFIJoyaxis:joyaxis];
            if (displayName.length > 0) {
                result[@((NSInteger)code)] = displayName;
                continue;
            }
        }

        input_config_get_bind_string(settings, buffer, bind, autoBind, sizeof(buffer));

        if (buffer[0] == '\0') {
            continue;
        }

            result[@((NSInteger)code)] = @(buffer);
        }

        return [result copy];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (uint16_t)joykeyForPhysicalSourceIdentifier:(NSString *)sourceIdentifier {
    return [RAInputPhysicalSource joykeyFromIdentifier:[self rawSourceIdentifierFromBindingIdentifier:sourceIdentifier]];
}

- (uint32_t)joyaxisForPhysicalSourceIdentifier:(NSString *)sourceIdentifier {
    return [RAInputPhysicalSource joyaxisFromIdentifier:[self rawSourceIdentifierFromBindingIdentifier:sourceIdentifier]];
}

- (void)clearJoypadBindingsUsingPhysicalSourceIdentifier:(NSString *)sourceIdentifier forPort:(int)port useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (sourceIdentifier.length == 0) {
            return;
        }
        if (port < 0 || port >= (int)MAX_USERS) {
            return;
        }

        uint16_t joykey = [self joykeyForPhysicalSourceIdentifier:sourceIdentifier];
        uint32_t joyaxis = [self joyaxisForPhysicalSourceIdentifier:sourceIdentifier];
        if ((joykey == NO_BTN || joykey >= 32) && joyaxis == AXIS_NONE) {
            return;
        }

        const unsigned playerPort = (unsigned)port;
        for (unsigned code = 0; code < RARCH_FIRST_CUSTOM_BIND; code++) {
            struct retro_keybind *bind = &input_config_binds[playerPort][code];
            const struct retro_keybind *autoBind = input_config_get_bind_auto(playerPort, code);
            if ([self keybind:bind autoBind:autoBind usesJoykey:joykey joyaxis:joyaxis]) {
                bind->joykey = NO_BTN;
                bind->joyaxis = AXIS_NONE;
                bind->valid = false;
            }
        }
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (nullable NSString *)displayNameForPhysicalSourceIdentifier:(NSString *)sourceIdentifier {
    uint16_t joykey = [self joykeyForPhysicalSourceIdentifier:sourceIdentifier];
    if (joykey != NO_BTN) {
        return [self displayNameForMFIJoykey:joykey];
    }

    uint32_t joyaxis = [self joyaxisForPhysicalSourceIdentifier:sourceIdentifier];
    if (joyaxis != AXIS_NONE) {
        return [self displayNameForMFIJoyaxis:joyaxis];
    }

    return nil;
}

- (nullable NSString *)displayNameForPhysicalSourceIdentifier:(NSString *)sourceIdentifier useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        return [self displayNameForPhysicalSourceIdentifier:sourceIdentifier];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (nullable NSString *)displayNameForMFIJoykey:(uint16_t)joykey {
    switch (joykey) {
    case RETRO_DEVICE_ID_JOYPAD_B:
        return @"A";
    case RETRO_DEVICE_ID_JOYPAD_A:
        return @"B";
    case RETRO_DEVICE_ID_JOYPAD_Y:
        return @"X";
    case RETRO_DEVICE_ID_JOYPAD_X:
        return @"Y";
    case RETRO_DEVICE_ID_JOYPAD_SELECT:
        return @"Select";
    case RETRO_DEVICE_ID_JOYPAD_START:
        return @"Menu";
    case RETRO_DEVICE_ID_JOYPAD_UP:
        return @"Up";
    case RETRO_DEVICE_ID_JOYPAD_DOWN:
        return @"Down";
    case RETRO_DEVICE_ID_JOYPAD_LEFT:
        return @"Left";
    case RETRO_DEVICE_ID_JOYPAD_RIGHT:
        return @"Right";
    case RETRO_DEVICE_ID_JOYPAD_L:
        return @"L1";
    case RETRO_DEVICE_ID_JOYPAD_R:
        return @"R1";
    case RETRO_DEVICE_ID_JOYPAD_L2:
        return @"L2";
    case RETRO_DEVICE_ID_JOYPAD_R2:
        return @"R2";
    case RETRO_DEVICE_ID_JOYPAD_L3:
        return @"L3";
    case RETRO_DEVICE_ID_JOYPAD_R3:
        return @"R3";
    default:
        return nil;
    }
}

- (nullable NSString *)displayNameForMFIJoyaxis:(uint32_t)joyaxis {
    BOOL isNegative = AXIS_NEG_GET(joyaxis) != 0xFFFFU;
    BOOL isPositive = AXIS_POS_GET(joyaxis) != 0xFFFFU;
    if (!isNegative && !isPositive) {
        return nil;
    }

    uint32_t axis = isNegative ? AXIS_NEG_GET(joyaxis) : AXIS_POS_GET(joyaxis);
    NSString *direction = isNegative ? @"-" : @"+";

    switch (axis) {
    case 0:
        return isNegative ? @"Left Stick Left" : @"Left Stick Right";
    case 1:
        return isNegative ? @"Left Stick Down" : @"Left Stick Up";
    case 2:
        return isNegative ? @"Right Stick Left" : @"Right Stick Right";
    case 3:
        return isNegative ? @"Right Stick Down" : @"Right Stick Up";
    case 4:
        return isNegative ? @"L2 Axis -" : @"L2 Axis +";
    case 5:
        return isNegative ? @"R2 Axis -" : @"R2 Axis +";
    default:
        return [NSString stringWithFormat:@"Axis %u %@", axis, direction];
    }
}

#pragma mark - Bind Setting

- (void)notifyTopologyChanged {
    RAInputTopologyChangedHandler handler = self.topologyChangedHandler;
    if (handler) {
        handler();
    }
}

- (void)markPendingReconcile {
    // 任意线程可调用：设置“需要重收敛”
    atomic_store_explicit(&d_pendingReconcile, true, memory_order_release);
}

- (BOOL)consumePendingReconcile {
    // 仅 tickFrame 线程消费：若为 true 则原子清零并返回 true
    return atomic_exchange_explicit(&d_pendingReconcile, false, memory_order_acq_rel);
}

- (void)resetBindingsToDefaultForPort:(int)port useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (port < 0 || port >= (int)MAX_USERS) {
            return;
        }

        unsigned p = (unsigned)port;

        // 1) 清该 player 的 native 显式覆盖，回到 auto-bind baseline
        for (unsigned code = 0; code < RARCH_FIRST_CUSTOM_BIND; code++) {
            input_config_binds[p][code].joykey  = NO_BTN;
            input_config_binds[p][code].joyaxis = AXIS_NONE;
            input_config_binds[p][code].valid   = true;
        }

        // 2) 清该 player 的扩展 action 绑定（只清 overlay/persisted/default:auto，保留其它玩家）
        NSMutableArray<NSString *> *toRemove = [NSMutableArray array];

        NSString *overlayPrefix   = [NSString stringWithFormat:@"player:%d:overlay:", port];
        NSString *defaultPrefix   = [NSString stringWithFormat:@"default:auto:p%d:", port];

        for (NSString *actionId in self.actionDescriptors.allKeys) {
            if ([actionId hasPrefix:overlayPrefix] ||
                [actionId hasPrefix:defaultPrefix]) {
                [toRemove addObject:actionId];
            }
        }

        for (NSString *actionId in toRemove) {
            [self removeActionDescriptorForIdentifier:actionId useLock:NO];
        }

        // 3) 按当前核心能力补默认 XY->turbo（如果允许）
        RAInputCoreCapabilities *caps = d_activeCoreCapabilities;
        if (caps == nil) {
            caps = [RAInputCoreCapabilities new];
        }
        [self ra_reconcileDefaultTurboXYWithCapabilities:caps useLock:NO];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (nullable RAInputBindingProfile *)exportInputBindingProfileUseLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        RAInputBindingProfile *profile = [[RAInputBindingProfile alloc] init];
        profile.version = 1;

        NSMutableArray<RAInputPlayerBinding *> *players = [NSMutableArray array];

        for (NSInteger port = 0; port < (NSInteger)MAX_USERS; port++) {
            unsigned p = (unsigned)port;
            NSMutableArray<RAInputBindingEntry *> *entries = [NSMutableArray array];
            NSMutableSet<NSString *> *dedupe = [NSMutableSet set];

            NSString* (^signatureForEntry)(RAInputPhysicalSourceRef *, RAInputBindingTarget *, NSString *) = ^NSString *(RAInputPhysicalSourceRef *source, RAInputBindingTarget *target, NSString *actionId) {
                NSString *codes = @"";
                if (target.joypadCodes.count > 0) {
                    NSMutableArray<NSString *> *tmp = [NSMutableArray arrayWithCapacity:target.joypadCodes.count];
                    for (NSNumber *n in target.joypadCodes) {
                        [tmp addObject:n.stringValue];
                    }
                    codes = [tmp componentsJoinedByString:@","];
                }
                return [NSString stringWithFormat:@"%ld|%ld|%ld|%@|%d|%ld|%@",
                        (long)source.sourceKind,
                        (long)source.sourceCode,
                        (long)target.targetKind,
                        codes,
                        target.turboEnabled ? 1 : 0,
                        (long)target.systemActionCode,
                        actionId ?: @""];
            };

            void (^addEntryIfNeeded)(RAInputPhysicalSourceRef *, RAInputBindingTarget *, NSString *) = ^(RAInputPhysicalSourceRef *source, RAInputBindingTarget *target, NSString *actionId) {
                if (!source || !target) return;
                NSString *sig = signatureForEntry(source, target, actionId);
                if ([dedupe containsObject:sig]) return;
                [dedupe addObject:sig];

                RAInputBindingEntry *entry = [[RAInputBindingEntry alloc] init];
                entry.source = source;
                entry.target = target;
                entry.actionId = actionId ?: @"";
                [entries addObject:entry];
            };

            // 1) Native explicit overrides (only non-default overrides)
            for (unsigned code = 0; code < RARCH_FIRST_CUSTOM_BIND; code++) {
                const struct retro_keybind *bind = &input_config_binds[p][code];
                if (!bind->valid) continue;

                BOOL hasExplicitJoykey = (bind->joykey != NO_BTN);
                BOOL hasExplicitJoyaxis = (bind->joyaxis != AXIS_NONE);
                if (!hasExplicitJoykey && !hasExplicitJoyaxis) continue;

                RAInputPhysicalSourceRef *source = [[RAInputPhysicalSourceRef alloc] init];
                if (hasExplicitJoykey) {
                    source.sourceKind = RAInputPhysicalSourceKindCodeButton;
                    source.sourceCode = (NSInteger)bind->joykey;
                } else {
                    source.sourceKind = RAInputPhysicalSourceKindCodeAxis;
                    source.sourceCode = (NSInteger)bind->joyaxis;
                }

                RAInputBindingTarget *target = [[RAInputBindingTarget alloc] init];
                target.targetKind = RAInputBindingTargetKindJoypadSingle;
                target.joypadCodes = @[ @((NSInteger)code) ];
                target.turboEnabled = NO;
                target.systemActionCode = RAInputSystemActionCodeUnknown;

                addEntryIfNeeded(source, target, @"");
            }

            // 2) Extended actions (overlay only), exclude default:auto
            [self.sourceIdentifierByActionIdentifier enumerateKeysAndObjectsUsingBlock:^(NSString *actionId, NSString *sourceIdentifier, BOOL *stop) {
                if (actionId.length == 0 || sourceIdentifier.length == 0) return;
                if ([actionId hasPrefix:@"default:auto:"]) return;

                RAInputActionDescriptor *descriptor = self.actionDescriptors[actionId];
                if (!descriptor) return;

                NSString *overlayPrefix   = [NSString stringWithFormat:@"player:%ld:overlay:", (long)port];
                BOOL isOverlay   = [actionId hasPrefix:overlayPrefix];

                // overlay 只导出“扩展动作”：fast-forward / combo / turbo(含单键 turbo)
                BOOL shouldExportOverlay = NO;
                if (isOverlay) {
                    if (descriptor.kind == RAInputActionKindFastForward) {
                        shouldExportOverlay = YES;
                    } else if (descriptor.kind == RAInputActionKindJoypadOutput) {
                        NSUInteger outputCount = descriptor.outputJoypadCodes.count;
                        shouldExportOverlay = descriptor.turboEnabled || outputCount > 1;
                    }
                }

                if (!shouldExportOverlay) {
                    return;
                }

                NSString *rawSource = [self rawSourceIdentifierFromBindingIdentifier:sourceIdentifier];
                uint16_t joykey = [RAInputPhysicalSource joykeyFromIdentifier:rawSource];
                uint32_t joyaxis = [RAInputPhysicalSource joyaxisFromIdentifier:rawSource];

                RAInputPhysicalSourceRef *source = [[RAInputPhysicalSourceRef alloc] init];
                if (joykey != NO_BTN) {
                    source.sourceKind = RAInputPhysicalSourceKindCodeButton;
                    source.sourceCode = (NSInteger)joykey;
                } else if (joyaxis != AXIS_NONE) {
                    source.sourceKind = RAInputPhysicalSourceKindCodeAxis;
                    source.sourceCode = (NSInteger)joyaxis;
                } else {
                    return;
                }

                RAInputBindingTarget *target = [[RAInputBindingTarget alloc] init];

                if (descriptor.kind == RAInputActionKindFastForward) {
                    target.targetKind = RAInputBindingTargetKindSystemAction;
                    target.joypadCodes = @[];
                    target.turboEnabled = NO;
                    target.systemActionCode = RAInputSystemActionCodeFastForward;
                    addEntryIfNeeded(source, target, actionId);
                    return;
                }

                // Joypad output
                NSMutableArray<NSNumber *> *codes = [NSMutableArray array];
                for (NSNumber *n in descriptor.outputJoypadCodes) {
                    NSInteger c = n.integerValue;
                    if (c != RetroArchJoypadCodeNone) {
                        [codes addObject:@(c)];
                    }
                }
                if (codes.count == 0) return;

                BOOL shouldBeComposite = descriptor.turboEnabled || (codes.count > 1);
                target.targetKind = shouldBeComposite
                    ? RAInputBindingTargetKindJoypadComposite
                    : RAInputBindingTargetKindJoypadSingle;
                target.joypadCodes = codes;
                target.turboEnabled = descriptor.turboEnabled;
                target.systemActionCode = RAInputSystemActionCodeUnknown;

                addEntryIfNeeded(source, target, actionId);
            }];

            if (entries.count > 0) {
                RAInputPlayerBinding *player = [[RAInputPlayerBinding alloc] init];
                player.port = port;
                player.entries = entries;
                [players addObject:player];
            }
        }

        if(players.count == 0) {
            return nil;
        } else {
            profile.players = players;
            return profile;
        }
    } @finally {
        [self ra_unlockState:useLock];
    }
}


- (BOOL)hasNonDefaultBindingsForPort:(int)port useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        if (port < 0 || port >= (int)MAX_USERS) return NO;

        const unsigned p = (unsigned)port;

        // 1) 检查 native bind 是否有显式覆盖（偏离 auto baseline）
        for (unsigned code = 0; code < RARCH_FIRST_CUSTOM_BIND; code++) {
            const struct retro_keybind *bind = &input_config_binds[p][code];
            if (!bind->valid) continue;

            if (bind->joykey != NO_BTN || bind->joyaxis != AXIS_NONE) {
                return YES;
            }
        }

        // 2) 检查扩展 action 绑定（只看该 player 相关，排除 default:auto）
        NSString *prefixOverlay = [NSString stringWithFormat:@"player:%d:overlay:", port];

        for (NSString *actionId in self.actionDescriptors) {
            if ([actionId hasPrefix:@"default:auto:"]) continue;

            BOOL hit = [actionId hasPrefix:prefixOverlay];

            if (!hit) continue;

            NSString *sourceId = self.sourceIdentifierByActionIdentifier[actionId];
            if (sourceId.length > 0) return YES;
        }

        return NO;
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (void)applyInputBindingProfile:(nullable RAInputBindingProfile *)profile coreCapabilities:(RAInputCoreCapabilities *)capabilities useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        d_activeBindingProfile   = profile;
        d_activeCoreCapabilities = capabilities;

        if (capabilities == nil) {
            capabilities = [RAInputCoreCapabilities new];
        }

        // Core capability -> axis suppression policy (统一在这里收敛)
        self.allowsAxisSuppression = !capabilities.supportsAnalog;

        // 1) 清理运行态，避免按压残留
        [self resetRuntimeState:NO];

        // 2) 清理上一局自动扩展绑定（只清 default:auto:*）
        [self ra_removeAutoExtendedBindings:NO];

        // 3) 重置 native 显式覆盖层，让 auto bind 成为 baseline
        [self ra_resetJoypadOverridesToAutoBindBaseline:NO];

        // 4) 清理并重建扩展动作绑定（persisted 由当前 profile 重新注入）
        [self removeAllBindings:NO];

        for (RAInputPlayerBinding *player in profile.players) {
            NSInteger port = player.port;
            if (port < 0 || port >= (NSInteger)MAX_USERS) {
                continue;
            }

            NSInteger idx = 0;
            for (RAInputBindingEntry *entry in player.entries) {
                RAInputPhysicalSource *source = [self ra_sourceFromRef:entry.source port:port];
                RAInputBindingTarget *target  = entry.target;
                if (source == nil || target == nil) {
                    idx++;
                    continue;
                }

                switch (target.targetKind) {
                case RAInputBindingTargetKindJoypadSingle: {
                    if (target.joypadCodes.count != 1) {
                        break;
                    }

                    enum RetroArchJoypadCode code = (enum RetroArchJoypadCode)target.joypadCodes.firstObject.intValue;
                    if (code != RetroArchJoypadCodeNone) {
                        [self bindJoypadCode:code toPhysicalSource:source forPort:(int)port useLock:NO];
                    }
                    break;
                }

                case RAInputBindingTargetKindJoypadComposite: {
                    NSMutableArray<NSNumber *> *codes = [NSMutableArray array];
                    for (NSNumber *n in target.joypadCodes) {
                        enum RetroArchJoypadCode c = (enum RetroArchJoypadCode)n.intValue;
                        if (c != RetroArchJoypadCodeNone) {
                            [codes addObject:@((int)c)];
                        }
                    }
                    if (codes.count == 0) {
                        break;
                    }

                    NSString *actionId = entry.actionId;
                    if (actionId.length == 0) {
                        actionId = [NSString stringWithFormat:@"player:%ld:overlay:unknown:%ld", (long)port, (long)idx];
                    }
                    RAInputActionDescriptor *descriptor =
                    [RAInputActionDescriptor joypadOutputActionWithIdentifier:actionId displayName:actionId outputJoypadCodes:codes turboEnabled:target.turboEnabled];
                    [self setActionDescriptor:descriptor useLock:NO];
                    [self bindPhysicalSource:source toActionIdentifier:descriptor.identifier useLock:NO];
                    break;
                }

                case RAInputBindingTargetKindSystemAction: {
                    if (target.systemActionCode == RAInputSystemActionCodeFastForward) {
                        // 规则：只允许 player 1 (port 0)
                        if (port != 0) {
                            break;
                        }

                        NSString *actionId = entry.actionId;
                        if (actionId.length == 0) {
                            actionId = [NSString stringWithFormat:@"player:%ld:overlay:fast:fast_forward", (long)port];
                        }
                        RAInputActionDescriptor *descriptor =
                        [RAInputActionDescriptor fastForwardActionWithIdentifier:actionId displayName:actionId];
                        [self setActionDescriptor:descriptor useLock:NO];
                        [self bindPhysicalSource:source toActionIdentifier:descriptor.identifier useLock:NO];
                    } else if (target.systemActionCode == RAInputSystemActionCodeMute) {
                        // 预留：后续可接 mute descriptor
                    }
                    break;
                }

                default:
                    break;
            }

                idx++;
            }
        }

        // 5) 最后收敛默认 XY->turbo（只补缺，不覆盖用户配置）
        [self ra_reconcileDefaultTurboXYWithCapabilities:capabilities useLock:NO];
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (void)ra_resetJoypadOverridesToAutoBindBaseline:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        // 保留 valid=true，仅清 joykey/joyaxis 显式覆盖，使 auto bind 生效
        for (unsigned p = 0; p < MAX_USERS; p++) {
            for (unsigned code = 0; code < RARCH_FIRST_CUSTOM_BIND; code++) {
                input_config_binds[p][code].joykey  = NO_BTN;
                input_config_binds[p][code].joyaxis = AXIS_NONE;
                input_config_binds[p][code].valid   = true;
            }
        }
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (void)ra_removeAutoExtendedBindings:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        NSArray<NSString *> *allIds = self.actionDescriptors.allKeys.copy;
        for (NSString *actionId in allIds) {
            if ([actionId hasPrefix:@"default:auto:"]) {
                [self removeActionDescriptorForIdentifier:actionId useLock:NO];
            }
        }
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (void)ra_reconcileDefaultTurboXYWithCapabilities:(RAInputCoreCapabilities *)capabilities useLock:(BOOL)useLock {
    [self ra_lockState:useLock];
    @try {
        // 先清理所有端口的 default:auto turbo 绑定，避免跨游戏/跨核心残留
        for (unsigned port = 0; port < MAX_USERS; port++) {
            NSString *turboAId = [NSString stringWithFormat:@"default:auto:p%u:turbo:a", port];
            NSString *turboBId = [NSString stringWithFormat:@"default:auto:p%u:turbo:b", port];
            [self removeActionDescriptorForIdentifier:turboAId useLock:NO];
            [self removeActionDescriptorForIdentifier:turboBId useLock:NO];
        }

        if (!capabilities.allowsDefaultTurboXYHijack) {
            return;
        }

        // 对每个 player 独立补位 XY->turbo AB
        for (unsigned port = 0; port < MAX_USERS; port++) {
            NSString *turboAId = [NSString stringWithFormat:@"default:auto:p%u:turbo:a", port];
            NSString *turboBId = [NSString stringWithFormat:@"default:auto:p%u:turbo:b", port];

            NSString *srcX = [self ra_portScopedSourceIdentifierForButtonCode:RetroArchJoypadCodeX port:(NSInteger)port];
            NSString *srcY = [self ra_portScopedSourceIdentifierForButtonCode:RetroArchJoypadCodeY port:(NSInteger)port];

            uint16_t joykeyX = [self joykeyForPhysicalSourceIdentifier:srcX];
            uint16_t joykeyY = [self joykeyForPhysicalSourceIdentifier:srcY];

            /* 默认 XY->turbo 的补位阶段，只检查“显式 native override”，不看 auto bind。 */
            BOOL xUsedByExplicitNative = NO;
            BOOL yUsedByExplicitNative = NO;
            for (unsigned code = 0; code < RARCH_FIRST_CUSTOM_BIND; code++) {
                const struct retro_keybind *bind = &input_config_binds[port][code];
                if (!bind->valid) {
                    continue;
                }

                if (bind->joykey != NO_BTN && bind->joykey < 32) {
                    if (bind->joykey == joykeyX) {
                        xUsedByExplicitNative = YES;
                    }
                    if (bind->joykey == joykeyY) {
                        yUsedByExplicitNative = YES;
                    }
                }

                if (xUsedByExplicitNative && yUsedByExplicitNative) {
                    break;
                }
            }

            /* action 占用：允许 default:auto 自己，不允许其它 action 占用。 */
            NSString *xActionId = [self actionIdentifierForPhysicalSourceIdentifier:srcX useLock:NO];
            NSString *yActionId = [self actionIdentifierForPhysicalSourceIdentifier:srcY useLock:NO];
            BOOL xUsedByExplicitAction = (xActionId.length > 0 && ![xActionId isEqualToString:turboAId]);
            BOOL yUsedByExplicitAction = (yActionId.length > 0 && ![yActionId isEqualToString:turboBId]);

            if (!xUsedByExplicitNative && !xUsedByExplicitAction) {
                RAInputActionDescriptor *dA =
                [RAInputActionDescriptor joypadOutputActionWithIdentifier:turboAId displayName:turboAId outputJoypadCodes:@[@((int)RetroArchJoypadCodeA)] turboEnabled:YES];
                [self setActionDescriptor:dA useLock:NO];
                [self bindPhysicalSourceIdentifier:srcX toActionIdentifier:turboAId useLock:NO];
            }

            if (!yUsedByExplicitNative && !yUsedByExplicitAction) {
                RAInputActionDescriptor *dB =
                [RAInputActionDescriptor joypadOutputActionWithIdentifier:turboBId displayName:turboBId outputJoypadCodes:@[@((int)RetroArchJoypadCodeB)] turboEnabled:YES];
                [self setActionDescriptor:dB useLock:NO];
                [self bindPhysicalSourceIdentifier:srcY toActionIdentifier:turboBId useLock:NO];
            }
        }
    } @finally {
        [self ra_unlockState:useLock];
    }
}

- (nullable RAInputPhysicalSource *)ra_sourceFromRef:(RAInputPhysicalSourceRef *)ref port:(NSInteger)port {
    if (ref == nil) {
        return nil;
    }

    switch (ref.sourceKind) {
        case RAInputPhysicalSourceKindCodeButton:
            if (ref.sourceCode < 0 || ref.sourceCode >= 32) {
                return nil;
            }
            return [RAInputPhysicalSource buttonSourceWithJoykey:(uint16_t)ref.sourceCode displayName:@"" playerIndex:port];
        case RAInputPhysicalSourceKindCodeAxis:
            return [RAInputPhysicalSource axisSourceWithJoyaxis:(uint32_t)ref.sourceCode displayName:@"" playerIndex:port];

        default:
            return nil;
    }
}

- (NSString *)ra_portScopedSourceIdentifierForButtonCode:(enum RetroArchJoypadCode)code port:(NSInteger)port {
    return [NSString stringWithFormat:@"port:%ld:mfi:button:%d", (long)port, (int)code];
}

- (void)ra_lockState:(BOOL)useLock {
    if (useLock) {
        os_unfair_lock_lock(&d_stateLock);
    }
}

- (void)ra_unlockState:(BOOL)useLock {
    if (useLock) {
        os_unfair_lock_unlock(&d_stateLock);
    }
}
@end
