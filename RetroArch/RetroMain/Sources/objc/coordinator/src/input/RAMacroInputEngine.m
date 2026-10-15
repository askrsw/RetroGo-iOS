// Copyright © 2026 haharsw. Part of RetroGo, GPL-3.0-or-later.
#import <RAMacroInputEngine.h>

@implementation RAMacroInputStep
- (instancetype)initWithButtons:(uint32_t)buttons frames:(NSUInteger)frames {
    if ((self = [super init])) { _buttons = buttons; _frames = frames; }
    return self;
}
@end

@implementation RAMacroInputEngine {
    NSLock *_lock;
    void (^_output)(uint32_t);
    NSArray<RAMacroInputStep *> *_steps;
    NSUInteger _index, _remaining, _elapsed;
    uint32_t _mask;
}
- (instancetype)initWithOutput:(void (^)(uint32_t))output {
    if ((self = [super init])) {
        _lock = [NSLock new]; _output = [output copy];
    }
    return self;
}
- (BOOL)isPlaying { [_lock lock]; BOOL value = _steps != nil; [_lock unlock]; return value; }
- (NSUInteger)elapsedFrames { [_lock lock]; NSUInteger value = _elapsed; [_lock unlock]; return value; }
- (void)emit:(uint32_t)mask {
    if (_mask == mask) return;
    _mask = mask; _output(mask);
}
- (BOOL)playSteps:(NSArray<RAMacroInputStep *> *)steps {
    NSUInteger total = 0;
    if (!steps.count || steps.count > 128) return NO;
    for (RAMacroInputStep *step in steps) {
        if (!step.frames || step.frames > 600 || step.buttons > 0xffff) return NO;
        total += step.frames;
        if (total > 600) return NO;
    }
    [_lock lock];
    [self emit:0]; _steps = [steps copy]; _index = 0; _remaining = 0; _elapsed = 0;
    [_lock unlock]; return YES;
}
- (void)cancel {
    [_lock lock]; _steps = nil; [self emit:0]; [_lock unlock];
}
- (void)advanceFrame {
    [_lock lock];
    if (_steps) {
        if (_index >= _steps.count) { _steps = nil; [self emit:0]; }
        else {
            RAMacroInputStep *step = _steps[_index];
            if (!_remaining) _remaining = step.frames;
            [self emit:step.buttons]; ++_elapsed;
            if (--_remaining == 0) ++_index;
        }
    }
    [_lock unlock];
}
@end
