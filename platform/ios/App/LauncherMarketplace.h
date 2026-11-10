// The Marketplace screen (M14): browse the Horizon registry and install from it. Lists, searches, shows
// project pages, installs mods, resource packs and shaders (MarketInstaller), removes them, and has an
// Installed tab. Never run on a phone; docs/IOS_MARKETPLACE.md says what is and is not checked.
#import <UIKit/UIKit.h>

@interface HZLauncherMarketplaceController : UITableViewController
@end

// Every project page shares one layout and one install flow (confirm, progress, cancel, check, place).
@interface HZMarketPageController : UIViewController
// What a subclass says. (Declared here so the subclasses compile; nothing else calls them.)
- (NSString *)pageTitle;
- (NSString *)kindKey;
- (NSString *)byline;
- (NSAttributedString *)detailText;
- (NSString *)installTitle;
- (NSString *)refusal;
- (NSString *)installedVersion;
- (NSString *)availableVersion;
- (NSString *)explanation;
- (unsigned long long)downloadSize;
- (NSString *)confirmText;
- (void)reloadText;
- (void)refreshButtons;
@end

// One project's page from Horizon's registry: the facts, and the Install / Update / Remove button.
@class HZMarketProject, HZMarketIndex;
@interface HZMarketProjectController : HZMarketPageController
- (instancetype)initWithProject:(HZMarketProject *)project index:(HZMarketIndex *)index;
@end

// A Modrinth resource pack's page: the facts it has from the search, and Install / Remove.
@class HZModrinthProject;
@interface HZModrinthProjectController : HZMarketPageController
- (instancetype)initWithProject:(HZModrinthProject *)project;
@end
