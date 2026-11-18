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
                    VStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("源里还没有插件")
                            .foregroundColor(.secondary)
                        Button("重新加载") { Task { await vm.loadPackages() } }
                    }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.name.isEmpty ? entry.package : entry.name)
                    .font(.headline)
                Spacer()
                Text("v\(entry.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(entry.desc)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Text(entry.arch)
                .font(.caption2)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }
}

struct PluginDetailView: View {
    let entry: PackageEntry

    var body: some View {
        List {
            Section("信息") {
                label("名称", entry.name)
                label("包名", entry.package)
                label("版本", entry.version)
                label("架构", entry.arch)
                label("大小", entry.size.isEmpty ? "—" : "\(entry.size) 字节")
            }
            Section("功能描述") {
                Text(entry.desc).font(.body)
            }
            Section("依赖") {
                Text(entry.depends.isEmpty ? "无" : entry.depends)
                    .font(.caption)
            }
        }
        .navigationTitle(entry.name.isEmpty ? "插件详情" : entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundColor(.secondary)
            Spacer()
            Text(v.isEmpty ? "—" : v)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}
