//! Touch input for phones, as pure logic: fingers in, game intent out.
//!
//! No winit types, no clock of its own and no game state, so the whole thing runs under
//! `cargo test`. The caller (`horizon-client`'s `game/touch.rs`) feeds it finger events with a
//! monotonic time in seconds, and turns what it returns into the inputs the game already has:
//! a virtual controller stick and buttons, a view turn, or a pointer click for menus.
//!
//! Positions are physical pixels, `y` down, as winit reports them. Sticks follow the controller
//! convention (`gamepad::PadState`): right and up positive.

use std::collections::HashMap;

/// A finger's identity for as long as it is down (winit's `Touch::id`).
pub type FingerId = u64;

/// How the screen is split while playing, as fractions of its width.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Layout {
    /// Fingers that land left of this fraction of the width steer.
    pub move_zone: f32,
    /// Stick travel in pixels for full tilt, as a fraction of the screen's shorter side.
    pub stick_radius: f32,
    /// Below this fraction of full tilt the stick reads as centred.
    pub stick_deadzone: f32,
}
impl Default for Layout {
    fn default() -> Self {
        Layout {
            move_zone: 0.40,
            stick_radius: 0.14,
            stick_deadzone: 0.12,
        }
    }
}

/// Tuning that is a matter of feel, kept apart from the layout so it can become a setting.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Feel {
    /// A finger that moves less than this many pixels is still "a tap or a hold".
    pub slop_px: f32,
    /// A tap is a press shorter than this.
    pub tap_secs: f64,
    /// A press held still this long is a long press.
    pub long_press_secs: f64,
    /// View turn per pixel of drag, in degrees. The caller converts degrees to the engine's
    /// mouse counts with `mouse::motion_for_turn`, so the player's sensitivity and invert
    /// settings apply to touch as they do to a mouse.
    pub look_degrees_per_px: f64,
    /// Two taps this close in time and place make a double tap.
    pub double_tap_secs: f64,
}
impl Default for Feel {
    fn default() -> Self {
        Feel {
            slop_px: 12.0,
            tap_secs: 0.25,
            long_press_secs: 0.40,
            // GUESS, to be tuned on the phone: 0.1 degrees a pixel turns the view about 250
            // degrees across a 2532 pixel wide screen.
            look_degrees_per_px: 0.1,
            double_tap_secs: 0.30,
        }
    }
}

/// What the player is doing, which decides what a finger means.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    /// In the world: steer, look, attack, use.
    Playing,
    /// On any screen with a pointer (title, inventory, pause, chat): one finger is the mouse.
    Menu,
}

/// Something the game should do now.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Action {
    /// Turn the view by this many degrees (`yaw` right positive, `pitch` down positive).
    Look { yaw: f64, pitch: f64 },
    /// The attack mapping goes down or up.
    Attack(bool),
    /// The use mapping goes down or up.
    Use(bool),
    /// Jump went down or up (a double tap on the world; see [`Touch::double_tap_jump`]).
    Jump(bool),
    /// Menu mode: move the pointer here (physical pixels).
    PointerTo { x: f32, y: f32 },
    /// Menu mode: the left button goes down or up.
    PointerLeft(bool),
    /// Menu mode: the right button goes down or up (a long press).
    PointerRight(bool),
    /// Menu mode: scroll by this many lines (positive up), from a two finger drag.
    Scroll { lines: f32 },
}

#[derive(Clone, Copy, Debug)]
struct Finger {
    start: (f32, f32),
    at: (f32, f32),
    since: f64,
    /// Moved past the slop at some point.
    dragged: bool,
    role: Role,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Role {
    /// The steering stick.
    Stick,
    /// Looking, and tapping or holding to attack.
    World,
    /// A virtual button owns this finger (it never reaches the world).
    Button,
    /// Menu mode: the pointer.
    Pointer,
    /// Menu mode: the second finger of a scroll.
    ScrollPair,
}

/// A button drawn on screen. The caller lists them each frame; touch tells which is under a finger.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
}
impl Rect {
    pub fn contains(&self, p: (f32, f32)) -> bool {
        p.0 >= self.x && p.0 < self.x + self.w && p.1 >= self.y && p.1 < self.y + self.h
    }
}

/// The finger state machine.
#[derive(Debug)]
pub struct Touch {
    pub layout: Layout,
    pub feel: Feel,
    mode: Mode,
    screen: (f32, f32),
    fingers: HashMap<FingerId, Finger>,
    stick_origin: Option<(f32, f32)>,
    stick: [f32; 2],
    /// The finger holding attack down (a hold on the world).
    attacking: Option<FingerId>,
    /// The finger whose long press is a held use.
    using: Option<FingerId>,
    /// Menu mode: the long press became a right button.
    right_down: Option<FingerId>,
    last_scroll_y: Option<f32>,
    last_tap: Option<(f64, (f32, f32))>,
    /// Treat a double tap on the world as a jump.
    pub double_tap_jump: bool,
    out: Vec<Action>,
}

impl Touch {
    pub fn new(screen: (f32, f32)) -> Self {
        Touch {
            layout: Layout::default(),
            feel: Feel::default(),
            mode: Mode::Playing,
            screen,
            fingers: HashMap::new(),
            stick_origin: None,
            stick: [0.0; 2],
            attacking: None,
            using: None,
            right_down: None,
            last_scroll_y: None,
            last_tap: None,
            double_tap_jump: false,
            out: Vec::new(),
        }
    }

    /// The window changed size (rotation, split view).
    pub fn resize(&mut self, screen: (f32, f32)) {
        self.screen = screen;
    }

    pub fn mode(&self) -> Mode {
        self.mode
    }

    /// The game opened or closed a screen. Everything held is let go, so a finger that landed in
    /// the world does not keep mining behind an inventory.
    pub fn set_mode(&mut self, mode: Mode) -> Vec<Action> {
        if mode == self.mode {
            return Vec::new();
        }
        self.mode = mode;
        self.cancel_all()
    }

    /// The steering stick, `[x, y]`, right and up positive, deadzone already applied.
    pub fn stick(&self) -> [f32; 2] {
        self.stick
    }

    /// Where the floating stick started, for drawing it.
    pub fn stick_origin(&self) -> Option<(f32, f32)> {
        self.stick_origin
    }

    /// Let go of everything (app backgrounded, a call came in, a screen opened).
    pub fn cancel_all(&mut self) -> Vec<Action> {
        let mut out = Vec::new();
        if self.attacking.take().is_some() {
            out.push(Action::Attack(false));
        }
        if self.using.take().is_some() {
            out.push(Action::Use(false));
        }
        if self.right_down.take().is_some() {
            out.push(Action::PointerRight(false));
        }
        if self.fingers.values().any(|f| f.role == Role::Pointer) {
            out.push(Action::PointerLeft(false));
        }
        self.fingers.clear();
        self.stick_origin = None;
        self.stick = [0.0; 2];
        self.last_scroll_y = None;
        out
    }

    /// A finger landed. `buttons` are the on-screen buttons now drawn; the index of the one under
    /// the finger comes back so the caller can press it.
    pub fn down(
        &mut self,
        id: FingerId,
        at: (f32, f32),
        now: f64,
        buttons: &[Rect],
    ) -> (Option<usize>, Vec<Action>) {
        self.out.clear();
        if self.fingers.contains_key(&id) {
            return (None, Vec::new());
        }
        let mut hit = None;
        let role = if self.mode == Mode::Menu {
            if self.fingers.values().any(|f| f.role == Role::Pointer) {
                self.last_scroll_y = Some(at.1);
                Role::ScrollPair
            } else {
                self.out.push(Action::PointerTo { x: at.0, y: at.1 });
                self.out.push(Action::PointerLeft(true));
                Role::Pointer
            }
        } else if let Some(i) = buttons.iter().position(|r| r.contains(at)) {
            hit = Some(i);
            Role::Button
        } else if at.0 < self.screen.0 * self.layout.move_zone
            && !self.fingers.values().any(|f| f.role == Role::Stick)
        {
            self.stick_origin = Some(at);
            self.stick = [0.0; 2];
            Role::Stick
        } else {
            Role::World
        };
        self.fingers.insert(
            id,
            Finger {
                start: at,
                at,
                since: now,
                dragged: false,
                role,
            },
        );
        (hit, std::mem::take(&mut self.out))
    }

    /// A finger moved.
    pub fn moved(&mut self, id: FingerId, at: (f32, f32), now: f64) -> Vec<Action> {
        self.out.clear();
        let Some(mut f) = self.fingers.get(&id).copied() else {
            return Vec::new();
        };
        let (dx, dy) = (at.0 - f.at.0, at.1 - f.at.1);
        let from_start = ((at.0 - f.start.0).powi(2) + (at.1 - f.start.1).powi(2)).sqrt();
        if from_start > self.feel.slop_px {
            f.dragged = true;
        }
        f.at = at;
        match f.role {
            Role::Stick => {
                if let Some(o) = self.stick_origin {
                    self.stick = stick_vector(
                        (at.0 - o.0, at.1 - o.1),
                        self.layout.stick_radius * self.screen.0.min(self.screen.1),
                        self.layout.stick_deadzone,
                    );
                }
            }
            Role::World => {
                // A drag turns the view. Before the slop is passed it is still a tap, so a hand
                // that shakes a little while mining does not move the aim.
                if f.dragged {
                    self.out.push(Action::Look {
                        yaw: f64::from(dx) * self.feel.look_degrees_per_px,
                        pitch: f64::from(dy) * self.feel.look_degrees_per_px,
                    });
                }
                self.world_hold(id, &f, now);
            }
            Role::Pointer => {
                self.out.push(Action::PointerTo { x: at.0, y: at.1 });
                self.pointer_hold(id, &f, now);
            }
            Role::ScrollPair => {
                if let Some(last) = self.last_scroll_y {
                    let lines = (last - at.1) / 40.0;
                    if lines.abs() >= 0.25 {
                        self.out.push(Action::Scroll { lines: -lines });
                        self.last_scroll_y = Some(at.1);
                    }
                }
            }
            Role::Button => {}
        }
        self.fingers.insert(id, f);
        std::mem::take(&mut self.out)
    }

    /// Time passing with no finger event: a held finger becomes a mine or a long press. Call it
    /// every frame.
    pub fn tick(&mut self, now: f64) -> Vec<Action> {
        self.out.clear();
        let ids: Vec<FingerId> = self.fingers.keys().copied().collect();
        for id in ids {
            let f = self.fingers[&id];
            match f.role {
                Role::World => self.world_hold(id, &f, now),
                Role::Pointer => self.pointer_hold(id, &f, now),
                _ => {}
            }
        }
        std::mem::take(&mut self.out)
    }

    /// A menu finger held still turns its press into a right click (the inventory's split).
    fn pointer_hold(&mut self, id: FingerId, f: &Finger, now: f64) {
        if !f.dragged && self.right_down.is_none() && now - f.since >= self.feel.long_press_secs {
            self.right_down = Some(id);
            self.out.push(Action::PointerLeft(false));
            self.out.push(Action::PointerRight(true));
        }
    }

    /// A held world finger that has not moved starts mining once the tap window has passed.
    fn world_hold(&mut self, id: FingerId, f: &Finger, now: f64) {
        if !f.dragged && self.attacking.is_none() && now - f.since >= self.feel.tap_secs {
            self.attacking = Some(id);
            self.out.push(Action::Attack(true));
        }
    }

    /// A finger lifted (or the system cancelled it).
    pub fn up(&mut self, id: FingerId, now: f64) -> Vec<Action> {
        self.out.clear();
        let Some(f) = self.fingers.remove(&id) else {
            return Vec::new();
        };
        match f.role {
            Role::Stick => {
                self.stick_origin = None;
                self.stick = [0.0; 2];
            }
            Role::World => {
                if self.attacking == Some(id) {
                    self.attacking = None;
                    self.out.push(Action::Attack(false));
                } else if !f.dragged && now - f.since < self.feel.tap_secs {
                    // A quick tap: one swing. The game samples keys once a tick, so the caller
                    // holds the release back a tick (`pad.rs` `late_releases` does this already).
                    self.out.push(Action::Attack(true));
                    self.out.push(Action::Attack(false));
                    if self.double_tap_jump
                        && let Some((t, p)) = self.last_tap
                        && now - t <= self.feel.double_tap_secs
                        && dist(p, f.at) <= self.feel.slop_px * 3.0
                    {
                        self.out.push(Action::Jump(true));
                        self.out.push(Action::Jump(false));
                    }
                    self.last_tap = Some((now, f.at));
                }
            }
            Role::Pointer => {
                if self.right_down == Some(id) {
                    self.right_down = None;
                    self.out.push(Action::PointerRight(false));
                } else {
                    self.out.push(Action::PointerTo {
                        x: f.at.0,
                        y: f.at.1,
                    });
                    self.out.push(Action::PointerLeft(false));
                }
                self.last_scroll_y = None;
            }
            Role::ScrollPair => self.last_scroll_y = None,
            Role::Button => {}
        }
        std::mem::take(&mut self.out)
    }

    /// Whether this finger belongs to an on-screen button (the caller releases the button on
    /// `up`).
    pub fn is_button_finger(&self, id: FingerId) -> bool {
        self.fingers
            .get(&id)
            .is_some_and(|f| f.role == Role::Button)
    }
}

fn dist(a: (f32, f32), b: (f32, f32)) -> f32 {
    ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt()
}

/// A finger's offset from the stick's origin as a stick tilt: radial deadzone, full tilt at
/// `radius` pixels, up positive (screen `y` grows downward, so it is flipped).
pub fn stick_vector(offset: (f32, f32), radius: f32, deadzone: f32) -> [f32; 2] {
    if radius <= 0.0 {
        return [0.0; 2];
    }
    let (x, y) = (offset.0 / radius, -offset.1 / radius);
    let len = (x * x + y * y).sqrt();
    if len < deadzone {
        return [0.0; 2];
    }
    // Rescale so the tilt rises from 0 at the deadzone edge to 1 at full travel, then cap.
    let scaled = ((len - deadzone) / (1.0 - deadzone)).min(1.0);
    [x / len * scaled, y / len * scaled]
}

#[cfg(test)]
mod tests {
    use super::*;

    const SCREEN: (f32, f32) = (2532.0, 1170.0);

    fn touch() -> Touch {
        Touch::new(SCREEN)
    }

    fn near(a: f32, b: f32) -> bool {
        (a - b).abs() < 1.0e-4
    }

    #[test]
    fn stick_has_a_deadzone_and_full_travel() {
        assert_eq!(stick_vector((3.0, 3.0), 100.0, 0.12), [0.0, 0.0]);
        let full = stick_vector((100.0, 0.0), 100.0, 0.12);
        assert!(near(full[0], 1.0) && near(full[1], 0.0));
        // Past full travel is capped, not amplified.
        let over = stick_vector((500.0, 0.0), 100.0, 0.12);
        assert!(near(over[0], 1.0));
        // Screen y grows downward, the stick's up is positive.
        let up = stick_vector((0.0, -100.0), 100.0, 0.12);
        assert!(near(up[1], 1.0));
        let down = stick_vector((0.0, 100.0), 100.0, 0.12);
        assert!(near(down[1], -1.0));
        // A diagonal is not longer than 1.
        let d = stick_vector((100.0, 100.0), 100.0, 0.12);
        assert!((d[0] * d[0] + d[1] * d[1]).sqrt() <= 1.0 + 1.0e-4);
        assert_eq!(stick_vector((10.0, 0.0), 0.0, 0.12), [0.0, 0.0]);
    }

    #[test]
    fn stick_rises_smoothly_from_the_deadzone() {
        let a = stick_vector((15.0, 0.0), 100.0, 0.12);
        let b = stick_vector((40.0, 0.0), 100.0, 0.12);
        assert!(a[0] > 0.0 && a[0] < b[0] && b[0] < 1.0);
    }

    #[test]
    fn a_finger_on_the_left_steers_with_a_floating_origin() {
        let mut t = touch();
        let (hit, _) = t.down(1, (300.0, 800.0), 0.0, &[]);
        assert_eq!(hit, None);
        assert_eq!(t.stick_origin(), Some((300.0, 800.0)));
        assert_eq!(t.stick(), [0.0, 0.0]);
        // Drag right and up from where it landed.
        t.moved(1, (300.0 + 200.0, 800.0 - 200.0), 0.1);
        let s = t.stick();
        assert!(s[0] > 0.5 && s[1] > 0.5, "right and forward, got {s:?}");
        t.up(1, 0.5);
        assert_eq!(t.stick(), [0.0, 0.0]);
        assert_eq!(t.stick_origin(), None);
    }

    #[test]
    fn only_one_finger_steers() {
        let mut t = touch();
        t.down(1, (200.0, 800.0), 0.0, &[]);
        t.down(2, (250.0, 900.0), 0.0, &[]);
        t.moved(2, (900.0, 900.0), 0.1);
        // Finger 2 is a world finger (it looks), it must not move the stick.
        assert_eq!(t.stick(), [0.0, 0.0]);
        assert_eq!(t.stick_origin(), Some((200.0, 800.0)));
    }

    #[test]
    fn a_quick_tap_on_the_world_is_one_swing() {
        let mut t = touch();
        t.down(1, (1800.0, 600.0), 0.0, &[]);
        let out = t.up(1, 0.10);
        assert_eq!(out, vec![Action::Attack(true), Action::Attack(false)]);
    }

    #[test]
    fn holding_still_mines_until_let_go() {
        let mut t = touch();
        t.down(1, (1800.0, 600.0), 0.0, &[]);
        assert!(t.tick(0.10).is_empty(), "still inside the tap window");
        assert_eq!(t.tick(0.30), vec![Action::Attack(true)]);
        assert!(t.tick(0.60).is_empty(), "only starts once");
        assert_eq!(t.up(1, 1.0), vec![Action::Attack(false)]);
    }

    #[test]
    fn a_small_wobble_does_not_turn_the_view_or_stop_a_tap() {
        let mut t = touch();
        t.down(1, (1800.0, 600.0), 0.0, &[]);
        let out = t.moved(1, (1804.0, 603.0), 0.05);
        assert!(out.is_empty(), "inside the slop: {out:?}");
        assert_eq!(
            t.up(1, 0.10),
            vec![Action::Attack(true), Action::Attack(false)]
        );
    }

    #[test]
    fn a_drag_turns_the_view_and_never_attacks() {
        let mut t = touch();
        t.down(1, (1800.0, 600.0), 0.0, &[]);
        let out = t.moved(1, (1850.0, 600.0), 0.05);
        match out.as_slice() {
            [Action::Look { yaw, pitch }] => {
                // 50 px at 0.1 degrees a pixel.
                assert!((yaw - 5.0).abs() < 1.0e-6 && pitch.abs() < 1.0e-9);
            }
            other => panic!("expected one Look, got {other:?}"),
        }
        // Even held long, a finger that dragged is not a mine.
        assert!(t.tick(2.0).is_empty());
        assert!(t.up(1, 2.1).is_empty());
    }

    #[test]
    fn mining_and_steering_at_once() {
        let mut t = touch();
        t.down(1, (300.0, 800.0), 0.0, &[]);
        t.down(2, (1800.0, 600.0), 0.0, &[]);
        t.moved(1, (500.0, 700.0), 0.1);
        assert_eq!(t.tick(0.4), vec![Action::Attack(true)]);
        assert!(t.stick()[0] > 0.0, "still steering while mining");
        assert_eq!(t.up(2, 1.0), vec![Action::Attack(false)]);
        assert!(t.stick()[0] > 0.0);
    }

    #[test]
    fn a_finger_on_a_button_is_the_buttons_and_not_the_worlds() {
        let mut t = touch();
        let jump = Rect {
            x: 2200.0,
            y: 700.0,
            w: 200.0,
            h: 200.0,
        };
        let (hit, out) = t.down(1, (2300.0, 800.0), 0.0, &[jump]);
        assert_eq!(hit, Some(0));
        assert!(out.is_empty());
        assert!(t.is_button_finger(1));
        // Holding it never mines, dragging it never looks.
        assert!(t.tick(2.0).is_empty());
        assert!(t.moved(1, (2000.0, 100.0), 2.1).is_empty());
        assert!(t.up(1, 2.2).is_empty());
        assert!(!t.is_button_finger(1));
    }

    #[test]
    fn a_double_tap_jumps_only_when_asked() {
        let mut t = touch();
        t.down(1, (1800.0, 600.0), 0.0, &[]);
        t.up(1, 0.08);
        t.down(2, (1802.0, 601.0), 0.20, &[]);
        let plain = t.up(2, 0.28);
        assert_eq!(plain, vec![Action::Attack(true), Action::Attack(false)]);

        let mut t = touch();
        t.double_tap_jump = true;
        t.down(1, (1800.0, 600.0), 0.0, &[]);
        t.up(1, 0.08);
        t.down(2, (1802.0, 601.0), 0.20, &[]);
        let jumped = t.up(2, 0.28);
        assert_eq!(
            jumped,
            vec![
                Action::Attack(true),
                Action::Attack(false),
                Action::Jump(true),
                Action::Jump(false)
            ]
        );
        // A tap far away, or much later, is not a double tap.
        let mut t = touch();
        t.double_tap_jump = true;
        t.down(1, (1800.0, 600.0), 0.0, &[]);
        t.up(1, 0.08);
        t.down(2, (1200.0, 300.0), 0.20, &[]);
        assert_eq!(t.up(2, 0.28).len(), 2);
    }

    #[test]
    fn opening_a_screen_lets_go_of_a_mine_and_the_stick() {
        let mut t = touch();
        t.down(1, (300.0, 800.0), 0.0, &[]);
        t.down(2, (1800.0, 600.0), 0.0, &[]);
        t.moved(1, (500.0, 700.0), 0.1);
        t.tick(0.5);
        let out = t.set_mode(Mode::Menu);
        assert_eq!(out, vec![Action::Attack(false)]);
        assert_eq!(t.stick(), [0.0, 0.0]);
        assert_eq!(t.stick_origin(), None);
        // The lifted fingers produce nothing afterwards.
        assert!(t.up(1, 0.6).is_empty());
        assert!(t.up(2, 0.6).is_empty());
        // Same mode again is a no-op.
        assert!(t.set_mode(Mode::Menu).is_empty());
    }

    #[test]
    fn in_a_menu_one_finger_is_the_mouse() {
        let mut t = touch();
        t.set_mode(Mode::Menu);
        let (_, out) = t.down(1, (500.0, 400.0), 0.0, &[]);
        assert_eq!(
            out,
            vec![
                Action::PointerTo { x: 500.0, y: 400.0 },
                Action::PointerLeft(true)
            ]
        );
        assert_eq!(
            t.moved(1, (520.0, 410.0), 0.05),
            vec![Action::PointerTo { x: 520.0, y: 410.0 }]
        );
        assert_eq!(
            t.up(1, 0.1),
            vec![
                Action::PointerTo { x: 520.0, y: 410.0 },
                Action::PointerLeft(false)
            ]
        );
    }

    #[test]
    fn in_a_menu_a_long_press_is_a_right_click() {
        let mut t = touch();
        t.set_mode(Mode::Menu);
        t.down(1, (500.0, 400.0), 0.0, &[]);
        assert!(t.tick(0.2).is_empty());
        assert_eq!(
            t.tick(0.5),
            vec![Action::PointerLeft(false), Action::PointerRight(true)]
        );
        assert!(t.tick(0.9).is_empty(), "only once");
        assert_eq!(t.up(1, 1.0), vec![Action::PointerRight(false)]);
    }

    #[test]
    fn in_a_menu_a_moved_finger_is_never_a_long_press() {
        let mut t = touch();
        t.set_mode(Mode::Menu);
        t.down(1, (500.0, 400.0), 0.0, &[]);
        t.moved(1, (600.0, 400.0), 0.1);
        assert!(t.tick(1.0).is_empty());
    }

    #[test]
    fn a_second_finger_in_a_menu_scrolls() {
        let mut t = touch();
        t.set_mode(Mode::Menu);
        t.down(1, (500.0, 400.0), 0.0, &[]);
        t.down(2, (700.0, 400.0), 0.0, &[]);
        // Dragging the second finger up scrolls the list down (positive lines go up).
        let out = t.moved(2, (700.0, 320.0), 0.1);
        match out.as_slice() {
            [Action::Scroll { lines }] => assert!(*lines < 0.0, "up-drag scrolls down: {lines}"),
            other => panic!("expected a scroll, got {other:?}"),
        }
        // It never moved the pointer or pressed anything.
        assert!(t.up(2, 0.2).is_empty());
    }

    #[test]
    fn a_cancelled_menu_press_releases_the_button() {
        let mut t = touch();
        t.set_mode(Mode::Menu);
        t.down(1, (500.0, 400.0), 0.0, &[]);
        let out = t.cancel_all();
        assert_eq!(out, vec![Action::PointerLeft(false)]);
    }

    #[test]
    fn a_repeated_down_for_the_same_finger_is_ignored() {
        let mut t = touch();
        t.down(1, (1800.0, 600.0), 0.0, &[]);
        let (hit, out) = t.down(1, (300.0, 800.0), 0.1, &[]);
        assert_eq!(hit, None);
        assert!(out.is_empty());
        assert_eq!(t.stick_origin(), None, "did not become a steering finger");
    }

    #[test]
    fn events_for_unknown_fingers_are_harmless() {
        let mut t = touch();
        assert!(t.moved(9, (1.0, 1.0), 0.0).is_empty());
        assert!(t.up(9, 0.0).is_empty());
    }

    #[test]
    fn rotating_changes_where_the_steering_zone_is() {
        let mut t = touch();
        t.resize((1170.0, 2532.0));
        // 0.40 of 1170 is 468: x = 600 is no longer a steering finger.
        t.down(1, (600.0, 2000.0), 0.0, &[]);
        assert_eq!(t.stick_origin(), None);
        t.down(2, (300.0, 2000.0), 0.0, &[]);
        assert_eq!(t.stick_origin(), Some((300.0, 2000.0)));
    }
}
