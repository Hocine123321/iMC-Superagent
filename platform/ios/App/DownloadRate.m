#import "DownloadRate.h"

// Seconds of history before a speed is shown, and the weight of each new sample in the average.
static const NSTimeInterval kWarmUp = 5.0;
static const double kAlpha = 0.25;

@implementation HZDownloadRate {
    BOOL _started;
    NSTimeInterval _firstTime, _lastTime;
    unsigned long long _firstBytes, _lastBytes;
    double _smoothed;    // bytes per second, exponential average of the samples
    BOOL _haveSmoothed;
}

- (void)reset { _started = NO; _smoothed = 0; _haveSmoothed = NO; }

- (void)noteBytes:(unsigned long long)bytesDone at:(NSTimeInterval)now {
    if (!_started) {
        _started = YES; _firstTime = _lastTime = now; _firstBytes = _lastBytes = bytesDone;
        return;
    }
    if (bytesDone < _lastBytes) { _lastBytes = bytesDone; _lastTime = now; return; }   // a file was dropped
    NSTimeInterval dt = now - _lastTime;
    if (dt < 0.5) return;   // too soon to mean anything
    double sample = (double)(bytesDone - _lastBytes) / dt;
    _smoothed = _haveSmoothed ? kAlpha * sample + (1.0 - kAlpha) * _smoothed : sample;
    _haveSmoothed = YES;
    _lastBytes = bytesDone; _lastTime = now;
}

- (double)bytesPerSecond {
    if (!_started || !_haveSmoothed) return 0;
    if (_lastTime - _firstTime < kWarmUp) return 0;
    return _smoothed;
}

- (NSString *)speedText {
    double v = self.bytesPerSecond;
    return v > 0 ? [HZDownloadRate formatSpeed:v] : nil;
}

- (NSString *)timeLeftTextForRemaining:(unsigned long long)remainingBytes {
    double v = self.bytesPerSecond;
    if (v <= 0 || remainingBytes == 0) return nil;
    return [NSString stringWithFormat:@"%@ left", [HZDownloadRate formatSeconds:(double)remainingBytes / v]];
}

+ (NSString *)formatSpeed:(double)v {
    if (v >= 1000.0 * 1000.0) return [NSString stringWithFormat:@"%.1f MB/s", v / 1000000.0];
    return [NSString stringWithFormat:@"%.0f KB/s", MAX(1.0, v / 1000.0)];
}

+ (NSString *)formatSeconds:(double)s {
    if (s < 45) return [NSString stringWithFormat:@"about %d s", (int)(MAX(5.0, ceil(s / 5.0) * 5.0))];
    if (s < 90) return @"about 1 min";
    if (s < 3600) return [NSString stringWithFormat:@"about %d min", (int)llround(s / 60.0)];
    int h = (int)(s / 3600.0), m = (int)llround(fmod(s, 3600.0) / 60.0);
    if (m == 60) { h += 1; m = 0; }
    return m == 0 ? [NSString stringWithFormat:@"about %d h", h] : [NSString stringWithFormat:@"about %d h %d min", h, m];
}

@end
