import Foundation

// MARK: - 仓库绑定配置
struct RepoConfig: Codable {
    var token: String = ""
    var owner: String = ""
    var repo: String = ""
    var branch: String = "main"

    var isValid: Bool {
        !token.isEmpty && !owner.isEmpty && !repo.isEmpty
    }

    var repoFullName: String { "\(owner)/\(repo)" }

    /// GitHub Pages 源地址（用于生成 SileoDepiction 链接）
    var pagesBase: String {
        if owner.lowercased().hasSuffix(".github.io") {
            return "https://\(owner)/\(repo)/"
        }
        return "https://\(owner).github.io/\(repo)/"
    }
}

// MARK: - Packages 索引里的一个插件条目
struct PackageEntry: Identifiable, Equatable {
    var id: String { package.isEmpty ? filename : package }
    var package: String = ""
    var name: String = ""
    var version: String = ""
    var arch: String = ""
    var desc: String = ""
    var section: String = "Tweaks"
    var depends: String = ""
    var maintainer: String = ""
    var filename: String = ""
    var size: String = ""
    var sha256: String = ""
    var md5: String = ""
    var extra: [String: String] = [:]   // SileoDepiction / Depiction 等额外字段

    /// 从 Packages 文本解析（按空行分块，处理续行）
    static func parseAll(_ text: String) -> [PackageEntry] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var result: [PackageEntry] = []
        for block in blocks {
            var fields: [(String, String)] = []
            for rawLine in block.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = String(rawLine)
                if line.isEmpty { continue }
                if line.hasPrefix(" ") || line.hasPrefix("\t") {
                    // 续行：接到上一个字段
                    if !fields.isEmpty {
                        let idx = fields.count - 1
                        fields[idx].1 += "\n" + line.trimmingCharacters(in: .whitespaces)
                    }
                    continue
                }
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                fields.append((key, value))
            }
            guard !fields.isEmpty else { continue }
            var entry = PackageEntry()
            let known: Set<String> = ["Package", "Name", "Version", "Architecture", "Description",
                                      "Section", "Depends", "Maintainer", "Author", "Filename",
                                      "Size", "SHA256", "MD5sum", "Installed-Size", "Pre-Depends",
                                      "Conflicts", "Replaces", "Priority", "Tag"]
            for (k, v) in fields {
                switch k.lowercased() {
                case "package": entry.package = v
                case "name": entry.name = v
                case "version": entry.version = v
                case "architecture": entry.arch = v
                case "description": entry.desc = v
                case "section": entry.section = v
                case "depends": entry.depends = v
                case "maintainer": entry.maintainer = v
                case "filename": entry.filename = v
                case "size": entry.size = v
                case "sha256": entry.sha256 = v
                case "md5sum": entry.md5 = v
                default:
                    if !known.contains(k) { entry.extra[k] = v }
                }
            }
            if !entry.package.isEmpty { result.append(entry) }
        }
        return result
    }

    /// 序列化成 Packages 条目
    func serialized() -> String {
        var lines: [String] = []
        lines.append("Package: \(package)")
        if !name.isEmpty { lines.append("Name: \(name)") }
        lines.append("Description: \(desc.isEmpty ? name : desc)")
        if !maintainer.isEmpty { lines.append("Maintainer: \(maintainer)") }
        if !section.isEmpty { lines.append("Section: \(section)") }
        if !depends.isEmpty { lines.append("Depends: \(depends)") }
        lines.append("Architecture: \(arch)")
        lines.append("Version: \(version)")
        lines.append("Installed-Size: 100")
        for (k, v) in extra where !["Package", "Name", "Description", "Version", "Architecture",
                                    "Filename", "Size", "SHA256", "MD5sum"].contains(k) {
            lines.append("\(k): \(v)")
        }
        lines.append("Filename: \(filename)")
        lines.append("Size: \(size)")
        lines.append("SHA256: \(sha256)")
        lines.append("MD5sum: \(md5)")
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - 上传表单
struct UploadDraft {
    var package: String = ""
    var name: String = ""
    var version: String = ""
    var arch: String = "iphoneos-arm64e"
    var desc: String = ""
    var depends: String = "mobilesubstrate"
    var section: String = "Tweaks"
    var debData: Data?
    var fileName: String = ""

    /// 从 deb 文件名推断元数据：com.xxx.name_1.2.3_iphoneos-arm64e.deb
    mutating func infer(from fileName: String) {
        self.fileName = fileName
        var base = (fileName as NSString).deletingPathExtension
        // 兼容 wxglass_0.2.0.deb 这类不带架构的名字
        var parts = base.split(separator: "_").map(String.init)
        if parts.count >= 3 {
            arch = parts[parts.count - 1]
            version = parts[parts.count - 2]
            package = parts.dropLast(2).joined(separator: "_")
        } else if parts.count == 2 {
            version = parts[1]
            package = parts[0]
        } else {
            package = base
        }
        if name.isEmpty {
            name = package.components(separatedBy: ".").last?.capitalized ?? package
        }
    }
}
