// The Marketplace screen (M14): browse the Horizon registry and install from it. Lists, searches, shows
// project pages, installs mods, resource packs and shaders (MarketInstaller), removes them, and has an
// Installed tab. Never run on a phone; docs/IOS_MARKETPLACE.md says what is and is not checked.
#import <UIKit/UIKit.h>

@interface HZLauncherMarketplaceController : UITableViewController
@end

// One project's page: the facts, and the Install / Update / Remove button.
@class HZMarketProject, HZMarketIndex;
@interface HZMarketProjectController : UIViewController
- (instancetype)initWithProject:(HZMarketProject *)project index:(HZMarketIndex *)index;
@end
