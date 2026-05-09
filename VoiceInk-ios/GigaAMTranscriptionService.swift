//
//  GigaAMTranscriptionService.swift
//  VoiceInk-iOS — Russian fork
//
//  Local Russian transcription via GigaAM-v2 RNNT (Sber, MIT) running on
//  sherpa-onnx. Drop-in alongside WhisperTranscriptionService.swift.
//
//  Model (241 MB int8) lives in Documents/GigaAM-v2-rnnt/. Downloaded on
//  first use by GigaAMModelManager.
//
//  Build prerequisites (one-time, in Xcode):
//   1. Drop SherpaOnnx.xcframework from the sherpa-onnx-vX.Y-ios release into
//      the project, embed & sign it.
//   2. Build Settings → Objective-C Bridging Header → path to
//      SherpaOnnx-Bridging-Header.h that ships with the framework.
//
//  After that, this file compiles. Without sherpa-onnx loaded the symbols
//  below are unresolved at build time — guard with the SHERPA_ONNX flag.
//

import AVFoundation
import Foundation

#if canImport(SherpaOnnx)
import SherpaOnnx
#endif

enum GigaAMTranscriptionError: Error {
    case modelNotReady
    case audioDecodeFailed
    case recognizerInitFailed
    case sherpaUnavailable

    var localizedDescription: String {
        switch self {
        case .modelNotReady:        return "Модель GigaAM не скачана. Открой настройки и скачай 241 MB."
        case .audioDecodeFailed:    return "Не удалось декодировать аудио для GigaAM."
        case .recognizerInitFailed: return "Не удалось инициализировать sherpa-onnx с GigaAM."
        case .sherpaUnavailable:    return "Сборка без sherpa-onnx. Подключи фреймворк в Xcode."
        }
    }
}

struct GigaAMTranscriptionService: TranscriptionService {

    /// Conform to the same TranscriptionService protocol the project uses.
    /// Cloud-only params (apiBaseURL/apiKey/model/language) are ignored.
    func transcribeAudioFile(
        apiBaseURL: URL,
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String? = nil
    ) async throws -> String {
        let mgr = await GigaAMModelManager.shared
        let isReady = await mgr.isReady
        guard isReady else { throw GigaAMTranscriptionError.modelNotReady }
        let modelDir = await mgr.modelDir

        // Decode the recorded audio (any format — m4a/wav/aac) into mono
        // 16 kHz Float32 PCM. AVAudioConverter handles arbitrary inputs.
        let pcm = try Self.decodeToFloat32Mono16k(url: fileURL)

        return try await Self.transcribe(pcm: pcm, modelDir: modelDir)
    }

    func verifyAPIKey(apiBaseURL: URL, _ apiKey: String) async -> Bool {
        await GigaAMModelManager.shared.isReady
    }

    // MARK: - Audio decode

    static func decodeToFloat32Mono16k(url: URL) throws -> [Float] {
        let inFile = try AVAudioFile(forReading: url)
        let inFmt = inFile.processingFormat
        guard let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: 16000,
                                         channels: 1,
                                         interleaved: true) else {
            throw GigaAMTranscriptionError.audioDecodeFailed
        }
        let frameCapacity = AVAudioFrameCount(inFile.length)
        guard frameCapacity > 0,
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: frameCapacity) else {
            throw GigaAMTranscriptionError.audioDecodeFailed
        }
        try inFile.read(into: inBuf)

        let outCap = AVAudioFrameCount(Double(inFile.length) * 16000.0 / inFmt.sampleRate) + 1024
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: outCap),
              let converter = AVAudioConverter(from: inFmt, to: outFmt) else {
            throw GigaAMTranscriptionError.audioDecodeFailed
        }
        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outBuf, error: &error) { _, outStatus in
            if consumed { outStatus.pointee = .endOfStream; return nil }
            outStatus.pointee = .haveData
            consumed = true
            return inBuf
        }
        if status == .error || error != nil {
            throw GigaAMTranscriptionError.audioDecodeFailed
        }
        let n = Int(outBuf.frameLength)
        guard n > 0, let ch = outBuf.floatChannelData?[0] else {
            throw GigaAMTranscriptionError.audioDecodeFailed
        }
        return Array(UnsafeBufferPointer(start: ch, count: n))
    }

    // MARK: - sherpa-onnx call

    static func transcribe(pcm: [Float], modelDir: URL) async throws -> String {
        #if canImport(SherpaOnnx)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let encoder = modelDir.appendingPathComponent("encoder.int8.onnx").path
                let decoder = modelDir.appendingPathComponent("decoder.onnx").path
                let joiner  = modelDir.appendingPathComponent("joiner.onnx").path
                let tokens  = modelDir.appendingPathComponent("tokens.txt").path

                var transducer = sherpaOnnxOfflineTransducerModelConfig(
                    encoder: encoder,
                    decoder: decoder,
                    joiner: joiner
                )
                var modelConfig = sherpaOnnxOfflineModelConfig(
                    tokens: tokens,
                    transducer: transducer,
                    numThreads: 2,
                    debug: 0,
                    modelType: "transducer"
                )
                // GigaAM uses 64-bin log-mel, 16 kHz (per model config.yaml).
                var feat = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 64)
                var config = sherpaOnnxOfflineRecognizerConfig(
                    featConfig: feat,
                    modelConfig: modelConfig,
                    decodingMethod: "greedy_search"
                )

                let recognizer = SherpaOnnxOfflineRecognizer(config: &config)
                guard recognizer.recognizer != nil else {
                    cont.resume(throwing: GigaAMTranscriptionError.recognizerInitFailed)
                    return
                }
                defer { SherpaOnnxDestroyOfflineRecognizer(recognizer.recognizer) }

                let stream = SherpaOnnxCreateOfflineStream(recognizer.recognizer)
                defer { SherpaOnnxDestroyOfflineStream(stream) }
                pcm.withUnsafeBufferPointer { buf in
                    SherpaOnnxAcceptWaveformOffline(stream, 16000, buf.baseAddress, Int32(buf.count))
                }
                SherpaOnnxDecodeOfflineStream(recognizer.recognizer, stream)
                let resultPtr = SherpaOnnxGetOfflineStreamResult(stream)
                defer { SherpaOnnxDestroyOfflineRecognizerResult(resultPtr) }

                let text = String(cString: resultPtr!.pointee.text)
                cont.resume(returning: text)
            }
        }
        #else
        throw GigaAMTranscriptionError.sherpaUnavailable
        #endif
    }
}

extension GigaAMTranscriptionService {
    @MainActor
    static var isAvailable: Bool {
        GigaAMModelManager.shared.isReady
    }
}
