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
const SAFE_SIDE: f32 = 0.08;
const SAFE_TOP: f32 = 0.04;
const SAFE_BOTTOM: f32 = 0.07;

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

impl Pad {
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
    pointer: (f32, f32),
    /// Auto-sprint is holding the Run button down now (`touch_sprint`).
    sprint_held: bool,
    /// Touch was used since the app started: the controls draw only then, so a desktop run with
    /// a mouse never shows them.
    pub(super) seen: bool,
}

impl Default for TouchState {
    fn default() -> Self {
        TouchState {
            logic: Touch::new((1.0, 1.0)),
            started: Instant::now(),
            holding: Vec::new(),
            pointer: (0.0, 0.0),
            sprint_held: false,
            seen: false,
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
        let rects = self.touch_rects(size);
        if touch.phase == TouchPhase::Started && !rects.is_empty() {
            // In the world the buttons are hit by rectangle, not by the engine's pointer, so the
            // log says where the finger was against the nearest button: how far left or right,
            // above or below its centre. A test reads the offset straight off these lines.
            let near = rects
                .iter()
                .enumerate()
                .take(PADS.len())
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
                    PADS[i].label,
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
                    if i < PADS.len() {
                        self.touch.holding.push((id, i));
                        self.touch_button(event_loop, PADS[i].button, true);
                    } else if !self.spectator() {
                        // A hotbar slot: the same as pressing its number key. Nothing is held,
                        // so there is nothing to let go of. A spectator's number keys open the
                        // teleport menu instead (`play_keys.rs`), which a tap does not.
                        self.hotbar_presses.push(i - PADS.len());
                    }
                }
                actions
            }
            TouchPhase::Moved => self.touch.logic.moved(id, at, now),
            TouchPhase::Ended | TouchPhase::Cancelled => {
                if let Some(n) = self.touch.holding.iter().position(|(f, _)| *f == id) {
                    let (_, i) = self.touch.holding.remove(n);
                    self.touch_button(event_loop, PADS[i].button, false);
                }
                self.touch.logic.up(id, now)
            }
        };
        self.touch.pointer = at;
        self.touch_apply(event_loop, actions);
    }

    /// The window's safe area, in physical pixels: its corner and its size. `(0, 0)` and the
    /// window's size on a desktop, the notch and corner insets on a phone.
    fn touch_safe_area(&self) -> ((f32, f32), (f32, f32)) {
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
        let actions = self.touch.logic.tick(now);
        self.touch_apply(event_loop, actions);
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
            .any(|(_, i)| PADS[*i].button == Button::LeftStick);
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
            self.touch_button(event_loop, PADS[i].button, false);
        }
        let actions = self.touch.logic.cancel_all();
        self.touch_apply(event_loop, actions);
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
                self.touch_button(event_loop, PADS[i].button, false);
            }
            let actions = self.touch.logic.set_mode(mode);
            self.touch_apply(event_loop, actions);
        }
    }

    fn touch_rects(&self, size: (f32, f32)) -> Vec<Rect> {
        if self.touch.logic.mode() != Mode::Playing || !self.touch_controls_visible() {
            return Vec::new();
        }
        let margin = self.settings.imc.safe_margin_scale();
        // iMC Settings' Button shift: where the buttons answer, not where they are drawn.
        let (bx, by) = self.settings.imc.button_shift();
        let mut rects: Vec<Rect> = PADS.iter().map(|p| p.rect(size, margin)).collect();
        // The nine hotbar slots follow the pads: an index of `PADS.len()` or more is a slot.
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

    /// A controller button down or up on the virtual controller.
    fn touch_button(&mut self, event_loop: &dyn EventLoopCtl, button: Button, down: bool) {
        let _ = event_loop;
        self.pad.inject_button(button, down);
    }

    fn touch_apply(&mut self, event_loop: &dyn EventLoopCtl, actions: Vec<TouchAction>) {
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
        if !self.touch_controls_visible() {
            return;
        }
        let atlas = &self.gui.atlas;
        let (w, h) = (batch.width, batch.height);
        for (i, p) in PADS.iter().enumerate() {
            // The same fractions as the hit test, on the GUI-unit size instead of pixels.
            let Rect { x, y, w: bw, h: bh } = p.rect((w, h), self.settings.imc.safe_margin_scale());
            let down = self.touch.holding.iter().any(|(_, held)| *held == i);
            let fill = if down { 0x90FF_FFFF } else { 0x5000_0000 };
            batch.fill(atlas, x, y, bw, bh, fill);
            let tw = HudBatch::text_width(atlas, p.label);
            batch.text(
                atlas,
                p.label,
                x + (bw - tw) / 2.0,
                y + (bh - 8.0) / 2.0,
                0xFFFF_FFFF,
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
