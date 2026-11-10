#import "LauncherFileManager.h"
#import "LauncherTheme.h"
#import "FileBrowser.h"
#import "LauncherModel.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const unsigned long long kPreviewLimit = 256 * 1024;   // text shown in the app; bigger files are shared instead

@interface HZLauncherFileManagerController () <UIDocumentPickerDelegate>
@property (copy) NSString *path;
@property (strong) HZFileBrowser *browser;
@property (copy) NSArray<HZFileEntry *> *entries;
@property (copy) NSString *error;
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *folderSizes;   // measured in the background
@end

@implementation HZLauncherFileManagerController

- (instancetype)initWithPath:(NSString *)relativePath {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _path = [relativePath copy];
        _browser = [[HZFileBrowser alloc] initWithRoot:[HZLauncherModel shared].root];
        _folderSizes = [NSMutableDictionary new];
        _entries = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.path.length ? self.path.lastPathComponent : @"Files";
    [HZTheme styleScreen:self];
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.tableView.separatorColor = [HZTheme separator];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"c"];
    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"] menu:[self addMenu]];
    self.navigationItem.rightBarButtonItem = add;
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reload]; }

- (UIMenu *)addMenu {
    __weak typeof(self) weak = self;
    return [UIMenu menuWithChildren:@[
        [UIAction actionWithTitle:@"New folder" image:[UIImage systemImageNamed:@"folder.badge.plus"] identifier:nil handler:^(UIAction *a) { [weak newFolder]; }],
        [UIAction actionWithTitle:@"Add files from the Files app" image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil handler:^(UIAction *a) { [weak pickFiles]; }],
    ]];
}

static NSString *ByteText(unsigned long long b) {
    return [NSByteCountFormatter stringFromByteCount:(long long)b countStyle:NSByteCountFormatterCountStyleFile];
}

- (void)reload {
    NSString *err = nil;
    NSArray *list = [self.browser listFolder:self.path error:&err];
    self.entries = list ?: @[];
    self.error = list ? nil : err;
    [self.tableView reloadData];
    // Folder sizes walk the disk: measure them off the main thread, one at a time, and fill them in.
    NSArray<HZFileEntry *> *folders = [self.entries filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(HZFileEntry *e, id b) { return e.isFolder; }]];
    HZFileBrowser *browser = self.browser;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        for (HZFileEntry *f in folders) {
            unsigned long long s = [browser sizeOf:f.relativePath];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.folderSizes[f.relativePath] = @(s);
                NSUInteger row = [self.entries indexOfObjectPassingTest:^BOOL(HZFileEntry *e, NSUInteger i, BOOL *stop) { return [e.relativePath isEqualToString:f.relativePath]; }];
                if (row != NSNotFound) [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
            });
        }
    });
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.entries.count; }

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (self.error) return self.error;
    unsigned long long free = 0;
    NSDictionary *fs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:self.browser.root error:nil];
    free = [fs[NSFileSystemFreeSize] unsignedLongLongValue];
    return [NSString stringWithFormat:@"%lu items. %@ free on this phone. Everything here is inside the Horizon folder; nothing outside it can be reached.",
            (unsigned long)self.entries.count, ByteText(free)];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    HZFileEntry *e = self.entries[(NSUInteger)ip.row];
    cell.backgroundColor = [HZTheme surface];
    cell.textLabel.textColor = [HZTheme text];
    cell.detailTextLabel.textColor = [HZTheme secondaryText];
    cell.textLabel.text = e.name;
    NSString *date = e.modified ? [NSDateFormatter localizedStringFromDate:e.modified dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle] : @"";
    NSString *size;
    if (e.isFolder) { NSNumber *n = self.folderSizes[e.relativePath]; size = n ? ByteText(n.unsignedLongLongValue) : @"..."; }
    else size = ByteText(e.size);
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@   %@", size, date];
    cell.imageView.image = [UIImage systemImageNamed:e.isFolder ? @"folder.fill" : @"doc"];
    cell.imageView.tintColor = e.isFolder ? [HZTheme accent] : [HZTheme secondaryText];
    cell.accessoryType = e.isFolder ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    HZFileEntry *e = self.entries[(NSUInteger)ip.row];
    if (e.isFolder) {
        [self.navigationController pushViewController:[[HZLauncherFileManagerController alloc] initWithPath:e.relativePath] animated:YES];
    } else {
        [self openFile:e];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    HZFileEntry *e = self.entries[(NSUInteger)ip.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) { [self confirmDelete:e done:done]; }];
    UIContextualAction *ren = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Rename"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) { [self rename:e]; done(YES); }];
    ren.backgroundColor = [UIColor systemGrayColor];
    UIContextualAction *share = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Share"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) { [self share:e from:[tv cellForRowAtIndexPath:ip]]; done(YES); }];
    share.backgroundColor = [UIColor systemBlueColor];
    return [UISwipeActionsConfiguration configurationWithActions:@[del, ren, share]];
}

#pragma mark - actions

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)confirmDelete:(HZFileEntry *)e done:(void (^)(BOOL))done {
    HZDeleteRisk risk = [self.browser deleteRiskOf:e.relativePath];
    unsigned long long size = e.isFolder ? [self.folderSizes[e.relativePath] unsignedLongLongValue] : e.size;
    if (risk == HZDeleteForbidden || risk == HZDeleteAccount) {
        [self alert:@"Not here" message:[HZFileBrowser warningForRisk:risk name:e.name size:size]];
        done(NO); return;
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Delete %@?", e.name]
        message:[HZFileBrowser warningForRisk:risk name:e.name size:size] preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { done(NO); }]];
    [a addAction:[UIAlertAction actionWithTitle:risk == HZDeleteOrdinary ? @"Delete" : @"Delete anyway" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        NSString *bad = [self.browser deletePath:e.relativePath];
        done(bad == nil);
        if (bad) [self alert:@"Could not delete" message:bad];
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)rename:(HZFileEntry *)e {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Rename" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = e.name; f.clearButtonMode = UITextFieldViewModeAlways; f.autocorrectionType = UITextAutocorrectionTypeNo; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *bad = [self.browser renamePath:e.relativePath to:a.textFields.firstObject.text ?: @""];
        if (bad) [self alert:@"Could not rename" message:bad];
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)newFolder {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"New folder" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"Name"; f.autocorrectionType = UITextAutocorrectionTypeNo; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *bad = [self.browser createFolderNamed:a.textFields.firstObject.text ?: @"" inside:self.path];
        if (bad) [self alert:@"Could not create the folder" message:bad];
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)share:(HZFileEntry *)e from:(UIView *)source {
    NSString *abs = [self.browser resolve:e.relativePath];
    if (!abs) return;
    if (e.isFolder) { [self alert:@"Folders cannot be shared yet" message:@"Open the folder and share its files one by one. Exporting a folder as a zip is planned."]; return; }
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:abs]] applicationActivities:nil];
    vc.popoverPresentationController.sourceView = source;
    [self presentViewController:vc animated:YES completion:nil];
}

// Text files up to 256 KB open in the app; everything else goes to the share sheet.
- (void)openFile:(HZFileEntry *)e {
    NSString *abs = [self.browser resolve:e.relativePath];
    if (!abs) return;
    NSString *ext = e.name.pathExtension.lowercaseString;
    BOOL texty = [@[@"txt", @"log", @"json", @"csv", @"md", @"toml", @"cfg", @"properties", @"mcmeta", @"xml", @"yml", @"yaml", @"snbt", @"lang"] containsObject:ext]
              || [e.name isEqualToString:@"options.txt"];
    if (!texty || e.size > kPreviewLimit) { [self share:e from:self.view]; return; }
    NSData *d = [NSData dataWithContentsOfFile:abs];
    NSString *text = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
    if (!text) { [self share:e from:self.view]; return; }   // not UTF-8 text after all
    UIViewController *vc = [UIViewController new];
    vc.title = e.name;
    vc.view.backgroundColor = self.view.backgroundColor;
    UITextView *tv = [UITextView new];
    tv.editable = NO; tv.text = text;
    tv.backgroundColor = [HZTheme codeBackground];
    tv.textColor = [HZTheme text];
    tv.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    tv.layer.cornerRadius = 10;
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:tv];
    UILayoutGuide *g = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [tv.topAnchor constraintEqualToAnchor:g.topAnchor constant:8], [tv.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-8],
        [tv.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16], [tv.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
    ]];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - adding files

- (void)pickFiles {
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:NO];
    p.delegate = self; p.allowsMultipleSelection = YES;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    HZFileBrowser *browser = self.browser; NSString *folder = self.path;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableArray *problems = [NSMutableArray new];
        NSUInteger added = 0;
        for (NSURL *src in urls) {
            BOOL scoped = [src startAccessingSecurityScopedResource];
            NSString *name = src.lastPathComponent;
            NSString *bad = [HZFileBrowser problemWithName:name];
            NSString *dest = bad ? nil : [browser resolve:[HZFileBrowser join:folder name:name]];
            NSDictionary *a = [fm attributesOfItemAtPath:src.path error:nil];
            unsigned long long need = a.fileSize;
            unsigned long long free = [[fm attributesOfFileSystemForPath:browser.root error:nil][NSFileSystemFreeSize] unsignedLongLongValue];
            if (bad || !dest) [problems addObject:[NSString stringWithFormat:@"%@: %@", name, bad ?: @"not allowed here"]];
            else if ([fm fileExistsAtPath:dest]) [problems addObject:[NSString stringWithFormat:@"%@: something with that name is already here", name]];
            else if (free && free < need + (100ull << 20)) [problems addObject:[NSString stringWithFormat:@"%@: not enough space", name]];
            else {
                NSError *e = nil;
                if ([fm copyItemAtPath:src.path toPath:dest error:&e]) added++;
                else [problems addObject:[NSString stringWithFormat:@"%@: %@", name, e.localizedDescription]];
            }
            if (scoped) [src stopAccessingSecurityScopedResource];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reload];
            if (problems.count) [self alert:added ? @"Some files were not added" : @"Nothing was added" message:[problems componentsJoinedByString:@"\n"]];
        });
    });
}

@end
