import Foundation
import AVFoundation
import CoreImage

#if canImport(WebRTC)
import WebRTC
#endif

#if canImport(WebRTC)
private final class FramePusher: RTCVideoCapturer {}
#endif

/// WebRTC sender used by the Broadcast Upload Extension (offerer role).
/// Link GoogleWebRTC via SPM to enable real streaming.
final class WebRtcBroadcastEngine: NSObject, @unchecked Sendable {

    private let signaling: SignalingClient
    private let streamConfig: StreamConfig
    private let extensionSignalingServer = ExtensionSignalingServer()
    private var activeSessionId: String?

#if canImport(WebRTC)
    private var factory: RTCPeerConnectionFactory?
    private var peerConnection: RTCPeerConnection?
    private var videoSource: RTCVideoSource?
    private var videoCapturer: RTCVideoCapturer?
    private var localIceCandidates: [IceCandidate] = []
    private var icePollTask: Task<Void, Never>?
    private var iceRepublishTask: Task<Void, Never>?
    private var offerSent = false
    private var iceGatheringContinuations: [CheckedContinuation<Void, Never>] = []
    private var lastAdaptedLayout: ScreenVideoLayout?
    private var ciContext: CIContext?
    private let factoryQueue = DispatchQueue(label: "com.androidremote.webrtc")
#endif

    /// Called once video capture pipeline is ready (before SDP exchange completes).
    var onCaptureReady: (() -> Void)?

    init(signaling: SignalingClient, streamConfig: StreamConfig = StreamConfig()) {
        self.signaling = signaling
        self.streamConfig = streamConfig
        super.init()
    }

    func start(session: SessionStore.Snapshot) async throws {
        ARLog.info("WebRTC", "start session=\(ARLog.sessionPrefix(session.sessionId)) transport=\(session.transport.rawValue) relay=\(session.signalingHost):\(session.signalingPort)")
        signaling.bind(snapshot: session)
        activeSessionId = session.sessionId

        if session.transport == .castReceiver {
            extensionSignalingServer.registerSession(session.sessionId)
            do {
                try extensionSignalingServer.start()
            } catch {
                throw CastError.notConfigured
            }
        }
        // directLanRelay: Mac relay handles signaling; extension uses outbound HTTP only.

#if canImport(WebRTC)
        try await startWebRtc(sessionId: session.sessionId)
#else
        throw CastError.webRtcUnavailable
#endif
    }

    func stop() {
        let endingSession = activeSessionId
        ARLog.info("WebRTC", "stop session=\(endingSession.map(ARLog.sessionPrefix) ?? "none")")
        extensionSignalingServer.stop()
        activeSessionId = nil
#if canImport(WebRTC)
        icePollTask?.cancel()
        icePollTask = nil
        iceRepublishTask?.cancel()
        iceRepublishTask = nil
        offerSent = false
        lastAdaptedLayout = nil
        factoryQueue.sync {
            iceGatheringContinuations.removeAll()
            peerConnection?.close()
            peerConnection = nil
            videoSource = nil
            videoCapturer = nil
            ciContext = nil
            factory = nil
            localIceCandidates.removeAll()
        }
        if let endingSession {
            Task {
                try? await signaling.updateSessionStatus(sessionId: endingSession, state: "ended")
            }
        }
#endif
    }

#if canImport(WebRTC)
    func pushVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestampNs = Int64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            * Double(NSEC_PER_SEC))
        let rotation = frameRotation(from: sampleBuffer)

        factoryQueue.async { [weak self] in
            guard let self, let capturer = self.videoCapturer, let source = self.videoSource else { return }
            let (uprightBuffer, layout) = self.uprightPixelBuffer(from: pixelBuffer, rotation: rotation)
            self.updateOutputFormatIfNeeded(for: layout)
            let rtcBuffer = RTCCVPixelBuffer(pixelBuffer: uprightBuffer)
            let frame = RTCVideoFrame(buffer: rtcBuffer, rotation: ._0, timeStampNs: timestampNs)
            source.capturer(capturer, didCapture: frame)
        }
    }

    private func startWebRtc(sessionId: String) async throws {
        ARLog.info("WebRTC", "setupPeerConnection session=\(ARLog.sessionPrefix(sessionId))")
        try await runOnFactoryQueue {
            try self.setupPeerConnection()
        }

        ARLog.info("WebRTC", "createOffer session=\(ARLog.sessionPrefix(sessionId))")
        let offer = try await createOffer()
        ARLog.info("WebRTC", "setLocalDescription session=\(ARLog.sessionPrefix(sessionId)) bytes=\(offer.sdp.count)")
        try await setLocalDescription(offer)

        offerSent = true
        ARLog.info("WebRTC", "sendOffer (initial) session=\(ARLog.sessionPrefix(sessionId)) bytes=\(offer.sdp.count)")
        try await signaling.sendOffer(sessionId: sessionId, sdp: offer.sdp)
        try await flushLocalIceCandidates(sessionId: sessionId)
        ARLog.info("WebRTC", "offer on relay — waiting for answer session=\(ARLog.sessionPrefix(sessionId))")

        startOfferRefreshTask(sessionId: sessionId)
        startLocalIceRepublish(sessionId: sessionId)

        try await exchangeIce(sessionId: sessionId)
        try await runOnFactoryQueue {
            self.applyVideoSenderParameters()
        }
        ARLog.info("WebRTC", "answer applied session=\(ARLog.sessionPrefix(sessionId))")
        startRemoteIcePolling(sessionId: sessionId)
    }

    private func runOnFactoryQueue(_ work: @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            factoryQueue.async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func createOffer() async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            factoryQueue.async { [weak self] in
                guard let pc = self?.peerConnection else {
                    continuation.resume(throwing: CastError.notConfigured)
                    return
                }
                let constraints = RTCMediaConstraints(
                    mandatoryConstraints: [
                        "OfferToReceiveAudio": "false",
                        "OfferToReceiveVideo": "false",
                    ],
                    optionalConstraints: nil
                )
                pc.offer(for: constraints) { sdp, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let sdp else {
                        continuation.resume(throwing: CastError.notConfigured)
                        return
                    }
                    continuation.resume(returning: sdp)
                }
            }
        }
    }

    private func setLocalDescription(_ sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            factoryQueue.async { [weak self] in
                guard let pc = self?.peerConnection else {
                    continuation.resume(throwing: CastError.notConfigured)
                    return
                }
                pc.setLocalDescription(sdp) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func startOfferRefreshTask(sessionId: String) {
        Task { [weak self] in
            guard let self else { return }
            await self.waitForIceGatheringComplete()
            let updated = self.factoryQueue.sync {
                self.peerConnection?.localDescription?.sdp
            }
            guard let updated, !updated.isEmpty else { return }
            try? await self.signaling.sendOffer(sessionId: sessionId, sdp: updated)
            try? await self.flushLocalIceCandidates(sessionId: sessionId)
        }
    }

    private func setupPeerConnection() throws {
        RTCInitializeSSL()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        if let h264 = RTCDefaultVideoEncoderFactory.supportedCodecs().first(where: { $0.name == "H264" }) {
            encoderFactory.preferredCodec = h264
        }
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)

        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let pcConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection = factory?.peerConnection(with: config, constraints: pcConstraints, delegate: self)

        videoSource = factory?.videoSource()
        ciContext = CIContext(options: [.useSoftwareRenderer: false])
        let capturer = FramePusher(delegate: videoSource!)
        videoCapturer = capturer

        guard let videoSource, let pc = peerConnection else {
            throw CastError.notConfigured
        }

        let videoTrack = factory?.videoTrack(with: videoSource, trackId: "screen0")
        guard let videoTrack else {
            throw CastError.notConfigured
        }
        videoTrack.isEnabled = true
        let transceiverInit = RTCRtpTransceiverInit()
        transceiverInit.direction = .sendOnly
        transceiverInit.streamIds = ["screen-stream"]
        let encoding = RTCRtpEncodingParameters()
        encoding.maxBitrateBps = NSNumber(value: streamConfig.maxBitrateKbps * 1000)
        encoding.minBitrateBps = NSNumber(value: streamConfig.minBitrateKbps * 1000)
        encoding.maxFramerate = NSNumber(value: streamConfig.fps)
        transceiverInit.sendEncodings = [encoding]
        pc.addTransceiver(with: videoTrack, init: transceiverInit)
        applyVideoSenderParameters()

        DispatchQueue.main.async { [weak self] in
            self?.onCaptureReady?()
        }
    }

    private func videoLayout(for width: Int, height: Int) -> ScreenVideoLayout {
        width >= height ? .landscape : .portrait
    }

    private func updateOutputFormatIfNeeded(for layout: ScreenVideoLayout) {
        guard let videoSource else { return }
        guard layout != lastAdaptedLayout else { return }
        lastAdaptedLayout = layout

        let (width, height) = streamConfig.outputDimensions(for: layout)
        videoSource.adaptOutputFormat(
            toWidth: Int32(width),
            height: Int32(height),
            fps: Int32(streamConfig.fps)
        )
        ARLog.info(
            "WebRTC",
            "adaptOutputFormat \(width)x\(height) layout=\(layout == .portrait ? "portrait" : "landscape")"
        )
        scheduleOfferRefreshAfterLayoutChange()
    }

    private func scheduleOfferRefreshAfterLayoutChange() {
        guard let sessionId = activeSessionId, offerSent else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self else { return }
            let sdp = self.factoryQueue.sync { self.peerConnection?.localDescription?.sdp }
            guard let sdp, !sdp.isEmpty else { return }
            try? await self.signaling.sendOffer(sessionId: sessionId, sdp: sdp)
            ARLog.info("WebRTC", "offer refresh after orientation change session=\(ARLog.sessionPrefix(sessionId))")
        }
    }

    private func uprightPixelBuffer(
        from pixelBuffer: CVPixelBuffer,
        rotation: RTCVideoRotation
    ) -> (CVPixelBuffer, ScreenVideoLayout) {
        if rotation == ._0 {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            return (pixelBuffer, videoLayout(for: width, height: height))
        }
        guard let ciContext else {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            return (pixelBuffer, videoLayout(for: width, height: height))
        }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
            .oriented(forExifOrientation: exifOrientation(for: rotation))
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)

        var outBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: CVPixelBufferGetPixelFormatType(pixelBuffer),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            CVPixelBufferGetPixelFormatType(pixelBuffer),
            attrs as CFDictionary,
            &outBuffer
        )
        guard let outBuffer else {
            return (pixelBuffer, videoLayout(for: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer)))
        }
        ciContext.render(image, to: outBuffer)
        return (outBuffer, videoLayout(for: width, height: height))
    }

    private func exifOrientation(for rotation: RTCVideoRotation) -> Int32 {
        switch rotation {
        case ._90: return 6
        case ._180: return 3
        case ._270: return 8
        default: return 1
        }
    }

    private func applyVideoSenderParameters() {
        guard let pc = peerConnection else { return }
        guard let sender = pc.senders.first(where: { $0.track?.kind == "video" }) else { return }

        var params = sender.parameters
        if params.encodings.isEmpty {
            params.encodings = [RTCRtpEncodingParameters()]
        }
        let maxBps = streamConfig.maxBitrateKbps * 1000
        let minBps = streamConfig.minBitrateKbps * 1000
        for index in params.encodings.indices {
            params.encodings[index].maxBitrateBps = NSNumber(value: maxBps)
            params.encodings[index].minBitrateBps = NSNumber(value: minBps)
            params.encodings[index].maxFramerate = NSNumber(value: streamConfig.fps)
        }
        params.degradationPreference = NSNumber(value: RTCDegradationPreference.maintainResolution.rawValue)
        sender.parameters = params
        ARLog.info(
            "WebRTC",
            "encoder \(streamConfig.width)x\(streamConfig.height)@\(streamConfig.fps) " +
            "bitrate \(streamConfig.minBitrateKbps)-\(streamConfig.maxBitrateKbps) kbps H264"
        )
    }

    private func flushLocalIceCandidates(sessionId: String) async throws {
        let pending = factoryQueue.sync { localIceCandidates }
        for candidate in pending where !candidate.candidate.isEmpty {
            try await signaling.sendIceCandidate(sessionId: sessionId, candidate: candidate)
        }
    }

    private func waitForIceGatheringComplete(timeoutSeconds: Double = 10) async {
        let alreadyComplete = factoryQueue.sync {
            peerConnection?.iceGatheringState == .complete
        }
        if alreadyComplete { return }

        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.factoryQueue.async {
                        if self.peerConnection?.iceGatheringState == .complete {
                            continuation.resume()
                        } else {
                            self.iceGatheringContinuations.append(continuation)
                        }
                    }
                }
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return false
            }
            _ = await group.next()
            group.cancelAll()
        }
        factoryQueue.async {
            self.iceGatheringContinuations.removeAll()
        }
    }

    private func startLocalIceRepublish(sessionId: String) {
        iceRepublishTask?.cancel()
        iceRepublishTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let batch = self.factoryQueue.sync { self.localIceCandidates }
                for candidate in batch where !candidate.candidate.isEmpty {
                    try? await self.signaling.sendIceCandidate(sessionId: sessionId, candidate: candidate)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func startRemoteIcePolling(sessionId: String) {
        icePollTask?.cancel()
        icePollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let remote = try await signaling.pollRemoteIceCandidates(sessionId: sessionId, side: "receiver")
                    for candidate in remote {
                        try await addRemoteCandidate(candidate)
                    }
                    let iceState = self.currentIceConnectionState()
                    if iceState == .connected || iceState == .completed { break }
                } catch {
                    break
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private func currentIceConnectionState() -> RTCIceConnectionState {
        factoryQueue.sync {
            peerConnection?.iceConnectionState ?? .new
        }
    }

    private func exchangeIce(sessionId: String) async throws {
        let answerSdp = try await signaling.pollAnswer(sessionId: sessionId)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            factoryQueue.async { [weak self] in
                guard let self, let pc = self.peerConnection else {
                    continuation.resume(throwing: CastError.notConfigured)
                    return
                }
                let answer = RTCSessionDescription(type: .answer, sdp: answerSdp)
                pc.setRemoteDescription(answer) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }

        // Poll receiver ICE until media path is up (signaling "connected" != ICE connected).
        for _ in 0..<120 {
            let remote = try await signaling.pollRemoteIceCandidates(sessionId: sessionId, side: "receiver")
            for c in remote {
                try await addRemoteCandidate(c)
            }
            let iceState = currentIceConnectionState()
            if iceState == .connected || iceState == .completed { break }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    private func addRemoteCandidate(_ candidate: IceCandidate) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            factoryQueue.async { [weak self] in
                guard let pc = self?.peerConnection else {
                    continuation.resume(throwing: CastError.notConfigured)
                    return
                }
                let ice = RTCIceCandidate(
                    sdp: candidate.candidate,
                    sdpMLineIndex: candidate.sdpMLineIndex,
                    sdpMid: candidate.sdpMid
                )
                pc.add(ice) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func frameRotation(from sampleBuffer: CMSampleBuffer) -> RTCVideoRotation {
        if let orientation = CMGetAttachment(
            sampleBuffer,
            key: RPVideoSampleOrientationKey as CFString,
            attachmentModeOut: nil
        ) as? NSNumber {
            switch orientation.uint32Value {
            case 1: return ._0
            case 3: return ._180
            case 6: return ._90
            case 8: return ._270
            default: return ._0
            }
        }
        return ._0
    }
#endif
}

#if canImport(WebRTC)
extension WebRtcBroadcastEngine: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        guard let sessionId = activeSessionId else { return }
        ARLog.info("WebRTC", "ICE state=\(newState.rawValue) session=\(ARLog.sessionPrefix(sessionId))")
        switch newState {
        case .connected, .completed:
            extensionSignalingServer.updateConnectionState(sessionId, state: "connected")
        case .disconnected, .failed, .closed:
            extensionSignalingServer.updateConnectionState(sessionId, state: "disconnected")
            Task {
                try? await signaling.updateSessionStatus(sessionId: sessionId, state: "disconnected")
            }
        default:
            break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let ice = IceCandidate(
            candidate: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex
        )
        factoryQueue.async { [weak self] in
            guard let self else { return }
            self.localIceCandidates.append(ice)
            guard self.offerSent, let sessionId = self.activeSessionId, !ice.candidate.isEmpty else { return }
            Task {
                try? await self.signaling.sendIceCandidate(sessionId: sessionId, candidate: ice)
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        if newState == .complete {
            factoryQueue.async { [weak self] in
                guard let self else { return }
                let pending = self.iceGatheringContinuations
                self.iceGatheringContinuations.removeAll()
                pending.forEach { $0.resume() }
            }
        }
    }
}
#endif

// ReplayKit orientation key (available without import in extension)
private let RPVideoSampleOrientationKey = "RPVideoSampleOrientationKey"
