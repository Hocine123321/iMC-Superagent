//! Touch calibration: a correction fitted from the player's own taps.
//!
//! The player taps targets the game draws; each pair (where the finger was reported, where the
//! target is) is a sample. A stretch and a shift per axis, `x' = sx * x + ox`, is fitted to the
//! samples by least squares and applied to every touch before anything else reads it. This
//! corrects an error that grows toward the screen's edges (a touch reported a little toward the
//! centre, more at the far left and far right) as well as a plain shift, whatever its cause.
//!
//! Pure: no window, no files except the text form. The screen that collects the taps is in
//! `horizon-client`.

/// The file the correction is kept in, beside the options.
pub const FILE: &str = "horizon-imc-touch-calibration.txt";

/// Where the targets are, as fractions of the screen: the four corners pulled in, and the centre.
/// Far apart on purpose: the stretch is read from the distance between them.
pub const TARGETS: [(f32, f32); 5] = [
    (0.10, 0.12),
    (0.90, 0.12),
    (0.10, 0.88),
    (0.90, 0.88),
    (0.50, 0.50),
];

/// A stretch and a shift for each axis. The default does nothing.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Calibration {
    pub sx: f32,
    pub ox: f32,
    pub sy: f32,
    pub oy: f32,
}

impl Default for Calibration {
    fn default() -> Self {
        Self::IDENTITY
    }
}

/// The most a fitted stretch may differ from 1 and the most a shift may move a touch (as a
/// fraction of the screen). A bad run (a finger that missed a target) is refused, not applied.
const MAX_STRETCH: f32 = 0.15;
const MAX_SHIFT: f32 = 0.10;

impl Calibration {
    pub const IDENTITY: Self = Self {
        sx: 1.0,
        ox: 0.0,
        sy: 1.0,
        oy: 0.0,
    };

    pub fn is_identity(&self) -> bool {
        *self == Self::IDENTITY
    }

    /// A reported touch as the finger really was.
    pub fn apply(&self, at: (f32, f32)) -> (f32, f32) {
        (self.sx * at.0 + self.ox, self.sy * at.1 + self.oy)
    }

    /// Fits the correction from `(reported, intended)` pairs on a screen of `size`, in pixels.
    /// `None` when there are too few samples, they do not spread over the screen, or the result
    /// is larger than any real error could be.
    pub fn fit(samples: &[((f32, f32), (f32, f32))], size: (f32, f32)) -> Option<Self> {
        if samples.len() < 3 || size.0 <= 0.0 || size.1 <= 0.0 {
            return None;
        }
        let (sx, ox) = line(samples.iter().map(|s| (s.0.0, s.1.0)))?;
        let (sy, oy) = line(samples.iter().map(|s| (s.0.1, s.1.1)))?;
        let fitted = Self { sx, ox, sy, oy };
        let fine = |s: f32, o: f32, extent: f32| {
            s.is_finite()
                && o.is_finite()
                && (s - 1.0).abs() <= MAX_STRETCH
                && o.abs() <= MAX_SHIFT * extent
        };
        (fine(sx, ox, size.0) && fine(sy, oy, size.1)).then_some(fitted)
    }

    /// The saved text: four numbers on one line.
    pub fn to_text(&self) -> String {
        format!("{:.6},{:.4},{:.6},{:.4}\n", self.sx, self.ox, self.sy, self.oy)
    }

    /// The saved text back. Anything unreadable or out of range is no correction.
    pub fn parse(text: &str) -> Self {
        let n: Vec<f32> = text
            .trim()
            .split(',')
            .filter_map(|v| v.trim().parse().ok())
            .collect();
        match n.as_slice() {
            [sx, ox, sy, oy]
                if [sx, ox, sy, oy].iter().all(|v| v.is_finite())
                    && (sx - 1.0).abs() <= MAX_STRETCH
                    && (sy - 1.0).abs() <= MAX_STRETCH
                    && ox.abs() <= 400.0
                    && oy.abs() <= 400.0 =>
            {
                Self {
                    sx: *sx,
                    ox: *ox,
                    sy: *sy,
                    oy: *oy,
                }
            }
            _ => Self::IDENTITY,
        }
    }
}

/// The target in pixels for target `i` on a screen of `size`.
pub fn target(i: usize, size: (f32, f32)) -> (f32, f32) {
    let t = TARGETS[i.min(TARGETS.len() - 1)];
    (t.0 * size.0, t.1 * size.1)
}

/// Least squares for `y = s * x + o` over `(x, y)` pairs. `None` if all `x` are the same.
fn line(pairs: impl Iterator<Item = (f32, f32)>) -> Option<(f32, f32)> {
    let (mut n, mut sx, mut sy, mut sxx, mut sxy) = (0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64);
    for (x, y) in pairs {
        let (x, y) = (f64::from(x), f64::from(y));
        n += 1.0;
        sx += x;
        sy += y;
        sxx += x * x;
        sxy += x * y;
    }
    let d = n * sxx - sx * sx;
    // The taps must differ along the axis, or no stretch can be read from them.
    if n < 2.0 || d.abs() < 1e-6 * n * n.max(1.0) {
        return None;
    }
    let s = (n * sxy - sx * sy) / d;
    let o = (sy - s * sx) / n;
    Some((s as f32, o as f32))
}

#[cfg(test)]
mod tests {
    use super::*;

    const PHONE: (f32, f32) = (2532.0, 1170.0);

    /// What the finger reported for each target, given a made-up error.
    fn taps(error: impl Fn((f32, f32)) -> (f32, f32)) -> Vec<((f32, f32), (f32, f32))> {
        (0..TARGETS.len())
            .map(|i| {
                let t = target(i, PHONE);
                (error(t), t)
            })
            .collect()
    }

    fn close(a: (f32, f32), b: (f32, f32), tol: f32) -> bool {
        (a.0 - b.0).abs() <= tol && (a.1 - b.1).abs() <= tol
    }

    #[test]
    fn exact_taps_need_no_correction() {
        let c = Calibration::fit(&taps(|t| t), PHONE).unwrap();
        assert!((c.sx - 1.0).abs() < 1e-4 && (c.sy - 1.0).abs() < 1e-4, "{c:?}");
        assert!(c.ox.abs() < 0.05 && c.oy.abs() < 0.05, "{c:?}");
    }

    #[test]
    fn a_pull_toward_the_centre_is_undone() {
        // The reported report: far left lands a little right, far right a little left. Here 3%
        // toward the centre, which is 38 px at the far left of an iPhone 12.
        let centre = (PHONE.0 / 2.0, PHONE.1 / 2.0);
        let pulled = |t: (f32, f32)| {
            (
                centre.0 + (t.0 - centre.0) * 0.97,
                centre.1 + (t.1 - centre.1) * 0.97,
            )
        };
        let c = Calibration::fit(&taps(pulled), PHONE).unwrap();
        for i in 0..TARGETS.len() {
            let t = target(i, PHONE);
            assert!(close(c.apply(pulled(t)), t, 0.5), "target {i}: {c:?}");
        }
        // Also at a point that was not a target.
        let p = (60.0, 1100.0);
        assert!(close(c.apply(pulled(p)), p, 0.5));
        assert!(c.sx > 1.0, "the stretch grows the touch back out: {c:?}");
    }

    #[test]
    fn a_plain_shift_is_undone_too() {
        let shifted = |t: (f32, f32)| (t.0 + 14.0, t.1 - 9.0);
        let c = Calibration::fit(&taps(shifted), PHONE).unwrap();
        assert!((c.sx - 1.0).abs() < 1e-4);
        assert!(close(c.apply(shifted((500.0, 500.0))), (500.0, 500.0), 0.05));
    }

    #[test]
    fn the_two_axes_are_fitted_separately() {
        let odd = |t: (f32, f32)| (t.0 * 1.02 + 5.0, t.1 * 0.98 - 3.0);
        let c = Calibration::fit(&taps(odd), PHONE).unwrap();
        for i in 0..TARGETS.len() {
            let t = target(i, PHONE);
            assert!(close(c.apply(odd(t)), t, 0.5));
        }
    }

    #[test]
    fn tap_noise_is_averaged_not_copied() {
        // A few pixels of wobble on each tap: the fit stays close to the truth.
        let wobble = [(2.0, -1.0), (-3.0, 2.0), (1.0, 3.0), (-2.0, -2.0), (0.0, 1.0)];
        let samples: Vec<_> = (0..5)
            .map(|i| {
                let t = target(i, PHONE);
                ((t.0 + wobble[i].0, t.1 + wobble[i].1), t)
            })
            .collect();
        let c = Calibration::fit(&samples, PHONE).unwrap();
        assert!((c.sx - 1.0).abs() < 0.005 && (c.sy - 1.0).abs() < 0.005, "{c:?}");
    }

    #[test]
    fn too_few_or_bunched_taps_give_nothing() {
        assert!(Calibration::fit(&[], PHONE).is_none());
        let two = &taps(|t| t)[..2];
        assert!(Calibration::fit(two, PHONE).is_none());
        // Every tap at the same spot: nothing to read a stretch from.
        let same: Vec<_> = (0..5).map(|_| ((100.0, 100.0), (100.0, 100.0))).collect();
        assert!(Calibration::fit(&same, PHONE).is_none());
    }

    #[test]
    fn a_missed_target_is_refused_not_applied() {
        // One tap a third of the screen away: not a calibration error, a mistake.
        let mut s = taps(|t| t);
        s[0].0 = (s[0].0.0 + 800.0, s[0].0.1);
        assert!(Calibration::fit(&s, PHONE).is_none());
    }

    #[test]
    fn it_survives_the_file() {
        let c = Calibration {
            sx: 1.031_25,
            ox: -37.5,
            sy: 0.987_5,
            oy: 12.25,
        };
        let back = Calibration::parse(&c.to_text());
        assert!((back.sx - c.sx).abs() < 1e-5 && (back.ox - c.ox).abs() < 1e-3);
        assert!((back.sy - c.sy).abs() < 1e-5 && (back.oy - c.oy).abs() < 1e-3);
    }

    #[test]
    fn a_damaged_file_is_no_correction() {
        for bad in ["", "x", "1,2,3", "1,0,1,0,9", "nan,0,1,0", "5,0,1,0", "1,9999,1,0"] {
            assert_eq!(Calibration::parse(bad), Calibration::IDENTITY, "{bad:?}");
        }
        assert!(Calibration::default().is_identity());
        assert_eq!(Calibration::IDENTITY.apply((10.0, 20.0)), (10.0, 20.0));
    }
}
