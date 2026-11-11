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

    static func head(uuid: String) async -> UIImage? {
        let id = uuid.replacingOccurrences(of: "-", with: "").lowercased()
        guard isHex32(id) else { return nil }
        let file = cacheDirectory.appendingPathComponent("\(id).png")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let date = attrs[.modificationDate] as? Date, Date().timeIntervalSince(date) < 86_400,
           let data = try? Data(contentsOf: file), let img = UIImage(data: data) { return img }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        let session = URLSession(configuration: config)
        do {
            guard let profileURL = URL(string: "https://sessionserver.mojang.com/session/minecraft/profile/\(id)") else { return nil }
            let (profileData, response) = try await session.data(from: profileURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: profileData) as? [String: Any],
                  let props = json["properties"] as? [[String: Any]],
                  let value = props.first(where: { ($0["name"] as? String) == "textures" })?["value"] as? String,
                  let decoded = Data(base64Encoded: value),
                  let tex = try JSONSerialization.jsonObject(with: decoded) as? [String: Any],
                  let skin = (tex["textures"] as? [String: Any])?["SKIN"] as? [String: Any],
                  let skinText = skin["url"] as? String,
                  let skinURL = URL(string: skinText),
                  // The address came out of a reply: only Mojang's texture server is asked for the picture.
                  skinURL.scheme == "https", skinURL.host == "textures.minecraft.net" else { return nil }
            let (png, resp2) = try await session.data(from: skinURL)
            guard (resp2 as? HTTPURLResponse)?.statusCode == 200, png.count < 262_144,
                  let image = UIImage(data: png), let cg = image.cgImage,
                  cg.width == 64, cg.height == 64 || cg.height == 32 else { return nil }
            guard let face = cg.cropping(to: CGRect(x: 8, y: 8, width: 8, height: 8)),
                  let hat = cg.cropping(to: CGRect(x: 40, y: 8, width: 8, height: 8)) else { return nil }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let head = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { ctx in
                ctx.cgContext.interpolationQuality = .none
                UIImage(cgImage: face).draw(in: CGRect(x: 0, y: 0, width: 8, height: 8))
                UIImage(cgImage: hat).draw(in: CGRect(x: 0, y: 0, width: 8, height: 8))
            }
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? head.pngData()?.write(to: file, options: .atomic)
            return head
        } catch {
            return nil
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
        }
        .accessibilityHidden(true)
    }
}
