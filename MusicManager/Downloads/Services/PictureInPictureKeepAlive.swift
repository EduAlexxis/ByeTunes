import AVKit
import AVFoundation
import UIKit
import CoreMedia

@MainActor
final class PictureInPictureKeepAlive: NSObject {
    static let shared = PictureInPictureKeepAlive()

    private let displayLayer = AVSampleBufferDisplayLayer()
    private let renderer = PictureInPictureRenderer()
    private var hostView: UIView?
    private var pipController: AVPictureInPictureController?
    private var timebase: CMTimebase?
    private var frameTimer: Timer?
    private var possibleObservation: NSKeyValueObservation?
    private var resignObserver: NSObjectProtocol?
    private weak var viewModel: DownloadViewModel?

    private(set) var isEngaged = false

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "pipKeepAliveEnabled")
    }

    var isPictureInPictureActive: Bool {
        pipController?.isPictureInPictureActive ?? false
    }

    func engage(for viewModel: DownloadViewModel) {
        guard isEnabled, !isEngaged else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            Logger.shared.log("[PiP] Picture in Picture is not supported on this device")
            return
        }

        self.viewModel = viewModel
        renderer.reset()
        renderer.configure(size: PictureInPictureRenderer.canvasSize(style: PictureInPictureStyle.current(), maxActive: viewModel.maxConcurrentDownloads))

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            Logger.shared.log("[PiP] Audio session setup failed: \(error.localizedDescription)")
            return
        }

        configureLayer()
        configureController()
        startFrameTimer()
        isEngaged = true

        resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.startPictureInPictureIfPossible(reason: "willResignActive")
            }
        }

        Logger.shared.log("[PiP] Keep-alive engaged")
    }

    func disengage() {
        guard isEngaged else { return }
        isEngaged = false

        frameTimer?.invalidate()
        frameTimer = nil
        possibleObservation = nil
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil

        pipController?.stopPictureInPicture()
        pipController = nil
        displayLayer.flushAndRemoveImage()
        hostView?.removeFromSuperview()
        hostView = nil
        timebase = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        Logger.shared.log("[PiP] Keep-alive disengaged")
    }

    private func configureLayer() {
        var newTimebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &newTimebase
        )
        if let newTimebase {
            CMTimebaseSetTime(newTimebase, time: CMClockGetTime(CMClockGetHostTimeClock()))
            CMTimebaseSetRate(newTimebase, rate: 1)
            displayLayer.controlTimebase = newTimebase
            timebase = newTimebase
        }

        displayLayer.videoGravity = .resizeAspect
        displayLayer.frame = CGRect(x: 0, y: 0, width: 2, height: 2)

        let host = UIView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        host.isUserInteractionEnabled = false
        host.layer.addSublayer(displayLayer)

        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
        window?.addSubview(host)
        hostView = host
    }

    private func configureController() {
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.requiresLinearPlayback = true
        pipController = controller

        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) { _, change in
            Logger.shared.log("[PiP] Possible: \(change.newValue ?? false)")
        }
    }

    private func startFrameTimer() {
        renderFrame()
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func tick() {
        guard let viewModel, viewModel.hasPendingOrActiveDownloads, !viewModel.isPaused else {
            disengage()
            return
        }
        renderFrame()
    }

    private func startPictureInPictureIfPossible(reason: String) {
        guard let controller = pipController, !controller.isPictureInPictureActive else { return }
        guard controller.isPictureInPicturePossible else {
            Logger.shared.log("[PiP] Cannot start (\(reason)): not possible yet")
            return
        }
        controller.startPictureInPicture()
        Logger.shared.log("[PiP] Start requested (\(reason))")
    }

    private func renderFrame() {
        guard let viewModel else { return }
        guard let buffer = renderer.makeFrame(snapshot: viewModel.pictureInPictureSnapshot(), style: PictureInPictureStyle.current(), timebase: timebase) else { return }

        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(buffer)
    }
}

extension PictureInPictureKeepAlive: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        guard !playing else { return }
        Task { @MainActor in
            DownloadViewModel.shared.pauseQueue()
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping @Sendable () -> Void) {
        completionHandler()
    }
}

extension PictureInPictureKeepAlive: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Logger.shared.log("[PiP] Window started")
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Logger.shared.log("[PiP] Failed to start: \(error.localizedDescription)")
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Logger.shared.log("[PiP] Window stopped")
        Task { @MainActor in
            DownloadViewModel.shared.pictureInPictureStopped()
        }
    }
}
