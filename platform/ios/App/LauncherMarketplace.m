#import "LauncherMarketplace.h"
#import "LauncherTheme.h"
#import "MarketClient.h"
#import "LauncherModel.h"
#import "MarketInstaller.h"
#import "MarketFetcher.h"
#import "GlassControls.h"

static NSString *const kGame = @"26.3";

// The game's own folder, the one with options.txt: what the engine is started with as --home.
static HZMarketInstaller *Installer(void) {
    return [[HZMarketInstaller alloc] initWithHome:[HZLauncherModel shared].home];
}

static UIColor *Accent(void) { return [HZTheme accent]; }

static NSString *MarketSupportText(HZMarketSupport s) {
    switch (s) {
        case HZMarketInstallable: return @"Works on iPhone";
        case HZMarketNeedsDesktop: return @"Needs a desktop build";
        case HZMarketNotYet: return @"Not supported yet";
    }
}

static NSString *MarketKindText(NSString *kind) {
    NSDictionary *names = @{@"mod": @"Mod", @"native-mod": @"Native mod", @"resourcepack": @"Resource pack", @"shader": @"Shader",
                            @"modpack": @"Modpack", @"shaderpack": @"Shader pack", @"datapack": @"Data pack"};
    return names[kind] ?: kind;
}

@interface HZLauncherMarketplaceController () <UISearchResultsUpdating>
@property (strong) HZMarketClient *client;
@property (strong) HZMarketIndex *index;
@property (copy) NSArray<HZMarketProject *> *shown;
@property (strong) UIControl *filter;
@property (strong) UIView *header;
@property (strong) UISearchController *search;
@property (strong) UILabel *banner;
@property (nonatomic) BOOL loading;
@end

@implementation HZLauncherMarketplaceController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _client = [[HZMarketClient alloc] initWithCacheDirectory:[[HZLauncherModel shared].root stringByAppendingPathComponent:@"marketplace"]];
        _shown = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Marketplace";
    [HZTheme styleScreen:self];
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.tableView.separatorColor = [HZTheme separator];

    // Glass tabs, in a header above the list. "Installed" is what this app put on the phone.
    self.filter = [HZTheme glassSegmentedWithItems:@[@"Works on iPhone", @"Installed", @"All", @"Mods", @"Packs", @"Shaders"] selected:0];
    [self.filter addTarget:self action:@selector(refilter) forControlEvents:UIControlEventValueChanged];
    UIView *head = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 56)];
    self.filter.translatesAutoresizingMaskIntoConstraints = NO;
    [head addSubview:self.filter];
    [NSLayoutConstraint activateConstraints:@[
        [self.filter.centerYAnchor constraintEqualToAnchor:head.centerYAnchor],
        [self.filter.leadingAnchor constraintEqualToAnchor:head.leadingAnchor constant:16],
        [self.filter.trailingAnchor constraintEqualToAnchor:head.trailingAnchor constant:-16]]];
    self.tableView.tableHeaderView = head;
    self.header = head;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(forceReload)];

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"Search the registry";
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    self.banner = [UILabel new];
    self.banner.numberOfLines = 0;
    self.banner.font = [UIFont systemFontOfSize:12];
    self.banner.textColor = [HZTheme tertiaryText];
    [self load:NO];
}

- (void)forceReload { [self load:YES]; }

- (void)load:(BOOL)force {
    if (self.loading) return;
    self.loading = YES;
    self.banner.text = @"Loading the registry...";
    [self.tableView reloadData];
    [self.client loadForce:force completion:^(HZMarketResult *r) {
        self.loading = NO;
        if (r.index) {
            self.index = r.index;
            NSString *when = r.fetched ? [NSDateFormatter localizedStringFromDate:r.fetched dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle] : @"";
            switch (r.source) {
                case HZMarketFresh: self.banner.text = @"Up to date."; break;
                case HZMarketCached: self.banner.text = [NSString stringWithFormat:@"Loaded %@.", when]; break;
                case HZMarketOffline: self.banner.text = [NSString stringWithFormat:@"Could not reach the registry%@. Showing the copy from %@.",
                                                          r.error ? [NSString stringWithFormat:@" (%@)", r.error] : @"", when]; break;
            }
        } else {
            self.index = nil;
            self.banner.text = r.error ?: @"The Marketplace could not be loaded.";
        }
        [self refilter];
    }];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc { [self refilter]; }

// Which projects match the tab and the search text. Search looks at name, summary, id, categories and authors.
- (void)refilter {
    NSMutableArray *out = [NSMutableArray new];
    NSMutableSet *installedIds = [NSMutableSet set];
    for (HZInstalledEntry *e in [Installer() installed]) [installedIds addObject:e.projectId];
    NSString *q = [self.search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString ?: @"";
    for (HZMarketProject *p in self.index.projects) {
        switch (((HZGlassSegmented *)self.filter).selectedSegmentIndex) {
            case 0: if (p.support != HZMarketInstallable) continue; break;
            case 1: if (![installedIds containsObject:p.projectId]) continue; break;
            case 3: if (![p.kind isEqualToString:@"mod"] && ![p.kind isEqualToString:@"native-mod"]) continue; break;
            case 4: if (![p.kind isEqualToString:@"resourcepack"] && ![p.kind isEqualToString:@"modpack"] && ![p.kind isEqualToString:@"shaderpack"] && ![p.kind isEqualToString:@"datapack"]) continue; break;
            case 5: if (![p.kind isEqualToString:@"shader"] && ![p.kind isEqualToString:@"shaderpack"]) continue; break;
            default: break;
        }
        if (q.length) {
            NSString *hay = [[@[p.name, p.summary, p.projectId, [p.categories componentsJoinedByString:@" "], [p.authors componentsJoinedByString:@" "]] componentsJoinedByString:@" "] lowercaseString];
            BOOL all = YES;
            for (NSString *w in [q componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) if (w.length && ![hay containsString:w]) { all = NO; break; }
            if (!all) continue;
        }
        [out addObject:p];
    }
    // Most downloaded first, then by name.
    [out sortUsingComparator:^NSComparisonResult(HZMarketProject *a, HZMarketProject *b) {
        if (a.downloads != b.downloads) return a.downloads > b.downloads ? NSOrderedAscending : NSOrderedDescending;
        return [a.name caseInsensitiveCompare:b.name];
    }];
    self.shown = out;
    [self.tableView reloadData];
}

#pragma mark - table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.shown.count; }

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    NSString *count = self.index ? [NSString stringWithFormat:@"%lu shown of %lu in the registry. ", (unsigned long)self.shown.count, (unsigned long)self.index.projects.count] : @"";
    return [count stringByAppendingFormat:@"%@\nNative mods change the game's source before it is compiled, so they cannot run on a phone.", self.banner.text ?: @""];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    HZMarketProject *p = self.shown[(NSUInteger)ip.row];
    cell.backgroundColor = [HZTheme surface];
    cell.textLabel.text = p.name;
    cell.textLabel.textColor = [HZTheme text];
    HZInstalledEntry *have = [Installer() installedEntryForProject:p.projectId];
    NSString *state = have ? [NSString stringWithFormat:@"Installed %@", have.version] : MarketSupportText(p.support);
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  |  %@\n%@", MarketKindText(p.kind), state, p.summary];
    cell.detailTextLabel.numberOfLines = 3;
    cell.detailTextLabel.textColor = (have || p.support == HZMarketInstallable) ? Accent() : [HZTheme secondaryText];
    cell.imageView.image = [UIImage systemImageNamed:have ? @"checkmark.circle.fill" : p.support == HZMarketInstallable ? @"arrow.down.circle" : @"nosign"];
    cell.imageView.tintColor = have ? Accent() : [HZTheme tertiaryText];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    HZMarketProject *p = self.shown[(NSUInteger)ip.row];
    [self.navigationController pushViewController:[[HZMarketProjectController alloc] initWithProject:p index:self.index] animated:YES];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; if (self.index) [self refilter]; }

@end

#pragma mark - A project's page

@interface HZMarketProjectController ()
@property (strong) HZMarketProject *project;
@property (strong) HZMarketIndex *index;
@property (strong) HZMarketVersion *version;       // what Install would fetch; nil when nothing can be
@property (copy) NSString *refusal;                // why not, in words
@property (strong) UITextView *text;
@property (strong) UIButton *installButton, *removeButton;
@property (strong) HZGlassProgress *bar;
@property (strong) UILabel *statusLabel;
@property (strong) HZMarketFetcher *fetcher;
@property (nonatomic) BOOL busy;
@end

@implementation HZMarketProjectController

- (instancetype)initWithProject:(HZMarketProject *)p index:(HZMarketIndex *)index {
    if ((self = [super initWithNibName:nil bundle:nil])) { _project = p; _index = index; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    HZMarketProject *p = self.project;
    self.title = p.name;
    [HZTheme styleScreen:self];
    self.version = [self.index installableVersionOf:p game:kGame];
    if (self.version) self.refusal = [HZMarketInstaller refusalFor:p version:self.version index:self.index];
    else self.refusal = @"No version of this project for Minecraft 26.3 is available.";

    // Left: the details. Right: the action panel.
    self.text = [UITextView new];
    self.text.editable = NO;
    self.text.backgroundColor = [HZTheme codeBackground];
    self.text.layer.cornerRadius = 18;
    self.text.layer.cornerCurve = kCACornerCurveContinuous;
    self.text.textContainerInset = UIEdgeInsetsMake(14, 14, 14, 14);
    self.text.dataDetectorTypes = UIDataDetectorTypeLink;
    self.text.linkTextAttributes = @{NSForegroundColorAttributeName: Accent()};
    self.text.translatesAutoresizingMaskIntoConstraints = NO;

    self.installButton = [HZTheme buttonWithTitle:@"Install" symbol:@"arrow.down.circle.fill" prominent:YES target:self action:@selector(installTapped)];
    [self.installButton.heightAnchor constraintEqualToConstant:64].active = YES;
    self.removeButton = [HZTheme buttonWithTitle:@"Remove" symbol:@"trash" prominent:NO target:self action:@selector(removeTapped)];
    [self.removeButton.heightAnchor constraintEqualToConstant:52].active = YES;
    self.bar = (HZGlassProgress *)[HZTheme glassProgressView];
    self.bar.hidden = YES;
    self.statusLabel = [HZTheme labelWithSize:13 weight:UIFontWeightRegular color:[HZTheme secondaryText]];

    UIStackView *panel = [[UIStackView alloc] initWithArrangedSubviews:@[self.installButton, self.bar, self.removeButton, self.statusLabel]];
    panel.axis = UILayoutConstraintAxisVertical; panel.spacing = 12;
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    UIScrollView *right = [UIScrollView new];
    right.translatesAutoresizingMaskIntoConstraints = NO;
    [right addSubview:panel];
    [self.view addSubview:self.text];
    [self.view addSubview:right];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.text.topAnchor constraintEqualToAnchor:g.topAnchor constant:8], [self.text.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-8],
        [self.text.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [self.text.trailingAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:40],
        [right.topAnchor constraintEqualToAnchor:g.topAnchor constant:8], [right.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-8],
        [right.leadingAnchor constraintEqualToAnchor:self.text.trailingAnchor constant:16], [right.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
        [panel.topAnchor constraintEqualToAnchor:right.contentLayoutGuide.topAnchor], [panel.bottomAnchor constraintEqualToAnchor:right.contentLayoutGuide.bottomAnchor],
        [panel.leadingAnchor constraintEqualToAnchor:right.frameLayoutGuide.leadingAnchor], [panel.trailingAnchor constraintEqualToAnchor:right.frameLayoutGuide.trailingAnchor]]];
    [self buildText];
    [self refreshButtons];
}

- (void)buildText {
    HZMarketProject *p = self.project; HZMarketVersion *v = self.version;
    HZMarketRevoked *rev = v ? nil : [self.index revocationFor:p.projectId sha256:nil];
    if (!rev && !v) rev = [self.index revocationFor:p.projectId sha256:p.versions.firstObject.file.sha256];
    NSMutableAttributedString *s = [NSMutableAttributedString new];
    UIFont *h1 = [UIFont systemFontOfSize:22 weight:UIFontWeightHeavy], *h2 = [UIFont systemFontOfSize:15 weight:UIFontWeightBold], *body = [UIFont systemFontOfSize:14];
    void (^add)(NSString *, UIFont *, UIColor *) = ^(NSString *t, UIFont *f, UIColor *c) {
        [s appendAttributedString:[[NSAttributedString alloc] initWithString:t attributes:@{NSFontAttributeName: f, NSForegroundColorAttributeName: c}]];
    };
    UIColor *white = [HZTheme text], *grey = [HZTheme secondaryText];
    add([p.name stringByAppendingString:@"\n"], h1, white);
    add([NSString stringWithFormat:@"%@  |  %@\n\n", MarketKindText(p.kind), MarketSupportText(p.support)], h2, p.support == HZMarketInstallable ? Accent() : grey);
    if (p.summary.length) add([p.summary stringByAppendingString:@"\n\n"], body, white);
    if (p.support == HZMarketNeedsDesktop) add(@"This is a native mod. It changes the game's Rust source before the game is compiled, so it needs a desktop build and cannot be added on a phone.\n\n", body, grey);
    if (p.support == HZMarketNotYet) add(@"This kind of project cannot be installed by the app yet.\n\n", body, grey);
    if (rev) add([NSString stringWithFormat:@"Taken down by the registry%@: %@\n\n", rev.date.length ? [@" on " stringByAppendingString:rev.date] : @"", rev.reason], body, [HZTheme danger]);
    add(@"Details\n", h2, white);
    NSMutableString *facts = [NSMutableString new];
    if (p.authors.count) [facts appendFormat:@"By %@\n", [p.authors componentsJoinedByString:@", "]];
    [facts appendFormat:@"Licence: %@\n", p.license];
    if (p.categories.count) [facts appendFormat:@"Categories: %@\n", [p.categories componentsJoinedByString:@", "]];
    if (v) [facts appendFormat:@"Version %@ for Minecraft %@, %@\n", v.version, v.game, [NSByteCountFormatter stringFromByteCount:(long long)v.file.size countStyle:NSByteCountFormatterCountStyleFile]];
    else if (p.versions.count) [facts appendFormat:@"No version for Minecraft %@ that is still available.\n", kGame];
    [facts appendFormat:@"%llu downloads, %llu stars\n", p.downloads, p.stars];
    [facts appendFormat:@"Signed by the author: %@\n", p.key ? @"yes (this app cannot check signatures yet, so it will not install it)" : @"no (the registry pins the exact file by SHA-256, which the app checks)"];
    [facts appendFormat:@"Source: %@\n", p.source];
    add(facts, body, grey);
    add(@"\nWhat the app checks\n", h2, white);
    add(@"The file must come from the registry's release address, match the size and SHA-256 the registry lists, not be taken down, and be a ZIP container. The game checks the content itself when it reads it, and shows a red reason on a mod it cannot load. The app does not repeat the desktop launcher's deeper content check.\n", body, grey);
    if (p.details.length) { add(@"\nDescription (as the author wrote it)\n", h2, white); add([p.details stringByAppendingString:@"\n"], body, grey); }
    if (v.changelog.length) { add(@"\nChangelog\n", h2, white); add([v.changelog stringByAppendingString:@"\n"], body, grey); }
    self.text.attributedText = s;
}

// Install / Update / Installed, Remove, and the line that says why a button is missing.
- (void)refreshButtons {
    HZMarketInstaller *inst = Installer();
    HZInstalledEntry *have = [inst installedEntryForProject:self.project.projectId];
    BOOL canInstall = self.version && !self.refusal;
    NSString *title; NSString *status = nil;
    if (have && canInstall && [have.version isEqualToString:self.version.version]) {
        title = @"Installed";
        status = [NSString stringWithFormat:@"Version %@ is on this phone.%@", have.version, [self.project.kind isEqualToString:@"mod"] ? (([inst isModEnabled:self.project.projectId]) ? @" It is turned on." : @" It is turned off. Turn it on in the game, Options > Mods.") : @" Choose it in the game's pack list."];
    } else if (have && canInstall) {
        title = [NSString stringWithFormat:@"Update to %@", self.version.version];
        status = [NSString stringWithFormat:@"Installed: %@.", have.version];
    } else if (canInstall) {
        title = @"Install";
        if ([self.project.kind isEqualToString:@"mod"]) status = @"It is turned on after install. The game reads mods when it starts, so restart the game to see it.";
        else if ([self.project.kind isEqualToString:@"shader"]) status = @"Choose it in the game's video settings. Shaders have not been tested on a phone.";
        else status = @"Choose it in the game's pack list.";
    } else {
        title = @"Can't install";
        status = self.refusal;
    }
    [HZTheme setTitle:title onButton:self.installButton];
    self.installButton.enabled = canInstall && !self.busy && !(have && [have.version isEqualToString:self.version.version]);
    self.removeButton.hidden = !have;
    self.removeButton.enabled = !self.busy;
    self.statusLabel.text = status;
    self.statusLabel.textColor = canInstall ? [HZTheme secondaryText] : [HZTheme warning];
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    self.bar.hidden = !busy;
    if (busy) self.bar.progress = 0;
    [self refreshButtons];
}

- (void)installTapped {
    if (self.busy || !self.version || self.refusal) return;
    // Free-space check: the file, and the same again while it is staged.
    HZMarketInstaller *inst = Installer();
    unsigned long long need = self.version.file.size * 2 + (10ull << 20);
    NSURL *home = [NSURL fileURLWithPath:[HZLauncherModel shared].root];
    NSNumber *free = [[home resourceValuesForKeys:@[NSURLVolumeAvailableCapacityForImportantUsageKey] error:nil] objectForKey:NSURLVolumeAvailableCapacityForImportantUsageKey];
    if (free && free.unsignedLongLongValue < need) {
        [self alert:@"Not enough space" message:[NSString stringWithFormat:@"This needs about %@ free.", [NSByteCountFormatter stringFromByteCount:(long long)need countStyle:NSByteCountFormatterCountStyleFile]]];
        return;
    }
    self.busy = YES;
    self.statusLabel.text = @"Downloading...";
    self.statusLabel.textColor = [HZTheme secondaryText];
    self.fetcher = [HZMarketFetcher new];
    HZMarketVersion *v = self.version; HZMarketProject *p = self.project; HZMarketIndex *index = self.index;
    __weak typeof(self) weak = self;
    [self.fetcher fetch:v.file stagingDir:[inst stagingDirectory]
               progress:^(double f) { weak.bar.progress = (float)f; }
                   done:^(NSString *path, NSString *error) {
        if (!path) { weak.fetcher = nil; weak.busy = NO; [weak refreshButtons]; weak.statusLabel.text = error; weak.statusLabel.textColor = [HZTheme danger]; return; }
        weak.statusLabel.text = @"Checking the file...";
        // Hashing and moving are off the main thread; a 600 KB file is quick but a 60 MB one is not.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *problem = [Installer() placeDownloaded:path project:p version:v index:index];
            dispatch_async(dispatch_get_main_queue(), ^{
                weak.fetcher = nil; weak.busy = NO;
                [weak refreshButtons];
                if (problem) { weak.statusLabel.text = problem; weak.statusLabel.textColor = [HZTheme danger]; }
                else [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
            });
        });
    }];
}

- (void)removeTapped {
    HZInstalledEntry *have = [Installer() installedEntryForProject:self.project.projectId];
    if (!have) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Remove %@?", self.project.name]
        message:@"The file is deleted from the Horizon folder. A mod's saved data, if it has any, stays." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        NSString *problem = [Installer() removeProject:self.project.projectId];
        [self refreshButtons];
        if (problem) { self.statusLabel.text = problem; self.statusLabel.textColor = [HZTheme danger]; }
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Leaving the page stops a download in progress; the staged file is deleted by the fetcher's owner next time.
    if (self.busy) [self.fetcher cancel];
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
