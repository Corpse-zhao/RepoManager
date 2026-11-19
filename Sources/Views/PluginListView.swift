import SwiftUI

struct PluginListView: View {
    @EnvironmentObject var vm: RepoViewModel
    @State private var deleteTarget: PackageEntry?

    var body: some View {
        NavigationView {
            Group {
                if vm.isBusy && vm.packages.isEmpty {
                    ProgressView("加载中…")
                } else if vm.packages.isEmpty {
                    VStack(spacing: 16) {
                        EmptyStateIcon(symbol: "square.stack.3d.up.slash")
                        Text("源里还没有插件")
                            .font(.headline)
                        Text("上传一个 deb，插件就会出现在这里")
                            .font(.caption).foregroundColor(.secondary)
                        Button {
                            Task { await vm.loadPackages() }
                        } label: {
                            Label("重新加载", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    List {
                        ForEach(vm.packages) { entry in
                            NavigationLink {
                                PluginDetailView(entry: entry)
                            } label: {
                                PluginRow(entry: entry)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteTarget = entry
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("插件")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await vm.loadPackages() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.isBusy)
                }
            }
            .refreshable { await vm.loadPackages() }
            .alert("确认删除", isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )) {
                Button("取消", role: .cancel) { deleteTarget = nil }
                Button("删除", role: .destructive) {
                    if let target = deleteTarget {
                        Task { _ = await vm.delete(entry: target) }
                    }
                    deleteTarget = nil
                }
            } message: {
                if let t = deleteTarget {
                    Text("确定从源里删除「\(t.name)」？\n\n这会删除仓库里的 deb 文件和索引条目，不可撤销。")
                }
            }
        }
    }
}

struct PluginRow: View {
    let entry: PackageEntry

    private var sectionColor: Color {
        switch entry.section.lowercased() {
        case "tweaks": return .purple
        case "utilities", "tools": return .blue
        case "themes": return .pink
        default: return .teal
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: "puzzlepiece.extension", color: AppTheme.accent, side: 42)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(entry.name.isEmpty ? entry.package : entry.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if !entry.version.isEmpty {
                        Badge(text: "v\(entry.version)", color: .secondary)
                    }
                }
                if !entry.desc.isEmpty {
                    Text(entry.desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if !entry.arch.isEmpty {
                        Badge(text: entry.arch, color: .blue)
                    }
                    if !entry.section.isEmpty {
                        Badge(text: entry.section, color: sectionColor)
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }
}

struct PluginDetailView: View {
    @EnvironmentObject var vm: RepoViewModel
    let entry: PackageEntry
    @State private var showEdit = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    IconBadge(symbol: "puzzlepiece.extension", color: AppTheme.accent, side: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name.isEmpty ? entry.package : entry.name)
                            .font(.title3.weight(.semibold))
                        HStack(spacing: 6) {
                            if !entry.version.isEmpty { Badge(text: "v\(entry.version)", color: .secondary) }
                            if !entry.arch.isEmpty { Badge(text: entry.arch, color: .blue) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Section("信息") {
                label("名称", entry.name, icon: "tag")
                label("包名", entry.package, icon: "shippingbox")
                label("版本", entry.version, icon: "number")
                label("架构", entry.arch, icon: "cpu")
                label("大小", entry.size.isEmpty ? "—" : "\(entry.size) 字节", icon: "internaldrive")
            }
            Section("功能描述") {
                Text(entry.desc.isEmpty ? "无描述" : entry.desc).font(.body)
            }
            Section("依赖") {
                Text(entry.depends.isEmpty ? "无" : entry.depends)
                    .font(.caption)
            }
        }
        .navigationTitle(entry.name.isEmpty ? "插件详情" : entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("编辑") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            PluginEditView(entry: entry)
                .environmentObject(vm)
        }
    }

    private func label(_ k: String, _ v: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(AppTheme.accent)
                .frame(width: 20)
            Text(k).foregroundColor(.secondary)
            Spacer()
            Text(v.isEmpty ? "—" : v)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - 编辑插件元数据
struct PluginEditView: View {
    @EnvironmentObject var vm: RepoViewModel
    @Environment(\.dismiss) private var dismiss
    let entry: PackageEntry

    @State private var name: String
    @State private var version: String
    @State private var desc: String
    @State private var depends: String
    @State private var section: String
    @State private var maintainer: String
    @State private var saving = false

    init(entry: PackageEntry) {
        self.entry = entry
        _name = State(initialValue: entry.name)
        _version = State(initialValue: entry.version)
        _desc = State(initialValue: entry.desc)
        _depends = State(initialValue: entry.depends)
        _section = State(initialValue: entry.section.isEmpty ? "Tweaks" : entry.section)
        _maintainer = State(initialValue: entry.maintainer)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    LabelledField(label: "显示名称", text: $name)
                    LabelledField(label: "版本", text: $version, placeholder: "如 1.2.3")
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    LabelledField(label: "分类", text: $section, placeholder: "如 Tweaks")
                }
                Section(header: Text("功能描述"), footer: Text("Sileo 详情页里显示的介绍文字。")) {
                    TextEditor(text: $desc).frame(minHeight: 100)
                }
                Section(header: Text("安装信息")) {
                    LabelledField(label: "依赖", text: $depends, placeholder: "如 mobilesubstrate，留空则无")
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    LabelledField(label: "维护者", text: $maintainer)
                }
                Section(header: Text("不可修改"), footer: Text("包名、架构、deb 文件不会改动；如需更换 deb，请用「上传」页面传同名包覆盖。")) {
                    Label("包名：\(entry.package)", systemImage: "lock.fill").font(.caption)
                    Label("架构：\(entry.arch)", systemImage: "lock.fill").font(.caption)
                }
            }
            .navigationTitle("编辑插件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saving = true
                        Task {
                            var draft = entry
                            draft.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            draft.version = version.trimmingCharacters(in: .whitespacesAndNewlines)
                            draft.desc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
                            draft.depends = depends.trimmingCharacters(in: .whitespacesAndNewlines)
                            draft.section = section.trimmingCharacters(in: .whitespacesAndNewlines)
                            draft.maintainer = maintainer.trimmingCharacters(in: .whitespacesAndNewlines)
                            let ok = await vm.update(entry: entry, to: draft)
                            saving = false
                            if ok { dismiss() }
                        }
                    } label: {
                        if saving { ProgressView() } else { Text("保存") }
                    }
                    .disabled(saving || version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
