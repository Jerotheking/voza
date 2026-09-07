import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettings().environmentObject(appState)
                .tabItem { Label(L.t("General", es: "General"), systemImage: "gearshape") }
            ModelSettings().environmentObject(appState)
                .tabItem { Label(L.t("Models", es: "Modelos"), systemImage: "square.stack.3d.down.forward") }
            AdvancedSettings().environmentObject(appState)
                .tabItem { Label(L.t("Advanced", es: "Avanzado"), systemImage: "wrench.and.screwdriver") }
            AboutSettings().environmentObject(appState)
                .tabItem { Label(L.t("About", es: "Acerca de"), systemImage: "info.circle") }
        }
        .frame(width: 480, height: 360)
    }
}

struct GeneralSettings: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Picker(L.t("Language", es: "Idioma"), selection: Binding(
                get: { L.override ?? "auto" },
                set: { L.override = $0 == "auto" ? nil : $0 }
            )) {
                Text(L.t("System", es: "Sistema")).tag("auto")
                Text("English").tag("en")
                Text("Español").tag("es")
            }
            Picker(L.t("AI cleanup", es: "Limpieza IA"), selection: Binding(
                get: { appState.config.cleanupMode },
                set: { appState.config.setCleanupMode($0) }
            )) {
                Text(L.t("Automatic (Ollama → cloud)", es: "Automático (Ollama → nube)")).tag("auto")
                Text("Ollama " + L.t("only", es: "solo")).tag("ollama")
                Text(L.t("Cloud API only", es: "Solo API en la nube")).tag("cloud")
                Text(L.t("Off (plain paste)", es: "Apagada (pegado simple)")).tag("plain")
            }
            if appState.config.cleanupMode == "ollama" || appState.config.cleanupMode == "auto" {
                HStack {
                    TextField("ollama model", text: Binding(
                        get: { appState.config.ollamaModel },
                        set: { appState.config.setOllamaModel($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Text(L.t("Ollama detected: \(appState.config.ollamaDetected ? "yes" : "no")",
                             es: "Ollama detectado: \(appState.config.ollamaDetected ? "sí" : "no")"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Picker(L.t("Transcription language", es: "Idioma de transcripción"), selection: Binding(
                get: { appState.config.language },
                set: { appState.config.setLanguage($0) }
            )) {
                Text(L.t("Auto-detect", es: "Autodetectar")).tag("auto")
                Text("English").tag("en")
                Text("Español").tag("es")
            }
        }
        .padding(20)
    }
}

struct ModelSettings: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("Auto preset for this Mac: **\(appState.recommendedModelId)** (needs ≥ \(HardwareProfile.totalRAMGB) GB RAM)",
                     es: "Preset automático para esta Mac: **\(appState.recommendedModelId)** (requiere ≥ \(HardwareProfile.totalRAMGB) GB RAM)"))
                .font(.callout)
            Text("\(L.t("Current model", es: "Modelo actual")): \(appState.config.resolvedModelId)")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 20).padding(.top, 16)

        List(WhisperCatalog.all) { model in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName).font(.system(size: 12, weight: .semibold))
                    Text("\(model.sizeLabel) · \(model.isEnglishOnly ? "EN" : L.t("multilingual", es: "multilingüe"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if appState.downloadingModelId == model.id {
                    ProgressView(value: appState.downloadProgress ?? 0)
                        .frame(width: 90)
                } else if ModelManager.shared.isDownloaded(model) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    if appState.config.resolvedModelId == model.id {
                        Text(L.t("active", es: "activo")).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button(L.t("Use", es: "Usar")) {
                            appState.config.setModel(model.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    Button(L.t("Download", es: "Descargar")) {
                        appState.downloadModel(id: model.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.inset)
    }
}

struct AdvancedSettings: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            HStack {
                TextField(L.t("whisper.cpp binary (empty = auto)", es: "Binario whisper.cpp (vacío = auto)"),
                          text: Binding(
                            get: { appState.config.whisperBinary ?? "" },
                            set: { appState.config.setWhisperBinary($0.isEmpty ? nil : $0) }
                          ))
                    .textFieldStyle(.roundedBorder)
                Image(systemName: Transcriber.locateBinary() != nil ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(Transcriber.locateBinary() != nil ? Color.green : Color.orange)
            }
            HStack {
                TextField(L.t("Models directory", es: "Carpeta de modelos"),
                          text: Binding(
                            get: { appState.config.modelsDirectory ?? "" },
                            set: { appState.config.setModelsDirectory($0.isEmpty ? nil : $0) }
                          ))
                    .textFieldStyle(.roundedBorder)
                Button(L.t("Reveal", es: "Mostrar")) {
                    NSWorkspace.shared.open(ModelManager.shared.modelsDirectory)
                }
            }
            Toggle(L.t("Launch Voza at login", es: "Abrir Voza al iniciar sesión"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    try? SMAppService.mainApp.register()
                    if !newValue { try? SMAppService.mainApp.unregister() }
                }
            Toggle(L.t("Play a sound when transcription finishes", es: "Sonido al terminar la transcripción"), isOn: Binding(
                get: { appState.config.playSound },
                set: { appState.config.setPlaySound($0) }
            ))
        }
        .padding(20)
    }
}

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.fill").font(.system(size: 40)).foregroundStyle(Theme.accent)
            Text("Voza").font(.title2).bold()
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.caption).foregroundStyle(.secondary)
            Text(L.t("Local dictation for macOS. Your voice never leaves your Mac.",
                     es: "Dictado local para macOS. Tu voz nunca sale de tu Mac."))
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
