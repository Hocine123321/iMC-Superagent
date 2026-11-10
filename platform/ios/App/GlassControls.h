// Glass controls drawn by the app (see LauncherTheme.h for why): a segmented control, a slider, a switch
// and a progress bar. Each sits on a UIGlassEffect surface where the phone has one (iOS 26 and later,
// found at run time) and on a system blur material where it does not. They are UIControls: they send
// UIControlEventValueChanged, so they are used like the UIKit controls they stand in for.
// Written 2026-11-10 against Apple's UIGlassEffect documentation; never run on a phone.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HZGlassSegmented : UIControl
@property (nonatomic) NSInteger selectedSegmentIndex;
- (instancetype)initWithItems:(NSArray<NSString *> *)items;
@end

@interface HZGlassSlider : UIControl
@property (nonatomic) float minimumValue, maximumValue, value;
@property (nonatomic, getter=isContinuous) BOOL continuous;
@end

@interface HZGlassSwitch : UIControl
@property (nonatomic, getter=isOn) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@end

@interface HZGlassProgress : UIView
@property (nonatomic) float progress;   // 0...1
@end

NS_ASSUME_NONNULL_END
