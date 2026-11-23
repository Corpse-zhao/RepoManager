import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var vm: RepoViewModel
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            PluginListView()
                .tabItem { Label("插件", systemImage: "square.stack.3d.up") }
                .tag(0)
                .task { await vm.loadPackages() }

            UploadView()
                .tabItem { Label("上传", systemImage: "arrow.up.bin") }
                .tag(1)

            IPAView()
                .tabItem { Label("IPA备份", systemImage: "app.badge") }
                .tag(2)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gear") }
                .tag(3)
        }
        .onChange(of: vm.requestedTab) { newTab in
            selection = newTab
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
