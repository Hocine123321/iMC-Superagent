#import "LauncherTheme.h"
#import "LauncherModel.h"
#import "GlassControls.h"

static UIColor *Dyn(UIColor *dark, UIColor *light) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleLight ? light : dark;
    }];
}
static UIColor *RGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a) { return [UIColor colorWithRed:r green:g blue:b alpha:a]; }

NSNotificationName const HZThemeChanged = @"HZThemeChanged";

@implementation HZTheme

+ (UIColor *)background    { return Dyn(RGB(0.07, 0.09, 0.11, 1), RGB(0.95, 0.96, 0.97, 1)); }
+ (UIColor *)surface       { return Dyn([UIColor colorWithWhite:1 alpha:0.10], [UIColor colorWithWhite:0 alpha:0.06]); }
+ (UIColor *)text          { return Dyn(UIColor.whiteColor, RGB(0.07, 0.09, 0.11, 1)); }
+ (UIColor *)secondaryText { return Dyn([UIColor colorWithWhite:1 alpha:0.70], [UIColor colorWithWhite:0 alpha:0.62]); }
+ (UIColor *)tertiaryText  { return Dyn([UIColor colorWithWhite:1 alpha:0.50], [UIColor colorWithWhite:0 alpha:0.48]); }
+ (UIColor *)accent        { return Dyn(RGB(0.36, 0.74, 0.33, 1), RGB(0.16, 0.55, 0.20, 1)); }
+ (UIColor *)onAccent      { return Dyn(UIColor.blackColor, UIColor.whiteColor); }
+ (UIColor *)danger        { return Dyn(RGB(1.00, 0.45, 0.45, 1), RGB(0.80, 0.15, 0.15, 1)); }
+ (UIColor *)warning       { return Dyn(RGB(0.95, 0.65, 0.20, 1), RGB(0.75, 0.42, 0.00, 1)); }
+ (UIColor *)separator     { return Dyn([UIColor colorWithWhite:1 alpha:0.12], [UIColor colorWithWhite:0 alpha:0.12]); }
+ (UIColor *)codeBackground{ return Dyn([UIColor colorWithWhite:0 alpha:0.35], [UIColor colorWithWhite:0 alpha:0.05]); }

#pragma mark - Appearance

+ (NSString *)settingsPath { return [[HZLauncherModel shared].root stringByAppendingPathComponent:@"launcher.txt"]; }

// launcher.txt holds one "key:value" per line (openGame: is read by LauncherModel and main.m). Reading and
// writing here keeps every line this class does not own.
+ (NSString *)settingFor:(NSString *)key {
    NSString *text = [NSString stringWithContentsOfFile:[self settingsPath] encoding:NSUTF8StringEncoding error:nil];
    NSString *prefix = [key stringByAppendingString:@":"];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) if ([line hasPrefix:prefix]) return [line substringFromIndex:prefix.length];
    return nil;
}
+ (void)setSetting:(NSString *)value for:(NSString *)key {
    NSString *old = [NSString stringWithContentsOfFile:[self settingsPath] encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSString *prefix = [key stringByAppendingString:@":"];
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *line in [old componentsSeparatedByString:@"\n"]) if (line.length && ![line hasPrefix:prefix]) [kept addObject:line];
    [kept addObject:[prefix stringByAppendingString:value]];
    [[NSFileManager defaultManager] createDirectoryAtPath:[HZLauncherModel shared].root withIntermediateDirectories:YES attributes:nil error:nil];
    [[[kept componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] writeToFile:[self settingsPath] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

+ (HZAppearance)appearance {
    NSString *v = [self settingFor:@"appearance"];
    if ([v hasPrefix:@"dark"]) return HZAppearanceDark;
    if ([v hasPrefix:@"light"]) return HZAppearanceLight;
    return HZAppearanceSystem;
}

+ (void)setAppearance:(HZAppearance)appearance {
    [self setSetting:appearance == HZAppearanceDark ? @"dark" : appearance == HZAppearanceLight ? @"light" : @"system" for:@"appearance"];
    [self applyAppearanceToWindows];
    [NSNotificationCenter.defaultCenter postNotificationName:HZThemeChanged object:nil];
}

+ (float)glassStrength {
    NSString *v = [self settingFor:@"glass"];
    return v.length ? MAX(0, MIN(1, v.floatValue)) : 0.5f;
}
+ (void)setGlassStrength:(float)strength {
    [self setSetting:[NSString stringWithFormat:@"%.2f", MAX(0, MIN(1, strength))] for:@"glass"];
    [NSNotificationCenter.defaultCenter postNotificationName:HZThemeChanged object:nil];
}

+ (NSString *)nameOfAppearance:(HZAppearance)a {
    return a == HZAppearanceDark ? @"Dark" : a == HZAppearanceLight ? @"Light" : @"System";
}

+ (void)applyAppearanceToWindows {
    UIUserInterfaceStyle style = UIUserInterfaceStyleUnspecified;
    switch ([self appearance]) {
        case HZAppearanceDark: style = UIUserInterfaceStyleDark; break;
        case HZAppearanceLight: style = UIUserInterfaceStyleLight; break;
        default: break;
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            [UIView animateWithDuration:0.25 animations:^{ w.overrideUserInterfaceStyle = style; }];
        }
    }
    // This app has no scene manifest, so its window may not be in a scene's list yet.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in UIApplication.sharedApplication.windows) w.overrideUserInterfaceStyle = style;
#pragma clang diagnostic pop
}

#pragma mark - Controls

+ (UILabel *)labelWithSize:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textColor = color;
    l.numberOfLines = 0;
    return l;
}

// Buttons are solid: a primary button is the accent colour with the on-accent text (dark on the light green in
// dark mode, white on the dark green in light mode), a secondary one is the surface colour with the normal text.
// The first pass asked iOS 26 for its glass button style; on the owner's phone that did not read as glass and put
// white text on a green-tinted pane, so contrast was left to chance. This is the same in both themes and on every iOS.
+ (UIButtonConfiguration *)configurationProminent:(BOOL)prominent title:(NSString *)title symbol:(nullable NSString *)symbolName {
    UIButtonConfiguration *cfg = prominent ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration grayButtonConfiguration];
    cfg.title = title;
    cfg.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    cfg.imagePadding = 8;
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(prominent ? 18 : 12, 14, prominent ? 18 : 12, 14);
    if (symbolName.length)
        cfg.image = [UIImage systemImageNamed:symbolName withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:prominent ? 24 : 18 weight:UIImageSymbolWeightSemibold]];
    cfg.baseBackgroundColor = prominent ? [HZTheme accent] : [HZTheme surface];
    cfg.baseForegroundColor = prominent ? [HZTheme onAccent] : [HZTheme text];
    UIFont *font = [UIFont systemFontOfSize:prominent ? 24 : 16 weight:prominent ? UIFontWeightBold : UIFontWeightSemibold];
    cfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *in) {
        NSMutableDictionary *d = [in mutableCopy]; d[NSFontAttributeName] = font; return d;
    };
    return cfg;
}

+ (UIButton *)buttonWithTitle:(NSString *)title symbol:(nullable NSString *)symbolName prominent:(BOOL)prominent target:(id)target action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.configuration = [self configurationProminent:prominent title:title symbol:symbolName];
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.titleLabel.minimumScaleFactor = 0.7;
    b.accessibilityLabel = title;
    // A disabled button (Play with no game files) keeps its shape and looks switched off.
    b.configurationUpdateHandler = ^(UIButton *btn) { btn.alpha = btn.isEnabled ? 1 : 0.45; };
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

+ (UIButton *)iconButtonWithSymbol:(NSString *)symbolName label:(NSString *)label {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration *cfg = [UIButtonConfiguration grayButtonConfiguration];
    cfg.baseBackgroundColor = [self surface];
    cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    cfg.image = [UIImage systemImageNamed:symbolName withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightBold]];
    cfg.baseForegroundColor = [self text];
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(12, 12, 12, 12);
    b.configuration = cfg;
    b.tintColor = [self text];
    b.accessibilityLabel = label;
    return b;
}

+ (void)setTitle:(NSString *)title onButton:(UIButton *)button {
    UIButtonConfiguration *cfg = button.configuration;
    if (cfg) { cfg.title = title; button.configuration = cfg; }
    button.accessibilityLabel = title;
}

#pragma mark - Glass controls

+ (UIControl *)glassSegmentedWithItems:(NSArray<NSString *> *)items selected:(NSInteger)selected {
    HZGlassSegmented *c = [[HZGlassSegmented alloc] initWithItems:items];
    c.selectedSegmentIndex = selected;
    return c;
}
+ (UIControl *)glassSliderMin:(float)min max:(float)max value:(float)value {
    HZGlassSlider *c = [HZGlassSlider new];
    c.minimumValue = min; c.maximumValue = max; c.value = value;
    return c;
}
+ (UIControl *)glassSwitchOn:(BOOL)on {
    HZGlassSwitch *c = [HZGlassSwitch new];
    c.on = on;
    return c;
}
+ (UIView *)glassProgressView { return [HZGlassProgress new]; }

#pragma mark - Screens

+ (void)styleNavigationBar:(UINavigationBar *)bar {
    // Opaque-looking bar that follows dark/light. On iOS 26 the system draws its own glass bar and
    // these appearances are ignored where they would fight it, which is the intent.
    UINavigationBarAppearance *a = [UINavigationBarAppearance new];
    [a configureWithTransparentBackground];
    a.titleTextAttributes = @{NSForegroundColorAttributeName: [self text]};
    a.largeTitleTextAttributes = @{NSForegroundColorAttributeName: [self text]};
    bar.standardAppearance = a;
    bar.scrollEdgeAppearance = a;
    bar.compactAppearance = a;
    bar.tintColor = [self accent];
}

+ (void)styleScreen:(UIViewController *)vc {
    vc.view.backgroundColor = [self background];
}

+ (UIScrollView *)scrollColumn:(UIView *)column onScreen:(UIViewController *)vc {
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:column];
    [vc.view addSubview:scroll];
    UILayoutGuide *g = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:g.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:vc.view.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        // The width is the frame's, so labels wrap; the height is the content's, so it scrolls.
        [column.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],
        [column.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-32],
        [column.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:24],
        [column.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-24],
    ]];
    return scroll;
}

@end
