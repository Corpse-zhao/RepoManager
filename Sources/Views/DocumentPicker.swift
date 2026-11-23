import SwiftUI
import UniformTypeIdentifiers

/// 系统原生文件选择器。
/// 关键改动：不再用 SwiftUI .sheet 包 UIDocumentPicker（iOS 17+ 会出现"能弹出但点文件没反应"），
/// 改由 UIKit 宿主直接 present。asCopy:true 把文件复制进沙盒，兼容自签 / 巨魔环境。
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (URL) -> Void
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> PickerHostController {
        let host = PickerHostController()
        host.coordinator = context.coordinator
        return host
    }

    func updateUIViewController(_ host: PickerHostController, context: Context) {
        let c = context.coordinator
        c.onPick = onPick
        c.onError = onError
        c.onFinish = { isPresented = false }
        c.isPresented = isPresented
        if isPresented {
            host.tryPresent()
        } else {
            host.reset()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: ((URL) -> Void)?
        var onError: ((String) -> Void)?
        var onFinish: (() -> Void)?
        /// 当前是否真的需要弹选择器。viewDidAppear 靠它判断，避免进 App / 切 tab 时误弹。
        var isPresented = false

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            onFinish?()
            guard let url = urls.first else {
                onError?("没有选到文件")
                return
            }
            onPick?(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish?()
        }
    }
}

/// 空宿主，负责用 UIKit 方式弹出选择器
final class PickerHostController: UIViewController {
    weak var coordinator: DocumentPicker.Coordinator?
    private var didPresent = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 只有用户主动点了「选择文件」才弹；否则 App 启动 / 切 tab / 从后台回来都会误弹
        guard coordinator?.isPresented == true else { return }
        tryPresent()
    }

    func reset() { didPresent = false }

    func tryPresent() {
        guard !didPresent,
              presentedViewController == nil,
              view.window != nil,
              let coord = coordinator else { return }
        didPresent = true
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = coord
        picker.allowsMultipleSelection = false
        picker.modalPresentationStyle = .fullScreen
        present(picker, animated: true)
    }
}
