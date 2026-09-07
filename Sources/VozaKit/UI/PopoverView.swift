import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.showOnboarding {
                OnboardingView()
            } else {
                VStack(spacing: 0) {
                    header
                    Divider()
                    historySection
                    Divider()
                    footer
                }
            }
        }
        .frame(width: Theme.popoverWidth)
        .onAppear { appState.refresh() }
    }

    private var header: some View {
        VStack(spacing: 4) {
            switch appState.phase {
            case .idle:
                Label(L.t("Hold Right Option to talk", es: "Mantén Option derecha para hablar"),
                      systemImage: "mic").font(.system(size: 12, weight: .medium))
                Text(L.t("Right Control = AI cleanup", es: "Control derecha = limpieza IA"))
                    .font(.caption2).foregroundStyle(.secondary)
            case .recording(let cleanup):
                Label(L.t(cleanup ? "Recording — cleanup mode" : "Recording…",
                          es: cleanup ? "Grabando — con limpieza" : "Grabando…"),
                      systemImage: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                Text(String(format: "%.0f s", appState.elapsedSeconds))
                    .font(.caption2).foregroundStyle(.secondary)
            case .transcribing:
                Label(L.t("Transcribing…", es: "Transcribiendo…"), systemImage: "waveform")
                    .font(.system(size: 12, weight: .medium))
                Text(L.t("100% on your Mac", es: "100% en tu Mac"))
                    .font(.caption2).foregroundStyle(.secondary)
            case .cleaning:
                Label(L.t("Polishing text…", es: "Puliendo texto…"), systemImage: "sparkles")
                    .font(.system(size: 12, weight: .medium))
            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
            }
            if let model = appState.downloadingModelId, let p = appState.downloadProgress {
                VStack(spacing: 2) {
                    ProgressView(value: p)
                    Text(L.t("Downloading \(model)… \(Int(p * 100))%", es: "Descargando \(model)… \(Int(p * 100))%"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
            }
            if let msg = appState.statusMessage {
                Text(msg).font(.caption2).foregroundStyle(.green)
            }
            if case .trialOver = appState.license.state {
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label(L.t("Trial over — activate Voza", es: "Prueba terminada — activa Voza"),
                          systemImage: "key")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L.t("Last 10 transcripts", es: "Últimos 10 dictados"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)

            if appState.recent.isEmpty {
                Text(L.t("Nothing yet — hold Right Option and speak.", es: "Nada aún — mantén Option derecha y habla."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.bottom, 12)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(appState.recent.prefix(10)) { entry in
                            TranscriptRow(entry: entry) {
                                appState.copyToClipboard(entry.text)
                            }
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                appState.openLogFolder()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help(L.t("Open log folder", es: "Abrir carpeta de logs"))

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(L.t("Settings", es: "Ajustes"))

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help(L.t("Quit Voza", es: "Salir de Voza"))
        }
        .padding(10)
    }
}

struct TranscriptRow: View {
    let entry: TranscriptEntry
    let onCopy: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    Text("\(entry.dayLabel) \(entry.timeLabel)")
                    if entry.cleaned {
                        Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }
            Button {
                onCopy()
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
