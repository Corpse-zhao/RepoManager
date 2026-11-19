import SwiftUI

struct SetupView: View {
    @EnvironmentObject var vm: RepoViewModel
    @State private var token = ""
    @State private var repoInput = ""
    @State private var testing = false
    @State private var bindError: String?
    @State private var bindOK = false

    /// 解析「owner/repo」/ 完整 GitHub URL / Pages 地址 → (owner, repo)
    private func parseRepo(_ raw: String) -> (String, String)? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // 只去掉结尾的 .git（git clone 地址），不能全局替换：
        // 否则 corpse-zhao.github.io 会被误删成 corpse-zhaohub.io，Pages 地址就识别不了
        if s.lowercased().hasSuffix(".git") {
            s = String(s.dropLast(4))
        }
        var parts = s.split(separator: "/").map(String.init)

        // 兼容 GitHub Pages 地址：corpse-zhao.github.io/banli → corpse-zhao / banli
        if let host = parts.first, host.lowercased().hasSuffix(".github.io") {
            let owner = host.replacingOccurrences(of: ".github.io", with: "",
                                                  options: .caseInsensitive)
            guard parts.count >= 2 else { return nil }
            return (owner, parts[1])
        }
        // 兼容 github.com/owner/repo（去掉可能的 github.com 前缀）
        if parts.first?.lowercased() == "github.com" {
            parts = Array(parts.dropFirst())
        }
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1])
    }

    var parsed: (String, String)? { parseRepo(repoInput) }
    var canBind: Bool { !token.isEmpty && parsed != nil && !testing }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("这个 App 用来在手机上管理你的越狱源：看插件、上传 deb、删插件。")
                            .font(.subheadline)
                        Text("绑定只需两样东西，填好后点最下面的「一键绑定」。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Section(header: Text("1 · GitHub Token（必填）")) {
                    SecureField("粘贴 ghp_ 开头的 token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("填什么：GitHub 私人访问令牌，用来读写你的源仓库。\n去哪拿：GitHub 网页 → 头像 → Settings → Developer settings → Personal access tokens → Generate new token (classic) → 只勾 repo → 复制 ghp_ 开头那串。\n只存手机本机，不会上传到别处。")
                        .font(.caption).foregroundColor(.secondary)
                }

                Section(header: Text("2 · 源仓库（必填）")) {
                    TextField("例如 Corpse-zhao/banli", text: $repoInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("填什么：存放越狱源的 GitHub 仓库（里面有 Packages、debs 文件夹的那个）。\n三种写法任选一种粘贴：")
                        .font(.caption).foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("• 用户名/仓库名：Corpse-zhao/banli")
                        Text("• 完整链接：https://github.com/Corpse-zhao/banli")
                        Text("• 源地址：https://corpse-zhao.github.io/banli/")
                    }
                    .font(.caption).foregroundColor(.secondary)
                    if let p = parsed {
                        Label("识别为：\(p.0)/\(p.1)", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundColor(.green)
                    } else {
                        Label("还没识别到仓库，按上面三种格式之一填", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundColor(.orange)
                    }
                }

                Section {
                    Button {
                        bindError = nil
                        bindOK = false
                        testing = true
                        Task {
                            guard let p = parseRepo(repoInput) else {
                                bindError = "没识别到仓库，请按上面三种格式之一填写「源仓库」。"
                                testing = false
                                return
                            }
                            let cfg = RepoConfig(token: token, owner: p.0, repo: p.1, branch: "main")
                            let err = await vm.verifyBindError(for: cfg)
                            if let e = err {
                                bindError = e
                                vm.config = RepoConfig()
                            } else {
                                vm.config = cfg
                                bindOK = true
                            }
                            testing = false
                        }
                    } label: {
                        HStack {
                            if testing { ProgressView() }
                            Text(testing ? "验证中…" : "一键绑定")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!canBind)

                    // 结果内联显示，不再用弹窗盖住输入框
                    if let e = bindError {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("绑定失败", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red).font(.subheadline.bold())
                            Text(e).font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                    if bindOK {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("绑定成功", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green).font(.subheadline.bold())
                            Text("已连接 \(vm.config.repoFullName)，切到「插件」页就能管理你的源了。")
                                .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("源管理")
        }
    }
}
