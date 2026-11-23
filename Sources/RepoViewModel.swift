import Foundation
import SwiftUI

@MainActor
final class RepoViewModel: ObservableObject {
    @Published var config: RepoConfig {
        didSet { ConfigStore.save(config) }
    }
    @Published var packages: [PackageEntry] = []
    @Published var isBusy = false
    @Published var status: String = "就绪"
    @Published var alertMessage: String?
    @Published var showAlert = false

    // 全 App 共用一个文件选择器：只在最外层挂一个宿主，避免多 Tab 各自挂宿主互相干扰
    @Published var isFilePickerPresented = false
    private var filePickerHandler: ((URL) -> Void)?

    /// 申请选择文件，选中后回调（扩展名由调用方校验）
    func requestFile(handler: @escaping (URL) -> Void) {
        filePickerHandler = handler
        isFilePickerPresented = true
    }

    func handlePickedFile(_ url: URL) {
        isFilePickerPresented = false
        let h = filePickerHandler
        filePickerHandler = nil
        h?(url)
    }

    // MARK: 从「其他应用打开 / 分享」导入
    /// 外部 App 传进来的文件（微信里点「用其他应用打开」选本 App 时会走这里）。
    /// 各页面监听它，自动跳到对应 tab 并预填。
    @Published var pendingIncoming: IncomingFile?
    /// 当前应切到哪个 tab：0 插件 / 1 上传 / 2 IPA / 3 设置
    @Published var requestedTab: Int = 0
    /// 顶部可见横幅：明确告诉用户文件有没有收到（比弹窗温和，且能直观排查）
    @Published var incomingBanner: String?

    // 双通道去重：onOpenURL 和 AppDelegate 可能同时上报同一个 URL
    private var lastIncomingURL: String?
    private var lastIncomingTime: Date?

    /// 接收外部文件 URL。立刻读取并复制进内存（外部临时文件随时会被系统回收）。
    /// - Returns: 是否成功接收（扩展名合法且读到数据）
    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        // 1 秒内同一 URL 只处理一次，避免两条通道重复导入
        let key = url.absoluteString
        let now = Date()
        if key == lastIncomingURL, let t = lastIncomingTime, now.timeIntervalSince(t) < 1.0 {
            return false
        }
        lastIncomingURL = key
        lastIncomingTime = now

        // 微信/QQ 传过来的临时文件名常被改写，扩展名判断放宽到整个路径
        let full = url.absoluteString.lowercased()
        let base = url.lastPathComponent.lowercased()
        var ext: String?
        if base.hasSuffix(".deb") || full.contains(".deb") { ext = "deb" }
        else if base.hasSuffix(".ipa") || full.contains(".ipa") { ext = "ipa" }

        guard let kind = ext else {
            incomingBanner = "收到文件但无法识别类型：\(url.lastPathComponent)"
            alert("只支持 .deb（插件）和 .ipa（备份）文件。收到的是「\(url.lastPathComponent)」，如果这是 deb/ipa，请确认文件名保留了扩展名。")
            return false
        }

        guard config.isValid else {
            incomingBanner = "已收到 \(kind.uppercased())，但还没绑定源"
            alert("已收到文件，但还没绑定源。请先在绑定页填入 Token 和仓库，再重新用其他应用打开这个文件。")
            return false
        }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                incomingBanner = "文件是空的，导入失败"
                alert("文件是空的，无法导入")
                return false
            }
            // 尽量还原成带正确扩展名的文件名（微信临时名常丢扩展名）
            var name = url.lastPathComponent
            if !name.lowercased().hasSuffix(".\(kind)") {
                name = (name as NSString).deletingPathExtension + ".\(kind)"
            }
            let incoming = IncomingFile(name: name, ext: kind, data: data)
            pendingIncoming = incoming
            requestedTab = (kind == "deb") ? 1 : 2
            incomingBanner = "已收到 \(name) · 正在导入"
            status = "已从外部导入 \(name)"
            // 横幅 4 秒后自动消失
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if self?.incomingBanner?.contains(name) == true { self?.incomingBanner = nil }
            }
            return true
        } catch {
            incomingBanner = "读取文件失败"
            alert("读取外部文件失败：\(error.localizedDescription)")
            return false
        }
    }

    private var service: GitHubService { GitHubService(config: config) }

    init() {
        self.config = ConfigStore.load()
    }

    func alert(_ msg: String) {
        // 切换页面会取消进行中的网络请求，这类错误是正常现象，不该弹窗打扰
        let lower = msg.lowercased()
        if lower.contains("cancelled") || lower.contains("canceled")
            || lower.contains("请求已取消") || lower.contains("is Cancelled")
            || lower.contains("code=-999") {
            return
        }
        alertMessage = msg
        showAlert = true
    }

    /// 绑定页专用：验证配置，返回错误文案（nil = 成功）。不触发全局弹窗，便于内联显示。
    func verifyBindError(for cfg: RepoConfig) async -> String? {
        guard cfg.isValid else { return "Token 和源都要填。" }
        do {
            let s = GitHubService(config: cfg)
            _ = try await s.verify()
            return nil
        } catch RepoError.http(404, _) {
            return "找不到仓库「\(cfg.repoFullName)」。\n请核对：① 解析出的仓库名对不对；② Token 属于哪个账号；③ 该账号下是否真有这个仓库（仓库名别写错）。"
        } catch RepoError.http(401, _) {
            return "Token 无效，或没勾 repo 权限。请重新生成 classic token，只勾 repo，再粘一次。"
        } catch {
            return "连接失败：\(error.localizedDescription)"
        }
    }

    /// 从 URL 下载（供上传页拉取 deb 用）
    func download(url: URL) async throws -> Data {
        try await service.download(url: url)
    }

    // MARK: 连接测试
    func testConnection() async -> Bool {
        guard config.isValid else {
            alert("请填全 Token / 用户名 / 仓库名")
            return false
        }
        isBusy = true; status = "正在验证仓库…"
        defer { isBusy = false; status = "就绪" }
        do {
            let name = try await service.verify()
            status = "已连接 \(name)"
            return true
        } catch RepoError.http(404, _) {
            alert("找不到仓库。App 实际解析为「\(config.repoFullName)」。\n\n正确格式：用户名/仓库名，例如 Corpse-zhao/banli。也可粘贴 github.com/用户名/仓库名 或 xxx.github.io/仓库名。注意 Token 和仓库要对应同一个 GitHub 账号。")
            return false
        } catch RepoError.http(401, _) {
            alert("Token 无效或已过期，请重新生成一个勾选 repo 权限的 GitHub Token。")
            return false
        } catch {
            alert("连接失败：\(error.localizedDescription)")
            return false
        }
    }

    // MARK: 加载插件列表
    func loadPackages() async {
        guard config.isValid else { return }
        isBusy = true; status = "正在读取 Packages…"
        defer { isBusy = false; status = "就绪" }
        do {
            guard let file = try await service.readFile("Packages") else {
                packages = []
                status = "源里还没有 Packages 索引"
                return
            }
            let text = String(data: file.data, encoding: .utf8) ?? ""
            packages = PackageEntry.parseAll(text).sorted {
                ($0.name.isEmpty ? $0.package : $0.name) < ($1.name.isEmpty ? $1.package : $1.name)
            }
            status = "共 \(packages.count) 个插件"
        } catch {
            let m = error.localizedDescription.lowercased()
            if m.contains("cancelled") || m.contains("canceled") || m.contains("code=-999") {
                return   // 切页面取消请求，静默
            }
            alert("读取失败：\(error.localizedDescription)")
        }
    }

    // MARK: 上传 deb（draft 里必须已有 debData）
    func upload(draft: UploadDraft) async -> Bool {
        guard config.isValid, let data = draft.debData else {
            alert("缺少配置或 deb 文件")
            return false
        }
        isBusy = true; status = "正在上传 \(draft.fileName)…"
        defer { isBusy = false; status = "就绪" }
        do {
            // 1) 读取现有 Packages
            var entries: [PackageEntry]
            if let file = try await service.readFile("Packages") {
                entries = PackageEntry.parseAll(String(data: file.data, encoding: .utf8) ?? "")
            } else {
                entries = []
            }
            // 2) 移除同包名的旧条目（同包更新 = 覆盖），并记下旧 deb 路径以便清理
            let oldDebPaths = entries.filter { $0.package == draft.package }
                .map { $0.filename }.filter { !$0.isEmpty }
            entries.removeAll { $0.package == draft.package }

            let pkgId = draft.package.isEmpty ? (draft.fileName as NSString).deletingPathExtension : draft.package
            let debPath = "debs/\(draft.fileName)"
            let depPath = "depictions/\(pkgId).json"

            // 3) 新条目
            var entry = PackageEntry()
            entry.package = pkgId
            entry.name = draft.name.isEmpty ? pkgId : draft.name
            entry.version = draft.version
            entry.arch = draft.arch
            entry.desc = draft.desc.isEmpty ? entry.name : draft.desc
            entry.section = draft.section
            entry.depends = draft.depends
            entry.maintainer = config.owner
            entry.filename = debPath
            entry.size = "\(data.count)"
            entry.sha256 = RepoHash.sha256(data)
            entry.md5 = RepoHash.md5(data)
            entry.extra["SileoDepiction"] = "\(config.pagesBase)\(depPath)"
            entry.extra["Depiction"] = "\(config.pagesBase)\(depPath)"

            // 4) 生成 depiction JSON
            let depiction = Self.makeDepiction(entry: entry, config: config)

            // 5) 重建 Packages + gz + Release
            entries.append(entry)
            entries.sort { $0.package < $1.package }
            let packagesText = entries.map { $0.serialized() }.joined(separator: "\n")
            let packagesData = Data(packagesText.utf8)
            let gzData = RepoHash.gzip(packagesData)
            let release = Self.makeRelease(packages: packagesData, gz: gzData, config: config)

            // 6) 一次原子提交：deb + depiction + Packages + gz + Release
            var changes: [FileChange] = [
                FileChange(path: debPath, data: data, sha: nil),
                FileChange(path: depPath, data: depiction, sha: nil),
                FileChange(path: "Packages", data: packagesData, sha: nil),
                FileChange(path: "Packages.gz", data: gzData, sha: nil),
                FileChange(path: "Release", data: release, sha: nil),
            ]
            // 删掉同名包的旧 deb（版本号变了文件名不同，避免仓库里堆积旧文件）
            for old in oldDebPaths where old != debPath {
                changes.append(FileChange(path: old, data: nil, sha: nil))
            }
            // 删掉旧的 bz2，避免客户端读到过期索引
            if let names = try? await service.listDir(""), names.contains("Packages.bz2") {
                changes.append(FileChange(path: "Packages.bz2", data: nil, sha: nil))
            }
            try await service.commit(changes: changes, message: "上传 \(pkgId) \(draft.version)（RepoManager）")
            packages = entries
            status = "已上传 \(pkgId) \(draft.version)"
            return true
        } catch {
            alert("上传失败：\(error.localizedDescription)")
            return false
        }
    }

    // MARK: - IPA 备份（存到仓库 ipas/ 目录，纯文件托管，不建索引）
    @Published var ipaFiles: [String] = []
    @Published var ipaNotes: [String: String] = [:]   // 文件名 → 备注

    /// 读取备注映射（ipas/notes.json）
    private func readIPANotes() async -> [String: String] {
        guard let f = try? await service.readFile("ipas/notes.json"),
              let obj = try? JSONSerialization.jsonObject(with: f.data),
              let map = obj as? [String: String] else { return [:] }
        return map
    }

    private func encodeIPANotes(_ notes: [String: String]) -> Data {
        (try? JSONSerialization.data(withJSONObject: notes, options: [.prettyPrinted]))
            ?? Data("{}".utf8)
    }

    func loadIPAs() async {
        guard config.isValid else { return }
        isBusy = true; status = "正在读取 IPA 列表…"
        defer { isBusy = false; status = "就绪" }
        do {
            let names = try await service.listDir("ipas")
            ipaFiles = names.filter { $0.lowercased().hasSuffix(".ipa") && $0 != "notes.json" }
                .sorted { $0 < $1 }
            ipaNotes = await readIPANotes()
            status = "已备份 \(ipaFiles.count) 个 IPA"
        } catch RepoError.http(404, _) {
            ipaFiles = []   // 目录还不存在
            status = "还没有 IPA 备份"
        } catch {
            let m = error.localizedDescription.lowercased()
            if m.contains("cancelled") || m.contains("canceled") || m.contains("code=-999") {
                return   // 切页面取消请求，静默
            }
            alert("读取 IPA 列表失败：\(error.localizedDescription)")
        }
    }

    func uploadIPA(fileName: String, data: Data, note: String = "") async -> Bool {
        guard config.isValid else { alert("尚未绑定源"); return false }
        // GitHub blob 单文件上限 100MB，留点余量
        guard data.count <= 99 * 1024 * 1024 else {
            alert("IPA 超过 99MB，GitHub 单个文件放不下（可压缩后再传）。")
            return false
        }
        isBusy = true; status = "正在上传 \(fileName)…"
        defer { isBusy = false; status = "就绪" }
        do {
            // 备注写进 notes.json（跟 IPA 同一次原子提交）
            var notes = await readIPANotes()
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { notes.removeValue(forKey: fileName) }
            else { notes[fileName] = trimmed }
            let path = "ipas/\(fileName)"
            try await service.commit(changes: [
                FileChange(path: path, data: data, sha: nil),
                FileChange(path: "ipas/notes.json", data: encodeIPANotes(notes), sha: nil)
            ], message: "备份 IPA \(fileName)（RepoManager）")
            await loadIPAs()
            status = "已备份 \(fileName)"
            return true
        } catch {
            alert("IPA 上传失败：\(error.localizedDescription)")
            return false
        }
    }

    /// 修改某个 IPA 的备注（留空则清除）
    func setIPANote(fileName: String, note: String) async -> Bool {
        guard config.isValid else { alert("尚未绑定源"); return false }
        isBusy = true; status = "正在保存备注…"
        defer { isBusy = false; status = "就绪" }
        do {
            var notes = await readIPANotes()
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { notes.removeValue(forKey: fileName) }
            else { notes[fileName] = trimmed }
            try await service.commit(
                changes: [FileChange(path: "ipas/notes.json", data: encodeIPANotes(notes), sha: nil)],
                message: "更新 IPA 备注 \(fileName)（RepoManager）")
            ipaNotes = notes
            status = "备注已保存"
            return true
        } catch {
            alert("保存备注失败：\(error.localizedDescription)")
            return false
        }
    }

    func deleteIPA(_ fileName: String) async -> Bool {
        isBusy = true; status = "正在删除 \(fileName)…"
        defer { isBusy = false; status = "就绪" }
        do {
            var notes = await readIPANotes()
            notes.removeValue(forKey: fileName)
            try await service.commit(
                changes: [
                    FileChange(path: "ipas/\(fileName)", data: nil, sha: nil),
                    FileChange(path: "ipas/notes.json", data: encodeIPANotes(notes), sha: nil)
                ],
                message: "删除 IPA 备份 \(fileName)（RepoManager）")
            await loadIPAs()
            status = "已删除 \(fileName)"
            return true
        } catch {
            alert("IPA 删除失败：\(error.localizedDescription)")
            return false
        }
    }

    /// IPA 在仓库里的 raw 下载地址（巨魔可直接打开安装）
    func ipaDownloadURL(_ fileName: String) -> String {
        let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        return "\(config.pagesBase)ipas/\(encoded)"
    }

    // MARK: 编辑插件元数据（不换 deb 文件）
    func update(entry original: PackageEntry, to draft: PackageEntry) async -> Bool {
        guard config.isValid else {
            alert("尚未绑定源")
            return false
        }
        isBusy = true; status = "正在保存…"
        defer { isBusy = false; status = "就绪" }
        do {
            var entries = packages
            if let idx = entries.firstIndex(where: { $0.package == original.package }) {
                entries[idx] = draft
            } else {
                entries.append(draft)
            }
            entries.sort { $0.package < $1.package }

            let packagesText = entries.map { $0.serialized() }.joined(separator: "\n")
            let packagesData = Data(packagesText.utf8)
            let gzData = RepoHash.gzip(packagesData)
            let release = Self.makeRelease(packages: packagesData, gz: gzData, config: config)
            let depiction = Self.makeDepiction(entry: draft, config: config)

            var changes: [FileChange] = [
                FileChange(path: "Packages", data: packagesData, sha: nil),
                FileChange(path: "Packages.gz", data: gzData, sha: nil),
                FileChange(path: "Release", data: release, sha: nil),
                FileChange(path: "depictions/\(draft.package).json", data: depiction, sha: nil),
            ]
            if let names = try? await service.listDir(""), names.contains("Packages.bz2") {
                changes.append(FileChange(path: "Packages.bz2", data: nil, sha: nil))
            }
            try await service.commit(changes: changes, message: "编辑 \(draft.package)（RepoManager）")
            packages = entries
            status = "已保存 \(draft.name.isEmpty ? draft.package : draft.name)"
            return true
        } catch {
            alert("保存失败：\(error.localizedDescription)")
            return false
        }
    }

    // MARK: 删除插件
    func delete(entry: PackageEntry) async -> Bool {
        isBusy = true; status = "正在删除 \(entry.name)…"
        defer { isBusy = false; status = "就绪" }
        do {
            var entries = packages
            entries.removeAll { $0.package == entry.package }
            let packagesText = entries.map { $0.serialized() }.joined(separator: "\n")
            let packagesData = Data(packagesText.utf8)
            let gzData = RepoHash.gzip(packagesData)
            let release = Self.makeRelease(packages: packagesData, gz: gzData, config: config)

            let changes: [FileChange] = [
                FileChange(path: entry.filename, data: nil, sha: nil),
                FileChange(path: "depictions/\(entry.package).json", data: nil, sha: nil),
                FileChange(path: "Packages", data: packagesData, sha: nil),
                FileChange(path: "Packages.gz", data: gzData, sha: nil),
                FileChange(path: "Release", data: release, sha: nil),
            ]
            try await service.commit(changes: changes, message: "删除 \(entry.package)（RepoManager）")
            packages = entries
            status = "已删除 \(entry.name)"
            return true
        } catch {
            alert("删除失败：\(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 生成 Sileo Native Depiction
    private static func makeDepiction(entry: PackageEntry, config: RepoConfig) -> Data {
        let header = "\(config.pagesBase)banner.jpg"
        let obj: [String: Any] = [
            "minVersion": "0.4",
            "class": "DepictionTabView",
            "headerImage": header,
            "tintColor": "#5b5bd6",
            "tabs": [[
                "class": "DepictionStackView",
                "tabname": "Details",
                "views": [
                    ["class": "DepictionHeaderView", "title": entry.name],
                    ["class": "DepictionSubheaderView", "title": "版本 \(entry.version) · \(entry.arch)"],
                    ["class": "DepictionMarkdownView", "markdown": entry.desc, "useSpacing": true],
                    ["class": "DepictionSeparatorView"],
                    ["class": "DepictionScreenshotsView",
                     "screenshots": [["url": header, "accessibilityText": "\(entry.name) 预览图"]],
                     "itemCornerRadius": 12,
                     "itemSize": ["x": 240, "y": 135]],
                    ["class": "DepictionSpacerView", "spacing": 12],
                    ["class": "DepictionTableTextView", "title": "包名", "text": entry.package],
                    ["class": "DepictionTableTextView", "title": "版本", "text": entry.version],
                    ["class": "DepictionTableTextView", "title": "架构", "text": entry.arch],
                    ["class": "DepictionTableButtonView", "title": "下载 deb",
                     "action": "\(config.pagesBase)\(entry.filename)"]
                ]
            ]]
        ]
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    // MARK: - 生成 Release
    private static func makeRelease(packages: Data, gz: Data?, config: RepoConfig) -> Data {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'UTC'"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        var lines: [String] = [
            "Origin: \(config.owner) Repo",
            "Label: \(config.owner) Repo",
            "Name: \(config.owner)",
            "Suite: stable",
            "Codename: stable",
            "Architectures: iphoneos-arm64e iphoneos-arm64 all",
            "Components: main",
            "Description: \(config.owner) 的越狱插件源（RepoManager 管理）",
            "Date: \(fmt.string(from: Date()))",
            "SHA256:"
        ]
        lines.append(" \(RepoHash.sha256(packages)) \(String(format: "%16d", packages.count)) Packages")
        if let gz = gz {
            lines.append(" \(RepoHash.sha256(gz)) \(String(format: "%16d", gz.count)) Packages.gz")
        }
        return Data(lines.joined(separator: "\n").utf8)
    }
}

// MARK: - 配置持久化
enum ConfigStore {
    private static let key = "repomanager.config"
    static func load() -> RepoConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cfg = try? JSONDecoder().decode(RepoConfig.self, from: data) else {
            return RepoConfig()
        }
        return cfg
    }
    static func save(_ cfg: RepoConfig) {
        if let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
