//! Cursor mode: the finger is a trackpad and a real pointer moves on the screen.
//!
//! Plain touch puts the pointer under the finger, so the finger covers what it aims at and a
//! small slot in a big inventory is hard to hit. Here the finger moves the pointer by how far it
//! travels, as a laptop's trackpad does: the pointer stays where it was when a finger lands,
//! the thumb can rest anywhere, and the pointer is drawn so the player sees exactly what a tap
//! will press.
//!
//! - **Drag** one finger: the pointer moves by the finger's travel times [`Cursor::speed`].
//! - **Tap** (short, little travel): a left click where the pointer is.
//! - **Hold still** a moment: a right click, held until the finger lifts (the inventory's split).
//! - **Tap, then touch again and drag** quickly: the left button goes down and the pointer drags
//!   with it (a slider's knob, a stack across the inventory), and goes up when the finger lifts.
//! - **Two fingers** moving up or down scroll.
//!
//! Pure logic with no winit types, so it runs under `cargo test`. It speaks the same [`Action`]s
//! as [`crate::touch::Touch`] in a menu, so the game feeds them through the same pointer path.

use crate::touch::{Action, FingerId};
use std::collections::HashMap;

/// How many pixels of finger travel scroll one line (as plain touch does).
const PIXELS_PER_LINE: f32 = 40.0;

/// Where the cursor starts when a screen opens, as fractions of the screen.
const START: (f32, f32) = (0.5, 0.5);

/// The speeds the player can pick: how many pixels the pointer moves for each pixel of finger.
pub const SPEEDS: [f32; 5] = [0.6, 0.8, 1.0, 1.4, 2.0];
pub const SPEED_NAMES: [&str; 5] = ["Slowest", "Slow", "Normal", "Fast", "Fastest"];
/// The index of the normal speed.
pub const NORMAL_SPEED: u8 = 2;

/// Which screens the cursor takes over by itself when "Cursor in inventory" is on. The caller
/// decides what is an inventory; this is what it says back to the game.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Source {
    /// Not in use: plain touch.
    Off,
    /// The player switched to it with the button.
    Switched,
    /// An inventory opened and the setting asked for it. Plain touch returns when it closes.
    Automatic,
}

impl Source {
    pub fn active(self) -> bool {
        self != Source::Off
    }
}

/// Whether the cursor should be in use, from the player's switch and the screen.
///
/// - `switched`: the player pressed the cursor/touch button (it holds across screens).
/// - `auto_inventory`: the setting "Cursor in inventory".
/// - `in_inventory`: the open screen is an inventory-type one (the inventory, chests, crafting,
///   creative).
///
/// The switch always wins when it is on. When it is off, an inventory brings the cursor up only
/// if the setting asks for it, and the cursor goes away again with the screen.
pub fn source_for(switched: bool, auto_inventory: bool, in_inventory: bool) -> Source {
    if switched {
        Source::Switched
    } else if auto_inventory && in_inventory {
        Source::Automatic
    } else {
        Source::Off
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Role {
    /// The only finger down so far: moves the pointer, or clicks.
    Pointer,
    /// A second finger: scrolls.
    Scroll,
}

#[derive(Clone, Copy, Debug)]
struct Finger {
    start: (f32, f32),
    at: (f32, f32),
    since: f64,
    /// Went further than the slop from where it landed.
    moved: bool,
    role: Role,
    /// This touch began soon after a tap, so a drag holds the left button.
    drag_armed: bool,
}

/// The state of cursor mode.
#[derive(Clone, Debug)]
pub struct Cursor {
    screen: (f32, f32),
    /// The pointer, in physical pixels.
    pos: (f32, f32),
    /// Pixels the pointer moves per pixel of finger.
    pub speed: f32,
    /// How far a finger may travel and still be a tap, in pixels.
    pub slop: f32,
    /// A tap is shorter than this many seconds.
    pub tap_secs: f64,
    /// A press held still this long is a right click.
    pub long_press_secs: f64,
    /// A touch that lands within this long of a tap's lift (and not far from it) is a tap-drag.
    pub drag_window_secs: f64,
    fingers: HashMap<FingerId, Finger>,
    /// When the last tap lifted, for the tap-drag.
    last_tap: Option<f64>,
    /// The left button is held by a tap-drag.
    left_down: Option<FingerId>,
    /// The right button is held by a long press.
    right_down: Option<FingerId>,
    last_scroll_y: Option<f32>,
    out: Vec<Action>,
}

impl Cursor {
    pub fn new(screen: (f32, f32)) -> Self {
        Cursor {
            screen,
            pos: (screen.0 * START.0, screen.1 * START.1),
            speed: 1.0,
            slop: 10.0,
            tap_secs: 0.25,
            long_press_secs: 0.45,
            drag_window_secs: 0.30,
            fingers: HashMap::new(),
            last_tap: None,
            left_down: None,
            right_down: None,
            last_scroll_y: None,
            out: Vec::new(),
        }
    }

    /// The screen changed size (a rotation): the pointer keeps its place as a fraction of it.
    pub fn resize(&mut self, screen: (f32, f32)) {
        if screen == self.screen || screen.0 <= 0.0 || screen.1 <= 0.0 {
            return;
        }
        let fraction = (
            self.pos.0 / self.screen.0.max(1.0),
            self.pos.1 / self.screen.1.max(1.0),
        );
        self.screen = screen;
        self.pos = self.clamp((fraction.0 * screen.0, fraction.1 * screen.1));
    }

    /// The pointer, in physical pixels.
    pub fn position(&self) -> (f32, f32) {
        self.pos
    }

    /// Puts the pointer somewhere (a screen opening, the player switching to the cursor).
    pub fn place(&mut self, at: (f32, f32)) {
        self.pos = self.clamp(at);
    }

    /// Puts the pointer back in the middle of the screen.
    pub fn centre(&mut self) {
        self.pos = (self.screen.0 * START.0, self.screen.1 * START.1);
    }

    /// Whether a button is held by the cursor now (a tap-drag or a long press).
    pub fn holding(&self) -> bool {
        self.left_down.is_some() || self.right_down.is_some()
    }

    fn clamp(&self, p: (f32, f32)) -> (f32, f32) {
        (
            p.0.clamp(0.0, (self.screen.0 - 1.0).max(0.0)),
            p.1.clamp(0.0, (self.screen.1 - 1.0).max(0.0)),
        )
    }

    /// A finger landed. The pointer does not move: only travel moves it.
    pub fn down(&mut self, id: FingerId, at: (f32, f32), now: f64) -> Vec<Action> {
        self.out.clear();
        if self.fingers.contains_key(&id) {
            return Vec::new();
        }
        let role = if self.fingers.values().any(|f| f.role == Role::Pointer) {
            self.last_scroll_y = Some(at.1);
            Role::Scroll
        } else {
            Role::Pointer
        };
        let drag_armed = role == Role::Pointer
            && self
                .last_tap
                .is_some_and(|t| now - t <= self.drag_window_secs);
        self.fingers.insert(
            id,
            Finger {
                start: at,
                at,
                since: now,
                moved: false,
                role,
                drag_armed,
            },
        );
        // A second finger in the middle of a click turns it into a scroll, not a click.
        if role == Role::Scroll {
            for f in self.fingers.values_mut() {
                f.moved = true;
            }
        }
        // Park the pointer so the game's hover follows it from the first touch.
        if role == Role::Pointer {
            self.out.push(Action::PointerTo {
                x: self.pos.0,
                y: self.pos.1,
            });
        }
        std::mem::take(&mut self.out)
    }

    /// A finger moved.
    pub fn moved(&mut self, id: FingerId, at: (f32, f32), now: f64) -> Vec<Action> {
        self.out.clear();
        let Some(mut f) = self.fingers.get(&id).copied() else {
            return Vec::new();
        };
        let (dx, dy) = (at.0 - f.at.0, at.1 - f.at.1);
        let from_start = ((at.0 - f.start.0).powi(2) + (at.1 - f.start.1).powi(2)).sqrt();
        f.at = at;
        match f.role {
            Role::Pointer => {
                if !f.moved && from_start > self.slop {
                    f.moved = true;
                    // A tap-drag: the second touch, once it really moves, grabs.
                    if f.drag_armed && self.left_down.is_none() {
                        self.left_down = Some(id);
                        self.out.push(Action::PointerLeft(true));
                    }
                }
                if f.moved {
                    // The travel that crossed the slop is spent on moving the pointer too, so
                    // it does not feel like a dead zone: from the second the finger counts as
                    // moving, every pixel counts.
                    self.pos = self.clamp((self.pos.0 + dx * self.speed, self.pos.1 + dy * self.speed));
                    self.out.push(Action::PointerTo {
                        x: self.pos.0,
                        y: self.pos.1,
                    });
                }
                self.hold(id, &f, now);
            }
            Role::Scroll => {
                if let Some(last) = self.last_scroll_y {
                    let lines = (last - at.1) / PIXELS_PER_LINE;
                    if lines.abs() >= 0.25 {
                        self.out.push(Action::Scroll { lines: -lines });
                        self.last_scroll_y = Some(at.1);
                    }
                }
            }
        }
        self.fingers.insert(id, f);
        std::mem::take(&mut self.out)
    }

    /// Time passing with no finger event: a finger held still becomes a right click.
    pub fn tick(&mut self, now: f64) -> Vec<Action> {
        self.out.clear();
        let ids: Vec<FingerId> = self.fingers.keys().copied().collect();
        for id in ids {
            let f = self.fingers[&id];
            if f.role == Role::Pointer {
                self.hold(id, &f, now);
            }
        }
        std::mem::take(&mut self.out)
    }

    fn hold(&mut self, id: FingerId, f: &Finger, now: f64) {
        if !f.moved
            && !f.drag_armed
            && self.right_down.is_none()
            && self.left_down.is_none()
            && now - f.since >= self.long_press_secs
        {
            self.right_down = Some(id);
            self.out.push(Action::PointerRight(true));
        }
    }

    /// A finger lifted (or the system cancelled it). `cancelled` never clicks.
    pub fn up(&mut self, id: FingerId, now: f64, cancelled: bool) -> Vec<Action> {
        self.out.clear();
        let Some(f) = self.fingers.remove(&id) else {
            return Vec::new();
        };
        match f.role {
            Role::Pointer => {
                if self.right_down == Some(id) {
                    self.right_down = None;
                    self.out.push(Action::PointerRight(false));
                } else if self.left_down == Some(id) {
                    self.left_down = None;
                    self.out.push(Action::PointerLeft(false));
                    self.last_tap = None;
                } else if !cancelled
                    && !f.moved
                    && !self.fingers.values().any(|o| o.role == Role::Scroll)
                    && now - f.since < self.tap_secs
                {
                    // A tap: the press and the release where the pointer is.
                    self.out.push(Action::PointerTo {
                        x: self.pos.0,
                        y: self.pos.1,
                    });
                    self.out.push(Action::PointerLeft(true));
                    self.out.push(Action::PointerLeft(false));
                    self.last_tap = Some(now);
                } else {
                    self.last_tap = None;
                }
            }
            Role::Scroll => {
                if !self.fingers.values().any(|o| o.role == Role::Scroll) {
                    self.last_scroll_y = None;
                }
            }
        }
        // When the last pointer finger leaves, a scroll finger left over scrolls on its own
        // no longer; it simply waits to lift.
        std::mem::take(&mut self.out)
    }

    /// Let go of everything (a screen closed, the app went to the background, the mode changed).
    pub fn cancel_all(&mut self) -> Vec<Action> {
        let mut out = Vec::new();
        if self.right_down.take().is_some() {
            out.push(Action::PointerRight(false));
        }
        if self.left_down.take().is_some() {
            out.push(Action::PointerLeft(false));
        }
        self.fingers.clear();
        self.last_tap = None;
        self.last_scroll_y = None;
        out
    }
}

/// The speed for a stored index, never out of range.
pub fn speed_at(index: u8) -> f32 {
    SPEEDS[usize::from(index).min(SPEEDS.len() - 1)]
}

/// Where the cursor/touch switch sits and how it is hit: a small button, as fractions of the
/// screen, under the Back button's corner so the two never overlap.
pub mod switch {
    pub const WIDTH: f32 = 0.11;
    pub const HEIGHT: f32 = 0.11;
    pub const INSET_X: f32 = 0.02;
    /// Below Back (which starts at 4% and is 13% tall).
    pub const INSET_Y: f32 = 0.19;

    /// The button as `[x, y, w, h]` in pixels on a screen of `size`.
    pub fn rect(size: (f32, f32)) -> [f32; 4] {
        [
            size.0 * INSET_X,
            size.1 * INSET_Y,
            size.0 * WIDTH,
            size.1 * HEIGHT,
        ]
    }

    /// A finger that went down on the switch toggles it when it lifts on it.
    pub fn fires(down_on_it: bool, up_at: (f32, f32), rect: [f32; 4]) -> bool {
        down_on_it
            && up_at.0 >= rect[0]
            && up_at.0 < rect[0] + rect[2]
            && up_at.1 >= rect[1]
            && up_at.1 < rect[1] + rect[3]
    }

    /// The caption: the mode a tap would switch TO.
    pub fn caption(cursor_on: bool) -> &'static str {
        if cursor_on { "Touch" } else { "Cursor" }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SCREEN: (f32, f32) = (2532.0, 1170.0);
    const F: FingerId = 1;
    const G: FingerId = 2;

    fn cursor() -> Cursor {
        Cursor::new(SCREEN)
    }

    fn near(a: (f32, f32), b: (f32, f32)) -> bool {
        (a.0 - b.0).abs() < 0.01 && (a.1 - b.1).abs() < 0.01
    }

    fn pointer_moves(actions: &[Action]) -> Vec<(f32, f32)> {
        actions
            .iter()
            .filter_map(|a| match a {
                Action::PointerTo { x, y } => Some((*x, *y)),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn the_pointer_starts_in_the_middle() {
        assert_eq!(cursor().position(), (1266.0, 585.0));
    }

    #[test]
    fn a_landing_finger_does_not_move_the_pointer() {
        let mut c = cursor();
        let before = c.position();
        let a = c.down(F, (100.0, 100.0), 0.0);
        assert_eq!(c.position(), before);
        // It only tells the game where the pointer is, which is not where the finger is.
        assert_eq!(pointer_moves(&a), vec![before]);
    }

    #[test]
    fn dragging_moves_the_pointer_by_the_travel() {
        let mut c = cursor();
        c.down(F, (100.0, 100.0), 0.0);
        // The first move crosses the slop and is spent in full.
        c.moved(F, (150.0, 100.0), 0.05);
        assert!(near(c.position(), (1316.0, 585.0)), "{:?}", c.position());
        c.moved(F, (150.0, 160.0), 0.10);
        assert!(near(c.position(), (1316.0, 645.0)), "{:?}", c.position());
    }

    #[test]
    fn the_speed_scales_the_travel() {
        let mut c = cursor();
        c.speed = 2.0;
        c.down(F, (0.0, 0.0), 0.0);
        c.moved(F, (50.0, 0.0), 0.05);
        assert!(near(c.position(), (1366.0, 585.0)), "{:?}", c.position());
    }

    #[test]
    fn the_pointer_stays_on_the_screen() {
        let mut c = cursor();
        c.down(F, (0.0, 0.0), 0.0);
        for i in 1..=100 {
            c.moved(F, (i as f32 * 100.0, i as f32 * 100.0), i as f64 * 0.01);
        }
        assert_eq!(c.position(), (SCREEN.0 - 1.0, SCREEN.1 - 1.0));
        for i in 1..=200 {
            c.moved(F, (10000.0 - i as f32 * 100.0, 10000.0 - i as f32 * 100.0), 1.0 + i as f64 * 0.01);
        }
        assert_eq!(c.position(), (0.0, 0.0));
    }

    #[test]
    fn a_tap_clicks_where_the_pointer_is_not_where_the_finger_is() {
        let mut c = cursor();
        c.down(F, (50.0, 50.0), 0.0);
        let a = c.up(F, 0.1, false);
        assert_eq!(
            a,
            vec![
                Action::PointerTo { x: 1266.0, y: 585.0 },
                Action::PointerLeft(true),
                Action::PointerLeft(false),
            ]
        );
    }

    #[test]
    fn a_shaky_thumb_is_still_a_tap_and_does_not_move_the_pointer() {
        let mut c = cursor();
        c.down(F, (100.0, 100.0), 0.0);
        c.moved(F, (104.0, 103.0), 0.05);
        assert_eq!(c.position(), (1266.0, 585.0));
        let a = c.up(F, 0.12, false);
        assert!(a.contains(&Action::PointerLeft(true)));
    }

    #[test]
    fn a_drag_never_clicks_when_it_lifts() {
        let mut c = cursor();
        c.down(F, (100.0, 100.0), 0.0);
        c.moved(F, (300.0, 100.0), 0.05);
        let a = c.up(F, 0.1, false);
        assert!(a.is_empty(), "{a:?}");
    }

    #[test]
    fn a_slow_press_is_not_a_tap() {
        let mut c = cursor();
        c.down(F, (100.0, 100.0), 0.0);
        // Held past the tap time but not yet a long press (the tick has not run).
        let a = c.up(F, 0.3, false);
        assert!(a.is_empty(), "{a:?}");
    }

    #[test]
    fn holding_still_is_a_right_click_held_until_the_finger_lifts() {
        let mut c = cursor();
        c.down(F, (100.0, 100.0), 0.0);
        assert!(c.tick(0.2).is_empty());
        assert_eq!(c.tick(0.5), vec![Action::PointerRight(true)]);
        // Only once.
        assert!(c.tick(0.6).is_empty());
        assert!(c.holding());
        assert_eq!(c.up(F, 0.9, false), vec![Action::PointerRight(false)]);
        assert!(!c.holding());
    }

    #[test]
    fn a_moved_finger_is_never_a_long_press() {
        let mut c = cursor();
        c.down(F, (100.0, 100.0), 0.0);
        c.moved(F, (200.0, 100.0), 0.1);
        assert!(c.tick(1.0).is_empty());
    }

    #[test]
    fn tap_then_drag_holds_the_left_button_until_the_finger_lifts() {
        let mut c = cursor();
        c.down(F, (100.0, 100.0), 0.0);
        c.up(F, 0.08, false);
        // The next touch is soon after the tap.
        c.down(G, (400.0, 400.0), 0.2);
        let a = c.moved(G, (460.0, 400.0), 0.25);
        assert!(a.contains(&Action::PointerLeft(true)), "{a:?}");
        assert!(c.holding());
        let a = c.moved(G, (520.0, 400.0), 0.3);
        assert!(a.contains(&Action::PointerTo { x: 1266.0 + 120.0, y: 585.0 }), "{a:?}");
        assert_eq!(c.up(G, 0.4, false), vec![Action::PointerLeft(false)]);
        assert!(!c.holding());
    }

    #[test]
    fn a_tap_drag_that_never_moves_is_just_a_second_tap() {
        let mut c = cursor();
        c.down(F, (100.0, 100.0), 0.0);
        c.up(F, 0.08, false);
        c.down(G, (100.0, 100.0), 0.2);
        let a = c.up(G, 0.26, false);
        assert!(a.contains(&Action::PointerLeft(true)) && a.contains(&Action::PointerLeft(false)));
    }

    #[test]
    fn a_touch_long_after_a_tap_is_a_plain_drag() {
        let mut c = cursor();
        c.down(F, (100.0, 100.0), 0.0);
        c.up(F, 0.08, false);
        c.down(G, (400.0, 400.0), 1.0);
        let a = c.moved(G, (500.0, 400.0), 1.05);
        assert!(!a.contains(&Action::PointerLeft(true)));
        assert!(!c.holding());
    }

    #[test]
    fn a_held_second_touch_after_a_tap_does_not_become_a_right_click() {
        let mut c = cursor();
        c.down(F, (100.0, 100.0), 0.0);
        c.up(F, 0.08, false);
        c.down(G, (100.0, 100.0), 0.2);
        // Held still: waiting to see if it drags, so no right click.
        assert!(c.tick(1.0).is_empty());
    }

    #[test]
    fn a_second_finger_scrolls_and_the_first_never_clicks() {
        let mut c = cursor();
        c.down(F, (100.0, 100.0), 0.0);
        c.down(G, (300.0, 300.0), 0.02);
        // Dragging up moves the list with the finger, as plain touch does: negative lines.
        let a = c.moved(G, (300.0, 220.0), 0.1);
        assert_eq!(a, vec![Action::Scroll { lines: -2.0 }]);
        // Lifting both: no click from the first finger's short press.
        assert!(c.up(G, 0.15, false).is_empty());
        assert!(c.up(F, 0.16, false).is_empty());
    }

    #[test]
    fn scrolling_back_down_scrolls_the_other_way() {
        let mut c = cursor();
        c.down(F, (100.0, 100.0), 0.0);
        c.down(G, (300.0, 300.0), 0.02);
        let a = c.moved(G, (300.0, 380.0), 0.1);
        assert_eq!(a, vec![Action::Scroll { lines: 2.0 }]);
    }

    #[test]
    fn a_cancelled_touch_never_clicks() {
        let mut c = cursor();
        c.down(F, (100.0, 100.0), 0.0);
        assert!(c.up(F, 0.05, true).is_empty());
    }

    #[test]
    fn a_cancelled_hold_or_drag_lets_go_of_its_button() {
        let mut c = cursor();
        c.down(F, (100.0, 100.0), 0.0);
        c.tick(0.5);
        assert_eq!(c.cancel_all(), vec![Action::PointerRight(false)]);
        assert!(!c.holding());

        let mut c = cursor();
        c.down(F, (0.0, 0.0), 0.0);
        c.up(F, 0.05, false);
        c.down(G, (0.0, 0.0), 0.1);
        c.moved(G, (100.0, 0.0), 0.15);
        assert_eq!(c.cancel_all(), vec![Action::PointerLeft(false)]);
        assert!(!c.holding());
    }

    #[test]
    fn cancel_all_forgets_the_fingers_so_a_stale_lift_does_nothing() {
        let mut c = cursor();
        c.down(F, (0.0, 0.0), 0.0);
        c.cancel_all();
        assert!(c.up(F, 0.1, false).is_empty());
        assert!(c.moved(F, (50.0, 50.0), 0.2).is_empty());
    }

    #[test]
    fn the_same_finger_landing_twice_is_ignored() {
        let mut c = cursor();
        c.down(F, (0.0, 0.0), 0.0);
        assert!(c.down(F, (5.0, 5.0), 0.01).is_empty());
    }

    #[test]
    fn rotating_keeps_the_pointer_in_the_same_place_on_the_screen() {
        let mut c = cursor();
        c.place((633.0, 292.5));
        c.resize((1170.0, 2532.0));
        assert!(near(c.position(), (292.5, 633.0)), "{:?}", c.position());
        c.resize((0.0, 0.0));
        assert!(near(c.position(), (292.5, 633.0)));
    }

    #[test]
    fn the_pointer_can_be_placed_and_is_kept_on_the_screen() {
        let mut c = cursor();
        c.place((-50.0, 99999.0));
        assert_eq!(c.position(), (0.0, SCREEN.1 - 1.0));
        c.centre();
        assert_eq!(c.position(), (1266.0, 585.0));
    }

    #[test]
    fn the_speeds_are_in_order_and_normal_changes_nothing() {
        assert!(SPEEDS.windows(2).all(|w| w[0] < w[1]));
        assert_eq!(SPEEDS.len(), SPEED_NAMES.len());
        assert_eq!(speed_at(NORMAL_SPEED), 1.0);
        assert_eq!(speed_at(200), SPEEDS[SPEEDS.len() - 1]);
    }

    #[test]
    fn the_switch_always_wins_and_the_setting_only_helps_in_an_inventory() {
        assert_eq!(source_for(true, false, false), Source::Switched);
        assert_eq!(source_for(true, true, true), Source::Switched);
        assert_eq!(source_for(false, true, true), Source::Automatic);
        assert_eq!(source_for(false, true, false), Source::Off);
        assert_eq!(source_for(false, false, true), Source::Off);
        assert!(!Source::Off.active());
        assert!(Source::Automatic.active() && Source::Switched.active());
    }

    #[test]
    fn the_switch_does_not_overlap_back_and_stays_on_the_screen() {
        let size = (2532.0, 1170.0);
        let s = switch::rect(size);
        assert!(s[0] >= 0.0 && s[1] >= 0.0 && s[0] + s[2] <= size.0 && s[1] + s[3] <= size.1);
        // Back: x 2%, y 4%, 11% wide, 13% tall (touch_layout::back).
        let b = crate::touch_layout::back::rect(size);
        let apart = s[0] + s[2] <= b[0] || b[0] + b[2] <= s[0] || s[1] + s[3] <= b[1] || b[1] + b[3] <= s[1];
        assert!(apart, "{s:?} overlaps {b:?}");
    }

    #[test]
    fn the_switch_fires_only_when_the_finger_lifts_on_it() {
        let r = switch::rect((2532.0, 1170.0));
        let inside = (r[0] + 5.0, r[1] + 5.0);
        assert!(switch::fires(true, inside, r));
        assert!(!switch::fires(false, inside, r));
        assert!(!switch::fires(true, (0.0, 0.0), r));
    }

    #[test]
    fn the_caption_names_the_mode_a_tap_switches_to() {
        assert_eq!(switch::caption(false), "Cursor");
        assert_eq!(switch::caption(true), "Touch");
    }
}
