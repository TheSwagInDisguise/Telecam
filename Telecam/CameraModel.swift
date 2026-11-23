import AVFoundation
import SwiftUI

enum LensChoice: String, CaseIterable, Identifiable {
    case main
    case telephoto

    var id: String { rawValue }

    var label: String {
        switch self {
        case .main: return "Main"
        case .telephoto: return "Telephoto"
        }
    }

    /// Physical (not virtual) camera, so iOS can never silently switch lenses
    /// out from under the add-on lens.
    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .main: return .builtInWideAngleCamera
        case .telephoto: return .builtInTelephotoCamera
        }
    }
}

/// Owns the capture session. Locks to one physical camera and captures
/// bursts of Bayer RAW frames (not ProRAW) into Documents/Bursts/<name>/,
/// which is visible in the Files app under "On My iPhone > Telecam".
final class CameraModel: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published var lens: LensChoice = .telephoto
    @Published var addOnAttached = true
    @Published var burstCount = 8
    @Published var status = "Starting…"
    @Published var isCapturing = false
    @Published var isReady = false

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "telecam.session")
    private var input: AVCaptureDeviceInput?
    private var rawFormat: OSType?

    // Burst state — only touched on sessionQueue.
    private var burstTotal = 0
    private var burstIndex = 0
    private var burstFolder: URL?
    private var burstInfo: [String: Any] = [:]

    // MARK: Setup

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.configure() } else { self.status = "Camera access denied" }
                }
            }
        default:
            status = "Camera access denied. Enable it in Settings."
        }
    }

    func configure() {
        let lens = self.lens
        isReady = false
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            if let existing = self.input {
                self.session.removeInput(existing)
                self.input = nil
            }

            guard let device = AVCaptureDevice.default(lens.deviceType, for: .video, position: .back),
                  let newInput = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(newInput) else {
                self.session.commitConfiguration()
                self.setStatus("\(lens.label) camera unavailable")
                return
            }
            self.session.addInput(newInput)
            self.input = newInput

            if !self.session.outputs.contains(self.photoOutput), self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            self.session.commitConfiguration()

            self.rawFormat = self.photoOutput.availableRawPhotoPixelFormatTypes.first {
                AVCapturePhotoOutput.isBayerRAWPixelFormat($0)
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            let rawNote = self.rawFormat == nil ? " (no Bayer RAW!)" : ""
            self.setStatus("\(lens.label) locked\(rawNote)")
            DispatchQueue.main.async { self.isReady = true }
        }
    }

    // MARK: Burst capture

    func captureBurst() {
        guard !isCapturing, isReady else { return }
        isCapturing = true
        let total = burstCount
        let lens = self.lens
        let addOn = addOnAttached

        sessionQueue.async {
            guard let device = self.input?.device, let raw = self.rawFormat else {
                self.setStatus("Bayer RAW not available on this lens")
                DispatchQueue.main.async { self.isCapturing = false }
                return
            }

            // Freeze focus / exposure / white balance so every frame in the
            // burst matches; only hand shake should differ between frames.
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
                if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
                device.unlockForConfiguration()
            } catch {
                // Not fatal; frames may just vary slightly.
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let name = "\(formatter.string(from: Date()))_\(lens.rawValue)\(addOn ? "_addon2x" : "")"
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let folder = docs.appendingPathComponent("Bursts", isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let dims = device.activeFormat.formatDescription.dimensions
            self.burstInfo = [
                "lens": lens.rawValue,
                "addOn2x": addOn,
                "frames": total,
                "exposureDurationSeconds": CMTimeGetSeconds(device.exposureDuration),
                "iso": device.iso,
                "lensPosition": device.lensPosition,
                "videoZoomFactor": device.videoZoomFactor,
                "activeFormatWidth": dims.width,
                "activeFormatHeight": dims.height,
                "deviceType": device.deviceType.rawValue,
                "startedAt": ISO8601DateFormatter().string(from: Date()),
            ]
            self.burstFolder = folder
            self.burstTotal = total
            self.burstIndex = 0
            self.setStatus("Capturing 0/\(total)… hold steady-ish")
            self.captureNext(raw: raw)
        }
    }

    private func captureNext(raw: OSType) {
        let settings = AVCapturePhotoSettings(rawPixelFormatType: raw)
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func finishBurst(error: Error?) {
        if let folder = burstFolder {
            var info = burstInfo
            info["framesSaved"] = burstIndex
            info["finishedAt"] = ISO8601DateFormatter().string(from: Date())
            if let error { info["error"] = error.localizedDescription }
            if let json = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
                try? json.write(to: folder.appendingPathComponent("burst.json"))
            }
        }

        if let device = input?.device, (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
            device.unlockForConfiguration()
        }

        let saved = burstIndex
        let folderName = burstFolder?.lastPathComponent ?? ""
        burstFolder = nil
        if let error {
            setStatus("Burst failed after \(saved): \(error.localizedDescription)")
        } else {
            setStatus("Saved \(saved) DNGs → \(folderName)")
        }
        DispatchQueue.main.async { self.isCapturing = false }
    }

    private func setStatus(_ text: String) {
        DispatchQueue.main.async { self.status = text }
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        sessionQueue.async {
            guard let folder = self.burstFolder else { return }
            if error == nil, let data = photo.fileDataRepresentation() {
                let url = folder.appendingPathComponent(String(format: "frame_%02d.dng", self.burstIndex))
                try? data.write(to: url)
            }
            self.burstIndex += 1
            self.setStatus("Capturing \(self.burstIndex)/\(self.burstTotal)…")

            if error != nil || self.burstIndex >= self.burstTotal {
                self.finishBurst(error: error)
            } else if let raw = self.rawFormat {
                self.captureNext(raw: raw)
            } else {
                self.finishBurst(error: nil)
            }
        }
    }
}
