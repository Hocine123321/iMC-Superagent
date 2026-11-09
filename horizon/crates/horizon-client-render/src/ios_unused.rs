//! Settings that mean nothing on an iPhone (iMC Settings > "Grey out unused settings").
//!
//! Horizon is a desktop game, and most of its settings page is about a keyboard, a mouse, a
//! window, or a program the iOS app does not have. With the switch on, each of them is greyed out
//! and says why when pointed at, so what is left is what a player can tune on the phone.
//!
//! Every match here lists its variants and has **no wildcard**: a new setting does not compile
//! until someone decides whether it belongs on a phone. That is the point of this file.
//!
//! What counts as "no meaning on iOS":
//! - it needs hardware an iPhone does not have (keyboard, mouse, a window, a second monitor);
//! - the port turns the feature off (native mods, shader packs, Discord, Splitscreen), see
//!   `docs/IOS_FEASIBILITY_REPORT.md` section 9 and the gate list in section 12;
//! - the system decides it (output device, refresh rate, graphics API: iOS has Metal only).
//!
//! What does **not**: anything that works through touch, the screen or the speaker, and the
//! controller settings, since an iPhone can pair a controller and the roadmap lists one.

use crate::graphics_ui::H;
use crate::settings::Opt;

/// Why a setting does nothing on an iPhone, in a few words for the tooltip. `None`: it is used.
pub type Reason = &'static str;

pub(crate) const KEYBOARD: Reason = "An iPhone has no keyboard.";
const MOUSE: Reason = "An iPhone has no mouse. Touch look speed is in iMC Settings.";
const WINDOW: Reason = "The game always fills the screen on an iPhone.";
const SYSTEM: Reason = "iOS decides this itself.";
const METAL: Reason = "iOS draws with Metal only.";
const DUALSENSE: Reason = "Only for a PlayStation DualSense controller.";
const NOT_ON_IOS: Reason = "Not available in the iPhone app.";
const OFFLINE_ONLY: Reason = "Not in the iPhone app: it has no Realms, friends or Discord.";

/// Why a vanilla option is of no use on an iPhone.
pub fn opt(o: Opt) -> Option<Reason> {
    use Opt::*;
    match o {
        // The mouse page.
        Sensitivity | WheelSensitivity | DiscreteScroll | InvertX | InvertY
        | AllowCursorChanges => Some(MOUSE),
        // Keyboard.
        CtrlClickEmulatesRightClick | QuitShortcuts | NarratorHotkey | PadKeyboard => {
            Some(KEYBOARD)
        }
        // The window and the display.
        Fullscreen | ExclusiveFullscreen | ExclusiveMode => Some(WINDOW),
        // Only the sync is the system's; a frame cap and the background cap save battery.
        Vsync => Some(SYSTEM),
        GraphicsBackend => Some(METAL),
        SoundDevice => Some(SYSTEM),
        // A DualSense only.
        PadAdaptiveTriggers | PadLightbar => Some(DUALSENSE),
        // Services the app does not have.
        RealmsNotifications | InGameNotification | SharePresence | AllowServerListing => {
            Some(OFFLINE_ONLY)
        }
        // Everything else works on a phone.
        MaxFps
        | InactivityFps
        | Fov
        | RenderDistance
        | SimulationDistance
        | Volume(_)
        | GuiScale
        | ViewBobbing
        | Gamma
        | SmoothLighting
        | Clouds
        | CloudRange
        | Particles
        | EntityDistance
        | EntityShadows
        | BiomeBlend
        | Preset
        | Mipmaps
        | WeatherRadius
        | ChunkFade
        | Vignette
        | Autosave
        | CutoutLeaves
        | ImprovedTransparency
        | AttackIndicator
        | ChunkBuilder
        | MenuBlur
        | ToggleCrouch
        | ToggleSprint
        | ToggleAttack
        | ToggleUse
        | AutoJump
        | SprintWindow
        | OperatorItemsTab
        | ChatVisibility
        | ChatColors
        | ChatLinks
        | ChatLinksPrompt
        | ChatOpacity
        | TextBackgroundOpacity
        | ChatScale
        | ChatWidth
        | ChatHeightFocused
        | ChatHeightUnfocused
        | ChatLineSpacing
        | AutoSuggestions
        | HideMatchedNames
        | ReducedDebugInfo
        | OnlySecureChat
        | SaveChatDrafts
        | HighContrast
        | ShowSubtitles
        | MusicFrequency
        | NotificationDisplayTime
        | Narrator
        | TextBackground
        | ChatDelay
        | DistortionEffects
        | FovEffects
        | DarknessPulsing
        | DamageTilt
        | GlintSpeed
        | GlintStrength
        | HideLightningFlashes
        | MonochromeLogo
        | PanoramaSpeed
        | HideSplashTexts
        | RotateWithMinecarts
        | HighContrastBlockOutlines
        | ForceUnicode
        | JapaneseGlyphs
        | PadEnabled
        | PadVibration
        | PadPlayInBackground
        | PadLookSensitivity
        | PadPointerSpeed
        | PadScrollSpeed
        | PadRepeatDelay
        | PadRepeatInterval
        | PadInvertX
        | PadInvertY
        | PadToggleSneak
        | PadMoveDeadzone
        | PadLookDeadzone
        | PadTriggerThreshold
        | PadGlyphs
        | PadGameplayGuide
        | ModelPart(_)
        | SkinLayers3d
        | MainHand
        | DirectionalAudio
        | MusicToast
        | TextureFiltering
        | MaxAnisotropy => None,
    }
}

/// Why one of Horizon's own graphics settings is of no use on an iPhone.
pub fn graphics(h: H) -> Option<Reason> {
    use H::*;
    match h {
        // The window and how frames reach it.
        PresentMode | Pacing | GraphicsApi => Some(SYSTEM),
        // HDR output is a Vulkan path in the engine; the port has no HDR yet.
        Hdr | HdrBlackLevel | HdrKey | HdrCalibrate | HdrPeak | HdrPaperWhite | HdrUiBrightness
        | HdrLighting | HdrSmoothGradients => Some(NOT_ON_IOS),
        // Everything else is the picture, the work done per frame, or the cache.
        ShaderPacks
        | BlueMapAutoDetect
        | BlueMapRadius
        | Preset
        | LodDistance
        | FarDetail
        | CaveCulling
        | GpuCulling
        | EntityCulling
        | EntityCullingPrecheck
        | ParticleCulling
        | LeafCulling
        | CacheShulkerBoxes
        | CacheSigns
        | CacheDecoratedPots
        | CacheBells
        | CacheChests
        | CacheBanners
        | CacheCopperGolemStatues
        | ChunkUpdates
        | UploadBudget
        | Sky
        | Fog
        | Weather
        | AnimatedTextures
        | DitherCutoutMips
        | Workers
        | Overlay
        | ResolutionScale
        | Antialiasing
        | Upscaling
        | ScreenshotQuality
        | FrameGeneration
        | BatteryMode
        | ShadowCache
        | TranslucentBatching => None,
    }
}

/// Why one of Horizon's extras is of no use on an iPhone.
pub fn extra(item: crate::extras::Item) -> Option<Reason> {
    use crate::extras::Item::*;
    match item {
        // Needs a keyboard.
        MouseTweaks | MouseTweaksWheel | ReproKeys | WheelCyclesSettings => Some(MOUSE),
        // Other programs and windows.
        DiscordPresence => Some(OFFLINE_ONLY),
        Splitscreen => Some("Needs a second player on one screen: not in the iPhone app."),
        // The PvP & HUD page: a handful of its options are about keys.
        Pvp(o) => pvp(o),
        // Everything else changes the game itself.
        AgentControl | NoAi | Fullbright | DynamicLights | OwnNameTag | HideBlockParticles
        | AutoReconnect | UiSoundReserve | MusicPage | Sort | SortKey | ChatAnimation
        | ChatIndicator | PackBrowser | Pregen | CosmeticsMine | CosmeticsOthers
        | CosmeticsHideFx | CosmeticsSolo | HorizonMarks | HorizonMe => None,
    }
}

/// Why a whole page of Options is of no use on an iPhone. A page that is only partly useless
/// (Video, Controls) stays open: its useless rows are greyed one by one.
pub fn page(p: crate::options_ui::Page) -> Option<Reason> {
    use crate::options_ui::Page::*;
    match p {
        // Keyboard binds and mouse settings.
        KeyBinds => Some(KEYBOARD),
        Mouse => Some(MOUSE),
        // A native mod is Rust source compiled by cargo: impossible on a phone (section 9.2).
        // Content mods (.hmod) are data and are viable, so the Mods pages stay.
        NativeMod(_) => Some("Native mods need a compiler: not possible on an iPhone."),
        HdrCalibration | GraphicsHdr => Some(NOT_ON_IOS),
        // Several players on one screen (a phone has one display).
        SplitProfiles | SplitSetup => Some(NOT_ON_IOS),
        // The rest is used. Replay Studio and the AI Agent page are not in the port's gate list
        // (`IOS_FEASIBILITY_REPORT.md` section 12), so they are not greyed on a guess.
        Mods | ModBrowser | ModProject | ShaderPacks | ShaderOptions | Studio | Agent | Main
        | Video | Sound | Controls | Chat | Accessibility | Language | Font | Packs | Graphics
        | GraphicsAdvanced | Controller | PadBinds | Extras | Pvp | Credits | Horizon | Imc
        | Skin | Online | Music => None,
    }
}

/// Why an option of the PvP & HUD page is of no use on an iPhone. Only the ones about keys are:
/// Keystrokes draws W, A, S and D as they are pressed, and the HUD editor opens on a key.
/// (Clicks per second stays: whether it counts a tap is not checked, so it is not assumed.)
pub fn pvp(o: crate::pvp::Opt) -> Option<Reason> {
    use crate::pvp::Opt::*;
    match o {
        HudKeys | HudKeysCorner | HudEditorKey => Some(KEYBOARD),
        Crosshair | CrosshairShape | CrosshairSize | CrosshairGap | CrosshairThickness
        | CrosshairColour | CrosshairOutline | CrosshairDot | CrosshairHover | Outline
        | OutlineColour | OutlineOpacity | OutlineThickness | OutlineFill | Hit | HitColour
        | HitOpacity | HudArmour | HudArmourCorner | HudArmourPercent | HudEffects
        | HudEffectsCorner | HudHeld | HudHeldCorner | HudPing | HudPingCorner | HudCoords
        | HudCoordsCorner | HudServer | HudServerCorner | HudCombo | HudComboCorner | HudFps
        | HudFpsCorner | HudCps | HudCpsCorner | HudClock | HudClockCorner | HudReach
        | HudReachCorner | HudSpeed | HudSpeedCorner | HudBackground | HudOpacity
        | HudTextColour | HudShadow | NumericEnchants | FireLower | ShieldSize | TotemSize
        | GlintColour | ClearWater | ClearLava | ViewTime | ViewWeather | ChatTimestamps
        | ChatCompact | ChatCopy | ChatSearch | CombatFeel | CombatIndicator | CombatSounds
        | CombatRules => None,
    }
}
