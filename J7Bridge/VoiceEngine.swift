import Foundation
import AVFoundation

final class VoiceEngine: NSObject {
    private let audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    private let playerNode = AVAudioPlayerNode()
    private var playerAttached = false
    private var isRunning = false
    private var converter: AVAudioConverter?
    private var useSpeaker = true
    private var muted = false

    var onAMRPacket: ((Data) -> Void)?
    var onStatus: ((String) -> Void)?

    private let codec = AMRCodecAdapter()
    private var pcmAccumulator: [Int16] = []
    private let codecQueue = DispatchQueue(label: "com.ugur.callshare.amr", qos: .userInitiated)

    func setSpeakerDefault(_ enabled: Bool) {
        useSpeaker = enabled
        if isRunning { applySessionCategory() }
    }

    func setMuted(_ value: Bool) {
        muted = value
        onStatus?(value ? "MUTED" : "UNMUTED")
    }

    /// CallKit must activate the audio session before this is called.
    func start() {
        guard !isRunning else { return }

        do {
            applySessionCategory()

            let input = audioEngine.inputNode
            let hardwareFormat = input.inputFormat(forBus: 0)
            guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
                throw NSError(domain: "J7Bridge.Audio", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "No input audio route"])
            }

            let target = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                       sampleRate: 8_000,
                                       channels: 1,
                                       interleaved: false)!
            converter = AVAudioConverter(from: hardwareFormat, to: target)

            if !playerAttached {
                audioEngine.attach(playerNode)
                audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: target)
                playerAttached = true
            }

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { [weak self] buffer, _ in
                self?.processPCM(buffer, target: target)
            }

            audioEngine.prepare()
            try audioEngine.start()
            playerNode.play()

            isRunning = true
            pcmAccumulator.removeAll(keepingCapacity: true)
            onStatus?("OPEN / AMR-NB MR515 / 8k")
        } catch {
            inputRemoveTapSafely()
            playerNode.stop()
            converter = nil
            onStatus?("ERROR \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isRunning || audioEngine.isRunning else { return }
        inputRemoveTapSafely()
        playerNode.stop()
        audioEngine.stop()
        converter = nil
        pcmAccumulator.removeAll(keepingCapacity: true)
        isRunning = false
        onStatus?("CLOSED")
    }

    func receiveAMR(_ packet: Data) {
        guard !packet.isEmpty, isRunning else { return }

        codecQueue.async { [weak self] in
            guard let self else { return }
            guard let pcm = self.codec.decode(packet) else {
                self.onStatus?("AMR DECODE ERROR / \(packet.count) bytes")
                return
            }
            self.schedulePlayback(pcm)
        }
    }

    private func schedulePlayback(_ pcm: [Int16]) {
        guard isRunning else { return }

        let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                   sampleRate: 8_000,
                                   channels: 1,
                                   interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(pcm.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(pcm.count)

        guard let channel = buffer.int16ChannelData?[0] else { return }
        pcm.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: pcm.count)
        }

        playerNode.scheduleBuffer(buffer)
    }

    private func applySessionCategory() {
        var options: AVAudioSession.CategoryOptions = [.allowBluetooth]
        if useSpeaker { options.insert(.defaultToSpeaker) }
        try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: options)
        try? audioSession.setPreferredSampleRate(8_000)
    }

    private func inputRemoveTapSafely() {
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func processPCM(_ buffer: AVAudioPCMBuffer, target: AVAudioFormat) {
        guard isRunning, let converter else { return }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        var error: NSError?
        var supplied = false
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }

        guard error == nil else { return }
        emit8kFrames(output)
    }

    private func emit8kFrames(_ buffer: AVAudioPCMBuffer) {
        guard let pointer = buffer.int16ChannelData?[0] else { return }
        pcmAccumulator.append(contentsOf: UnsafeBufferPointer(start: pointer,
                                                              count: Int(buffer.frameLength)))

        while pcmAccumulator.count >= 160 {
            let frame = Array(pcmAccumulator.prefix(160))
            pcmAccumulator.removeFirst(160)
            guard !muted else { continue }

            codecQueue.async { [weak self] in
                guard let self, let amr = self.codec.encode160(frame) else { return }
                self.onAMRPacket?(amr)
            }
        }
    }
}

private final class AMRCodecAdapter {
    func encode160(_ pcm8k: [Int16]) -> Data? {
        guard pcm8k.count == 160 else { return nil }

        var out = [UInt8](repeating: 0, count: 64)
        let length = pcm8k.withUnsafeBufferPointer { pcm in
            out.withUnsafeMutableBufferPointer { dst in
                amr_codec_encode_frame(pcm.baseAddress, pcm.count,
                                       dst.baseAddress, dst.count)
            }
        }
        guard length > 0, length <= out.count else { return nil }
        return Data(out.prefix(Int(length)))
    }

    func decode(_ amr: Data) -> [Int16]? {
        guard !amr.isEmpty else { return nil }

        var pcm = [Int16](repeating: 0, count: 160)
        let result = amr.withUnsafeBytes { raw in
            pcm.withUnsafeMutableBufferPointer { dst in
                amr_codec_decode_frame(raw.bindMemory(to: UInt8.self).baseAddress,
                                       amr.count,
                                       dst.baseAddress,
                                       dst.count)
            }
        }
        return result == 160 ? pcm : nil
    }

    deinit {
        amr_codec_reset()
    }
}
