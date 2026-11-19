import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: RepoViewModel
    @State private var showUnbind = false

    private var appVersion: String {
        let b = Bundle.main
        let v = b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = b.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(build))"
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 13).fill(AppTheme.accentGradient)
                            Image(systemName: "server.rack")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(vm.config.repo.isEmpty ? "未绑定" : vm.config.repo)
                                .font(.headline)
                            Text("\(vm.config.owner) · \(vm.config.branch)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("仓库信息")) {
                    InfoRow(title: "源地址", value: vm.config.pagesBase, icon: "link")
                    InfoRow(title: "Token", value: "\(vm.config.token.prefix(7))…（已隐藏）", icon: "key.fill")
                }

                Section(header: Text("操作"), footer: Text("重新绑定可换用其他 GitHub 账号或仓库。")) {
                    Button {
                        Task { _ = await vm.testConnection() }
                    } label: {
                        Label("测试连接", systemImage: "bolt.fill")
                    }
                    Button(role: .destructive) {
                        showUnbind = true
                    } label: {
                        Label("重新绑定", systemImage: "arrow.triangle.branch")
                    }
                }

                Section(header: Text("关于")) {
                    InfoRow(title: "版本", value: appVersion)
                    Text("RepoManager · 在手机上管理你的越狱源：查看、上传、删除插件，自动重建 Packages 索引与 Sileo 图文页。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
            .alert("解除绑定", isPresented: $showUnbind) {
                Button("取消", role: .cancel) {}
                Button("解除", role: .destructive) {
                    vm.config = RepoConfig()
                }
            } message: {
                Text("清除本机的 Token 与仓库配置？仓库里的文件不会受影响。")
            }
            .alert(vm.alertMessage ?? "", isPresented: $vm.showAlert) {
                Button("好", role: .cancel) {}
            }
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(AppTheme.accent)
                    .frame(width: 20)
            }
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(title == "源地址" ? AppTheme.accent : .primary)
                .textSelection(.enabled)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}
