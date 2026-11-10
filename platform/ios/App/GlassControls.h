// Controls drawn by the app: a segmented control, a slider, a switch and a progress bar. The names say
// Glass because the first version tried Liquid Glass; they are now plain solid controls (a clear track, an
// accent fill, a white knob) because glass over the launcher's dark background shows nothing. They are
// UIControls and send UIControlEventValueChanged, so they are used like the UIKit controls they replace.
// Never run on a phone.
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
