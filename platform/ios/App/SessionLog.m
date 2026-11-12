#import "SessionLog.h"
#import <UIKit/UIKit.h>
#include <mach/mach.h>
#include <os/proc.h>
#include <sys/utsname.h>

// How often a row is written, and the size at which the file is replaced by a fresh one.
static const double kEverySeconds = 5.0;
static const unsigned long long kMaxBytes = 2ull * 1024 * 1024;

static dispatch_source_t gTimer;
static NSFileHandle *gHandle;
static NSString *gPath;
static NSString *gPreviousPath;
static CFAbsoluteTime gStart;

// The state the sampler reads on a non-main thread. UIApplication.applicationState and
// UIDevice battery properties are main-thread API, so a notification on the main thread keeps
// these two up to date and the timer only reads them.
static volatile int gForeground = 1;

static NSString *ThermalName(NSInteger s) {
    switch (s) {
        case NSProcessInfoThermalStateNominal:  return @"nominal";
        case NSProcessInfoThermalStateFair:     return @"fair";
        case NSProcessInfoThermalStateSerious:  return @"serious";
        case NSProcessInfoThermalStateCritical: return @"critical";
        default:                                return @"unknown";
    }
}
static NSString *BatteryStateName(NSInteger s) {
    switch (s) {
        case UIDeviceBatteryStateUnplugged: return @"unplugged";
        case UIDeviceBatteryStateCharging:  return @"charging";
        case UIDeviceBatteryStateFull:      return @"full";
        default:                            return @"unknown";
    }
}

static const char *kColumns = "seconds,footprint_mb,available_mb,thermal,low_power,battery_pct,battery_state,foreground,main_ticks_per_s,main_stalls,main_worst_ms";

// Main-thread responsiveness. A display link on the main run loop is asked for once per screen refresh; how many
// ticks arrive per second, and how many gaps are long (over 50 ms) and how long the worst one is, says whether the
// thread that feeds the engine's window events and the launcher is being held up. It is the cheapest honest
// measure of "laggy" that needs no change to the engine: a tick is a counter increment and a clock read.
// (The engine's own frame time is not measured here; that still needs an engine hook.)
static volatile uint32_t gTicks;
static volatile uint32_t gStalls;
static volatile uint32_t gWorstMs;
static CFTimeInterval gLastTick;

@interface HZTickProbe : NSObject
- (void)tick:(CADisplayLink *)link;
@end
@implementation HZTickProbe
- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = CACurrentMediaTime();
    if (gLastTick > 0) {
        uint32_t ms = (uint32_t)((now - gLastTick) * 1000.0);
        if (ms > 50) gStalls++;
        if (ms > gWorstMs) gWorstMs = ms;
    }
    gLastTick = now;
    gTicks++;
}
@end
static CADisplayLink *gLink;

// seconds,footprint_mb,available_mb,thermal,low_power,battery_pct,battery_state,foreground
// A value the system could not give is empty, never 0: a 0 would read as a measurement.
// The same line with the main-thread probe's three columns. ticksPerSecond < 0 means no reading (empty cells).
NSString *HorizonSessionLogLineWithTicks(double seconds, unsigned long long footprintMB,
                                unsigned long long availableMB, NSInteger thermal,
                                BOOL lowPower, float battery, NSInteger batteryState,
                                BOOL foreground, double ticksPerSecond, unsigned stalls, unsigned worstMs) {
    NSString *fp = footprintMB == ULLONG_MAX ? @"" : [NSString stringWithFormat:@"%llu", footprintMB];
    NSString *av = availableMB == ULLONG_MAX ? @"" : [NSString stringWithFormat:@"%llu", availableMB];
    // UIDevice.batteryLevel is -1 when monitoring is off or the level is unknown.
    NSString *bat = battery < 0 ? @"" : [NSString stringWithFormat:@"%d", (int)lroundf(battery * 100.0f)];
    NSString *probe = ticksPerSecond < 0 ? @",," : [NSString stringWithFormat:@"%.1f,%u,%u", ticksPerSecond, stalls, worstMs];
    return [NSString stringWithFormat:@"%.1f,%@,%@,%@,%d,%@,%@,%d,%@", seconds, fp, av,
            ThermalName(thermal), lowPower ? 1 : 0, bat, BatteryStateName(batteryState),
            foreground ? 1 : 0, probe];
}

NSString *HorizonSessionLogLine(double seconds, unsigned long long footprintMB,
                                unsigned long long availableMB, NSInteger thermal,
                                BOOL lowPower, float battery, NSInteger batteryState,
                                BOOL foreground) {
    return HorizonSessionLogLineWithTicks(seconds, footprintMB, availableMB, thermal, lowPower, battery,
                                          batteryState, foreground, -1, 0, 0);
}

static unsigned long long FootprintMB(void) {
    task_vm_info_data_t info; mach_msg_type_number_t cnt = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &cnt) != KERN_SUCCESS) return ULLONG_MAX;
    return info.phys_footprint >> 20;
}
static unsigned long long AvailableMB(void) {
    // os_proc_available_memory is 0 when the process has no limit to report (the simulator).
    size_t b = os_proc_available_memory();
    return b == 0 ? ULLONG_MAX : (unsigned long long)(b >> 20);
}

static void Append(NSString *text) {
    NSData *d = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!gHandle || !d) return;
    @try { [gHandle writeData:d]; } @catch (__unused NSException *e) { gHandle = nil; }
}

static NSString *Machine(void) {
    struct utsname u; uname(&u);
    return [NSString stringWithUTF8String:u.machine];
}

static void StartNewFile(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:gPreviousPath error:nil];
    if ([fm fileExistsAtPath:gPath]) [fm moveItemAtPath:gPath toPath:gPreviousPath error:nil];
    [fm createFileAtPath:gPath contents:nil attributes:nil];
    gHandle = [NSFileHandle fileHandleForWritingAtPath:gPath];
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSDate *now = [NSDate date];
    NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
    // Comment lines first, so the file says which phone and build it came from.
    Append([NSString stringWithFormat:
            @"# iMC Horizon session log. Stays on this phone; nothing is sent.\n"
            @"# started: %@\n# device: %@  iOS %@\n# app: %@ (%@)\n# every %.0f s\n%s\n",
            [iso stringFromDate:now], Machine(), [UIDevice currentDevice].systemVersion,
            info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"], kEverySeconds, kColumns]);
}

static void Sample(void) {
    double seconds = CFAbsoluteTimeGetCurrent() - gStart;
    NSProcessInfo *pi = [NSProcessInfo processInfo];
    UIDevice *dev = [UIDevice currentDevice];
    // batteryLevel and batteryState are plain property reads once monitoring is on (set on the
    // main thread at start); they are safe to read here.
    // Read and reset the probe's counters. The window is the time since the last sample, so the rate is per second
    // whatever the timer's drift. In the background the display link does not fire: no reading, empty cells.
    static CFAbsoluteTime lastSample;
    CFAbsoluteTime nowAbs = CFAbsoluteTimeGetCurrent();
    double window = lastSample > 0 ? nowAbs - lastSample : 0;
    lastSample = nowAbs;
    uint32_t ticks = gTicks, stalls = gStalls, worst = gWorstMs;
    gTicks = 0; gStalls = 0; gWorstMs = 0;
    double rate = (window > 0.5 && gForeground != 0 && ticks > 0) ? ticks / window : -1;
    NSString *line = HorizonSessionLogLineWithTicks(seconds, FootprintMB(), AvailableMB(), pi.thermalState,
                                           pi.lowPowerModeEnabled, dev.batteryLevel,
                                           dev.batteryState, gForeground != 0, rate, stalls, worst);
    Append([line stringByAppendingString:@"\n"]);
    // A long session replaces the file rather than growing it without bound.
    if (gHandle && [gHandle offsetInFile] > kMaxBytes) StartNewFile();
}

void HorizonStartSessionLog(NSString *root) {
    if (gTimer) return;
    gPath = [root stringByAppendingPathComponent:@"session-log.csv"];
    gPreviousPath = [root stringByAppendingPathComponent:@"session-log-previous.csv"];
    gStart = CFAbsoluteTimeGetCurrent();
    StartNewFile();
    // Main-thread work: battery monitoring on, and the foreground flag from the lifecycle.
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil
                    usingBlock:^(__unused NSNotification *n) { gForeground = 0; }];
        [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:nil
                    usingBlock:^(__unused NSNotification *n) { gForeground = 1; }];
        // The app object may not exist yet (the engine creates it); until the first lifecycle
        // notification the app counts as in the foreground, which is where every run starts.
        UIApplication *app = [UIApplication sharedApplication];
        if (app) gForeground = app.applicationState != UIApplicationStateBackground;
        // The main-thread probe (see HZTickProbe). Added to the main run loop, in common modes so a scroll or a
        // touch does not pause it. Asked for the screen's own rate; it costs one counter and one clock read a tick.
        gLink = [CADisplayLink displayLinkWithTarget:[HZTickProbe new] selector:@selector(tick:)];
        [gLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    });
    dispatch_queue_t q = dispatch_queue_create("dev.imc.sessionlog", DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(q, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(gTimer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              (uint64_t)(kEverySeconds * NSEC_PER_SEC), NSEC_PER_SEC / 2);
    dispatch_source_set_event_handler(gTimer, ^{ Sample(); });
    dispatch_resume(gTimer);
}
