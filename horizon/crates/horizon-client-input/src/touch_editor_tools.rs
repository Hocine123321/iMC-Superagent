//! The touch controls editor's tools, as pure data: snapping a dragged button, finding buttons
//! that overlap or leave the safe area, and the named layouts (presets). No winit, no game state,
//! so every rule is tested here.
//!
//! Rectangles are `[x, y, w, h]` in pixels on a screen of `size`, as in `touch_layout`.

use crate::touch_layout::{COUNT, ControlLayout, Slot};

/// The grid a dragged button snaps to, as a fraction of the screen's shorter side.
pub const GRID: f32 = 1.0 / 24.0;
/// How near an edge or a grid line must be, as a fraction of the shorter side, to pull a button.
/// Small enough that a button can still be put just beside another one.
pub const SNAP_RANGE: f32 = 1.0 / 60.0;

/// A line a snap landed on, for the editor to draw: vertical at `x` or horizontal at `y`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Guide {
    Vertical(f32),
    Horizontal(f32),
}

/// What a snap did: the rectangle after it and the lines it landed on.
#[derive(Clone, Debug, PartialEq)]
pub struct Snapped {
    pub rect: [f32; 4],
    pub guides: Vec<Guide>,
}

/// The candidates on one axis: positions a button's start, middle or end can be pulled to.
fn pull(start: f32, len: f32, lines: &[f32], range: f32) -> Option<(f32, f32)> {
    // For each of the button's three reference points, the nearest line within range; then the
    // one that moves the button least wins.
    let points = [start, start + len / 2.0, start + len];
    let mut best: Option<(f32, f32)> = None;
    for p in &points {
        for line in lines {
            let d = line - p;
            if d.abs() <= range && best.is_none_or(|(b, _)| d.abs() < b.abs()) {
                best = Some((d, *line));
            }
        }
    }
    best
}

/// The lines of the grid on one axis of length `len`, `step` apart.
fn grid_lines(len: f32, step: f32) -> Vec<f32> {
    if step <= 0.0 {
        return Vec::new();
    }
    let n = (len / step).floor() as i32;
    (0..=n).map(|i| i as f32 * step).collect()
}

/// `rect` after snapping to the screen's edges and middle, the grid, and the edges and middles
/// of `others`. A button that is near nothing stays exactly where the finger put it, and the
/// result never leaves the screen.
pub fn snap(rect: [f32; 4], others: &[[f32; 4]], size: (f32, f32), grid: bool) -> Snapped {
    let short = size.0.min(size.1);
    let range = short * SNAP_RANGE;
    let mut xs = vec![0.0, size.0 / 2.0, size.0];
    let mut ys = vec![0.0, size.1 / 2.0, size.1];
    if grid {
        xs.extend(grid_lines(size.0, short * GRID));
        ys.extend(grid_lines(size.1, short * GRID));
    }
    for o in others {
        xs.extend([o[0], o[0] + o[2] / 2.0, o[0] + o[2]]);
        ys.extend([o[1], o[1] + o[3] / 2.0, o[1] + o[3]]);
    }
    let mut out = rect;
    let mut guides = Vec::new();
    if let Some((d, line)) = pull(rect[0], rect[2], &xs, range) {
        out[0] += d;
        guides.push(Guide::Vertical(line));
    }
    if let Some((d, line)) = pull(rect[1], rect[3], &ys, range) {
        out[1] += d;
        guides.push(Guide::Horizontal(line));
    }
    out[0] = out[0].min(size.0 - out[2]).max(0.0);
    out[1] = out[1].min(size.1 - out[3]).max(0.0);
    Snapped { rect: out, guides }
}

/// Why a button is flagged.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Problem {
    /// It overlaps the button at this index.
    Overlaps(usize),
    /// It reaches into the margin the notch, the corners or the home bar take.
    OutsideSafeArea,
}

/// Whether two rectangles share area. Touching edges do not count.
pub fn overlap(a: [f32; 4], b: [f32; 4]) -> bool {
    a[0] < b[0] + b[2] && b[0] < a[0] + a[2] && a[1] < b[1] + b[3] && b[1] < a[1] + a[3]
}

/// The safe area as `[x, y, w, h]`: the screen less a margin of `fraction` of the width on the
/// sides and of the height on the top and bottom.
pub fn safe_area(size: (f32, f32), side: f32, top: f32, bottom: f32) -> [f32; 4] {
    let (l, r) = (size.0 * side, size.0 * side);
    let (t, b) = (size.1 * top, size.1 * bottom);
    [l, t, (size.0 - l - r).max(0.0), (size.1 - t - b).max(0.0)]
}

/// Every flagged button: `rects[i]` is where button `i` stands, `None` when it is hidden or
/// off. A hidden button is never flagged and never flags another. Each problem is listed once
/// per pair (the lower index carries `Overlaps(higher)` on the higher one, too), so the editor
/// can frame both.
pub fn problems(rects: &[Option<[f32; 4]>], safe: [f32; 4]) -> Vec<(usize, Problem)> {
    let mut out = Vec::new();
    for (i, a) in rects.iter().enumerate() {
        let Some(a) = a else { continue };
        let inside = a[0] >= safe[0] - 0.5
            && a[1] >= safe[1] - 0.5
            && a[0] + a[2] <= safe[0] + safe[2] + 0.5
            && a[1] + a[3] <= safe[1] + safe[3] + 0.5;
        if !inside {
            out.push((i, Problem::OutsideSafeArea));
        }
        for (j, b) in rects.iter().enumerate() {
            if i == j {
                continue;
            }
            if let Some(b) = b
                && overlap(*a, *b)
            {
                out.push((i, Problem::Overlaps(j)));
            }
        }
    }
    out
}

/// The built-in layouts, by name. A layout is a nudge from the default (`touch_layout`), so
/// each is a few moves.
pub const BUILT_IN: [&str; 3] = ["Default", "Left-handed", "Compact"];

/// The built-in layout `name`, or `None` for a name that is not one.
pub fn built_in(name: &str) -> Option<ControlLayout> {
    let mut l = ControlLayout::default();
    match name {
        "Default" => {}
        // The movement and look sides swap: the action buttons go left, the pause row stays.
        "Left-handed" => {
            for (i, dx) in [
                (0, -0.80), // jump
                (1, -0.80), // sneak
                (2, -0.80), // run
                (3, -0.80), // use
            ] {
                l.slots[i] = Slot {
                    dx,
                    ..Slot::default()
                };
            }
        }
        // Everything a little smaller and a little fainter, for a small phone or a clear view.
        "Compact" => {
            for s in l.slots.iter_mut() {
                *s = Slot {
                    scale: 0.8,
                    opacity: 0.7,
                    ..Slot::default()
                };
            }
        }
        _ => return None,
    }
    Some(l)
}

/// A name a player may give a saved layout: 1 to 20 letters, digits, spaces, hyphens and
/// underscores, not starting with a space and not one of the built-in names. It ends up in a
/// line of a file, so nothing else is let through.
pub fn valid_preset_name(name: &str) -> bool {
    let n = name.trim();
    !n.is_empty()
        && n.chars().count() <= 20
        && n == name
        && n.chars()
            .all(|c| c.is_ascii_alphanumeric() || c == ' ' || c == '-' || c == '_')
        && !BUILT_IN.iter().any(|b| b.eq_ignore_ascii_case(n))
}

/// The most layouts a player can keep.
pub const MAX_SAVED: usize = 6;

/// The player's saved layouts.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Presets {
    pub saved: Vec<(String, ControlLayout)>,
}

impl Presets {
    /// Keeps `layout` under `name`, replacing a layout of that name. Fails on a bad name or when
    /// all [`MAX_SAVED`] places are taken by other names.
    pub fn save(&mut self, name: &str, layout: &ControlLayout) -> bool {
        if !valid_preset_name(name) {
            return false;
        }
        if let Some(entry) = self.saved.iter_mut().find(|(n, _)| n == name) {
            entry.1 = layout.clone();
            return true;
        }
        if self.saved.len() >= MAX_SAVED {
            return false;
        }
        self.saved.push((name.to_owned(), layout.clone()));
        true
    }

    /// Forgets the layout `name`.
    pub fn delete(&mut self, name: &str) -> bool {
        let before = self.saved.len();
        self.saved.retain(|(n, _)| n != name);
        self.saved.len() != before
    }

    /// The layout `name`, built in or saved.
    pub fn get(&self, name: &str) -> Option<ControlLayout> {
        built_in(name).or_else(|| {
            self.saved
                .iter()
                .find(|(n, _)| n == name)
                .map(|(_, l)| l.clone())
        })
    }

    /// Every name in the order the editor lists them: built in, then saved.
    pub fn names(&self) -> Vec<String> {
        BUILT_IN
            .iter()
            .map(|s| (*s).to_owned())
            .chain(self.saved.iter().map(|(n, _)| n.clone()))
            .collect()
    }

    /// The file's text: a `[name]` line, then that layout's lines (`touch_layout`), for each
    /// saved layout.
    pub fn serialize(&self) -> String {
        let mut out = String::new();
        for (name, layout) in &self.saved {
            out.push_str(&format!("[{name}]\n"));
            out.push_str(&layout.serialize());
        }
        out
    }

    /// Reads the file's text. A bad name, a repeated name or a section past [`MAX_SAVED`] is
    /// dropped; the lines inside are read as `ControlLayout::parse` reads them.
    pub fn parse(text: &str) -> Self {
        let mut presets = Presets::default();
        let mut current: Option<(String, String)> = None;
        let flush = |presets: &mut Presets, cur: Option<(String, String)>| {
            if let Some((name, body)) = cur
                && !presets.saved.iter().any(|(n, _)| *n == name)
            {
                presets.save(&name, &ControlLayout::parse(&body));
            }
        };
        for line in text.lines() {
            if let Some(name) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
                let prev = current.take();
                flush(&mut presets, prev);
                current = Some((name.to_owned(), String::new()));
            } else if let Some((_, body)) = current.as_mut() {
                body.push_str(line);
                body.push('\n');
            }
        }
        flush(&mut presets, current);
        presets
    }
}

/// How many slots a layout has, for a test that the built-ins cover them all.
pub const SLOTS: usize = COUNT;

#[cfg(test)]
mod tests {
    use super::*;

    const PHONE: (f32, f32) = (2532.0, 1170.0);

    #[test]
    fn a_button_near_nothing_stays_where_the_finger_put_it() {
        // Chosen to sit well away from every grid line, edge and middle.
        let r = [600.0 + 17.0, 300.0 + 11.0, 150.0, 100.0];
        let s = snap(r, &[], PHONE, false);
        assert_eq!(s.rect, r);
        assert!(s.guides.is_empty());
    }

    #[test]
    fn a_button_near_the_screen_edge_is_pulled_to_it() {
        let s = snap([6.0, 400.0, 150.0, 100.0], &[], PHONE, false);
        assert_eq!(s.rect[0], 0.0);
        assert!(s.guides.contains(&Guide::Vertical(0.0)));
    }

    #[test]
    fn a_button_near_another_lines_up_with_its_edge() {
        let other = [1000.0, 200.0, 150.0, 100.0];
        // Its left edge is 5 px from the other's left edge, and its top near the other's top.
        let s = snap([1005.0, 203.0, 150.0, 100.0], &[other], PHONE, false);
        assert_eq!(s.rect[0], 1000.0);
        assert_eq!(s.rect[1], 200.0);
        assert!(s.guides.contains(&Guide::Vertical(1000.0)));
        assert!(s.guides.contains(&Guide::Horizontal(200.0)));
    }

    #[test]
    fn the_far_edge_and_the_middle_snap_too() {
        // The right edge near the screen's right edge.
        let s = snap([2532.0 - 150.0 - 4.0, 400.0, 150.0, 100.0], &[], PHONE, false);
        assert_eq!(s.rect[0], 2532.0 - 150.0);
        // The middle near the screen's middle.
        let s = snap([1266.0 - 75.0 + 5.0, 400.0, 150.0, 100.0], &[], PHONE, false);
        assert_eq!(s.rect[0], 1266.0 - 75.0);
    }

    #[test]
    fn the_grid_pulls_only_when_it_is_on() {
        let step = 1170.0 / 24.0;
        let near = [step * 5.0 + 4.0, step * 3.0 + 4.0, 150.0, 100.0];
        let off = snap(near, &[], PHONE, false);
        let on = snap(near, &[], PHONE, true);
        assert_eq!(on.rect[0], step * 5.0);
        assert_eq!(on.rect[1], step * 3.0);
        assert_ne!(off.rect, on.rect);
    }

    #[test]
    fn a_snap_never_leaves_the_screen() {
        let s = snap([-30.0, -30.0, 150.0, 100.0], &[], PHONE, true);
        assert!(s.rect[0] >= 0.0 && s.rect[1] >= 0.0);
        let s = snap([2500.0, 1150.0, 150.0, 100.0], &[], PHONE, true);
        assert!(s.rect[0] + s.rect[2] <= PHONE.0 && s.rect[1] + s.rect[3] <= PHONE.1);
    }

    #[test]
    fn touching_edges_do_not_overlap_but_shared_area_does() {
        let a = [0.0, 0.0, 100.0, 100.0];
        assert!(!overlap(a, [100.0, 0.0, 100.0, 100.0]));
        assert!(!overlap(a, [0.0, 100.0, 100.0, 100.0]));
        assert!(overlap(a, [99.0, 99.0, 100.0, 100.0]));
        assert!(overlap(a, [10.0, 10.0, 5.0, 5.0]), "one inside the other");
    }

    #[test]
    fn overlapping_buttons_are_both_flagged_and_hidden_ones_never() {
        let safe = safe_area(PHONE, 0.0, 0.0, 0.0);
        let rects = [
            Some([100.0, 100.0, 200.0, 200.0]),
            Some([250.0, 250.0, 200.0, 200.0]),
            None,
            Some([1500.0, 100.0, 200.0, 200.0]),
        ];
        let p = problems(&rects, safe);
        assert!(p.contains(&(0, Problem::Overlaps(1))));
        assert!(p.contains(&(1, Problem::Overlaps(0))));
        assert!(!p.iter().any(|(i, _)| *i == 2 || *i == 3));
    }

    #[test]
    fn a_button_in_the_margin_is_outside_the_safe_area() {
        let safe = safe_area(PHONE, 0.08, 0.04, 0.07);
        let rects = [
            Some([10.0, 400.0, 150.0, 100.0]),
            Some([safe[0] + 10.0, safe[1] + 10.0, 150.0, 100.0]),
        ];
        let p = problems(&rects, safe);
        assert!(p.contains(&(0, Problem::OutsideSafeArea)));
        assert!(!p.iter().any(|(i, _)| *i == 1));
    }

    #[test]
    fn the_safe_area_is_the_screen_less_its_margins_and_never_negative() {
        let s = safe_area((1000.0, 500.0), 0.1, 0.1, 0.2);
        assert_eq!(s, [100.0, 50.0, 800.0, 350.0]);
        let tiny = safe_area((100.0, 100.0), 0.9, 0.9, 0.9);
        assert!(tiny[2] >= 0.0 && tiny[3] >= 0.0);
    }

    #[test]
    fn the_built_in_layouts_exist_and_the_default_changes_nothing() {
        for name in BUILT_IN {
            assert!(built_in(name).is_some(), "{name}");
        }
        assert!(built_in("Default").unwrap().is_default());
        assert!(built_in("nope").is_none());
        assert_eq!(SLOTS, COUNT);
    }

    #[test]
    fn left_handed_moves_the_action_buttons_left_and_stays_in_range() {
        let l = built_in("Left-handed").unwrap();
        for i in 0..4 {
            assert!(l.slots[i].dx < 0.0, "button {i}");
            assert_eq!(l.slots[i], l.slots[i].clamped());
        }
        // The pause row and Back are not moved.
        assert!(l.slots[4].is_default() && l.slots[9].is_default());
    }

    #[test]
    fn compact_shrinks_and_fades_every_button_within_the_allowed_range() {
        let l = built_in("Compact").unwrap();
        for s in l.slots {
            assert!(s.scale < 1.0 && s.opacity < 1.0);
            assert_eq!(s, s.clamped());
        }
    }

    #[test]
    fn preset_names_are_short_plain_and_not_a_built_in() {
        assert!(valid_preset_name("Night play"));
        assert!(valid_preset_name("a-b_c 2"));
        for bad in ["", " x", "x ", "default", "LEFT-HANDED", "a:b", "a]b", "[x", "x\ny", "é"] {
            assert!(!valid_preset_name(bad), "{bad:?}");
        }
        assert!(!valid_preset_name(&"x".repeat(21)));
        assert!(valid_preset_name(&"x".repeat(20)));
    }

    #[test]
    fn saving_replaces_by_name_and_stops_at_the_limit() {
        let mut p = Presets::default();
        let mut l = ControlLayout::default();
        l.slots[0].dx = 0.2;
        assert!(p.save("one", &l));
        l.slots[0].dx = 0.3;
        assert!(p.save("one", &l), "same name replaces");
        assert_eq!(p.saved.len(), 1);
        assert_eq!(p.get("one").unwrap().slots[0].dx, 0.3);
        for i in 1..MAX_SAVED {
            assert!(p.save(&format!("p{i}"), &l));
        }
        assert!(!p.save("one more", &l), "no place left");
        assert!(p.save("one", &l), "but a name that exists still replaces");
        assert!(!p.save("bad:name", &l));
        assert!(!p.save("Compact", &l), "a built in name is taken");
    }

    #[test]
    fn deleting_forgets_a_saved_layout_and_not_a_built_in() {
        let mut p = Presets::default();
        p.save("mine", &ControlLayout::default());
        assert!(p.delete("mine"));
        assert!(!p.delete("mine"));
        assert!(!p.delete("Compact"));
        assert!(p.get("Compact").is_some());
    }

    #[test]
    fn names_list_the_built_ins_first_then_the_saved() {
        let mut p = Presets::default();
        p.save("mine", &ControlLayout::default());
        assert_eq!(
            p.names(),
            vec!["Default", "Left-handed", "Compact", "mine"]
        );
    }

    #[test]
    fn saved_layouts_survive_the_file_exactly() {
        let mut p = Presets::default();
        let mut a = ControlLayout::default();
        a.slots[0] = Slot {
            dx: 0.25,
            dy: -0.1,
            scale: 1.5,
            opacity: 0.5,
            shown: true,
        };
        a.slots[9].shown = false;
        let b = built_in("Compact").unwrap();
        p.save("first", &a);
        p.save("second one", &b);
        let back = Presets::parse(&p.serialize());
        assert_eq!(back.saved.len(), 2);
        assert_eq!(back.get("first").unwrap().slots[0].dx, 0.25);
        assert!(!back.get("first").unwrap().slots[9].shown);
        assert_eq!(back.get("second one").unwrap(), b);
    }

    #[test]
    fn a_file_with_junk_loses_only_the_junk() {
        let text = "stray line\n[good]\njump:0.1,0.0,1.0,1.0,true\n[bad:name]\njump:0.9,0,1,1,true\n[good]\njump:0.5,0,1,1,true\n[Compact]\n[ok]\nnot a line\n";
        let p = Presets::parse(text);
        let names: Vec<_> = p.saved.iter().map(|(n, _)| n.as_str()).collect();
        assert_eq!(names, vec!["good", "ok"]);
        assert_eq!(p.get("good").unwrap().slots[0].dx, 0.1, "the first one wins");
    }

    #[test]
    fn a_file_with_too_many_sections_keeps_the_limit() {
        let mut text = String::new();
        for i in 0..20 {
            text.push_str(&format!("[n{i}]\njump:0.1,0,1,1,true\n"));
        }
        assert_eq!(Presets::parse(&text).saved.len(), MAX_SAVED);
    }

    #[test]
    fn an_empty_file_has_no_saved_layouts_and_writes_nothing() {
        assert!(Presets::parse("").saved.is_empty());
        assert_eq!(Presets::default().serialize(), "");
    }
}

/// The editor's panel, version two: collapsible, with sliders. Pure geometry and slider maths.
pub mod panel2 {
    use crate::touch_layout::{MAX_SCALE, MIN_OPACITY, MIN_SCALE};

    /// What the panel's controls do.
    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    pub enum Control {
        /// The tab that folds the panel away or brings it back.
        Fold,
        /// The size slider's track.
        SizeSlider,
        /// The fade (opacity) slider's track.
        FadeSlider,
        ToggleShown,
        /// Snapping to the grid on or off (edges and other buttons always pull).
        ToggleSnap,
        /// Step to the next layout in the list.
        NextPreset,
        /// Keep the arrangement under the name shown.
        SavePreset,
        /// Forget the saved layout shown.
        DeletePreset,
        ResetButton,
        ResetAll,
        Cancel,
        Done,
    }

    pub const OPEN_W: f32 = 150.0;
    /// The tab a folded panel leaves, wide enough for a thumb.
    pub const TAB_W: f32 = 26.0;
    pub const ROW_H: f32 = 22.0;
    pub const GAP: f32 = 4.0;

    /// The width the panel takes: the tab alone when folded.
    pub fn width(open: bool) -> f32 {
        if open { OPEN_W } else { TAB_W }
    }

    /// The stage: the width left of the panel.
    pub fn stage_width(size: (f32, f32), open: bool) -> f32 {
        size.0 - width(open)
    }

    /// The controls with their places `(control, [x, y, w, h])`. Folded, only the tab; open, the
    /// tab is a strip down the panel's left edge and the rest sit to its right.
    pub fn layout(size: (f32, f32), open: bool) -> Vec<(Control, [f32; 4])> {
        let left = size.0 - width(open);
        let mut out = vec![(Control::Fold, [left, 0.0, TAB_W, size.1])];
        if !open {
            return out;
        }
        let x = left + TAB_W + GAP;
        let inner = OPEN_W - TAB_W - 2.0 * GAP;
        let half = (inner - GAP) / 2.0;
        // Below the heading and the picked button's name.
        let mut y = GAP + 24.0;
        // Rows: the two sliders, then pairs, so ten controls fit a small phone's height.
        for c in [Control::SizeSlider, Control::FadeSlider, Control::NextPreset] {
            out.push((c, [x, y, inner, ROW_H]));
            y += ROW_H + GAP;
        }
        let pairs = [
            (Control::ToggleShown, Control::ToggleSnap),
            (Control::SavePreset, Control::DeletePreset),
            (Control::ResetButton, Control::ResetAll),
        ];
        for (a, b) in pairs {
            out.push((a, [x, y, half, ROW_H]));
            out.push((b, [x + half + GAP, y, half, ROW_H]));
            y += ROW_H + GAP;
        }
        // Done and Cancel at the bottom, where a thumb rests.
        let bottom = size.1 - GAP - ROW_H;
        out.push((Control::Done, [x + half + GAP, bottom, half, ROW_H]));
        out.push((Control::Cancel, [x, bottom, half, ROW_H]));
        out
    }

    /// The control under `at`.
    pub fn control_at(size: (f32, f32), open: bool, at: (f32, f32)) -> Option<Control> {
        layout(size, open).into_iter().find_map(|(c, r)| {
            (at.0 >= r[0] && at.0 < r[0] + r[2] && at.1 >= r[1] && at.1 < r[1] + r[3]).then_some(c)
        })
    }

    /// Where along a track `[x, y, w, h]` the finger is, 0 at the left end and 1 at the right.
    pub fn track_fraction(track: [f32; 4], at_x: f32) -> f32 {
        if track[2] <= 0.0 {
            return 0.0;
        }
        ((at_x - track[0]) / track[2]).clamp(0.0, 1.0)
    }

    /// The size a track fraction means, in 5 % steps so the number is easy to read and repeat.
    pub fn scale_at(fraction: f32) -> f32 {
        let raw = MIN_SCALE + fraction.clamp(0.0, 1.0) * (MAX_SCALE - MIN_SCALE);
        ((raw * 20.0).round() / 20.0).clamp(MIN_SCALE, MAX_SCALE)
    }

    /// The opacity a track fraction means, in 5 % steps.
    pub fn opacity_at(fraction: f32) -> f32 {
        let raw = MIN_OPACITY + fraction.clamp(0.0, 1.0) * (1.0 - MIN_OPACITY);
        ((raw * 20.0).round() / 20.0).clamp(MIN_OPACITY, 1.0)
    }

    /// The inverse: where on the track a size sits, for drawing the handle.
    pub fn scale_fraction(scale: f32) -> f32 {
        ((scale - MIN_SCALE) / (MAX_SCALE - MIN_SCALE)).clamp(0.0, 1.0)
    }

    pub fn opacity_fraction(opacity: f32) -> f32 {
        ((opacity - MIN_OPACITY) / (1.0 - MIN_OPACITY)).clamp(0.0, 1.0)
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        const PHONE: (f32, f32) = (633.0, 292.5);
        const SMALL: (f32, f32) = (427.0, 240.0);

        fn overlaps(a: [f32; 4], b: [f32; 4]) -> bool {
            crate::touch_editor_tools::overlap(a, b)
        }

        #[test]
        fn folded_leaves_only_the_tab_and_the_stage_gets_the_screen() {
            let l = layout(PHONE, false);
            assert_eq!(l.len(), 1);
            assert_eq!(l[0].0, Control::Fold);
            assert_eq!(stage_width(PHONE, false), PHONE.0 - TAB_W);
            assert!(stage_width(PHONE, false) > stage_width(PHONE, true));
        }

        #[test]
        fn open_every_control_fits_the_screen_and_none_overlap() {
            for size in [PHONE, SMALL, (320.0, 240.0)] {
                let l = layout(size, true);
                for (c, r) in &l {
                    assert!(r[0] >= 0.0 && r[1] >= 0.0, "{c:?} {size:?}");
                    assert!(r[0] + r[2] <= size.0 + 0.01, "{c:?} {size:?}");
                    assert!(r[1] + r[3] <= size.1 + 0.01, "{c:?} {size:?}");
                }
                for (i, (ca, a)) in l.iter().enumerate() {
                    for (cb, b) in &l[i + 1..] {
                        assert!(!overlaps(*a, *b), "{ca:?} and {cb:?} overlap on {size:?}");
                    }
                }
            }
        }

        #[test]
        fn every_control_is_there_once_when_open() {
            let l = layout(PHONE, true);
            for c in [
                Control::Fold,
                Control::SizeSlider,
                Control::FadeSlider,
                Control::ToggleShown,
                Control::ToggleSnap,
                Control::NextPreset,
                Control::SavePreset,
                Control::DeletePreset,
                Control::ResetButton,
                Control::ResetAll,
                Control::Cancel,
                Control::Done,
            ] {
                assert_eq!(l.iter().filter(|(x, _)| *x == c).count(), 1, "{c:?}");
            }
        }

        #[test]
        fn controls_are_thumb_sized() {
            for (c, r) in layout(PHONE, true) {
                let min = if c == Control::Fold { r[2] } else { r[3] };
                assert!(min >= 20.0, "{c:?} is {min} units");
            }
        }

        #[test]
        fn a_touch_finds_its_control_and_the_stage_finds_none() {
            let (c, r) = layout(PHONE, true)[1];
            assert_eq!(control_at(PHONE, true, (r[0] + 1.0, r[1] + 1.0)), Some(c));
            assert_eq!(control_at(PHONE, true, (10.0, 10.0)), None);
            assert_eq!(
                control_at(PHONE, false, (PHONE.0 - 5.0, 100.0)),
                Some(Control::Fold)
            );
        }

        #[test]
        fn a_track_reads_zero_to_one_and_holds_past_its_ends() {
            let t = [100.0, 0.0, 80.0, 20.0];
            assert_eq!(track_fraction(t, 100.0), 0.0);
            assert_eq!(track_fraction(t, 140.0), 0.5);
            assert_eq!(track_fraction(t, 180.0), 1.0);
            assert_eq!(track_fraction(t, 0.0), 0.0);
            assert_eq!(track_fraction(t, 999.0), 1.0);
            assert_eq!(track_fraction([0.0, 0.0, 0.0, 1.0], 5.0), 0.0);
        }

        #[test]
        fn sliders_reach_both_limits_and_move_in_five_percent_steps() {
            assert_eq!(scale_at(0.0), MIN_SCALE);
            assert_eq!(scale_at(1.0), MAX_SCALE);
            assert_eq!(opacity_at(0.0), MIN_OPACITY);
            assert_eq!(opacity_at(1.0), 1.0);
            for i in 0..=100 {
                let f = i as f32 / 100.0;
                for v in [scale_at(f), opacity_at(f)] {
                    assert!(((v * 20.0).round() - v * 20.0).abs() < 1e-3, "{v}");
                }
                assert!(scale_at(f) >= MIN_SCALE && scale_at(f) <= MAX_SCALE);
                assert!(opacity_at(f) >= MIN_OPACITY && opacity_at(f) <= 1.0);
            }
        }

        #[test]
        fn the_handle_sits_where_the_value_is() {
            for s in [0.5_f32, 0.8, 1.0, 1.5, 2.0] {
                assert!((scale_at(scale_fraction(s)) - s).abs() < 0.03, "{s}");
            }
            for o in [0.15_f32, 0.5, 1.0] {
                assert!((opacity_at(opacity_fraction(o)) - o).abs() < 0.03, "{o}");
            }
            assert_eq!(scale_fraction(0.0), 0.0);
            assert_eq!(scale_fraction(9.0), 1.0);
        }

        #[test]
        fn the_default_size_and_fade_are_reachable_exactly() {
            assert_eq!(scale_at(scale_fraction(1.0)), 1.0);
            assert_eq!(opacity_at(opacity_fraction(1.0)), 1.0);
        }
    }
}
