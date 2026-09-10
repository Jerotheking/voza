import SwiftUI
import ServiceManagement

/// Tab order follows the adaptive-UX spec: Status is the home; power knobs sink.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            StatusView().environmentObject(appState)
                .tabItem { Label(L.t("Status", es: "Estado"), systemImage: "heart.text.square") }
            DictationSettings().environmentObject(appState)
                .tabItem { Label(L.t("Dictation", es: "Dictado"), systemImage: "mic") }
            ModelSettings().environmentObject(appState)
                .tabItem { Label(L.t("Models", es: "Modelos"), systemImage: "square.stack.3d.down.forward") }
            AdvancedSettings().environmentObject(appState)
                .tabItem { Label(L.t("Advanced", es: "Avanzado"), systemImage: "wrench.and.screwdriver") }
            LicenseSettings().environmentObject(appState)
                .tabItem { Label(L.t("License", es: "Licencia"), systemImage: "key") }
            AboutSettings().environmentObject(appState)
                .tabItem { Label(L.t("About", es: "Acerca de"), systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - Status home

struct StatusView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var brew = BrewInstaller()
    @State private var readiness = ReadinessChecker.check()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                heroCard
                checklistChips
                if appState.downloadingModelId != nil {
                    downloadCard
                }
                if let suggestion = appState.perfSuggestion {
                    suggestionCard(suggestion)
                }
                if !readiness.engineFound && readiness.brewAvailable {
                    brewCard
                }
                if !appState.recent.isEmpty {
                    recentMiniList
                }
            }
            .padding(16)
        }
        .onAppear(perform: refreshNow)
        .onReceive(appState.$phase) { _ in refreshSoon() }
    }

    private func refreshNow() {
        appState.refresh()
        readiness = ReadinessChecker.check()
    }

    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            readiness = ReadinessChecker.check()
        }
    }

    // Priority order mirrors docs/design-adaptive-ux.md — first match wins.

    @ViewBuilder
    private var heroCard: some View {
        if readiness.freeDiskMB < ReadinessChecker.requiredFreeMB(for: WhisperCatalog.byId(appState.recommendedModelId) ?? WhisperCatalog.all[0]) && !readiness.modelAvailable {
            let needed = ReadinessChecker.requiredFreeMB(for: WhisperCatalog.byId(appState.recommendedModelId) ?? WhisperCatalog.all[0])
            hero(icon: "externaldrive.badge.exclamationmark", tint: .orange,
                 title: L.t("Not enough disk space", es: "Poco espacio en disco"),
                 detail: L.t("Downloading \(appState.recommendedModelId) needs about \(needed) MB free. You have \(readiness.freeDiskMB) MB.",
                             es: "Descargar \(appState.recommendedModelId) requiere unos \(needed) MB libres. Tienes \(readiness.freeDiskMB) MB."))
        } else if !readiness.micGranted {
            hero(icon: "mic.badge.xmark", tint: .orange,
                 title: L.t("Microphone needed", es: "Falta el micrófono"),
                 detail: L.t("Your audio never leaves this Mac.",
                             es: "Tu audio nunca sale de esta Mac."),
                 buttonTitle: L.t("Grant", es: "Conceder")) {
                Task {
                    _ = await Permissions.requestMicrophone()
                    refreshNow()
                }
            }
        } else if !readiness.accessibilityGranted {
            hero(icon: "hand.raised.app", tint: .orange,
                 title: L.t("Paste permission needed", es: "Falta permiso para pegar"),
                 detail: L.t("Accessibility lets Voza paste text into the app you're using.",
                             es: "Accesibilidad permite a Voza pegar el texto en la app que uses."),
                 buttonTitle: L.t("Open Settings", es: "Abrir Ajustes")) {
                Permissions.openAccessibilitySettings()
                refreshSoon()
            }
        } else if !readiness.inputMonitoringGranted || !readiness.hotkeyTapActive {
            hero(icon: "keyboard.badge.eye", tint: .orange,
                 title: L.t("Global hotkey blocked", es: "Hotkey global bloqueado"),
                 detail: readiness.hotkeyTapActive
                    ? L.t("Input Monitoring lets Voza detect the push-to-talk key system-wide.",
                          es: "Input Monitoring permite a Voza detectar la tecla de dictado en todo el sistema.")
                    : (HotKeyManager.shared.lastTapError ?? L.t("Global hotkey unavailable — grant Input Monitoring",
                                                                es: "Hotkey global no disponible — otorga Input Monitoring")),
                 buttonTitle: L.t("Open Settings", es: "Abrir Ajustes")) {
                Permissions.openInputMonitoringSettings()
                refreshSoon()
            }
        } else if !readiness.engineFound {
            hero(icon: "cpu", tint: .orange,
                 title: L.t("Speech engine missing", es: "Falta el motor de voz"),
                 detail: L.t("Voza needs whisper.cpp (free, runs on your Mac). Install it with Homebrew in one click.",
                             es: "Voza necesita whisper.cpp (gratis, corre en tu Mac). Instálalo con Homebrew en un clic."),
                 buttonTitle: L.t("Install for me", es: "Instalar por mí")) {
                brew.installEngine() // no-ops while a previous install is running
            }
        } else if !readiness.modelAvailable {
            hero(icon: "arrow.down.circle", tint: Theme.accent,
                 title: L.t("Download your voice model", es: "Descarga tu modelo de voz"),
                 detail: L.t("Recommended for this Mac: \(appState.recommendedModelId) (\(WhisperCatalog.byId(appState.recommendedModelId)?.sizeLabel ?? "?")). Verified with SHA-256.",
                             es: "Recomendado para esta Mac: \(appState.recommendedModelId) (\(WhisperCatalog.byId(appState.recommendedModelId)?.sizeLabel ?? "?")). Verificado con SHA-256."),
                 buttonTitle: L.t("Download", es: "Descargar")) {
                appState.downloadModel(id: appState.recommendedModelId)
            }
        } else if let suggestion = appState.perfSuggestion {
            switch suggestion.direction {
            case .lighter:
                hero(icon: "gauge.with.needle", tint: .orange,
                     title: L.t("Transcription feels slow?", es: "¿La transcripción va lenta?"),
                     detail: L.t("On your last dictations it was slower than real time. Try \(suggestion.targetModelId) — one tap.",
                                 es: "En tus últimos dictados fue más lenta que el habla. Prueba \(suggestion.targetModelId) — un toque."),
                     buttonTitle: L.t("Switch now", es: "Cambiar ahora")) {
                        appState.applySuggestion()
                    }
            case .heavier:
                hero(icon: "sparkles", tint: Theme.accent,
                     title: L.t("Your Mac can do more", es: "Tu Mac puede dar más"),
                     detail: L.t("Transcription runs at \(PerformanceMonitor.shared.speedLabel(model: appState.config.resolvedModelId) ?? "high speed"). Try \(suggestion.targetModelId) for extra accuracy.",
                                 es: "La transcripción corre a \(PerformanceMonitor.shared.speedLabel(model: appState.config.resolvedModelId) ?? "alta velocidad"). Prueba \(suggestion.targetModelId) para más precisión."),
                     buttonTitle: L.t("Switch now", es: "Cambiar ahora")) {
                        appState.applySuggestion()
                    }
            }
        } else {
            hero(icon: "checkmark.seal.fill", tint: .green,
                 title: L.t("Voza is ready", es: "Voza está lista"),
                 detail: L.t("Hold Right Option anywhere and talk. Left Option adds AI cleanup (test).",
                             es: "Mantén Option derecha en cualquier app y habla. Option izquierda agrega limpieza IA (prueba)."))
        }
    }

    private func hero(icon: String, tint: Color, title: String, detail: String, buttonTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(tint)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .bold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if let buttonTitle {
                    Button(buttonTitle) { action?() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 4)
                        .disabled(brew.isInstalling)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
    }

    private var checklistChips: some View {
        HStack(spacing: 8) {
            chip(L.t("Mic", es: "Mic"), ok: readiness.micGranted)
            chip(L.t("Paste", es: "Pegar"), ok: readiness.accessibilityGranted)
            chip(L.t("Hotkey", es: "Hotkey"), ok: readiness.inputMonitoringGranted && readiness.hotkeyTapActive)
            chip(L.t("Engine", es: "Motor"), ok: readiness.engineFound)
            chip(L.t("Model", es: "Modelo"), ok: readiness.modelAvailable)
            Spacer()
            Text("\(HardwareProfile.machineLabel) · \(HardwareProfile.totalRAMGB) GB")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func chip(_ label: String, ok: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? Color.green : Color.orange)
            Text(label).font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quinary, in: Capsule())
    }

    private var downloadCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("Downloading \(appState.downloadingModelId ?? "")… \(Int((appState.downloadProgress ?? 0) * 100))%",
                         es: "Descargando \(appState.downloadingModelId ?? "")… \(Int((appState.downloadProgress ?? 0) * 100))%"))
                    .font(.caption.weight(.medium))
                if let eta = appState.downloadETA {
                    Text(L.t("About \(eta) left", es: "Faltan ~\(eta)"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                ProgressView(value: appState.downloadProgress ?? 0)
            }
            Spacer()
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
    }

    private func suggestionCard(_ suggestion: PerformanceMonitor.Suggestion) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("Suggestion: try \(suggestion.targetModelId)",
                         es: "Sugerencia: prueba \(suggestion.targetModelId)"))
                    .font(.caption.weight(.semibold))
                Text(L.t("Based on \(PerformanceMonitor.shared.speedLabel(model: appState.config.resolvedModelId) ?? "measured") speed on this Mac.",
                         es: "Basado en la velocidad \(PerformanceMonitor.shared.speedLabel(model: appState.config.resolvedModelId) ?? "medida") en esta Mac."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L.t("Switch", es: "Cambiar")) { appState.applySuggestion() }
                .buttonStyle(.bordered).controlSize(.small)
            Button {
                appState.dismissSuggestion()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless).controlSize(.small)
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
    }

    private var brewCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if brew.isInstalling {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L.t("Installing whisper.cpp…", es: "Instalando whisper.cpp…"))
                        .font(.caption.weight(.medium))
                }
            } else if let message = brew.installError {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            if !brew.logLines.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(brew.logLines.suffix(8).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 90)
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
    }

    private var recentMiniList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("Recent transcriptions", es: "Dictados recientes"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(appState.recent.prefix(3)) { entry in
                HStack {
                    Text(entry.text).font(.caption).lineLimit(1)
                    Spacer()
                    Text(entry.timeLabel).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
    }
}

// MARK: - Dictation (the 3 real knobs)

struct DictationSettings: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Picker(L.t("AI cleanup", es: "Limpieza IA"), selection: Binding(
                    get: { appState.config.cleanupMode },
                    set: { appState.config.setCleanupMode($0) }
                )) {
                    Text(L.t("Automatic — local only, never cloud", es: "Automática — solo local, nunca nube")).tag("auto")
                    Text("Ollama " + L.t("only", es: "solo")).tag("ollama")
                    Text(L.t("Cloud API only (explicit)", es: "Solo API en la nube (explícito)")).tag("cloud")
                    Text(L.t("Off (plain paste)", es: "Apagada (pegado simple)")).tag("plain")
                }
                if appState.config.cleanupMode == "ollama" || appState.config.cleanupMode == "auto" {
                    HStack {
                        TextField("ollama model", text: Binding(
                            get: { appState.config.ollamaModel },
                            set: { appState.config.setOllamaModel($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        Text(appState.config.ollamaDetected
                             ? L.t("Ollama detected ✓", es: "Ollama detectado ✓")
                             : L.t("Ollama not found", es: "Ollama no encontrado"))
                            .font(.caption)
                            .foregroundStyle(appState.config.ollamaDetected ? Color.green : Color.orange)
                    }
                }
            } header: {
                Text(L.t("What happens after you speak", es: "Qué pasa después de hablar"))
            }
            Section {
                Picker(L.t("Transcription language", es: "Idioma de transcripción"), selection: Binding(
                    get: { appState.config.language },
                    set: { appState.config.setLanguage($0) }
                )) {
                    Text(L.t("Auto-detect", es: "Autodetectar")).tag("auto")
                    Text("English").tag("en")
                    Text("Español").tag("es")
                }
                Picker(L.t("App language", es: "Idioma de la app"), selection: Binding(
                    get: { L.override ?? "auto" },
                    set: { L.override = $0 == "auto" ? nil : $0 }
                )) {
                    Text(L.t("System", es: "Sistema")).tag("auto")
                    Text("English").tag("en")
                    Text("Español").tag("es")
                }
            } header: {
                Text(L.t("Languages", es: "Idiomas"))
            }
            Section {
                Text(L.t("Hotkeys: hold **Right Option** to dictate · hold **Left Option** for AI cleanup (temporary test binding).",
                         es: "Teclas: mantén **Option derecha** para dictar · **Option izquierda** para limpieza IA (bind temporal de prueba)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}

// MARK: - Models

struct ModelSettings: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars").foregroundStyle(Theme.accent)
                Text(L.t("Automatic is recommended — Voza picks and tunes for this Mac (\(HardwareProfile.totalRAMGB) GB RAM).",
                         es: "Automático es lo recomendado — Voza elige y ajusta para esta Mac (\(HardwareProfile.totalRAMGB) GB de RAM)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 14)

            List {
                automaticRow
                ForEach(WhisperCatalog.all) { model in
                    modelRow(model)
                }
            }
            .listStyle(.inset)
        }
    }

    private var automaticRow: some View {
        HStack {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(appState.config.modelId == nil ? Theme.accent : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("Automatic (recommended)", es: "Automático (recomendado)"))
                    .font(.system(size: 12, weight: .semibold))
                Text(L.t("→ \(appState.recommendedModelId), adapts to your usage", es: "→ \(appState.recommendedModelId), se adapta a tu uso"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if appState.config.modelId == nil {
                Text(L.t("active", es: "activo")).font(.caption).foregroundStyle(.secondary)
            } else {
                Button(L.t("Use", es: "Usar")) { appState.config.setModel(nil) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private func modelRow(_ model: WhisperModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName).font(.system(size: 12, weight: .semibold))
                HStack(spacing: 6) {
                    Text("\(model.sizeLabel) · \(model.isEnglishOnly ? "EN" : L.t("multilingual", es: "multilingüe"))")
                    if let speed = PerformanceMonitor.shared.speedLabel(model: model.id) {
                        Text("· \(speed)").foregroundStyle(Theme.accent)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if appState.downloadingModelId == model.id {
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: appState.downloadProgress ?? 0).frame(width: 90)
                    if let eta = appState.downloadETA {
                        Text("~\(eta)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else if ModelManager.shared.isDownloaded(model) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                if appState.config.resolvedModelId == model.id {
                    Text(L.t("active", es: "activo")).font(.caption).foregroundStyle(.secondary)
                } else {
                    Button(L.t("Use", es: "Usar")) { appState.config.setModel(model.id) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            } else {
                Button(L.t("Download", es: "Descargar")) { appState.downloadModel(id: model.id) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Advanced

struct AdvancedSettings: View {
    @EnvironmentObject var appState: AppState
    // Reflect the OS's actual registration instead of a guessed default.
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
            Toggle(L.t("Learn from my corrections automatically", es: "Aprender de mis correcciones automáticamente"), isOn: Binding(
                get: { appState.config.autoLearn },
                set: { appState.config.setAutoLearn($0) }
            ))
            Text(L.t("After each dictation, Voza briefly re-reads only the text it just pasted. If you fix it by typing, Voza learns the correction — on your Mac, never recorded, never sent anywhere.", es: "Después de cada dictado, Voza relee por unos segundos únicamente el texto que acaba de pegar. Si lo corriges tecleando, Voza aprende la corrección — en tu Mac, sin grabar nada, sin enviar nada."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
        .padding(20)
    }
}

// MARK: - License

struct LicenseSettings: View {
    @EnvironmentObject var appState: AppState
    @State private var key = ""
    @State private var activating = false

    var body: some View {
        Form {
            switch appState.license.state {
            case .licensed(let email):
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.t("Voza is activated — thank you!", es: "Voza está activada — ¡gracias!"))
                            .font(.headline)
                        if let email {
                            Text(email).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
            case .trial(let daysLeft):
                Label(L.t("Trial: \(daysLeft) days left", es: "Prueba: \(daysLeft) días restantes"),
                      systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            case .trialOver:
                Label(L.t("Trial finished — the nag continues, dictation keeps working.", es: "Prueba terminada — el recordatorio sigue, el dictado sigue funcionando."),
                      systemImage: "exclamationmark.circle")
                    .foregroundStyle(Theme.accent)
            case .invalid(let message):
                Label(message, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
            case .unlicensed:
                EmptyView()
            }

            HStack {
                SecureField("VOZA-XXXX-XXXX-XXXX", text: $key)
                    .textFieldStyle(.roundedBorder)
                Button(activating ? L.t("Activating…", es: "Activando…") : L.t("Activate", es: "Activar")) {
                    activating = true
                    Task {
                        await appState.license.activate(key)
                        activating = false
                    }
                }
                .disabled(key.isEmpty || activating)
                .buttonStyle(.borderedProminent)
            }

            HStack {
                Text(L.t("No license yet?", es: "¿Aún no tienes licencia?"))
                    .foregroundStyle(.secondary)
                Link(L.t("Buy Voza ($29) →", es: "Comprar Voza ($29) →"),
                     destination: URL(string: "https://jerotherey.gumroad.com/l/\(appState.config.gumroadPermalink)")!)
                    .foregroundStyle(Theme.accent)
            }
            .font(.callout)

            Text(L.t("Licenses are verified once against Gumroad and then cached — Voza keeps working fully offline. The source remains MIT: build it yourself and no license is needed.",
                     es: "La licencia se verifica una vez contra Gumroad y queda en caché — Voza sigue funcionando 100% offline. El código sigue siendo MIT: compílalo tú mismo y no necesitas licencia."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

// MARK: - About

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
