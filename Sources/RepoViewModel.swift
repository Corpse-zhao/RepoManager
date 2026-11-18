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

    private var service: GitHubService { GitHubService(config: config) }

    init() {
        self.config = ConfigStore.load()
    }

    func alert(_ msg: String) {
        alertMessage = msg
        showAlert = true
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
            // 2) 移除同包名的旧条目（同包更新 = 覆盖）
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
