#import "LauncherAbout.h"

// Horizon's licence, copied byte for byte from horizon/LICENSE (the MIT licence requires the notice to
// travel with copies). tests/about_check.py compares this text with that file.
static NSString *const kHorizonLicense =
    @"MIT License\n"
    @"\n"
    @"Copyright (c) 2026 Ludovic Marie and the Horizon contributors\n"
    @"\n"
    @"Permission is hereby granted, free of charge, to any person obtaining a copy\n"
    @"of this software and associated documentation files (the \"Software\"), to deal\n"
    @"in the Software without restriction, including without limitation the rights\n"
    @"to use, copy, modify, merge, publish, distribute, sublicense, and/or sell\n"
    @"copies of the Software, and to permit persons to whom the Software is\n"
    @"furnished to do so, subject to the following conditions:\n"
    @"\n"
    @"The above copyright notice and this permission notice shall be included in all\n"
    @"copies or substantial portions of the Software.\n"
    @"\n"
    @"THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\n"
    @"IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\n"
    @"FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\n"
    @"AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\n"
    @"LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\n"
    @"OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\n"
    @"SOFTWARE.\n"
    @"";

@interface HZLauncherAboutController ()
@property (strong) UITextView *text;
@end

@implementation HZLauncherAboutController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"About";
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.09 blue:0.11 alpha:1];
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *version = info[@"CFBundleShortVersionString"] ?: @"?";

    NSMutableAttributedString *s = [NSMutableAttributedString new];
    UIColor *white = UIColor.whiteColor, *grey = [UIColor colorWithWhite:0.75 alpha:1];
    void (^add)(NSString *, UIFont *, UIColor *) = ^(NSString *t, UIFont *f, UIColor *c) {
        [s appendAttributedString:[[NSAttributedString alloc] initWithString:t attributes:@{NSFontAttributeName: f, NSForegroundColorAttributeName: c}]];
    };
    UIFont *h1 = [UIFont systemFontOfSize:26 weight:UIFontWeightHeavy], *h2 = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    UIFont *body = [UIFont systemFontOfSize:14], *mono = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];

    add(@"iMC Horizon\n", h1, white);
    add([NSString stringWithFormat:@"Launcher %@   Minecraft 26.3\n\n", version], body, grey);
    add(@"What this is\n", h2, white);
    add(@"An unofficial iOS port of Horizon, a Minecraft: Java Edition client written in Rust. It is a personal "
        @"engineering project, not a product of Mojang or Microsoft.\n\n", body, grey);
    add(@"Not an official Minecraft product\n", h2, white);
    add(@"This app is not made by, approved by or associated with Mojang Studios, Microsoft or Xbox. Minecraft is a "
        @"trademark of Mojang Studios. The app contains no Minecraft code or assets: you need your own copy of "
        @"Minecraft: Java Edition, which this app downloads from Mojang's servers to your phone after you sign in "
        @"with the account that owns it.\n\n", body, grey);
    add(@"Built on\n", h2, white);
    add(@"Horizon, by Ludovic Marie and the Horizon contributors, under the MIT licence below. Project site: "
        @"https://playhorizon.dev   Source: https://github.com/horizon-rust/horizon\n\n", body, grey);
    add(@"This app's source\n", h2, white);
    add(@"https://github.com/Hocine123321/iMC-Superagent\n\n", body, grey);
    add(@"Privacy\n", h2, white);
    add(@"The launcher keeps its logs on the phone and sends them nowhere unless you share them yourself. The game "
        @"itself sends Horizon's anonymous \"I'm playing\" ping to telemetry.playhorizon.dev once a minute while you "
        @"play, as Horizon does on every platform.\n\n", body, grey);
    add(@"Licence of Horizon\n", h2, white);
    add(kHorizonLicense, mono, grey);
    add(@"\nOther components and their licences are listed in Horizon's THIRD_PARTY_NOTICES.md, in the source "
        @"repository above (horizon/THIRD_PARTY_NOTICES.md). They are not yet shown inside the app.\n", body, grey);

    self.text = [UITextView new];
    self.text.editable = NO;
    self.text.dataDetectorTypes = UIDataDetectorTypeLink;
    self.text.linkTextAttributes = @{NSForegroundColorAttributeName: [UIColor colorWithRed:0.36 green:0.74 blue:0.33 alpha:1]};
    self.text.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    self.text.textContainerInset = UIEdgeInsetsMake(16, 16, 16, 16);
    self.text.layer.cornerRadius = 10;
    self.text.attributedText = s;
    self.text.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.text];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.text.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [self.text.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-8],
        [self.text.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [self.text.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
    ]];
}
@end
