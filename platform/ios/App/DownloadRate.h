// Download speed and time left (M24 stage 4), kept apart from the screen so the rules can be read and
// tested without UIKit. It is fed the bytes done now and then, smooths them, and says nothing until it
// has enough to be honest: a number that jumps around is worse than none.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HZDownloadRate : NSObject
// Forget everything (a new run).
- (void)reset;
// `bytesDone` is the total on the phone so far; `now` is seconds from any steady clock.
// A value that goes down (a file dropped) is ignored for the speed.
- (void)noteBytes:(unsigned long long)bytesDone at:(NSTimeInterval)now;
// Smoothed bytes per second, or 0 while there is not enough data (under about 5 seconds, or no progress).
@property (nonatomic, readonly) double bytesPerSecond;
// "4.2 MB/s", or nil while unknown.
- (nullable NSString *)speedText;
// "about 3 min left", "about 40 s left", or nil while unknown or when nothing is left.
- (nullable NSString *)timeLeftTextForRemaining:(unsigned long long)remainingBytes NS_SWIFT_NAME(timeLeftText(remaining:));

// Pure helpers, public so a test can read them.
+ (NSString *)formatSpeed:(double)bytesPerSecond;
+ (NSString *)formatSeconds:(double)seconds;
@end

NS_ASSUME_NONNULL_END
