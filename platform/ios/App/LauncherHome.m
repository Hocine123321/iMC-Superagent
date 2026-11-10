#import "LauncherHome.h"
#import "LauncherModel.h"
#import "LauncherFiles.h"
#import "LauncherDiagnostics.h"
#import "LauncherAccount.h"
#import "LauncherDownload.h"
#import "LauncherFileManager.h"
#import "LauncherAbout.h"
#import "LauncherMarketplace.h"
#import "LauncherTheme.h"
#import "LauncherSettings.h"
#import "AccountClient.h"
#import "AccountStore.h"
#import "CrashReporter.h"

static UIColor *Accent(void) { return [HZTheme accent]; }

@interface HZLauncherHomeController ()
@property (strong) UILabel *statusTitle, *statusDetail, *versionLabel;
@property (strong) UIButton *playButton, *filesButton, *downloadButton, *accountButton, *marketButton, *moreButton;
@property (strong) UIView *statusDot;
@property (strong) UIActivityIndicatorView *spinner;
@end

@implementation HZLauncherHomeController

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleDefault; }

// The status card and the "..." menu: a glass surface holding content. Plain card where there is no glass.
- (UIVisualEffectView *)card {
    UIVisualEffectView *v = [HZTheme glassViewWithTint:nil interactive:NO cornerRadius:24];
    return v;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Once per run of the launcher: renews a saved sign-in in the background, so the game that
    // starts next has a Minecraft token that is not a day old (GameSession.h). Silent: it shows
    // nothing, and a network failure keeps the last answer instead of signing the player out.
    // The game itself never reaches the network for this: with "open straight into the game" on, the
    // launcher is skipped and the token is as fresh as the last time the launcher was open.
    if ([[HZAccountStore shared] account]) [[HZAccountClient shared] recheck:^(BOOL reachable, BOOL owns, NSString *error) {}];
    [HZTheme styleScreen:self];
    [self addBackdrop];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(themeChanged) name:HZThemeChanged object:nil];

    // ---- Left: who this is, and the state of the game files.
    UILabel *name = [HZTheme labelWithSize:44 weight:UIFontWeightHeavy color:[HZTheme text]];
    name.text = @"iMC Horizon";
    name.numberOfLines = 1; name.adjustsFontSizeToFitWidth = YES; name.minimumScaleFactor = 0.6;

    self.versionLabel = [HZTheme labelWithSize:14 weight:UIFontWeightMedium color:[HZTheme secondaryText]];
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    self.versionLabel.text = [NSString stringWithFormat:@"Launcher %@  \u00B7  Minecraft 26.3",
                              info[@"CFBundleShortVersionString"] ?: @"?"];

    self.statusDot = [UIView new];
    self.statusDot.layer.cornerRadius = 6;
    self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statusDot.widthAnchor constraintEqualToConstant:12].active = YES;
    [self.statusDot.heightAnchor constraintEqualToConstant:12].active = YES;
    self.statusTitle = [HZTheme labelWithSize:18 weight:UIFontWeightSemibold color:[HZTheme text]];
    self.statusDetail = [HZTheme labelWithSize:14 weight:UIFontWeightRegular color:[HZTheme secondaryText]];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[self.statusDot, self.statusTitle, self.spinner]];
    head.spacing = 10; head.alignment = UIStackViewAlignmentCenter;
    UIStackView *statusText = [[UIStackView alloc] initWithArrangedSubviews:@[head, self.statusDetail]];
    statusText.axis = UILayoutConstraintAxisVertical; statusText.spacing = 6;
    statusText.translatesAutoresizingMaskIntoConstraints = NO;
    UIVisualEffectView *statusCard = [self card];
    [statusCard.contentView addSubview:statusText];
    [NSLayoutConstraint activateConstraints:@[
        [statusText.topAnchor constraintEqualToAnchor:statusCard.contentView.topAnchor constant:16],
        [statusText.bottomAnchor constraintEqualToAnchor:statusCard.contentView.bottomAnchor constant:-16],
        [statusText.leadingAnchor constraintEqualToAnchor:statusCard.contentView.leadingAnchor constant:18],
        [statusText.trailingAnchor constraintEqualToAnchor:statusCard.contentView.trailingAnchor constant:-18],
    ]];

    UIStackView *left = [[UIStackView alloc] initWithArrangedSubviews:@[name, self.versionLabel, statusCard]];
    left.axis = UILayoutConstraintAxisVertical; left.spacing = 6;
    [left setCustomSpacing:22 afterView:self.versionLabel];

    // ---- Right: Play, then the four things a player reaches for, in a grid.
    self.playButton = [HZTheme buttonWithTitle:@"Play" symbol:@"play.fill" prominent:YES target:self action:@selector(play)];
    [self.playButton.heightAnchor constraintEqualToConstant:76].active = YES;
    self.downloadButton = [HZTheme buttonWithTitle:@"Download" symbol:@"arrow.down.circle" prominent:NO target:self action:@selector(openDownload)];
    self.marketButton = [HZTheme buttonWithTitle:@"Marketplace" symbol:@"square.grid.2x2" prominent:NO target:self action:@selector(openMarket)];
    self.filesButton = [HZTheme buttonWithTitle:@"Game files" symbol:@"folder" prominent:NO target:self action:@selector(openFiles)];
    self.accountButton = [HZTheme buttonWithTitle:@"Account" symbol:@"person.crop.circle" prominent:NO target:self action:@selector(openAccount)];
    for (UIButton *b in @[self.downloadButton, self.marketButton, self.filesButton, self.accountButton])
        [b.heightAnchor constraintEqualToConstant:56].active = YES;

    UIStackView *r1 = [[UIStackView alloc] initWithArrangedSubviews:@[self.downloadButton, self.marketButton]];
    UIStackView *r2 = [[UIStackView alloc] initWithArrangedSubviews:@[self.filesButton, self.accountButton]];
    for (UIStackView *r in @[r1, r2]) { r.spacing = 12; r.distribution = UIStackViewDistributionFillEqually; }
    UIStackView *right = [[UIStackView alloc] initWithArrangedSubviews:@[self.playButton, r1, r2]];
    right.axis = UILayoutConstraintAxisVertical; right.spacing = 12;

    // Landscape (the app is landscape-only): the name on the left, the controls on the right.
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[left, right]];
    row.spacing = 48; row.alignment = UIStackViewAlignmentCenter; row.distribution = UIStackViewDistributionFillEqually;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:row];

    // ---- Top right: the "..." button. Everything that is not needed every time lives behind it.
    self.moreButton = [HZTheme iconButtonWithSymbol:@"ellipsis" label:@"More"];
    // A pull-down menu opened by a tap, rebuilt each time so the checkmarks are current.
    self.moreButton.showsMenuAsPrimaryAction = YES;
    self.moreButton.menu = [self buildMenu];
    [self.view addSubview:self.moreButton];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [row.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
        [row.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:40],
        [row.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-40],
        [self.moreButton.topAnchor constraintEqualToAnchor:g.topAnchor constant:12],
        [self.moreButton.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],
        [self.moreButton.widthAnchor constraintEqualToConstant:48],
        [self.moreButton.heightAnchor constraintEqualToConstant:48],
    ]];
}

// Soft colour behind the glass, so the glass has something to refract. Follows dark/light.
- (void)addBackdrop {
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.name = @"backdrop";
    grad.frame = self.view.bounds;
    [self.view.layer insertSublayer:grad atIndex:0];
    [self updateBackdrop];
}
- (void)updateBackdrop {
    for (CALayer *l in self.view.layer.sublayers) {
        if (![l.name isEqualToString:@"backdrop"]) continue;
        CAGradientLayer *grad = (CAGradientLayer *)l;
        UITraitCollection *t = self.traitCollection;
        UIColor *top = [[HZTheme accent] resolvedColorWithTraitCollection:t];
        float k = [HZTheme glassStrength];
        grad.colors = @[(id)[top colorWithAlphaComponent:(t.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.45 : 0.40) * k].CGColor,
                        (id)[[HZTheme background] resolvedColorWithTraitCollection:t].CGColor];
        grad.startPoint = CGPointMake(0, 0); grad.endPoint = CGPointMake(0.9, 1);
        grad.frame = self.view.bounds;
    }
}
- (void)themeChanged { [self updateBackdrop]; self.moreButton.menu = [self buildMenu]; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self updateBackdrop]; }
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self updateBackdrop];
}

// The "..." menu, in groups. Library holds the places files live; Tools the things for when something is
// wrong; Settings opens the page with the appearance, glass and start-up choices. Quick appearance stays
// in the menu as a submenu with a check on the current choice, because it is the thing most often flipped.
- (UIMenu *)buildMenu {
    HZAppearance current = [HZTheme appearance];
    NSMutableArray *looks = [NSMutableArray array];
    NSArray *choices = @[@(HZAppearanceSystem), @(HZAppearanceDark), @(HZAppearanceLight)];
    NSArray *icons = @[@"circle.lefthalf.filled", @"moon.fill", @"sun.max.fill"];
    for (NSUInteger i = 0; i < choices.count; i++) {
        HZAppearance a = (HZAppearance)[choices[i] integerValue];
        UIAction *act = [UIAction actionWithTitle:[HZTheme nameOfAppearance:a] image:[UIImage systemImageNamed:icons[i]]
                                       identifier:nil handler:^(UIAction *x) {
            [HZTheme setAppearance:a];
            self.moreButton.menu = [self buildMenu];
        }];
        act.state = a == current ? UIMenuElementStateOn : UIMenuElementStateOff;
        [looks addObject:act];
    }
    UIMenu *appearance = [UIMenu menuWithTitle:@"Appearance" image:[UIImage systemImageNamed:@"circle.lefthalf.filled"]
                                    identifier:nil options:0 children:looks];

    UIAction *fm = [UIAction actionWithTitle:@"File manager" image:[UIImage systemImageNamed:@"folder.badge.gearshape"]
                                  identifier:nil handler:^(UIAction *x) { [self openFileManager]; }];
    UIAction *files = [UIAction actionWithTitle:@"Game files" image:[UIImage systemImageNamed:@"shippingbox"]
                                     identifier:nil handler:^(UIAction *x) { [self openFiles]; }];
    UIAction *diag = [UIAction actionWithTitle:@"Diagnostics" image:[UIImage systemImageNamed:@"stethoscope"]
                                    identifier:nil handler:^(UIAction *x) { [self openDiagnostics]; }];
    UIAction *settings = [UIAction actionWithTitle:@"Settings" image:[UIImage systemImageNamed:@"gearshape"]
                                        identifier:nil handler:^(UIAction *x) { [self openSettings]; }];
    UIAction *about = [UIAction actionWithTitle:@"About" image:[UIImage systemImageNamed:@"info.circle"]
                                     identifier:nil handler:^(UIAction *x) { [self openAbout]; }];

    UIMenu *library = [UIMenu menuWithTitle:@"Library" image:[UIImage systemImageNamed:@"books.vertical"] identifier:nil options:0 children:@[fm, files]];
    UIMenu *tools = [UIMenu menuWithTitle:@"Tools" image:[UIImage systemImageNamed:@"wrench.and.screwdriver"] identifier:nil options:0 children:@[diag]];
    UIMenu *group1 = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[library, tools]];
    UIMenu *group2 = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[appearance, settings]];
    UIMenu *group3 = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[about]];
    return [UIMenu menuWithTitle:@"" children:@[group1, group2, group3]];
}

- (void)openSettings {
    [self.navigationController pushViewController:[HZLauncherSettingsController new] animated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.moreButton.menu = [self buildMenu];
    [self refresh];
}

// Reads the disk and shows it. The size walk is off the main thread: it touches every file.
- (void)refresh {
    HZLauncherModel *m = [HZLauncherModel shared];
    NSString *problem = nil;
    HZFilesState state = [m checkFiles:&problem];
    switch (state) {
        case HZFilesMissing:
            self.statusDot.backgroundColor = [HZTheme warning];
            self.statusTitle.text = @"No game files yet";
            self.statusDetail.text = @"Open Game files to import the folder you prepared on your computer.";
            [self.spinner stopAnimating];
            break;
        case HZFilesDamaged:
            self.statusDot.backgroundColor = [HZTheme danger];
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
    [HZTheme setTitle:signedIn.name.length ? signedIn.name : @"Account" onButton:self.accountButton];
    BOOL ready = state == HZFilesReady;
    self.playButton.enabled = ready;
    self.playButton.alpha = ready ? 1 : 0.45;
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
