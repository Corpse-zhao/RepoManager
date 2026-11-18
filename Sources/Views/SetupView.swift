import SwiftUI

struct SetupView: View {
    @EnvironmentObject var vm: RepoViewModel
    @State private var token = ""
    @State private var repoInput = "Corpse-zhao/banli"
    @State private var branch = "main"
    @State private var showAdvanced = false
    @State private var testing = false

    /// 解析「owner/repo」或完整 GitHub URL → (owner, repo)
    private func parseRepo(_ raw: String) -> (String, String)? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("https://github.com/") || s.hasPrefix("http://github.com/") {
            s = s.replacingOccurrences(of: "https://github.com/", with: "")
                .replacingOccurrences(of: "http://github.com/", with: "")
        }
        s = s.replacingOccurrences(of: ".git", with: "")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = s.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1])
    }

    var parsed: (String, String)? { parseRepo(repoInput) }
    var canBind: Bool { !token.isEmpty && parsed != nil && !testing }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("1 · 粘贴 Token"), footer: Text(
                    "GitHub → Settings → Developer settings → Personal access tokens → Generate new token (classic)，勾选 repo 权限，复制 ghp_ 开头的串粘到这里。只存本机。"
                )) {
                    SecureField("ghp_xxxxxxxxxxxx", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(header: Text("2 · 确认仓库"), footer: Text(
                    "已默认填好你的源。也可以直接粘贴完整链接，如 https://github.com/Corpse-zhao/banli"
                )) {
                    TextField("用户名/仓库名", text: $repoInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let p = parsed {
                        Label("将绑定 \(p.0)/\(p.1)", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("格式：用户名/仓库名", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Section {
                    DisclosureGroup("高级设置", isExpanded: $showAdvanced) {
                        TextField("分支（默认 main）", text: $branch)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section {
                    Button {
                        testing = true
                        Task {
                            let p = parseRepo(repoInput) ?? ("", "")
                            vm.config = RepoConfig(token: token, owner: p.0, repo: p.1, branch: branch)
                            let ok = await vm.testConnection()
                            testing = false
                            if !ok { vm.config = RepoConfig() }
                        }
                    } label: {
                        HStack {
                            if testing { ProgressView() }
                            Text(testing ? "验证中…" : "一键绑定")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!canBind)
                }
            }
            .navigationTitle("源管理")
        }
    }
}
