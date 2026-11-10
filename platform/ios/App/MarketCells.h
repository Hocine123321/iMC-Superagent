// What a Marketplace list row shows, and the card that draws it. One row type for every source, so the list does
// not care whether a pack comes from Horizon's registry or from Modrinth.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HZRowState) {
    HZRowGet,          // can be installed
    HZRowInstalled,    // installed (the version is in `stateText`)
    HZRowUnavailable,  // listed but cannot be installed here (native mod, signed, not supported)
};

@interface HZMarketRow : NSObject
@property (nonatomic, copy) NSString *title, *subtitle, *summary, *kind, *source;   // source: "Horizon" or "Modrinth"
@property (nonatomic, copy, nullable) NSString *stateText;
@property (nonatomic) HZRowState state;
@property (nonatomic, strong, nullable) id payload;   // HZMarketProject or HZModrinthProject
@end

@interface HZMarketCardCell : UITableViewCell
+ (NSString *)reuseIdentifier;
- (void)configure:(HZMarketRow *)row compact:(BOOL)compact;
@end

// The symbol and colour a kind gets.
NSString *HZMarketSymbolForKind(NSString *kind);
UIColor *HZMarketColorForKind(NSString *kind);
NSString *HZMarketKindName(NSString *kind);

NS_ASSUME_NONNULL_END
