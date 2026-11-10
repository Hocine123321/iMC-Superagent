#import "GlassControls.h"
#import "LauncherTheme.h"

static const CGFloat kTrackHeight = 8;

// A rounded glass (or blur) surface, never stealing touches.
static UIVisualEffectView *Surface(UIColor *tint, BOOL interactive, CGFloat radius) {
    UIVisualEffectView *v = [HZTheme glassViewWithTint:tint interactive:interactive cornerRadius:radius];
    v.userInteractionEnabled = NO;
    return v;
}
static void Pin(UIView *v, UIView *to) {
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [v.leadingAnchor constraintEqualToAnchor:to.leadingAnchor], [v.trailingAnchor constraintEqualToAnchor:to.trailingAnchor],
        [v.topAnchor constraintEqualToAnchor:to.topAnchor], [v.bottomAnchor constraintEqualToAnchor:to.bottomAnchor]]];
}
static void Haptic(void) { [[UISelectionFeedbackGenerator new] selectionChanged]; }

#pragma mark - Segmented

@implementation HZGlassSegmented {
    NSArray<UILabel *> *_labels;
    UIVisualEffectView *_track, *_thumb;
    NSLayoutConstraint *_thumbLeading, *_thumbWidth;
    NSInteger _selected;
}

- (instancetype)initWithItems:(NSArray<NSString *> *)items {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.isAccessibilityElement = NO;
        _track = Surface(nil, NO, 20);
        [self addSubview:_track];
        Pin(_track, self);
        // The selected segment is a second, tinted glass pill that slides.
        _thumb = Surface([[HZTheme accent] colorWithAlphaComponent:0.55], YES, 17);
        _thumb.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_thumb];
        NSMutableArray *labels = [NSMutableArray array];
        UIStackView *row = [UIStackView new];
        row.distribution = UIStackViewDistributionFillEqually;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        row.userInteractionEnabled = NO;
        for (NSString *t in items) {
            UILabel *l = [HZTheme labelWithSize:14 weight:UIFontWeightSemibold color:[HZTheme text]];
            l.text = t; l.textAlignment = NSTextAlignmentCenter; l.numberOfLines = 1;
            l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = 0.7;
            [row addArrangedSubview:l]; [labels addObject:l];
        }
        _labels = labels;
        [self addSubview:row];
        _thumbLeading = [_thumb.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:3];
        _thumbWidth = [_thumb.widthAnchor constraintEqualToConstant:40];
        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:40],
            [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:3], [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-3],
            [row.topAnchor constraintEqualToAnchor:self.topAnchor], [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            _thumbLeading, _thumbWidth,
            [_thumb.topAnchor constraintEqualToAnchor:self.topAnchor constant:3], [_thumb.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-3]]];
        [self addTarget:self action:@selector(tapped:forEvent:) forControlEvents:UIControlEventTouchUpInside];
        self.accessibilityTraits = UIAccessibilityTraitAdjustable;
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = [items componentsJoinedByString:@", "];
    }
    return self;
}

- (CGFloat)segmentWidth { return _labels.count ? (self.bounds.size.width - 6) / (CGFloat)_labels.count : 0; }
- (void)layoutSubviews {
    [super layoutSubviews];
    _thumbWidth.constant = [self segmentWidth];
    _thumbLeading.constant = 3 + [self segmentWidth] * (CGFloat)_selected;
}
- (NSInteger)selectedSegmentIndex { return _selected; }
- (void)setSelectedSegmentIndex:(NSInteger)i {
    _selected = MAX(0, MIN(i, (NSInteger)_labels.count - 1));
    self.accessibilityValue = _selected < (NSInteger)_labels.count ? _labels[(NSUInteger)_selected].text : nil;
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.4 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        [self setNeedsLayout]; [self layoutIfNeeded];
    } completion:nil];
}
- (void)tapped:(UIControl *)c forEvent:(UIEvent *)e {
    CGPoint pt = [[e touchesForView:self].anyObject locationInView:self];
    CGFloat w = [self segmentWidth];
    if (w <= 0) return;
    NSInteger i = (NSInteger)((pt.x - 3) / w);
    if (i == _selected) return;
    self.selectedSegmentIndex = i;
    Haptic();
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (void)accessibilityIncrement { if (_selected + 1 < (NSInteger)_labels.count) { self.selectedSegmentIndex = _selected + 1; [self sendActionsForControlEvents:UIControlEventValueChanged]; } }
- (void)accessibilityDecrement { if (_selected > 0) { self.selectedSegmentIndex = _selected - 1; [self sendActionsForControlEvents:UIControlEventValueChanged]; } }
@end

#pragma mark - Slider

@implementation HZGlassSlider {
    UIVisualEffectView *_track, *_fill, *_thumb;
    NSLayoutConstraint *_fillWidth, *_thumbCenter;
    float _value;
    BOOL _dragging;
}

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        _minimumValue = 0; _maximumValue = 1; _value = 0; _continuous = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _track = Surface(nil, NO, kTrackHeight / 2);
        _fill = Surface([[HZTheme accent] colorWithAlphaComponent:0.9], NO, kTrackHeight / 2);
        _thumb = Surface(nil, YES, 16);
        for (UIView *v in @[_track, _fill, _thumb]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:v]; }
        _fillWidth = [_fill.widthAnchor constraintEqualToConstant:0];
        _thumbCenter = [_thumb.centerXAnchor constraintEqualToAnchor:self.leadingAnchor constant:16];
        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:44],
            [_track.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16], [_track.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [_track.centerYAnchor constraintEqualToAnchor:self.centerYAnchor], [_track.heightAnchor constraintEqualToConstant:kTrackHeight],
            [_fill.leadingAnchor constraintEqualToAnchor:_track.leadingAnchor], [_fill.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_fill.heightAnchor constraintEqualToConstant:kTrackHeight], _fillWidth,
            [_thumb.centerYAnchor constraintEqualToAnchor:self.centerYAnchor], [_thumb.widthAnchor constraintEqualToConstant:32], [_thumb.heightAnchor constraintEqualToConstant:32],
            _thumbCenter]];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitAdjustable;
    }
    return self;
}

- (CGFloat)travel { return MAX(1, self.bounds.size.width - 32); }
- (float)fraction { return _maximumValue > _minimumValue ? (_value - _minimumValue) / (_maximumValue - _minimumValue) : 0; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat x = 16 + [self travel] * (CGFloat)[self fraction];
    _thumbCenter.constant = x;
    _fillWidth.constant = x - 16;
}
- (float)value { return _value; }
- (void)setValue:(float)v {
    _value = MAX(_minimumValue, MIN(v, _maximumValue));
    self.accessibilityValue = [NSString stringWithFormat:@"%d%%", (int)lroundf([self fraction] * 100)];
    [self setNeedsLayout];
    if (!_dragging) [UIView animateWithDuration:0.2 animations:^{ [self layoutIfNeeded]; }]; else [self layoutIfNeeded];
}

- (void)moveTo:(CGPoint)pt {
    float f = (float)MAX(0, MIN(1, (pt.x - 16) / [self travel]));
    float old = _value;
    self.value = _minimumValue + f * (_maximumValue - _minimumValue);
    if (_continuous && _value != old) [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    _dragging = YES;
    [UIView animateWithDuration:0.2 animations:^{ self->_thumb.transform = CGAffineTransformMakeScale(1.25, 1.25); }];
    [self moveTo:[t locationInView:self]];
    return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e { [self moveTo:[t locationInView:self]]; return YES; }
- (void)endTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    _dragging = NO;
    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0 options:0 animations:^{ self->_thumb.transform = CGAffineTransformIdentity; } completion:nil];
    if (!_continuous) [self sendActionsForControlEvents:UIControlEventValueChanged];
    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}
- (void)cancelTrackingWithEvent:(UIEvent *)e { _dragging = NO; _thumb.transform = CGAffineTransformIdentity; }
- (void)accessibilityIncrement { self.value = _value + (_maximumValue - _minimumValue) * 0.1f; [self sendActionsForControlEvents:UIControlEventValueChanged]; }
- (void)accessibilityDecrement { self.value = _value - (_maximumValue - _minimumValue) * 0.1f; [self sendActionsForControlEvents:UIControlEventValueChanged]; }
@end

#pragma mark - Switch

@implementation HZGlassSwitch {
    UIVisualEffectView *_track, *_knob;
    NSLayoutConstraint *_knobLeading;
    BOOL _on;
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _track = Surface(nil, NO, 16);
        _knob = Surface(nil, YES, 14);
        for (UIView *v in @[_track, _knob]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:v]; }
        Pin(_track, self);
        _knobLeading = [_knob.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2];
        [NSLayoutConstraint activateConstraints:@[
            [self.widthAnchor constraintEqualToConstant:64], [self.heightAnchor constraintEqualToConstant:32],
            [_knob.widthAnchor constraintEqualToConstant:40], [_knob.heightAnchor constraintEqualToConstant:28],
            [_knob.centerYAnchor constraintEqualToAnchor:self.centerYAnchor], _knobLeading]];
        [self addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        [self apply];
    }
    return self;
}
- (BOOL)isOn { return _on; }
- (void)setOn:(BOOL)on { [self setOn:on animated:NO]; }
- (void)setOn:(BOOL)on animated:(BOOL)animated {
    _on = on;
    void (^change)(void) = ^{ [self apply]; [self layoutIfNeeded]; };
    if (animated) [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.3 options:0 animations:change completion:nil]; else change();
}
- (void)apply {
    _knobLeading.constant = _on ? 64 - 40 - 2 : 2;
    // The track takes the accent colour when on. The glass view's own tint cannot be changed after it is made,
    // so the colour sits in its content view.
    _track.contentView.backgroundColor = _on ? [[HZTheme accent] colorWithAlphaComponent:0.7] : UIColor.clearColor;
    self.accessibilityValue = _on ? @"On" : @"Off";
}
- (void)toggle { [self setOn:!_on animated:YES]; Haptic(); [self sendActionsForControlEvents:UIControlEventValueChanged]; }
- (BOOL)accessibilityActivate { [self toggle]; return YES; }
@end

#pragma mark - Progress

@implementation HZGlassProgress {
    UIVisualEffectView *_track, *_fill;
    NSLayoutConstraint *_fillWidth;
    float _progress;
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _track = Surface(nil, NO, 7);
        _fill = Surface([[HZTheme accent] colorWithAlphaComponent:0.9], NO, 7);
        for (UIView *v in @[_track, _fill]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:v]; }
        Pin(_track, self);
        _fillWidth = [_fill.widthAnchor constraintEqualToConstant:0];
        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:14],
            [_fill.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [_fill.topAnchor constraintEqualToAnchor:self.topAnchor], [_fill.bottomAnchor constraintEqualToAnchor:self.bottomAnchor], _fillWidth]];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitUpdatesFrequently;
    }
    return self;
}
- (float)progress { return _progress; }
- (void)setProgress:(float)p {
    _progress = MAX(0, MIN(1, p));
    self.accessibilityValue = [NSString stringWithFormat:@"%d%%", (int)lroundf(_progress * 100)];
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    // A little width keeps the rounded end from looking like a dot at 0%.
    _fillWidth.constant = _progress <= 0 ? 0 : MAX(14, self.bounds.size.width * (CGFloat)_progress);
}
@end
