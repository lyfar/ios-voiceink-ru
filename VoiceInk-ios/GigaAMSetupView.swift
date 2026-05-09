//
//  GigaAMSetupView.swift
//  VoiceInk-iOS — Russian fork
//
//  First-time download UI for the GigaAM-v2 RNNT offline Russian model.
//  Drops 241 MB of ONNX into Documents/GigaAM-v2-rnnt/. After that the
//  GigaAM provider is selectable in Settings and works fully offline.
//

import SwiftUI

struct GigaAMSetupView: View {
    @StateObject private var manager = GigaAMModelManager.shared

    var body: some View {
        List {
            Section {
                if manager.isReady {
                    Label("Модель установлена", systemImage: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Распознаёт русскую речь полностью на устройстве, без интернета. " +
                         "Качество — 8.42% WER, государственный русский SOTA.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else if manager.downloadingFile != nil {
                    HStack {
                        ProgressView(value: manager.downloadProgress)
                        Text("\(Int(manager.downloadProgress * 100))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                    if let f = manager.downloadingFile {
                        Text(f)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("GigaAM v2 RNNT — оффлайн русский STT")
                        .font(.headline)
                    Text("Размер: ~241 МБ. Качество ≈ 8% WER на русском (вдвое точнее Whisper Large v3 на русском). " +
                         "Скачивается один раз, хранится в Documents.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Локальная модель")
            }

            if !manager.isReady {
                Section {
                    Button {
                        Task { await manager.downloadAll() }
                    } label: {
                        Label("Скачать модель (241 МБ)", systemImage: "arrow.down.circle")
                    }
                    .disabled(manager.downloadingFile != nil)
                }
            } else {
                Section {
                    Button(role: .destructive) {
                        manager.deleteAll()
                    } label: {
                        Label("Удалить модель", systemImage: "trash")
                    }
                }
            }

            if let err = manager.lastError {
                Section {
                    Text(err)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }

            Section {
                Link(destination: URL(string: "https://github.com/salute-developers/GigaAM")!) {
                    Label("О GigaAM (Sber AI, MIT)", systemImage: "info.circle")
                }
            } header: {
                Text("Источник")
            }
        }
        .navigationTitle("GigaAM (русский)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await manager.refreshAvailability()
        }
    }
}

#Preview {
    NavigationView {
        GigaAMSetupView()
    }
}
