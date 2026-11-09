//! The extra on-screen buttons: Chat, F3, F2, View and two keys the player picks.
//!
//! Each one presses a key of the game, by the name of the binding, so the player's own choice
//! counts: Chat presses whatever `key.chat` is bound to, not a hard-coded T. A button is drawn
//! and answers a touch only once it is switched on; where it sits and how big it is comes from
//! the layout (`touch_layout`), like the nine that are always there.
//!
//! Pure: the file's text, the names and the checks. The game presses the key
//! (`horizon-client`). Kept in `horizon-imc-buttons.txt`, written only once something is changed.

/// The file, beside `options.txt`.
pub const FILE: &str = "horizon-imc-buttons.txt";

/// One of the extra buttons.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Extra {
    Chat,
    Debug,
    Screenshot,
    View,
    Key1,
    Key2,
}

impl Extra {
    pub const ALL: [Extra; 6] = [
        Extra::Chat,
        Extra::Debug,
        Extra::Screenshot,
        Extra::View,
        Extra::Key1,
        Extra::Key2,
    ];

    /// The name in the file, and the button's name in the layout file.
    pub fn name(self) -> &'static str {
        match self {
            Extra::Chat => "chat",
            Extra::Debug => "debug",
            Extra::Screenshot => "shot",
            Extra::View => "view",
            Extra::Key1 => "key1",
            Extra::Key2 => "key2",
        }
    }

    /// What the button shows by default.
    pub fn label(self) -> &'static str {
        match self {
            Extra::Chat => "Chat",
            Extra::Debug => "F3",
            Extra::Screenshot => "F2",
            Extra::View => "View",
            Extra::Key1 => "Key 1",
            Extra::Key2 => "Key 2",
        }
    }

    /// The game's binding this button presses, or `None` for the two the player picks.
    pub fn binding(self) -> Option<&'static str> {
        match self {
            Extra::Chat => Some("key.chat"),
            Extra::Debug => Some("key.debug.overlay"),
            Extra::Screenshot => Some("key.screenshot"),
            Extra::View => Some("key.togglePerspective"),
            Extra::Key1 | Extra::Key2 => None,
        }
    }

    fn index(self) -> usize {
        Self::ALL.iter().position(|e| *e == self).unwrap_or(0)
    }
}

/// Which extras are on, and the two keys.
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct Extras {
    on: [bool; 6],
    /// The game's key name (`key.keyboard.g`) the two picked buttons press, or empty.
    keys: [String; 2],
}

impl Extras {
    pub fn is_on(&self, e: Extra) -> bool {
        self.on[e.index()]
    }

    pub fn set_on(&mut self, e: Extra, on: bool) {
        self.on[e.index()] = on;
    }

    pub fn toggle(&mut self, e: Extra) {
        let i = e.index();
        self.on[i] = !self.on[i];
    }

    /// A picked button's key name, `""` while none is chosen.
    pub fn key_of(&self, e: Extra) -> &str {
        match e {
            Extra::Key1 => &self.keys[0],
            Extra::Key2 => &self.keys[1],
            _ => "",
        }
    }

    /// Chooses the key of Key 1 or Key 2. Anything that is not a plain key name is refused, and
    /// the old choice stays.
    pub fn set_key(&mut self, e: Extra, name: &str) -> bool {
        let slot = match e {
            Extra::Key1 => 0,
            Extra::Key2 => 1,
            _ => return false,
        };
        if !valid_key_name(name) {
            return false;
        }
        self.keys[slot] = name.to_owned();
        true
    }

    /// The buttons that are on and have something to press, in order.
    pub fn active(&self) -> impl Iterator<Item = Extra> + '_ {
        Extra::ALL.into_iter().filter(|e| {
            self.is_on(*e) && (e.binding().is_some() || !self.key_of(*e).is_empty())
        })
    }

    pub fn is_default(&self) -> bool {
        *self == Extras::default()
    }

    /// The saved text. A button is a line `chat:on`; a picked key adds `key1.key:key.keyboard.g`.
    pub fn serialize(&self) -> String {
        let mut out = String::new();
        for e in Extra::ALL {
            if self.is_on(e) {
                out.push_str(&format!("{}:on\n", e.name()));
            }
        }
        for (i, e) in [Extra::Key1, Extra::Key2].into_iter().enumerate() {
            if !self.keys[i].is_empty() {
                out.push_str(&format!("{}.key:{}\n", e.name(), self.keys[i]));
            }
        }
        out
    }

    /// Reads the text. Unknown lines and key names that are not plain are ignored.
    pub fn parse(text: &str) -> Self {
        let mut extras = Extras::default();
        for line in text.lines() {
            let Some((name, value)) = line.split_once(':') else {
                continue;
            };
            let (name, value) = (name.trim(), value.trim());
            if let Some(e) = Extra::ALL.into_iter().find(|e| e.name() == name) {
                extras.set_on(e, value == "on");
            } else if let Some(base) = name.strip_suffix(".key")
                && let Some(e) = [Extra::Key1, Extra::Key2]
                    .into_iter()
                    .find(|e| e.name() == base)
            {
                extras.set_key(e, value);
            }
        }
        extras
    }
}

/// The keys Key 1 and Key 2 can be set to: the ones a player is likely to want on a button. A
/// click on the setting steps to the next, so the page needs no "press a key" screen. Each is a
/// name the game knows (`keybinds`), and each passes [`valid_key_name`].
pub const CHOICES: [&str; 24] = [
    "key.keyboard.f1",
    "key.keyboard.f4",
    "key.keyboard.f5",
    "key.keyboard.f6",
    "key.keyboard.f7",
    "key.keyboard.f8",
    "key.keyboard.f9",
    "key.keyboard.f10",
    "key.keyboard.f11",
    "key.keyboard.g",
    "key.keyboard.h",
    "key.keyboard.j",
    "key.keyboard.k",
    "key.keyboard.l",
    "key.keyboard.m",
    "key.keyboard.n",
    "key.keyboard.o",
    "key.keyboard.p",
    "key.keyboard.u",
    "key.keyboard.v",
    "key.keyboard.b",
    "key.keyboard.x",
    "key.keyboard.z",
    "key.keyboard.slash",
];

/// A key as the page shows it: `key.keyboard.f6` is `F6`, `key.keyboard.g` is `G`, and no key
/// is `None`.
pub fn key_caption(name: &str) -> String {
    match name.strip_prefix("key.keyboard.") {
        Some(rest) if !rest.is_empty() => rest.replace('.', " ").to_ascii_uppercase(),
        _ => "None".to_owned(),
    }
}

impl Extras {
    /// Steps Key 1 or Key 2 to the next choice (from none to the first, and after the last back
    /// to none). A key the file holds that is not among the choices steps to the first.
    pub fn step_key(&mut self, e: Extra) -> bool {
        let current = self.key_of(e).to_owned();
        let next = if current.is_empty() {
            Some(CHOICES[0])
        } else {
            match CHOICES.iter().position(|c| *c == current) {
                Some(i) => CHOICES.get(i + 1).copied(),
                None => Some(CHOICES[0]),
            }
        };
        match next {
            Some(name) => self.set_key(e, name),
            None => {
                let slot = if e == Extra::Key1 { 0 } else { 1 };
                if e != Extra::Key1 && e != Extra::Key2 {
                    return false;
                }
                self.keys[slot].clear();
                true
            }
        }
    }
}

/// Whether `name` could be a key of the game: `key.keyboard.` and then lower case letters,
/// digits, dots and underscores. The game still has the last word on whether it exists; this
/// keeps a damaged file or a typo from carrying anything odd into a command line.
pub fn valid_key_name(name: &str) -> bool {
    name.len() <= 40
        && name
            .strip_prefix("key.keyboard.")
            .is_some_and(|rest| {
                !rest.is_empty()
                    && rest
                        .chars()
                        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '.' || c == '_')
            })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nothing_is_on_until_the_player_switches_it_on() {
        let extras = Extras::default();
        assert!(extras.is_default());
        assert_eq!(extras.active().count(), 0);
        assert_eq!(extras.serialize(), "");
        assert_eq!(Extras::parse(""), extras);
    }

    #[test]
    fn a_button_is_active_only_when_on_and_it_has_a_key() {
        let mut extras = Extras::default();
        extras.set_on(Extra::Chat, true);
        extras.set_on(Extra::Key1, true);
        // Key 1 is on but has no key yet: nothing to press, so no button.
        assert_eq!(extras.active().collect::<Vec<_>>(), vec![Extra::Chat]);
        assert!(extras.set_key(Extra::Key1, "key.keyboard.g"));
        assert_eq!(
            extras.active().collect::<Vec<_>>(),
            vec![Extra::Chat, Extra::Key1]
        );
        extras.toggle(Extra::Chat);
        assert_eq!(extras.active().collect::<Vec<_>>(), vec![Extra::Key1]);
    }

    #[test]
    fn the_fixed_buttons_press_the_players_own_bindings() {
        assert_eq!(Extra::Chat.binding(), Some("key.chat"));
        assert_eq!(Extra::Debug.binding(), Some("key.debug.overlay"));
        assert_eq!(Extra::Screenshot.binding(), Some("key.screenshot"));
        assert_eq!(Extra::View.binding(), Some("key.togglePerspective"));
        assert_eq!(Extra::Key1.binding(), None);
    }

    #[test]
    fn it_survives_the_file() {
        let mut extras = Extras::default();
        extras.set_on(Extra::Debug, true);
        extras.set_on(Extra::Key2, true);
        extras.set_key(Extra::Key2, "key.keyboard.left.bracket");
        extras.set_key(Extra::Key1, "key.keyboard.f6");
        assert_eq!(Extras::parse(&extras.serialize()), extras);
        assert!(!extras.is_default());
    }

    #[test]
    fn only_plain_key_names_are_taken() {
        let mut extras = Extras::default();
        for bad in [
            "",
            "g",
            "key.keyboard.",
            "key.keyboard.G",
            "key.keyboard.g tap\nquit",
            "key.mouse.left",
            "key.keyboard.a;b",
            &format!("key.keyboard.{}", "x".repeat(40)),
        ] {
            assert!(!extras.set_key(Extra::Key1, bad), "{bad:?}");
        }
        assert_eq!(extras.key_of(Extra::Key1), "");
        assert!(!extras.set_key(Extra::Chat, "key.keyboard.g"), "Chat's key is not picked");
        // A bad line in the file is dropped and the rest is read.
        let read = Extras::parse("chat:on\nkey1.key:key.keyboard.g\nkey2.key:quit\nnonsense\nfoo:on");
        assert!(read.is_on(Extra::Chat));
        assert_eq!(read.key_of(Extra::Key1), "key.keyboard.g");
        assert_eq!(read.key_of(Extra::Key2), "");
    }

    #[test]
    fn every_choice_is_a_valid_name_the_game_knows_and_none_twice() {
        for (i, c) in CHOICES.iter().enumerate() {
            assert!(valid_key_name(c), "{c}");
            assert!(CHOICES[i + 1..].iter().all(|o| o != c), "{c} is listed twice");
        }
    }

    #[test]
    fn the_game_knows_every_choice() {
        // An unknown name would press nothing, silently.
        for c in CHOICES {
            assert!(crate::keybinds::key_code(c).is_some(), "{c} is not a key of the game");
        }
    }

    #[test]
    fn stepping_goes_through_every_choice_and_back_to_none() {
        let mut extras = Extras::default();
        assert_eq!(extras.key_of(Extra::Key1), "");
        for c in CHOICES {
            assert!(extras.step_key(Extra::Key1));
            assert_eq!(extras.key_of(Extra::Key1), c);
        }
        assert!(extras.step_key(Extra::Key1));
        assert_eq!(extras.key_of(Extra::Key1), "");
        // Key 2 is its own; the fixed buttons have no key to step.
        assert_eq!(extras.key_of(Extra::Key2), "");
        assert!(!extras.step_key(Extra::Chat));
    }

    #[test]
    fn a_key_not_among_the_choices_steps_to_the_first() {
        let mut extras = Extras::parse("key2.key:key.keyboard.left.bracket\n");
        assert_eq!(extras.key_of(Extra::Key2), "key.keyboard.left.bracket");
        assert!(extras.step_key(Extra::Key2));
        assert_eq!(extras.key_of(Extra::Key2), CHOICES[0]);
    }

    #[test]
    fn keys_are_shown_by_their_plain_name() {
        assert_eq!(key_caption("key.keyboard.f6"), "F6");
        assert_eq!(key_caption("key.keyboard.g"), "G");
        assert_eq!(key_caption("key.keyboard.left.bracket"), "LEFT BRACKET");
        assert_eq!(key_caption(""), "None");
    }

    #[test]
    fn every_extra_has_its_own_name_and_a_label() {
        for (i, a) in Extra::ALL.iter().enumerate() {
            assert!(!a.label().is_empty() && !a.name().contains([':', ',', '.', '\n']));
            assert!(Extra::ALL[i + 1..].iter().all(|b| a.name() != b.name()));
        }
    }
}
