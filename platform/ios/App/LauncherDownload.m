#import "LauncherDownload.h"
#import "LauncherTheme.h"
#import "GlassControls.h"
#import "LauncherModel.h"
#import "Downloader.h"
#import "DownloadRate.h"
#import "AccountClient.h"
#import "AccountStore.h"
#import "AccountModel.h"

static NSString *const kVersion = @"26.3";

@interface HZLauncherDownloadController ()
@property (strong) UILabel *titleLabel, *detailLabel, *numbersLabel, *fileLabel, *gateLabel;
@property (strong) HZGlassProgress *bar;
@property (strong) UIButton *startButton, *stopButton;
@property (strong) HZDownloader *downloader;
@property (strong) HZDownloadRate *rate;   // speed and time left, fed from the progress callbacks
@property (nonatomic) BOOL busy;
@end

@implementation HZLauncherDownloadController

- (NSString *)gameFolder { return [[HZLauncherModel shared].root stringByAppendingPathComponent:@"minecraft"]; }
- (NSString *)overridePath { return [[HZLauncherModel shared].root stringByAppendingPathComponent:@"developer-download"]; }
- (BOOL)overrideOn { return [[NSFileManager defaultManager] fileExistsAtPath:[self overridePath]]; }

- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *b = [HZTheme buttonWithTitle:title symbol:nil prominent:NO target:self action:action];
    [b.heightAnchor constraintEqualToConstant:52].active = YES;
    return b;
}

- (UILabel *)label:(CGFloat)size weight:(UIFontWeight)w white:(CGFloat)white {
    UILabel *l = [UILabel new];
    l.font = [UIFont systemFontOfSize:size weight:w];
    l.textColor = white >= 0.95 ? [HZTheme text] : white >= 0.8 ? [HZTheme text] : white >= 0.7 ? [HZTheme secondaryText] : [HZTheme tertiaryText];
    l.numberOfLines = 0;
    return l;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Download Minecraft";
    [HZTheme styleScreen:self];

    self.titleLabel = [self label:22 weight:UIFontWeightBold white:1];
    self.detailLabel = [self label:14 weight:UIFontWeightRegular white:0.72];
    self.gateLabel = [self label:13 weight:UIFontWeightRegular white:0.6];
    self.numbersLabel = [self label:14 weight:UIFontWeightSemibold white:0.9];
    self.fileLabel = [self label:11 weight:UIFontWeightRegular white:0.6];
    self.fileLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.fileLabel.numberOfLines = 1;
    self.bar = (HZGlassProgress *)[HZTheme glassProgressView];
    self.bar.hidden = YES;

    self.startButton = [self button:@"Download Minecraft 26.3" action:@selector(start)];
    self.stopButton = [self button:@"Stop" action:@selector(stop)];
    self.stopButton.hidden = YES;

    UIStackView *left = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.detailLabel, self.bar, self.numbersLabel, self.fileLabel, self.gateLabel]];
    left.axis = UILayoutConstraintAxisVertical; left.spacing = 10;
    UIStackView *right = [[UIStackView alloc] initWithArrangedSubviews:@[self.startButton, self.stopButton]];
    right.axis = UILayoutConstraintAxisVertical; right.spacing = 12;
    // Portrait: the text, then the buttons under it, in a column that scrolls.
    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[left, right]];
    column.axis = UILayoutConstraintAxisVertical; column.spacing = 24;
    [HZTheme scrollColumn:column onScreen:self];
    [self showIdle];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Leaving the screen does not stop a download that is running: the app keeps going while it is
    // in the foreground. Closing the app does stop it, and the next run carries on.
}

static NSString *Bytes(unsigned long long b) {
    return [NSByteCountFormatter stringFromByteCount:(long long)b countStyle:NSByteCountFormatterCountStyleFile];
}

- (void)showIdle {
    self.titleLabel.text = @"Download Minecraft 26.3";
    self.detailLabel.text = @"Downloads your copy of the game from Mojang's servers: the game, its libraries and the sounds and "
                            @"other assets, about 673 MB. Every file is checked against the checksum Mojang lists. "
                            @"If it is interrupted, starting again carries on with what is missing.";
    self.gateLabel.text = [self overrideOn]
        ? @"Developer override is on (the file developer-download is in the Horizon folder): the sign-in check is skipped."
        : @"You need to be signed in to an account that owns Minecraft: Java Edition (Account screen).";
    self.numbersLabel.text = @"";
    self.fileLabel.text = @"";
    self.bar.hidden = YES;
    self.startButton.enabled = YES;
    self.stopButton.hidden = YES;
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - the gate, then the run

- (void)start {
    if (self.busy) return;
    self.busy = YES;
    self.startButton.enabled = NO;
    if ([self overrideOn]) { [self begin]; return; }

    HZAccountState *acct = [[HZAccountStore shared] account];
    if (!acct) {
        [self gateRefused:@"Sign in first. Open Account on the launcher and sign in with the Microsoft account that owns Minecraft: Java Edition."];
        return;
    }
    self.titleLabel.text = @"Checking your account...";
    self.detailLabel.text = @"Asking Microsoft and Mojang that this account owns Minecraft: Java Edition.";
    // A fresh answer when the services can be reached; offline, the last answer stands (HZMayDownload).
    // The download itself needs the network, so being offline ends here with a plain message.
    [[HZAccountClient shared] recheck:^(BOOL reachable, BOOL owns, NSString *error) {
        HZAccountState *now = [[HZAccountStore shared] account];
        if (!HZMayDownload(now != nil, now.owns, reachable, owns)) {
            [self gateRefused:reachable ? @"This account does not own Minecraft: Java Edition, so the game cannot be downloaded."
                                        : @"Could not check your account and it has not passed before. Connect to the internet and try again."];
            return;
        }
        [self begin];
    }];
}

- (void)gateRefused:(NSString *)why {
    self.busy = NO;
    [self showIdle];
    [self alert:@"Cannot download yet" message:why];
}

- (void)begin {
    self.downloader = [[HZDownloader alloc] initWithRoot:[self gameFolder] version:kVersion];
    self.bar.hidden = NO;
    self.bar.progress = 0;
    self.stopButton.hidden = NO;
    self.stopButton.enabled = YES;
    // Keep the screen awake while a 673 MB download runs; restored when it ends.
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    self.rate = [HZDownloadRate new];
    __weak typeof(self) weak = self;
    [self.downloader startWithProgress:^(HZDownloadProgress *p) { [weak apply:p]; }];
}

- (void)stop {
    self.stopButton.enabled = NO;
    self.detailLabel.text = @"Stopping...";
    [self.downloader cancel];
}

- (void)apply:(HZDownloadProgress *)p {
    switch (p.phase) {
        case HZPhaseLooking: case HZPhaseChecking:
            self.titleLabel.text = p.phase == HZPhaseLooking ? @"Preparing the download..." : @"Checking what is already here...";
            self.detailLabel.text = p.message;
            break;
        case HZPhaseDownloading:
            self.titleLabel.text = @"Downloading Minecraft 26.3";
            self.detailLabel.text = @"Keep the app open. Stopping is safe: finished files are kept.";
            self.fileLabel.text = p.message;
            break;
        case HZPhaseDone:
            self.busy = NO;
            UIApplication.sharedApplication.idleTimerDisabled = NO;
            self.titleLabel.text = @"Download finished";
            self.detailLabel.text = p.message;
            self.stopButton.hidden = YES;
            self.startButton.enabled = YES;
            [HZTheme setTitle:@"Check again" onButton:self.startButton];
            self.fileLabel.text = @"";
            break;
        case HZPhaseFailed:
            self.busy = NO;
            UIApplication.sharedApplication.idleTimerDisabled = NO;
            self.titleLabel.text = @"The download stopped";
            self.detailLabel.text = [p.error stringByAppendingString:@"\n\nStart again to carry on: files that finished are kept."];
            self.stopButton.hidden = YES;
            self.startButton.enabled = YES;
            [HZTheme setTitle:@"Try again" onButton:self.startButton];
            self.fileLabel.text = @"";
            break;
        case HZPhaseCancelled:
            self.busy = NO;
            UIApplication.sharedApplication.idleTimerDisabled = NO;
            self.titleLabel.text = @"Stopped";
            self.detailLabel.text = p.message;
            self.stopButton.hidden = YES;
            self.startButton.enabled = YES;
            [HZTheme setTitle:@"Continue" onButton:self.startButton];
            self.fileLabel.text = @"";
            break;
        case HZPhaseIdle: break;
    }
    if (p.bytesTotal > 0) {
        self.bar.progress = (float)((double)p.bytesDone / (double)p.bytesTotal);
        NSString *numbers = [NSString stringWithFormat:@"%@ of %@   (%lu of %lu files)", Bytes(p.bytesDone), Bytes(p.bytesTotal),
                             (unsigned long)p.filesDone, (unsigned long)p.filesTotal];
        // Speed and time left only while files are really coming in, and only once there is enough to be honest.
        if (p.phase == HZPhaseDownloading) {
            [self.rate noteBytes:p.bytesDone at:NSProcessInfo.processInfo.systemUptime];
            NSString *speed = [self.rate speedText];
            NSString *left = [self.rate timeLeftTextForRemaining:p.bytesTotal > p.bytesDone ? p.bytesTotal - p.bytesDone : 0];
            if (speed) numbers = [numbers stringByAppendingFormat:@"\n%@%@", speed, left ? [@"  ·  " stringByAppendingString:left] : @""];
        }
        self.numbersLabel.text = numbers;
    }
}

@end
