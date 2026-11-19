import SwiftUI
import UniformTypeIdentifiers

struct IPAView: View {
    @EnvironmentObject var vm: RepoViewModel
    @State private var showImporter = false
    @State private var pendingURL: URL?
    @State private var pendingName = ""
    @State private var pendingSize = ""
    @State private var deleteTarget: String?
    @State private var copied: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("备份 IPA"), footer: Text(
                    "把 IPA 文件存到你的源仓库 ipas/ 目录，作为备份留着。只是在仓库里存文件，不会加入越狱源索引，也不影响 Sileo。单个 IPA 上限 99MB。"
                )) {
                    Button {
                        showImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("从「文件」App 选择 IPA")
                        }
                    }

                    if !pendingName.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("待上传：\(pendingName)").font(.subheadline.bold())
                            Text(pendingSize).font(.caption).foregroundColor(.secondary)
                            Button {
                                guard let url = pendingURL else { return }
                                let accessing = url.startAccessingSecurityScopedResource()
                                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                                if let data = try? Data(contentsOf: url) {
                                    Task {
                                        let ok = await vm.uploadIPA(fileName: pendingName, data: data)
                                        if ok { clearPending() }
                                    }
                                } else {
                                    vm.alert("读取 IPA 失败")
                                }
                            } label: {
                                HStack {
                                    if vm.isBusy { ProgressView() }
                                    Text("上传到仓库备份")
                                }
                            }
                            .disabled(vm.isBusy)

                            Text("上传后可在下方「已备份」列表里看到，需要时装到巨魔或下载回来。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("已备份 IPA")) {
                    if vm.ipaFiles.isEmpty {
                        Text("还没有备份。点上面按钮选择 IPA 上传。")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(vm.ipaFiles, id: \.self) { name in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "app.badge")
                                    Text(name).font(.subheadline)
                                    Spacer()
                                    Button(role: .destructive) {
                                        deleteTarget = name
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                                Button {
                                    UIPasteboard.general.string = vm.ipaDownloadURL(name)
                                    copied = name
                                } label: {
                                    Label("复制下载/安装地址", systemImage: "doc.on.doc")
                                        .font(.caption)
                                }
                                if copied == name {
                                    Text("已复制。用巨魔打开这个链接，或用浏览器下载。")
                                        .font(.caption2).foregroundColor(.green)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("IPA 备份")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await vm.loadIPAs() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.disabled(vm.isBusy)
                }
            }
            .refreshable { await vm.loadIPAs() }
            .task { await vm.loadIPAs() }
            .alert(vm.alertMessage ?? "", isPresented: $vm.showAlert) {
                Button("好", role: .cancel) {}
            }
            .alert("确认删除", isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )) {
                Button("取消", role: .cancel) { deleteTarget = nil }
                Button("删除", role: .destructive) {
                    if let t = deleteTarget {
                        Task { _ = await vm.deleteIPA(t) }
                    }
                    deleteTarget = nil
                }
            } message: {
                if let t = deleteTarget {
                    Text("确定删除备份「\(t)」？仓库里的 IPA 文件会被移除，不可撤销。")
                }
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
        guard ext == "ipa" else {
            vm.alert("请选择 .ipa 文件（你选的是 .\(ext.isEmpty ? "未知" : ext)）")
            return
        }
        do {
            // asCopy 模式：URL 已是沙盒内副本，直接读即可
            let data = try Data(contentsOf: url)
            pendingURL = url
            pendingName = url.lastPathComponent
            pendingSize = "大小：\(formatSize(data.count))"
            vm.status = "已选择 \(url.lastPathComponent)"
        } catch {
            vm.alert("读取失败：\(error.localizedDescription)")
        }
    }

    private func clearPending() {
        pendingURL = nil
        pendingName = ""
        pendingSize = ""
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}
