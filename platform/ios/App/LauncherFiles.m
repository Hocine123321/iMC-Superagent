#import "LauncherFiles.h"
#import "LauncherTheme.h"
#import "GlassControls.h"
#import "LauncherModel.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface HZLauncherFilesController ()
@property (strong) UILabel *stateLabel, *detailLabel, *progressLabel;
@property (strong) HZGlassProgress *progress;
@property (strong) UIButton *importButton, *checkButton, *deleteButton;
@property (nonatomic) BOOL busy;
@end

@implementation HZLauncherFilesController

- (UIButton *)button:(NSString *)title action:(SEL)action destructive:(BOOL)destructive {
    UIButton *b = [HZTheme buttonWithTitle:title symbol:destructive ? @"trash" : nil prominent:NO target:self action:action];
    if (destructive) { UIButtonConfiguration *c = b.configuration; c.baseForegroundColor = [HZTheme danger]; b.configuration = c; }
    [b.heightAnchor constraintEqualToConstant:52].active = YES;
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Game files";
    [HZTheme styleScreen:self];

    self.stateLabel = [UILabel new];
    self.stateLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    self.stateLabel.textColor = [HZTheme text];
    self.detailLabel = [UILabel new];
    self.detailLabel.font = [UIFont systemFontOfSize:14];
    self.detailLabel.textColor = [HZTheme secondaryText];
    self.detailLabel.numberOfLines = 0;
    self.progress = (HZGlassProgress *)[HZTheme glassProgressView];
    self.progress.hidden = YES;
    self.progressLabel = [UILabel new];
    self.progressLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.progressLabel.textColor = [HZTheme tertiaryText];
    self.progressLabel.hidden = YES;

    UILabel *help = [UILabel new];
    help.numberOfLines = 0;
    help.font = [UIFont systemFontOfSize:13];
    help.textColor = [HZTheme tertiaryText];
    help.text = @"Prepare the game on your computer with the Horizon launcher, copy the version folder "
                @"(the one holding horizon-resources.json, for example 26.3) to the phone, then choose Import "
                @"and pick that folder. About 500 MB; the phone needs room for the old and new copy while it works.";

    self.importButton = [self button:@"Import a folder..." action:@selector(pickFolder) destructive:NO];
    self.checkButton = [self button:@"Check the files" action:@selector(check) destructive:NO];
    self.deleteButton = [self button:@"Delete the game files" action:@selector(confirmDelete) destructive:YES];

    UIStackView *left = [[UIStackView alloc] initWithArrangedSubviews:@[self.stateLabel, self.detailLabel, self.progress, self.progressLabel, help]];
    left.axis = UILayoutConstraintAxisVertical; left.spacing = 10;
    UIStackView *right = [[UIStackView alloc] initWithArrangedSubviews:@[self.importButton, self.checkButton, self.deleteButton]];
    right.axis = UILayoutConstraintAxisVertical; right.spacing = 12;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[left, right]];
    row.spacing = 36; row.alignment = UIStackViewAlignmentCenter; row.distribution = UIStackViewDistributionFillEqually;
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

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    for (UIButton *b in @[self.importButton, self.checkButton, self.deleteButton]) b.enabled = !busy;
    self.progress.hidden = self.progressLabel.hidden = !busy;
}

- (void)refresh {
    HZLauncherModel *m = [HZLauncherModel shared];
    NSString *problem = nil;
    HZFilesState s = [m checkFiles:&problem];
    self.stateLabel.text = s == HZFilesReady ? @"Game files are ready" : s == HZFilesMissing ? @"No game files" : @"Game files are damaged";
    NSString *where = @"Files > On My iPhone > Horizon > Horizon > resources";
    if (s == HZFilesReady) {
        self.detailLabel.text = [NSString stringWithFormat:@"%lu items in\n%@", (unsigned long)[m topLevelItemCount], where];
    } else {
        self.detailLabel.text = [NSString stringWithFormat:@"%@\nLooking in: %@", problem ?: @"", where];
    }
    self.deleteButton.enabled = !self.busy && [m topLevelItemCount] > 0;
}

- (void)check {
    NSString *problem = nil;
    HZFilesState s = [[HZLauncherModel shared] checkFiles:&problem];
    [self refresh];
    [self alert:s == HZFilesReady ? @"The files look good" : @"Problem found"
        message:s == HZFilesReady ? @"horizon-resources.json is present and valid, and no other top-level JSON file is empty. "
                                    @"This is the same test the game makes before it starts."
                                  : problem];
}

- (void)pickFolder {
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder]];
    p.delegate = self;
    p.allowsMultipleSelection = NO;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    self.busy = YES;
    self.progress.progress = 0;
    self.progressLabel.text = @"Starting...";
    [[HZLauncherModel shared] importFolderAtURL:url completion:^(NSError *error) {
        self.busy = NO;
        [self refresh];
        if (error) [self alert:@"Import failed" message:error.localizedDescription];
        else [self alert:@"Import finished" message:@"The game files are on the phone. Go back and press Play."];
    } progress:^(double fraction, NSString *file) {
        self.progress.progress = (float)fraction;
        self.progressLabel.text = file;
    }];
}

- (void)confirmDelete {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Delete the game files?"
        message:@"This removes the resources folder (about 500 MB). Your worlds and settings are kept."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        NSFileManager *fm = [NSFileManager defaultManager];
        HZLauncherModel *m = [HZLauncherModel shared];
        NSError *e = nil;
        [fm removeItemAtPath:m.resources error:&e];
        [fm createDirectoryAtPath:m.resources withIntermediateDirectories:YES attributes:nil error:nil];
        [self refresh];
        if (e) [self alert:@"Could not delete" message:e.localizedDescription];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
@end
