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
            CorrectionsSettings().environmentObject(appState)
                .tabItem { Label(L.t("Corrections", es: "Correcciones"), systemImage: "character.book.closed") }
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
                // D055 (subtract-before-you-add): whisper-cli is bundled statically (D043);
                // never surface the legacy Homebrew installer card to end users.
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
                 detail: L.t("Voza's bundled whisper.cpp engine was not found. Reinstall Voza.app or check Settings → Advanced.",
                             es: "No se encontró el motor whisper.cpp integrado de Voza. Reinstala Voza.app o revisa Ajustes → Avanzado."))
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
                 detail: L.t("Hold either Option key, talk, release — your words are pasted as spoken. Optional AI cleanup lives in the Dictation tab.",
                             es: "Mantén cualquiera de las teclas Option, habla y suelta — tus palabras se pegan tal cual. La limpieza IA opcional vive en la pestaña Dictado."))
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
            chip(L.t("\(appState.learnedCount) learned", es: "\(appState.learnedCount) aprendidas"), ok: true)
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
                Picker(L.t("Smart Polish", es: "Pulido inteligente"), selection: Binding(
                    get: { (appState.config.cleanupMode == "cloud" && !appState.config.hasCleanupProvider) ? "plain" : appState.config.cleanupMode },
                    set: { appState.config.setCleanupMode($0) }
                )) {
                    Text(L.t("Off — type exactly what I say", es: "Apagado — escribe tal cual lo que digo")).tag("plain")
                    if appState.config.hasCleanupProvider {
                        Text(L.t("On — fix punctuation & remove fillers", es: "Activado — corrige puntuación y muletillas")).tag("cloud")
                    }
                }
                CloudKeySection()
            } header: {
                Text(L.t("Writing style", es: "Estilo de escritura"))
            }
            Section {
                Picker(L.t("Spoken language", es: "Idioma al hablar"), selection: Binding(
                    get: { appState.config.language },
                    set: { appState.config.setLanguage($0) }
                )) {
                    Text(L.t("Automatic", es: "Automático")).tag("auto")
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
                Text(L.t("**Tap Option** for hands-free dictation (tap again to finish), or **hold Option** while speaking. Fix any word by typing and Voza learns it automatically.",
                         es: "**Toca Option** para dictar en manos libres (toca de nuevo para terminar), o **mantén Option** mientras hablas. Si corriges una palabra tecleando, Voza la aprende sola."))
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

// MARK: - Corrections (the learned dictionary, visible and editable)

/// The user-facing surface of the auto-learn feature (D033): every lesson
/// Voza taught itself is visible, editable and deletable here. Trust requires
/// inspectability — "the app learns from you" only works if "you" can see
/// what it learned and undo it.
struct CorrectionsSettings: View {
    @EnvironmentObject var appState: AppState
    @State private var corrections: [Correction] = []
    @State private var editingId: UUID?
    @State private var editSaid = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "character.book.closed").foregroundStyle(Theme.accent)
                Text(L.t("Applied on every dictation. Fix a word by typing and Voza learns it here.",
                         es: "Se aplican en cada dictado. Corrige una palabra tecleando y Voza la aprende aquí."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 14)

            if corrections.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(L.t("Nothing learned yet", es: "Aún no ha aprendido nada"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L.t("After a dictation, fix any word by typing — Voza learns it automatically. You can also fix past dictations from the menu bar history (✏️).",
                             es: "Después de un dictado, corrige cualquier palabra tecleando — Voza la aprende automáticamente. También puedes corregir dictados pasados desde el historial de la barra de menú (✏️)."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(corrections) { c in
                        correctionRow(c)
                        Divider().padding(.leading, 12)
                    }
                }
                .listStyle(.inset)
                Text(L.t("\(corrections.count) learned · stored only on this Mac", es: "\(corrections.count) aprendidas · guardadas solo en esta Mac"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20).padding(.bottom, 10)
            }
        }
        .onAppear { corrections = CorrectionStore.shared.all() }
    }

    @ViewBuilder
    private func correctionRow(_ c: Correction) -> some View {
        if editingId == c.id {
            HStack(spacing: 8) {
                TextField(c.heard, text: $editSaid)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(saveEdit)
                Button(L.t("Save", es: "Guardar"), action: saveEdit)
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(L.t("Cancel", es: "Cancelar")) { editingId = nil }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.said).font(.system(size: 12, weight: .semibold))
                    Text(L.t("when Voza hears “\(c.heard)”", es: "cuando Voza oye “\(c.heard)”"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    editingId = c.id
                    editSaid = c.said
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless).controlSize(.small)
                Button {
                    CorrectionStore.shared.delete(id: c.id)
                    corrections = CorrectionStore.shared.all()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless).controlSize(.small)
            }
        }
    }

    private func saveEdit() {
        if let id = editingId, let c = corrections.first(where: { $0.id == id }) {
            // record() updates the existing entry for the same heard phrase.
            CorrectionStore.shared.record(heard: c.heard, said: editSaid)
            corrections = CorrectionStore.shared.all()
        }
        editingId = nil
    }
}

// MARK: - Advanced

struct AdvancedSettings: View {
    @EnvironmentObject var appState: AppState
    // Reflect the OS's actual registration instead of a guessed default.
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var whisperBinaryDraft = ""
    @State private var modelsDirDraft = ""
    @State private var showClearHistoryConfirm = false

    private func commitDrafts() {
        let trimmedBin = whisperBinaryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let newBin: String? = trimmedBin.isEmpty ? nil : trimmedBin
        if newBin != appState.config.whisperBinary {
            appState.config.setWhisperBinary(newBin)
        }
        let trimmedDir = modelsDirDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let newDir: String? = trimmedDir.isEmpty ? nil : trimmedDir
        if newDir != appState.config.modelsDirectory {
            appState.config.setModelsDirectory(newDir)
        }
    }

    var body: some View {
        Form {
            HStack {
                TextField(L.t("whisper.cpp binary (empty = auto)", es: "Binario whisper.cpp (vacío = auto)"),
                          text: $whisperBinaryDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitDrafts() }
                Image(systemName: Transcriber.locateBinary() != nil ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(Transcriber.locateBinary() != nil ? Color.green : Color.orange)
            }
            HStack {
                TextField(L.t("Models directory", es: "Carpeta de modelos"),
                          text: $modelsDirDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitDrafts() }
                Button(L.t("Reveal", es: "Mostrar")) {
                    commitDrafts()
                    NSWorkspace.shared.open(ModelManager.shared.modelsDirectory)
                }
            }
            Toggle(L.t("Launch Voza at login", es: "Abrir Voza al iniciar sesión"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = (SMAppService.mainApp.status == .enabled)
                    }
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
            Toggle(L.t("Save transcript history to disk (~/Dictation)", es: "Guardar historial de dictados en disco (~/Dictation)"), isOn: Binding(
                get: { appState.config.saveHistory },
                set: { appState.config.setSaveHistory($0) }
            ))
            HStack {
                Text(L.t("Recent dictations stay in memory while Voza is open even if disk history is off.",
                         es: "Los dictados recientes se mantienen en memoria mientras Voza está abierta aunque apagues el guardado en disco."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L.t("Clear History…", es: "Borrar historial…"), role: .destructive) {
                    showClearHistoryConfirm = true
                }
                .controlSize(.small)
                .confirmationDialog(
                    L.t("Delete all saved transcript logs in ~/Dictation and clear recent history?",
                        es: "¿Eliminar todos los archivos de historial en ~/Dictation y vaciar la lista reciente?"),
                    isPresented: $showClearHistoryConfirm,
                    titleVisibility: .visible
                ) {
                    Button(L.t("Delete History", es: "Eliminar historial"), role: .destructive) {
                        appState.clearHistory()
                    }
                }
            }
        }
        .padding(20)
        .onAppear {
            whisperBinaryDraft = appState.config.whisperBinary ?? ""
            modelsDirDraft = appState.config.modelsDirectory ?? ""
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
        .onDisappear {
            commitDrafts()
        }
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
                     // P2-5 (audit 2026-09-21): force-unwrap crashed the whole
                     // License tab on an unencodable permalink.
                     destination: gumroadURL(permalink: appState.config.gumroadPermalink))
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

/// P2-5 (audit 2026-09-21): percent-encodes the permalink and NEVER force-
/// unwraps — an unencodable value degrades to the plain product page.
func gumroadURL(permalink: String) -> URL {
    let encoded = permalink.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? permalink
    return URL(string: "https://jerotherey.gumroad.com/l/\(encoded)")
        ?? URL(string: "https://jerotherey.gumroad.com/l/voza")!
}

/// V12 — GUI for the cloud cleanup key. A buyer never opens a terminal:
/// paste the key here and it goes straight into the macOS Keychain (never a
/// plaintext file). The field is SecureField; the stored value is never
/// displayed back — only its presence (a status line + the picker gate).
struct CloudKeySection: View {
    @EnvironmentObject var appState: AppState
    @State private var draftKey = ""
    @State private var clipboardCandidate: (preset: Cleaner.CloudProviderPreset, key: String)?
    @State private var isGuidingSetup = false
    @State private var guideBaselineChangeCount: Int = 0
    @State private var guideWatchTask: Task<Void, Never>?
    @State private var showManualField = false
    @State private var feedback: String?
    @State private var showRemoveConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appState.config.hasCleanupProvider {
                let activePreset = Cleaner.CloudProviderPreset.current(in: appState.config.env)
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(L.t("Connected with \(activePreset.providerShortName) · audio stays on your Mac",
                             es: "Conectado con \(activePreset.providerShortName) · tu audio nunca sale de la Mac"))
                        .font(.caption.weight(.medium))
                    Spacer()
                    Button(L.t("Disconnect", es: "Desconectar"), role: .destructive) {
                        showRemoveConfirm = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                .confirmationDialog(
                    L.t("Disconnect Smart Polish?", es: "¿Desconectar el Pulido inteligente?"),
                    isPresented: $showRemoveConfirm,
                    titleVisibility: .visible
                ) {
                    Button(L.t("Disconnect", es: "Desconectar"), role: .destructive) { remove() }
                }
            } else if isGuidingSetup {
                guidedSetupCard
            } else {
                Text(L.t("Smart Polish uses a free Groq key (or OpenAI / Anthropic) to fix punctuation and remove fillers in ~180 ms.",
                         es: "El Pulido inteligente usa una llave gratuita de Groq (u OpenAI / Anthropic) para corregir puntuación y muletillas en ~180 ms."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let candidate = clipboardCandidate {
                    Button {
                        connectKey(candidate.key, autoDetected: true)
                    } label: {
                        Label(
                            L.t("Connect copied \(candidate.preset.providerShortName) key in 1 click",
                                es: "Conectar llave de \(candidate.preset.providerShortName) copiada (1 clic)"),
                            systemImage: "sparkles"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }

                HStack(spacing: 10) {
                    Button {
                        startGuidedSetup(url: URL(string: "https://console.groq.com/keys")!)
                    } label: {
                        Label(
                            L.t("Guide me to get a free key (30 s)",
                                es: "Guíame para sacar mi llave gratis (30 s)"),
                            systemImage: "wand.and.stars"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        if let clip = NSPasteboard.general.string(forType: .string),
                           Cleaner.CloudProviderPreset.validKeyCandidate(from: clip) != nil {
                            connectKey(clip, autoDetected: true)
                        } else {
                            showManualField.toggle()
                        }
                    } label: {
                        Text(L.t("I already have a key", es: "Ya tengo una llave"))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if showManualField {
                    HStack(spacing: 8) {
                        SecureField(
                            L.t("Paste key here — connects automatically",
                                es: "Pega tu llave aquí — se conecta sola"),
                            text: $draftKey
                        )
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: draftKey) { _, newValue in
                            if let valid = Cleaner.CloudProviderPreset.validKeyCandidate(from: newValue) {
                                connectKey(valid.key, autoDetected: false)
                            }
                        }
                        .onSubmit {
                            connectKey(draftKey, autoDetected: false)
                        }

                        Button {
                            if let clip = NSPasteboard.general.string(forType: .string) {
                                connectKey(clip, autoDetected: false)
                            }
                        } label: {
                            Label(L.t("Paste", es: "Pegar"), systemImage: "doc.on.clipboard")
                        }
                        .controlSize(.small)
                    }
                }
            }
            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
        .onAppear { refreshClipboardCandidate() }
        .onDisappear { stopGuidedSetup() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshClipboardCandidate()
        }
    }

    private var guidedSetupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L.t("Waiting for you to copy your key…",
                         es: "Esperando a que copies tu llave…"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(L.t("Cancel", es: "Cancelar")) {
                    stopGuidedSetup()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            VStack(alignment: .leading, spacing: 5) {
                guideStep(
                    number: "1",
                    text: L.t("Sign in with Google or GitHub on the page that just opened.",
                              es: "Inicia sesión con Google o GitHub en la página que se acaba de abrir.")
                )
                guideStep(
                    number: "2",
                    text: L.t("Click **Create API Key** and give it any name (e.g. “Voza”).",
                              es: "Haz clic en **Create API Key** y ponle cualquier nombre (ej. “Voza”).")
                )
                guideStep(
                    number: "3",
                    text: L.t("Click **Copy** — Voza detects it from your clipboard and connects automatically!",
                              es: "Haz clic en **Copy** — ¡Voza la detecta sola del portapapeles y se conecta automáticamente!")
                )
            }
            .padding(.vertical, 2)

            HStack(spacing: 12) {
                Button(L.t("Reopen Groq ↗", es: "Reabrir Groq ↗")) {
                    NSWorkspace.shared.open(URL(string: "https://console.groq.com/keys")!)
                }
                .buttonStyle(.link)
                .font(.caption2)

                Button(L.t("Use OpenAI instead ↗", es: "Usar OpenAI ↗")) {
                    NSWorkspace.shared.open(URL(string: "https://platform.openai.com/api-keys")!)
                }
                .buttonStyle(.link)
                .font(.caption2)

                Button(L.t("Use Anthropic instead ↗", es: "Usar Anthropic ↗")) {
                    NSWorkspace.shared.open(URL(string: "https://console.anthropic.com/settings/keys")!)
                }
                .buttonStyle(.link)
                .font(.caption2)
            }
        }
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
    }

    private func guideStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(number)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Theme.accent))
            Text(.init(text))
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    private func startGuidedSetup(url: URL) {
        feedback = nil
        guideBaselineChangeCount = NSPasteboard.general.changeCount
        isGuidingSetup = true
        NSWorkspace.shared.open(url)
        guideWatchTask?.cancel()
        guideWatchTask = Task { @MainActor in
            // Poll clipboard every 0.5s for up to 3 minutes while the user creates & copies their key.
            for _ in 0..<360 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled, isGuidingSetup else { return }
                let pb = NSPasteboard.general
                guard pb.changeCount != guideBaselineChangeCount else { continue }
                guideBaselineChangeCount = pb.changeCount
                if let clip = pb.string(forType: .string),
                   let valid = Cleaner.CloudProviderPreset.validKeyCandidate(from: clip) {
                    connectKey(valid.key, autoDetected: true)
                    return
                }
            }
            if isGuidingSetup {
                isGuidingSetup = false
            }
        }
    }

    private func stopGuidedSetup() {
        guideWatchTask?.cancel()
        guideWatchTask = nil
        isGuidingSetup = false
    }

    private func refreshClipboardCandidate() {
        guard !appState.config.hasCleanupProvider else {
            clipboardCandidate = nil
            return
        }
        let clip = NSPasteboard.general.string(forType: .string)
        clipboardCandidate = Cleaner.CloudProviderPreset.validKeyCandidate(from: clip)
    }

    private func connectKey(_ raw: String, autoDetected: Bool) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let preset = Cleaner.CloudProviderPreset.detect(fromKey: value) ?? .openai
        let keychain = Config.productionKeychain(for: AppPaths.default)
        appState.config.applyCloudPreset(preset, keychain: keychain)
        if appState.config.saveCleanupKey(preset.keySlot, value: value, keychain: keychain) {
            appState.config.setCleanupMode("cloud")
            stopGuidedSetup()
            showManualField = false
            clipboardCandidate = nil
            feedback = L.t("✓ Connected automatically with \(preset.providerShortName)!",
                           es: "✓ ¡Conectado automáticamente con \(preset.providerShortName)!")
            if autoDetected {
                NSSound(named: "Glass")?.play()
                NSApp.bringSettingsToFront()
            }
        } else {
            feedback = L.t("Could not save the key to Keychain.",
                           es: "No se pudo guardar la llave en el Llavero.")
        }
        draftKey = ""
    }

    private func remove() {
        stopGuidedSetup()
        let keychain = Config.productionKeychain(for: AppPaths.default)
        for key in Config.credentialKeys {
            appState.config.deleteCleanupKey(key, keychain: keychain)
        }
        appState.config.setCleanupModel(nil)
        if appState.config.cleanupMode == "cloud" {
            appState.config.setCleanupMode("plain")
        }
        feedback = nil
        refreshClipboardCandidate()
    }
}
