import SwiftUI
import UIKit

/// The player's head, cut from their skin. The skin comes from Mojang's own servers (the profile on
/// sessionserver.mojang.com names the picture, the picture is on textures.minecraft.net): the same company that
/// already answers the sign-in, and nobody else. The finished 8x8 head is cached on the phone for a day.
/// Settings > Game > "Show my Minecraft head" turns it off, and then nothing extra is requested.
enum SkinService {
    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("heads", isDirectory: true)
    }

    private static func isHex32(_ s: String) -> Bool {
        s.count == 32 && s.allSatisfy { $0.isHexDigit }
    }

    /// Why the last attempt gave no head, in words, for the Account page (nil after a success).
    static var lastProblem: String? = nil

    private static func fail(_ why: String, stale: UIImage?) -> UIImage? {
        lastProblem = stale == nil ? why : nil          // an older head is better than none
        return stale
    }

    static func head(uuid: String) async -> UIImage? {
        let id = uuid.replacingOccurrences(of: "-", with: "").lowercased()
        guard isHex32(id) else { lastProblem = "The profile ID is not a valid UUID."; return nil }
        let file = cacheDirectory.appendingPathComponent("\(id).png")
        var stale: UIImage? = nil
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let date = attrs[.modificationDate] as? Date,
           let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            if Date().timeIntervalSince(date) < 86_400 { lastProblem = nil; return img }
            stale = img
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        let session = URLSession(configuration: config)
        do {
            guard let profileURL = URL(string: "https://sessionserver.mojang.com/session/minecraft/profile/\(id)") else { return fail("Bad profile address.", stale: stale) }
            let (profileData, response) = try await session.data(from: profileURL)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 429 { return fail("Mojang asks to slow down (it allows one profile lookup a minute). Try again shortly.", stale: stale) }
            guard code == 200 else { return fail("Mojang's profile server answered \(code).", stale: stale) }
            guard let json = try JSONSerialization.jsonObject(with: profileData) as? [String: Any],
                  let props = json["properties"] as? [[String: Any]],
                  let value = props.first(where: { ($0["name"] as? String) == "textures" })?["value"] as? String,
                  let decoded = Data(base64Encoded: value) ?? Data(base64Encoded: value + String(repeating: "=", count: (4 - value.count % 4) % 4)),
                  let tex = try JSONSerialization.jsonObject(with: decoded) as? [String: Any]
            else { return fail("Mojang's reply had no skin information.", stale: stale) }
            // No SKIN entry means the account has not set a skin: it plays as the default Steve or Alex.
            guard let skin = (tex["textures"] as? [String: Any])?["SKIN"] as? [String: Any], let skinText = skin["url"] as? String
            else { return fail("This account has no custom skin.", stale: stale) }
            // Mojang names its skins with an http address; the same server answers on https, which is what is asked. The
            // address came out of a reply, so only Mojang's texture server is ever contacted.
            guard var parts = URLComponents(string: skinText), let host = parts.host, host == "textures.minecraft.net",
                  parts.scheme == "http" || parts.scheme == "https"
            else { return fail("The skin address was not on Mojang's texture server.", stale: stale) }
            parts.scheme = "https"
            guard let skinURL = parts.url else { return fail("Bad skin address.", stale: stale) }
            let (png, resp2) = try await session.data(from: skinURL)
            guard (resp2 as? HTTPURLResponse)?.statusCode == 200 else { return fail("Mojang's texture server did not send the skin.", stale: stale) }
            guard png.count < 262_144, let image = UIImage(data: png), let cg = image.cgImage,
                  cg.width == 64, cg.height == 64 || cg.height == 32
            else { return fail("The skin file was not a normal 64 by 64 or 64 by 32 picture.", stale: stale) }
            guard let face = cg.cropping(to: CGRect(x: 8, y: 8, width: 8, height: 8)),
                  let hat = cg.cropping(to: CGRect(x: 40, y: 8, width: 8, height: 8)) else { return fail("The skin could not be cropped.", stale: stale) }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let head = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { ctx in
                ctx.cgContext.interpolationQuality = .none
                UIImage(cgImage: face).draw(in: CGRect(x: 0, y: 0, width: 8, height: 8))
                UIImage(cgImage: hat).draw(in: CGRect(x: 0, y: 0, width: 8, height: 8))
            }
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? head.pngData()?.write(to: file, options: .atomic)
            lastProblem = nil
            return head
        } catch {
            return fail("Could not reach Mojang: \((error as? URLError)?.localizedDescription ?? error.localizedDescription)", stale: stale)
        }
    }

    static func forget() {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

/// The head, or a plain person symbol while it loads, when it is off, or when Mojang could not be reached.
struct MinecraftHead: View {
    let uuid: String?
    var size: CGFloat = 72
    /// Told why there is no head (nil when there is one), so the Account page can say so.
    var onProblem: ((String?) -> Void)? = nil
    @ObservedObject private var prefs = Prefs.shared
    @State private var image: UIImage? = nil
    @Environment(\.brand) private var brand

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            } else {
                Image(systemName: "person.crop.square.fill").resizable().scaledToFit().foregroundStyle(brand.opacity(0.8))
                    .padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .task(id: "\(uuid ?? "")|\(prefs.showHead)") {
            guard prefs.showHead, let uuid else { image = nil; return }
            image = await SkinService.head(uuid: uuid)
            onProblem?(image == nil ? SkinService.lastProblem : nil)
        }
        .accessibilityHidden(true)
    }
}
