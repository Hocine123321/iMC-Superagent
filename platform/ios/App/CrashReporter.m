#import "CrashReporter.h"
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <execinfo.h>
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <pthread.h>
#include <signal.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int gFd = -1;                         // crash.txt, opened at install time
static char gRunningPath[1024];              // the marker file
static char gBreadcrumb[160];                // last step reached (written by any thread)
static char gMemory[160];
static char gStack[200];                     // main thread stack bounds, set at install                    // last memory figures (refreshed by the main thread)
static struct sigaction gOld[32];
static const int kSignals[] = { SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP, SIGFPE, SIGSYS };

void horizon_ios_breadcrumb(const char *step) {
    if (!step) return;
    strlcpy(gBreadcrumb, step, sizeof gBreadcrumb);
    // Also to the file at once, so a kill with no signal still shows the last step.
    if (gFd >= 0) {
        char line[256];
        int n = snprintf(line, sizeof line, "breadcrumb: %s\n", gBreadcrumb);
        if (n > 0) (void)!write(gFd, line, (size_t)n);
    }
}

// --- async-signal-safe output helpers (no malloc, no stdio) ---
static void Out(const char *s) { if (gFd >= 0) (void)!write(gFd, s, strlen(s)); }
static void OutHex(unsigned long long v) {
    char b[19]; b[0]='0'; b[1]='x';
    for (int i = 0; i < 16; i++) b[2+i] = "0123456789abcdef"[(v >> (60 - 4*i)) & 0xf];
    b[18] = 0; Out(b);
}
static void OutDec(long long v) {
    char b[24]; int i = 23; b[i] = 0; int neg = v < 0; unsigned long long u = neg ? -v : v;
    do { b[--i] = '0' + (u % 10); u /= 10; } while (u);
    if (neg) b[--i] = '-';
    Out(b + i);
}

static void RefreshMemory(void) {
    task_vm_info_data_t info; mach_msg_type_number_t cnt = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &cnt) == KERN_SUCCESS) {
        snprintf(gMemory, sizeof gMemory, "footprint %llu MB, limit remaining %llu MB",
                 (unsigned long long)(info.phys_footprint >> 20),
                 (unsigned long long)(info.limit_bytes_remaining >> 20));
    }
}

static void OnSignal(int sig, siginfo_t *si, void *ctx) {
    Out("\n=== FATAL SIGNAL ===\nsignal: "); OutDec(sig);
    Out("\nfault address: "); OutHex((unsigned long long)(uintptr_t)si->si_addr);
    Out("\ncode: "); OutDec(si->si_code);
    char name[64] = "?"; pthread_getname_np(pthread_self(), name, sizeof name);
    Out("\nthread: "); Out(name); Out(pthread_main_np() ? " (main)" : "");
    Out("\nbreadcrumb: "); Out(gBreadcrumb);
    Out("\nmain thread stack: "); Out(gStack);
    Out("\nmemory (last seen): "); Out(gMemory);
    Out("\nbacktrace (address, image, offset):\n");
    void *frames[64]; int n = backtrace(frames, 64);
    for (int i = 0; i < n; i++) {
        Dl_info d;
        OutDec(i); Out("  "); OutHex((unsigned long long)(uintptr_t)frames[i]);
        if (dladdr(frames[i], &d)) {
            const char *img = d.dli_fname ? strrchr(d.dli_fname, '/') : NULL;
            Out("  "); Out(img ? img + 1 : "?");
            Out("  +"); OutHex((unsigned long long)((uintptr_t)frames[i] - (uintptr_t)d.dli_fbase));
            if (d.dli_sname) { Out("  "); Out(d.dli_sname); }
        }
        Out("\n");
    }
    Out("image load addresses:\n");
    for (uint32_t i = 0; i < _dyld_image_count() && i < 8; i++) {
        const char *p = _dyld_get_image_name(i); const char *b = p ? strrchr(p, '/') : NULL;
        OutDec(i); Out("  "); Out(b ? b + 1 : "?"); Out("  slide "); OutHex((unsigned long long)_dyld_get_image_vmaddr_slide(i)); Out("\n");
    }
    if (gFd >= 0) fsync(gFd);
    // Hand on to the previous handler (the system's crash logger) so iOS still records it.
    struct sigaction *old = &gOld[sig];
    signal(sig, SIG_DFL);
    if (old->sa_flags & SA_SIGINFO) { if (old->sa_sigaction) old->sa_sigaction(sig, si, ctx); }
    else if (old->sa_handler && old->sa_handler != SIG_DFL && old->sa_handler != SIG_IGN) old->sa_handler(sig);
    raise(sig);
}

static void OnException(NSException *e) {
    NSMutableString *s = [NSMutableString stringWithFormat:
        @"\n=== UNCAUGHT OBJECTIVE-C EXCEPTION ===\nname: %@\nreason: %@\nbreadcrumb: %s\nmemory (last seen): %s\ncall stack:\n",
        e.name, e.reason, gBreadcrumb, gMemory];
    for (NSString *l in e.callStackSymbols) [s appendFormat:@"%@\n", l];
    const char *c = s.UTF8String;
    if (gFd >= 0 && c) { (void)!write(gFd, c, strlen(c)); fsync(gFd); }
}

void HorizonCrashReporterCleanExit(void) {
    if (gRunningPath[0]) unlink(gRunningPath);
}

void HorizonInstallCrashReporter(NSString *root) {
    NSString *crash = [root stringByAppendingPathComponent:@"crash.txt"];
    NSString *marker = [root stringByAppendingPathComponent:@".running"];
    NSFileManager *fm = [NSFileManager defaultManager];

    // The previous run: a leftover marker means it ended without a signal or an exception.
    NSString *previous = @"";
    if ([fm fileExistsAtPath:crash]) previous = [NSString stringWithContentsOfFile:crash encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSString *banner = @"";
    // How many runs in a row ended with no signal and no exception (a debugger stop, a swipe in
    // the app switcher, the system's memory kill). "Straight to game" (LauncherModel) puts up
    // the launcher only when this reaches three, which looks like a kill loop, not for one stop.
    NSString *countFile = [root stringByAppendingPathComponent:@"unclean-ends"];
    NSInteger unclean = [[NSString stringWithContentsOfFile:countFile encoding:NSUTF8StringEncoding error:nil] integerValue];
    if ([fm fileExistsAtPath:marker]) {
        unclean += 1;
        [[NSString stringWithFormat:@"%ld\n", (long)unclean] writeToFile:countFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *m = [NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:nil] ?: @"";
        banner = [NSString stringWithFormat:@"=== PREVIOUS RUN ENDED WITHOUT A SIGNAL OR EXCEPTION ===\n"
                  "(the system probably killed it; memory is the usual cause)\n%@\n", m];
    }
    // Keep the last report beside the new one: crash.txt is the newest, crash-previous.txt before.
    // Only a report that records a crash is kept: crash.txt is rewritten at every launch, and a
    // launch that did not crash (the launcher, then the game) must not overwrite the evidence.
    BOOL wasCrash = [previous containsString:@"=== FATAL SIGNAL"] || [previous containsString:@"=== UNCAUGHT"]
                 || [previous containsString:@"=== PREVIOUS RUN ENDED"];
    if (wasCrash) [previous writeToFile:[root stringByAppendingPathComponent:@"crash-previous.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];

    gFd = open(crash.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    NSString *head = [NSString stringWithFormat:@"%@launch: %@\ndevice: iOS %@\n",
                      banner, [NSDate date], UIDevice.currentDevice.systemVersion];
    if (gFd >= 0) (void)!write(gFd, head.UTF8String, strlen(head.UTF8String));

    {
        // The main thread's stack: the base (highest address), its size and the current depth, so
        // the report can say whether a fault address is just past the end of it.
        pthread_t t = pthread_self();
        void *base = pthread_get_stackaddr_np(t);
        size_t size = pthread_get_stacksize_np(t);
        char here; 
        snprintf(gStack, sizeof gStack, "base %p size %zu KB, low end %p, in use at start %ld KB, main=%d",
                 base, size / 1024, (char *)base - size, (long)(((char *)base - &here) / 1024), pthread_main_np());
        NSString *line = [NSString stringWithFormat:@"main thread stack: %s\n", gStack];
        if (gFd >= 0) (void)!write(gFd, line.UTF8String, strlen(line.UTF8String));
    }

    strlcpy(gRunningPath, marker.fileSystemRepresentation, sizeof gRunningPath);
    [@"" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];

    // An alternate stack, so a stack overflow can still run the handler.
    static char altstack[64 * 1024];
    stack_t ss = { .ss_sp = altstack, .ss_size = sizeof altstack, .ss_flags = 0 };
    sigaltstack(&ss, NULL);
    for (size_t i = 0; i < sizeof kSignals / sizeof *kSignals; i++) {
        struct sigaction sa; memset(&sa, 0, sizeof sa);
        sa.sa_sigaction = OnSignal; sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
        sigemptyset(&sa.sa_mask);
        sigaction(kSignals[i], &sa, &gOld[kSignals[i]]);
    }
    NSSetUncaughtExceptionHandler(OnException);

    // Memory figures every second on the main run loop, and the marker follows the app state: the
    // marker holds the figures, so a system kill leaves them behind.
    RefreshMemory();
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
        RefreshMemory();
        NSString *s = [NSString stringWithFormat:@"last seen: %s\nbreadcrumb: %s\n", gMemory, gBreadcrumb];
        [s writeToFile:marker atomically:NO encoding:NSUTF8StringEncoding error:nil];
    }];
    // A run that lasted fifteen seconds was not a crash loop, whatever ends it: the count starts over.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [fm removeItemAtPath:countFile error:nil];
    });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil
        usingBlock:^(NSNotification *n) { [fm removeItemAtPath:marker error:nil]; [fm removeItemAtPath:countFile error:nil]; }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil
        usingBlock:^(NSNotification *n) { [@"" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil]; }];
}
