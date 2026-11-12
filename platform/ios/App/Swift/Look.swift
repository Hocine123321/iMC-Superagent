import SwiftUI
import UIKit

// iMC's look. The glass is ONLY the system's: `glassEffect`, `GlassEffectContainer`, `.glass` and `.glassProminent`
// on iOS 26 and later, the system's own materials before that. Nothing here draws a glass imitation.

// MARK: - The ground behind every screen

/// A faint grid of squares, like a block world seen from above, tinted blue and red. It gives the glass something
/// to refract: glass over a flat colour looks like a flat slab.
struct BlockGrid: View {
    var cell: CGFloat = 36
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2

    var body: some View {
        // The squares are drawn once into a bitmap and the bitmap is what every screen shows. The first version ran
        // a Canvas (hundreds of rounded rectangles, each with its own colour) every time a screen was built, and
        // each tab and pushed page has its own backdrop, so the same picture was redrawn again and again.
        GeometryReader { geo in
            if let image = BlockGridCache.image(size: geo.size, cell: cell, brand: brand, brand2: brand2) {
                Image(uiImage: image).resizable().frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Keeps the last picture for each size and pair of colours, so it is drawn once.
enum BlockGridCache {
    private static var key = ""
    private static var cached: UIImage?

    static func image(size: CGSize, cell: CGFloat, brand: Color, brand2: Color) -> UIImage? {
        guard size.width > 1, size.height > 1 else { return nil }
        let a = UIColor(brand), b = UIColor(brand2)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let k = "\(Int(size.width))x\(Int(size.height))/\(cell)/\(r1),\(g1),\(b1)/\(r2),\(g2),\(b2)"
        if k == key, let cached { return cached }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { rc in
            let ctx = rc.cgContext
            let cols = Int(size.width / cell) + 1, rows = Int(size.height / cell) + 1
            for r in 0..<rows {
                for col in 0..<cols {
                    // A fixed pseudo-random pattern (no animation, no state): the same picture every time.
                    let h = (r &* 73856093) ^ (col &* 19349663)
                    let v = Double(abs(h % 1000)) / 1000
                    guard v > 0.58 else { continue }
                    let rect = CGRect(x: CGFloat(col) * cell + 2, y: CGFloat(r) * cell + 2, width: cell - 4, height: cell - 4)
                    let colour = (h & 4) == 0 ? a : b
                    ctx.setFillColor(colour.withAlphaComponent(0.05 + (v - 0.58) * 0.30).cgColor)
                    ctx.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 6).cgPath)
                    ctx.fillPath()
                }
            }
        }
        key = k
        cached = image
        return image
    }
}

/// Navy at the top, wine at the bottom, a blue glow and a red glow in the corners, and the block grid fading out
/// downwards. "Colour balance" in Settings moves the mix; "Backdrop colour" sets how strong it is.
struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        let strength = prefs.intensity * 2                       // 1 at the default
        let base = scheme == .dark ? 0.50 : 0.30
        // Balance 0 is all brand, 1 is all the other one; the middle is an even mix.
        let a1 = min(0.95, base * strength * min(1.4, 2 * (1 - prefs.balance)))
        let a2 = min(0.95, base * strength * min(1.4, 2 * prefs.balance))
        ZStack {
            LinearGradient(colors: [Palette.ink, Palette.wine], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [brand.opacity(a1), .clear], center: .topLeading, startRadius: 0, endRadius: 560)
            RadialGradient(colors: [brand2.opacity(a2), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 620)
            BlockGrid().mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
    }
}

// MARK: - System glass

@available(iOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

extension View {
    /// A card of system Liquid Glass on iOS 26 and later; the system's material before that.
    @ViewBuilder func glassCard(cornerRadius: CGFloat = 26, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive), in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.white.opacity(0.10)))
        }
    }

    /// The same in a capsule: chips, small status pills.
    @ViewBuilder func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive), in: Capsule())
        } else {
            self.background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10)))
        }
    }

    @ViewBuilder func glassCircle(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive), in: Circle())
        } else {
            self.background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10)))
        }
    }

    @ViewBuilder func primaryAction() -> some View {
        if #available(iOS 26.0, *) { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.borderedProminent) }
    }

    @ViewBuilder func secondaryAction() -> some View {
        if #available(iOS 26.0, *) { self.buttonStyle(.glass) } else { self.buttonStyle(.bordered) }
    }

    /// A round button. `buttonBorderShape(.circle)` needs iOS 17; the deployment target is 16.
    @ViewBuilder func circleShape() -> some View {
        if #available(iOS 17.0, *) { self.buttonBorderShape(.circle) } else { self }
    }

    /// The scroll content of a screen: the backdrop behind it, side margins and room under the tab bar.
    func screenBackground() -> some View {
        self.background(Backdrop())
    }
}

/// Groups nearby glass so the system can blend and morph it as one piece (iOS 26); a plain container before that.
struct GlassStack<Content: View>: View {
    var spacing: CGFloat
    let content: Content
    init(spacing: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Building blocks

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.footnote.weight(.semibold)).tracking(1.1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One glass card holding rows. Put `Sep()` between rows.
struct GlassGroup<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 24)
    }
}

/// The thin line between two rows, starting under the text (after the icon tile).
struct Sep: View {
    var inset: CGFloat = 62
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 0.5).padding(.leading, inset)
    }
}

/// A rounded square with a symbol on a blue or red gradient: the icon of a row.
struct IconTile: View {
    enum Tone { case brand, brand2, neutral, ok, warn }
    let symbol: String
    var tone: Tone = .brand
    var size: CGFloat = 34
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2

    private var colours: [Color] {
        switch tone {
        case .brand: return [brand, Palette.blueDeep.opacity(0.9)]
        case .brand2: return [brand2, Palette.redDeep.opacity(0.9)]
        case .neutral: return [Color.gray, Color.gray.opacity(0.7)]
        case .ok: return [Palette.ok, Palette.ok.opacity(0.7)]
        case .warn: return [Palette.warn, Palette.warn.opacity(0.7)]
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: colours, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The label of a row that opens something: icon tile, title, a grey line, a chevron.
struct RowLabel: View {
    let symbol: String
    var tone: IconTile.Tone = .brand
    let title: String
    var detail: String? = nil
    var value: String? = nil
    var chevron = true

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, tone: tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let value { Text(value).font(.subheadline).foregroundStyle(.secondary) }
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// A switch row.
struct ToggleRow: View {
    let symbol: String
    var tone: IconTile.Tone = .brand
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, tone: tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// A small coloured dot with a word: the state of something.
struct StatusPill: View {
    enum Kind { case ok, warn, bad, info }
    let kind: Kind
    let text: String
    private var colour: Color {
        switch kind {
        case .ok: return Palette.ok
        case .warn: return Palette.warn
        case .bad: return Palette.red
        case .info: return Palette.blue
        }
    }
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(colour).frame(width: 8, height: 8)
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .glassCapsule()
    }
}

/// A bar that fills from blue to red.
struct MixBar: View {
    let fraction: Double
    var height: CGFloat = 10
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [brand, brand2], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, g.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: height)
        .accessibilityValue("\(Int((min(1, max(0, fraction)) * 100).rounded())) percent")
    }
}

/// Long text (logs, licences) in pieces, so only what is on screen is laid out.
struct LongText: View {
    let text: String
    var font: Font = .system(size: 11, design: .monospaced)
    var linesPerChunk = 40

    private var chunks: [String] {
        let lines = text.components(separatedBy: "\n")
        return stride(from: 0, to: lines.count, by: linesPerChunk).map {
            lines[$0..<min($0 + linesPerChunk, lines.count)].joined(separator: "\n")
        }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                Text(chunk).font(font).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - The mark

/// The app's mark: an isometric block, blue on one side and red on the other, with a bright top. Drawn in code so it
/// is the same picture as the app icon (tools/make_app_icon.py) at any size.
struct BrandMark: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let r = s * 0.5, h = r * 0.8660254
            let cx = g.size.width / 2, cy = g.size.height / 2
            let t = CGPoint(x: cx, y: cy - r), tr = CGPoint(x: cx + h, y: cy - r / 2), br = CGPoint(x: cx + h, y: cy + r / 2)
            let b = CGPoint(x: cx, y: cy + r), bl = CGPoint(x: cx - h, y: cy + r / 2), tl = CGPoint(x: cx - h, y: cy - r / 2)
            let c = CGPoint(x: cx, y: cy)
            ZStack {
                Path { p in p.move(to: tl); p.addLine(to: c); p.addLine(to: b); p.addLine(to: bl); p.closeSubpath() }
                    .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.47, blue: 1.0), Color(red: 0.10, green: 0.22, blue: 0.70)],
                                         startPoint: .top, endPoint: .bottom))
                Path { p in p.move(to: c); p.addLine(to: tr); p.addLine(to: br); p.addLine(to: b); p.closeSubpath() }
                    .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.32, blue: 0.38), Color(red: 0.66, green: 0.08, blue: 0.20)],
                                         startPoint: .top, endPoint: .bottom))
                Path { p in p.move(to: t); p.addLine(to: tr); p.addLine(to: c); p.addLine(to: tl); p.closeSubpath() }
                    .fill(LinearGradient(colors: [Color.white, Color(red: 0.78, green: 0.86, blue: 1.0)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    p.move(to: tl); p.addLine(to: c); p.addLine(to: tr)
                    p.move(to: c); p.addLine(to: b)
                }
                .stroke(Color.white.opacity(0.55), lineWidth: max(1, s * 0.012))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
