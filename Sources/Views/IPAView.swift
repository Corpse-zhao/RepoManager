import SwiftUI
import UniformTypeIdentifiers

struct IPAView: View {
    @EnvironmentObject var vm: RepoViewModel
    @State private var pendingData: Data?
    @State private var pendingName = ""
    @State private var pendingSize = ""
    @State private var pendingNote = ""
    @State private var deleteTarget: String?
    @State private var copied: String?
    @State private var noteTarget: String?
    @State private var noteDraft = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("备份 IPA"), footer: Text(
                    "把 IPA 文件存到你的源仓库 ipas/ 目录，作为备份留着。只是在仓库里存文件，不会加入越狱源索引，也不影响 Sileo。单个 IPA 上限 99MB。"
                )) {
                    Button {
                        vm.requestFile { url in handlePickedURL(url) }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("从「文件」App 选择 IPA")
                        }
                    }

                    if !pendingName.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("待上传：\(pendingName)")
                                        .font(.subheadline.bold())
                                    Text(pendingSize).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer(minLength: 8)
                                // 取消选择：清掉当前文件，重新选
                                Button {
                                    clearPending()
                                    vm.status = "已取消，可重新选择 IPA"
                                } label: {
                                    Text("取消")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.secondary.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(vm.isBusy)
                            }
                            LabelledField(label: "备注", text: $pendingNote, placeholder: "选填，如：备用签名版")
                            Button {
                                guard let data = pendingData else {
                                    vm.alert("IPA 数据已失效，请重新选择文件")
                                    return
                                }
                                Task {
                                    let ok = await vm.uploadIPA(fileName: pendingName, data: data, note: pendingNote)
                                    if ok { clearPending() }
                                }
                            } label: {
                                HStack {
                                    if vm.isBusy { ProgressView() }
                                    Text("上传到仓库备份")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.accent)
                            .disabled(vm.isBusy)

                            Text("上传后可在下方「已备份」列表里看到，需要时装到巨魔或下载回来。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("已备份 IPA")) {
                    if vm.ipaFiles.isEmpty {
                        VStack(spacing: 12) {
                            EmptyStateIcon(symbol: "app.badge")
                            Text("还没有备份")
                                .font(.subheadline.weight(.medium))
                            Text("点上面按钮选择 IPA 上传，留个自用备份")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    } else {
                        ForEach(vm.ipaFiles, id: \.self) { name in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    IconBadge(symbol: "app.badge", color: .blue, side: 34)
                                    Text(name).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Spacer(minLength: 4)
                                    // 编辑备注：独立的点击热区（plain 样式 + 固定 frame 防相邻按钮误触）
                                    Button {
                                        noteDraft = vm.ipaNotes[name] ?? ""
                                        noteTarget = name
                                    } label: {
                                        Image(systemName: "pencil")
                                            .frame(width: 32, height: 32)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    // 删除：独立的点击热区
                                    Button(role: .destructive) {
                                        deleteTarget = name
                                    } label: {
                                        Image(systemName: "trash")
                                            .frame(width: 32, height: 32)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                if let note = vm.ipaNotes[name], !note.isEmpty {
                                    Label(note, systemImage: "note.text")
                                        .font(.caption).foregroundColor(.secondary)
                                } else {
                                    Button {
                                        noteDraft = ""
                                        noteTarget = name
                                    } label: {
                                        Label("添加备注", systemImage: "note.text.badge.plus")
                                            .font(.caption)
                                    }
                                }
                                Button {
                                    UIPasteboard.general.string = vm.ipaDownloadURL(name)
                                    copied = name
                                    let target = name
                                    Task {
                                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                                        if copied == target { copied = nil }
                                    }
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

            // 全局错误提示（唯一保留的 alert）
            .alert(vm.alertMessage ?? "", isPresented: $vm.showAlert) {
                Button("好", role: .cancel) {}
            }

            // 删除确认：改用 confirmationDialog，走独立通道，不再和其它 alert 抢状态
            .confirmationDialog(
                "确认删除",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let t = deleteTarget {
                        Task { _ = await vm.deleteIPA(t) }
                    }
                    deleteTarget = nil
                }
                Button("取消", role: .cancel) { deleteTarget = nil }
            } message: {
                if let t = deleteTarget {
                    Text("确定删除备份「\(t)」？仓库里的 IPA 文件会被移除，不可撤销。")
                }
            }

            // 编辑备注：改用 sheet，弹窗通道彻底分离，点备注不会再误触发删除
            .sheet(isPresented: Binding(
                get: { noteTarget != nil },
                set: { if !$0 { noteTarget = nil } }
            )) {
                IPANoteEditor(name: noteTarget ?? "", draft: $noteDraft) {
                    let t = noteTarget
                    let note = noteDraft
                    if let t = t {
                        Task { _ = await vm.setIPANote(fileName: t, note: note) }
                    }
                }
            }
            // 从微信「用其他应用打开」导入的 IPA：自动预填（onChange + onAppear 双保险）
            .onChange(of: vm.pendingIncoming) { _ in applyIncomingIfNeeded() }
            .onAppear { applyIncomingIfNeeded() }
        }
    }

    private func applyIncomingIfNeeded() {
        guard let incoming = vm.pendingIncoming, incoming.ext == "ipa" else { return }
        applyIncoming(incoming)
        vm.pendingIncoming = nil
    }

    private func handlePickedURL(_ url: URL) {
        let ext = (url.lastPathComponent as NSString).pathExtension.lowercased()
        guard ext == "ipa" else {
            vm.alert("请选择 .ipa 文件（你选的是 .\(ext.isEmpty ? "未知" : ext)）")
            return
        }
        do {
            // 立刻读进内存缓存，上传时不再二次读临时文件（避免 IPA 读到一半失效）
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            pendingData = data
            pendingName = url.lastPathComponent
            pendingSize = "大小：\(formatSize(data.count))"
            vm.status = "已选择 \(url.lastPathComponent)"
        } catch {
            vm.alert("读取失败：\(error.localizedDescription)")
        }
    }

    /// 用已读入内存的文件预填（外部 App 导入用）
    private func applyIncoming(_ incoming: IncomingFile) {
        pendingData = incoming.data
        pendingName = incoming.name
        pendingSize = "大小：\(formatSize(incoming.data.count))"
        vm.status = "已导入 \(incoming.name)，填好备注后点上传"
    }

    private func clearPending() {
        pendingData = nil
        pendingName = ""
        pendingSize = ""
        pendingNote = ""
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}

/// 备注编辑页：用 sheet 呈现，与删除确认完全隔离
struct IPANoteEditor: View {
    let name: String
    @Binding var draft: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(
                    header: Text("备注内容"),
                    footer: Text("给这个备份写点说明，方便以后认出来。留空则清除备注。")
                ) {
                    TextEditor(text: $draft)
                        .frame(minHeight: 120)
                }
                Section(header: Text("文件")) {
                    Text(name).font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("编辑备注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}
