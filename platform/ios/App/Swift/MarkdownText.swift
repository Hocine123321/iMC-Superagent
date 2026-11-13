import SwiftUI

/// A small Markdown reader for project descriptions. Authors write Markdown with HTML mixed in (badges, centred images,
/// line breaks); this keeps what reads well as text (headings, paragraphs, lists, quotes, code, emphasis, links) and drops
/// the rest (images, tags, comments), so a long description is a clean column of text rather than a wall of markup.
enum MarkdownLite {
    enum Block {
        case heading(Int, String)
        case paragraph(String)
        case bullet(Int, String)
        case numbered(String, String)
        case quote(String)
        case code(String)
        case rule

        /// Characters of text in the block, for deciding where a collapsed description ends.
        var length: Int {
            switch self {
            case .heading(_, let t), .paragraph(let t), .bullet(_, let t), .numbered(_, let t), .quote(let t), .code(let t): return t.count
            case .rule: return 0
            }
        }

        func truncated(to limit: Int) -> Block {
            func cut(_ t: String) -> String { t.count > limit ? String(t.prefix(limit)).trimmingCharacters(in: .whitespaces) + "..." : t }
            switch self {
            case .heading(let l, let t): return .heading(l, cut(t))
            case .paragraph(let t): return .paragraph(cut(t))
            case .bullet(let l, let t): return .bullet(l, cut(t))
            case .numbered(let n, let t): return .numbered(n, cut(t))
            case .quote(let t): return .quote(cut(t))
            case .code(let t): return .code(cut(t))
            case .rule: return self
            }
        }
    }

    private static var memo: [Int: [Block]] = [:]

    static func releaseMemo() { memo.removeAll() }

    /// Parsed once per text: a page that redraws while a download moves must not parse sixty thousand characters again.
    static func parse(_ source: String) -> [Block] {
        let key = source.hashValue
        if let hit = memo[key] { return hit }
        let blocks = build(clean(source))
        if memo.count > 6 { memo.removeAll() }
        memo[key] = blocks
        return blocks
    }

    static func clean(_ source: String) -> String {
        var t = source.replacingOccurrences(of: "\r\n", with: "\n")
        func sub(_ pattern: String, _ with: String, options: NSString.CompareOptions = []) {
            t = t.replacingOccurrences(of: pattern, with: with, options: options.union(.regularExpression))
        }
        sub("(?s)<!--.*?-->", "")
        sub("<br\\s*/?>", "\n", options: .caseInsensitive)
        sub("</(p|div|h[1-6]|li|tr)>", "\n\n", options: .caseInsensitive)
        sub("<[^>]+>", "")
        sub("!\\[[^\\]]*\\]\\([^)]*\\)", "")          // images
        sub("\\[\\s*\\]\\([^)]*\\)", "")                // links that wrapped an image and have no text left
        for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            t = t.replacingOccurrences(of: entity, with: char)
        }
        sub("\\n{3,}", "\n\n")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(_ line: String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: line).map { String(line[$0]) } ?? ""
        }
    }

    private static func build(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]? = nil
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code { blocks.append(.code(c.joined(separator: "\n"))); code = nil } else { flush(); code = [] }
                continue
            }
            if code != nil { code?.append(raw); continue }
            if line.isEmpty { flush(); continue }
            if let m = firstMatch(line, "^(#{1,6})\\s+(.*)$") { flush(); blocks.append(.heading(m[1].count, m[2])); continue }
            if firstMatch(line, "^(-{3,}|\\*{3,}|_{3,})$") != nil { flush(); blocks.append(.rule); continue }
            if let m = firstMatch(raw, "^(\\s*)[-*+]\\s+(.*)$") { flush(); blocks.append(.bullet(m[1].count / 2, m[2])); continue }
            if let m = firstMatch(raw, "^\\s*(\\d+)[.)]\\s+(.*)$") { flush(); blocks.append(.numbered(m[1], m[2])); continue }
            if let m = firstMatch(line, "^>\\s?(.*)$") { flush(); blocks.append(.quote(m[1])); continue }
            paragraph.append(line)
        }
        flush()
        if let c = code, !c.isEmpty { blocks.append(.code(c.joined(separator: "\n"))) }
        return blocks
    }

    /// The first blocks that fit in `limit` characters (the first one cut if it alone is longer), and whether anything was left out.
    static func preview(_ blocks: [Block], limit: Int) -> (shown: [Block], cut: Bool) {
        var total = 0
        var shown: [Block] = []
        for b in blocks {
            if total + b.length > limit {
                if shown.isEmpty { shown.append(b.truncated(to: limit)) }
                return (shown, true)
            }
            shown.append(b)
            total += b.length
        }
        return (shown, false)
    }
}

/// The blocks as text.
struct MarkdownView: View {
    let blocks: [MarkdownLite.Block]

    private func inline(_ s: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let a = try? AttributedString(markdown: s, options: options) { return Text(a) }
        return Text(s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let t):
                    inline(t).font(level <= 1 ? .title3.weight(.bold) : level == 2 ? .headline : .subheadline.weight(.semibold)).padding(.top, 4)
                case .paragraph(let t):
                    inline(t).font(.subheadline).foregroundStyle(.secondary)
                case .bullet(let level, let t):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\u{2022}").foregroundStyle(.secondary)
                        inline(t).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.leading, CGFloat(level) * 14)
                case .numbered(let n, let t):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(n).").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        inline(t).font(.subheadline).foregroundStyle(.secondary)
                    }
                case .quote(let t):
                    HStack(spacing: 10) {
                        Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 3)
                        inline(t).font(.subheadline.italic()).foregroundStyle(.secondary)
                    }
                case .code(let t):
                    Text(t).font(.system(size: 12, design: .monospaced)).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                case .rule:
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A titled card of long text that shows its first part and an Expand button when there is more.
struct DescriptionCard: View {
    let title: String
    let source: String
    var loading = false
    var limit = 650
    @State private var expanded = false
    @Environment(\.brand) private var brand

    var body: some View {
        let blocks = MarkdownLite.parse(source)
        let (shown, cut) = MarkdownLite.preview(blocks, limit: limit)
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if blocks.isEmpty {
                if loading { HStack(spacing: 8) { ProgressView(); Text("Loading...").font(.subheadline).foregroundStyle(.secondary) } }
            } else {
                MarkdownView(blocks: expanded ? blocks : shown)
                    .mask {
                        if cut && !expanded {
                            LinearGradient(stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                        } else {
                            Color.black
                        }
                    }
                if cut {
                    Button { Haptics.select(); withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                        Label(expanded ? "Show less" : "Expand", systemImage: expanded ? "chevron.up" : "chevron.down")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .secondaryAction()
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 24)
    }
}
