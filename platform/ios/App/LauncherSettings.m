#import "LauncherSettings.h"
#import "LauncherTheme.h"
#import "LauncherModel.h"
#import "LauncherPrefs.h"
#import "GlassControls.h"
#import <objc/runtime.h>

// The launcher's Settings page: a titled list of cards, grouped into sections. Everything here is saved at
// once (launcher.txt), and everything that is hidden by default is explained where it is turned on.
@interface HZLauncherSettingsController ()
@property (strong) UIStackView *stack;
@property (strong) UILabel *strengthValue;
@end

@implementation HZLauncherSettingsController

#pragma mark - building blocks

- (UILabel *)sectionHeader:(NSString *)title {
    UILabel *l = [HZTheme labelWithSize:13 weight:UIFontWeightBold color:[HZTheme tertiaryText]];
    l.text = title.uppercaseString;
    return l;
}

// A solid card holding rows. `rows` are the views from -rowTitle:..., separated by hairlines.
- (UIView *)cardWithRows:(NSArray<UIView *> *)rows {
    UIStackView *s = [UIStackView new];
    s.axis = UILayoutConstraintAxisVertical;
    for (NSUInteger i = 0; i < rows.count; i++) {
        if (i) {
            UIView *line = [UIView new];
            line.backgroundColor = [HZTheme separator];
            [line.heightAnchor constraintEqualToConstant:1 / UIScreen.mainScreen.scale].active = YES;
            UIView *wrap = [UIView new];
            line.translatesAutoresizingMaskIntoConstraints = NO;
            [wrap addSubview:line];
            [NSLayoutConstraint activateConstraints:@[[line.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:16], [line.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor],
                                                      [line.topAnchor constraintEqualToAnchor:wrap.topAnchor], [line.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor]]];
            [s addArrangedSubview:wrap];
        }
        [s addArrangedSubview:rows[i]];
    }
    UIView *card = [UIView new];
    card.backgroundColor = [HZTheme surface];
    card.layer.cornerRadius = 18; card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:s];
    [NSLayoutConstraint activateConstraints:@[[s.topAnchor constraintEqualToAnchor:card.topAnchor], [s.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
                                              [s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor], [s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor]]];
    return card;
}

// One row: a title and a grey line on the left, the control on the right (or underneath when `stacked`).
- (UIView *)rowTitle:(NSString *)title detail:(NSString *)detail control:(UIView *)control stacked:(BOOL)stacked {
    UILabel *t = [HZTheme labelWithSize:16 weight:UIFontWeightSemibold color:[HZTheme text]];
    t.text = title;
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[t]];
    text.axis = UILayoutConstraintAxisVertical; text.spacing = 3;
    if (detail.length) {
        UILabel *d = [HZTheme labelWithSize:13 weight:UIFontWeightRegular color:[HZTheme secondaryText]];
        d.text = detail;
        [text addArrangedSubview:d];
    }
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[text, control]];
    row.axis = stacked ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    row.spacing = stacked ? 12 : 16;
    row.alignment = stacked ? UIStackViewAlignmentFill : UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [control setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [control setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIView *wrap = [UIView new];
    [wrap addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:14], [row.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-14],
        [row.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:16], [row.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-16]]];
    return wrap;
}

// A switch row. `setter` runs with the new value.
- (UIView *)switchTitle:(NSString *)title detail:(NSString *)detail on:(BOOL)on set:(void (^)(BOOL))setter {
    HZGlassSwitch *sw = (HZGlassSwitch *)[HZTheme glassSwitchOn:on];
    sw.accessibilityLabel = title;   // VoiceOver reads the setting's name, then On or Off
    objc_setAssociatedObject(sw, "setter", setter, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [sw addTarget:self action:@selector(switchFlipped:) forControlEvents:UIControlEventValueChanged];
    return [self rowTitle:title detail:detail control:sw stacked:NO];
}
- (void)switchFlipped:(HZGlassSwitch *)sw {
    void (^setter)(BOOL) = objc_getAssociatedObject(sw, "setter");
    if (setter) setter(sw.on);
}

#pragma mark - the page

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    [HZTheme styleScreen:self];

    // --- Appearance
    UIControl *appearance = [HZTheme glassSegmentedWithItems:@[@"System", @"Dark", @"Light"] selected:(NSInteger)[HZTheme appearance]];
    appearance.accessibilityLabel = @"Appearance";
    [appearance addTarget:self action:@selector(appearanceChanged:) forControlEvents:UIControlEventValueChanged];
    [appearance.widthAnchor constraintEqualToConstant:230].active = YES;
    UIControl *strength = [HZTheme glassSliderMin:0 max:1 value:[HZTheme glassStrength]];
    strength.accessibilityLabel = @"Background colour";
    [strength addTarget:self action:@selector(strengthChanged:) forControlEvents:UIControlEventValueChanged];
    self.strengthValue = [HZTheme labelWithSize:14 weight:UIFontWeightMedium color:[HZTheme secondaryText]];
    self.strengthValue.text = [NSString stringWithFormat:@"%d%%", (int)lroundf([HZTheme glassStrength] * 100)];
    self.strengthValue.textAlignment = NSTextAlignmentRight;
    [self.strengthValue.widthAnchor constraintEqualToConstant:46].active = YES;
    UIStackView *sliderRow = [[UIStackView alloc] initWithArrangedSubviews:@[strength, self.strengthValue]];
    sliderRow.alignment = UIStackViewAlignmentCenter; sliderRow.spacing = 8;

    UIView *look = [self cardWithRows:@[
        [self rowTitle:@"Appearance" detail:@"Follow the phone, or always dark or light." control:appearance stacked:NO],
        [self rowTitle:@"Background colour" detail:@"How strongly the colour shows behind the launcher." control:sliderRow stacked:YES],
        [self switchTitle:@"Compact lists" detail:@"Marketplace rows without the description line." on:[HZPrefs compactLists] set:^(BOOL on) { [HZPrefs setCompactLists:on]; }],
        [self switchTitle:@"Reduce motion" detail:@"No bounce on switches and tabs." on:[HZPrefs reduceMotion] set:^(BOOL on) { [HZPrefs setReduceMotion:on]; }],
    ]];

    // --- Marketplace
    UIView *market = [self cardWithRows:@[
        [self switchTitle:@"Modrinth resource packs" detail:@"Adds a Modrinth tab with thousands of packs for 26.3. They come from Modrinth's servers and are not reviewed by Horizon." on:[HZPrefs useModrinth] set:^(BOOL on) { [HZPrefs setUseModrinth:on]; }],
        [self switchTitle:@"Show mods" detail:@"Adds a Mods tab. Mods change the game and are off in the game until you turn them on." on:[HZPrefs showMods] set:^(BOOL on) { [HZPrefs setShowMods:on]; }],
        [self switchTitle:@"Show shaders" detail:@"Adds a Shaders tab. Shaders have not been tested on a phone." on:[HZPrefs showShaders] set:^(BOOL on) { [HZPrefs setShowShaders:on]; }],
        [self switchTitle:@"Show everything else" detail:@"Adds an Everything tab, including native mods and kinds the app cannot install yet." on:[HZPrefs showOtherKinds] set:^(BOOL on) { [HZPrefs setShowOtherKinds:on]; }],
        [self switchTitle:@"Ask before installing" detail:@"Shows what will happen and the download size first." on:[HZPrefs confirmInstalls] set:^(BOOL on) { [HZPrefs setConfirmInstalls:on]; }],
    ]];

    // --- Start-up
    UIView *start = [self cardWithRows:@[
        [self switchTitle:@"Open straight into the game" detail:@"Skips the launcher when the game files are ready. It comes back after a crash, or when a file named open-launcher is in the Horizon folder." on:[HZLauncherModel shared].opensGameDirectly set:^(BOOL on) { [HZLauncherModel shared].opensGameDirectly = on; }],
    ]];

    self.stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self sectionHeader:@"Look"], look, [self sectionHeader:@"Marketplace"], market, [self sectionHeader:@"Start-up"], start]];
    self.stack.axis = UILayoutConstraintAxisVertical; self.stack.spacing = 8;
    [self.stack setCustomSpacing:24 afterView:look]; [self.stack setCustomSpacing:24 afterView:market];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:self.stack];
    [self.view addSubview:scroll];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:g.topAnchor], [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:g.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12],
        [self.stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-32],
        [self.stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:40],
        [self.stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-40]]];
}

- (void)appearanceChanged:(HZGlassSegmented *)c { [HZTheme setAppearance:(HZAppearance)c.selectedSegmentIndex]; }
- (void)strengthChanged:(HZGlassSlider *)c {
    [HZTheme setGlassStrength:c.value];
    self.strengthValue.text = [NSString stringWithFormat:@"%d%%", (int)lroundf(c.value * 100)];
}

@end
