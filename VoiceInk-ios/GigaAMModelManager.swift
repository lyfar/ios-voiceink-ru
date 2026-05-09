//
//  GigaAMModelManager.swift
//  VoiceInk-iOS — Russian fork
//
//  Downloads + manages GigaAM-v2 RNNT model files for the offline Russian
//  transcription engine. Files live in Documents/GigaAM-v2-rnnt/. Total
//  ~241 MB on first run; cached forever after. Source:
//   https://huggingface.co/Alexanrd/GigaAMv2_RNNT_RU_ASR_for_sherpa_onnx
//

import Foundation
import Combine

@MainActor
final class GigaAMModelManager: ObservableObject {
    static let shared = GigaAMModelManager()

    /// Files needed by sherpa-onnx OfflineRecognizer. Sizes are approx —
    /// only used for progress indication. order = download order.
    static let files: [(name: String, sizeMB: Int)] = [
        ("tokens.txt",         1),     // tiny — fetch first to check connectivity
        ("decoder.onnx",       4),
        ("joiner.onnx",        2),
        ("encoder.int8.onnx",  236),   // the big one
    ]

    private let baseURL = URL(string:
        "https://huggingface.co/Alexanrd/GigaAMv2_RNNT_RU_ASR_for_sherpa_onnx/resolve/main")!

    @Published private(set) var isReady: Bool = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var downloadingFile: String? = nil
    @Published private(set) var lastError: String? = nil

    var modelDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("GigaAM-v2-rnnt", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var totalSizeMB: Int {
        Self.files.reduce(0) { $0 + $1.sizeMB }
    }

    private init() {
        Task { await refreshAvailability() }
    }

    /// Re-check disk for all model files. Cheap, idempotent.
    func refreshAvailability() async {
        let allPresent = Self.files.allSatisfy { name, _ in
            FileManager.default.fileExists(atPath: modelDir.appendingPathComponent(name).path)
        }
        if isReady != allPresent { isReady = allPresent }
    }

    /// Download whichever files are missing. Idempotent — running again is a
    /// no-op once everything's local. Reports progress via published props.
    func downloadAll() async {
        lastError = nil
        downloadProgress = 0

        // Total bytes for accurate progress; check what's already on disk.
        let neededTotal = Self.files.reduce(0) { acc, item in
            let p = modelDir.appendingPathComponent(item.name).path
            return acc + (FileManager.default.fileExists(atPath: p) ? 0 : item.sizeMB)
        }
        if neededTotal == 0 {
            await refreshAvailability()
            return
        }
        var doneMB: Double = 0

        for (name, sizeMB) in Self.files {
            let dst = modelDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dst.path) { continue }
            downloadingFile = name
            do {
                let url = baseURL.appendingPathComponent(name)
                let (tmpURL, _) = try await URLSession.shared.download(from: url) { received, total in
                    Task { @MainActor in
                        guard total > 0 else { return }
                        let frac = Double(received) / Double(total)
                        let weighted = (doneMB + Double(sizeMB) * frac) / Double(neededTotal)
                        self.downloadProgress = max(0, min(1, weighted))
                    }
                }
                if FileManager.default.fileExists(atPath: dst.path) {
                    try? FileManager.default.removeItem(at: dst)
                }
                try FileManager.default.moveItem(at: tmpURL, to: dst)
                doneMB += Double(sizeMB)
                downloadProgress = doneMB / Double(neededTotal)
            } catch {
                lastError = "Не удалось скачать \(name): \(error.localizedDescription)"
                downloadingFile = nil
                return
            }
        }
        downloadingFile = nil
        await refreshAvailability()
    }

    func deleteAll() {
        for (name, _) in Self.files {
            try? FileManager.default.removeItem(at: modelDir.appendingPathComponent(name))
        }
        Task { await refreshAvailability() }
    }
}

// MARK: - URLSession.download with progress

extension URLSession {
    /// Pure-async URL download with progress callback. The standard
    /// `URLSession.download(from:)` doesn't expose progress; this wraps the
    /// delegate-based API.
    func download(
        from url: URL,
        progress: @escaping (_ received: Int64, _ total: Int64) -> Void
    ) async throws -> (URL, URLResponse) {
        let request = URLRequest(url: url)
        return try await withCheckedThrowingContinuation { cont in
            let task = self.downloadTask(with: request) { tmp, resp, err in
                if let err = err { cont.resume(throwing: err); return }
                guard let tmp = tmp, let resp = resp else {
                    cont.resume(throwing: URLError(.badServerResponse)); return
                }
                // The callback handler URL is auto-deleted after this closure
                // returns, so move it to a safe temp before resuming.
                let safe = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                do {
                    try FileManager.default.moveItem(at: tmp, to: safe)
                    cont.resume(returning: (safe, resp))
                } catch {
                    cont.resume(throwing: error)
                }
            }
            // Manual progress observation via KVO.
            let obs = task.progress.observe(\.fractionCompleted) { p, _ in
                progress(p.completedUnitCount, p.totalUnitCount)
            }
            // Keep observer alive for the duration of the task.
            task.resume()
            _ = obs  // capture
        }
    }
}
