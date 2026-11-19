import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var vm: RepoViewModel

    var body: some View {
        TabView {
            PluginListView()
                .tabItem { Label("插件", systemImage: "square.stack.3d.up") }
                .task { await vm.loadPackages() }

            UploadView()
                .tabItem { Label("上传", systemImage: "arrow.up.bin") }

            IPAView()
                .tabItem { Label("IPA备份", systemImage: "app.badge") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gear") }
        }
        .overlay(alignment: .bottom) {
            if vm.isBusy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(vm.status)
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 70)
            }
        }
    }
}
