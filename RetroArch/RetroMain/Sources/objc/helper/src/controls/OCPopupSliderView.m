//
//  OCPopupSliderView.m
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

#import "OCPopupSliderView.h"

@implementation OCPopupSliderView {
    __weak id<OCPopupSliderDelegate> d_delegate;

    UIButton *d_minusButton;
    UIButton *d_plusButton;
    UISlider *d_slider;

    NSTimer *d_timer;
    float d_pendingSendValue;
    BOOL  d_valueWaitSending;

    BOOL d_roundToNearestInteger;
}

- (instancetype)initWithDelegate:(id<OCPopupSliderDelegate>)delegate anchorPosition:(OCPopupViewAnchorPosition)position {
    CGFloat width = MIN([UIScreen mainScreen].bounds.size.width, 428) * 0.8;
    CGFloat height = 60;
    self = [super initWithSize:CGSizeMake(width, height) anchorPosition:position];
    if(self != nil) {
        d_delegate = delegate;

        [self configUI];
        [self updateUIParams];

        if ([delegate respondsToSelector:@selector(updateToggle)]) {
            NSObject *obj = delegate;
            [obj addObserver:self forKeyPath:@"updateToggle" options:NSKeyValueObservingOptionNew context:nil];
        }
    }
    return self;
}

- (void)dealloc {
    [d_timer invalidate];
    d_timer = nil;

    NSObject *obj = d_delegate;
    if ([obj respondsToSelector:@selector(updateToggle)]) {
        [obj removeObserver:self forKeyPath:@"updateToggle"];
    }
}

- (id<OCPopupSliderDelegate>)delegate {
    return d_delegate;
}

- (void)setValue:(float)value {
    float v = [self getProperValue:value];
    if(_value != v) {
        if(v > d_delegate.maximumValue) {
            _value = d_delegate.maximumValue;
        } else if(v < d_delegate.minimumValue) {
            _value = d_delegate.minimumValue;
        } else {
            _value = v;
        }
        d_minusButton.enabled = _value > d_delegate.minimumValue;
        d_plusButton.enabled  = _value < d_delegate.maximumValue;
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    self.value = [self getProperValue:d_delegate.currentValue];
    d_slider.value = self.value;
}

- (void)uninstall {
    [super uninstall];
    [d_timer invalidate];
    d_timer = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"updateToggle"]) {
        [self updateUIParams];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - Utils

- (void)updateUIParams {
    [d_timer invalidate];
    d_timer = nil;

    if ([d_delegate respondsToSelector:@selector(roundToNearestInteger)]) {
        d_roundToNearestInteger = d_delegate.roundToNearestInteger;
    } else {
        d_roundToNearestInteger = NO;
    }

    d_slider.minimumValue = d_delegate.minimumValue;
    d_slider.maximumValue = d_delegate.maximumValue;

    _value = [self getProperValue:d_delegate.currentValue];
    d_slider.value = _value;
    d_minusButton.enabled = _value > d_delegate.minimumValue;
    d_plusButton.enabled  = _value < d_delegate.maximumValue;

    d_pendingSendValue = 0;
    d_valueWaitSending = NO;

    if ([d_delegate respondsToSelector:@selector(setValueTimerInterval)]) {
        CGFloat setValueTimerInterval = d_delegate.setValueTimerInterval;
        if (setValueTimerInterval > 0) {
            d_timer = [NSTimer scheduledTimerWithTimeInterval:setValueTimerInterval target:self selector:@selector(handleTimerTick) userInfo:nil repeats:YES];
        }
    }
}

- (void)configUI {
    d_minusButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [d_minusButton setImage:[UIImage systemImageNamed:@"minus.circle"] forState:UIControlStateNormal];
    d_minusButton.tintColor = UIColor.labelColor;
    [d_minusButton addTarget:self action:@selector(minusAction:) forControlEvents:UIControlEventTouchUpInside];
    d_minusButton.translatesAutoresizingMaskIntoConstraints = NO;
    [d_minusButton sizeToFit];
    [self.containerView addSubview:d_minusButton];
    [NSLayoutConstraint activateConstraints:@[
        [d_minusButton.widthAnchor constraintEqualToConstant:d_minusButton.frame.size.width],
        [d_minusButton.heightAnchor constraintEqualToConstant:d_minusButton.frame.size.height],
        [d_minusButton.centerYAnchor constraintEqualToAnchor:self.containerView.centerYAnchor],
        [d_minusButton.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:15],
    ]];

    d_plusButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [d_plusButton setImage:[UIImage systemImageNamed:@"plus.circle"] forState:UIControlStateNormal];
    d_plusButton.tintColor = UIColor.labelColor;
    [d_plusButton addTarget:self action:@selector(plusAction:) forControlEvents:UIControlEventTouchUpInside];
    d_plusButton.translatesAutoresizingMaskIntoConstraints = NO;
    [d_plusButton sizeToFit];
    [self.containerView addSubview:d_plusButton];
    [NSLayoutConstraint activateConstraints:@[
        [d_plusButton.widthAnchor constraintEqualToConstant:d_plusButton.frame.size.width],
        [d_plusButton.heightAnchor constraintEqualToConstant:d_plusButton.frame.size.height],
        [d_plusButton.centerYAnchor constraintEqualToAnchor:self.containerView.centerYAnchor],
        [d_plusButton.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-15],
    ]];

    d_slider = [[UISlider alloc] initWithFrame:CGRectZero];
    d_slider.minimumTrackTintColor = UIColor.labelColor;
    [d_slider addTarget:self action:@selector(sliderValueChange:) forControlEvents:UIControlEventValueChanged];
    d_slider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.containerView addSubview:d_slider];
    [NSLayoutConstraint activateConstraints:@[
        [d_slider.centerYAnchor constraintEqualToAnchor:self.containerView.centerYAnchor],
        [d_slider.trailingAnchor constraintEqualToAnchor:d_plusButton.leadingAnchor constant:-10],
        [d_slider.leadingAnchor constraintEqualToAnchor:d_minusButton.trailingAnchor constant:10],
    ]];
}

- (float)getProperValue:(float)v {
    if(d_roundToNearestInteger) {
        return roundf(v);
    } else {
        return v;
    }
}

- (void)minusAction:(UIButton *)sender {
    self.value -= d_delegate.step;
    d_slider.value = self.value;

    if(d_timer != nil) {
        d_pendingSendValue = self.value;
        d_valueWaitSending = YES;
    } else {
        [d_delegate setValue:self.value];
    }
}

- (void)plusAction:(UIButton *)sender {
    self.value += d_delegate.step;
    d_slider.value = self.value;

    if(d_timer != nil) {
        d_pendingSendValue = self.value;
        d_valueWaitSending = YES;
    } else {
        [d_delegate setValue:self.value];
    }
}

- (void)sliderValueChange:(UISlider *)slider {
    float step = d_delegate.step;
    if(step <= 0) {
        return;
    }
    float v = roundf(slider.value / step) * step;
    self.value = v;

    if(d_timer != nil) {
        d_pendingSendValue = self.value;
        d_valueWaitSending = YES;
    } else {
        [d_delegate setValue:self.value];
    }
}

- (void)handleTimerTick {
    if (d_valueWaitSending) {
        [d_delegate setValue:_value];
        d_valueWaitSending = NO;
    }
}

@end
