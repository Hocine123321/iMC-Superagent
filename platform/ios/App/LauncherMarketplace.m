#import "LauncherMarketplace.h"
#import "LauncherTheme.h"
#import "MarketClient.h"
#import "LauncherModel.h"
#import "MarketInstaller.h"
#import "MarketFetcher.h"
#import "GlassControls.h"
#import "LauncherPrefs.h"
#import "MarketCells.h"
#import "ModrinthClient.h"

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

// Which tabs exist depends on Settings: resource packs and Installed always; Mods, Shaders and Everything else
// only once turned on there; Modrinth only once turned on (it reaches another company's server).
typedef NS_ENUM(NSInteger, HZTab) { HZTabPacks, HZTabModrinth, HZTabMods, HZTabShaders, HZTabAll, HZTabInstalled };

@interface HZLauncherMarketplaceController () <UISearchResultsUpdating>
@property (strong) HZMarketClient *client;
@property (strong) HZModrinthClient *modrinth;
@property (strong) HZMarketIndex *index;
@property (copy) NSArray<HZMarketRow *> *shown;
@property (copy) NSArray<NSNumber *> *tabs;               // HZTab values, in order
@property (nonatomic) HZTab tab;
@property (strong) UIScrollView *chipScroll;
@property (strong) UIStackView *chipStack;
@property (strong) UISearchController *search;
@property (strong) UILabel *banner;
@property (strong) UIActivityIndicatorView *spinner;
@property (nonatomic) BOOL loading, loadingModrinth, modrinthPending;
@property (copy) NSArray<HZModrinthProject *> *modrinthHits;
@property (nonatomic) NSUInteger modrinthTotal;
@property (copy) NSString *modrinthError, *modrinthQuery;
@property (strong) NSTimer *searchTimer;
@property (copy) NSString *tabSignature;
@end

@implementation HZLauncherMarketplaceController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.client = [[HZMarketClient alloc] initWithCacheDirectory:[[HZLauncherModel shared].root stringByAppendingPathComponent:@"marketplace"]];
        self.modrinth = [HZModrinthClient new];
        self.shown = @[]; self.modrinthHits = @[];
    }
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; [self.searchTimer invalidate]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Marketplace";
    [HZTheme styleScreen:self];
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.tableView registerClass:HZMarketCardCell.class forCellReuseIdentifier:[HZMarketCardCell reuseIdentifier]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"] style:UIBarButtonItemStylePlain target:self action:@selector(forceReload)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = @"Refresh";

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"Search";
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    // The chip row: one scrolling line of pills. The selected one is filled with the accent colour.
    self.chipStack = [UIStackView new];
    self.chipStack.spacing = 8;
    self.chipStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.chipScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, 0, 52)];
    self.chipScroll.showsHorizontalScrollIndicator = NO;
    [self.chipScroll addSubview:self.chipStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.chipStack.leadingAnchor constraintEqualToAnchor:self.chipScroll.contentLayoutGuide.leadingAnchor constant:16],
        [self.chipStack.trailingAnchor constraintEqualToAnchor:self.chipScroll.contentLayoutGuide.trailingAnchor constant:-16],
        [self.chipStack.centerYAnchor constraintEqualToAnchor:self.chipScroll.frameLayoutGuide.centerYAnchor],
        [self.chipStack.heightAnchor constraintEqualToConstant:36]]];
    self.tableView.tableHeaderView = self.chipScroll;

    self.banner = [HZTheme labelWithSize:12 weight:UIFontWeightRegular color:[HZTheme tertiaryText]];
    self.banner.textAlignment = NSTextAlignmentCenter;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = [HZTheme secondaryText];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged) name:HZThemeChanged object:nil];
    self.tabSignature = [NSString stringWithFormat:@"%d%d%d%d", [HZPrefs useModrinth], [HZPrefs showMods], [HZPrefs showShaders], [HZPrefs showOtherKinds]];
    [self rebuildTabs];
    [self load:NO];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect f = self.chipScroll.frame; f.size.width = self.tableView.bounds.size.width;
    if (f.size.width != self.chipScroll.frame.size.width) { self.chipScroll.frame = f; self.tableView.tableHeaderView = self.chipScroll; }
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refilter]; }
- (void)forceReload { [self load:YES]; if (self.tab == HZTabModrinth) [self searchModrinth:YES]; }

#pragma mark - tabs

static NSString *TabName(HZTab t) {
    switch (t) { case HZTabPacks: return @"Resource packs"; case HZTabModrinth: return @"Modrinth"; case HZTabMods: return @"Mods";
                 case HZTabShaders: return @"Shaders"; case HZTabAll: return @"Everything"; case HZTabInstalled: return @"Installed"; }
}

// Which tabs this person has turned on. Resource packs and Installed are always there.
- (void)rebuildTabs {
    NSMutableArray *t = [NSMutableArray arrayWithObject:@(HZTabPacks)];
    if ([HZPrefs useModrinth]) [t addObject:@(HZTabModrinth)];
    if ([HZPrefs showMods]) [t addObject:@(HZTabMods)];
    if ([HZPrefs showShaders]) [t addObject:@(HZTabShaders)];
    if ([HZPrefs showOtherKinds]) [t addObject:@(HZTabAll)];
    [t addObject:@(HZTabInstalled)];
    self.tabs = t;
    if (![t containsObject:@(self.tab)]) self.tab = HZTabPacks;
    for (UIView *v in self.chipStack.arrangedSubviews) { [self.chipStack removeArrangedSubview:v]; [v removeFromSuperview]; }
    for (NSNumber *n in t) {
        HZTab tab = (HZTab)n.integerValue;
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
        c.title = TabName(tab);
        c.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        c.contentInsets = NSDirectionalEdgeInsetsMake(8, 16, 8, 16);
        b.configuration = c;
        b.tag = tab;
        [b addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.chipStack addArrangedSubview:b];
    }
    [self paintChips];
}

- (void)paintChips {
    for (UIButton *b in self.chipStack.arrangedSubviews) {
        if (![b isKindOfClass:UIButton.class]) continue;
        BOOL on = b.tag == self.tab;
        UIButtonConfiguration *c = b.configuration;
        c.baseBackgroundColor = on ? [HZTheme accent] : [HZTheme surface];
        c.baseForegroundColor = on ? [HZTheme onAccent] : [HZTheme text];
        UIFont *f = [UIFont systemFontOfSize:15 weight:on ? UIFontWeightBold : UIFontWeightMedium];
        c.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *in) { NSMutableDictionary *d = [in mutableCopy]; d[NSFontAttributeName] = f; return d; };
        b.configuration = c;
        b.accessibilityTraits = on ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
    }
}

- (void)chipTapped:(UIButton *)b {
    if (self.tab == (HZTab)b.tag) return;
    self.tab = (HZTab)b.tag;
    [self paintChips];
    [[UISelectionFeedbackGenerator new] selectionChanged];
    if (self.tab == HZTabModrinth && !self.modrinthHits.count) [self searchModrinth:NO];
    [self refilter];
    [self.tableView setContentOffset:CGPointMake(0, -self.tableView.adjustedContentInset.top) animated:NO];
}

// A switch in Settings changed what is visible (or the look). The tabs are rebuilt only when the set of tabs
// changed, so moving the Appearance or Background slider does not reset the chip row.
- (void)settingsChanged {
    NSString *signature = [NSString stringWithFormat:@"%d%d%d%d", [HZPrefs useModrinth], [HZPrefs showMods], [HZPrefs showShaders], [HZPrefs showOtherKinds]];
    if (![signature isEqualToString:self.tabSignature]) { self.tabSignature = signature; [self rebuildTabs]; }
    [self refilter];
    [self paintChips];
}

#pragma mark - loading

- (void)load:(BOOL)force {
    if (self.loading) return;
    self.loading = YES;
    [self refilter];
    [self.client loadForce:force completion:^(HZMarketResult *r) {
        self.loading = NO;
        if (r.index) {
            self.index = r.index;
            NSString *when = r.fetched ? [NSDateFormatter localizedStringFromDate:r.fetched dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle] : @"";
            self.banner.text = r.source == HZMarketOffline ? [NSString stringWithFormat:@"Offline. Showing the copy from %@.", when] : nil;
        } else {
            self.index = nil;
            self.banner.text = r.error ?: @"The Marketplace could not be loaded.";
        }
        [self refilter];
    }];
}

- (NSString *)currentQuery {
    return [self.search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

// Searches Modrinth for what is typed. If a search is already running, the newer text is searched as soon as
// it returns (an answer for older text is never shown), so typing quickly cannot leave stale results.
- (void)searchModrinth:(BOOL)force {
    if (![HZPrefs useModrinth]) return;
    NSString *q = [self currentQuery];
    if (self.loadingModrinth) { self.modrinthPending = YES; return; }
    if (!force && [q isEqualToString:self.modrinthQuery ?: @""] && self.modrinthHits.count) return;
    self.loadingModrinth = YES; self.modrinthError = nil; self.modrinthQuery = q; self.modrinthPending = NO;
    [self refilter];
    __weak typeof(self) weak = self;
    [self.modrinth searchText:q offset:0 completion:^(NSArray<HZModrinthProject *> *p, NSUInteger total, NSString *err) {
        typeof(self) me = weak; if (!me) return;
        me.loadingModrinth = NO;
        BOOL stale = ![q isEqualToString:[me currentQuery]];
        if (!stale) { me.modrinthHits = p ?: @[]; me.modrinthTotal = total; me.modrinthError = err; }
        if (stale || me.modrinthPending) { me.modrinthPending = NO; [me searchModrinth:NO]; return; }
        [me refilter];
    }];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    if (self.tab == HZTabModrinth) {
        // Modrinth is searched on its server, a moment after typing stops.
        [self.searchTimer invalidate];
        __weak typeof(self) weak = self;
        self.searchTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *t) { [weak searchModrinth:NO]; }];
    }
    [self refilter];
}

#pragma mark - rows

- (HZMarketRow *)rowForProject:(HZMarketProject *)p installer:(HZMarketInstaller *)inst {
    HZMarketRow *r = [HZMarketRow new];
    r.title = p.name; r.kind = p.kind; r.source = @"Horizon"; r.summary = p.summary; r.payload = p;
    HZInstalledEntry *have = [inst installedEntryForProject:p.projectId];
    HZMarketVersion *v = self.index ? [self.index installableVersionOf:p game:kGame] : nil;
    NSString *refusal = v ? [HZMarketInstaller refusalFor:p version:v index:self.index] : @"No version for 26.3";
    if (have) { r.state = HZRowInstalled; r.stateText = have.version.length ? [@"v" stringByAppendingString:have.version] : @"Installed"; }
    else if (!refusal) { r.state = HZRowGet; r.stateText = @"Get"; }
    else { r.state = HZRowUnavailable; r.stateText = p.support == HZMarketNeedsDesktop ? @"Desktop only" : p.key.length ? @"Signed" : @"Unavailable"; }
    return r;
}

- (HZMarketRow *)rowForModrinth:(HZModrinthProject *)p installer:(HZMarketInstaller *)inst {
    HZMarketRow *r = [HZMarketRow new];
    r.title = p.title; r.kind = @"resourcepack"; r.source = @"Modrinth"; r.summary = p.summary; r.payload = p;
    HZInstalledEntry *have = [inst installedEntryForModrinth:p.projectId];
    if (have) { r.state = HZRowInstalled; r.stateText = have.version.length ? [@"v" stringByAppendingString:have.version] : @"Installed"; }
    else { r.state = HZRowGet; r.stateText = @"Get"; }
    return r;
}

// What the current tab and search show. Search looks at name, summary, id, categories and authors.
- (void)refilter {
    HZMarketInstaller *inst = Installer();
    NSString *q = [self.search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString ?: @"";
    NSMutableArray *out = [NSMutableArray new];
    if (self.tab == HZTabModrinth) {
        for (HZModrinthProject *p in self.modrinthHits) [out addObject:[self rowForModrinth:p installer:inst]];
    } else {
        NSMutableArray<HZMarketProject *> *list = [NSMutableArray array];
        for (HZMarketProject *p in self.index.projects) {
            if (self.tab == HZTabInstalled) { if (![inst installedEntryForProject:p.projectId]) continue; }
            else if (self.tab == HZTabPacks) { if (![p.kind isEqualToString:@"resourcepack"]) continue; }
            else if (self.tab == HZTabMods) { if (![p.kind isEqualToString:@"mod"] && ![p.kind isEqualToString:@"native-mod"]) continue; }
            else if (self.tab == HZTabShaders) { if (![p.kind isEqualToString:@"shader"] && ![p.kind isEqualToString:@"shaderpack"]) continue; }
            // "Everything" shows only the kinds Settings turned on; the other tabs are their own filter, and they
            // exist only once their switch is on. Installed shows what is installed, whatever is hidden.
            if (self.tab == HZTabAll && ![HZPrefs isKindVisible:p.kind]) continue;
            if (q.length) {
                NSString *hay = [[@[p.name, p.summary, p.projectId, [p.categories componentsJoinedByString:@" "], [p.authors componentsJoinedByString:@" "]] componentsJoinedByString:@" "] lowercaseString];
                BOOL all = YES;
                for (NSString *w in [q componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) if (w.length && ![hay containsString:w]) { all = NO; break; }
                if (!all) continue;
            }
            [list addObject:p];
        }
        [list sortUsingComparator:^NSComparisonResult(HZMarketProject *a, HZMarketProject *b) {
            if (a.downloads != b.downloads) return a.downloads > b.downloads ? NSOrderedAscending : NSOrderedDescending;
            return [a.name caseInsensitiveCompare:b.name];
        }];
        for (HZMarketProject *p in list) [out addObject:[self rowForProject:p installer:inst]];
        // The Installed tab also lists Modrinth packs the app put on the phone.
        if (self.tab == HZTabInstalled) {
            for (HZInstalledEntry *e in [inst installed]) {
                if (![e.source isEqual:@"modrinth"]) continue;
                if (q.length && ![e.title.lowercaseString containsString:q]) continue;
                HZMarketRow *r = [HZMarketRow new];
                r.title = e.title; r.kind = @"resourcepack"; r.source = @"Modrinth"; r.summary = @""; r.state = HZRowInstalled;
                r.stateText = e.version.length ? [@"v" stringByAppendingString:e.version] : @"Installed";
                HZModrinthProject *mp = [HZModrinthProject new]; mp.projectId = e.projectId; mp.title = e.title; mp.slug = e.projectId; mp.summary = @""; mp.author = @""; mp.license = @"";
                r.payload = mp;
                [out addObject:r];
            }
        }
    }
    self.shown = out;
    [self.tableView reloadData];
    [self updateFooter];
}

- (void)updateFooter {
    BOOL busy = self.tab == HZTabModrinth ? self.loadingModrinth : self.loading;
    NSString *msg = nil;
    if (busy) msg = @"Loading...";
    else if (self.tab == HZTabModrinth && self.modrinthError) msg = self.modrinthError;
    else if (!self.shown.count) {
        if (self.tab == HZTabInstalled) msg = @"Nothing installed yet.";
        else if (!self.index && self.tab != HZTabModrinth) msg = self.banner.text ?: @"The Marketplace could not be loaded.";
        else msg = @"Nothing matches.";
    } else if (self.tab == HZTabModrinth) msg = [NSString stringWithFormat:@"Showing %lu of %lu resource packs for Minecraft 26.3 on Modrinth.", (unsigned long)self.shown.count, (unsigned long)self.modrinthTotal];
    else msg = self.banner.text;
    UILabel *l = [HZTheme labelWithSize:13 weight:UIFontWeightRegular color:[HZTheme tertiaryText]];
    l.text = msg; l.textAlignment = NSTextAlignmentCenter;
    UIView *f = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, msg.length ? 64 : 24)];
    l.frame = CGRectInset(f.bounds, 24, 8);
    if (msg.length) [f addSubview:l];
    self.tableView.tableFooterView = f;
}

#pragma mark - table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.shown.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    HZMarketCardCell *cell = [tv dequeueReusableCellWithIdentifier:[HZMarketCardCell reuseIdentifier] forIndexPath:ip];
    [cell configure:self.shown[(NSUInteger)ip.row] compact:[HZPrefs compactLists]];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    HZMarketRow *r = self.shown[(NSUInteger)ip.row];
    UIViewController *vc = nil;
    if ([r.payload isKindOfClass:HZMarketProject.class]) vc = [[HZMarketProjectController alloc] initWithProject:r.payload index:self.index];
    else if ([r.payload isKindOfClass:HZModrinthProject.class]) vc = [[HZModrinthProjectController alloc] initWithProject:r.payload];
    if (vc) [self.navigationController pushViewController:vc animated:YES];
}

@end

#pragma mark - Project pages

// The page every project has: a header (icon tile, name, who and what), the action button with its progress bar
// and one line saying what happens, then the facts and the description. A subclass says where the facts come
// from and how a download is started; this class owns the layout, the confirm, the progress and the cancel.
@interface HZMarketPageController ()
@property (strong) UIView *tile;
@property (strong) UIImageView *tileIcon;
@property (strong) UILabel *nameLabel, *byLabel, *statusLabel;
@property (strong) UITextView *text;
@property (strong) UIButton *installButton, *removeButton;
@property (strong) HZGlassProgress *bar;
@property (strong) HZMarketFetcher *fetcher;
@property (nonatomic) BOOL busy;
@end

@implementation HZMarketPageController

// ---- hooks (a subclass overrides these) ----
- (NSString *)pageTitle { return @""; }
- (NSString *)kindKey { return @"resourcepack"; }
- (NSString *)byline { return @""; }
- (NSAttributedString *)detailText { return [NSAttributedString new]; }
- (NSString *)installTitle { return @"Get"; }         // the button's words; nil/empty = nothing to do
- (NSString *)refusal { return nil; }                  // why it cannot be installed, or nil
- (NSString *)installedVersion { return nil; }         // the installed version, or nil when not installed
- (NSString *)availableVersion { return nil; }
- (NSString *)explanation { return @""; }              // the grey line under the button
- (unsigned long long)downloadSize { return 0; }
- (NSString *)confirmText { return @""; }
- (void)startDownload:(HZMarketFetcher *)fetcher progress:(void (^)(double))progress done:(void (^)(NSString *, NSString *))done {}
- (NSString *)placeFile:(NSString *)path { return @"Not supported."; }   // runs off the main thread
- (NSString *)removeInstalled { return nil; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    [HZTheme styleScreen:self];

    self.tile = [UIView new];
    self.tile.backgroundColor = HZMarketColorForKind([self kindKey]);
    self.tile.layer.cornerRadius = 20; self.tile.layer.cornerCurve = kCACornerCurveContinuous;
    self.tile.translatesAutoresizingMaskIntoConstraints = NO;
    self.tileIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:HZMarketSymbolForKind([self kindKey]) withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:34 weight:UIImageSymbolWeightSemibold]]];
    self.tileIcon.tintColor = UIColor.whiteColor;
    self.tileIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tile addSubview:self.tileIcon];
    self.nameLabel = [HZTheme labelWithSize:24 weight:UIFontWeightBold color:[HZTheme text]];
    self.nameLabel.text = [self pageTitle];
    self.byLabel = [HZTheme labelWithSize:14 weight:UIFontWeightRegular color:[HZTheme secondaryText]];
    self.byLabel.text = [self byline];
    UIStackView *names = [[UIStackView alloc] initWithArrangedSubviews:@[self.nameLabel, self.byLabel]];
    names.axis = UILayoutConstraintAxisVertical; names.spacing = 4;
    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[self.tile, names]];
    head.alignment = UIStackViewAlignmentCenter; head.spacing = 16;

    self.installButton = [HZTheme buttonWithTitle:@"Get" symbol:@"arrow.down.circle.fill" prominent:YES target:self action:@selector(installTapped)];
    [self.installButton.heightAnchor constraintEqualToConstant:56].active = YES;
    self.removeButton = [HZTheme buttonWithTitle:@"Remove" symbol:@"trash" prominent:NO target:self action:@selector(removeTapped)];
    [self.removeButton.heightAnchor constraintEqualToConstant:48].active = YES;
    self.bar = (HZGlassProgress *)[HZTheme glassProgressView];
    self.bar.hidden = YES;
    self.statusLabel = [HZTheme labelWithSize:13 weight:UIFontWeightRegular color:[HZTheme secondaryText]];

    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[head, self.installButton, self.bar, self.removeButton, self.statusLabel]];
    actions.axis = UILayoutConstraintAxisVertical; actions.spacing = 14;
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    [actions setCustomSpacing:20 afterView:head];
    UIScrollView *left = [UIScrollView new];
    left.translatesAutoresizingMaskIntoConstraints = NO;
    [left addSubview:actions];

    self.text = [UITextView new];
    self.text.editable = NO;
    self.text.backgroundColor = [HZTheme surface];
    self.text.layer.cornerRadius = 18; self.text.layer.cornerCurve = kCACornerCurveContinuous;
    self.text.textContainerInset = UIEdgeInsetsMake(16, 16, 16, 16);
    self.text.dataDetectorTypes = UIDataDetectorTypeLink;
    self.text.linkTextAttributes = @{NSForegroundColorAttributeName: [HZTheme accent]};
    self.text.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:left]; [self.view addSubview:self.text];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tile.widthAnchor constraintEqualToConstant:76], [self.tile.heightAnchor constraintEqualToConstant:76],
        [self.tileIcon.centerXAnchor constraintEqualToAnchor:self.tile.centerXAnchor], [self.tileIcon.centerYAnchor constraintEqualToAnchor:self.tile.centerYAnchor],
        [left.topAnchor constraintEqualToAnchor:g.topAnchor constant:8], [left.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
        [left.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20], [left.widthAnchor constraintEqualToAnchor:g.widthAnchor multiplier:0.4],
        [actions.topAnchor constraintEqualToAnchor:left.contentLayoutGuide.topAnchor], [actions.bottomAnchor constraintEqualToAnchor:left.contentLayoutGuide.bottomAnchor constant:-16],
        [actions.leadingAnchor constraintEqualToAnchor:left.frameLayoutGuide.leadingAnchor], [actions.trailingAnchor constraintEqualToAnchor:left.frameLayoutGuide.trailingAnchor],
        [self.text.topAnchor constraintEqualToAnchor:g.topAnchor constant:8], [self.text.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-8],
        [self.text.leadingAnchor constraintEqualToAnchor:left.trailingAnchor constant:20], [self.text.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20]]];
    [self reloadText];
    [self refreshButtons];
}

- (void)reloadText { self.text.attributedText = [self detailText]; }

// Install / Update / Installed, Remove, and the one line saying what happens or why it cannot.
- (void)refreshButtons {
    NSString *have = [self installedVersion], *avail = [self availableVersion], *why = [self refusal];
    BOOL canInstall = !why && avail.length;
    BOOL current = have && [have isEqualToString:avail];
    NSString *title, *symbol = @"arrow.down.circle.fill", *status;
    if (current) { title = @"Installed"; symbol = @"checkmark.circle.fill"; status = [self explanation]; }
    else if (have && canInstall) { title = [NSString stringWithFormat:@"Update to %@", avail]; status = [NSString stringWithFormat:@"Installed: %@.", have]; }
    else if (canInstall) { title = [self installTitle]; status = [self explanation]; }
    else { title = @"Can't install"; symbol = @"nosign"; status = why ?: @"There is nothing to install."; }
    [HZTheme setTitle:title onButton:self.installButton];
    UIButtonConfiguration *c = self.installButton.configuration;
    c.image = [UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold]];
    self.installButton.configuration = c;
    self.installButton.enabled = canInstall && !self.busy && !current;
    self.removeButton.hidden = !have;
    self.removeButton.enabled = !self.busy;
    self.statusLabel.text = status;
    self.statusLabel.textColor = canInstall || current ? [HZTheme secondaryText] : [HZTheme warning];
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    self.bar.hidden = !busy;
    if (busy) self.bar.progress = 0;
    [self refreshButtons];
}

- (void)setError:(NSString *)message {
    self.statusLabel.text = message;
    self.statusLabel.textColor = [HZTheme danger];
}

- (void)installTapped {
    if (self.busy || [self refusal] || ![[self availableVersion] length]) return;
    if ([HZPrefs confirmInstalls]) {
        unsigned long long size = [self downloadSize];
        NSString *msg = [NSString stringWithFormat:@"%@%@%@", [self confirmText], [self confirmText].length ? @"\n\n" : @"",
                         size ? [NSString stringWithFormat:@"The download is %@.", [NSByteCountFormatter stringFromByteCount:(long long)size countStyle:NSByteCountFormatterCountStyleFile]] : @""];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Install %@?", [self pageTitle]] message:msg preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Install" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self beginInstall]; }]];
        [self presentViewController:a animated:YES completion:nil];
    } else {
        [self beginInstall];
    }
}

- (void)beginInstall {
    unsigned long long need = [self downloadSize] * 2 + (10ull << 20);
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
    __weak typeof(self) weak = self;
    [self startDownload:self.fetcher progress:^(double f) { weak.bar.progress = (float)f; } done:^(NSString *path, NSString *error) {
        if (!path) { weak.fetcher = nil; weak.busy = NO; [weak refreshButtons]; [weak setError:error]; return; }
        weak.statusLabel.text = @"Checking the file...";
        // Hashing and moving are off the main thread; a 600 KB file is quick but a 60 MB one is not.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *problem = [weak placeFile:path];
            dispatch_async(dispatch_get_main_queue(), ^{
                weak.fetcher = nil; weak.busy = NO;
                [weak refreshButtons];
                if (problem) [weak setError:problem];
                else [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
            });
        });
    }];
}

- (void)removeTapped {
    if (![self installedVersion]) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Remove %@?", [self pageTitle]]
        message:@"The file is deleted from the Horizon folder." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        NSString *problem = [self removeInstalled];
        [self refreshButtons];
        if (problem) [self setError:problem];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.busy) [self.fetcher cancel];   // leaving the page stops a download in progress
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

// Shared text styles for the detail pane.
+ (NSMutableAttributedString *)builder { return [NSMutableAttributedString new]; }
+ (void)add:(NSString *)t to:(NSMutableAttributedString *)s font:(UIFont *)f color:(UIColor *)c {
    [s appendAttributedString:[[NSAttributedString alloc] initWithString:t attributes:@{NSFontAttributeName: f, NSForegroundColorAttributeName: c}]];
}
@end

#pragma mark - Horizon project

@interface HZMarketProjectController ()
@property (strong) HZMarketProject *project;
@property (strong) HZMarketIndex *index;
@property (strong) HZMarketVersion *version;
@end

@implementation HZMarketProjectController

- (instancetype)initWithProject:(HZMarketProject *)p index:(HZMarketIndex *)index {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _project = p; _index = index;
        _version = [index installableVersionOf:p game:kGame];
    }
    return self;
}

- (NSString *)pageTitle { return self.project.name; }
- (NSString *)kindKey { return self.project.kind; }
- (NSString *)byline { return self.project.authors.count ? [@"by " stringByAppendingString:[self.project.authors componentsJoinedByString:@", "]] : @"Horizon registry"; }
- (NSString *)availableVersion { return self.version.version; }
- (unsigned long long)downloadSize { return self.version.file.size; }
- (NSString *)installedVersion { return [Installer() installedEntryForProject:self.project.projectId].version; }
- (NSString *)installTitle { return @"Install"; }

- (NSString *)refusal {
    if (!self.version) return @"No version of this project for Minecraft 26.3 is available.";
    return [HZMarketInstaller refusalFor:self.project version:self.version index:self.index];
}

- (NSString *)explanation {
    NSString *k = self.project.kind;
    if ([k isEqualToString:@"mod"]) return [Installer() isModEnabled:self.project.projectId] ? @"Installed and turned on. Restart the game to see it." : @"Installed, but turned off. Turn it on in the game, under Options > Mods.";
    if ([k isEqualToString:@"shader"]) return @"Choose it in the game's video settings. Shaders have not been tested on a phone.";
    return @"Choose it in the game's resource pack list.";
}

- (NSString *)confirmText {
    if ([self.project.kind isEqualToString:@"mod"]) return @"Mods change the game. It is checked against the registry's fingerprint, then turned on.";
    return @"The file is checked against the registry's fingerprint before it is installed.";
}

- (void)startDownload:(HZMarketFetcher *)f progress:(void (^)(double))progress done:(void (^)(NSString *, NSString *))done {
    [f fetch:self.version.file stagingDir:[Installer() stagingDirectory] progress:progress done:done];
}
- (NSString *)placeFile:(NSString *)path { return [Installer() placeDownloaded:path project:self.project version:self.version index:self.index]; }
- (NSString *)removeInstalled { return [Installer() removeProject:self.project.projectId]; }

- (NSAttributedString *)detailText {
    HZMarketProject *p = self.project; HZMarketVersion *v = self.version;
    HZMarketRevoked *rev = v ? nil : [self.index revocationFor:p.projectId sha256:nil];
    if (!rev && !v) rev = [self.index revocationFor:p.projectId sha256:p.versions.firstObject.file.sha256];
    NSMutableAttributedString *s = [HZMarketPageController builder];
    UIFont *h2 = [UIFont systemFontOfSize:16 weight:UIFontWeightBold], *body = [UIFont systemFontOfSize:15];
    UIColor *white = [HZTheme text], *grey = [HZTheme secondaryText];
    void (^add)(NSString *, UIFont *, UIColor *) = ^(NSString *t, UIFont *f, UIColor *c) { [HZMarketPageController add:t to:s font:f color:c]; };
    if (p.summary.length) add([p.summary stringByAppendingString:@"\n\n"], [UIFont systemFontOfSize:17 weight:UIFontWeightMedium], white);
    if (p.support == HZMarketNeedsDesktop) add(@"This is a native mod. It changes the game's Rust source before the game is compiled, so it needs a desktop build and cannot be added on a phone.\n\n", body, grey);
    if (rev) add([NSString stringWithFormat:@"Taken down by the registry%@: %@\n\n", rev.date.length ? [@" on " stringByAppendingString:rev.date] : @"", rev.reason], body, [HZTheme danger]);
    add(@"Details\n", h2, white);
    NSMutableString *facts = [NSMutableString new];
    [facts appendFormat:@"Type: %@\n", HZMarketKindName(p.kind)];
    [facts appendFormat:@"Licence: %@\n", p.license];
    if (p.categories.count) [facts appendFormat:@"Categories: %@\n", [p.categories componentsJoinedByString:@", "]];
    if (v) [facts appendFormat:@"Version %@ for Minecraft %@, %@\n", v.version, v.game, [NSByteCountFormatter stringFromByteCount:(long long)v.file.size countStyle:NSByteCountFormatterCountStyleFile]];
    [facts appendFormat:@"%llu downloads, %llu stars\n", p.downloads, p.stars];
    [facts appendFormat:@"Signed by the author: %@\n", p.key ? @"yes (this app cannot check signatures yet, so it will not install it)" : @"no (the registry's fingerprint of the file is checked)"];
    [facts appendFormat:@"Source: %@\n", p.source];
    add(facts, body, grey);
    add(@"\nWhat the app checks\n", h2, white);
    add(@"The file must come from the registry's release address, match the size and SHA-256 the registry lists, not be taken down, and be a ZIP. The game checks the content itself when it reads it. The app does not repeat the desktop launcher's deeper content check.\n", body, grey);
    if (p.details.length) { add(@"\nDescription\n", h2, white); add([p.details stringByAppendingString:@"\n"], body, grey); }
    if (v.changelog.length) { add(@"\nChangelog\n", h2, white); add([v.changelog stringByAppendingString:@"\n"], body, grey); }
    return s;
}
@end

#pragma mark - Modrinth project

@interface HZModrinthProjectController ()
@property (strong) HZModrinthProject *project;
@property (strong) HZModrinthClient *client;
@property (strong) HZModrinthVersion *version;
@property (copy) NSString *versionProblem;
@property (nonatomic) BOOL looking;
@end

@implementation HZModrinthProjectController

- (instancetype)initWithProject:(HZModrinthProject *)p {
    if ((self = [super initWithNibName:nil bundle:nil])) { _project = p; _client = [HZModrinthClient new]; _looking = YES; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // The version (and its file) is looked up when the page opens, so the size and the button are true.
    [self.client newestVersionOf:self.project completion:^(HZModrinthVersion *v, NSString *err) {
        self.looking = NO; self.version = v; self.versionProblem = err;
        [self reloadText]; [self refreshButtons];
    }];
}

- (NSString *)pageTitle { return self.project.title; }
- (NSString *)kindKey { return @"resourcepack"; }
- (NSString *)byline { return self.project.author.length ? [@"by " stringByAppendingString:self.project.author] : @"Modrinth"; }
- (NSString *)availableVersion { return self.version.number.length ? self.version.number : (self.version ? self.version.versionId : nil); }
- (unsigned long long)downloadSize { return self.version.file.size; }
- (NSString *)installedVersion { return [Installer() installedEntryForModrinth:self.project.projectId].version; }
- (NSString *)installTitle { return @"Install"; }
- (NSString *)refusal {
    if (self.looking) return @"Looking up the newest version...";
    return self.version ? nil : (self.versionProblem ?: @"No version of this pack can be installed.");
}
- (NSString *)explanation { return @"Choose it in the game's resource pack list."; }
- (NSString *)confirmText { return @"This pack comes from Modrinth, not from Horizon's reviewed registry. The app checks the file against the fingerprint Modrinth lists and that it is a plain resource pack, but nobody at Horizon has reviewed it."; }

- (void)startDownload:(HZMarketFetcher *)f progress:(void (^)(double))progress done:(void (^)(NSString *, NSString *))done {
    [f fetchURL:self.version.file.url size:self.version.file.size stagingDir:[Installer() stagingDirectory] redirectHosts:@[@"cdn.modrinth.com"] progress:progress done:done];
}
- (NSString *)placeFile:(NSString *)path { return [Installer() placeModrinthDownloaded:path project:self.project version:self.version]; }
- (NSString *)removeInstalled { return [Installer() removeModrinth:self.project.projectId]; }

- (NSAttributedString *)detailText {
    HZModrinthProject *p = self.project; HZModrinthVersion *v = self.version;
    NSMutableAttributedString *s = [HZMarketPageController builder];
    UIFont *h2 = [UIFont systemFontOfSize:16 weight:UIFontWeightBold], *body = [UIFont systemFontOfSize:15];
    UIColor *white = [HZTheme text], *grey = [HZTheme secondaryText];
    void (^add)(NSString *, UIFont *, UIColor *) = ^(NSString *t, UIFont *f, UIColor *c) { [HZMarketPageController add:t to:s font:f color:c]; };
    if (p.summary.length) add([p.summary stringByAppendingString:@"\n\n"], [UIFont systemFontOfSize:17 weight:UIFontWeightMedium], white);
    add(@"Details\n", h2, white);
    NSMutableString *facts = [NSMutableString new];
    [facts appendString:@"Type: Resource pack\nSource: Modrinth\n"];
    if (p.license.length) [facts appendFormat:@"Licence: %@\n", p.license];
    if (p.downloads) [facts appendFormat:@"%llu downloads\n", p.downloads];
    if (v) [facts appendFormat:@"Version %@ for Minecraft 26.3, %@\nFile: %@\n", v.number, [NSByteCountFormatter stringFromByteCount:(long long)v.file.size countStyle:NSByteCountFormatterCountStyleFile], v.file.name];
    else if (self.looking) [facts appendString:@"Looking up the newest version...\n"];
    else if (self.versionProblem) [facts appendFormat:@"%@\n", self.versionProblem];
    [facts appendFormat:@"Page: https://modrinth.com/resourcepack/%@\n", p.slug];
    add(facts, body, grey);
    add(@"\nWhat the app checks\n", h2, white);
    add(@"The file must come from Modrinth's file server, match the size and SHA-512 Modrinth lists, be a ZIP whose paths are all plain, and have pack.mcmeta at its root. Modrinth packs are not reviewed by Horizon.\n", body, grey);
    return s;
}
@end
