// The launcher's look: one place for colours, buttons and glass, so every screen follows the same
// dark/light setting. Pure UIKit, no storyboard.
//
// Dark and light: the colours are dynamic (they resolve against the screen's trait collection), and
// the person's choice (System, Dark or Light) is applied to the window with overrideUserInterfaceStyle.
// The choice is the line "appearance:" in <root>/launcher.txt (LauncherModel).
//
// Liquid Glass: the CI runner builds with the iOS 18.5 SDK, which has no UIGlassEffect. The class is
// therefore looked up by name at run time (NSClassFromString). On iOS 26 and later it exists and the
// surfaces are real glass; on anything older, or if the lookup fails, they are a system blur material.
// Written 2026-11-10 against Apple's documentation (UIGlassEffect, iOS 26.0+): never run on a phone.
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, HZAppearance) {
    HZAppearanceSystem = 0,
    HZAppearanceDark = 1,
    HZAppearanceLight = 2,
};

@interface HZTheme : NSObject
// Colours. All dynamic: they change with dark/light without a reload.
+ (UIColor *)background;     // the screen behind everything
+ (UIColor *)surface;        // a card or a plain button
+ (UIColor *)text;           // main text
+ (UIColor *)secondaryText;  // detail lines
+ (UIColor *)tertiaryText;   // small print
+ (UIColor *)accent;         // Horizon green, tuned for each mode
+ (UIColor *)onAccent;       // text on top of the accent
+ (UIColor *)danger;
+ (UIColor *)warning;
+ (UIColor *)separator;
+ (UIColor *)codeBackground; // behind logs and licence text

// The stored choice, and applying it to every window now.
+ (HZAppearance)appearance;
+ (void)setAppearance:(HZAppearance)appearance;
+ (void)applyAppearanceToWindows;
+ (NSString *)nameOfAppearance:(HZAppearance)appearance;

// Whether this phone can draw real Liquid Glass (the class exists at run time).
+ (BOOL)hasLiquidGlass;

// A view that draws glass (or a blur material where there is none). Put content in `contentView`.
// `tint` may be nil. `interactive` makes it react to touch on iOS 26 and later.
+ (UIVisualEffectView *)glassViewWithTint:(UIColor *)tint interactive:(BOOL)interactive cornerRadius:(CGFloat)radius;

// A pill/rounded button. `prominent` is the green Play-style one. Glass behind it where available.
+ (UIButton *)buttonWithTitle:(NSString *)title
                         symbol:(NSString *)symbolName
                      prominent:(BOOL)prominent
                         target:(id)target
                         action:(SEL)action;

// Standard text styles.
+ (UILabel *)labelWithSize:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;

// Dress a screen pushed on the navigation stack (background colour, bar).
+ (void)styleScreen:(UIViewController *)vc;
+ (void)styleNavigationBar:(UINavigationBar *)bar;
@end

// Used by the buttons above for the press response.
@interface UIButton (HZTheme)
- (void)hz_down;
- (void)hz_up;
@end

// Change the title of a button made by +buttonWithTitle:...
static inline void HZThemeSetButtonTitle(UIButton *b, NSString *title) {
    UILabel *l = (UILabel *)[b viewWithTag:7001];
    if ([l isKindOfClass:[UILabel class]]) l.text = title;
    b.accessibilityLabel = title;
}
