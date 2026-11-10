// Downloads one Marketplace file (M14, step 3) and hands it to MarketInstaller. The network half only:
//   * the first address must pass HZMarketIndex isRegistryFileURL (the registry's release host);
//   * GitHub answers that address with a redirect to its asset host, so a redirect is followed only to
//     https on github.com or *.githubusercontent.com, and at most 5 times; any other host is refused;
//   * the answer is cut off after the size the index lists (plus nothing), so a hostile server cannot
//     fill the phone; the SHA-256 in the index is what finally pins the bytes (MarketInstaller);
//   * a whole request is cut off after 120 seconds without data.
#import <Foundation/Foundation.h>
#import "MarketIndex.h"

NS_ASSUME_NONNULL_BEGIN

@interface HZMarketFetcher : NSObject
// Whether a redirect target is allowed. Public so a test can read the rule.
+ (BOOL)isAllowedRedirectHost:(NSString *)host scheme:(NSString *)scheme;

// Starts the download into `stagingDir`. `progress` (0...1) and `done` run on the main queue. `done`
// gets the temp file's path on success, or an error sentence. Cancel with -cancel.
- (void)fetch:(HZMarketFile *)file
   stagingDir:(NSString *)stagingDir
     progress:(void (^)(double fraction))progress
         done:(void (^)(NSString *_Nullable path, NSString *_Nullable error))done;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
