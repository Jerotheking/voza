import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            historySection
            // While setup is incomplete, offer a way back to the floating
            // guide window (which lives outside this dismissable panel).
            if appState.showOnboarding {
                Divider()
                Button {
                    OnboardingWindowController.shared.show(appState: appState)
                } label: {
                    Label(L.t("Show setup guide", es: "Mostrar guía de configuración"),
                          systemImage: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            Divider()
            footer
        }
        .frame(width: Theme.popoverWidth)
        .onAppear { appState.refresh() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                PhaseIcon(phase: appState.phase)
                VStack(alignment: .leading, spacing: 2) {
                    Text(phaseTitle).font(.system(size: 13, weight: .semibold))
                    Text(phaseDetail)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)

            if showsBusyBar {
                ProgressView()
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 12)
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
                SettingsOpenButton {
                    Label(L.t("Trial over — activate Voza", es: "Prueba terminada — activa Voza"),
                          systemImage: "key")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private var phaseTitle: String {
        switch appState.phase {
        case .idle:
            return L.t("Tap or hold Option to talk", es: "Toca o mantén Option para hablar")
        case .recording:
            return appState.isHandsFree
                ? L.t("Recording (hands-free)…", es: "Grabando (manos libres)…")
                : L.t("Recording…", es: "Grabando…")
        case .transcribing:
            return L.t("Transcribing…", es: "Transcribiendo…")
        case .failed(let msg):
            return msg
        }
    }

    private var phaseDetail: String {
        switch appState.phase {
        case .idle:
            return L.t("Tap = hands-free · Hold = push-to-talk · 100% local",
                       es: "Toca = manos libres · Mantén = push-to-talk · 100% local")
        case .recording:
            let secs = String(format: "%.0f s", appState.elapsedSeconds)
            if appState.isHandsFree {
                return L.t("\(secs) · tap Option to finish (Esc cancels)",
                           es: "\(secs) · toca Option para terminar (Esc cancela)")
            }
            return secs
        case .transcribing:
            return L.t("100% on your Mac", es: "100% en tu Mac")
        case .failed:
            return L.t("Tap or hold Option to try again", es: "Toca o mantén Option para intentar de nuevo")
        }
    }

    private var showsBusyBar: Bool {
        appState.phase == .transcribing
    }

    /// Colored capsule glyph for the header; pulses while recording.
    private struct PhaseIcon: View {
        let phase: VozaPhase
        @State private var pulse = false

        var body: some View {
            switch phase {
            case .idle:
                glyph("mic", tint: .secondary, bg: Color.primary.opacity(0.06))
            case .recording:
                glyph("mic.fill", tint: .red, bg: Color.red.opacity(0.14))
                    .opacity(pulse ? 0.45 : 1)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
            case .transcribing:
                glyph("waveform", tint: Theme.accent, bg: Theme.accent.opacity(0.14))
            case .failed:
                glyph("exclamationmark.triangle", tint: .orange, bg: Color.orange.opacity(0.14))
            }
        }

        private func glyph(_ system: String, tint: Color, bg: Color) -> some View {
            Image(systemName: system)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(bg))
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L.t("Recent transcripts", es: "Transcripciones recientes"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !appState.recent.isEmpty {
                    Text("\(min(appState.recent.count, 20))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)

            if appState.recent.isEmpty {
                Text(L.t("Nothing yet — tap or hold Option and speak.",
                         es: "Nada aún — toca o mantén Option y habla."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.bottom, 14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(appState.recent.prefix(20)) { entry in
                            TranscriptRow(entry: entry) {
                                appState.copyToClipboard(entry.text)
                            } onEdit: { corrected in
                                appState.learnCorrection(entry: entry, corrected: corrected)
                            }
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .frame(minHeight: 280, maxHeight: 460)
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

            SettingsOpenButton {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(L.t("Settings", es: "Ajustes"))

            SettingsOpenButton {
                HStack(spacing: 4) {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                    Text(L.t("\(appState.learnedCount) learned", es: "\(appState.learnedCount) aprendidas"))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quinary, in: Capsule())
            }
            .buttonStyle(.plain)
            .help(L.t("Learned corrections dictionary", es: "Diccionario de palabras aprendidas"))

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
    var onEdit: ((String) -> Void)? = nil
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var isEditing = false
    @State private var isExpanded = false
    @State private var draft = ""

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField(L.t("Corrected text — Voza learns from this", es: "Texto corregido — Voza aprende de esto"), text: $draft, axis: .vertical)
                        .font(.system(size: 12.5))
                        .lineLimit(3...8)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitEdit() }
                    HStack(spacing: 8) {
                        Button {
                            commitEdit()
                        } label: {
                            Label(L.t("Save & teach", es: "Guardar y enseñar"), systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        Button(role: .cancel) {
                            isEditing = false
                        } label: {
                            Text(L.t("Cancel", es: "Cancelar")).font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    Text(entry.text)
                        .font(.system(size: 12.5))
                        .lineSpacing(2)
                        .lineLimit(isExpanded ? nil : 8)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture {
                            if entry.text.count > 140 {
                                isExpanded.toggle()
                            }
                        }
                }
                HStack(spacing: 6) {
                    Text("\(entry.dayLabel) \(entry.timeLabel)")
                    if entry.cleaned {
                        Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                    }
                    if !isEditing && entry.text.count > 220 {
                        Button {
                            isExpanded.toggle()
                        } label: {
                            Text(isExpanded
                                 ? L.t("Show less", es: "Ver menos")
                                 : L.t("Show full", es: "Ver completo"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if !isEditing, onEdit != nil {
                    Button {
                        draft = entry.text
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(L.t("Fix and teach Voza", es: "Corrige y enseña a Voza"))
                }
                Button {
                    onCopy()
                    copyResetTask?.cancel()
                    copied = true
                    copyResetTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        guard !Task.isCancelled else { return }
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(copied ? Color.green : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(L.t("Copy transcript", es: "Copiar transcripción"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onDisappear {
            copyResetTask?.cancel()
            copyResetTask = nil
            copied = false
        }
    }

    /// Records the learned correction and pastes the fixed text immediately,
    /// so fixing a row doubles as "redo the paste" — no hotkey needed.
    private func commitEdit() {
        let fixed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = false
        guard !fixed.isEmpty, fixed != entry.text else { return }
        onEdit?(fixed)
    }
}
