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

static const char *kColumns = "seconds,footprint_mb,available_mb,thermal,low_power,battery_pct,battery_state,foreground";

// seconds,footprint_mb,available_mb,thermal,low_power,battery_pct,battery_state,foreground
// A value the system could not give is empty, never 0: a 0 would read as a measurement.
NSString *HorizonSessionLogLine(double seconds, unsigned long long footprintMB,
                                unsigned long long availableMB, NSInteger thermal,
                                BOOL lowPower, float battery, NSInteger batteryState,
                                BOOL foreground) {
    NSString *fp = footprintMB == ULLONG_MAX ? @"" : [NSString stringWithFormat:@"%llu", footprintMB];
    NSString *av = availableMB == ULLONG_MAX ? @"" : [NSString stringWithFormat:@"%llu", availableMB];
    // UIDevice.batteryLevel is -1 when monitoring is off or the level is unknown.
    NSString *bat = battery < 0 ? @"" : [NSString stringWithFormat:@"%d", (int)lroundf(battery * 100.0f)];
    return [NSString stringWithFormat:@"%.1f,%@,%@,%@,%d,%@,%@,%d", seconds, fp, av,
            ThermalName(thermal), lowPower ? 1 : 0, bat, BatteryStateName(batteryState),
            foreground ? 1 : 0];
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
    NSString *line = HorizonSessionLogLine(seconds, FootprintMB(), AvailableMB(), pi.thermalState,
                                           pi.lowPowerModeEnabled, dev.batteryLevel,
                                           dev.batteryState, gForeground != 0);
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
    });
    dispatch_queue_t q = dispatch_queue_create("dev.imc.sessionlog", DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(q, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(gTimer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              (uint64_t)(kEverySeconds * NSEC_PER_SEC), NSEC_PER_SEC / 2);
    dispatch_source_set_event_handler(gTimer, ^{ Sample(); });
    dispatch_resume(gTimer);
}
