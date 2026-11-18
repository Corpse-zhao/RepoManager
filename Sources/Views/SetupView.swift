import SwiftUI

struct SetupView: View {
    @EnvironmentObject var vm: RepoViewModel
    @State private var token = ""
    @State private var owner = ""
    @State private var repo = ""
    @State private var branch = "main"
    @State private var testing = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("绑定你的越狱源"), footer: Text(
                    "在 GitHub 设置 → Developer settings → Personal access tokens 生成 Token，勾选 repo 权限。Token 只保存在本机，不会上传到任何服务器。"
                )) {
                    SecureField("GitHub Token (ghp_...)", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("用户名，如 Corpse-zhao", text: $owner)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("仓库名，如 banli", text: $repo)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("分支", text: $branch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button {
                        testing = true
                        Task {
                            vm.config = RepoConfig(token: token, owner: owner, repo: repo, branch: branch)
                            let ok = await vm.testConnection()
                            testing = false
                            if !ok {
                                vm.config = RepoConfig()   // 验证失败不留配置
                            }
                        }
                    } label: {
                        HStack {
                            if testing { ProgressView() }
                            Text("验证并绑定")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(token.isEmpty || owner.isEmpty || repo.isEmpty || testing)
                }
            }
            .navigationTitle("源管理")
        }
    }
}
