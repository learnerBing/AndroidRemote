import Foundation
import AVFoundation

#if canImport(WebRTC)
import WebRTC

/// Custom WebRTC audio device that feeds ReplayKit app/mic PCM into the sender track.
/// Send-only: no playout in the broadcast extension (saves memory vs AVAudioEngine).
final class ReplayKitAudioDevice: NSObject, RTCAudioDevice, @unchecked Sendable {
    static let shared = ReplayKitAudioDevice()

    private let appBuffer = ReplayKitAudioRingBuffer()
    private let micBuffer = ReplayKitAudioRingBuffer()
    private let queue = DispatchQueue(label: "com.androidremote.replaykit-audio")

    private var delegate_: RTCAudioDeviceDelegate?
    private var shouldRecord = false
    private var recordTimer: DispatchSourceTimer?
    private var pcmScratch = [Int16](repeating: 0, count: 4800)

    private var delegate: RTCAudioDeviceDelegate? {
        get { queue.sync { delegate_ } }
        set { queue.sync { delegate_ = newValue } }
    }

    var deviceInputSampleRate: Double { Double(ReplayKitAudioRingBuffer.sampleRate) }
    var inputIOBufferDuration: TimeInterval { 0.01 }
    var inputNumberOfChannels: Int { 1 }
    var inputLatency: TimeInterval { 0.01 }

    var deviceOutputSampleRate: Double { Double(ReplayKitAudioRingBuffer.sampleRate) }
    var outputIOBufferDuration: TimeInterval { 0.01 }
    var outputNumberOfChannels: Int { 1 }
    var outputLatency: TimeInterval { 0 }

    var isInitialized: Bool { delegate != nil }
    var isPlayoutInitialized: Bool { true }
    var isPlaying: Bool { false }
    var isRecordingInitialized: Bool { true }
    var isRecording: Bool { queue.sync { shouldRecord } }

    func initialize(with delegate: RTCAudioDeviceDelegate) -> Bool {
        self.delegate = delegate
        ARLog.info("WebRTC", "ReplayKitAudioDevice initialized")
        return true
    }

    func terminateDevice() -> Bool {
        stopRecording()
        delegate = nil
        appBuffer.clear()
        micBuffer.clear()
        return true
    }

    func initializePlayout() -> Bool { true }
    func startPlayout() -> Bool { true }
    func stopPlayout() -> Bool { true }
    func initializeRecording() -> Bool { true }

    func startRecording() -> Bool {
        queue.sync { shouldRecord = true }
        delegate?.dispatchAsync { [weak self] in
            self?.startRecordPump()
        }
        ARLog.info("WebRTC", "ReplayKitAudioDevice recording started")
        return true
    }

    func stopRecording() -> Bool {
        queue.sync { shouldRecord = false }
        recordTimer?.cancel()
        recordTimer = nil
        return true
    }

    func pushAppSample(_ sampleBuffer: CMSampleBuffer) {
        guard let pcm = ReplayKitAudioExtractor.monoInt16(from: sampleBuffer) else { return }
        appBuffer.append(pcm)
    }

    func pushMicSample(_ sampleBuffer: CMSampleBuffer) {
        guard let pcm = ReplayKitAudioExtractor.monoInt16(from: sampleBuffer) else { return }
        micBuffer.append(pcm)
    }

    private func startRecordPump() {
        recordTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: inputIOBufferDuration)
        timer.setEventHandler { [weak self] in
            self?.deliverRecordedFrame()
        }
        recordTimer = timer
        timer.resume()
    }

    private func deliverRecordedFrame() {
        guard shouldRecord, let delegate else { return }
        let frameCount = UInt32(deviceInputSampleRate * inputIOBufferDuration)
        guard frameCount > 0, Int(frameCount) <= pcmScratch.count else { return }

        pcmScratch.withUnsafeMutableBufferPointer { scratch in
            guard let base = scratch.baseAddress else { return }
            mixIntoOutput(base, frameCount: Int(frameCount))

            var audioBuffer = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(frameCount * UInt32(MemoryLayout<Int16>.size)),
                mData: UnsafeMutableRawPointer(base)
            )
            var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
            var flags: AudioUnitRenderActionFlags = []
            var timestamp = AudioTimeStamp()
            timestamp.mFlags = .sampleTimeValid
            _ = delegate.deliverRecordedData(
                &flags,
                &timestamp,
                0,
                frameCount,
                &bufferList,
                nil,
                nil
            )
        }
    }

    private func mixIntoOutput(_ output: UnsafeMutablePointer<Int16>, frameCount: Int) {
        var appScratch = [Int16](repeating: 0, count: frameCount)
        var micScratch = [Int16](repeating: 0, count: frameCount)
        appScratch.withUnsafeMutableBufferPointer { appBuffer.read(into: $0.baseAddress!, frameCount: frameCount) }
        micScratch.withUnsafeMutableBufferPointer { micBuffer.read(into: $0.baseAddress!, frameCount: frameCount) }
        for index in 0..<frameCount {
            let mixed = Int32(appScratch[index]) + Int32(micScratch[index])
            let clamped = max(Int32(Int16.min), min(Int32(Int16.max), mixed / 2))
            output[index] = Int16(clamped)
        }
    }
}
#endif
