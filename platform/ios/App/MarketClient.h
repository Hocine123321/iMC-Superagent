// Fetches the Horizon registry's index.json (M14, step 1) and keeps the last good copy, so the
// Marketplace opens offline. The rules for what a good index is are in MarketIndex; this class only
// moves bytes and decides which copy to trust:
//   * the address is fixed (the registry's GitHub Pages site); nothing else is ever fetched here;
//   * an answer over 16 MiB is refused after it arrives (MarketIndex), and a whole request is cut off
//     after 60 seconds;
//   * what comes back is parsed and checked BEFORE it replaces the cache, so a broken or hostile
//     answer can never overwrite a good copy;
//   * a copy newer than ten minutes is used without asking the network (as the desktop launcher does);
//   * with no network, or a refused answer, the cached copy is used and the result says so.
#import <Foundation/Foundation.h>
#import "MarketIndex.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HZMarketSource) {
    HZMarketFresh,     // just fetched from the registry
    HZMarketCached,    // the copy fetched earlier, still within ten minutes
    HZMarketOffline,   // the registry could not be used; this is an older copy
};

@interface HZMarketResult : NSObject
@property (nonatomic, strong, nullable) HZMarketIndex *index;
@property (nonatomic) HZMarketSource source;
@property (nonatomic, strong, nullable) NSDate *fetched;      // when this copy was fetched
@property (nonatomic, copy, nullable) NSString *error;        // set when `index` is nil, or why the old copy was used
@end

@interface HZMarketClient : NSObject
// `cacheDirectory` is where horizon-index.json lives (inside the Horizon folder, so the file manager shows it).
- (instancetype)initWithCacheDirectory:(NSString *)cacheDirectory;

// Calls `done` on the main queue. `force` skips the ten-minute freshness window (pull to refresh).
- (void)loadForce:(BOOL)force completion:(void (^)(HZMarketResult *result))done NS_SWIFT_NAME(load(force:completion:));

+ (NSString *)indexURL;
+ (NSTimeInterval)freshSeconds;   // 600
@end

NS_ASSUME_NONNULL_END
