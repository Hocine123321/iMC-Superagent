#import "LauncherSettings.h"
#import "LauncherTheme.h"
#import "LauncherModel.h"
#import "GlassControls.h"

@interface HZLauncherSettingsController ()
@property (strong) UIControl *appearance, *strength, *direct;
@property (strong) UILabel *strengthValue;
@end

@implementation HZLauncherSettingsController

// A titled row: text on the left, the control on the right, on a glass card.
- (UIView *)rowTitle:(NSString *)title detail:(NSString *)detail control:(UIView *)control stacked:(BOOL)stacked {
    UILabel *t = [HZTheme labelWithSize:16 weight:UIFontWeightSemibold color:[HZTheme text]];
    t.text = title;
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[t]];
    text.axis = UILayoutConstraintAxisVertical; text.spacing = 3;
    if (detail.length) {
        UILabel *d = [HZTheme labelWithSize:12 weight:UIFontWeightRegular color:[HZTheme secondaryText]];
        d.text = detail;
        [text addArrangedSubview:d];
    }
    UIStackView *row = stacked ? [[UIStackView alloc] initWithArrangedSubviews:@[text, control]] : [[UIStackView alloc] initWithArrangedSubviews:@[text, control]];
    row.axis = stacked ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    row.spacing = stacked ? 10 : 16;
    row.alignment = stacked ? UIStackViewAlignmentFill : UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [control setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIVisualEffectView *card = [HZTheme glassViewWithTint:nil interactive:NO cornerRadius:22];
    [card.contentView addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:card.contentView.topAnchor constant:14], [row.bottomAnchor constraintEqualToAnchor:card.contentView.bottomAnchor constant:-14],
        [row.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor constant:18], [row.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor constant:-18]]];
    return card;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    [HZTheme styleScreen:self];

    self.appearance = [HZTheme glassSegmentedWithItems:@[@"System", @"Dark", @"Light"] selected:(NSInteger)[HZTheme appearance]];
    [self.appearance addTarget:self action:@selector(appearanceChanged:) forControlEvents:UIControlEventValueChanged];
    [self.appearance.widthAnchor constraintEqualToConstant:240].active = YES;

    self.strength = [HZTheme glassSliderMin:0 max:1 value:[HZTheme glassStrength]];
    [self.strength addTarget:self action:@selector(strengthChanged:) forControlEvents:UIControlEventValueChanged];
    self.strengthValue = [HZTheme labelWithSize:13 weight:UIFontWeightMedium color:[HZTheme secondaryText]];
    self.strengthValue.text = [NSString stringWithFormat:@"%d%%", (int)lroundf([HZTheme glassStrength] * 100)];
    self.strengthValue.textAlignment = NSTextAlignmentRight;
    [self.strengthValue.widthAnchor constraintEqualToConstant:44].active = YES;
    UIStackView *sliderRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.strength, self.strengthValue]];
    sliderRow.alignment = UIStackViewAlignmentCenter; sliderRow.spacing = 8;

    self.direct = [HZTheme glassSwitchOn:[HZLauncherModel shared].opensGameDirectly];
    [self.direct addTarget:self action:@selector(directChanged:) forControlEvents:UIControlEventValueChanged];

    UIView *r1 = [self rowTitle:@"Appearance" detail:@"Follow the phone, or always dark or light." control:self.appearance stacked:NO];
    UIView *r2 = [self rowTitle:@"Glass strength" detail:[HZTheme hasLiquidGlass] ? @"How much colour shows through the glass." : @"This phone has no Liquid Glass (iOS 26 or later), so surfaces use a blur." control:sliderRow stacked:YES];
    UIView *r3 = [self rowTitle:@"Open straight into the game" detail:@"Skips the launcher when the game files are ready. It returns after a crash, or when a file named open-launcher is in the Horizon folder." control:self.direct stacked:NO];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[r1, r2, r3]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [self.view addSubview:scroll];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:g.topAnchor], [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:g.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:40],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-40]]];
}

- (void)appearanceChanged:(HZGlassSegmented *)c { [HZTheme setAppearance:(HZAppearance)c.selectedSegmentIndex]; }
- (void)strengthChanged:(HZGlassSlider *)c {
    // Written on release would lose the live look; the file is tiny, so it is written as it moves.
    [HZTheme setGlassStrength:c.value];
    self.strengthValue.text = [NSString stringWithFormat:@"%d%%", (int)lroundf(c.value * 100)];
}
- (void)directChanged:(HZGlassSwitch *)c { [HZLauncherModel shared].opensGameDirectly = c.on; }

@end
