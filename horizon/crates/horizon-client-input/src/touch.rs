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
    /// A finger that moves less than this many pixels is still "a tap or a hold". The game sets
    /// it from the screen (`slop_for`) so it is the same distance under the thumb on every phone.
    pub slop_px: f32,
    /// In a menu, how far a finger may wander and still be a tap, in pixels. Set from the screen
    /// (`menu_slop_for`) and scaled by iMC Settings' Menu touch.
    pub menu_slop_px: f32,
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
            menu_slop_px: 12.0,
            tap_secs: 0.25,
            long_press_secs: 0.40,
            // GUESS, to be tuned on the phone: 0.1 degrees a pixel turns the view about 250
            // degrees across a 2532 pixel wide screen.
            look_degrees_per_px: 0.1,
            double_tap_secs: 0.30,
        }
    }
}

/// The slop for a screen: 1% of its shorter side, never under 8 pixels. On the iPhone 12 in
/// landscape (1170 px high) that is 11.7 px, close to the fixed 12 px it replaces; on a screen with
/// more pixels it grows with them, so it stays the same distance under the thumb. A GUESS to
/// tune on the phone.
pub fn menu_slop_for(screen: (f32, f32)) -> f32 {
    slop_for(screen)
}

pub fn slop_for(screen: (f32, f32)) -> f32 {
    (screen.0.min(screen.1) * 0.01).max(8.0)
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
    /// Bedrock style: a quick tap on the world. The game decides what it is from what the
    /// crosshair is on: an entity is hit, anything else is used (a block is placed, a door
    /// opens, an item is used).
    Tap,
    /// Bedrock style: a finger has rested on the world long enough to hold (`true`), or lifted
    /// after holding (`false`). The game breaks while the crosshair is on a block or entity, and
    /// keeps placing while it is on nothing it can break.
    Hold(bool),
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
    /// Menu mode, one finger: what the touch has turned into (`Gesture`).
    gesture: Gesture,
}

/// What a lone menu finger is doing. It starts `Undecided` and nothing is pressed: a finger that
/// lifts still is a tap, one that wanders a little (a shaky thumb) is still a tap, and one that
/// goes past `Feel::menu_slop_px` turns into a drag or a scroll for the rest of that touch.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Gesture {
    /// Not yet known; the pointer follows the finger but the button is not down.
    Undecided,
    /// Mostly sideways: the button went down where the finger landed and the pointer follows it
    /// (a slider's knob, a scrollbar).
    Drag,
    /// Mostly up or down: the list moves with the finger and nothing is pressed.
    Scroll,
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
    /// The thumb is at the forward edge of the stick (`sprinting`).
    sprint: bool,
    /// Treat a double tap on the world as a jump.
    pub double_tap_jump: bool,
    /// How a tap on the world is read (`WorldStyle`).
    pub world_style: WorldStyle,
    out: Vec<Action>,
}

/// Whether a finger that has rested on empty air since `began` should now keep using, given the
/// player's settings and the time `now` (seconds). Off, never; on, once `delay` has passed.
pub fn air_hold_due(enabled: bool, began: f64, now: f64, delay: f64) -> bool {
    enabled && now - began >= delay
}

/// What a quick tap on the world means.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum WorldStyle {
    /// A tap is one swing; placing is the Use button (how touch worked first).
    #[default]
    Classic,
    /// As on Bedrock Edition: a tap hits what the crosshair is on if it is an entity and uses
    /// (places, opens) otherwise; holding still breaks.
    Bedrock,
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
            sprint: false,
            double_tap_jump: false,
            world_style: WorldStyle::Classic,
            out: Vec::new(),
        }
    }

    /// The window changed size (rotation, split view).
    pub fn resize(&mut self, screen: (f32, f32)) {
        self.screen = screen;
        self.feel.slop_px = slop_for(screen);
    }

    /// The screen size touch last heard of.
    pub fn screen(&self) -> (f32, f32) {
        self.screen
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

    /// Whether the thumb is pushed to the edge of the stick, forward: that sprints, as double
    /// tapping forward does on a keyboard. A thumb that is steering cannot also hold a Run
    /// button, so this is how a phone player sprints. Backward and sideways pushes do not
    /// (vanilla only sprints forward), and it lets go once the push eases off, with a margin so
    /// a thumb resting at the edge does not flicker.
    pub fn sprinting(&self) -> bool {
        self.sprint
    }

    /// Works out `sprint` from the stick: on at [`SPRINT_AT`], off below [`SPRINT_OFF`].
    fn update_sprint(&mut self) {
        let [x, y] = self.stick;
        let tilt = (x * x + y * y).sqrt();
        let forward = y > 0.0 && y >= x.abs() * 0.5;
        self.sprint = forward
            && if self.sprint {
                tilt >= SPRINT_OFF
            } else {
                tilt >= SPRINT_AT
            };
    }

    /// Where the floating stick started, for drawing it.
    pub fn stick_origin(&self) -> Option<(f32, f32)> {
        self.stick_origin
    }

    /// Let go of everything (app backgrounded, a call came in, a screen opened).
    pub fn cancel_all(&mut self) -> Vec<Action> {
        let mut out = Vec::new();
        if self.attacking.take().is_some() {
            out.push(match self.world_style {
                WorldStyle::Classic => Action::Attack(false),
                WorldStyle::Bedrock => Action::Hold(false),
            });
        }
        if self.using.take().is_some() {
            out.push(Action::Use(false));
        }
        if self.right_down.take().is_some() {
            out.push(Action::PointerRight(false));
        }
        // Only a dragging finger holds the button down; a tap or a scroll never pressed it.
        if self
            .fingers
            .values()
            .any(|f| f.role == Role::Pointer && f.gesture == Gesture::Drag)
        {
            out.push(Action::PointerLeft(false));
        }
        self.fingers.clear();
        self.stick_origin = None;
        self.stick = [0.0; 2];
        self.sprint = false;
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
                // Only the pointer moves: nothing is pressed until the touch says what it is.
                self.out.push(Action::PointerTo { x: at.0, y: at.1 });
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
            self.sprint = false;
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
                gesture: Gesture::Undecided,
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
                    let radius = self.layout.stick_radius * self.screen.0.min(self.screen.1);
                    // The origin trails the thumb: past full travel it is dragged along, so
                    // turning back is one short move instead of a trip back across the stick.
                    let o = follow(o, at, radius * FOLLOW_AFTER);
                    self.stick_origin = Some(o);
                    self.stick =
                        stick_vector((at.0 - o.0, at.1 - o.1), radius, self.layout.stick_deadzone);
                    self.update_sprint();
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
                if f.gesture == Gesture::Undecided {
                    let (tx, ty) = (at.0 - f.start.0, at.1 - f.start.1);
                    if (tx * tx + ty * ty).sqrt() > self.feel.menu_slop_px {
                        if tx.abs() >= ty.abs() {
                            // Sideways: grab what is under the finger's start and follow.
                            f.gesture = Gesture::Drag;
                            self.out.push(Action::PointerTo {
                                x: f.start.0,
                                y: f.start.1,
                            });
                            self.out.push(Action::PointerLeft(true));
                            self.out.push(Action::PointerTo { x: at.0, y: at.1 });
                        } else {
                            // Up or down: the list follows the finger, from where it landed.
                            f.gesture = Gesture::Scroll;
                            self.last_scroll_y = Some(f.start.1);
                            self.scroll_to(at.1);
                        }
                    } else {
                        self.out.push(Action::PointerTo { x: at.0, y: at.1 });
                    }
                } else if f.gesture == Gesture::Drag {
                    self.out.push(Action::PointerTo { x: at.0, y: at.1 });
                } else {
                    self.scroll_to(at.1);
                }
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

    /// Scrolls by the finger's travel since the last scroll, a line for every 40 pixels, with
    /// the list following the finger (dragging up moves the content up, so the view goes down).
    fn scroll_to(&mut self, y: f32) {
        if let Some(last) = self.last_scroll_y {
            let lines = (last - y) / 40.0;
            if lines.abs() >= 0.25 {
                self.out.push(Action::Scroll { lines: -lines });
                self.last_scroll_y = Some(y);
            }
        }
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
        if f.gesture == Gesture::Undecided
            && self.right_down.is_none()
            && now - f.since >= self.feel.long_press_secs
        {
            self.right_down = Some(id);
            self.out.push(Action::PointerRight(true));
        }
    }

    /// A held world finger that has not moved starts mining once the tap window has passed.
    fn world_hold(&mut self, id: FingerId, f: &Finger, now: f64) {
        if !f.dragged && self.attacking.is_none() && now - f.since >= self.feel.tap_secs {
            self.attacking = Some(id);
            self.out.push(match self.world_style {
                WorldStyle::Classic => Action::Attack(true),
                WorldStyle::Bedrock => Action::Hold(true),
            });
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
                self.sprint = false;
            }
            Role::World => {
                if self.attacking == Some(id) {
                    self.attacking = None;
                    self.out.push(match self.world_style {
                        WorldStyle::Classic => Action::Attack(false),
                        WorldStyle::Bedrock => Action::Hold(false),
                    });
                } else if !f.dragged && now - f.since < self.feel.tap_secs {
                    // A quick tap. Classic: one swing. Bedrock: the game picks hit or use from
                    // what the crosshair is on. The game samples keys once a tick, so the caller
                    // holds the release back a tick (`pad.rs` `late_releases` does this already).
                    match self.world_style {
                        WorldStyle::Classic => {
                            self.out.push(Action::Attack(true));
                            self.out.push(Action::Attack(false));
                        }
                        WorldStyle::Bedrock => self.out.push(Action::Tap),
                    }
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
                    match f.gesture {
                        // A tap: the press and the release together, where the finger lifted.
                        Gesture::Undecided => {
                            self.out.push(Action::PointerTo {
                                x: f.at.0,
                                y: f.at.1,
                            });
                            self.out.push(Action::PointerLeft(true));
                            self.out.push(Action::PointerLeft(false));
                        }
                        Gesture::Drag => {
                            self.out.push(Action::PointerTo {
                                x: f.at.0,
                                y: f.at.1,
                            });
                            self.out.push(Action::PointerLeft(false));
                        }
                        // The list was only moved: nothing was pressed.
                        Gesture::Scroll => {}
                    }
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

/// The stick tilt at which forward starts sprinting, and the lower one at which it stops, so a
/// thumb resting at the edge does not make it flicker.
const SPRINT_AT: f32 = 0.95;
const SPRINT_OFF: f32 = 0.80;

/// The nine hotbar slots as touch targets, in physical pixels, for a GUI `scale` (physical pixels
/// per GUI unit) on a surface `screen` pixels wide and high.
///
/// The hotbar is 182 by 22 GUI units, centred, on the bottom edge (`hud_layout::hotbar`:
/// `center - 91`, `h - 22`), and slot `i` starts 3 units in and 20 apart. Each target is the
/// whole 20-unit column and the full height of the bar, grown upward by `lift` GUI units, because
/// a thumb is much larger than the 16-unit icon it aims at.
pub fn hotbar_slots(screen: (f32, f32), scale: f32, lift: f32) -> [Rect; 9] {
    let center = screen.0 / 2.0;
    let top = screen.1 - (22.0 + lift) * scale;
    std::array::from_fn(|i| Rect {
        x: center + (-91.0 + 3.0 + 20.0 * i as f32 - 2.0) * scale,
        y: top,
        w: 20.0 * scale,
        h: (22.0 + lift) * scale,
    })
}

/// How far past full travel the thumb may go before the stick's origin follows, as a multiple of
/// the radius.
const FOLLOW_AFTER: f32 = 1.0;

/// The origin moved toward `at` just enough that `at` is within `reach` of it.
fn follow(origin: (f32, f32), at: (f32, f32), reach: f32) -> (f32, f32) {
    let d = dist(origin, at);
    if reach <= 0.0 || d <= reach {
        return origin;
    }
    let k = (d - reach) / d;
    (
        origin.0 + (at.0 - origin.0) * k,
        origin.1 + (at.1 - origin.1) * k,
    )
}

fn dist(a: (f32, f32), b: (f32, f32)) -> f32 {
    ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt()
}

/// Where a finger is on the drawn surface, from where winit says it touched.
///
/// winit's iOS backend reports a touch relative to the whole window (`locationInView(nil)`).
/// The surface is one of two sizes, and which one decides whether the touch must move:
///
/// - the **safe area** (`Window::inner_size`, which the first surface is made from): its corner
///   is `Window::inner_position`, pushed in by the notch and the rounded corners, so the touch
///   is moved back by that corner. Without this every touch lands that far right and down of the
///   finger;
/// - the **whole window** (what `Resized` reports after the first layout): the surface's corner
///   is the window's corner, so the touch is already right and must not move.
///
/// `safe_origin` and `safe_size` are the safe area's corner and extent, `surface` the size the
/// renderer actually draws at, all in physical pixels. The surface counts as the safe area when
/// it is within a pixel of `safe_size` in both directions and `safe_size` is smaller than the
/// window; otherwise the touch is left alone. A desktop window has `safe_origin == (0, 0)`, so
/// nothing moves there either. The result is clamped to the surface so a finger on the notch edge
/// still lands on the nearest pixel.
pub fn to_surface(
    at: (f32, f32),
    safe_origin: (f32, f32),
    safe_size: (f32, f32),
    surface: (f32, f32),
) -> (f32, f32) {
    let is_safe_area = (surface.0 - safe_size.0).abs() <= 1.0
        && (surface.1 - safe_size.1).abs() <= 1.0
        && (safe_origin.0 > 0.0 || safe_origin.1 > 0.0);
    let origin = if is_safe_area {
        safe_origin
    } else {
        (0.0, 0.0)
    };
    let x = (at.0 - origin.0).clamp(0.0, (surface.0 - 1.0).max(0.0));
    let y = (at.1 - origin.1).clamp(0.0, (surface.1 - 1.0).max(0.0));
    (x, y)
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
    fn holding_on_air_only_counts_when_enabled_and_after_its_delay() {
        assert!(!air_hold_due(false, 0.0, 10.0, 0.8), "off never fires");
        assert!(!air_hold_due(true, 0.0, 0.79, 0.8), "not before the delay");
        assert!(air_hold_due(true, 0.0, 0.80, 0.8));
        assert!(air_hold_due(true, 5.0, 5.9, 0.8), "counted from when the rest began");
    }

    fn bedrock() -> Touch {
        let mut t = touch();
        t.world_style = WorldStyle::Bedrock;
        t
    }

    #[test]
    fn bedrock_a_quick_tap_is_a_tap_for_the_game_to_resolve() {
        let mut t = bedrock();
        t.down(1, (2000.0, 600.0), 0.0, &[]);
        assert_eq!(t.up(1, 0.10), vec![Action::Tap]);
    }

    #[test]
    fn bedrock_holding_still_holds_and_lifting_lets_go() {
        let mut t = bedrock();
        t.down(1, (2000.0, 600.0), 0.0, &[]);
        assert!(t.tick(0.10).is_empty());
        assert_eq!(t.tick(0.30), vec![Action::Hold(true)]);
        assert!(t.tick(0.50).is_empty(), "only once");
        assert_eq!(t.up(1, 0.9), vec![Action::Hold(false)]);
    }

    #[test]
    fn bedrock_a_drag_still_only_looks() {
        let mut t = bedrock();
        t.down(1, (2000.0, 600.0), 0.0, &[]);
        let a = t.moved(1, (2100.0, 600.0), 0.05);
        assert!(a.iter().all(|x| matches!(x, Action::Look { .. })), "{a:?}");
        assert!(t.tick(1.0).is_empty(), "a dragged finger never holds");
        assert!(t.up(1, 1.1).is_empty(), "and never taps");
    }

    #[test]
    fn bedrock_cancelling_lets_go_of_a_hold() {
        let mut t = bedrock();
        t.down(1, (2000.0, 600.0), 0.0, &[]);
        t.tick(0.5);
        assert_eq!(t.cancel_all(), vec![Action::Hold(false)]);
    }

    #[test]
    fn classic_is_unchanged_by_the_new_style() {
        let mut t = touch();
        assert_eq!(t.world_style, WorldStyle::Classic);
        t.down(1, (2000.0, 600.0), 0.0, &[]);
        assert_eq!(t.up(1, 0.10), vec![Action::Attack(true), Action::Attack(false)]);
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

    fn menu() -> Touch {
        let mut t = touch();
        t.set_mode(Mode::Menu);
        t.feel.menu_slop_px = 12.0;
        t
    }

    #[test]
    fn in_a_menu_a_landing_finger_only_moves_the_pointer() {
        let mut t = menu();
        let (_, out) = t.down(1, (500.0, 400.0), 0.0, &[]);
        assert_eq!(out, vec![Action::PointerTo { x: 500.0, y: 400.0 }]);
    }

    #[test]
    fn in_a_menu_a_tap_presses_and_releases_on_lift() {
        let mut t = menu();
        t.down(1, (500.0, 400.0), 0.0, &[]);
        assert_eq!(
            t.up(1, 0.1),
            vec![
                Action::PointerTo { x: 500.0, y: 400.0 },
                Action::PointerLeft(true),
                Action::PointerLeft(false)
            ]
        );
    }

    #[test]
    fn in_a_menu_a_shaky_thumb_is_still_a_tap() {
        let mut t = menu();
        t.down(1, (500.0, 400.0), 0.0, &[]);
        // Wanders 8 px sideways and 6 down: inside the 12 px of slop, nothing but the pointer.
        assert_eq!(
            t.moved(1, (508.0, 406.0), 0.05),
            vec![Action::PointerTo { x: 508.0, y: 406.0 }]
        );
        let out = t.up(1, 0.1);
        assert_eq!(out.last(), Some(&Action::PointerLeft(false)));
        assert!(out.contains(&Action::PointerLeft(true)), "still one click");
    }

    #[test]
    fn in_a_menu_a_sideways_drag_grabs_where_it_started() {
        let mut t = menu();
        t.down(1, (500.0, 400.0), 0.0, &[]);
        // Past the slop, mostly sideways: press at the start, then follow (a slider's knob).
        assert_eq!(
            t.moved(1, (530.0, 404.0), 0.05),
            vec![
                Action::PointerTo { x: 500.0, y: 400.0 },
                Action::PointerLeft(true),
                Action::PointerTo { x: 530.0, y: 404.0 }
            ]
        );
        assert_eq!(
            t.moved(1, (560.0, 410.0), 0.08),
            vec![Action::PointerTo { x: 560.0, y: 410.0 }]
        );
        assert_eq!(
            t.up(1, 0.1),
            vec![
                Action::PointerTo { x: 560.0, y: 410.0 },
                Action::PointerLeft(false)
            ]
        );
    }

    #[test]
    fn in_a_menu_a_vertical_drag_scrolls_and_never_presses() {
        let mut t = menu();
        t.down(1, (500.0, 400.0), 0.0, &[]);
        // Up 80 px: the first move past the slop scrolls the list down, a line per 40 px.
        let out = t.moved(1, (502.0, 320.0), 0.05);
        match out.as_slice() {
            [Action::Scroll { lines }] => assert!((*lines + 2.0).abs() < 1e-3, "{lines}"),
            other => panic!("expected one scroll, got {other:?}"),
        }
        assert!(!out.contains(&Action::PointerLeft(true)));
        // Sideways wobble after it was decided stays a scroll: still nothing pressed.
        let out = t.moved(1, (600.0, 320.0), 0.08);
        assert!(out.is_empty(), "{out:?}");
        // Lifting a scroll presses nothing.
        assert!(t.up(1, 0.2).is_empty());
    }

    #[test]
    fn in_a_menu_scrolling_back_down_scrolls_the_other_way() {
        let mut t = menu();
        t.down(1, (500.0, 400.0), 0.0, &[]);
        t.moved(1, (500.0, 320.0), 0.05);
        match t.moved(1, (500.0, 360.0), 0.1).as_slice() {
            [Action::Scroll { lines }] => assert!(*lines > 0.0, "{lines}"),
            other => panic!("expected a scroll, got {other:?}"),
        }
    }

    #[test]
    fn in_a_menu_a_slider_drag_that_starts_a_little_vertical_still_drags() {
        // The decision is by the larger axis once past the slop, so a mostly sideways move with
        // some drift is a drag.
        let mut t = menu();
        t.down(1, (500.0, 400.0), 0.0, &[]);
        let out = t.moved(1, (540.0, 415.0), 0.05);
        assert!(out.contains(&Action::PointerLeft(true)), "{out:?}");
    }

    #[test]
    fn in_a_menu_a_long_press_is_a_right_click() {
        let mut t = menu();
        t.down(1, (500.0, 400.0), 0.0, &[]);
        assert!(t.tick(0.2).is_empty());
        assert_eq!(t.tick(0.5), vec![Action::PointerRight(true)]);
        assert!(t.tick(0.9).is_empty(), "only once");
        assert_eq!(t.up(1, 1.0), vec![Action::PointerRight(false)]);
    }

    #[test]
    fn in_a_menu_a_moved_finger_is_never_a_long_press() {
        let mut t = menu();
        t.down(1, (500.0, 400.0), 0.0, &[]);
        t.moved(1, (600.0, 400.0), 0.1);
        assert!(t.tick(1.0).is_empty());
    }

    #[test]
    fn the_menu_slop_is_the_players_to_set() {
        let mut t = menu();
        t.feel.menu_slop_px = 60.0;
        t.down(1, (500.0, 400.0), 0.0, &[]);
        // 40 px is inside 60 px of slop: still only the pointer.
        assert_eq!(
            t.moved(1, (540.0, 400.0), 0.05),
            vec![Action::PointerTo { x: 540.0, y: 400.0 }]
        );
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
    fn a_cancelled_menu_drag_releases_the_button() {
        let mut t = menu();
        t.down(1, (500.0, 400.0), 0.0, &[]);
        t.moved(1, (540.0, 400.0), 0.05);
        assert_eq!(t.cancel_all(), vec![Action::PointerLeft(false)]);
    }

    #[test]
    fn a_cancelled_menu_tap_or_scroll_releases_nothing() {
        let mut t = menu();
        t.down(1, (500.0, 400.0), 0.0, &[]);
        assert!(t.cancel_all().is_empty());
        t.down(2, (500.0, 400.0), 0.0, &[]);
        t.moved(2, (500.0, 330.0), 0.05);
        assert!(t.cancel_all().is_empty());
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

    #[test]
    fn a_touch_is_moved_when_the_surface_is_the_safe_area() {
        // iPhone 12, landscape, 3x: the safe area starts 141 px in from the left.
        let origin = (141.0, 0.0);
        let safe = (2250.0, 1107.0);
        // A finger on the surface's own top-left pixel reads (141, 0) in window pixels.
        assert_eq!(to_surface((141.0, 0.0), origin, safe, safe), (0.0, 0.0));
        let mid = to_surface((141.0 + 1125.0, 553.0), origin, safe, safe);
        assert!(near(mid.0, 1125.0) && near(mid.1, 553.0), "{mid:?}");
    }

    #[test]
    fn a_touch_is_not_moved_when_the_surface_is_the_whole_window() {
        // After `Resized` the surface is the full 2532x1170 window: the touch is already right.
        let at = (1266.0, 585.0);
        let got = to_surface(at, (141.0, 0.0), (2250.0, 1107.0), (2532.0, 1170.0));
        assert_eq!(got, at);
    }

    #[test]
    fn a_touch_on_a_desktop_window_does_not_move() {
        let at = (812.5, 300.25);
        let size = (1280.0, 720.0);
        assert_eq!(to_surface(at, (0.0, 0.0), size, size), at);
    }

    #[test]
    fn a_touch_outside_the_surface_lands_on_its_edge() {
        let origin = (141.0, 0.0);
        let safe = (2250.0, 1107.0);
        // On the notch, left of the surface.
        assert_eq!(to_surface((20.0, 500.0), origin, safe, safe), (0.0, 500.0));
        // Past the far edges.
        let far = to_surface((9999.0, 9999.0), origin, safe, safe);
        assert_eq!(far, (2249.0, 1106.0));
        // A zero-sized surface does not panic.
        let zero = (0.0, 0.0);
        assert_eq!(to_surface((5.0, 5.0), zero, zero, zero), (0.0, 0.0));
    }

    #[test]
    fn the_slop_follows_the_screen_with_a_floor() {
        assert!(near(slop_for((2532.0, 1170.0)), 11.7));
        assert!(near(slop_for((2796.0, 1290.0)), 12.9));
        assert!(
            near(slop_for((200.0, 100.0)), 8.0),
            "never smaller than 8 px"
        );
        let mut t = touch();
        t.resize((2796.0, 1290.0));
        assert!(near(t.feel.slop_px, 12.9));
    }

    #[test]
    fn a_thumb_pushed_past_full_travel_drags_the_stick_origin_along() {
        let mut t = touch();
        t.down(1, (300.0, 800.0), 0.0, &[]);
        let radius = t.layout.stick_radius * 1170.0;
        // Out to three radii: the stick is at full tilt and its origin has moved after the thumb.
        t.moved(1, (300.0 + radius * 3.0, 800.0), 0.1);
        let o = t.stick_origin().unwrap();
        assert!(near(o.0, 300.0 + radius * 2.0), "origin {o:?}");
        assert!(near(t.stick()[0], 1.0));
        // Turning back by one radius now reverses the stick, which the fixed origin would not.
        t.moved(1, (300.0 + radius * 2.0, 800.0), 0.2);
        assert!(near(t.stick()[0], 0.0), "{:?}", t.stick());
    }

    #[test]
    fn a_thumb_inside_full_travel_leaves_the_origin_where_it_landed() {
        let mut t = touch();
        t.down(1, (300.0, 800.0), 0.0, &[]);
        let radius = t.layout.stick_radius * 1170.0;
        t.moved(1, (300.0 + radius * 0.7, 800.0), 0.1);
        assert_eq!(t.stick_origin(), Some((300.0, 800.0)));
    }

    #[test]
    fn forward_at_the_edge_sprints_and_it_does_not_flicker() {
        let mut t = touch();
        t.down(1, (300.0, 800.0), 0.0, &[]);
        let radius = t.layout.stick_radius * 1170.0;
        // Forward is up the screen (y down is negative here).
        t.moved(1, (300.0, 800.0 - radius), 0.1);
        assert!(t.sprinting());
        // Easing to 85% keeps it: that is between the two lines.
        t.moved(1, (300.0, 800.0 - radius * 0.88), 0.2);
        assert!(t.sprinting(), "{:?}", t.stick());
        // Easing further lets go.
        t.moved(1, (300.0, 800.0 - radius * 0.6), 0.3);
        assert!(!t.sprinting());
        // And 85% alone, from rest, does not start it.
        t.moved(1, (300.0, 800.0 - radius * 0.88), 0.4);
        assert!(!t.sprinting());
    }

    #[test]
    fn backward_and_sideways_never_sprint() {
        let mut t = touch();
        t.down(1, (300.0, 800.0), 0.0, &[]);
        let radius = t.layout.stick_radius * 1170.0;
        t.moved(1, (300.0, 800.0 + radius), 0.1);
        assert!(!t.sprinting(), "backward");
        t.moved(1, (300.0 + radius, 800.0), 0.2);
        assert!(!t.sprinting(), "sideways");
    }

    #[test]
    fn lifting_the_steering_finger_stops_the_sprint() {
        let mut t = touch();
        t.down(1, (300.0, 800.0), 0.0, &[]);
        let radius = t.layout.stick_radius * 1170.0;
        t.moved(1, (300.0, 800.0 - radius), 0.1);
        assert!(t.sprinting());
        t.up(1, 0.2);
        assert!(!t.sprinting());
        t.down(2, (300.0, 800.0), 0.3, &[]);
        t.moved(2, (300.0, 800.0 - radius), 0.4);
        t.cancel_all();
        assert!(!t.sprinting());
    }
}
