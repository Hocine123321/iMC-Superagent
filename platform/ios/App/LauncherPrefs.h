// The launcher's own choices, kept as "key:value" lines in Horizon/launcher.txt beside the lines
// LauncherModel and main.m read. No UIKit. Every default is the safe one: what is hidden stays hidden
// until the person turns it on in Settings.
//
// What the Marketplace shows (the owner's rule, 2026-11-10): resource packs by default. Mods, shaders and
// every other category stay hidden until turned on here. Modrinth resource packs are a separate switch
// because they reach another company's server.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HZPrefs : NSObject
// Marketplace visibility (all default NO)
+ (BOOL)showMods;           // content mods from Horizon's registry
+ (BOOL)showShaders;        // shaders from Horizon's registry
+ (BOOL)showOtherKinds;     // native mods, modpacks, data packs: listed but not installable
+ (BOOL)useModrinth;        // resource packs from Modrinth (api.modrinth.com, cdn.modrinth.com)
+ (void)setShowMods:(BOOL)on;
+ (void)setShowShaders:(BOOL)on;
+ (void)setShowOtherKinds:(BOOL)on;
+ (void)setUseModrinth:(BOOL)on;

// Behaviour
+ (BOOL)confirmInstalls;    // default YES: ask before downloading
+ (BOOL)compactLists;       // default NO
+ (BOOL)reduceMotion;       // default NO
+ (void)setConfirmInstalls:(BOOL)on;
+ (void)setCompactLists:(BOOL)on;
+ (void)setReduceMotion:(BOOL)on;

// A project kind that Horizon's registry lists: is it shown with the current choices?
+ (BOOL)isKindVisible:(NSString *)kind;

// The pure parser, public so a test can read the rule: "true"/"false" lines, anything else is the default.
+ (BOOL)boolFromText:(nullable NSString *)text fallback:(BOOL)fallback;
@end

NS_ASSUME_NONNULL_END
