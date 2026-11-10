#import "MarketCells.h"
#import "LauncherTheme.h"

@implementation HZMarketRow
@end

NSString *HZMarketSymbolForKind(NSString *kind) {
    NSDictionary *s = @{@"resourcepack": @"paintpalette.fill", @"mod": @"puzzlepiece.extension.fill", @"native-mod": @"cpu.fill",
                        @"shader": @"sun.max.fill", @"modpack": @"shippingbox.fill", @"shaderpack": @"sun.max.fill", @"datapack": @"doc.zipper"};
    return s[kind] ?: @"cube.fill";
}
UIColor *HZMarketColorForKind(NSString *kind) {
    NSDictionary *c = @{@"resourcepack": [UIColor colorWithRed:0.30 green:0.66 blue:0.95 alpha:1], @"mod": [UIColor colorWithRed:0.62 green:0.46 blue:0.95 alpha:1],
                        @"native-mod": [UIColor colorWithRed:0.60 green:0.60 blue:0.65 alpha:1], @"shader": [UIColor colorWithRed:0.98 green:0.70 blue:0.22 alpha:1],
                        @"modpack": [UIColor colorWithRed:0.95 green:0.45 blue:0.45 alpha:1], @"shaderpack": [UIColor colorWithRed:0.98 green:0.70 blue:0.22 alpha:1],
                        @"datapack": [UIColor colorWithRed:0.35 green:0.80 blue:0.75 alpha:1]};
    return c[kind] ?: [UIColor colorWithWhite:0.6 alpha:1];
}
NSString *HZMarketKindName(NSString *kind) {
    NSDictionary *n = @{@"mod": @"Mod", @"native-mod": @"Native mod", @"resourcepack": @"Resource pack", @"shader": @"Shader",
                        @"modpack": @"Modpack", @"shaderpack": @"Shader pack", @"datapack": @"Data pack"};
    return n[kind] ?: kind;
}

@implementation HZMarketCardCell {
    UIView *_card, *_tile;
    UIImageView *_icon;
    UILabel *_title, *_meta, *_summary, *_pill;
    UIView *_pillBox;
    NSLayoutConstraint *_summaryHeight;
}

+ (NSString *)reuseIdentifier { return @"card"; }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _card = [UIView new];
        _card.backgroundColor = [HZTheme surface];
        _card.layer.cornerRadius = 18;
        _card.layer.cornerCurve = kCACornerCurveContinuous;
        _card.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_card];

        _tile = [UIView new];
        _tile.layer.cornerRadius = 14;
        _tile.layer.cornerCurve = kCACornerCurveContinuous;
        _tile.translatesAutoresizingMaskIntoConstraints = NO;
        _icon = [UIImageView new];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _icon.tintColor = UIColor.whiteColor;
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        [_tile addSubview:_icon];

        _title = [HZTheme labelWithSize:17 weight:UIFontWeightSemibold color:[HZTheme text]];
        _title.numberOfLines = 1;
        _meta = [HZTheme labelWithSize:12 weight:UIFontWeightMedium color:[HZTheme tertiaryText]];
        _meta.numberOfLines = 1;
        _summary = [HZTheme labelWithSize:14 weight:UIFontWeightRegular color:[HZTheme secondaryText]];
        _summary.numberOfLines = 2;

        _pill = [HZTheme labelWithSize:13 weight:UIFontWeightSemibold color:[HZTheme text]];
        _pill.numberOfLines = 1;
        _pill.textAlignment = NSTextAlignmentCenter;
        _pillBox = [UIView new];
        _pillBox.layer.cornerRadius = 14;
        _pillBox.layer.cornerCurve = kCACornerCurveContinuous;
        _pillBox.translatesAutoresizingMaskIntoConstraints = NO;
        _pill.translatesAutoresizingMaskIntoConstraints = NO;
        [_pillBox addSubview:_pill];
        [_pillBox setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_pillBox setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[_title, _meta, _summary]];
        text.axis = UILayoutConstraintAxisVertical; text.spacing = 3;
        text.translatesAutoresizingMaskIntoConstraints = NO;
        [_card addSubview:_tile]; [_card addSubview:text]; [_card addSubview:_pillBox];

        UILayoutGuide *g = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5], [_card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5],
            [_card.leadingAnchor constraintEqualToAnchor:g.leadingAnchor], [_card.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
            [_tile.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:14], [_tile.topAnchor constraintEqualToAnchor:_card.topAnchor constant:14],
            [_tile.widthAnchor constraintEqualToConstant:52], [_tile.heightAnchor constraintEqualToConstant:52],
            [_icon.centerXAnchor constraintEqualToAnchor:_tile.centerXAnchor], [_icon.centerYAnchor constraintEqualToAnchor:_tile.centerYAnchor],
            [_icon.widthAnchor constraintEqualToConstant:26], [_icon.heightAnchor constraintEqualToConstant:26],
            [text.leadingAnchor constraintEqualToAnchor:_tile.trailingAnchor constant:14], [text.topAnchor constraintEqualToAnchor:_card.topAnchor constant:13],
            [text.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-13],
            [text.trailingAnchor constraintEqualToAnchor:_pillBox.leadingAnchor constant:-12],
            [_pillBox.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-14], [_pillBox.centerYAnchor constraintEqualToAnchor:_card.centerYAnchor],
            [_pillBox.heightAnchor constraintEqualToConstant:28],
            [_pill.leadingAnchor constraintEqualToAnchor:_pillBox.leadingAnchor constant:12], [_pill.trailingAnchor constraintEqualToAnchor:_pillBox.trailingAnchor constant:-12],
            [_pill.centerYAnchor constraintEqualToAnchor:_pillBox.centerYAnchor],
            [_card.heightAnchor constraintGreaterThanOrEqualToConstant:80]]];
    }
    return self;
}

- (void)setHighlighted:(BOOL)h animated:(BOOL)a {
    [super setHighlighted:h animated:a];
    [UIView animateWithDuration:0.15 animations:^{ self->_card.alpha = h ? 0.7 : 1; }];
}

- (void)configure:(HZMarketRow *)row compact:(BOOL)compact {
    _tile.backgroundColor = HZMarketColorForKind(row.kind);
    _icon.image = [UIImage systemImageNamed:HZMarketSymbolForKind(row.kind) withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold]];
    _title.text = row.title;
    _meta.text = [NSString stringWithFormat:@"%@  \u00B7  %@", HZMarketKindName(row.kind), row.source];
    _summary.text = row.summary;
    _summary.hidden = compact || !row.summary.length;
    switch (row.state) {
        case HZRowGet:
            _pillBox.backgroundColor = [HZTheme accent]; _pill.textColor = [HZTheme onAccent]; _pill.text = row.stateText ?: @"Get"; break;
        case HZRowInstalled:
            _pillBox.backgroundColor = [[HZTheme accent] colorWithAlphaComponent:0.22]; _pill.textColor = [HZTheme accent]; _pill.text = row.stateText ?: @"Installed"; break;
        case HZRowUnavailable:
            _pillBox.backgroundColor = [HZTheme surface]; _pill.textColor = [HZTheme tertiaryText]; _pill.text = row.stateText ?: @"Unavailable"; break;
    }
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@", row.title, HZMarketKindName(row.kind), _pill.text];
    self.accessibilityTraits = UIAccessibilityTraitButton;
}
@end
