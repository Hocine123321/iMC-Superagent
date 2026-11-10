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

// How strongly the colour behind the glass shows, 0...1 (default 0.5). It is what makes glass look like
// glass, so a person can turn it down. Kept as "glass:" in launcher.txt. Posts HZThemeChanged when set.
+ (float)glassStrength;
+ (void)setGlassStrength:(float)strength;
extern NSNotificationName const HZThemeChanged;

// Whether this phone can draw real Liquid Glass (the class exists at run time).
+ (BOOL)hasLiquidGlass;

// A view that draws glass (or a blur material where there is none). Put content in `contentView`.
// `tint` may be nil. `interactive` makes it react to touch on iOS 26 and later.
+ (UIVisualEffectView *)glassViewWithTint:(UIColor *)tint interactive:(BOOL)interactive cornerRadius:(CGFloat)radius;

// A button. `prominent` is the green Play-style one. On iOS 26 and later it is the system's own glass
// button (UIButtonConfiguration glassButtonConfiguration / prominentGlassButtonConfiguration, found at run
// time), so it gets the real press, morph and highlight behaviour; elsewhere it is a tinted plain button.
+ (UIButton *)buttonWithTitle:(NSString *)title
                         symbol:(NSString *)symbolName
                      prominent:(BOOL)prominent
                         target:(id)target
                         action:(SEL)action;
// Same for a button that only shows a symbol (the "..." button).
+ (UIButton *)iconButtonWithSymbol:(NSString *)symbolName label:(NSString *)label;
// Changes the title of a button made by the two methods above.
+ (void)setTitle:(NSString *)title onButton:(UIButton *)button;

// Glass controls the iOS 18.5 SDK cannot give us. The system only turns UISlider, UISwitch and
// UISegmentedControl into glass when an app is BUILT with the iOS 26 SDK, which CI does not have. These
// are drawn by the app on a glass surface instead, and behave like their UIKit twins (target-action,
// value, accessibility, dragging).
+ (UIControl *)glassSegmentedWithItems:(NSArray<NSString *> *)items selected:(NSInteger)selected;
+ (UIControl *)glassSliderMin:(float)min max:(float)max value:(float)value;
+ (UIControl *)glassSwitchOn:(BOOL)on;
+ (UIView *)glassProgressView;

// Standard text styles.
+ (UILabel *)labelWithSize:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;

// Dress a screen pushed on the navigation stack (background colour, bar).
+ (void)styleScreen:(UIViewController *)vc;
+ (void)styleNavigationBar:(UINavigationBar *)bar;
@end

