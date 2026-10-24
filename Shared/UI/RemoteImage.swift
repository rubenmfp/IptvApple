import SwiftUI
import UIKit

/// Cache des images (affiches) : en mémoire et sur le disque, avec réduction à la taille d'affichage.
final class ImageStore {
    static let shared = ImageStore()

    private let memory = NSCache<NSString, UIImage>()
    private let dir: URL
    private let session: URLSession

    private init() {
        memory.totalCostLimit = 96 * 1024 * 1024
        dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("img", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.httpMaximumConnectionsPerHost = 6
        c.urlCache = nil
        session = URLSession(configuration: c)
    }

    private func file(_ url: String) -> URL {
        // nom de fichier stable tiré de l'adresse (FNV-1a 64 bits)
        var h: UInt64 = 0xcbf29ce484222325
        for b in url.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return dir.appendingPathComponent(String(h, radix: 16))
    }

    func cached(_ url: String, px: Int) -> UIImage? { memory.object(forKey: "\(px)|\(url)" as NSString) }

    func load(_ url: String, px: Int) async -> UIImage? {
        let key = "\(px)|\(url)" as NSString
        if let m = memory.object(forKey: key) { return m }
        let f = file(url)
        var data = try? Data(contentsOf: f)
        if data == nil, let u = URL(string: url) {
            guard let res = try? await session.data(from: u) else { return nil }
            let (d, r) = res
            if let h = r as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { return nil }
            try? d.write(to: f, options: .atomic)
            data = d
        }
        guard let d = data else { return nil }
        let img: UIImage? = await Task.detached(priority: .utility) {
            guard let full = UIImage(data: d) else { return nil }
            let w = CGFloat(px)
            if full.size.width <= w { return full }
            let size = CGSize(width: w, height: (full.size.height * w / full.size.width).rounded())
            return await full.byPreparingThumbnail(ofSize: size) ?? full
        }.value
        if let img { memory.setObject(img, forKey: key, cost: Int(img.size.width * img.size.height * img.scale * img.scale * 4)) }
        return img
    }
}

/// Image chargée depuis une adresse, avec un fond et le titre en attendant (ou si elle manque).
struct RemoteImage: View {
    let url: String?
    let px: Int
    var fallback: String = ""

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.panel
                if !fallback.isEmpty {
                    Text(fallback)
                        .font(Theme.tv ? .headline : .caption)
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                        .padding(8)
                }
            }
        }
        .task(id: url) {
            guard let url, !url.isEmpty else { image = nil; return }
            if let c = ImageStore.shared.cached(url, px: px) { image = c; return }
            image = nil
            image = await ImageStore.shared.load(url, px: px)
        }
    }
}
