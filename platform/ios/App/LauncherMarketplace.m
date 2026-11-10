#import "LauncherMarketplace.h"
#import "MarketClient.h"
#import "LauncherModel.h"

static NSString *const kGame = @"26.3";

static UIColor *Accent(void) { return [UIColor colorWithRed:0.36 green:0.74 blue:0.33 alpha:1]; }

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
@property (strong) UISegmentedControl *filter;
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
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.09 blue:0.11 alpha:1];
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.tableView.separatorColor = [UIColor colorWithWhite:1 alpha:0.12];

    self.filter = [[UISegmentedControl alloc] initWithItems:@[@"Works on iPhone", @"All", @"Mods", @"Packs", @"Shaders"]];
    self.filter.selectedSegmentIndex = 0;
    [self.filter addTarget:self action:@selector(refilter) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.filter;
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
    self.banner.textColor = [UIColor colorWithWhite:0.6 alpha:1];
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
    NSString *q = [self.search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString ?: @"";
    for (HZMarketProject *p in self.index.projects) {
        switch (self.filter.selectedSegmentIndex) {
            case 0: if (p.support != HZMarketInstallable) continue; break;
            case 2: if (![p.kind isEqualToString:@"mod"] && ![p.kind isEqualToString:@"native-mod"]) continue; break;
            case 3: if (![p.kind isEqualToString:@"resourcepack"] && ![p.kind isEqualToString:@"modpack"] && ![p.kind isEqualToString:@"shaderpack"] && ![p.kind isEqualToString:@"datapack"]) continue; break;
            case 4: if (![p.kind isEqualToString:@"shader"] && ![p.kind isEqualToString:@"shaderpack"]) continue; break;
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
    return [count stringByAppendingFormat:@"%@\nInstalling is not built yet: this page only browses. Native mods change the game's source before it is compiled, so they cannot run on a phone.", self.banner.text ?: @""];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    HZMarketProject *p = self.shown[(NSUInteger)ip.row];
    cell.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
    cell.textLabel.text = p.name;
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  |  %@\n%@", MarketKindText(p.kind), MarketSupportText(p.support), p.summary];
    cell.detailTextLabel.numberOfLines = 3;
    cell.detailTextLabel.textColor = p.support == HZMarketInstallable ? Accent() : [UIColor colorWithWhite:0.65 alpha:1];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    HZMarketProject *p = self.shown[(NSUInteger)ip.row];
    HZMarketVersion *v = [self.index installableVersionOf:p game:kGame];
    HZMarketRevoked *rev = v ? nil : [self.index revocationFor:p.projectId sha256:nil];
    if (!rev && !v) rev = [self.index revocationFor:p.projectId sha256:p.versions.firstObject.file.sha256];

    UIViewController *vc = [UIViewController new];
    vc.title = p.name;
    vc.view.backgroundColor = self.view.backgroundColor;
    UITextView *tx = [UITextView new];
    tx.editable = NO;
    tx.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    tx.layer.cornerRadius = 10;
    tx.textContainerInset = UIEdgeInsetsMake(14, 14, 14, 14);
    tx.dataDetectorTypes = UIDataDetectorTypeLink;
    tx.linkTextAttributes = @{NSForegroundColorAttributeName: Accent()};

    NSMutableAttributedString *s = [NSMutableAttributedString new];
    UIFont *h1 = [UIFont systemFontOfSize:22 weight:UIFontWeightHeavy], *h2 = [UIFont systemFontOfSize:15 weight:UIFontWeightBold], *body = [UIFont systemFontOfSize:14];
    void (^add)(NSString *, UIFont *, UIColor *) = ^(NSString *t, UIFont *f, UIColor *c) {
        [s appendAttributedString:[[NSAttributedString alloc] initWithString:t attributes:@{NSFontAttributeName: f, NSForegroundColorAttributeName: c}]];
    };
    UIColor *white = UIColor.whiteColor, *grey = [UIColor colorWithWhite:0.75 alpha:1];
    add([p.name stringByAppendingString:@"\n"], h1, white);
    add([NSString stringWithFormat:@"%@  |  %@\n\n", MarketKindText(p.kind), MarketSupportText(p.support)], h2, p.support == HZMarketInstallable ? Accent() : grey);
    if (p.summary.length) add([p.summary stringByAppendingString:@"\n\n"], body, white);
    if (p.support == HZMarketNeedsDesktop) add(@"This is a native mod. It changes the game's Rust source before the game is compiled, so it needs a desktop build and cannot be added on a phone.\n\n", body, grey);
    if (p.support == HZMarketNotYet) add(@"This kind of project cannot be installed by the app yet.\n\n", body, grey);
    if (rev) add([NSString stringWithFormat:@"Taken down by the registry%@: %@\n\n", rev.date.length ? [@" on " stringByAppendingString:rev.date] : @"", rev.reason], body, [UIColor colorWithRed:1 green:0.55 blue:0.55 alpha:1]);
    add(@"Details\n", h2, white);
    NSMutableString *facts = [NSMutableString new];
    if (p.authors.count) [facts appendFormat:@"By %@\n", [p.authors componentsJoinedByString:@", "]];
    [facts appendFormat:@"Licence: %@\n", p.license];
    if (p.categories.count) [facts appendFormat:@"Categories: %@\n", [p.categories componentsJoinedByString:@", "]];
    if (v) [facts appendFormat:@"Version %@ for Minecraft %@, %@\n", v.version, v.game, [NSByteCountFormatter stringFromByteCount:(long long)v.file.size countStyle:NSByteCountFormatterCountStyleFile]];
    else if (p.versions.count) [facts appendFormat:@"No version for Minecraft %@ that is still available.\n", kGame];
    [facts appendFormat:@"%llu downloads, %llu stars\n", p.downloads, p.stars];
    [facts appendFormat:@"Signed by the author: %@\n", p.key ? @"yes (checked at install)" : @"no (the registry pins the exact file by SHA-256)"];
    [facts appendFormat:@"Source: %@\n", p.source];
    add(facts, body, grey);
    if (p.details.length) { add(@"\nDescription (as the author wrote it)\n", h2, white); add([p.details stringByAppendingString:@"\n"], body, grey); }
    if (v.changelog.length) { add(@"\nChangelog\n", h2, white); add([v.changelog stringByAppendingString:@"\n"], body, grey); }
    tx.attributedText = s;
    tx.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:tx];
    UILayoutGuide *g = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [tx.topAnchor constraintEqualToAnchor:g.topAnchor constant:8], [tx.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-8],
        [tx.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16], [tx.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
    ]];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
