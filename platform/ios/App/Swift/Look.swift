import SwiftUI
import UIKit

/// iMC's own look. The colours come from the existing launcher theme so Settings > Look still works,
/// and the glass is ONLY the system's: `glassEffect`, `.glass` and `.glassProminent` on iOS 26 and later,
/// system materials below that. Nothing here draws a glass imitation.
enum Look {
    static var accent: Color { Color(uiColor: HZTheme.accent()) }
    static var onAccent: Color { Color(uiColor: HZTheme.onAccent()) }
    static var danger: Color { Color(uiColor: HZTheme.danger()) }
    static var warning: Color { Color(uiColor: HZTheme.warning()) }
    static var background: Color { Color(uiColor: HZTheme.background()) }
}

/// A faint grid of squares, like a block world seen from above. It gives the glass something to refract:
/// glass over a flat colour looks like a flat slab, which is what the earlier attempts showed.
struct BlockGrid: View {
    var cell: CGFloat = 34
    var body: some View {
        Canvas { ctx, size in
            let cols = Int(size.width / cell) + 1, rows = Int(size.height / cell) + 1
            for r in 0..<rows {
                for c in 0..<cols {
                    // A fixed pseudo-random pattern (no animation, no state): the same picture every time.
                    let h = (r &* 73856093) ^ (c &* 19349663)
                    let v = Double(abs(h) % 100) / 100
                    guard v > 0.55 else { continue }
                    let rect = CGRect(x: CGFloat(c) * cell + 1.5, y: CGFloat(r) * cell + 1.5, width: cell - 3, height: cell - 3)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(Look.accent.opacity(0.05 + (v - 0.55) * 0.35)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The screen behind every tab: the theme background with a wash of the accent and the block grid.
struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Look.background
            LinearGradient(colors: [Look.accent.opacity(scheme == .dark ? 0.32 : 0.22), .clear],
                           startPoint: .topLeading, endPoint: .center)
            BlockGrid().mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// System Liquid Glass on iOS 26 and later; the system's own material before that.
    @ViewBuilder func glassCard(cornerRadius: CGFloat = 28) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
    @ViewBuilder func primaryAction() -> some View {
        if #available(iOS 26.0, *) { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.borderedProminent) }
    }
    @ViewBuilder func secondaryAction() -> some View {
        if #available(iOS 26.0, *) { self.buttonStyle(.glass) } else { self.buttonStyle(.bordered) }
    }
}

extension View {
    /// A round button. `buttonBorderShape(.circle)` needs iOS 17; the deployment target is 16, so before that the
    /// button keeps the system's default shape.
    @ViewBuilder func circleShape() -> some View {
        if #available(iOS 17.0, *) { self.buttonBorderShape(.circle) } else { self }
    }
}
