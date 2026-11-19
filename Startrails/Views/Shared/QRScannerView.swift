import AVFoundation
import SwiftUI
import UIKit

struct QRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let hint: String
    let onScanned: (String) -> Void

    @State private var cameraError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let cameraError {
                    VStack(spacing: 16) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 52))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(cameraError)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)

                        if let pasted = UIPasteboard.general.string, !pasted.isEmpty {
                            Button {
                                onScanned(pasted)
                                dismiss()
                            } label: {
                                Label("改用剪贴板内容", systemImage: "doc.on.clipboard")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    AVCameraScannerRepresentable(
                        onCodeScanned: { code in
                            Haptics.notify(.success)
                            onScanned(code)
                            dismiss()
                        },
                        onError: { err in
                            cameraError = err
                        }
                    )
                    .ignoresSafeArea()

                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.white.opacity(0.85), lineWidth: 2.5)
                            .frame(width: 240, height: 240)
                        Spacer()
                        Text(hint)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private struct AVCameraScannerRepresentable: UIViewControllerRepresentable {
    let onCodeScanned: @MainActor (String) -> Void
    let onError: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned, onError: onError)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = ScannerViewController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onCodeScanned: @MainActor (String) -> Void
        private let onError: @MainActor (String) -> Void
        private var didEmit = false

        init(onCodeScanned: @escaping @MainActor (String) -> Void, onError: @escaping @MainActor (String) -> Void) {
            self.onCodeScanned = onCodeScanned
            self.onError = onError
        }

        func reportError(_ message: String) {
            Task { @MainActor [weak self] in
                self?.onError(message)
            }
        }

        nonisolated func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let raw = readable.stringValue,
                  !raw.isEmpty
            else { return }
            Task { @MainActor [weak self] in
                guard let self, !self.didEmit else { return }
                self.didEmit = true
                self.onCodeScanned(raw)
            }
        }
    }

    private final class ScannerViewController: UIViewController {
        var coordinator: Coordinator?
        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "com.vongzh.startrails.qr-session")
        private var previewLayer: AVCaptureVideoPreviewLayer?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black

            #if targetEnvironment(simulator)
            coordinator?.reportError("当前运行在 iOS 模拟器，请使用真机摄像头或直接粘贴链接")
            #else
            setupCamera()
            #endif
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            let captureSession = session
            sessionQueue.async {
                if captureSession.isRunning {
                    captureSession.stopRunning()
                }
            }
        }

        private func setupCamera() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                configureSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    Task { @MainActor [weak self] in
                        if granted {
                            self?.configureSession()
                        } else {
                            self?.coordinator?.reportError("未授予相机权限，请在系统设置中允许访问相机")
                        }
                    }
                }
            default:
                coordinator?.reportError("相机权限受限或被拒绝，请在系统设置中开启")
            }
        }

        private func configureSession() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else {
                coordinator?.reportError("无法初始化摄像头")
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                coordinator?.reportError("无法添加二维码元数据输出")
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(coordinator, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            previewLayer = layer

            let captureSession = session
            sessionQueue.async {
                captureSession.startRunning()
            }
        }
    }
}
