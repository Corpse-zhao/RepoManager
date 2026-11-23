import SwiftUI

@main
struct RepoManagerApp: App {
    @StateObject private var vm = RepoViewModel()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vm)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var vm: RepoViewModel

    var body: some View {
        Group {
            if vm.config.isValid {
                MainTabView()
            } else {
                SetupView()
            }
        }
        .alert(vm.alertMessage ?? "", isPresented: $vm.showAlert) {
            Button("好", role: .cancel) {}
        }
        .background {
            DocumentPicker(
                isPresented: $vm.isFilePickerPresented,
                onPick: { url in vm.handlePickedFile(url) },
                onError: { msg in
                    vm.isFilePickerPresented = false
                    vm.alert(msg)
                }
            )
        }
        .tint(AppTheme.accent)
        // 通道 1：SwiftUI 标准 URL 接收
        .onOpenURL { url in
            _ = vm.handleIncomingURL(url)
        }
        // 通道 2：AppDelegate 转发（第三方 App 唤醒 / 冷启动更可靠）
        .onReceive(NotificationCenter.default.publisher(for: .incomingFileURL)) { note in
            if let url = note.object as? URL {
                _ = vm.handleIncomingURL(url)
            }
        }
    }
}
