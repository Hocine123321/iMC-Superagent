//! Touch on a phone: fingers become the inputs the game already has.
//!
//! The finger logic is `horizon_client_input::touch` (pure, unit tested). This file only
//! connects it to the game:
//!
//! - **In a menu** (any screen with a pointer) one finger is the mouse: it sends the same
//!   `CursorMoved` and `MouseInput` events a mouse would, so every widget, slider and inventory
//!   slot works with no per-screen code.
//! - **In the world** the left side steers through the virtual controller (`pad.injected`, the
//!   one `horizon-ctl pad` uses), buttons press controller buttons so the player's rebinds apply,
//!   and a drag turns the view with `look_turn`, as the right stick does.
//!
//! iOS cannot grab the pointer (`Window::set_cursor_grab` is `NotSupported` in winit's iOS
//! backend), so the mouse-look path, which needs a grabbed pointer, never runs there. Touch
//! look goes round it, the way `pad_look` does.
use super::event_loop::EventLoopCtl;
use super::{Game, Screen, input_trace};
use horizon_client::gamepad::Button;
use horizon_client::hud::HudBatch;
use horizon_client_input::touch::{
    Action as TouchAction, FingerId, Mode, Rect, Touch, hotbar_slots, to_surface,
};
use horizon_client_input::touch_extras::Extra;
use horizon_client_input::touch_layout::{EXTRA_FIRST, back};
use std::time::Instant;
use winit::{
    dpi::PhysicalPosition,
    event::{DeviceId, ElementState, MouseButton, Touch as WinitTouch, TouchPhase, WindowEvent},
};

/// `Entity.turn` turns this many degrees for each unit it is given.
const DEGREES_PER_TURN_UNIT: f64 = 0.15;

/// The screen's edges that a phone hides or rounds (the notch, the corners, the home bar), as
/// fractions of the screen: left and right, top, bottom. An iPhone 12 in landscape needs about
/// 5.6% at the sides and 5.1% at the bottom; this leaves some room over that, so the same layout
/// also fits the phones with a larger notch. winit 0.30 does not report the safe area, so this is
/// a constant, to be tuned on the phone.
pub(super) const SAFE_SIDE: f32 = 0.08;
pub(super) const SAFE_TOP: f32 = 0.04;
pub(super) const SAFE_BOTTOM: f32 = 0.07;

/// An on-screen button: where it is, what it shows, and the controller button it presses.
struct Pad {
    /// Which edge it hangs from and how far in (fractions of the safe area), then its size
    /// (fractions of the whole screen).
    at: Anchor,
    label: &'static str,
    button: Button,
}

/// Where a button sits inside the safe area.
#[derive(Clone, Copy)]
enum Anchor {
    /// Distance from the safe area's left or right edge, and from its top or bottom edge.
    TopLeft(f32, f32, f32, f32),
    TopRight(f32, f32, f32, f32),
    BottomRight(f32, f32, f32, f32),
}

/// `PADS`' index into the layout file's buttons (`touch_layout::NAMES`).
const PAD_SLOT: [usize; 9] = [0, 1, 2, 3, 4, 5, 6, 7, 8];

/// What a pad index means: one of the nine that are always there, or an extra that is on.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum PadKind {
    /// An index into `PADS`.
    Fixed(usize),
    /// An extra button, and its number among the extras that are showing (for its default place).
    Extra(Extra, usize),
    /// A button of the menu screens (Cursor or Shift). The editor arranges it; play never hits it
    /// as a world button (`pad_kinds` leaves it out, `editor_kinds` adds it).
    Menu(MenuButton),
}

/// The buttons that only exist on screens with a pointer.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum MenuButton {
    Cursor,
    Shift,
}

impl PadKind {
    /// The button's place in the layout file.
    pub(super) fn slot(self) -> usize {
        match self {
            PadKind::Fixed(i) => PAD_SLOT[i],
            PadKind::Extra(e, _) => {
                EXTRA_FIRST + Extra::ALL.iter().position(|x| *x == e).unwrap_or(0)
            }
            PadKind::Menu(MenuButton::Cursor) => horizon_client_input::touch_layout::CURSOR_SLOT,
            PadKind::Menu(MenuButton::Shift) => horizon_client_input::touch_layout::SHIFT_SLOT,
        }
    }

    pub(super) fn label(self) -> &'static str {
        match self {
            PadKind::Fixed(i) => PADS[i].label,
            PadKind::Extra(e, _) => e.label(),
            PadKind::Menu(MenuButton::Cursor) => "Cursor",
            PadKind::Menu(MenuButton::Shift) => "Shift",
        }
    }

    /// Where the button is before the player's arrangement, as `[x, y, w, h]`. The extras stand
    /// in a column down the left edge under Pause, one under the other.
    pub(super) fn base(self, size: (f32, f32), margin: f32) -> [f32; 4] {
        match self {
            PadKind::Fixed(i) => PADS[i].base(size, margin),
            PadKind::Menu(MenuButton::Cursor) => {
                horizon_client_input::touch_cursor::switch::rect(size)
            }
            PadKind::Menu(MenuButton::Shift) => {
                horizon_client_input::touch_cursor::shift::rect(size)
            }
            PadKind::Extra(_, n) => Pad {
                at: Anchor::TopLeft(0.0, 0.15 + 0.115 * n as f32, 0.07, 0.10),
                label: "",
                button: Button::Start,
            }
            .base(size, margin),
        }
    }
}

/// The controller button pad `i` holds while a finger is on it. The extras press a key once and
/// hold nothing, so they answer `None`.
fn held_button(i: usize) -> Option<Button> {
    PADS.get(i).map(|p| p.button)
}

impl Game<'_> {
    /// The buttons now on offer, in index order: the nine, then the extras that are on and have
    /// a key to press. The hotbar's slots follow, so every place that counts buttons asks here.
    pub(super) fn pad_kinds(&self) -> Vec<PadKind> {
        let mut kinds: Vec<PadKind> = (0..PADS.len()).map(PadKind::Fixed).collect();
        kinds.extend(
            self.settings
                .touch_extras
                .active()
                .enumerate()
                .map(|(n, e)| PadKind::Extra(e, n)),
        );
        kinds
    }
}

impl Game<'_> {
    /// Every button the touch editor arranges: the play buttons, then the two menu buttons.
    pub(super) fn editor_kinds(&self) -> Vec<PadKind> {
        let mut kinds = self.pad_kinds();
        kinds.push(PadKind::Menu(MenuButton::Cursor));
        kinds.push(PadKind::Menu(MenuButton::Shift));
        kinds
    }

    /// Where a menu button stands: its base place moved by the player's arrangement, or `None`
    /// when they hid it. In pixels on a screen of `size`.
    pub(super) fn menu_button_rect(&self, button: MenuButton, size: (f32, f32)) -> Option<[f32; 4]> {
        let kind = PadKind::Menu(button);
        let slot = self.settings.touch_layout.slot(kind.slot());
        if !slot.shown {
            return None;
        }
        Some(slot.place(kind.base(size, 1.0), size))
    }
}

impl Pad {
    /// Where the layout puts this pad before the player's arrangement, as `[x, y, w, h]`.
    fn base(&self, size: (f32, f32), margin: f32) -> [f32; 4] {
        let r = self.rect(size, margin);
        [r.x, r.y, r.w, r.h]
    }

    /// The button as a rectangle in pixels on a screen of `size`. `margin` scales the safe
    /// edges (iMC Settings' Screen margin): 1.0 is the layout's own.
    fn rect(&self, size: (f32, f32), margin: f32) -> Rect {
        let (w, h) = size;
        let (side, top, bottom) = (SAFE_SIDE * margin, SAFE_TOP * margin, SAFE_BOTTOM * margin);
        let (left, right) = (w * side, w * (1.0 - side));
        let (top, bottom) = (h * top, h * (1.0 - bottom));
        let (x, y, bw, bh) = match self.at {
            Anchor::TopLeft(dx, dy, bw, bh) => (left + dx * w, top + dy * h, bw * w, bh * h),
            Anchor::TopRight(dx, dy, bw, bh) => {
                (right - dx * w - bw * w, top + dy * h, bw * w, bh * h)
            }
            Anchor::BottomRight(dx, dy, bw, bh) => (
                right - dx * w - bw * w,
                bottom - dy * h - bh * h,
                bw * w,
                bh * h,
            ),
        };
        Rect { x, y, w: bw, h: bh }
    }
}

/// The playing buttons. The controller buttons are the defaults in `gamepad::ACTIONS`; pressing
/// the button rather than the action means a rebind applies. Start is always pause.
const PADS: &[Pad] = &[
    // Right thumb: jump on the corner, sneak and sprint beside and above it, use above.
    Pad {
        at: Anchor::BottomRight(0.0, 0.02, 0.09, 0.20),
        label: "Jump",
        button: Button::South,
    },
    Pad {
        at: Anchor::BottomRight(0.10, 0.02, 0.08, 0.17),
        label: "Sneak",
        button: Button::RightStick,
    },
    Pad {
        at: Anchor::BottomRight(0.10, 0.21, 0.08, 0.17),
        label: "Run",
        button: Button::LeftStick,
    },
    Pad {
        at: Anchor::BottomRight(0.0, 0.24, 0.09, 0.18),
        label: "Use",
        button: Button::LeftTrigger,
    },
    // The top edge: pause, then the hotbar, then drop and inventory.
    Pad {
        at: Anchor::TopLeft(0.0, 0.0, 0.07, 0.13),
        label: "Pause",
        button: Button::Start,
    },
    Pad {
        at: Anchor::TopLeft(0.22, 0.0, 0.06, 0.13),
        label: "<",
        button: Button::LeftBumper,
    },
    Pad {
        at: Anchor::TopRight(0.22, 0.0, 0.06, 0.13),
        label: ">",
        button: Button::RightBumper,
    },
    Pad {
        at: Anchor::TopRight(0.10, 0.0, 0.08, 0.13),
        label: "Drop",
        button: Button::DPadDown,
    },
    Pad {
        at: Anchor::TopRight(0.0, 0.0, 0.09, 0.13),
        label: "Inv",
        button: Button::North,
    },
];

/// A colour (0xAARRGGBB) with its alpha scaled by `opacity`, 0 to 1.
pub(super) fn faded(colour: u32, opacity: f32) -> u32 {
    let alpha = ((colour >> 24) as f32 * opacity.clamp(0.0, 1.0)).round() as u32;
    (alpha.min(255) << 24) | (colour & 0x00FF_FFFF)
}

/// How far above the hotbar a tap still selects its slot, in GUI units. The icons are 16 units
/// across and a thumb is not; this is room for it without reaching the buttons above.
const HOTBAR_LIFT: f32 = 6.0;

/// Everything touch keeps in the game.
pub(super) struct TouchState {
    logic: Touch,
    started: Instant,
    /// Which on-screen button each finger holds.
    holding: Vec<(FingerId, usize)>,
    /// The last physical position of a menu finger, to send a release at the same place.
    pub(super) pointer: (f32, f32),
    /// Auto-sprint is holding the Run button down now (`touch_sprint`).
    sprint_held: bool,
    /// Bedrock style: what a finger resting on the world is holding, chosen once when the hold
    /// began so it never flips mid-hold.
    world_hold: Option<Button>,
    /// A one-tick pulse waiting to be let go (a Bedrock tap), and the tick it was pressed on.
    pulse: Option<(Button, u8)>,
    /// Touch was used since the app started: the controls draw only then, so a desktop run with
    /// a mouse never shows them.
    pub(super) seen: bool,
    /// The finger that went down on Back, and is not a pointer: it fires when it lifts on Back.
    back_finger: Option<FingerId>,
    /// iMC Settings > Calibrate touch is running: the taps so far. While it is, every touch is
    /// a sample and nothing behind it hears of the finger.
    pub(super) calibrating: Option<Calibrating>,
}

/// A calibration run: the targets are tapped in order, and each tap is kept as the point the
/// window reported against the point the target is at.
#[derive(Default)]
pub(super) struct Calibrating {
    /// `(reported, intended)` in surface pixels, one per target tapped.
    pub(super) samples: Vec<((f32, f32), (f32, f32))>,
    /// The run finished but could not be used: shown until the next tap starts it over.
    pub(super) failed: bool,
}

impl Default for TouchState {
    fn default() -> Self {
        TouchState {
            logic: Touch::new((1.0, 1.0)),
            started: Instant::now(),
            holding: Vec::new(),
            pointer: (0.0, 0.0),
            sprint_held: false,
            world_hold: None,
            pulse: None,
            seen: false,
            back_finger: None,
            calibrating: None,
        }
    }
}

impl Game<'_> {
    /// One finger event from the window. Returns at once for a window with no renderer yet.
    pub(super) fn touch_event(&mut self, event_loop: &dyn EventLoopCtl, touch: &WinitTouch) {
        let Some(size) = self
            .renderer
            .as_ref()
            .map(|r| (r.config.width as f32, r.config.height as f32))
        else {
            return;
        };
        self.touch.seen = true;
        self.last_input = Instant::now();
        self.touch.logic.resize(size);
        // iMC Settings may have changed since the last finger.
        self.settings.imc.apply(&mut self.touch.logic);
        self.touch_follow_mode(event_loop);
        let now = self.touch.started.elapsed().as_secs_f64();
        // winit reports the touch from the window's corner; whether the surface starts there
        // too depends on its size: see `to_surface`.
        let (safe_origin, safe_size) = self.touch_safe_area();
        let raw = (touch.location.x as f32, touch.location.y as f32);
        // Calibrate touch: while it runs, a finger is a sample and nothing else hears of it.
        if self.touch.calibrating.is_some() {
            self.touch_calibration_event(touch.phase, raw, size);
            return;
        }
        // The correction the player fitted from their own taps, before anything reads the touch.
        let raw = self.settings.touch_calibration.apply(raw);
        let moved = to_surface(raw, safe_origin, safe_size, size);
        // iMC Settings' Touch shift: the player's own correction for what is left over.
        let (sx, sy) = self.settings.imc.touch_shift();
        let at = (
            (moved.0 + sx).clamp(0.0, (size.0 - 1.0).max(0.0)),
            (moved.1 + sy).clamp(0.0, (size.1 - 1.0).max(0.0)),
        );
        if touch.phase == TouchPhase::Started {
            // What decides where a finger lands, once per press, so a phone test states the
            // offset in numbers: the raw touch, the safe area, the surface, the result.
            log::info!(
                "touch: raw ({:.0}, {:.0}) safe origin ({:.0}, {:.0}) safe size {:.0}x{:.0} \
                 surface {:.0}x{:.0} window {:?} scale {:.2} -> ({:.0}, {:.0}) shift ({sx}, {sy})",
                raw.0,
                raw.1,
                safe_origin.0,
                safe_origin.1,
                safe_size.0,
                safe_size.1,
                size.0,
                size.1,
                self.window.as_ref().map(|w| w.outer_size()),
                self.window.as_ref().map_or(0.0, |w| w.scale_factor()),
                at.0,
                at.1,
            );
        }
        let id = touch.id;
        if self.touch_back_event(event_loop, id, touch.phase, at, size) {
            return;
        }
        // The Cursor/Touch button, kept from the pointer like Back.
        if self.cursor_switch_event(id, touch.phase, at, size) {
            return;
        }
        // The Shift button of the inventory screens, held while a finger is on it.
        if self.shift_button_event(id, touch.phase, at, size) {
            return;
        }
        // Cursor mode: in a menu the finger moves a drawn pointer instead of being one.
        if self.cursor_event(event_loop, id, touch.phase, at, size, now) {
            return;
        }
        let rects = self.touch_rects(size);
        if touch.phase == TouchPhase::Started && !rects.is_empty() {
            // In the world the buttons are hit by rectangle, not by the engine's pointer, so the
            // log says where the finger was against the nearest button: how far left or right,
            // above or below its centre. A test reads the offset straight off these lines.
            let kinds = self.pad_kinds();
            let near = rects
                .iter()
                .enumerate()
                .take(kinds.len())
                .map(|(i, r)| (i, (at.0 - (r.x + r.w / 2.0), at.1 - (r.y + r.h / 2.0)), r))
                .min_by(|a, b| {
                    let d = |v: (f32, f32)| v.0 * v.0 + v.1 * v.1;
                    d(a.1).total_cmp(&d(b.1))
                });
            if let Some((i, (dx, dy), r)) = near {
                log::info!(
                    "touch button: finger ({:.0}, {:.0}) nearest {} centre offset ({dx:+.0}, {dy:+.0}) \
                     rect {:.0}x{:.0} at ({:.0}, {:.0}) hit {}",
                    at.0,
                    at.1,
                    kinds[i].label(),
                    r.w,
                    r.h,
                    r.x,
                    r.y,
                    r.contains(at),
                );
            }
        }
        let actions = match touch.phase {
            TouchPhase::Started => {
                let (hit, actions) = self.touch.logic.down(id, at, now, &rects);
                if let Some(i) = hit {
                    let kinds = self.pad_kinds();
                    if let Some(PadKind::Extra(extra, _)) = kinds.get(i).copied() {
                        // An extra presses its key once, as a tap on the keyboard would.
                        self.touch_extra_key(event_loop, extra);
                    } else if i < PADS.len() {
                        self.touch.holding.push((id, i));
                        self.touch_button(event_loop, PADS[i].button, true);
                    } else if !self.spectator() {
                        // A hotbar slot: the same as pressing its number key. Nothing is held,
                        // so there is nothing to let go of. A spectator's number keys open the
                        // teleport menu instead (`play_keys.rs`), which a tap does not.
                        self.hotbar_presses.push(i - kinds.len());
                    }
                }
                actions
            }
            TouchPhase::Moved => self.touch.logic.moved(id, at, now),
            TouchPhase::Ended | TouchPhase::Cancelled => {
                if let Some(n) = self.touch.holding.iter().position(|(f, _)| *f == id) {
                    let (_, i) = self.touch.holding.remove(n);
                    if let Some(button) = held_button(i) {
                        self.touch_button(event_loop, button, false);
                    }
                }
                self.touch.logic.up(id, now)
            }
        };
        self.touch.pointer = at;
        self.touch_apply(event_loop, actions);
    }

    /// The window's safe area, in physical pixels: its corner and its size. `(0, 0)` and the
    /// window's size on a desktop, the notch and corner insets on a phone.
    pub(super) fn touch_safe_area(&self) -> ((f32, f32), (f32, f32)) {
        let Some(window) = self.window.as_ref() else {
            return ((0.0, 0.0), (0.0, 0.0));
        };
        let size = window.inner_size();
        let origin = window
            .inner_position()
            .map_or((0.0, 0.0), |p| (p.x as f32, p.y as f32));
        (origin, (size.width as f32, size.height as f32))
    }

    /// Each frame, before the controllers are read: time passing (a held finger starts mining),
    /// and the steering stick written into the virtual controller.
    pub(super) fn touch_frame(&mut self, event_loop: &dyn EventLoopCtl) {
        if !self.touch.seen {
            return;
        }
        self.settings.imc.apply(&mut self.touch.logic);
        self.touch_follow_mode(event_loop);
        let now = self.touch.started.elapsed().as_secs_f64();
        self.cursor_frame(event_loop, now);
        let actions = self.touch.logic.tick(now);
        self.touch_apply(event_loop, actions);
        self.touch_pulse_frame(event_loop);
        let stick = if self.touch.logic.mode() == Mode::Playing {
            self.touch.logic.stick()
        } else {
            [0.0; 2]
        };
        self.pad.set_injected_left(stick);
        self.touch_sprint(event_loop);
    }

    /// Forward at the edge of the stick holds the Run button, as a thumb that is steering cannot
    /// hold the on-screen one. The Run pad's own finger keeps its press: this only holds the
    /// button when no pad finger does, and lets go only of what it pressed itself.
    fn touch_sprint(&mut self, event_loop: &dyn EventLoopCtl) {
        let want = self.settings.imc.auto_sprint
            && self.touch.logic.mode() == Mode::Playing
            && self.touch.logic.sprinting();
        let run_pad_held = self
            .touch
            .holding
            .iter()
            .any(|(_, i)| held_button(*i) == Some(Button::LeftStick));
        // Held by sprint only while no pad finger holds it; checked every frame, so lifting the
        // pad's finger with the thumb still forward hands the press back to sprint.
        let hold = want && !run_pad_held;
        if hold != self.touch.sprint_held {
            self.touch.sprint_held = hold;
            // When the pad's finger took the button over, it already holds the press: letting go
            // here would cut it.
            if hold || !run_pad_held {
                self.touch_button(event_loop, Button::LeftStick, hold);
            }
        }
    }

    /// Everything touch holds is let go: the app is going to the background, or a screen that
    /// ends play opened.
    pub(super) fn touch_release_all(&mut self, event_loop: &dyn EventLoopCtl) {
        if !self.touch.seen {
            return;
        }
        let held = std::mem::take(&mut self.touch.holding);
        for (_, i) in held {
            if let Some(button) = held_button(i) {
                self.touch_button(event_loop, button, false);
            }
        }
        let actions = self.touch.logic.cancel_all();
        self.touch_apply(event_loop, actions);
        if let Some((button, _)) = self.touch.pulse.take() {
            self.touch_button(event_loop, button, false);
        }
        if let Some(button) = self.touch.world_hold.take() {
            self.touch_button(event_loop, button, false);
        }
        self.cursor_release_all(event_loop);
        self.pad.set_injected_left([0.0; 2]);
        if std::mem::take(&mut self.touch.sprint_held) {
            self.touch_button(event_loop, Button::LeftStick, false);
        }
    }

    /// The screen decides what a finger means: the world, or a pointer.
    fn touch_follow_mode(&mut self, event_loop: &dyn EventLoopCtl) {
        let mode = if self.pad_in_menu() {
            Mode::Menu
        } else {
            Mode::Playing
        };
        if mode != self.touch.logic.mode() {
            // Buttons held when the screen changed are let go, so a Jump held while the
            // inventory opened does not stay down.
            let held = std::mem::take(&mut self.touch.holding);
            for (_, i) in held {
                if let Some(button) = held_button(i) {
                    self.touch_button(event_loop, button, false);
                }
            }
            let actions = self.touch.logic.set_mode(mode);
            self.touch_apply(event_loop, actions);
        }
    }

    /// Screens that close by a key a phone does not have: the inventory and what opens through it
    /// (chests, furnaces, crafting), creative, chat and the other text screens, signs and books.
    /// The screens with their own Back or Done button are not on this list.
    fn touch_back_wanted(&self) -> bool {
        if !self.touch.seen || !self.settings.imc.controls || self.prompt_open() {
            return false;
        }
        // The title screen: every page but the first one (Add Server, Direct Connection, a
        // world's Edit, Create World, Realms, ...) leaves by Escape, which a phone has no key
        // for, and some of those pages are only reachable with the keyboard covering their own
        // buttons. The options over the title are such a page too.
        if let Some(title) = self.title.as_ref() {
            return self.screen == Screen::Options
                || !matches!(title.mode, horizon_client::title::Mode::Main);
        }
        self.sign_edit.is_some()
            || self.book.is_some()
            || matches!(
                self.screen,
                Screen::Inventory
                    | Screen::Creative
                    | Screen::Chat
                    | Screen::CommandBlock
                    | Screen::BlockEditor
            )
    }

    /// Back's finger: a press on the button is kept from the pointer, and fires on lift. Returns
    /// whether the event was Back's, so the caller leaves it alone.
    fn touch_back_event(
        &mut self,
        event_loop: &dyn EventLoopCtl,
        id: FingerId,
        phase: TouchPhase,
        at: (f32, f32),
        size: (f32, f32),
    ) -> bool {
        let rect = back::rect(size);
        let on_button = at.0 >= rect[0]
            && at.0 < rect[0] + rect[2]
            && at.1 >= rect[1]
            && at.1 < rect[1] + rect[3];
        match phase {
            TouchPhase::Started => {
                if self.touch_back_wanted() && on_button && self.touch.back_finger.is_none() {
                    self.touch.back_finger = Some(id);
                    return true;
                }
                // Any other touch on a screen is the player going to a field: the keyboard may
                // come back.
                self.ime_hidden = false;
                false
            }
            TouchPhase::Moved => self.touch.back_finger == Some(id),
            TouchPhase::Ended | TouchPhase::Cancelled => {
                if self.touch.back_finger != Some(id) {
                    return false;
                }
                self.touch.back_finger = None;
                if phase == TouchPhase::Ended && back::fires(true, at, rect) {
                    self.touch_back_fire(event_loop);
                }
                true
            }
        }
    }

    /// The first tap puts the keyboard away; the next leaves, as Escape does.
    fn touch_back_fire(&mut self, event_loop: &dyn EventLoopCtl) {
        let _ = event_loop;
        let keyboard_open = self.ime_allowed && !self.ime_hidden;
        match back::effect(keyboard_open) {
            back::Effect::CloseKeyboard => {
                self.ime_hidden = true;
                self.sync_ime();
            }
            back::Effect::Leave => {
                self.ime_hidden = false;
                if let Err(e) = self.pad_back() {
                    log::warn!("Horizon: touch back: {e}");
                }
            }
        }
    }

    /// Where pad `i` is on a screen of `size`: the layout's own place, then the player's
    /// arrangement. The hit test and the drawing both come here, so they cannot disagree.
    /// `None` for a button the player hid.
    fn pad_rect(&self, kind: PadKind, size: (f32, f32)) -> Option<Rect> {
        let slot = self.settings.touch_layout.slot(kind.slot());
        if !slot.shown {
            return None;
        }
        let base = kind.base(size, self.settings.imc.safe_margin_scale());
        let [x, y, w, h] = slot.place(base, size);
        Some(Rect { x, y, w, h })
    }

    /// Presses the key an extra button stands for, once: the player's own binding for Chat, F3,
    /// F2 and View, or the key they picked. It goes in as the control line `key <name> tap`, the
    /// same path a script's key takes, so every screen and rebind treats it as the keyboard's.
    fn touch_extra_key(&mut self, event_loop: &dyn EventLoopCtl, extra: Extra) {
        let name = match extra.binding() {
            Some(binding) => self.settings.keys.get(binding).to_owned(),
            None => self.settings.touch_extras.key_of(extra).to_owned(),
        };
        if !horizon_client_input::touch_extras::valid_key_name(&name) {
            log::info!("touch: {} has no key to press ({name})", extra.label());
            return;
        }
        self.replay_line(&format!("key {name} tap"), event_loop);
    }

    fn touch_rects(&self, size: (f32, f32)) -> Vec<Rect> {
        if self.touch.logic.mode() != Mode::Playing || !self.touch_controls_visible() {
            return Vec::new();
        }
        let margin = self.settings.imc.safe_margin_scale();
        // iMC Settings' Button shift: where the buttons answer, not where they are drawn.
        let (bx, by) = self.settings.imc.button_shift();
        let _ = margin;
        // A hidden button keeps its index, with no area, so nothing else shifts.
        let kinds = self.pad_kinds();
        let mut rects: Vec<Rect> = kinds
            .iter()
            .map(|&kind| {
                self.pad_rect(kind, size).unwrap_or(Rect {
                    x: -1.0,
                    y: -1.0,
                    w: 0.0,
                    h: 0.0,
                })
            })
            .collect();
        // The nine hotbar slots follow the pads: an index of the pads' count or more is a slot.
        if let Some(scale) = self.gui_scale().map(|b| b.scale) {
            rects.extend(hotbar_slots(size, scale, HOTBAR_LIFT));
        }
        for r in &mut rects {
            r.x += bx;
            r.y += by;
        }
        rects
    }

    /// The on-screen buttons show while a world is being played.
    fn touch_controls_visible(&self) -> bool {
        self.touch.seen
            && self.settings.imc.controls
            && self.title.is_none()
            && self.screen == Screen::Playing
    }

    /// The crosshair is on an entity before any block (`pick_entity.rs`).
    fn touch_aims_at_entity(&self) -> bool {
        self.pick_entity_hit().is_some()
    }

    /// The crosshair is on a block within reach.
    fn touch_aims_at_block(&self) -> bool {
        self.pick_unfiltered().is_some()
    }

    /// Lets go of a Bedrock tap's press once the game has had a tick to see it. The pad keeps a
    /// press for a frame at least (`late_releases`), so releasing on the second frame is safe.
    fn touch_pulse_frame(&mut self, event_loop: &dyn EventLoopCtl) {
        if let Some((button, frames)) = self.touch.pulse {
            if frames >= 1 {
                self.touch.pulse = None;
                self.touch_button(event_loop, button, false);
            } else {
                self.touch.pulse = Some((button, frames + 1));
            }
        }
    }

    /// A controller button down or up on the virtual controller.
    fn touch_button(&mut self, event_loop: &dyn EventLoopCtl, button: Button, down: bool) {
        let _ = event_loop;
        self.pad.inject_button(button, down);
    }

    pub(super) fn touch_apply(&mut self, event_loop: &dyn EventLoopCtl, actions: Vec<TouchAction>) {
        for action in actions {
            match action {
                TouchAction::Look { yaw, pitch } => {
                    if self.player.is_some() && !self.pad_in_menu() {
                        self.look_turn(yaw / DEGREES_PER_TURN_UNIT, pitch / DEGREES_PER_TURN_UNIT);
                    }
                }
                TouchAction::Attack(down) => {
                    self.touch_button(event_loop, Button::RightTrigger, down)
                }
                TouchAction::Use(down) => self.touch_button(event_loop, Button::LeftTrigger, down),
                TouchAction::Jump(down) => self.touch_button(event_loop, Button::South, down),
                // Bedrock style. A tap hits an entity under the crosshair and uses anything
                // else (places a block, opens a door, uses the item). The press is let go a
                // frame later (`touch_pulse_frame`), as a tap's release is for a click.
                TouchAction::Tap => {
                    let button = if self.touch_aims_at_entity() {
                        Button::RightTrigger
                    } else {
                        Button::LeftTrigger
                    };
                    self.touch_button(event_loop, button, true);
                    self.touch.pulse = Some((button, 0));
                }
                // A rest on the world breaks what the crosshair is on, or keeps placing when it
                // is on nothing to break. Chosen when the hold begins and kept until it ends.
                TouchAction::Hold(true) => {
                    let button = if self.touch_aims_at_entity() || self.touch_aims_at_block() {
                        Button::RightTrigger
                    } else {
                        Button::LeftTrigger
                    };
                    self.touch.world_hold = Some(button);
                    self.touch_button(event_loop, button, true);
                }
                TouchAction::Hold(false) => {
                    if let Some(button) = self.touch.world_hold.take() {
                        self.touch_button(event_loop, button, false);
                    }
                }
                TouchAction::PointerTo { x, y } => self.touch_pointer_to(event_loop, (x, y)),
                TouchAction::PointerLeft(down) => {
                    self.touch_pointer_button(event_loop, MouseButton::Left, down);
                }
                TouchAction::PointerRight(down) => {
                    self.touch_pointer_button(event_loop, MouseButton::Right, down);
                }
                TouchAction::Scroll { lines } => self.touch_scroll(event_loop, lines),
            }
        }
    }

    /// A pointer event as the window would send it: `physical` is in window pixels.
    fn touch_window_event(&mut self, event_loop: &dyn EventLoopCtl, event: WindowEvent) {
        let Some(id) = self.window.as_ref().map(|w| w.id()) else {
            return;
        };
        self.handle_window_event(event_loop, id, event, input_trace::InputOrigin::User);
    }

    fn touch_pointer_to(&mut self, event_loop: &dyn EventLoopCtl, at: (f32, f32)) {
        self.touch_window_event(
            event_loop,
            WindowEvent::CursorMoved {
                device_id: DeviceId::dummy(),
                position: PhysicalPosition::new(f64::from(at.0), f64::from(at.1)),
            },
        );
    }

    fn touch_pointer_button(
        &mut self,
        event_loop: &dyn EventLoopCtl,
        button: MouseButton,
        down: bool,
    ) {
        self.touch_window_event(
            event_loop,
            WindowEvent::MouseInput {
                device_id: DeviceId::dummy(),
                state: if down {
                    ElementState::Pressed
                } else {
                    ElementState::Released
                },
                button,
            },
        );
    }

    fn touch_scroll(&mut self, event_loop: &dyn EventLoopCtl, lines: f32) {
        self.touch_window_event(
            event_loop,
            WindowEvent::MouseWheel {
                device_id: DeviceId::dummy(),
                delta: winit::event::MouseScrollDelta::LineDelta(0.0, lines),
                phase: TouchPhase::Moved,
            },
        );
    }

    /// The on-screen buttons and the steering stick, over the world. Nothing before the first
    /// touch, so a desktop run never shows them.
    pub(super) fn draw_touch_controls(&self, batch: &mut HudBatch) {
        if self.touch.calibrating.is_some() {
            self.draw_touch_calibration(batch);
            return;
        }
        if self.touch_back_wanted() {
            let [x, y, w, h] = back::rect((batch.width, batch.height));
            let atlas = &self.gui.atlas;
            let down = self.touch.back_finger.is_some();
            batch.fill(atlas, x, y, w, h, if down { 0xA0FF_FFFF } else { 0x7000_0000 });
            let label = if self.ime_allowed && !self.ime_hidden {
                "Done"
            } else {
                "Back"
            };
            let tw = HudBatch::text_width(atlas, label);
            batch.text(atlas, label, x + (w - tw) / 2.0, y + (h - 8.0) / 2.0, 0xFFFF_FFFF, true);
        }
        if self.touch_controls_visible() {
            self.draw_touch_pads(batch);
        }
        // The Cursor/Touch button and the pointer last, so nothing covers them.
        self.draw_touch_cursor(batch);
    }

    /// The on-screen buttons and the steering stick, over the world.
    fn draw_touch_pads(&self, batch: &mut HudBatch) {
        let atlas = &self.gui.atlas;
        let (w, h) = (batch.width, batch.height);
        for (i, kind) in self.pad_kinds().into_iter().enumerate() {
            // The same fractions as the hit test, on the GUI-unit size instead of pixels.
            let Some(Rect { x, y, w: bw, h: bh }) = self.pad_rect(kind, (w, h)) else {
                continue;
            };
            let opacity = self.settings.touch_layout.slot(kind.slot()).opacity;
            let down = self.touch.holding.iter().any(|(_, held)| *held == i);
            let fill = faded(if down { 0x90FF_FFFF } else { 0x5000_0000 }, opacity);
            batch.fill(atlas, x, y, bw, bh, fill);
            let label = kind.label();
            let tw = HudBatch::text_width(atlas, label);
            batch.text(
                atlas,
                label,
                x + (bw - tw) / 2.0,
                y + (bh - 8.0) / 2.0,
                faded(0xFFFF_FFFF, opacity),
                true,
            );
        }
        if let Some((ox, oy)) = self.touch.logic.stick_origin() {
            let s = batch.scale;
            let [sx, sy] = self.touch.logic.stick();
            let r = 22.0;
            batch.fill(atlas, ox / s - r, oy / s - r, r * 2.0, r * 2.0, 0x3000_0000);
            batch.fill(
                atlas,
                ox / s - 8.0 + sx * r,
                oy / s - 8.0 - sy * r,
                16.0,
                16.0,
                0xA0FF_FFFF,
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use horizon_client_input::touch_layout::{COUNT, CURSOR_SLOT, ControlLayout, NAMES, Slot};

    const PHONE: (f32, f32) = (2532.0, 1170.0);

    #[test]
    fn every_pad_has_a_layout_slot_and_they_are_distinct() {
        assert_eq!(PAD_SLOT.len(), PADS.len());
        for (i, slot) in PAD_SLOT.iter().enumerate() {
            assert!(*slot < COUNT, "{} has no slot", PADS[i].label);
            assert!(PAD_SLOT[i + 1..].iter().all(|o| o != slot));
        }
        // Back is the one slot of the first ten that is not a pad; the extras follow it.
        assert_eq!(EXTRA_FIRST, PADS.len() + 1);
        assert_eq!(NAMES[EXTRA_FIRST - 1], "back");
        assert_eq!(COUNT, EXTRA_FIRST + Extra::ALL.len() + 2);
    }

    #[test]
    fn the_extras_have_their_own_slots_and_stay_on_the_screen() {
        for (n, e) in Extra::ALL.iter().enumerate() {
            let kind = PadKind::Extra(*e, n);
            assert!(kind.slot() >= EXTRA_FIRST && kind.slot() < CURSOR_SLOT);
            assert_eq!(NAMES[kind.slot()], e.name());
            let [x, y, w, h] = kind.base(PHONE, 1.0);
            assert!(x >= 0.0 && y >= 0.0 && x + w <= PHONE.0 && y + h <= PHONE.1, "{e:?}");
        }
    }

    #[test]
    fn the_extras_do_not_sit_on_the_fixed_buttons() {
        let fixed: Vec<Rect> = PADS.iter().map(|p| p.rect(PHONE, 1.0)).collect();
        let overlap = |a: &Rect, b: &Rect| {
            a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
        };
        for n in 0..Extra::ALL.len() {
            let [x, y, w, h] = PadKind::Extra(Extra::ALL[n], n).base(PHONE, 1.0);
            let r = Rect { x, y, w, h };
            assert!(!fixed.iter().any(|f| overlap(&r, f)), "extra {n} is on a fixed button");
            for m in 0..n {
                let [x, y, w, h] = PadKind::Extra(Extra::ALL[m], m).base(PHONE, 1.0);
                assert!(!overlap(&r, &Rect { x, y, w, h }), "extras {m} and {n} overlap");
            }
        }
    }

    #[test]
    fn an_extra_holds_no_controller_button() {
        assert_eq!(held_button(PADS.len()), None);
        assert_eq!(held_button(0), Some(Button::South));
    }

    #[test]
    fn an_unedited_layout_leaves_every_pad_where_it_was() {
        let layout = ControlLayout::default();
        for (i, pad) in PADS.iter().enumerate() {
            let base = pad.rect(PHONE, 1.0);
            let placed = layout
                .slot(PAD_SLOT[i])
                .place([base.x, base.y, base.w, base.h], PHONE);
            assert_eq!(placed, [base.x, base.y, base.w, base.h], "{}", pad.label);
        }
    }

    #[test]
    fn the_pads_do_not_overlap_each_other_in_the_default_layout() {
        let rects: Vec<Rect> = PADS.iter().map(|p| p.rect(PHONE, 1.0)).collect();
        for (i, a) in rects.iter().enumerate() {
            for b in &rects[i + 1..] {
                let apart = a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y;
                assert!(apart, "{a:?} overlaps {b:?}");
            }
        }
    }

    #[test]
    fn a_hidden_pad_cannot_be_hit() {
        let hidden = Slot {
            shown: false,
            ..Slot::default()
        };
        assert!(!hidden.shown);
        // The sentinel the hit test uses for a hidden pad has no area, so no point is inside it.
        let none = Rect { x: -1.0, y: -1.0, w: 0.0, h: 0.0 };
        assert!(!none.contains((-1.0, -1.0)) && !none.contains((0.0, 0.0)));
    }

    #[test]
    fn fading_scales_only_the_alpha() {
        assert_eq!(faded(0x80FF_8040, 1.0), 0x80FF_8040);
        assert_eq!(faded(0x80FF_8040, 0.5), 0x40FF_8040);
        assert_eq!(faded(0xFFFF_FFFF, 0.0), 0x00FF_FFFF);
        // Out of range opacity cannot overflow the alpha byte.
        assert_eq!(faded(0xFF00_0000, 7.0), 0xFF00_0000);
    }
}
