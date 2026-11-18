import SwiftUI
import UniformTypeIdentifiers

struct UploadView: View {
    @EnvironmentObject var vm: RepoViewModel
    @State private var draft = UploadDraft()
    @State private var showImporter = false
    @State private var urlString = ""
    @State private var downloading = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("选择 deb 来源")) {
                    Button {
                        showImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text("从「文件」App 导入 deb")
                        }
                    }
                    .fileImporter(
                        isPresented: $showImporter,
                        allowedContentTypes: [UTType(filenameExtension: "deb") ?? .data],
                        allowsMultipleSelection: false
                    ) { result in
                        handleImport(result)
                    }

                    HStack {
                        TextField("或粘贴 deb 下载链接 (http...)", text: $urlString)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Button(downloading ? "…" : "拉取") {
                            downloadFromURL()
                        }
                        .disabled(urlString.isEmpty || downloading)
                    }
                }

                if !draft.fileName.isEmpty {
                    Section(header: Text("已选择：\(draft.fileName)")) {
                        TextField("显示名称", text: $draft.name)
                        TextField("包名 (com.xxx)", text: $draft.package)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("版本", text: $draft.version)
                        TextField("架构", text: $draft.arch)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("功能描述", text: $draft.desc)
                        TextField("依赖", text: $draft.depends)
                        TextField("分类", text: $draft.section)

                        Button {
                            Task {
                                let ok = await vm.upload(draft: draft)
                                if ok { reset() }
                            }
                        } label: {
                            HStack {
                                if vm.isBusy { ProgressView() }
                                Text("上传到源")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(vm.isBusy || draft.package.isEmpty)
                    }
                } else {
                    Section {
                        Text("导入 deb 后会自动从文件名推断包名、版本、架构，可再手动修改。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("上传插件")
            .alert(vm.alertMessage ?? "", isPresented: $vm.showAlert) {
                Button("好", role: .cancel) {}
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                var d = UploadDraft()
                d.debData = data
                d.infer(from: url.lastPathComponent)
                draft = d
            } catch {
                vm.alert("读取失败：\(error.localizedDescription)")
            }
        case .failure(let err):
            vm.alert("导入失败：\(err.localizedDescription)")
        }
    }

    private func downloadFromURL() {
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
            vm.alert("请输入有效的 http/https 链接")
            return
        }
        downloading = true
        Task {
            do {
                let data = try await vm.download(url: url)
                var d = UploadDraft()
                d.debData = data
                let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                d.infer(from: name)
                draft = d
            } catch {
                vm.alert("下载失败：\(error.localizedDescription)")
            }
            downloading = false
        }
    }

    private func reset() {
        draft = UploadDraft()
        urlString = ""
    }
}
