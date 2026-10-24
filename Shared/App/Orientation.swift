#if os(iOS)
import UIKit

/// Orientations autorisées, modifiables pendant la lecture (paysage imposé sur iPhone, comme Netflix).
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var mask: UIInterfaceOrientationMask = .allButUpsideDown

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.mask
    }

    /// Téléchargements terminés pendant que l'appli était fermée : iOS la réveille pour les finir.
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        MainActor.assumeIsolated { DownloadManager.shared.backgroundCompletion = completionHandler }
    }
}

enum Orientation {
    /// Impose des orientations et fait tourner l'écran tout de suite.
    static func lock(_ m: UIInterfaceOrientationMask) {
        AppDelegate.mask = m
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        var vc = scene.windows.first(where: \.isKeyWindow)?.rootViewController ?? scene.windows.first?.rootViewController
        while let c = vc {
            c.setNeedsUpdateOfSupportedInterfaceOrientations()
            vc = c.presentedViewController
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: m)) { _ in }
    }

    /// Fin de lecture : retour en portrait, puis toutes les orientations à nouveau permises.
    static func release() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { lock(.allButUpsideDown); return }
        lock(.portrait)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { lock(.allButUpsideDown) }
    }
}
#endif
