//! The player's own arrangement of the on-screen buttons, as pure data: no winit, no game state.
//!
//! Each button keeps only what the player changed, as a nudge from where the layout puts it
//! (`game/touch.rs`'s `PADS`): a move in fractions of the screen, a size factor, an opacity and
//! whether it shows. Kept as a nudge and not as a position so that
//!
//! - a layout nobody edited is exactly the layout touch had before it could be edited,
//! - iMC Settings' Screen margin still moves the buttons that follow the safe edges,
//! - a saved layout still fits another phone or a turned screen (fractions, not pixels).
//!
//! The file is `horizon-touch-layout.txt` beside `horizon-imc.txt`: one line per button,
//! `name:dx,dy,scale,opacity,shown`, written only when something differs from the default.

/// How many buttons can be arranged (the nine pads, Back, the six extras, and the menu buttons
/// Cursor and Shift).
pub const COUNT: usize = 18;

/// The menu buttons' places in [`NAMES`]: after the extras, so a file saved before they existed
/// still reads the same.
pub const CURSOR_SLOT: usize = 16;
pub const SHIFT_SLOT: usize = 17;

/// Where the extras start in [`NAMES`]; they follow `touch_extras::Extra::ALL` in order.
pub const EXTRA_FIRST: usize = 10;

/// The buttons by their saved name, in the order they are listed and drawn. New ones go on the
/// end, so a file saved by an older version still reads the same.
pub const NAMES: [&str; COUNT] = [
    "jump", "sneak", "run", "use", "pause", "prev", "next", "drop", "inv", "back", "chat",
    "debug", "shot", "view", "key1", "key2", "cursor", "shift",
];

/// Largest move from the default, as a fraction of the screen's width or height. Enough to put a
/// button anywhere on screen from any corner without letting it be lost off the edge.
pub const MAX_MOVE: f32 = 1.0;
/// Smallest and largest size factor.
pub const MIN_SCALE: f32 = 0.5;
pub const MAX_SCALE: f32 = 2.0;
/// An opacity below this is hard to find and press, so it is not offered.
pub const MIN_OPACITY: f32 = 0.15;

/// One button's arrangement.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Slot {
    /// Move from the default, as fractions of the screen's width and height. Right and down are
    /// positive.
    pub dx: f32,
    pub dy: f32,
    /// Size factor around the button's centre: 1.0 is the default size.
    pub scale: f32,
    /// How opaque it is drawn, 0 to 1. A button that is drawn faintly still answers a touch.
    pub opacity: f32,
    /// Hidden buttons are neither drawn nor pressable.
    pub shown: bool,
}

impl Default for Slot {
    fn default() -> Self {
        Slot {
            dx: 0.0,
            dy: 0.0,
            scale: 1.0,
            opacity: 1.0,
            shown: true,
        }
    }
}

impl Slot {
    /// This slot with every value brought into the range the editor allows. A saved file can hold
    /// anything, including NaN, so each value is checked.
    pub fn clamped(self) -> Slot {
        let fix = |v: f32, lo: f32, hi: f32, fallback: f32| {
            if v.is_finite() {
                v.clamp(lo, hi)
            } else {
                fallback
            }
        };
        Slot {
            dx: fix(self.dx, -MAX_MOVE, MAX_MOVE, 0.0),
            dy: fix(self.dy, -MAX_MOVE, MAX_MOVE, 0.0),
            scale: fix(self.scale, MIN_SCALE, MAX_SCALE, 1.0),
            opacity: fix(self.opacity, MIN_OPACITY, 1.0, 1.0),
            shown: self.shown,
        }
    }

    /// The rectangle `base` (x, y, w, h in pixels) becomes in this arrangement, on a screen of
    /// `size`, kept fully on the screen. The size changes around the centre.
    pub fn place(&self, base: [f32; 4], size: (f32, f32)) -> [f32; 4] {
        let s = self.clamped();
        // Nothing changed: exactly the base, with none of the centre round trip's rounding.
        if s.dx == 0.0 && s.dy == 0.0 && s.scale == 1.0 {
            return base;
        }
        let [x, y, w, h] = base;
        let (nw, nh) = (w * s.scale, h * s.scale);
        let cx = x + w / 2.0 + s.dx * size.0;
        let cy = y + h / 2.0 + s.dy * size.1;
        // A button bigger than the screen cannot fit; the clamp order keeps its top left visible.
        let nx = (cx - nw / 2.0).min(size.0 - nw).max(0.0);
        let ny = (cy - nh / 2.0).min(size.1 - nh).max(0.0);
        [nx, ny, nw, nh]
    }

    /// The nudge that moves a button from where `base` is to `target` (a rectangle in pixels,
    /// usually one the player dragged to), so that `place(base)` gives `target` back.
    pub fn moved_to(&self, base: [f32; 4], target: [f32; 4], size: (f32, f32)) -> Slot {
        let s = self.clamped();
        let (bx, by) = (base[0] + base[2] / 2.0, base[1] + base[3] / 2.0);
        let (tx, ty) = (target[0] + target[2] / 2.0, target[1] + target[3] / 2.0);
        Slot {
            dx: if size.0 > 0.0 {
                (tx - bx) / size.0
            } else {
                0.0
            },
            dy: if size.1 > 0.0 {
                (ty - by) / size.1
            } else {
                0.0
            },
            ..s
        }
        .clamped()
    }

    /// Whether this is the default, which is not written to the file.
    pub fn is_default(&self) -> bool {
        *self == Slot::default()
    }
}

/// The arrangement of every button.
#[derive(Clone, Debug, PartialEq)]
pub struct ControlLayout {
    pub slots: [Slot; COUNT],
}

impl Default for ControlLayout {
    fn default() -> Self {
        ControlLayout {
            slots: [Slot::default(); COUNT],
        }
    }
}

impl ControlLayout {
    /// The slot of the button at `index` into [`NAMES`]; the default for an index past the end.
    pub fn slot(&self, index: usize) -> Slot {
        self.slots.get(index).copied().unwrap_or_default().clamped()
    }

    pub fn is_default(&self) -> bool {
        self.slots.iter().all(Slot::is_default)
    }

    /// Back to the default arrangement.
    pub fn reset(&mut self) {
        *self = ControlLayout::default();
    }

    /// One button back to its default.
    pub fn reset_slot(&mut self, index: usize) {
        if let Some(s) = self.slots.get_mut(index) {
            *s = Slot::default();
        }
    }

    /// Reads the file's text. Unknown names, malformed lines and out of range numbers are
    /// ignored or brought into range, so a file edited by hand or from another version cannot
    /// break touch or push a button off the screen.
    pub fn parse(text: &str) -> Self {
        let mut layout = ControlLayout::default();
        for line in text.lines() {
            let Some((name, rest)) = line.split_once(':') else {
                continue;
            };
            let Some(index) = NAMES.iter().position(|n| *n == name.trim()) else {
                continue;
            };
            let parts: Vec<&str> = rest.split(',').map(str::trim).collect();
            if parts.len() != 5 {
                continue;
            }
            let num = |i: usize| parts[i].parse::<f32>().ok();
            let (Some(dx), Some(dy), Some(scale), Some(opacity)) = (num(0), num(1), num(2), num(3))
            else {
                continue;
            };
            let Ok(shown) = parts[4].parse::<bool>() else {
                continue;
            };
            layout.slots[index] = Slot {
                dx,
                dy,
                scale,
                opacity,
                shown,
            }
            .clamped();
        }
        layout
    }

    /// The file's text: only the buttons that differ from the default, so a layout nobody edited
    /// writes nothing at all.
    pub fn serialize(&self) -> String {
        let mut out = String::new();
        for (name, slot) in NAMES.iter().zip(&self.slots) {
            if slot.is_default() {
                continue;
            }
            let s = slot.clamped();
            out.push_str(&format!(
                "{name}:{:.4},{:.4},{:.3},{:.3},{}\n",
                s.dx, s.dy, s.scale, s.opacity, s.shown
            ));
        }
        out
    }
}

/// How the Back button decides what it does and where it sits. Pure, so the rules are tested.
pub mod back {
    /// What a tap on Back does, from what is on screen.
    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    pub enum Effect {
        /// A text box has the keyboard: put it away and stay on the screen.
        CloseKeyboard,
        /// Leave the screen: what Escape does.
        Leave,
    }

    /// The first tap puts the keyboard away, and only the next leaves, so typing a message can be
    /// paused without losing it.
    pub fn effect(keyboard_open: bool) -> Effect {
        if keyboard_open {
            Effect::CloseKeyboard
        } else {
            Effect::Leave
        }
    }

    /// The button's size as fractions of the screen, and its gap from the top left corner.
    pub const WIDTH: f32 = 0.11;
    pub const HEIGHT: f32 = 0.13;
    pub const INSET_X: f32 = 0.02;
    pub const INSET_Y: f32 = 0.04;

    /// Back as `[x, y, w, h]` in pixels on a screen of `size`.
    pub fn rect(size: (f32, f32)) -> [f32; 4] {
        [
            size.0 * INSET_X,
            size.1 * INSET_Y,
            size.0 * WIDTH,
            size.1 * HEIGHT,
        ]
    }

    /// A finger that went down on Back fires it when it lifts on Back too: a brush past the
    /// corner, or a drag that began there and left, closes nothing.
    pub fn fires(down_on_back: bool, up_at: (f32, f32), rect: [f32; 4]) -> bool {
        down_on_back
            && up_at.0 >= rect[0]
            && up_at.0 < rect[0] + rect[2]
            && up_at.1 >= rect[1]
            && up_at.1 < rect[1] + rect[3]
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn the_first_tap_puts_the_keyboard_away_and_the_next_leaves() {
            assert_eq!(effect(true), Effect::CloseKeyboard);
            assert_eq!(effect(false), Effect::Leave);
        }

        #[test]
        fn it_is_a_thumb_sized_target_in_the_corner_on_a_phone() {
            let r = rect((2532.0, 1170.0));
            assert!(r[2] >= 200.0 && r[3] >= 120.0, "{r:?}");
            assert!(r[0] > 0.0 && r[1] > 0.0);
            assert!(r[0] + r[2] < 2532.0 / 4.0 && r[1] + r[3] < 1170.0 / 4.0);
        }

        #[test]
        fn lifting_on_the_button_fires_and_lifting_elsewhere_does_not() {
            let r = rect((1000.0, 500.0));
            let inside = (r[0] + 1.0, r[1] + 1.0);
            assert!(fires(true, inside, r));
            assert!(!fires(true, (900.0, 400.0), r), "dragged away");
            assert!(!fires(false, inside, r), "never went down on it");
            assert!(
                !fires(true, (r[0] + r[2], r[1]), r),
                "the far edge is outside"
            );
        }

        #[test]
        fn it_does_not_cover_the_inventory_it_closes() {
            // The inventory panel is centred; the button stays in the corner outside its
            // middle fifth of the width.
            let r = rect((2532.0, 1170.0));
            assert!(r[0] + r[2] < 2532.0 * 0.4);
        }
    }
}

/// The editor's panel and what its buttons do. Pure, so the geometry and the steps are tested.
pub mod editor {
    use super::{MAX_SCALE, MIN_OPACITY, MIN_SCALE, Slot};

    /// What the panel's buttons do.
    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    pub enum Action {
        SmallerButton,
        BiggerButton,
        FainterButton,
        SolidButton,
        ToggleShown,
        ResetButton,
        ResetAll,
        Cancel,
        Done,
    }

    /// Size and opacity move in steps of this much, so a few taps cover the whole range.
    pub const SCALE_STEP: f32 = 0.1;
    pub const OPACITY_STEP: f32 = 0.1;

    /// The panel's width in GUI units, and the gap around its buttons.
    pub const PANEL_W: f32 = 150.0;
    pub const BUTTON_H: f32 = 24.0;
    pub const GAP: f32 = 4.0;

    /// The panel's buttons in order, each with its place: `(action, x, y, w, h)`. The panel hangs
    /// on the right edge and the stage is everything left of `stage_width`. Two small buttons
    /// share a row where they pair up (size, opacity).
    pub fn panel(size: (f32, f32)) -> Vec<(Action, [f32; 4])> {
        let left = size.0 - PANEL_W + GAP;
        let inner = PANEL_W - 2.0 * GAP;
        let half = (inner - GAP) / 2.0;
        // Below the heading and the name of the selected button, which take two rows.
        let mut y = GAP + 2.0 * (BUTTON_H - 6.0);
        let mut out = Vec::with_capacity(9);
        let mut row = |out: &mut Vec<(Action, [f32; 4])>, pair: &[Action]| {
            if let [only] = pair {
                out.push((*only, [left, y, inner, BUTTON_H]));
            } else {
                for (i, a) in pair.iter().enumerate() {
                    out.push((*a, [left + i as f32 * (half + GAP), y, half, BUTTON_H]));
                }
            }
            y += BUTTON_H + GAP;
        };
        row(&mut out, &[Action::SmallerButton, Action::BiggerButton]);
        row(&mut out, &[Action::FainterButton, Action::SolidButton]);
        row(&mut out, &[Action::ToggleShown]);
        row(&mut out, &[Action::ResetButton]);
        // The last rows sit at the bottom so Done is always where a thumb expects it.
        let bottom = size.1 - GAP - BUTTON_H;
        out.push((Action::Done, [left + half + GAP, bottom, half, BUTTON_H]));
        out.push((Action::Cancel, [left, bottom, half, BUTTON_H]));
        out.push((
            Action::ResetAll,
            [left, bottom - BUTTON_H - GAP, inner, BUTTON_H],
        ));
        out
    }

    /// The stage: the width left of the panel, where the buttons are arranged.
    pub fn stage_width(size: (f32, f32)) -> f32 {
        size.0 - PANEL_W
    }

    /// The panel's button under `at`, if any.
    pub fn action_at(size: (f32, f32), at: (f32, f32)) -> Option<Action> {
        panel(size).into_iter().find_map(|(a, r)| {
            (at.0 >= r[0] && at.0 < r[0] + r[2] && at.1 >= r[1] && at.1 < r[1] + r[3]).then_some(a)
        })
    }

    /// `slot` after a size or opacity step; other actions leave it alone. Values land on the
    /// limits instead of passing them, and steps are rounded so repeated taps do not drift
    /// (0.1 added ten times is not 1.0 in floating point).
    pub fn step(slot: Slot, action: Action) -> Slot {
        let round = |v: f32| (v * 100.0).round() / 100.0;
        let mut s = slot;
        match action {
            Action::SmallerButton => s.scale = round((s.scale - SCALE_STEP).max(MIN_SCALE)),
            Action::BiggerButton => s.scale = round((s.scale + SCALE_STEP).min(MAX_SCALE)),
            Action::FainterButton => s.opacity = round((s.opacity - OPACITY_STEP).max(MIN_OPACITY)),
            Action::SolidButton => s.opacity = round((s.opacity + OPACITY_STEP).min(1.0)),
            Action::ToggleShown => s.shown = !s.shown,
            _ => {}
        }
        s.clamped()
    }

    /// A value as the percentage the panel shows.
    pub fn percent(v: f32) -> String {
        format!("{}%", (v * 100.0).round() as i32)
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        const PHONE: (f32, f32) = (633.0, 292.5);
        const SMALL: (f32, f32) = (427.0, 240.0);

        fn overlap(a: [f32; 4], b: [f32; 4]) -> bool {
            !(a[0] + a[2] <= b[0]
                || b[0] + b[2] <= a[0]
                || a[1] + a[3] <= b[1]
                || b[1] + b[3] <= a[1])
        }

        #[test]
        fn every_button_fits_the_screen_and_none_overlap() {
            for size in [PHONE, SMALL, (320.0, 240.0)] {
                let buttons = panel(size);
                assert_eq!(buttons.len(), 9);
                for (i, (a, r)) in buttons.iter().enumerate() {
                    assert!(r[0] >= 0.0 && r[1] >= 0.0, "{a:?} on {size:?}");
                    assert!(
                        r[0] + r[2] <= size.0 && r[1] + r[3] <= size.1,
                        "{a:?} on {size:?}"
                    );
                    for (b, o) in &buttons[i + 1..] {
                        assert!(!overlap(*r, *o), "{a:?} overlaps {b:?} on {size:?}");
                    }
                }
            }
        }

        #[test]
        fn the_panel_never_covers_the_stage() {
            for size in [PHONE, SMALL] {
                let stage = stage_width(size);
                assert!(stage > size.0 * 0.5, "the stage is the wide part: {stage}");
                assert!(panel(size).iter().all(|(_, r)| r[0] >= stage));
            }
        }

        #[test]
        fn a_thumb_can_hit_every_button_on_a_phone() {
            // 4 pixels to a GUI unit at the usual scale: 24 units is 96 pixels, about 8 mm.
            for (_, r) in panel(PHONE) {
                assert!(r[3] >= 24.0 && r[2] >= 60.0, "{r:?}");
            }
        }

        #[test]
        fn done_is_bottom_right_and_cancel_beside_it() {
            let buttons = panel(PHONE);
            let find = |a| buttons.iter().find(|(x, _)| *x == a).unwrap().1;
            let (done, cancel) = (find(Action::Done), find(Action::Cancel));
            assert!(done[0] > cancel[0] && done[1] == cancel[1]);
            assert!(done[1] + done[3] <= PHONE.1);
        }

        #[test]
        fn a_tap_finds_the_button_under_it_and_nothing_on_the_stage() {
            let r = panel(PHONE)[0].1;
            assert_eq!(
                action_at(PHONE, (r[0] + 1.0, r[1] + 1.0)),
                Some(Action::SmallerButton)
            );
            assert_eq!(action_at(PHONE, (50.0, 50.0)), None);
        }

        #[test]
        fn size_steps_stop_at_the_limits_without_passing_them() {
            let mut s = Slot::default();
            for _ in 0..40 {
                s = step(s, Action::BiggerButton);
            }
            assert_eq!(s.scale, MAX_SCALE);
            for _ in 0..40 {
                s = step(s, Action::SmallerButton);
            }
            assert_eq!(s.scale, MIN_SCALE);
        }

        #[test]
        fn repeated_steps_do_not_drift_off_round_numbers() {
            let mut s = Slot::default();
            for _ in 0..5 {
                s = step(s, Action::BiggerButton);
            }
            assert_eq!(s.scale, 1.5);
            for _ in 0..5 {
                s = step(s, Action::SmallerButton);
            }
            assert_eq!(s.scale, 1.0);
            assert!(s.is_default());
        }

        #[test]
        fn opacity_cannot_go_below_what_can_be_found() {
            let mut s = Slot::default();
            for _ in 0..30 {
                s = step(s, Action::FainterButton);
            }
            assert_eq!(s.opacity, MIN_OPACITY);
            for _ in 0..30 {
                s = step(s, Action::SolidButton);
            }
            assert_eq!(s.opacity, 1.0);
        }

        #[test]
        fn hiding_toggles_and_other_actions_change_nothing() {
            let s = step(Slot::default(), Action::ToggleShown);
            assert!(!s.shown);
            assert!(step(s, Action::ToggleShown).shown);
            assert_eq!(step(Slot::default(), Action::Done), Slot::default());
            assert_eq!(step(Slot::default(), Action::ResetAll), Slot::default());
        }

        #[test]
        fn percentages_read_as_whole_numbers() {
            assert_eq!(percent(1.0), "100%");
            assert_eq!(percent(0.15), "15%");
            assert_eq!(percent(1.5), "150%");
        }
    }
}

/// The file the layout is saved in, beside `horizon-imc.txt`.
pub const FILE: &str = "horizon-touch-layout.txt";

#[cfg(test)]
mod tests {
    use super::*;

    const SCREEN: (f32, f32) = (2532.0, 1170.0);
    const BASE: [f32; 4] = [2101.0, 830.0, 228.0, 234.0];

    #[test]
    fn nobody_edited_means_the_old_layout_and_an_empty_file() {
        let layout = ControlLayout::default();
        assert!(layout.is_default());
        assert_eq!(layout.serialize(), "");
        assert_eq!(ControlLayout::parse(""), layout);
        for i in 0..COUNT {
            assert_eq!(layout.slot(i).place(BASE, SCREEN), BASE);
        }
    }

    #[test]
    fn the_extras_have_their_places_in_the_order_they_are_listed() {
        use crate::touch_extras::Extra;
        for (i, e) in Extra::ALL.iter().enumerate() {
            assert_eq!(NAMES[EXTRA_FIRST + i], e.name(), "{e:?}");
        }
        assert_eq!(EXTRA_FIRST + Extra::ALL.len() + 2, COUNT);
        assert_eq!(NAMES[CURSOR_SLOT], "cursor");
        assert_eq!(NAMES[SHIFT_SLOT], "shift");
    }

    #[test]
    fn an_older_file_without_the_extras_still_reads() {
        let layout = ControlLayout::parse("jump:0.0100,0.0200,1.500,0.800,true\n");
        assert_eq!(layout.slots[0].scale, 1.5);
        assert!(layout.slots[EXTRA_FIRST..].iter().all(Slot::is_default));
        assert!(layout.slots[CURSOR_SLOT].is_default() && layout.slots[SHIFT_SLOT].is_default());
    }

    #[test]
    fn there_is_a_name_for_every_button_and_no_name_twice() {
        assert_eq!(NAMES.len(), COUNT);
        for (i, a) in NAMES.iter().enumerate() {
            assert!(!a.is_empty() && !a.contains([':', ',', '\n']));
            assert!(NAMES[i + 1..].iter().all(|b| a != b), "{a} is listed twice");
        }
    }

    #[test]
    fn a_move_shifts_the_centre_by_a_fraction_of_the_screen() {
        let slot = Slot {
            dx: -0.10,
            dy: -0.20,
            ..Slot::default()
        };
        let [x, y, w, h] = slot.place(BASE, SCREEN);
        assert_eq!((w, h), (BASE[2], BASE[3]));
        assert!((x - (BASE[0] - 253.2)).abs() < 0.01);
        assert!((y - (BASE[1] - 234.0)).abs() < 0.01);
    }

    #[test]
    fn a_size_change_keeps_the_centre() {
        let slot = Slot {
            scale: 1.5,
            ..Slot::default()
        };
        let [x, y, w, h] = slot.place([1000.0, 500.0, 200.0, 100.0], SCREEN);
        assert_eq!((w, h), (300.0, 150.0));
        assert_eq!((x + w / 2.0, y + h / 2.0), (1100.0, 550.0));
    }

    #[test]
    fn a_button_cannot_be_pushed_off_the_screen() {
        for (dx, dy) in [(1.0, 1.0), (-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0)] {
            let slot = Slot {
                dx,
                dy,
                scale: MAX_SCALE,
                ..Slot::default()
            };
            let [x, y, w, h] = slot.place(BASE, SCREEN);
            assert!(x >= 0.0 && y >= 0.0, "{dx},{dy}: starts off screen");
            assert!(
                x + w <= SCREEN.0 + 0.01 && y + h <= SCREEN.1 + 0.01,
                "{dx},{dy}: ends off"
            );
        }
    }

    #[test]
    fn dragging_a_button_and_placing_it_again_agree() {
        // Whatever the finger drags a button to is what is drawn and pressed afterwards.
        let target = [900.0, 300.0, 228.0, 234.0];
        let slot = Slot::default().moved_to(BASE, target, SCREEN);
        let placed = slot.place(BASE, SCREEN);
        for (a, b) in placed.iter().zip(target) {
            assert!((a - b).abs() < 0.05, "{placed:?} vs {target:?}");
        }
    }

    #[test]
    fn dragging_keeps_the_size_opacity_and_visibility() {
        let before = Slot {
            scale: 1.3,
            opacity: 0.6,
            shown: false,
            ..Slot::default()
        };
        let after = before.moved_to(BASE, [100.0, 100.0, 228.0, 234.0], SCREEN);
        assert_eq!((after.scale, after.opacity, after.shown), (1.3, 0.6, false));
    }

    #[test]
    fn it_round_trips_through_the_file() {
        let mut layout = ControlLayout::default();
        layout.slots[0] = Slot {
            dx: -0.0625,
            dy: 0.125,
            scale: 1.25,
            opacity: 0.5,
            shown: true,
        };
        layout.slots[9] = Slot {
            shown: false,
            ..Slot::default()
        };
        let text = layout.serialize();
        assert_eq!(text.lines().count(), 2, "{text}");
        assert_eq!(ControlLayout::parse(&text), layout);
    }

    #[test]
    fn only_the_buttons_that_changed_are_written() {
        let mut layout = ControlLayout::default();
        layout.slots[4].opacity = 0.4;
        let text = layout.serialize();
        assert!(text.starts_with("pause:"), "{text}");
        assert_eq!(text.lines().count(), 1);
    }

    #[test]
    fn a_damaged_file_cannot_break_touch() {
        let text = "jump:nan,inf,1e9,-5,true\n\
                    sneak:0.1,0.1,1.0\n\
                    run:0.1,0.1,1.0,1.0,maybe\n\
                    nothing:0,0,1,1,true\n\
                    no colon here\n\
                    use:5,-5,100,0.0,false\n\
                    \n";
        let layout = ControlLayout::parse(text);
        // jump: NaN and infinity fall back, the rest is brought into range.
        let jump = layout.slots[0];
        assert!(jump.dx.is_finite() && jump.dy.is_finite());
        assert_eq!((jump.scale, jump.opacity), (MAX_SCALE, MIN_OPACITY));
        // Wrong field count or a bad boolean: the line is skipped, the default stays.
        assert_eq!(layout.slots[1], Slot::default());
        assert_eq!(layout.slots[2], Slot::default());
        // Out of range values are brought into range.
        let used = layout.slots[3];
        assert_eq!((used.dx, used.dy), (MAX_MOVE, -MAX_MOVE));
        assert_eq!(
            (used.scale, used.opacity, used.shown),
            (MAX_SCALE, MIN_OPACITY, false)
        );
        // Nothing else was touched.
        assert!(layout.slots[4..].iter().all(Slot::is_default));
    }

    #[test]
    fn a_hidden_button_is_a_saved_change() {
        let mut layout = ControlLayout::default();
        layout.slots[1].shown = false;
        assert!(!layout.is_default());
        assert_eq!(
            ControlLayout::parse(&layout.serialize()).slots[1].shown,
            false
        );
    }

    #[test]
    fn reset_puts_back_one_button_or_all() {
        let mut layout = ControlLayout::default();
        layout.slots[0].scale = 2.0;
        layout.slots[3].dx = 0.2;
        layout.reset_slot(0);
        assert!(layout.slots[0].is_default() && !layout.slots[3].is_default());
        layout.reset();
        assert!(layout.is_default());
        // An index past the end is not an error.
        layout.reset_slot(99);
        assert_eq!(layout.slot(99), Slot::default());
    }

    #[test]
    fn a_zero_sized_screen_does_not_divide_by_zero() {
        let slot = Slot::default().moved_to(BASE, [0.0, 0.0, 1.0, 1.0], (0.0, 0.0));
        assert_eq!((slot.dx, slot.dy), (0.0, 0.0));
        let placed = Slot::default().place(BASE, (0.0, 0.0));
        assert!(placed.iter().all(|v| v.is_finite()));
    }
}
