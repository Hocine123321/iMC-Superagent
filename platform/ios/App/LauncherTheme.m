#import "LauncherTheme.h"
#import "LauncherModel.h"
#import <objc/message.h>

static UIColor *Dyn(UIColor *dark, UIColor *light) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleLight ? light : dark;
    }];
}
static UIColor *RGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a) { return [UIColor colorWithRed:r green:g blue:b alpha:a]; }

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

+ (HZAppearance)appearance {
    NSString *text = [NSString stringWithContentsOfFile:[self settingsPath] encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"appearance:"]) {
            NSString *v = [line substringFromIndex:11];
            if ([v hasPrefix:@"dark"]) return HZAppearanceDark;
            if ([v hasPrefix:@"light"]) return HZAppearanceLight;
        }
    }
    return HZAppearanceSystem;
}

// Rewrites launcher.txt keeping every other line (main.m and LauncherModel read "openGame:").
+ (void)setAppearance:(HZAppearance)appearance {
    NSString *value = appearance == HZAppearanceDark ? @"dark" : appearance == HZAppearanceLight ? @"light" : @"system";
    NSString *old = [NSString stringWithContentsOfFile:[self settingsPath] encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *line in [old componentsSeparatedByString:@"\n"]) {
        if (line.length && ![line hasPrefix:@"appearance:"]) [kept addObject:line];
    }
    [kept addObject:[@"appearance:" stringByAppendingString:value]];
    NSString *text = [[kept componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
    [[NSFileManager defaultManager] createDirectoryAtPath:[HZLauncherModel shared].root withIntermediateDirectories:YES attributes:nil error:nil];
    [text writeToFile:[self settingsPath] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [self applyAppearanceToWindows];
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

#pragma mark - Glass

+ (BOOL)hasLiquidGlass { return NSClassFromString(@"UIGlassEffect") != nil; }

// UIGlassEffect is iOS 26+. Apple documents init(style:), isInteractive and tintColor; the style
// enum is { regular, clear }. Called through the Objective-C runtime so the iOS 18.5 SDK compiles it.
+ (UIVisualEffect *)glassEffectWithTint:(UIColor *)tint interactive:(BOOL)interactive {
    Class cls = NSClassFromString(@"UIGlassEffect");
    if (!cls) return nil;
    id effect = nil;
    SEL initWithStyle = NSSelectorFromString(@"initWithStyle:");
    id alloc = [cls alloc];
    if ([alloc respondsToSelector:initWithStyle]) {
        NSInteger regular = 0;   // UIGlassEffectStyleRegular
        id (*send)(id, SEL, NSInteger) = (id (*)(id, SEL, NSInteger))objc_msgSend;
        effect = send(alloc, initWithStyle, regular);
    } else {
        effect = [alloc init];
    }
    if (![effect isKindOfClass:[UIVisualEffect class]]) return nil;
    @try {
        if (interactive && [effect respondsToSelector:NSSelectorFromString(@"setInteractive:")]) [effect setValue:@YES forKey:@"interactive"];
        if (tint && [effect respondsToSelector:NSSelectorFromString(@"setTintColor:")]) [effect setValue:tint forKey:@"tintColor"];
    } @catch (NSException *e) { /* a property that is not there: plain glass */ }
    return effect;
}

+ (UIVisualEffectView *)glassViewWithTint:(UIColor *)tint interactive:(BOOL)interactive cornerRadius:(CGFloat)radius {
    UIVisualEffect *effect = [self glassEffectWithTint:tint interactive:interactive];
    UIVisualEffectView *v;
    if (effect) {
        v = [[UIVisualEffectView alloc] initWithEffect:effect];
    } else {
        // No Liquid Glass here: the closest thing the older SDKs have.
        v = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        if (tint) v.contentView.backgroundColor = [tint colorWithAlphaComponent:0.35];
    }
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.layer.cornerRadius = radius;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.clipsToBounds = YES;
    return v;
}

#pragma mark - Controls

+ (UILabel *)labelWithSize:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textColor = color;
    l.numberOfLines = 0;
    return l;
}

+ (UIButton *)buttonWithTitle:(NSString *)title symbol:(NSString *)symbolName prominent:(BOOL)prominent target:(id)target action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.layer.cornerRadius = prominent ? 22 : 18;
    b.clipsToBounds = YES;

    // A glass layer behind the content where the phone has it; a tinted plain fill where not.
    UIView *backing;
    if ([self hasLiquidGlass]) {
        UIVisualEffectView *g = [self glassViewWithTint:prominent ? [self.accent colorWithAlphaComponent:0.85] : nil
                                            interactive:YES cornerRadius:b.layer.cornerRadius];
        g.userInteractionEnabled = NO;
        backing = g;
    } else {
        backing = [UIView new];
        backing.translatesAutoresizingMaskIntoConstraints = NO;
        backing.userInteractionEnabled = NO;
        backing.backgroundColor = prominent ? [self accent] : [self surface];
    }
    [b addSubview:backing];
    [NSLayoutConstraint activateConstraints:@[
        [backing.leadingAnchor constraintEqualToAnchor:b.leadingAnchor],
        [backing.trailingAnchor constraintEqualToAnchor:b.trailingAnchor],
        [backing.topAnchor constraintEqualToAnchor:b.topAnchor],
        [backing.bottomAnchor constraintEqualToAnchor:b.bottomAnchor],
    ]];

    UIColor *fg = prominent && ![self hasLiquidGlass] ? [self onAccent] : [self text];
    UIImageView *icon = nil;
    if (symbolName.length) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:prominent ? 24 : 19 weight:UIImageSymbolWeightSemibold];
        icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbolName withConfiguration:cfg]];
        icon.tintColor = fg;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.userInteractionEnabled = NO;
    }
    UILabel *label = [self labelWithSize:prominent ? 24 : 16 weight:prominent ? UIFontWeightBold : UIFontWeightSemibold color:fg];
    label.text = title;
    label.numberOfLines = 1;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.7;
    label.userInteractionEnabled = NO;
    label.tag = 7001;   // so a screen can change the title later (HZThemeSetButtonTitle)

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:icon ? @[icon, label] : @[label]];
    row.spacing = 10; row.alignment = UIStackViewAlignmentCenter;
    row.userInteractionEnabled = NO;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [b addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.centerXAnchor constraintEqualToAnchor:b.centerXAnchor],
        [row.centerYAnchor constraintEqualToAnchor:b.centerYAnchor],
        [row.leadingAnchor constraintGreaterThanOrEqualToAnchor:b.leadingAnchor constant:12],
        [row.trailingAnchor constraintLessThanOrEqualToAnchor:b.trailingAnchor constant:-12],
    ]];
    b.accessibilityLabel = title;
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    // A small press response for the non-glass fallback (real glass animates itself).
    [b addTarget:b action:@selector(hz_down) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [b addTarget:b action:@selector(hz_up) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    return b;
}

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

@end

@implementation UIButton (HZTheme)
- (void)hz_down { [UIView animateWithDuration:0.12 animations:^{ self.transform = CGAffineTransformMakeScale(0.97, 0.97); self.alpha = 0.85; }]; }
- (void)hz_up   { [UIView animateWithDuration:0.18 animations:^{ self.transform = CGAffineTransformIdentity; self.alpha = self.enabled ? 1 : 0.45; }]; }
@end
