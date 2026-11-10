#import "LauncherHome.h"
#import "LauncherModel.h"
#import "LauncherFiles.h"
#import "LauncherDiagnostics.h"
#import "LauncherAccount.h"
#import "LauncherDownload.h"
#import "LauncherFileManager.h"
#import "LauncherAbout.h"
#import "LauncherMarketplace.h"
#import "AccountClient.h"
#import "AccountStore.h"
#import "CrashReporter.h"

static UIColor *Accent(void) { return [UIColor colorWithRed:0.36 green:0.74 blue:0.33 alpha:1]; }

@interface HZLauncherHomeController ()
@property (strong) UILabel *statusTitle, *statusDetail, *versionLabel;
@property (strong) UIButton *playButton, *filesButton, *fileManagerButton, *downloadButton, *diagButton, *accountButton, *aboutButton, *marketButton;
@property (strong) UISwitch *directSwitch;
@property (strong) UIView *statusDot;
@property (strong) UIActivityIndicatorView *spinner;
@end

@implementation HZLauncherHomeController

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (UIButton *)buttonWithTitle:(NSString *)title filled:(BOOL)filled action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:filled ? 22 : 17 weight:filled ? UIFontWeightBold : UIFontWeightSemibold];
    b.layer.cornerRadius = 14;
    if (filled) {
        b.backgroundColor = Accent();
        [b setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
        [b setTitleColor:[UIColor colorWithWhite:0.25 alpha:1] forState:UIControlStateDisabled];
    } else {
        b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    }
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Once per run of the launcher: renews a saved sign-in in the background, so the game that
    // starts next has a Minecraft token that is not a day old (GameSession.h). Silent: it shows
    // nothing, and a network failure keeps the last answer instead of signing the player out.
    // The game itself never reaches the network for this: with "open straight into the game" on, the
    // launcher is skipped and the token is as fresh as the last time the launcher was open.
    if ([[HZAccountStore shared] account]) [[HZAccountClient shared] recheck:^(BOOL reachable, BOOL owns, NSString *error) {}];
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.09 blue:0.11 alpha:1];

    UILabel *name = [UILabel new];
    name.text = @"iMC Horizon";
    name.font = [UIFont systemFontOfSize:34 weight:UIFontWeightHeavy];
    name.textColor = UIColor.whiteColor;

    self.versionLabel = [UILabel new];
    self.versionLabel.font = [UIFont systemFontOfSize:14];
    self.versionLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    self.versionLabel.text = [NSString stringWithFormat:@"Launcher %@   Minecraft 26.3",
                              info[@"CFBundleShortVersionString"] ?: @"?"];

    UIStackView *titleBox = [[UIStackView alloc] initWithArrangedSubviews:@[name, self.versionLabel]];
    titleBox.axis = UILayoutConstraintAxisVertical; titleBox.spacing = 2;

    // The state of the game files: a coloured dot, one line, one line of detail.
    self.statusDot = [UIView new];
    self.statusDot.layer.cornerRadius = 6;
    self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statusDot.widthAnchor constraintEqualToConstant:12].active = YES;
    [self.statusDot.heightAnchor constraintEqualToConstant:12].active = YES;
    self.statusTitle = [UILabel new];
    self.statusTitle.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    self.statusTitle.textColor = UIColor.whiteColor;
    self.statusDetail = [UILabel new];
    self.statusDetail.font = [UIFont systemFontOfSize:14];
    self.statusDetail.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    self.statusDetail.numberOfLines = 0;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = UIColor.whiteColor;
    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[self.statusDot, self.statusTitle, self.spinner]];
    head.spacing = 10; head.alignment = UIStackViewAlignmentCenter;
    UIStackView *status = [[UIStackView alloc] initWithArrangedSubviews:@[head, self.statusDetail]];
    status.axis = UILayoutConstraintAxisVertical; status.spacing = 6;

    self.playButton = [self buttonWithTitle:@"Play" filled:YES action:@selector(play)];
    self.filesButton = [self buttonWithTitle:@"Game files" filled:NO action:@selector(openFiles)];
    self.fileManagerButton = [self buttonWithTitle:@"File manager" filled:NO action:@selector(openFileManager)];
    self.downloadButton = [self buttonWithTitle:@"Download Minecraft" filled:NO action:@selector(openDownload)];
    self.diagButton = [self buttonWithTitle:@"Diagnostics" filled:NO action:@selector(openDiagnostics)];
    self.accountButton = [self buttonWithTitle:@"Account" filled:NO action:@selector(openAccount)];
    self.marketButton = [self buttonWithTitle:@"Marketplace" filled:NO action:@selector(openMarket)];
    [self.marketButton.heightAnchor constraintEqualToConstant:48].active = YES;
    self.aboutButton = [self buttonWithTitle:@"About" filled:NO action:@selector(openAbout)];
    [self.aboutButton.heightAnchor constraintEqualToConstant:48].active = YES;
    [self.accountButton.heightAnchor constraintEqualToConstant:48].active = YES;
    [self.playButton.heightAnchor constraintEqualToConstant:64].active = YES;
    [self.filesButton.heightAnchor constraintEqualToConstant:48].active = YES;
    [self.diagButton.heightAnchor constraintEqualToConstant:48].active = YES;
    [self.downloadButton.heightAnchor constraintEqualToConstant:48].active = YES;
    [self.fileManagerButton.heightAnchor constraintEqualToConstant:48].active = YES;

    UIStackView *secondary = [[UIStackView alloc] initWithArrangedSubviews:@[self.filesButton, self.fileManagerButton, self.accountButton, self.diagButton]];
    secondary.spacing = 12; secondary.distribution = UIStackViewDistributionFillEqually;
    // Getting the game onto the phone is the first thing a new install needs: its own full-width row.

    // Skip this screen on the next opens: straight into the game when the files are ready.
    UILabel *directLabel = [UILabel new];
    directLabel.text = @"Open straight into the game";
    directLabel.font = [UIFont systemFontOfSize:15];
    directLabel.textColor = UIColor.whiteColor;
    directLabel.numberOfLines = 0;
    self.directSwitch = [UISwitch new];
    self.directSwitch.onTintColor = Accent();
    self.directSwitch.on = [HZLauncherModel shared].opensGameDirectly;
    [self.directSwitch addTarget:self action:@selector(directChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *direct = [[UIStackView alloc] initWithArrangedSubviews:@[directLabel, self.directSwitch]];
    direct.spacing = 12; direct.alignment = UIStackViewAlignmentCenter;
    UILabel *directNote = [UILabel new];
    directNote.text = @"Skips this screen when the game files are ready. Stopping the app (from Xcode, StikDebug or the app switcher) does not bring it back. It comes back after a crash, after the app ends four times in a row within 15 seconds, or when a file named open-launcher is in the Horizon folder.";
    directNote.font = [UIFont systemFontOfSize:12];
    directNote.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    directNote.numberOfLines = 0;

    UIStackView *right = [[UIStackView alloc] initWithArrangedSubviews:@[status, self.playButton, self.downloadButton, self.marketButton, secondary, self.aboutButton, direct, directNote]];
    right.axis = UILayoutConstraintAxisVertical; right.spacing = 18;

    // Landscape (the app is landscape-only): the name on the left, the controls on the right.
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[titleBox, right]];
    row.spacing = 40; row.alignment = UIStackViewAlignmentCenter; row.distribution = UIStackViewDistributionFillEqually;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:row];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [row.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
        [row.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:40],
        [row.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-40],
    ]];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }

// Reads the disk and shows it. The size walk is off the main thread: it touches every file.
- (void)refresh {
    HZLauncherModel *m = [HZLauncherModel shared];
    NSString *problem = nil;
    HZFilesState state = [m checkFiles:&problem];
    switch (state) {
        case HZFilesMissing:
            self.statusDot.backgroundColor = [UIColor colorWithRed:0.95 green:0.65 blue:0.2 alpha:1];
            self.statusTitle.text = @"No game files yet";
            self.statusDetail.text = @"Open Game files to import the folder you prepared on your computer.";
            [self.spinner stopAnimating];
            break;
        case HZFilesDamaged:
            self.statusDot.backgroundColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1];
            self.statusTitle.text = @"Game files need attention";
            self.statusDetail.text = [problem stringByAppendingString:@" Open Game files to import them again."];
            [self.spinner stopAnimating];
            break;
        case HZFilesReady:
            self.statusDot.backgroundColor = Accent();
            self.statusTitle.text = @"Ready to play";
            self.statusDetail.text = @"Checking the size of the game files...";
            [self.spinner startAnimating];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                unsigned long long bytes = [m resourcesSize];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.spinner stopAnimating];
                    self.statusDetail.text = [NSString stringWithFormat:@"Game files %@ on this phone.",
                        [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile]];
                });
            });
            break;
    }
    // Who the game will play as: the signed-in profile (GameSession.h), else it plays offline.
    HZAccountState *signedIn = [[HZAccountStore shared] account];
    [self.accountButton setTitle:signedIn.name.length ? [NSString stringWithFormat:@"Account: %@", signedIn.name] : @"Account"
                        forState:UIControlStateNormal];
    BOOL ready = state == HZFilesReady;
    self.playButton.enabled = ready;
    self.playButton.alpha = ready ? 1 : 0.45;
}

- (void)directChanged:(UISwitch *)sender {
    [HZLauncherModel shared].opensGameDirectly = sender.on;
}

// Play: the game is a different run of the app. Leave the flag, say what happens, and exit
// the launcher so the next open starts the game. iOS apps cannot restart themselves.
- (void)play {
    HZLauncherModel *m = [HZLauncherModel shared];
    if (![m setStartGameFlag]) {
        [self alert:@"Could not start" message:@"The launcher could not write its start flag in the Horizon folder."];
        return;
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Starting the game"
        message:@"iMC Horizon will close now. Open it again and the game starts."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Close app" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        // iOS cannot restart an app, and the game needs a fresh main(): end the process so the
        // next open starts the game. (Not App Store material, which is not the aim here.)
        HorizonCrashReporterCleanExit();
        exit(0);
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) {
        [m consumeStartGameFlag];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)openFiles {
    [self.navigationController pushViewController:[HZLauncherFilesController new] animated:YES];
}
- (void)openMarket {
    [self.navigationController pushViewController:[HZLauncherMarketplaceController new] animated:YES];
}
- (void)openAbout {
    [self.navigationController pushViewController:[HZLauncherAboutController new] animated:YES];
}
- (void)openFileManager {
    [self.navigationController pushViewController:[[HZLauncherFileManagerController alloc] initWithPath:@""] animated:YES];
}
- (void)openDownload {
    [self.navigationController pushViewController:[HZLauncherDownloadController new] animated:YES];
}
- (void)openAccount {
    [self.navigationController pushViewController:[HZLauncherAccountController new] animated:YES];
}
- (void)openDiagnostics {
    [self.navigationController pushViewController:[HZLauncherDiagnosticsController new] animated:YES];
}
- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
@end
