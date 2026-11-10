//! iMC Settings: the settings that belong to the iOS app, not to Minecraft.
//!
//! Pure logic with no winit types and no game state, so it runs under `cargo test`. The values
//! live in `horizon-imc.txt` beside `options.txt` (so that file stays exactly vanilla's, as
//! `horizon-extras.txt` does), one `key:value` per line. Every value is clamped when it is read,
//! so a hand-edited or damaged file can never give the game a stick that cannot move or a view
//! that spins.
//!
//! The settings drive the touch controls through [`ImcSettings::apply`], which writes into the
//! public `layout`, `feel` and `double_tap_jump` of [`crate::touch::Touch`].

use crate::auto_performance::{Config as AutoConfig, Sensitivity};
use crate::touch::{Touch, menu_slop_for};

/// The file, next to `options.txt`.
pub const FILE: &str = "horizon-imc.txt";

/// One setting of the page, in the order the page lists them.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Item {
    /// Show the on-screen buttons.
    Controls,
    /// How far a finger drag turns the view.
    LookSpeed,
    /// How far the steering finger travels for full speed.
    StickSize,
    /// How much of the left side steers.
    MoveZone,
    /// How long a press must be held before it mines or uses.
    HoldTime,
    /// A double tap on the world jumps.
    DoubleTapJump,
    /// Greys out every setting that means nothing on an iPhone.
    GreyUnused,
    /// How far a finger may wander in a menu and still be a tap.
    MenuTouch,
    /// Moves where the on-screen buttons are hit, sideways and up or down.
    ButtonShiftX,
    ButtonShiftY,
    /// Sprint while the stick is pushed forward to its edge.
    AutoSprint,
    /// Moves every touch sideways by a few pixels, to cancel an offset on this phone.
    ShiftX,
    /// Moves every touch up or down by a few pixels.
    ShiftY,
    /// The edges a notch or rounded corner hides: where the buttons stop.
    SafeMargin,
    /// Gives memory back when the phone runs short (`auto_performance`).
    AutoPerformance,
    /// How early Auto Performance acts.
    AutoSensitivity,
    /// The render distance Auto Performance never goes below.
    AutoMinDistance,
    /// Auto Performance may cut far terrain.
    AutoFarTerrain,
    /// Auto Performance may lower the render distance.
    AutoRenderDistance,
    /// Auto Performance may lower the resolution.
    AutoResolution,
    /// Inventories open with the cursor, without switching the whole game to it.
    CursorInventory,
    /// How fast the cursor travels for the finger's travel.
    CursorSpeed,
}

impl Item {
    pub const ALL: [Item; 22] = [
        Item::Controls,
        Item::LookSpeed,
        Item::StickSize,
        Item::MoveZone,
        Item::HoldTime,
        Item::DoubleTapJump,
        Item::GreyUnused,
        Item::MenuTouch,
        Item::ButtonShiftX,
        Item::ButtonShiftY,
        Item::AutoSprint,
        Item::ShiftX,
        Item::ShiftY,
        Item::SafeMargin,
        Item::AutoPerformance,
        Item::AutoSensitivity,
        Item::AutoMinDistance,
        Item::AutoFarTerrain,
        Item::AutoRenderDistance,
        Item::AutoResolution,
        Item::CursorInventory,
        Item::CursorSpeed,
    ];

    /// The line's key in `horizon-imc.txt`.
    pub fn key(self) -> &'static str {
        match self {
            Item::Controls => "touchControls",
            Item::LookSpeed => "lookSpeed",
            Item::StickSize => "stickSize",
            Item::MoveZone => "moveZone",
            Item::HoldTime => "holdTime",
            Item::DoubleTapJump => "doubleTapJump",
            Item::GreyUnused => "greyUnused",
            Item::MenuTouch => "menuTouch",
            Item::ButtonShiftX => "buttonShiftX",
            Item::ButtonShiftY => "buttonShiftY",
            Item::AutoSprint => "autoSprint",
            Item::ShiftX => "shiftX",
            Item::ShiftY => "shiftY",
            Item::SafeMargin => "safeMargin",
            Item::AutoPerformance => "autoPerformance",
            Item::AutoSensitivity => "autoSensitivity",
            Item::AutoMinDistance => "autoMinDistance",
            Item::AutoFarTerrain => "autoFarTerrain",
            Item::AutoRenderDistance => "autoRenderDistance",
            Item::AutoResolution => "autoResolution",
            Item::CursorInventory => "cursorInventory",
            Item::CursorSpeed => "cursorSpeed",
        }
    }

    /// The English caption, and the fallback of the language key `horizon.imc.<key>`.
    pub fn caption(self) -> &'static str {
        match self {
            Item::Controls => "On-screen buttons",
            Item::LookSpeed => "Look speed",
            Item::StickSize => "Stick size",
            Item::MoveZone => "Steering area",
            Item::HoldTime => "Hold to mine",
            Item::DoubleTapJump => "Double tap to jump",
            Item::GreyUnused => "Grey out unused settings",
            Item::MenuTouch => "Menu touch",
            Item::ButtonShiftX => "Button shift X",
            Item::ButtonShiftY => "Button shift Y",
            Item::AutoSprint => "Auto sprint",
            Item::ShiftX => "Touch shift X",
            Item::ShiftY => "Touch shift Y",
            Item::SafeMargin => "Screen margin",
            Item::AutoPerformance => "Auto Performance",
            Item::AutoSensitivity => "Reacts",
            Item::AutoMinDistance => "Lowest distance",
            Item::AutoFarTerrain => "Cut far terrain",
            Item::AutoRenderDistance => "Lower render distance",
            Item::AutoResolution => "Lower resolution",
            Item::CursorInventory => "Cursor in inventory",
            Item::CursorSpeed => "Cursor speed",
        }
    }

    /// The language key of the caption.
    pub fn caption_key(self) -> String {
        format!("horizon.imc.{}", self.key())
    }

    /// The language key of the tooltip.
    pub fn description_key(self) -> String {
        format!("horizon.imc.{}.tooltip", self.key())
    }

    /// A short grey line under the setting when it is on and costs memory or speed: what the
    /// player is trading. `None` for a setting that costs neither. English; the language key is
    /// `horizon.imc.<key>.cost`.
    pub fn cost(self) -> Option<&'static str> {
        match self {
            Item::AutoRenderDistance => Some("Biggest saving: fewer chunks loaded and drawn."),
            Item::AutoFarTerrain => Some("Cuts far terrain first: it only shows on the horizon."),
            Item::AutoResolution => Some("Softens every pixel. Last resort."),
            Item::AutoSensitivity => Some("Early reacts sooner and holds back more often."),
            Item::AutoPerformance => {
                Some("Checks memory every 5 s. Your own settings are never changed.")
            }
            _ => None,
        }
    }

    /// The language key of the cost line.
    pub fn cost_key(self) -> String {
        format!("horizon.imc.{}.cost", self.key())
    }

    /// The English tooltip.
    pub fn description(self) -> &'static str {
        match self {
            Item::Controls => "Show the buttons on the screen while you play.",
            Item::LookSpeed => "How far the view turns when you drag a finger across the world.",
            Item::StickSize => "How far you slide the steering finger to walk at full speed.",
            Item::MoveZone => "How much of the left side of the screen steers.",
            Item::HoldTime => "How long you hold a finger still before it starts mining.",
            Item::DoubleTapJump => "Tap the world twice quickly to jump.",
            Item::GreyUnused => {
                "Greys out every setting that does nothing on an iPhone, such as keyboard binds, the mouse and the window, and says why when you point at it. What is left is what you can tune."
            }
            Item::MenuTouch => {
                "How far a finger can drift on a menu and still count as a tap. Higher means fewer accidental presses and slider moves, but a drag has to start further. Dragging sideways moves a slider, dragging up or down scrolls."
            }
            Item::ButtonShiftX => {
                "Moves where the on-screen buttons answer, sideways, without moving how they are drawn. Negative moves it left. If you have to press left of a button, use a negative value."
            }
            Item::ButtonShiftY => {
                "Moves where the on-screen buttons answer, up or down. Negative moves it up. If you have to press above a button, use a negative value."
            }
            Item::ShiftX => {
                "Moves every touch sideways, in screen pixels. Positive moves it right. If your finger lands to the right of where it acts, use a negative value."
            }
            Item::ShiftY => {
                "Moves every touch up or down, in screen pixels. Positive moves it down. If your finger lands below where it acts, use a negative value."
            }
            Item::AutoSprint => {
                "Push the stick forward to its edge and you sprint, without holding Run. Ease off and you walk."
            }
            Item::SafeMargin => {
                "Keeps the buttons away from the notch, the corners and the home bar."
            }
            Item::AutoPerformance => {
                "Watches the memory iOS still lets the game use, every 5 seconds. When it runs short the game gives some back by capping far terrain, then render distance. Your own settings are never changed: the caps lift again when memory recovers."
            }
            Item::AutoSensitivity => {
                "How early Auto Performance acts. Early: while there is still room, for a phone running other apps. Relaxed: only close to the limit."
            }
            Item::AutoMinDistance => {
                "Auto Performance never lowers the render distance below this many chunks."
            }
            Item::AutoFarTerrain => {
                "Auto Performance may shorten or turn off far terrain first. It is only seen on the horizon, so it costs the least picture."
            }
            Item::AutoRenderDistance => {
                "Auto Performance may lower the render distance, two chunks at a time, down to the lowest distance. The biggest saving."
            }
            Item::AutoResolution => {
                "Auto Performance may lower the world resolution as a last resort. Off by default: it softens every pixel."
            }
            Item::CursorInventory => {
                "Shows the cursor whenever an inventory is open (your bag, chests, crafting, creative), without switching the whole game to cursor mode. It goes away when you close it. The Cursor button on the screen still switches everything."
            }
            Item::CursorSpeed => {
                "How far the cursor moves for each bit your finger travels. Higher reaches the far corner of the inventory with a short swipe; lower is steadier for small slots."
            }
        }
    }
}

/// The choices of a stepped setting, from lowest to highest.
const LOOK_SPEEDS: [f64; 5] = [0.05, 0.075, 0.10, 0.14, 0.20];
const STICK_SIZES: [f32; 4] = [0.10, 0.14, 0.18, 0.22];
const MOVE_ZONES: [f32; 4] = [0.30, 0.40, 0.50, 0.60];
const HOLD_TIMES: [f64; 4] = [0.15, 0.25, 0.40, 0.60];
const SAFE_MARGINS: [f32; 4] = [0.0, 0.5, 1.0, 1.5];
/// The touch shifts, in physical pixels, by step. The middle one (index 2) is no shift. Five
/// steps, because every setting comes round in at most six clicks (a test holds them to it) and
/// a phone has no room for a long click-through. 8 px is a small part of the screen but the size
/// of the offset reported ("a small margin"); a larger one is a different bug.
const SHIFTS: [i16; 5] = [-16, -8, 0, 8, 16];
const NO_SHIFT: u8 = 2;
const SHIFT_NAMES: [&str; 5] = ["-16", "-8", "0", "+8", "+16"];
fn shift_name(i: u8) -> &'static str {
    SHIFT_NAMES[usize::from(i).min(SHIFT_NAMES.len() - 1)]
}

/// The names the page shows for a stepped setting, in the same order as its choices.
const LOOK_NAMES: [&str; 5] = ["Slowest", "Slow", "Normal", "Fast", "Fastest"];
const SIZE_NAMES: [&str; 4] = ["Small", "Normal", "Large", "Largest"];
const ZONE_NAMES: [&str; 4] = ["Narrow", "Normal", "Wide", "Widest"];
/// How far a menu finger may drift and still be a tap, as a multiple of the screen's own slop.
const MENU_SLOPS: [f32; 5] = [0.5, 1.0, 1.75, 2.5, 3.5];
const MENU_NAMES: [&str; 5] = ["Precise", "Normal", "Careful", "Very careful", "Firm"];
const HOLD_NAMES: [&str; 4] = ["Very short", "Short", "Normal", "Long"];
const MARGIN_NAMES: [&str; 4] = ["None", "Small", "Normal", "Large"];
/// The lowest render distances Auto Performance can be held to, in chunks.
const MIN_DISTANCES: [u32; 6] = [2, 4, 6, 8, 10, 12];
const MIN_DISTANCE_NAMES: [&str; 6] = [
    "2 chunks",
    "4 chunks",
    "6 chunks",
    "8 chunks",
    "10 chunks",
    "12 chunks",
];

/// The settings. A stepped one is stored as the index of its choice, so the file reads
/// `lookSpeed:2` and a value outside the list falls back to the default.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ImcSettings {
    pub controls: bool,
    pub look_speed: u8,
    pub stick_size: u8,
    pub move_zone: u8,
    pub hold_time: u8,
    pub double_tap_jump: bool,
    pub safe_margin: u8,
    /// Sprint while the stick is pushed forward to its edge.
    pub auto_sprint: bool,
    /// Settings that mean nothing on an iPhone are greyed out (`unused_on_ios`).
    pub grey_unused: bool,
    /// Index into [`MENU_SLOPS`].
    pub menu_touch: u8,
    /// Index into [`SHIFTS`] for x and y.
    pub shift_x: u8,
    pub shift_y: u8,
    /// Index into [`SHIFTS`]: where the on-screen buttons answer.
    pub button_shift_x: u8,
    pub button_shift_y: u8,
    /// Auto Performance (`auto_performance`).
    pub auto: AutoConfig,
    /// Inventories open with the cursor (`touch_cursor`), without the whole game switching.
    pub cursor_inventory: bool,
    /// Index into [`crate::touch_cursor::SPEEDS`].
    pub cursor_speed: u8,
}

impl Default for ImcSettings {
    /// The values touch had before it had settings, so nothing changes until the player does.
    fn default() -> Self {
        ImcSettings {
            controls: true,
            look_speed: 2,
            stick_size: 1,
            move_zone: 1,
            hold_time: 1,
            double_tap_jump: false,
            safe_margin: 2,
            auto_sprint: false,
            grey_unused: false,
            menu_touch: 1,
            shift_x: NO_SHIFT,
            shift_y: NO_SHIFT,
            button_shift_x: NO_SHIFT,
            button_shift_y: NO_SHIFT,
            auto: AutoConfig::default(),
            cursor_inventory: false,
            cursor_speed: crate::touch_cursor::NORMAL_SPEED,
        }
    }
}

impl ImcSettings {
    /// Reads the file's text. An unknown line, a missing line, or a value out of range keeps
    /// the default for that setting.
    pub fn parse(text: &str) -> Self {
        let mut s = ImcSettings::default();
        for line in text.lines() {
            let Some((key, value)) = line.split_once(':') else {
                continue;
            };
            let (key, value) = (key.trim(), value.trim());
            let step = |len: usize| value.parse::<u8>().ok().filter(|v| usize::from(*v) < len);
            match key {
                "touchControls" => {
                    if let Ok(v) = value.parse() {
                        s.controls = v;
                    }
                }
                "doubleTapJump" => {
                    if let Ok(v) = value.parse() {
                        s.double_tap_jump = v;
                    }
                }
                "lookSpeed" => s.look_speed = step(LOOK_SPEEDS.len()).unwrap_or(s.look_speed),
                "stickSize" => s.stick_size = step(STICK_SIZES.len()).unwrap_or(s.stick_size),
                "moveZone" => s.move_zone = step(MOVE_ZONES.len()).unwrap_or(s.move_zone),
                "holdTime" => s.hold_time = step(HOLD_TIMES.len()).unwrap_or(s.hold_time),
                "safeMargin" => s.safe_margin = step(SAFE_MARGINS.len()).unwrap_or(s.safe_margin),
                "greyUnused" => {
                    if let Ok(v) = value.parse() {
                        s.grey_unused = v;
                    }
                }
                "menuTouch" => s.menu_touch = step(MENU_SLOPS.len()).unwrap_or(s.menu_touch),
                "buttonShiftX" => s.button_shift_x = step(SHIFTS.len()).unwrap_or(s.button_shift_x),
                "buttonShiftY" => s.button_shift_y = step(SHIFTS.len()).unwrap_or(s.button_shift_y),
                "shiftX" => s.shift_x = step(SHIFTS.len()).unwrap_or(s.shift_x),
                "shiftY" => s.shift_y = step(SHIFTS.len()).unwrap_or(s.shift_y),
                "autoSprint" => {
                    if let Ok(v) = value.parse() {
                        s.auto_sprint = v;
                    }
                }
                "autoPerformance" => {
                    if let Ok(v) = value.parse() {
                        s.auto.enabled = v;
                    }
                }
                "autoSensitivity" => {
                    if let Some(i) = step(Sensitivity::ALL.len()) {
                        s.auto.sensitivity = Sensitivity::ALL[usize::from(i)];
                    }
                }
                "autoMinDistance" => {
                    if let Some(i) = step(MIN_DISTANCES.len()) {
                        s.auto.min_render_distance = MIN_DISTANCES[usize::from(i)];
                    }
                }
                "autoFarTerrain" => {
                    if let Ok(v) = value.parse() {
                        s.auto.use_far_terrain = v;
                    }
                }
                "autoRenderDistance" => {
                    if let Ok(v) = value.parse() {
                        s.auto.use_render_distance = v;
                    }
                }
                "autoResolution" => {
                    if let Ok(v) = value.parse() {
                        s.auto.use_resolution = v;
                    }
                }
                "cursorInventory" => {
                    if let Ok(v) = value.parse() {
                        s.cursor_inventory = v;
                    }
                }
                "cursorSpeed" => {
                    s.cursor_speed = step(crate::touch_cursor::SPEEDS.len()).unwrap_or(s.cursor_speed);
                }
                _ => {}
            }
        }
        s
    }

    /// The file's text.
    pub fn serialize(&self) -> String {
        format!(
            "touchControls:{}\nlookSpeed:{}\nstickSize:{}\nmoveZone:{}\nholdTime:{}\ndoubleTapJump:{}\nsafeMargin:{}\nautoSprint:{}\ngreyUnused:{}\nmenuTouch:{}\nbuttonShiftX:{}\nbuttonShiftY:{}\nshiftX:{}\nshiftY:{}\n\
             autoPerformance:{}\nautoSensitivity:{}\nautoMinDistance:{}\nautoFarTerrain:{}\nautoRenderDistance:{}\nautoResolution:{}\ncursorInventory:{}\ncursorSpeed:{}\n",
            self.controls,
            self.look_speed,
            self.stick_size,
            self.move_zone,
            self.hold_time,
            self.double_tap_jump,
            self.safe_margin,
            self.auto_sprint,
            self.grey_unused,
            self.menu_touch,
            self.button_shift_x,
            self.button_shift_y,
            self.shift_x,
            self.shift_y,
            self.auto.enabled,
            self.auto_sensitivity_index(),
            self.auto_min_distance_index(),
            self.auto.use_far_terrain,
            self.auto.use_render_distance,
            self.auto.use_resolution,
            self.cursor_inventory,
            self.cursor_speed,
        )
    }

    /// What the page's button shows for `item`.
    pub fn value(&self, item: Item) -> &'static str {
        let on_off = |on: bool| if on { "On" } else { "Off" };
        let name = |names: &[&'static str], i: u8| names[usize::from(i).min(names.len() - 1)];
        match item {
            Item::Controls => on_off(self.controls),
            Item::DoubleTapJump => on_off(self.double_tap_jump),
            Item::LookSpeed => name(&LOOK_NAMES, self.look_speed),
            Item::StickSize => name(&SIZE_NAMES, self.stick_size),
            Item::MoveZone => name(&ZONE_NAMES, self.move_zone),
            Item::HoldTime => name(&HOLD_NAMES, self.hold_time),
            Item::SafeMargin => name(&MARGIN_NAMES, self.safe_margin),
            Item::AutoSprint => on_off(self.auto_sprint),
            Item::GreyUnused => on_off(self.grey_unused),
            Item::MenuTouch => name(&MENU_NAMES, self.menu_touch),
            Item::ButtonShiftX => shift_name(self.button_shift_x),
            Item::ButtonShiftY => shift_name(self.button_shift_y),
            Item::ShiftX => shift_name(self.shift_x),
            Item::ShiftY => shift_name(self.shift_y),
            Item::AutoPerformance => on_off(self.auto.enabled),
            Item::AutoSensitivity => self.auto.sensitivity.name(),
            Item::AutoMinDistance => name(&MIN_DISTANCE_NAMES, self.auto_min_distance_index()),
            Item::AutoFarTerrain => on_off(self.auto.use_far_terrain),
            Item::AutoRenderDistance => on_off(self.auto.use_render_distance),
            Item::AutoResolution => on_off(self.auto.use_resolution),
            Item::CursorInventory => on_off(self.cursor_inventory),
            Item::CursorSpeed => name(&crate::touch_cursor::SPEED_NAMES, self.cursor_speed),
        }
    }

    /// The index of the sensitivity among its choices, as the file stores it.
    fn auto_sensitivity_index(&self) -> u8 {
        Sensitivity::ALL
            .iter()
            .position(|s| *s == self.auto.sensitivity)
            .unwrap_or(1) as u8
    }

    /// The index of the lowest distance among its choices (the nearest, if a value is not one).
    fn auto_min_distance_index(&self) -> u8 {
        MIN_DISTANCES
            .iter()
            .position(|d| *d == self.auto.min_render_distance)
            .unwrap_or(2) as u8
    }

    /// A click on `item`'s button: the next choice, or the previous one for the right button.
    /// The last choice wraps to the first.
    pub fn cycle(&mut self, item: Item, back: bool) {
        let turn = |v: &mut u8, len: usize| {
            let len = len as u8;
            *v = if back {
                (*v + len - 1) % len
            } else {
                (*v + 1) % len
            };
        };
        match item {
            Item::Controls => self.controls = !self.controls,
            Item::DoubleTapJump => self.double_tap_jump = !self.double_tap_jump,
            Item::LookSpeed => turn(&mut self.look_speed, LOOK_SPEEDS.len()),
            Item::StickSize => turn(&mut self.stick_size, STICK_SIZES.len()),
            Item::MoveZone => turn(&mut self.move_zone, MOVE_ZONES.len()),
            Item::HoldTime => turn(&mut self.hold_time, HOLD_TIMES.len()),
            Item::SafeMargin => turn(&mut self.safe_margin, SAFE_MARGINS.len()),
            Item::AutoSprint => self.auto_sprint = !self.auto_sprint,
            Item::GreyUnused => self.grey_unused = !self.grey_unused,
            Item::MenuTouch => turn(&mut self.menu_touch, MENU_SLOPS.len()),
            Item::ButtonShiftX => turn(&mut self.button_shift_x, SHIFTS.len()),
            Item::ButtonShiftY => turn(&mut self.button_shift_y, SHIFTS.len()),
            Item::ShiftX => turn(&mut self.shift_x, SHIFTS.len()),
            Item::ShiftY => turn(&mut self.shift_y, SHIFTS.len()),
            Item::AutoPerformance => self.auto.enabled = !self.auto.enabled,
            Item::AutoFarTerrain => self.auto.use_far_terrain = !self.auto.use_far_terrain,
            Item::AutoRenderDistance => {
                self.auto.use_render_distance = !self.auto.use_render_distance;
            }
            Item::AutoResolution => self.auto.use_resolution = !self.auto.use_resolution,
            Item::CursorInventory => self.cursor_inventory = !self.cursor_inventory,
            Item::CursorSpeed => turn(&mut self.cursor_speed, crate::touch_cursor::SPEEDS.len()),
            Item::AutoSensitivity => {
                let mut i = self.auto_sensitivity_index();
                turn(&mut i, Sensitivity::ALL.len());
                self.auto.sensitivity = Sensitivity::ALL[usize::from(i)];
            }
            Item::AutoMinDistance => {
                let mut i = self.auto_min_distance_index();
                turn(&mut i, MIN_DISTANCES.len());
                self.auto.min_render_distance = MIN_DISTANCES[usize::from(i)];
            }
        }
    }

    /// Whether `item` does anything right now: the settings of Auto Performance do nothing while
    /// it is off, and the lowest distance does nothing while the render distance is left alone.
    pub fn is_active(&self, item: Item) -> bool {
        match item {
            Item::AutoSensitivity
            | Item::AutoFarTerrain
            | Item::AutoRenderDistance
            | Item::AutoResolution => self.auto.enabled,
            Item::AutoMinDistance => self.auto.enabled && self.auto.use_render_distance,
            _ => true,
        }
    }

    /// Back to the defaults.
    pub fn reset(&mut self) {
        *self = ImcSettings::default();
    }

    /// The factor the on-screen buttons' safe margins are multiplied by (1.0 is the layout's
    /// own: 8% at the sides, 4% at the top, 7% at the bottom).
    /// The shift to add to every touch, `(x, y)` in physical pixels.
    pub fn touch_shift(&self) -> (f32, f32) {
        let at = |i: u8| f32::from(SHIFTS[usize::from(i).min(SHIFTS.len() - 1)]);
        (at(self.shift_x), at(self.shift_y))
    }

    /// Where the on-screen buttons answer, `(x, y)` in physical pixels, added to their hit
    /// rectangles and not to how they are drawn.
    pub fn button_shift(&self) -> (f32, f32) {
        let at = |i: u8| f32::from(SHIFTS[usize::from(i).min(SHIFTS.len() - 1)]);
        (at(self.button_shift_x), at(self.button_shift_y))
    }

    /// The multiple of the screen's own slop a menu finger may drift (Menu touch).
    pub fn menu_slop_scale(&self) -> f32 {
        MENU_SLOPS[usize::from(self.menu_touch).min(MENU_SLOPS.len() - 1)]
    }

    /// How far the cursor moves for a pixel of finger (`touch_cursor::SPEEDS`).
    pub fn cursor_speed_scale(&self) -> f32 {
        crate::touch_cursor::speed_at(self.cursor_speed)
    }

    pub fn safe_margin_scale(&self) -> f32 {
        SAFE_MARGINS[usize::from(self.safe_margin).min(SAFE_MARGINS.len() - 1)]
    }

    /// Writes the touch-driving settings into the finger state machine.
    pub fn apply(&self, touch: &mut Touch) {
        let pick = |len: usize, i: u8| usize::from(i).min(len - 1);
        touch.feel.look_degrees_per_px = LOOK_SPEEDS[pick(LOOK_SPEEDS.len(), self.look_speed)];
        touch.layout.stick_radius = STICK_SIZES[pick(STICK_SIZES.len(), self.stick_size)];
        touch.layout.move_zone = MOVE_ZONES[pick(MOVE_ZONES.len(), self.move_zone)];
        // A tap is a press shorter than the hold time, and a long press is a little longer, so
        // the two never overlap whatever the player picks.
        let hold = HOLD_TIMES[pick(HOLD_TIMES.len(), self.hold_time)];
        touch.feel.tap_secs = hold;
        touch.feel.long_press_secs = hold + 0.15;
        touch.double_tap_jump = self.double_tap_jump;
        touch.feel.menu_slop_px = menu_slop_for(touch.screen()) * self.menu_slop_scale();
    }
}

/// What kind of cost a heavy engine setting has.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Cost {
    /// Holds memory for as long as it is on.
    Memory,
    /// Makes every frame take longer, which on a phone becomes heat and then throttling.
    Speed,
    /// Both.
    Both,
}

impl Cost {
    pub fn label(self) -> &'static str {
        match self {
            Cost::Memory => "memory",
            Cost::Speed => "speed",
            Cost::Both => "memory and speed",
        }
    }
}

/// An engine setting known to cost memory or speed, and the notice shown about it.
///
/// Only costs the engine's own documentation states, or that follow from what the setting does,
/// are listed, and **no figure is quoted**: how many megabytes each costs on an iPhone has not
/// been measured (`IOS_MEMORY_STRATEGY.md`, section 5), and a number made up here would be
/// believed. The page shows the notice under the setting's group, in grey, so the player knows
/// what they are changing.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct HeavySetting {
    /// The language key of the setting's own name in the game (`options.*` or `horizon.*`).
    pub name_key: &'static str,
    /// The English name, when the key is missing.
    pub name: &'static str,
    pub cost: Cost,
    /// The English notice: what it costs and why, in one short line.
    pub notice: &'static str,
}

/// The settings that cost the most on a phone, most expensive first.
pub const HEAVY: [HeavySetting; 7] = [
    HeavySetting {
        name_key: "options.renderDistance",
        name: "Render distance",
        cost: Cost::Both,
        notice: "Every chunk loaded is meshed, held in memory and drawn. The biggest cost of all.",
    },
    HeavySetting {
        name_key: "horizon.graphics.lod_distance",
        name: "LOD distance",
        cost: Cost::Both,
        notice: "Far terrain tiles and their meshes stay loaded beyond the render distance.",
    },
    HeavySetting {
        name_key: "horizon.graphics.resolution_scale",
        name: "Resolution scale",
        cost: Cost::Both,
        notice: "Above 100% the render targets are larger, and every pixel costs more to draw.",
    },
    HeavySetting {
        name_key: "options.simulationDistance",
        name: "Simulation distance",
        cost: Cost::Speed,
        notice: "Mobs, crops and machines tick in every chunk in range, on the CPU.",
    },
    HeavySetting {
        name_key: "options.mipmapLevels",
        name: "Mipmap levels",
        cost: Cost::Memory,
        notice: "Each level keeps another smaller copy of every block texture.",
    },
    HeavySetting {
        name_key: "options.biomeBlendRadius",
        name: "Biome blend",
        cost: Cost::Speed,
        notice: "A wider blend makes the mesh workers sample more biomes for every block.",
    },
    HeavySetting {
        name_key: "horizon.graphics.taa",
        name: "Anti-aliasing (TAA)",
        cost: Cost::Both,
        notice: "Keeps a history of the last frame and blends into it every frame.",
    },
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_defaults_are_the_values_touch_had_before_it_had_settings() {
        let mut t = Touch::new((2532.0, 1170.0));
        let before = (t.layout, t.feel, t.double_tap_jump);
        ImcSettings::default().apply(&mut t);
        assert_eq!(t.layout, before.0);
        assert_eq!(t.double_tap_jump, before.2);
        assert_eq!(t.feel.look_degrees_per_px, before.1.look_degrees_per_px);
        assert_eq!(t.feel.tap_secs, before.1.tap_secs);
        // The long press stays at its old 0.40 s: tap 0.25 + 0.15.
        assert!((t.feel.long_press_secs - before.1.long_press_secs).abs() < 1.0e-9);
        // The deadzone is not a setting, so it is untouched.
        assert_eq!(t.layout.stick_deadzone, before.0.stick_deadzone);
    }

    #[test]
    fn a_file_round_trips() {
        let mut s = ImcSettings::default();
        s.cycle(Item::LookSpeed, false);
        s.cycle(Item::Controls, false);
        s.cycle(Item::DoubleTapJump, false);
        s.cycle(Item::SafeMargin, true);
        assert_eq!(ImcSettings::parse(&s.serialize()), s);
    }

    #[test]
    fn a_damaged_file_keeps_the_defaults() {
        let s = ImcSettings::parse(
            "lookSpeed:99\nstickSize:-1\nmoveZone:abc\ntouchControls:maybe\nnonsense\nunknown:1\n:\n",
        );
        assert_eq!(s, ImcSettings::default());
        assert_eq!(ImcSettings::parse(""), ImcSettings::default());
    }

    #[test]
    fn one_bad_line_does_not_lose_the_good_ones() {
        let s = ImcSettings::parse("lookSpeed:4\nstickSize:77\ndoubleTapJump:true\n");
        assert_eq!(s.look_speed, 4);
        assert_eq!(s.stick_size, ImcSettings::default().stick_size);
        assert!(s.double_tap_jump);
    }

    #[test]
    fn a_stepped_setting_wraps_both_ways() {
        let mut s = ImcSettings::default();
        s.look_speed = 4;
        s.cycle(Item::LookSpeed, false);
        assert_eq!(s.look_speed, 0);
        s.cycle(Item::LookSpeed, true);
        assert_eq!(s.look_speed, 4);
        // Every item can be cycled through its whole range and back to the start.
        for item in Item::ALL {
            let start = s.clone();
            let mut seen = 0;
            loop {
                s.cycle(item, false);
                seen += 1;
                if s == start || seen > 10 {
                    break;
                }
            }
            assert!(seen <= 6, "{item:?} took {seen} clicks to come round");
        }
    }

    #[test]
    fn apply_reaches_the_finger_state_machine() {
        let mut t = Touch::new((2532.0, 1170.0));
        let mut s = ImcSettings::default();
        s.look_speed = 4;
        s.stick_size = 3;
        s.move_zone = 3;
        s.hold_time = 0;
        s.double_tap_jump = true;
        s.apply(&mut t);
        assert_eq!(t.feel.look_degrees_per_px, 0.20);
        assert_eq!(t.layout.stick_radius, 0.22);
        assert_eq!(t.layout.move_zone, 0.60);
        assert_eq!(t.feel.tap_secs, 0.15);
        assert!(t.double_tap_jump);
    }

    #[test]
    fn a_tap_is_always_shorter_than_a_long_press() {
        for hold_time in 0..HOLD_TIMES.len() as u8 {
            let mut t = Touch::new((2532.0, 1170.0));
            let s = ImcSettings {
                hold_time,
                ..ImcSettings::default()
            };
            s.apply(&mut t);
            assert!(t.feel.tap_secs < t.feel.long_press_secs);
        }
    }

    #[test]
    fn every_item_has_a_distinct_key_and_a_value_for_every_step() {
        let mut keys: Vec<_> = Item::ALL.iter().map(|i| i.key()).collect();
        keys.sort_unstable();
        keys.dedup();
        assert_eq!(keys.len(), Item::ALL.len());
        let mut s = ImcSettings::default();
        for item in Item::ALL {
            for _ in 0..8 {
                assert!(!s.value(item).is_empty());
                s.cycle(item, false);
            }
            assert!(!item.caption().is_empty() && !item.description().is_empty());
        }
    }

    #[test]
    fn reset_restores_every_default() {
        let mut s = ImcSettings::parse("lookSpeed:0\nstickSize:3\ntouchControls:false\n");
        assert_ne!(s, ImcSettings::default());
        s.reset();
        assert_eq!(s, ImcSettings::default());
    }

    #[test]
    fn the_default_margin_leaves_the_layout_as_it_was() {
        assert_eq!(ImcSettings::default().safe_margin_scale(), 1.0);
        assert_eq!(
            ImcSettings {
                safe_margin: 0,
                ..ImcSettings::default()
            }
            .safe_margin_scale(),
            0.0
        );
    }

    #[test]
    fn auto_performance_is_off_by_default_and_round_trips() {
        let d = ImcSettings::default();
        assert!(!d.auto.enabled);
        assert!(!d.auto.use_resolution, "resolution is opt-in");
        let mut s = d.clone();
        s.cycle(Item::AutoPerformance, false);
        s.cycle(Item::AutoSensitivity, false);
        s.cycle(Item::AutoMinDistance, false);
        s.cycle(Item::AutoFarTerrain, false);
        s.cycle(Item::AutoRenderDistance, false);
        s.cycle(Item::AutoResolution, false);
        assert!(s.auto.enabled && s.auto.use_resolution);
        assert!(!s.auto.use_far_terrain && !s.auto.use_render_distance);
        assert_eq!(s.auto.sensitivity, Sensitivity::Early);
        assert_eq!(s.auto.min_render_distance, 8);
        assert_eq!(ImcSettings::parse(&s.serialize()), s);
    }

    #[test]
    fn an_old_file_without_auto_performance_still_reads() {
        let s = ImcSettings::parse("lookSpeed:3\ndoubleTapJump:true\n");
        assert_eq!(s.look_speed, 3);
        assert_eq!(s.auto, AutoConfig::default());
    }

    #[test]
    fn auto_performance_lines_out_of_range_keep_their_defaults() {
        let s = ImcSettings::parse(
            "autoSensitivity:9\nautoMinDistance:77\nautoPerformance:yes\nautoResolution:true\n",
        );
        assert_eq!(s.auto.sensitivity, AutoConfig::default().sensitivity);
        assert_eq!(s.auto.min_render_distance, 6);
        assert!(!s.auto.enabled);
        assert!(
            s.auto.use_resolution,
            "the good line beside the bad ones is kept"
        );
    }

    #[test]
    fn the_auto_performance_settings_are_inert_while_it_is_off() {
        let mut s = ImcSettings::default();
        for item in [
            Item::AutoSensitivity,
            Item::AutoMinDistance,
            Item::AutoFarTerrain,
            Item::AutoRenderDistance,
            Item::AutoResolution,
        ] {
            assert!(!s.is_active(item), "{item:?}");
        }
        s.cycle(Item::AutoPerformance, false);
        assert!(s.is_active(Item::AutoSensitivity));
        assert!(s.is_active(Item::AutoMinDistance));
        s.cycle(Item::AutoRenderDistance, false);
        assert!(
            !s.is_active(Item::AutoMinDistance),
            "nothing to hold a floor under"
        );
        // The touch settings are always live.
        assert!(s.is_active(Item::LookSpeed));
    }

    #[test]
    fn the_lowest_distance_choices_are_the_ones_the_governor_can_hold() {
        let mut s = ImcSettings::default();
        let mut seen = Vec::new();
        for _ in 0..MIN_DISTANCES.len() {
            seen.push(s.auto.min_render_distance);
            s.cycle(Item::AutoMinDistance, false);
        }
        assert_eq!(s.auto.min_render_distance, 6, "it comes back round");
        seen.sort_unstable();
        assert_eq!(seen, MIN_DISTANCES);
    }

    #[test]
    fn every_heavy_setting_has_a_short_notice_with_no_invented_figure() {
        for h in HEAVY {
            assert!(!h.name.is_empty() && !h.notice.is_empty());
            assert!(
                h.notice.len() <= 90,
                "{} is too long for one grey line",
                h.name
            );
            // Nothing on a phone has been measured yet, so no megabyte figure may appear.
            assert!(
                !h.notice.contains("MB") && !h.notice.contains("GB"),
                "{}",
                h.name
            );
            assert!(!h.cost.label().is_empty());
        }
        let mut keys: Vec<_> = HEAVY.iter().map(|h| h.name_key).collect();
        keys.sort_unstable();
        keys.dedup();
        assert_eq!(keys.len(), HEAVY.len());
    }

    #[test]
    fn the_cost_lines_of_auto_performance_fit_one_line() {
        for item in Item::ALL {
            if let Some(c) = item.cost() {
                assert!(c.len() <= 70, "{item:?}: {c}");
            }
        }
        assert!(Item::AutoRenderDistance.cost().is_some());
        assert!(Item::LookSpeed.cost().is_none());
    }

    #[test]
    fn the_touch_shift_defaults_to_none_and_steps_in_both_directions() {
        let mut s = ImcSettings::default();
        assert_eq!(s.touch_shift(), (0.0, 0.0));
        assert_eq!(s.value(Item::ShiftX), "0");
        s.cycle(Item::ShiftX, false);
        assert_eq!(s.touch_shift(), (8.0, 0.0));
        assert_eq!(s.value(Item::ShiftX), "+8");
        s.cycle(Item::ShiftY, true);
        s.cycle(Item::ShiftY, true);
        assert_eq!(s.touch_shift(), (8.0, -16.0));
        assert_eq!(s.value(Item::ShiftY), "-16");
        // It round-trips through the file, and a value out of range keeps the default.
        assert_eq!(ImcSettings::parse(&s.serialize()), s);
        assert_eq!(ImcSettings::parse("shiftX:99\n").touch_shift(), (0.0, 0.0));
        s.reset();
        assert_eq!(s.touch_shift(), (0.0, 0.0));
    }

    #[test]
    fn every_shift_name_matches_its_step() {
        assert_eq!(SHIFTS.len(), SHIFT_NAMES.len());
        assert_eq!(SHIFTS[usize::from(NO_SHIFT)], 0);
        for (v, n) in SHIFTS.iter().zip(SHIFT_NAMES) {
            let shown = if *v > 0 {
                format!("+{v}")
            } else {
                v.to_string()
            };
            assert_eq!(shown, n);
        }
    }

    #[test]
    fn grey_unused_is_off_by_default_and_round_trips() {
        let mut s = ImcSettings::default();
        assert!(!s.grey_unused);
        assert_eq!(s.value(Item::GreyUnused), "Off");
        s.cycle(Item::GreyUnused, false);
        assert!(s.grey_unused);
        assert_eq!(ImcSettings::parse(&s.serialize()), s);
        s.reset();
        assert!(!s.grey_unused);
    }

    #[test]
    fn menu_touch_scales_the_menu_slop_and_defaults_to_the_screens_own() {
        let mut t = Touch::new((2532.0, 1170.0));
        let mut s = ImcSettings::default();
        s.apply(&mut t);
        let normal = t.feel.menu_slop_px;
        assert!((normal - menu_slop_for((2532.0, 1170.0))).abs() < 1e-4);
        s.menu_touch = 4;
        s.apply(&mut t);
        assert!(t.feel.menu_slop_px > normal * 3.0);
        s.menu_touch = 0;
        s.apply(&mut t);
        assert!(t.feel.menu_slop_px < normal);
    }

    #[test]
    fn button_shift_is_none_by_default_and_round_trips() {
        let mut s = ImcSettings::default();
        assert_eq!(s.button_shift(), (0.0, 0.0));
        s.cycle(Item::ButtonShiftX, true);
        s.cycle(Item::ButtonShiftY, false);
        assert_ne!(s.button_shift(), (0.0, 0.0));
        let back = ImcSettings::parse(&s.serialize());
        assert_eq!(back, s);
        assert_eq!(back.button_shift(), s.button_shift());
        s.reset();
        assert_eq!(s.button_shift(), (0.0, 0.0));
        assert_eq!(s.menu_touch, 1);
    }

    #[test]
    fn the_cursor_is_off_by_default_at_normal_speed_and_round_trips() {
        let d = ImcSettings::default();
        assert!(!d.cursor_inventory, "plain touch until the player asks");
        assert_eq!(d.cursor_speed_scale(), 1.0);
        let mut s = d.clone();
        s.cycle(Item::CursorInventory, false);
        s.cycle(Item::CursorSpeed, false);
        assert!(s.cursor_inventory);
        assert_eq!(s.cursor_speed_scale(), 1.4);
        assert_eq!(ImcSettings::parse(&s.serialize()), s);
        assert_eq!(s.value(Item::CursorInventory), "On");
        assert_eq!(s.value(Item::CursorSpeed), "Fast");
        // Back from the first choice wraps to the last.
        let mut s = d;
        s.cycle(Item::CursorSpeed, true);
        s.cycle(Item::CursorSpeed, true);
        s.cycle(Item::CursorSpeed, true);
        assert_eq!(s.cursor_speed, 4);
    }

    #[test]
    fn an_old_file_without_the_cursor_lines_still_reads_with_the_defaults() {
        let s = ImcSettings::parse("lookSpeed:3\ndoubleTapJump:true\n");
        assert!(!s.cursor_inventory);
        assert_eq!(s.cursor_speed, crate::touch_cursor::NORMAL_SPEED);
    }

    #[test]
    fn cursor_lines_out_of_range_keep_their_defaults() {
        let s = ImcSettings::parse("cursorSpeed:9\ncursorInventory:maybe\n");
        assert_eq!(s.cursor_speed, crate::touch_cursor::NORMAL_SPEED);
        assert!(!s.cursor_inventory);
        let s = ImcSettings::parse("cursorSpeed:0\ncursorInventory:true\n");
        assert_eq!(s.cursor_speed, 0);
        assert!(s.cursor_inventory);
    }
}
