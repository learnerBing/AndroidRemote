import Foundation
import CoreMedia

/// Small thread-safe mono PCM ring buffer for ReplayKit → WebRTC audio (extension memory budget).
final class ReplayKitAudioRingBuffer: @unchecked Sendable {
    static let sampleRate: Int = 48_000
    /// ~250 ms at 48 kHz mono Int16 (~24 KB).
    private static let capacitySamples = sampleRate / 4

    private var storage: [Int16]
    private var writeIndex = 0
    private var readIndex = 0
    private var available = 0
    private let lock = NSLock()

    init() {
        storage = [Int16](repeating: 0, count: Self.capacitySamples)
    }

    func append(_ samples: [Int16]) {
        guard !samples.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        for sample in samples {
            storage[writeIndex] = sample
            writeIndex = (writeIndex + 1) % storage.count
            if available < storage.count {
                available += 1
            } else {
                readIndex = (readIndex + 1) % storage.count
            }
        }
    }

    func read(into output: UnsafeMutablePointer<Int16>, frameCount: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let toRead = min(frameCount, available)
        for index in 0..<toRead {
            output[index] = storage[readIndex]
            readIndex = (readIndex + 1) % storage.count
        }
        available -= toRead
        if toRead < frameCount {
            memset(output.advanced(by: toRead), 0, (frameCount - toRead) * MemoryLayout<Int16>.size)
        }
        return toRead
    }

    func clear() {
        lock.lock()
        writeIndex = 0
        readIndex = 0
        available = 0
        lock.unlock()
    }
}

enum ReplayKitAudioExtractor {
    /// Downmix ReplayKit PCM (Float32 or Int16, interleaved or planar) to mono Int16 at 48 kHz.
    static func monoInt16(from sampleBuffer: CMSampleBuffer) -> [Int16]? {
        guard CMSampleBufferGetNumSamples(sampleBuffer) > 0,
              let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }
        let asbd = asbdPtr.pointee
        let sourceRate = asbd.mSampleRate
        let channels = max(1, Int(asbd.mChannelsPerFrame))
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isPlanar = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0

        var requiredSize = 0
        let probeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: nil
        )
        guard probeStatus == noErr, requiredSize > 0 else { return nil }

        let listMemory = UnsafeMutableRawPointer.allocate(
            byteCount: requiredSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { listMemory.deallocate() }

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: listMemory.assumingMemoryBound(to: AudioBufferList.self),
            bufferListSize: requiredSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        defer {
            if let blockBuffer {
                Unmanaged.passUnretained(blockBuffer).release()
            }
        }
        guard status == noErr else { return nil }

        let audioBufferList = listMemory.assumingMemoryBound(to: AudioBufferList.self).pointee
        var mono = [Float](repeating: 0, count: frameCount)

        if isPlanar {
            let bufferCount = Int(audioBufferList.mNumberBuffers)
            guard bufferCount > 0 else { return nil }
            let buffersPointer = listMemory
                .advanced(by: MemoryLayout<AudioBufferList>.offset(of: \AudioBufferList.mBuffers)!)
                .assumingMemoryBound(to: AudioBuffer.self)
            for frame in 0..<frameCount {
                var sum: Float = 0
                let activeChannels = min(channels, bufferCount)
                for channel in 0..<activeChannels {
                    let buffer = buffersPointer[channel]
                    guard let data = buffer.mData else { continue }
                    let bytesPerSample = isFloat ? MemoryLayout<Float32>.size : MemoryLayout<Int16>.size
                    let offset = frame * bytesPerSample
                    guard offset + bytesPerSample <= Int(buffer.mDataByteSize) else { continue }
                    if isFloat {
                        var value: Float32 = 0
                        memcpy(&value, data.advanced(by: offset), MemoryLayout<Float32>.size)
                        sum += value
                    } else {
                        var value: Int16 = 0
                        memcpy(&value, data.advanced(by: offset), MemoryLayout<Int16>.size)
                        sum += Float(value) / Float(Int16.max)
                    }
                }
                mono[frame] = sum / Float(activeChannels)
            }
        } else {
            let buffer = audioBufferList.mBuffers
            guard let baseAddress = buffer.mData else { return nil }
            let bytesPerSample = isFloat ? MemoryLayout<Float32>.size : MemoryLayout<Int16>.size
            for frame in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channels {
                    let offset = (frame * channels + channel) * bytesPerSample
                    if isFloat {
                        var value: Float32 = 0
                        memcpy(&value, baseAddress.advanced(by: offset), MemoryLayout<Float32>.size)
                        sum += value
                    } else {
                        var value: Int16 = 0
                        memcpy(&value, baseAddress.advanced(by: offset), MemoryLayout<Int16>.size)
                        sum += Float(value) / Float(Int16.max)
                    }
                }
                mono[frame] = sum / Float(channels)
            }
        }

        let normalized: [Int16]
        if abs(sourceRate - Double(ReplayKitAudioRingBuffer.sampleRate)) < 1 {
            normalized = mono.map { sample in
                let clamped = max(-1, min(1, sample))
                return Int16(clamped * Float(Int16.max))
            }
        } else {
            let ratio = Double(ReplayKitAudioRingBuffer.sampleRate) / sourceRate
            let outCount = max(1, Int(Double(frameCount) * ratio))
            var resampled = [Int16]()
            resampled.reserveCapacity(outCount)
            for index in 0..<outCount {
                let sourcePos = Double(index) / ratio
                let lower = Int(sourcePos)
                let upper = min(lower + 1, frameCount - 1)
                let fraction = Float(sourcePos - Double(lower))
                let value = mono[lower] * (1 - fraction) + mono[upper] * fraction
                let clamped = max(-1, min(1, value))
                resampled.append(Int16(clamped * Float(Int16.max)))
            }
            normalized = resampled
        }
        return normalized
    }
}
