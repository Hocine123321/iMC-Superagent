#import "LauncherDiagnostics.h"
#import "LauncherTheme.h"
#import "LauncherModel.h"

@interface HZLauncherDiagnosticsController ()
@property (strong) UITextView *text;
@property (strong) UISegmentedControl *which;
@end

@implementation HZLauncherDiagnosticsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Diagnostics";
    [HZTheme styleScreen:self];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                                           target:self action:@selector(share:)];
    self.which = [[UISegmentedControl alloc] initWithItems:@[@"Crash report", @"Game log"]];
    self.which.selectedSegmentIndex = 0;
    [self.which addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    self.which.translatesAutoresizingMaskIntoConstraints = NO;

    self.text = [UITextView new];
    self.text.editable = NO;
    self.text.backgroundColor = [HZTheme codeBackground];
    self.text.textColor = [HZTheme text];
    self.text.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.text.layer.cornerRadius = 10;
    self.text.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:self.which];
    [self.view addSubview:self.text];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.which.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [self.which.centerXAnchor constraintEqualToAnchor:g.centerXAnchor],
        [self.which.widthAnchor constraintEqualToConstant:280],
        [self.text.topAnchor constraintEqualToAnchor:self.which.bottomAnchor constant:8],
        [self.text.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [self.text.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
        [self.text.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-8],
    ]];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reload]; }

- (void)reload {
    HZLauncherModel *m = [HZLauncherModel shared];
    NSString *t = self.which.selectedSegmentIndex == 0 ? [m crashReportText] : [m gameLogText];
    self.text.text = t.length ? t : (self.which.selectedSegmentIndex == 0
        ? @"No crash report. The game has not crashed since the files were last cleared."
        : @"No game log yet. It appears after the game has run once.");
}

// Shares every diagnostic file that exists, as files, so the person can AirDrop or message them.
- (void)share:(UIBarButtonItem *)item {
    NSArray *files = [[HZLauncherModel shared] diagnosticFiles];
    if (!files.count) return;
    UIActivityViewController *a = [[UIActivityViewController alloc] initWithActivityItems:files applicationActivities:nil];
    a.popoverPresentationController.barButtonItem = item;
    [self presentViewController:a animated:YES completion:nil];
}
@end
