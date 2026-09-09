import SwiftUI

/// First-run permission flow. macOS shows prompts on first use of each API;
/// this window explains what will appear and why, EN/ES.
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var micGranted = Permissions.microphoneGranted
    @State private var axGranted = Permissions.accessibilityGranted
    @State private var whisperFound = Transcriber.locateBinary() != nil
    @State private var anyModel = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "mic.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text(L.t("Welcome to Voza", es: "Bienvenido a Voza")).font(.title2).bold()
            Text(L.t("Three quick things and you're dictating. Everything runs on your Mac — nothing is uploaded, ever.",
                     es: "Tres pasos rápidos y dictas. Todo corre en tu Mac — nada se sube, jamás."))
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            VStack(alignment: .leading, spacing: 12) {
                stepRow(
                    done: micGranted,
                    title: L.t("Microphone", es: "Micrófono"),
                    detail: L.t("To record your voice.", es: "Para grabar tu voz."),
                    actionTitle: micGranted ? nil : L.t("Grant", es: "Conceder")
                ) {
                    Task {
                        micGranted = await Permissions.requestMicrophone()
                        // If the user denied earlier, the system won't re-prompt;
                        // the deep link is the only way back to the toggle.
                        if !micGranted { Permissions.openMicrophoneSettings() }
                        refresh()
                    }
                }
                stepRow(
                    done: axGranted,
                    title: L.t("Accessibility", es: "Accesibilidad"),
                    detail: L.t("So Voza can paste the text for you. macOS will ask on first paste.",
                                es: "Para que Voza pegue el texto por ti. macOS lo pedirá al primer pegado."),
                    actionTitle: axGranted ? nil : L.t("Open Settings", es: "Abrir Ajustes")
                ) {
                    Permissions.openAccessibilitySettings()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { refresh() }
                }
                stepRow(
                    done: whisperFound,
                    title: L.t("whisper.cpp engine", es: "Motor whisper.cpp"),
                    detail: whisperFound
                        ? L.t("Found ✓", es: "Encontrado ✓")
                        : L.t("Install with Homebrew: brew install whisper-cpp",
                              es: "Instala con Homebrew: brew install whisper-cpp"),
                    actionTitle: nil, action: nil
                )
                stepRow(
                    done: anyModel,
                    title: L.t("Speech model", es: "Modelo de voz"),
                    detail: anyModel
                        ? L.t("Ready ✓", es: "Listo ✓")
                        : L.t("Download one from Settings → Models (the app picks one for your Mac automatically).",
                              es: "Descarga uno en Ajustes → Modelos (la app elige uno para tu Mac automáticamente)."),
                    actionTitle: anyModel ? nil : L.t("Download recommended", es: "Descargar recomendado")
                ) {
                    appState.downloadModel(id: appState.recommendedModelId)
                    refresh()
                }
            }
            .padding(.horizontal, 8)

            if micGranted && axGranted {
                Button(L.t("Start dictating", es: "Empezar a dictar")) {
                    appState.showOnboarding = false
                    OnboardingWindowController.shared.closeIfVisible()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Text(L.t("Grant both permissions to continue.", es: "Concede ambos permisos para continuar."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
        }
        .padding(20)
        .frame(width: 300)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        micGranted = Permissions.microphoneGranted
        axGranted = Permissions.accessibilityGranted
        whisperFound = Transcriber.locateBinary() != nil
        anyModel = !ModelManager.shared.downloadedModels().isEmpty
    }

    @ViewBuilder
    private func stepRow(done: Bool, title: String, detail: String, actionTitle: String?, action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
