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

use crate::touch::Touch;

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
    /// The edges a notch or rounded corner hides: where the buttons stop.
    SafeMargin,
}

impl Item {
    pub const ALL: [Item; 7] = [
        Item::Controls,
        Item::LookSpeed,
        Item::StickSize,
        Item::MoveZone,
        Item::HoldTime,
        Item::DoubleTapJump,
        Item::SafeMargin,
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
            Item::SafeMargin => "safeMargin",
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
            Item::SafeMargin => "Screen margin",
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

    /// The English tooltip.
    pub fn description(self) -> &'static str {
        match self {
            Item::Controls => "Show the buttons on the screen while you play.",
            Item::LookSpeed => "How far the view turns when you drag a finger across the world.",
            Item::StickSize => "How far you slide the steering finger to walk at full speed.",
            Item::MoveZone => "How much of the left side of the screen steers.",
            Item::HoldTime => "How long you hold a finger still before it starts mining.",
            Item::DoubleTapJump => "Tap the world twice quickly to jump.",
            Item::SafeMargin => {
                "Keeps the buttons away from the notch, the corners and the home bar."
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

/// The names the page shows for a stepped setting, in the same order as its choices.
const LOOK_NAMES: [&str; 5] = ["Slowest", "Slow", "Normal", "Fast", "Fastest"];
const SIZE_NAMES: [&str; 4] = ["Small", "Normal", "Large", "Largest"];
const ZONE_NAMES: [&str; 4] = ["Narrow", "Normal", "Wide", "Widest"];
const HOLD_NAMES: [&str; 4] = ["Very short", "Short", "Normal", "Long"];
const MARGIN_NAMES: [&str; 4] = ["None", "Small", "Normal", "Large"];

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
                _ => {}
            }
        }
        s
    }

    /// The file's text.
    pub fn serialize(&self) -> String {
        format!(
            "touchControls:{}\nlookSpeed:{}\nstickSize:{}\nmoveZone:{}\nholdTime:{}\ndoubleTapJump:{}\nsafeMargin:{}\n",
            self.controls,
            self.look_speed,
            self.stick_size,
            self.move_zone,
            self.hold_time,
            self.double_tap_jump,
            self.safe_margin,
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
        }
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
        }
    }

    /// Back to the defaults.
    pub fn reset(&mut self) {
        *self = ImcSettings::default();
    }

    /// The factor the on-screen buttons' safe margins are multiplied by (1.0 is the layout's
    /// own: 8% at the sides, 4% at the top, 7% at the bottom).
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
    }
}

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
            assert!(seen <= 5, "{item:?} took {seen} clicks to come round");
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
            for _ in 0..6 {
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
}
