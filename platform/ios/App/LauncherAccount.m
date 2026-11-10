#import "LauncherAccount.h"
#import "AccountClient.h"
#import "AccountModel.h"
#import "AccountStore.h"

@interface HZLauncherAccountController ()
@property (strong) UILabel *titleLabel, *detailLabel, *codeLabel, *noteLabel;
@property (strong) UIButton *primary, *secondary;
@property (strong) UIActivityIndicatorView *spinner;
@property (strong) HZDeviceCode *code;
@property (nonatomic) BOOL busy;
@end

@implementation HZLauncherAccountController

- (UIButton *)button:(NSString *)title filled:(BOOL)filled action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [b setTitleColor:filled ? UIColor.blackColor : UIColor.whiteColor forState:UIControlStateNormal];
    b.backgroundColor = filled ? [UIColor colorWithRed:0.36 green:0.74 blue:0.33 alpha:1] : [UIColor colorWithWhite:1 alpha:0.10];
    b.layer.cornerRadius = 12;
    [b.heightAnchor constraintEqualToConstant:48].active = YES;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Account";
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.09 blue:0.11 alpha:1];

    self.titleLabel = [UILabel new];
    self.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    self.titleLabel.textColor = UIColor.whiteColor;
    self.titleLabel.numberOfLines = 0;
    self.detailLabel = [UILabel new];
    self.detailLabel.font = [UIFont systemFontOfSize:14];
    self.detailLabel.textColor = [UIColor colorWithWhite:0.72 alpha:1];
    self.detailLabel.numberOfLines = 0;
    // The code the player types on the Microsoft page: large, spaced, easy to read aloud.
    self.codeLabel = [UILabel new];
    self.codeLabel.font = [UIFont monospacedSystemFontOfSize:34 weight:UIFontWeightHeavy];
    self.codeLabel.textColor = UIColor.whiteColor;
    self.codeLabel.hidden = YES;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = UIColor.whiteColor;
    self.primary = [self button:@"Sign in" filled:YES action:@selector(primaryTapped)];
    self.secondary = [self button:@"Cancel" filled:NO action:@selector(secondaryTapped)];
    self.secondary.hidden = YES;
    self.noteLabel = [UILabel new];
    self.noteLabel.font = [UIFont systemFontOfSize:12];
    self.noteLabel.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    self.noteLabel.numberOfLines = 0;
    self.noteLabel.text = @"Signing in is needed only to download the game; playing files already on this phone never asks for it. When you are signed in, the game plays as your profile. The sign-in stays on this phone, in the Keychain, and is removed when you sign out.";

    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[self.primary, self.secondary]];
    buttons.spacing = 12; buttons.distribution = UIStackViewDistributionFillEqually;
    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.spinner]];
    head.spacing = 10; head.alignment = UIStackViewAlignmentCenter;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[head, self.detailLabel, self.codeLabel, buttons, self.noteLabel]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:40],
        [stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-40],
    ]];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Leaving the screen ends a sign-in that is waiting: nothing should poll in the background.
    if (self.busy) [[HZAccountClient shared] cancel];
}

// Shows the state that is true now: nobody, someone, or a sign-in under way.
- (void)refresh {
    if (self.code) return;   // a sign-in is showing its code
    HZAccountState *a = [[HZAccountStore shared] account];
    self.codeLabel.hidden = YES;
    self.secondary.hidden = YES;
    [self.spinner stopAnimating];
    if (a) {
        self.titleLabel.text = a.name;
        self.detailLabel.text = a.owns ? @"Owns Minecraft: Java Edition. You can download the game."
                                       : @"This account was not confirmed as an owner. Check again, or sign in with another account.";
        [self.primary setTitle:@"Sign out" forState:UIControlStateNormal];
    } else if (HZSignInIsTestMode()) {
        self.titleLabel.text = @"Not signed in (test mode)";
        self.detailLabel.text = @"Test mode: signing in with another launcher's app ID, set on this phone only. It can stop working at any time and is not for sharing. Sign in with the Microsoft account that owns Minecraft: Java Edition.";
        [self.primary setTitle:@"Sign in" forState:UIControlStateNormal];
    } else if (!HZMicrosoftClientID()) {
        self.titleLabel.text = @"Sign-in is not set up yet";
        self.detailLabel.text = HZSignInNotConfigured;
        [self.primary setTitle:@"Sign in" forState:UIControlStateNormal];
    } else {
        self.titleLabel.text = @"Not signed in";
        self.detailLabel.text = @"Sign in with the Microsoft account that owns Minecraft: Java Edition.";
        [self.primary setTitle:@"Sign in" forState:UIControlStateNormal];
    }
    BOOL canSignIn = a || HZActiveClientID();
    self.primary.enabled = canSignIn;
    self.primary.alpha = canSignIn ? 1 : 0.45;
}

- (void)primaryTapped {
    if (self.code) { [self openMicrosoft]; return; }          // "Open the page" while a code shows
    if ([[HZAccountStore shared] account]) {
        [[HZAccountStore shared] signOut];
        [self refresh];
        return;
    }
    [self startSignIn];
}

- (void)secondaryTapped {   // Cancel
    [[HZAccountClient shared] cancel];
    self.code = nil;
    self.busy = NO;
    [self refresh];
}

- (void)startSignIn {
    self.busy = YES;
    self.primary.enabled = NO;
    self.titleLabel.text = @"Starting sign-in...";
    self.detailLabel.text = @"";
    [self.spinner startAnimating];
    __weak typeof(self) weak = self;
    [[HZAccountClient shared] requestDeviceCode:^(HZDeviceCode *code, NSString *error) {
        HZLauncherAccountController *me = weak;
        if (!me) return;
        if (!code) { [me failed:error]; return; }
        me.code = code;
        me.titleLabel.text = @"Enter this code";
        me.codeLabel.text = code.userCode;
        me.codeLabel.hidden = NO;
        me.detailLabel.text = [NSString stringWithFormat:@"Open %@ and type the code there. The code is copied for you.", code.verificationURI];
        UIPasteboard.generalPasteboard.string = code.userCode;
        [me.primary setTitle:@"Open the page" forState:UIControlStateNormal];
        me.primary.enabled = YES;
        me.secondary.hidden = NO;
        [[HZAccountClient shared] completeSignIn:code
            status:^(NSString *line) { if (weak.code == code) weak.titleLabel.text = line; }
            done:^(HZAccountState *account, NSString *err) {
                HZLauncherAccountController *m = weak;
                if (!m || m.code != code) return;   // cancelled or left: a late answer changes nothing
                m.code = nil;
                m.busy = NO;
                if (!account) { [m failed:err]; return; }
                [m refresh];
            }];
    }];
}

- (void)openMicrosoft {
    NSURL *url = [NSURL URLWithString:self.code.verificationURI];
    // Only Microsoft's own page: the address came from a reply, so it is checked before it is opened.
    if ([url.scheme isEqualToString:@"https"] && ([url.host isEqualToString:@"www.microsoft.com"] || [url.host isEqualToString:@"microsoft.com"] || [url.host hasSuffix:@".microsoft.com"] || [url.host hasSuffix:@".live.com"])) {
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    }
}

- (void)failed:(NSString *)message {
    self.code = nil;
    self.busy = NO;
    [self.spinner stopAnimating];
    [self refresh];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Could not sign in"
        message:message ?: @"Microsoft sign-in failed." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
@end
