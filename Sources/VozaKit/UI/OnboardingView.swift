import SwiftUI

/// First-run flow. One button, one promise: hold an Option key, talk, release —
/// the text is pasted exactly as spoken. Cloud AI cleanup exists but is opt-in
/// in Settings and never part of first-run (D032).
/// macOS shows permission prompts on first use of each API; this window
/// explains what will appear and why, EN/ES.
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var micGranted = Permissions.microphoneGranted
    @State private var axGranted = Permissions.accessibilityGranted
    @State private var inputMonGranted = Permissions.inputMonitoringGranted
    @State private var whisperFound = Transcriber.locateBinary() != nil
    @State private var anyModel = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text(L.t("Welcome to Voza", es: "Bienvenido a Voza")).font(.title2).bold()
            Text(L.t("Hold an Option key, speak, release — your words appear instantly, exactly as you said them.\nFix any word by typing and Voza learns it. Everything runs on your Mac; nothing is uploaded, ever.",
                     es: "Mantén una tecla Option, habla, suelta — tus palabras aparecen al instante, tal como las dijiste.\nCorrige cualquier palabra tecleando y Voza la aprende. Todo corre en tu Mac; nada se sube, jamás."))
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            VStack(alignment: .leading, spacing: 11) {
                stepRow(
                    done: micGranted,
                    title: L.t("Microphone", es: "Micrófono"),
                    detail: L.t("To record your voice while you hold the key.", es: "Para grabar tu voz mientras mantienes la tecla."),
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
                    done: inputMonGranted,
                    title: L.t("Input Monitoring", es: "Monitorización de entrada"),
                    detail: L.t("Lets the Option key start Voza from any app. macOS will ask the first time you dictate.",
                                es: "Permite que la tecla Option active Voza en cualquier app. macOS lo pedirá al dictar por primera vez."),
                    actionTitle: inputMonGranted ? nil : L.t("Open Settings", es: "Abrir Ajustes")
                ) {
                    // The OS prompt fires when the event tap is first created;
                    // the deep link is the reliable path if it was dismissed.
                    HotKeyManager.shared.ensureTapAlive()
                    Permissions.openInputMonitoringSettings()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { refresh() }
                }
                stepRow(
                    done: engineReady,
                    title: L.t("Speech model", es: "Modelo de voz"),
                    detail: engineReady
                        ? L.t("Ready ✓ — picked for this Mac, verified with SHA-256.", es: "Listo ✓ — elegido para esta Mac, verificado con SHA-256.")
                        : whisperFound
                            ? L.t("One download. Voza picks the right size for your Mac automatically.",
                                  es: "Una descarga. Voza elige el tamaño correcto para tu Mac automáticamente.")
                            : L.t("Requires whisper.cpp (brew install whisper-cpp) — or one click in Settings → Status.",
                                  es: "Requiere whisper.cpp (brew install whisper-cpp) — o un clic en Ajustes → Estado."),
                    actionTitle: engineReady || !whisperFound ? nil : L.t("Download recommended", es: "Descargar recomendado")
                ) {
                    appState.downloadModel(id: appState.recommendedModelId)
                    refresh()
                }
            }
            .padding(.horizontal, 8)

            if micGranted && axGranted && inputMonGranted {
                Button(L.t("Start dictating", es: "Empezar a dictar")) {
                    appState.showOnboarding = false
                    OnboardingWindowController.shared.closeIfVisible()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                if !engineReady {
                    Text(L.t("You can download the model later — Settings → Models.",
                             es: "Puedes descargar el modelo después — Ajustes → Modelos."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(L.t("Grant the three permissions to continue.", es: "Concede los tres permisos para continuar."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
        }
        .padding(20)
        .frame(width: 320)
        .onAppear(perform: refresh)
    }

    /// Engine + model collapse into one row: no model without an engine anyway.
    private var engineReady: Bool {
        whisperFound && anyModel
    }

    private func refresh() {
        micGranted = Permissions.microphoneGranted
        axGranted = Permissions.accessibilityGranted
        inputMonGranted = Permissions.inputMonitoringGranted
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
