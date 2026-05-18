import Foundation
import AVFoundation
import CoreMedia

enum AudioGenError: LocalizedError {
    case cannotCreateBlockBuffer
    case cannotCopyData
    case cannotCreateSampleBuffer
    case cannotCreateFormatDescription
    case cannotAddInput
    case cannotStartWriting
    case appendFailed
    case writingFailed

    var errorDescription: String? {
        switch self {
        case .cannotCreateBlockBuffer: return "Could not create CMBlockBuffer."
        case .cannotCopyData: return "Could not copy audio data."
        case .cannotCreateSampleBuffer: return "Could not create CMSampleBuffer."
        case .cannotCreateFormatDescription: return "Could not create audio format description."
        case .cannotAddInput: return "Could not add audio writer input."
        case .cannotStartWriting: return "Could not start writing audio file."
        case .appendFailed: return "Failed to append audio samples."
        case .writingFailed: return "Audio file writing failed."
        }
    }
}

class AudioTrackGenerator {
    static let sampleRate: Double = 44100
    static let trackDuration: TimeInterval = 180 // 3 minutes

    // MARK: - Public API

    static func cachedURL(for preset: AudioPreset) -> URL {
        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.custom.screenrecorder/audio", isDirectory: true)
        return cacheDir.appendingPathComponent("\(preset.rawValue).m4a")
    }

    static func ensureTrack(_ preset: AudioPreset) async throws -> URL {
        let url = cachedURL(for: preset)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        try await generate(preset, to: url)
        return url
    }

    // MARK: - Generation

    private static func generate(_ preset: AudioPreset, to outputURL: URL) async throws {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Render samples on a background task
        let samples: [Float] = await Task.detached(priority: .userInitiated) {
            switch preset {
            case .calm: return renderCalm()
            case .adventurous: return renderAdventurous()
            case .electronic: return renderElectronic()
            }
        }.value

        try await encodeToAAC(samples: samples, to: outputURL)
    }

    // MARK: - Synthesis primitives

    private static func midiToFreq(_ note: Int) -> Double {
        return 440.0 * pow(2.0, Double(note - 69) / 12.0)
    }

    private static func sine(_ freq: Double, _ t: Double) -> Float {
        Float(sin(2 * .pi * freq * t))
    }

    private static func square(_ freq: Double, _ t: Double) -> Float {
        sin(2 * .pi * freq * t) > 0 ? 1.0 : -1.0
    }

    private static func sawtooth(_ freq: Double, _ t: Double) -> Float {
        let period = 1.0 / freq
        let phase = t.truncatingRemainder(dividingBy: period) / period
        return Float(2.0 * phase - 1.0)
    }

    private static func adsr(t: Double, a: Double, d: Double, s: Double, r: Double, dur: Double) -> Float {
        if t < 0 || t >= dur { return 0 }
        if t < a {
            return Float(t / a)
        } else if t < a + d {
            return Float(1.0 - (t - a) / d * (1.0 - s))
        } else if t < dur - r {
            return Float(s)
        } else {
            return Float(s * (1.0 - (t - (dur - r)) / r))
        }
    }

    // MARK: - Calm (C major, 70 BPM, pad + arpeggio)

    private static func renderCalm() -> [Float] {
        let total = Int(trackDuration * sampleRate)
        var out = [Float](repeating: 0, count: total * 2)

        let chordDuration = 8.0
        let bpm = 70.0
        let beat = 60.0 / bpm

        // Cmaj7, Am7, Fmaj7, G7
        let chords: [[Int]] = [
            [60, 64, 67, 71],
            [57, 60, 64, 67],
            [53, 57, 60, 64],
            [55, 59, 62, 65],
        ]

        for frame in 0..<total {
            let t = Double(frame) / sampleRate
            let chordIdx = Int(t / chordDuration) % chords.count
            let timeInChord = t.truncatingRemainder(dividingBy: chordDuration)
            let chord = chords[chordIdx]

            // Slow chord envelope (long attack and release inside the 8s window)
            let chordEnv = adsr(t: timeInChord, a: 1.0, d: 0.5, s: 0.85, r: 1.5, dur: chordDuration)

            // Sine pad — 4 voices stacking the chord tones
            var pad: Float = 0
            for note in chord {
                pad += sine(midiToFreq(note), t) * 0.04
            }
            pad *= chordEnv

            // Arpeggio (one note per beat, octave up)
            let arpIdx = Int(timeInChord / beat) % chord.count
            let timeInBeat = timeInChord.truncatingRemainder(dividingBy: beat)
            let arpEnv = adsr(t: timeInBeat, a: 0.05, d: 0.4, s: 0.0, r: 0.0, dur: beat)
            let arpNote = chord[arpIdx] + 12
            let arp = sine(midiToFreq(arpNote), t) * 0.07 * arpEnv

            let stereo = pad + arp
            out[frame * 2] = stereo
            out[frame * 2 + 1] = stereo
        }

        // Soft master limiter to avoid clipping
        applySoftLimit(&out)
        return out
    }

    // MARK: - Adventurous (A minor, 110 BPM, bass + lead + kick)

    private static func renderAdventurous() -> [Float] {
        let total = Int(trackDuration * sampleRate)
        var out = [Float](repeating: 0, count: total * 2)

        let bpm = 110.0
        let beat = 60.0 / bpm
        let chordDuration = beat * 4

        // Am, F, C, G — bass roots
        let bassNotes = [45, 41, 36, 43]

        // 8-note motifs per chord (8th notes outlining chord tones with a passing tone)
        let leadMotifs: [[Int]] = [
            [69, 72, 76, 72, 69, 67, 69, 72], // Am
            [65, 69, 72, 69, 65, 64, 65, 69], // F
            [60, 64, 67, 64, 60, 59, 60, 64], // C
            [67, 71, 74, 71, 67, 66, 67, 71], // G
        ]

        for frame in 0..<total {
            let t = Double(frame) / sampleRate
            let chordIdx = Int(t / chordDuration) % 4
            let timeInChord = t.truncatingRemainder(dividingBy: chordDuration)

            // Bass on beats 1 and 3 (half-note duration)
            let bassNote = bassNotes[chordIdx]
            let bassPhase = timeInChord.truncatingRemainder(dividingBy: beat * 2)
            let bassEnv = adsr(t: bassPhase, a: 0.02, d: 0.3, s: 0.45, r: 0.4, dur: beat * 2)
            let bass = square(midiToFreq(bassNote), t) * 0.09 * bassEnv

            // Lead — 8th notes
            let motif = leadMotifs[chordIdx]
            let eighth = beat / 2
            let leadIdx = Int(timeInChord / eighth) % motif.count
            let leadPhase = timeInChord.truncatingRemainder(dividingBy: eighth)
            let leadEnv = adsr(t: leadPhase, a: 0.005, d: 0.08, s: 0.45, r: 0.05, dur: eighth)
            let leadNote = motif[leadIdx]
            let lead = sawtooth(midiToFreq(leadNote), t) * 0.07 * leadEnv

            // Kick on beats 1 and 3
            let beatIdx = Int(timeInChord / beat) % 4
            var kick: Float = 0
            if beatIdx == 0 || beatIdx == 2 {
                let beatPhase = timeInChord.truncatingRemainder(dividingBy: beat)
                if beatPhase < 0.15 {
                    let kf = 60.0 - 30.0 * (beatPhase / 0.15)
                    let ke = Float(max(0, 1.0 - beatPhase / 0.12))
                    kick = sine(kf, beatPhase) * 0.18 * ke
                }
            }

            let stereo = bass + lead + kick
            out[frame * 2] = stereo
            out[frame * 2 + 1] = stereo
        }

        applySoftLimit(&out)
        return out
    }

    // MARK: - Electronic (A minor, 124 BPM, kick + hat + bass + arp)

    private static func renderElectronic() -> [Float] {
        let total = Int(trackDuration * sampleRate)
        var out = [Float](repeating: 0, count: total * 2)

        let bpm = 124.0
        let beat = 60.0 / bpm
        let eighth = beat / 2
        let sixteenth = beat / 4

        let bassNote = 33 // A1
        // 8th-note pattern over 4 beats: 1, _, 1-and, _, _, _, 4, _ (syncopated)
        let bassPattern: [Bool] = [true, false, true, false, false, true, false, true]

        // Arpeggio rotates chord every 8 beats: Am, C, G, F
        let chordSet: [[Int]] = [
            [57, 60, 64, 67],
            [60, 64, 67, 72],
            [55, 59, 62, 67],
            [53, 57, 60, 65],
        ]
        let chordSpan = beat * 8

        // Fast pseudo-random for hi-hat noise
        var rngState: UInt32 = 0x12345
        @inline(__always) func nextNoise() -> Float {
            rngState = 1664525 &* rngState &+ 1013904223
            let bits = (rngState >> 8) & 0xFFFFFF
            return Float(bits) / Float(0xFFFFFF) * 2.0 - 1.0
        }

        // Simple one-pole lowpass state for hi-hat
        var hatLpState: Float = 0
        let hatLpCutoff: Float = 0.35 // ~smoothing factor for filtered noise

        for frame in 0..<total {
            let t = Double(frame) / sampleRate

            // Kick — every quarter
            let beatPhase = t.truncatingRemainder(dividingBy: beat)
            var kick: Float = 0
            if beatPhase < 0.1 {
                let kf = 70.0 - 35.0 * (beatPhase / 0.1)
                let ke = Float(max(0, 1.0 - beatPhase / 0.08))
                kick = sine(kf, beatPhase) * 0.22 * ke
            }

            // Hi-hat — off-beat 8th notes
            let eighthPhase = t.truncatingRemainder(dividingBy: eighth)
            let eighthIdx = Int(t / eighth) % 2
            var hat: Float = 0
            // Generate filtered noise continuously, gate on off-beat
            let rawNoise = nextNoise()
            hatLpState = hatLpState + hatLpCutoff * (rawNoise - hatLpState)
            let filtered = rawNoise - hatLpState // highpass approximation (raw - lowpass)
            if eighthIdx == 1 && eighthPhase < 0.04 {
                let env = Float(max(0, 1.0 - eighthPhase / 0.04))
                hat = filtered * 0.08 * env
            }

            // Bass — 8th-note pattern over 4 beats
            let patternSpan = beat * 4
            let timeInPattern = t.truncatingRemainder(dividingBy: patternSpan)
            let bassIdx = Int(timeInPattern / eighth) % bassPattern.count
            var bass: Float = 0
            if bassPattern[bassIdx] {
                let bassPhase = timeInPattern.truncatingRemainder(dividingBy: eighth)
                let env = adsr(t: bassPhase, a: 0.003, d: 0.06, s: 0.35, r: 0.08, dur: eighth)
                bass = square(midiToFreq(bassNote), t) * 0.13 * env
            }

            // Arpeggio — 16th notes, chord rotates every 8 beats
            let chordIdx = Int(t / chordSpan) % chordSet.count
            let timeInChord = t.truncatingRemainder(dividingBy: chordSpan)
            let arpIdx = Int(timeInChord / sixteenth) % 4
            let arpPhase = timeInChord.truncatingRemainder(dividingBy: sixteenth)
            let arpEnv = adsr(t: arpPhase, a: 0.001, d: 0.04, s: 0.2, r: 0.02, dur: sixteenth)
            let arpNote = chordSet[chordIdx][arpIdx] + 12
            let arp = sawtooth(midiToFreq(arpNote), t) * 0.05 * arpEnv

            let stereo = kick + hat + bass + arp
            out[frame * 2] = stereo
            out[frame * 2 + 1] = stereo
        }

        applySoftLimit(&out)
        return out
    }

    // MARK: - Soft limiter (tanh) — protects against clipping
    private static func applySoftLimit(_ samples: inout [Float]) {
        for i in 0..<samples.count {
            let x = samples[i]
            // Gentle tanh-ish soft clipping
            samples[i] = tanh(x * 1.2) * 0.95
        }
    }

    // MARK: - AAC Encoding

    private static func encodeToAAC(samples: [Float], to outputURL: URL) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 96000,
        ]

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        guard writer.canAdd(input) else { throw AudioGenError.cannotAddInput }
        writer.add(input)

        guard writer.startWriting() else { throw AudioGenError.cannotStartWriting }
        writer.startSession(atSourceTime: .zero)

        // Build source format description (float PCM, interleaved stereo, 44.1k)
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var formatDesc: CMAudioFormatDescription?
        let fdStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        guard fdStatus == noErr, let format = formatDesc else {
            throw AudioGenError.cannotCreateFormatDescription
        }

        // Feed samples in chunks of 4096 frames (2 channels each)
        let chunkFrames = 4096
        let totalFrames = samples.count / 2
        var frameIndex = 0

        while frameIndex < totalFrames {
            let framesInChunk = min(chunkFrames, totalFrames - frameIndex)

            // Wait for writer input to be ready
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }

            try appendChunk(
                samples: samples,
                startFrame: frameIndex,
                framesCount: framesInChunk,
                format: format,
                input: input
            )

            frameIndex += framesInChunk
        }

        input.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw writer.error ?? AudioGenError.writingFailed
        }
    }

    private static func appendChunk(
        samples: [Float],
        startFrame: Int,
        framesCount: Int,
        format: CMAudioFormatDescription,
        input: AVAssetWriterInput
    ) throws {
        let bytesPerFrame = 8 // 2 channels * 4 bytes
        let dataSize = framesCount * bytesPerFrame

        // Create CMBlockBuffer that allocates its own memory
        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let bb = blockBuffer else {
            throw AudioGenError.cannotCreateBlockBuffer
        }

        // Copy float samples into the block buffer
        let startSample = startFrame * 2
        try samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { throw AudioGenError.cannotCopyData }
            let copyStatus = CMBlockBufferReplaceDataBytes(
                with: UnsafeRawPointer(base.advanced(by: startSample)),
                blockBuffer: bb,
                offsetIntoDestination: 0,
                dataLength: dataSize
            )
            guard copyStatus == noErr else { throw AudioGenError.cannotCopyData }
        }

        // Create CMSampleBuffer
        var sampleBuffer: CMSampleBuffer?
        let pts = CMTime(value: CMTimeValue(startFrame), timescale: CMTimeScale(sampleRate))
        status = CMAudioSampleBufferCreateWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: bb,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: framesCount,
            presentationTimeStamp: pts,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sb = sampleBuffer else {
            throw AudioGenError.cannotCreateSampleBuffer
        }

        if !input.append(sb) {
            throw AudioGenError.appendFailed
        }
    }
}
