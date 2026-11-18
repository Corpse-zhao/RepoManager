import Foundation
import CryptoKit
import Compression

// MARK: - 错误
enum RepoError: LocalizedError {
    case http(Int, String)
    case decode(String)
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let msg): return "HTTP \(code): \(msg)"
        case .decode(let s): return "解析失败: \(s)"
        case .missing(let s): return "缺少: \(s)"
        }
    }
}

// MARK: - 文件变更（nil 表示删除）
struct FileChange {
    let path: String
    let data: Data?   // nil = 删除该文件
    let sha: String?  // 已有文件的 sha（Contents API 用）
}

// MARK: - GitHub REST 封装
final class GitHubService {
    let config: RepoConfig
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(config: RepoConfig) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: cfg)
    }

    private var apiBase: String { "https://api.github.com" }
    private var repoBase: String { "\(apiBase)/repos/\(config.repoFullName)" }

    private func request(_ method: String, _ path: String,
                         body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: path.hasPrefix("http") ? path : repoBase + path) else {
            throw RepoError.decode("无效 URL: \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("RepoManager/1.0", forHTTPHeaderField: "User-Agent")
        if let body = body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if !(200...299).contains(code) {
            var msg = String(data: data, encoding: .utf8) ?? ""
            if msg.count > 300 { msg = String(msg.prefix(300)) }
            throw RepoError.http(code, msg)
        }
        return data
    }

    private func json(_ data: Data) throws -> [String: Any] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RepoError.decode("JSON 格式错误")
        }
        return obj
    }

    /// 测试绑定：获取仓库信息
    func verify() async throws -> String {
        let data = try await request("GET", "")
        let obj = try json(data)
        return obj["full_name"] as? String ?? config.repoFullName
    }

    /// 读取单个文件（Contents API）。404 返回 nil
    func readFile(_ path: String) async throws -> (data: Data, sha: String)? {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        do {
            let data = try await request("GET", "/contents/\(encoded)?ref=\(config.branch)")
            let obj = try json(data)
            guard let b64 = obj["content"] as? String else { return nil }
            let clean = b64.filter { !$0.isWhitespace && !$0.isNewline }
            guard let raw = Data(base64Encoded: clean, options: .ignoreUnknownCharacters) else {
                throw RepoError.decode("文件 base64 解码失败: \(path)")
            }
            return (raw, obj["sha"] as? String ?? "")
        } catch RepoError.http(404, _) {
            return nil
        }
    }

    /// 列出目录文件名
    func listDir(_ path: String) async throws -> [String] {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let data = try await request("GET", "/contents/\(encoded)?ref=\(config.branch)")
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { $0["name"] as? String }
    }

    /// 用 Git Data API 一次性原子提交多个文件变更
    func commit(changes: [FileChange], message: String) async throws {
        // 1) 当前分支 HEAD commit
        let refData = try await request("GET", "/git/ref/heads/\(config.branch)")
        let refObj = try json(refData)
        guard let commitSha = ((refObj["object"] as? [String: Any])?["sha"]) as? String else {
            throw RepoError.decode("无法读取分支 HEAD")
        }

        // 2) 当前树
        let commitData = try await request("GET", "/git/commits/\(commitSha)")
        let commitObj = try json(commitData)
        guard let baseTree = (commitObj["tree"] as? [String: Any])?["sha"] as? String else {
            throw RepoError.decode("无法读取 base tree")
        }

        // 3) 为每个新内容创建 blob
        var tree: [[String: Any]] = []
        for change in changes {
            var entry: [String: Any] = [
                "path": change.path,
                "mode": "100644",
                "type": "blob"
            ]
            if let data = change.data {
                let blobData = try await request("POST", "/git/blobs", [
                    "content": data.base64EncodedString(),
                    "encoding": "base64"
                ])
                let blobObj = try json(blobData)
                guard let sha = blobObj["sha"] as? String else {
                    throw RepoError.decode("blob 创建失败: \(change.path)")
                }
                entry["sha"] = sha
            } else {
                // sha = null 表示删除文件
                entry["sha"] = NSNull()
            }
            tree.append(entry)
        }

        // 4) 创建新树
        let treeData = try await request("POST", "/git/trees", [
            "base_tree": baseTree,
            "tree": tree
        ])
        let treeObj = try json(treeData)
        guard let newTree = treeObj["sha"] as? String else {
            throw RepoError.decode("tree 创建失败")
        }

        // 5) 创建 commit
        let newCommitData = try await request("POST", "/git/commits", [
            "message": message,
            "tree": newTree,
            "parents": [commitSha]
        ])
        let newCommitObj = try json(newCommitData)
        guard let newCommitSha = newCommitObj["sha"] as? String else {
            throw RepoError.decode("commit 创建失败")
        }

        // 6) 移动分支指针
        _ = try await request("PATCH", "/git/refs/heads/\(config.branch)", ["sha": newCommitSha])
    }

    /// 下载任意 URL（用于贴链接拉 deb）
    func download(url: URL) async throws -> Data {
        let (data, resp) = try await session.data(from: url)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            throw RepoError.http(code, "下载失败 \(url.lastPathComponent)")
        }
        return data
    }
}

// MARK: - 哈希 / 压缩工具
enum RepoHash {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// gzip 压缩（Compression framework）
    static func gzip(_ data: Data) -> Data? {
        let dstSize = 64 * 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: dstSize)
        defer { dst.deallocate() }

        var stream = compression_stream()
        let initStatus = compression_stream_init(&stream, COMPRESSION_STREAM_OPERATION_ENCODE, COMPRESSION_ALGORITHM_GZIP)
        guard initStatus != COMPRESSION_STATUS_ERROR else { return nil }
        defer { compression_stream_destroy(&stream) }

        var output = Data()
        let count = data.count
        let result: Data? = data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Data? in
            guard let base = buf.baseAddress else { return nil }
            stream.src_ptr = base.assumingMemoryBound(to: UInt8.self)
            stream.src_size = count
            var finalized = false
            while true {
                stream.dst_ptr = dst
                stream.dst_size = dstSize
                let flags: Int32 = finalized ? Int32(COMPRESSION_STREAM_FINALIZATION) : 0
                let status = compression_stream_process(&stream, flags)
                let produced = dstSize - stream.dst_size
                if produced > 0 { output.append(dst, count: produced) }
                if status == COMPRESSION_STATUS_END { break }
                if status == COMPRESSION_STATUS_ERROR { return nil }
                if stream.src_size == 0 && !finalized {
                    finalized = true
                }
            }
            return output
        }
        return result
    }
}
