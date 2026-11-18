import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: RepoViewModel
    @State private var showUnbind = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("已绑定仓库")) {
                    InfoRow(title: "仓库", value: vm.config.repoFullName)
                    InfoRow(title: "分支", value: vm.config.branch)
                    InfoRow(title: "源地址", value: vm.config.pagesBase)
                    InfoRow(title: "Token", value: "\(vm.config.token.prefix(7))…（已隐藏）")
                }

                Section(header: Text("操作"), footer: Text("重新绑定可换用其他 GitHub 账号或仓库。")) {
                    Button("测试连接") {
                        Task { _ = await vm.testConnection() }
                    }
                    Button("重新绑定", role: .destructive) {
                        showUnbind = true
                    }
                }

                Section(header: Text("关于")) {
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
    var body: some View {
        HStack {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}
