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

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("链接：")
                            .frame(width: 56, alignment: .leading)
                            .foregroundColor(.secondary)
                        TextField("http...", text: $urlString)
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
                        LabelledField(label: "显示名称", text: $draft.name)
                        LabelledField(label: "包名", text: $draft.package)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        LabelledField(label: "版本", text: $draft.version)
                        LabelledField(label: "架构", text: $draft.arch)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        LabelledField(label: "功能描述", text: $draft.desc)
                        LabelledField(label: "依赖", text: $draft.depends)
                        LabelledField(label: "分类", text: $draft.section)

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
            .background {
                DocumentPicker(
                    isPresented: $showImporter,
                    onPick: { url in handlePickedURL(url) },
                    onError: { msg in vm.alert(msg) }
                )
            }
        }
    }

    private func handlePickedURL(_ url: URL) {
        let ext = (url.lastPathComponent as NSString).pathExtension.lowercased()
        guard ext == "deb" else {
            vm.alert("请选择 .deb 文件（你选的是 .\(ext.isEmpty ? "未知" : ext)）")
            return
        }
        do {
            // asCopy 模式：URL 已是沙盒内副本，直接读即可
            let data = try Data(contentsOf: url)
            var d = UploadDraft()
            d.debData = data
            d.infer(from: url.lastPathComponent)
            draft = d
            vm.status = "已选择 \(url.lastPathComponent)"
        } catch {
            vm.alert("读取失败：\(error.localizedDescription)")
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

/// 固定标签 + 输入框：标签始终可见，打字也不会消失
struct LabelledField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label + "：")
                .frame(width: 72, alignment: .leading)
                .foregroundColor(.secondary)
                .fixedSize()
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
        }
    }
}
