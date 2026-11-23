import UIKit

/// 通过 AppDelegate 接收外部 App（微信 / QQ / 文件）用「其他应用打开」传入的文件 URL。
/// SwiftUI 的 .onOpenURL 有时在第三方 App 唤醒（尤其 App 在后台）时接不到，
/// 这里作为第二条通道，保证文件能被接收。
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        Self.post(url)
        return true
    }

    /// 冷启动场景：App 没运行时被微信用文件唤起，URL 在 launchOptions 里
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if let url = launchOptions?[.url] as? URL {
            // 等 SwiftUI 视图树建立后再发，避免监听方还没注册
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                Self.post(url)
            }
        }
        return true
    }

    private static func post(_ url: URL) {
        NotificationCenter.default.post(name: .incomingFileURL, object: url)
    }
}

extension Notification.Name {
    static let incomingFileURL = Notification.Name("com.corpsezhao.repomanager.incomingFileURL")
}
