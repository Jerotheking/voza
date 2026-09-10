# Mapa de código: qué existe y dónde va cada cambio

Baseline `44caaf145c4e1e77d53afbc31dfdd1e3c79aaabf`. Líneas y hashes en [evidence/baseline.json](evidence/baseline.json). Símbolos son anclas; volver a buscarlos si cambia HEAD. Las rutas nuevas son propuestas, no archivos implementados.

## Archivos actuales auditados

| Archivo / líneas | Símbolos y lectura | Destino / responsabilidad | Tickets dueños |
|---|---|---|---|
| [Sources/VozaSmoke/main.swift](../../Sources/VozaSmoke/main.swift) · 202 l | check/top-level smoke/E2E | Reescribir hermeticidad; integración manual opt-in; no borrar datos reales. | V02, V05 |
| [Sources/Voza/VozaEntryPoint.swift](../../Sources/Voza/VozaEntryPoint.swift) · 8 l | entrypoint | Conservar entrypoint mínimo; ningún pipeline nuevo aquí. | Sin cambios previstos |
| [Sources/VozaKit/UI/SettingsView.swift](../../Sources/VozaKit/UI/SettingsView.swift) · 571 l | SettingsView/StatusView/DictationSettings/ModelSettings/AdvancedSettings/LicenseSettings/AboutSettings | Separar vistas en UI/Settings según UX; composición observando estado real. | V17, V18 |
| [Sources/VozaKit/UI/PopoverView.swift](../../Sources/VozaKit/UI/PopoverView.swift) · 177 l | PopoverView/TranscriptRow | Dos modos, controles accesibles, estado y recuperación; settings siempre disponible. | V18, V20, V25 |
| [Sources/VozaKit/UI/Theme.swift](../../Sources/VozaKit/UI/Theme.swift) · 11 l | Theme | Tokens nativos; conservar marca mientras D012 pendiente; no hardcode para ocultar clipping. | V20 |
| [Sources/VozaKit/UI/OnboardingView.swift](../../Sources/VozaKit/UI/OnboardingView.swift) · 115 l | OnboardingView/refresh | O01–O05 con OnboardingState/readiness únicos. | V19 |
| [Sources/VozaKit/Core/TranscriptStore.swift](../../Sources/VozaKit/Core/TranscriptStore.swift) · 109 l | add/appendToFile/parseEntries/loadRecent | Separar RAM/historial; policy, publicación completion, formato estructurado y export Markdown. | V01, V10 |
| [Sources/VozaKit/Core/HotKeyManager.swift](../../Sources/VozaKit/Core/HotKeyManager.swift) · 116 l | installTap/handleFlagsChanged/ensureTapAlive/stop | Corregir constantes; reducer dueño de tecla; lifecycle tap/timer; hold/toggle. | V03, V18 |
| [Sources/VozaKit/Core/Paster.swift](../../Sources/VozaKit/Core/Paster.swift) · 54 l | paste/sendCmdV | InsertionEngine @MainActor; async, snapshot completo y receipt honesto. | V09 |
| [Sources/VozaKit/Core/Permissions.swift](../../Sources/VozaKit/Core/Permissions.swift) · 50 l | allGranted/requestMicrophone/open settings | Capacidades reales/contextuales y SessionPrivacyGuard; no solicitud inútil repetida. | V08 |
| [Sources/VozaKit/Core/Config.swift](../../Sources/VozaKit/Core/Config.swift) · 146 l | load/persist/setters/resolved values | Facade temporal de SettingsRepository tipado; rutas puras y migración conservadora. | V01, V11, V12 |
| [Sources/VozaKit/Core/ReadinessChecker.swift](../../Sources/VozaKit/Core/ReadinessChecker.swift) · 41 l | check/requiredFreeMB/freeDiskMB | ReadinessReport por modo y unknown; destino de disco; no efectos al leer. | V15, V17 |
| [Sources/VozaKit/Core/Transcriber.swift](../../Sources/VozaKit/Core/Transcriber.swift) · 102 l | locateBinary/transcribe/runProcess/isNonSpeechMarker | Adapter SpeechEngine; runner cancelable; binario bundled; filtro específico y no Config.shared durante ejecución. | V04, V14, V16 |
| [Sources/VozaKit/Core/PerformanceMonitor.swift](../../Sources/VozaKit/Core/PerformanceMonitor.swift) · 103 l | record/medianRTF/suggestion/_test_clear | Mediciones por modo/modelo; sin índice lingüísticamente inseguro; tests aislados. | V01, V14, V26 |
| [Sources/VozaKit/Core/Cleaner.swift](../../Sources/VozaKit/Core/Cleaner.swift) · 154 l | providerChain/clean/ollamaClean/openAIClean/anthropicClean | Adapter legacy→TextProcessor local; cloud solo opt-in; outcome y validación separados. | V12, V24 |
| [Sources/VozaKit/Core/ModelManager.swift](../../Sources/VozaKit/Core/ModelManager.swift) · 214 l | WhisperCatalog/HardwareProfile/resolvedModel/download | Catálogo con idiomas/hash/origen; política compartida; descarga/lease independiente. | V02, V14, V15, V23 |
| [Sources/VozaKit/Core/AudioRecorder.swift](../../Sources/VozaKit/Core/AudioRecorder.swift) · 180 l | AudioRecorder.start/stop/cancel/enqueue/wavHeader | Conservar captura/formato; aislamiento/escritor/AudioAsset y rollback. No reintroducir header malformado. | V05, V20 |
| [Sources/VozaKit/Core/BrewInstaller.swift](../../Sources/VozaKit/Core/BrewInstaller.swift) · 70 l | installEngine/brewPath | Retirar del camino estándar al empaquetar; eliminar si queda sin callers, no instalador invisible alternativo. | V16 |
| [Sources/VozaKit/Core/LicenseManager.swift](../../Sources/VozaKit/Core/LicenseManager.swift) · 175 l | activate/verifyRequest/reverify/readCache/writeCache | Transport/Clock inyectados; verdict trivalente y entitlement separado; mantener proveedor hasta decisión. | V01, V13 |
| [Sources/VozaKit/App/VozaApp.swift](../../Sources/VozaKit/App/VozaApp.swift) · 60 l | VozaApp/AppDelegate/MenuBarLabel | Composition root, lifecycle/cancel, panel y updater; no abrir el mic al importar tests. | V07, V18, V19, V20, V28 |
| [Sources/VozaKit/App/Localizer.swift](../../Sources/VozaKit/App/Localizer.swift) · 20 l | L.override/isSpanish/t | Separar idioma UI de voz; inyectar resolución tests; copy estable ES/EN. | V02, V18 |
| [Sources/VozaKit/State/AppState.swift](../../Sources/VozaKit/State/AppState.swift) · 255 l | AppState.startDictation/stopDictation/pipeline/downloadModel/refresh | Proyección @MainActor; pipeline a DictationPipeline; descarga independiente; Config snapshot por sesión. | V05, V07, V10, V11, V15, V17, V25, V26 |
| [Tests/VozaTests/ConfigTests.swift](../../Tests/VozaTests/ConfigTests.swift) · 50 l | testHardwareProfileRecommendsByRAM/testTranscriptStoreWritesAndReadsLog | Reparar firma y fixtures; dividir suites por dueño de riesgo. | V02 |
| [packaging/Voza.entitlements](../../packaging/Voza.entitlements) · 12 l | audio-input/apple-events | Menor privilegio necesario; quitar Apple Events si no se usa realmente. | V28 |
| [packaging/voza.rb](../../packaging/voza.rb) · 23 l | version/sha256/url | Checksum real y requisitos de artefacto; no :no_check. | V28 |
| [packaging/Info.plist](../../packaging/Info.plist) · 19 l | bundle/version/permissions | Version/build coherentes; textos permisos honestos; no cambiar bundle ID sin migración. | V16, V28 |
| [scripts/release.sh](../../scripts/release.sh) · 61 l | sign/notarize/staple/DMG | Validar artefacto final con autorización; inside-out y no --deep. | V16, V28 |
| [scripts/make-icons.sh](../../scripts/make-icons.sh) · 21 l | icon conversion | Sin cambio necesario salvo packaging bloqueado; no ejecutar por auditoría. | Sin cambios previstos |
| [design/landing.html](../../design/landing.html) · 295 l | hero/comparison/FAQ/buy | Blueprint Literal/Pulido; claims verificables y términos aceptados. | V29 |
| [design/wireframes/wireframes.html](../../design/wireframes/wireframes.html) · 187 l | wireframes estáticos | Referencia visual histórica; no evidencia de UI instalada. | Sin cambios previstos |
| [design/assets/voza-icon.svg](../../design/assets/voza-icon.svg) · 20 l | icono | Conservar hasta decisión de marca; no modificar como parte de bugs. | Sin cambios previstos |
| [Package.swift](../../Package.swift) · 28 l | targets/platforms | Mantener targets y mínimo; añadir dependencia updater/engine solo justificada y pinned. | V02, V04, V28 |
| [build.sh](../../build.sh) · 35 l | bundle build | Empaquetar engine/resources y no ocultar errores; build distinto de release. | V16, V28 |
| [README.md](../../README.md) · 141 l | requirements/config/licensing/verification | Claims/version/precios y comandos según gates; distinguir beta de estable. | V29 |
| [docs/AUDIT-SPEC.md](../../docs/AUDIT-SPEC.md) · 422 l | spec histórico con contradicciones | Actualizar con estado de versión, conservando histórico original del paquete. | V29 |
| [docs/design-adaptive-ux.md](../../docs/design-adaptive-ux.md) · 60 l | UX parcial técnica | Referenciar PRD vigente; no RTF invertido ni tres permisos ausentes del flow. | V29 |
| [docs/market-analysis.md](../../docs/market-analysis.md) · 49 l | market/pricing/roadmap | Revalidar fuentes antes de publicar; propuestas distintas de hechos. | V29 |

## Nuevos archivos propuestos y dueño de creación

Creación solo dentro del ticket autorizado; si un agente anterior ya creó el archivo, verificar contrato/callers antes de duplicarlo. Los archivos de evidencia se generan al ejecutar, no ahora.

| Ruta propuesta | Primer ticket / posteriores | Existe en baseline |
|---|---|---|
| `.github/workflows/ci.yml` | V02 | No |
| `Sources/VozaKit/App/Dependencies.swift` | V06, V07, V08, V09, V10, V11, V12, V13, V14, V15, V16, V17, V18, V19, V20, V23, V24, V25, V26, V28 | No |
| `Sources/VozaKit/Core/AppPaths.swift` | V01 | No |
| `Sources/VozaKit/Core/AppPreferencesStore.swift` | V31 | No |
| `Sources/VozaKit/Core/AudioAsset.swift` | V05 | No |
| `Sources/VozaKit/Core/Clock.swift` | V01 | No |
| `Sources/VozaKit/Core/DictationPipeline.swift` | V07, V08, V09, V25 | No |
| `Sources/VozaKit/Core/EngineAssets.swift` | V16, V23 | No |
| `Sources/VozaKit/Core/EnginePolicy.swift` | V14, V22, V26, V31 | No |
| `Sources/VozaKit/Core/HardwareSnapshot.swift` | V26 | No |
| `Sources/VozaKit/Core/HotkeyBinding.swift` | V03 | No |
| `Sources/VozaKit/Core/InsertionEngine.swift` | V09 | No |
| `Sources/VozaKit/Core/InsertionReceipt.swift` | V09 | No |
| `Sources/VozaKit/Core/KeychainStore.swift` | V12 | No |
| `Sources/VozaKit/Core/LicenseTransport.swift` | V13 | No |
| `Sources/VozaKit/Core/LocalTextProcessor.swift` | V23 | No |
| `Sources/VozaKit/Core/ProcessRunner.swift` | V04 | No |
| `Sources/VozaKit/Core/ReadinessReport.swift` | V17 | No |
| `Sources/VozaKit/Core/RecoveryBuffer.swift` | V10, V25 | No |
| `Sources/VozaKit/Core/RetentionPolicy.swift` | V10 | No |
| `Sources/VozaKit/Core/RewriteValidator.swift` | V24 | No |
| `Sources/VozaKit/Core/SessionPrivacyGuard.swift` | V08 | No |
| `Sources/VozaKit/Core/SessionTypes.swift` | V06 | No |
| `Sources/VozaKit/Core/SettingsRepository.swift` | V11 | No |
| `Sources/VozaKit/Core/SettingsSnapshot.swift` | V11 | No |
| `Sources/VozaKit/Core/SpeechEngine.swift` | V06 | No |
| `Sources/VozaKit/Core/TargetInspector.swift` | V08 | No |
| `Sources/VozaKit/Core/TextProcessor.swift` | V06, V23 | No |
| `Sources/VozaKit/Core/UpdateCoordinator.swift` | V28 | No |
| `Sources/VozaKit/Core/VocabularyStore.swift` | V31 | No |
| `Sources/VozaKit/State/OnboardingState.swift` | V19 | No |
| `Sources/VozaKit/UI/ModePicker.swift` | V18 | No |
| `Sources/VozaKit/UI/RecordingPanel.swift` | V20 | No |
| `Sources/VozaKit/UI/RecoveryView.swift` | V25 | No |
| `Sources/VozaKit/UI/Settings/AboutSettings.swift` | V18 | No |
| `Sources/VozaKit/UI/Settings/AdvancedSettings.swift` | V18 | No |
| `Sources/VozaKit/UI/Settings/DictationSettings.swift` | V18, V31 | No |
| `Sources/VozaKit/UI/Settings/LicenseSettings.swift` | V18 | No |
| `Sources/VozaKit/UI/Settings/PrivacySettings.swift` | V18 | No |
| `Sources/VozaKit/UI/Settings/StatusView.swift` | V18 | No |
| `Tests/VozaTests/AdaptivePolicyTests.swift` | V26 | No |
| `Tests/VozaTests/AppPreferencesTests.swift` | V31 | No |
| `Tests/VozaTests/AudioRecorderTests.swift` | V05 | No |
| `Tests/VozaTests/DictationPipelineTests.swift` | V07 | No |
| `Tests/VozaTests/EndToEndContractTests.swift` | V27 | No |
| `Tests/VozaTests/EngineAssetsTests.swift` | V16 | No |
| `Tests/VozaTests/EnginePolicyTests.swift` | V14 | No |
| `Tests/VozaTests/Fixtures/Polished/development.json` | V21 | No |
| `Tests/VozaTests/Fixtures/Polished/holdout-manifest.json` | V21 | No |
| `Tests/VozaTests/HotKeyManagerTests.swift` | V03 | No |
| `Tests/VozaTests/LicenseManagerTests.swift` | V13 | No |
| `Tests/VozaTests/LocalTextProcessorTests.swift` | V23 | No |
| `Tests/VozaTests/ModePipelineTests.swift` | V25 | No |
| `Tests/VozaTests/ModeSelectionTests.swift` | V18 | No |
| `Tests/VozaTests/ModelDownloadTests.swift` | V15 | No |
| `Tests/VozaTests/OnboardingTests.swift` | V19 | No |
| `Tests/VozaTests/PasterTests.swift` | V09 | No |
| `Tests/VozaTests/PolishedContractTests.swift` | V21 | No |
| `Tests/VozaTests/ProcessRunnerTests.swift` | V04 | No |
| `Tests/VozaTests/ProviderPrivacyTests.swift` | V12 | No |
| `Tests/VozaTests/ReadinessTests.swift` | V17 | No |
| `Tests/VozaTests/RecordingPanelTests.swift` | V20 | No |
| `Tests/VozaTests/RecoveryBufferTests.swift` | V10 | No |
| `Tests/VozaTests/RewriteValidatorTests.swift` | V24 | No |
| `Tests/VozaTests/SessionPrivacyGuardTests.swift` | V08 | No |
| `Tests/VozaTests/SessionTypesTests.swift` | V06 | No |
| `Tests/VozaTests/SettingsRepositoryTests.swift` | V11 | No |
| `Tests/VozaTests/SmokeIsolationTests.swift` | V02 | No |
| `Tests/VozaTests/Support/ProcessFixtures.swift` | V04 | No |
| `Tests/VozaTests/Support/TestEnvironment.swift` | V01 | No |
| `Tests/VozaTests/TranscriptStoreTests.swift` | V10 | No |
| `Tests/VozaTests/UpdateCoordinatorTests.swift` | V28 | No |
| `Tests/VozaTests/VocabularyTests.swift` | V31 | No |
| `docs/plan-glm/DECISIONS.md` | V29 | No |
| `docs/plan-glm/evidence/V21/corpus-protocol.md` | V21 | No |
| `docs/plan-glm/evidence/V22/benchmark-results.json` | V22 | No |
| `docs/plan-glm/evidence/V22/engine-decision.md` | V22 | No |
| `docs/plan-glm/evidence/V27/compatibility.json` | V27 | No |
| `docs/plan-glm/evidence/V27/manual-qa.md` | V27 | No |
| `docs/plan-glm/evidence/V29/commercial-readiness.md` | V29 | No |
| `docs/plan-glm/evidence/V30/beta-protocol.md` | V30 | No |
| `docs/plan-glm/evidence/V30/decision.md` | V30 | No |
| `docs/plan-glm/evidence/V30/funnel.json` | V30 | No |
| `docs/plan-glm/evidence/V32/scope-decision.md` | V32 | No |
| `Tests/VozaTests/AppPathsTests.swift` | V01 | No |
| `Tests/VozaTests/TestEnvironmentTests.swift` | V01 | No |
| `Sources/VozaProcessFixture/main.swift` | V04 | No |

## Traza de hallazgos

| Hallazgo | Tickets |
|---|---|
| F01 | V03, V27 |
| F02 | V08, V09, V10, V25, V27 |
| F03 | V14, V22, V26 |
| F04 | V06, V07, V15, V27 |
| F05 | V04, V27 |
| F06 | V05, V27 |
| F07 | V13, V27 |
| F08 | V16, V17, V19, V20, V23, V27 |
| F09 | V06, V07, V10, V11, V17, V18, V20, V25, V27 |
| F10 | V01, V02 |
| F11 | V11 |
| F12 | V15, V27 |
| F13 | V06, V21, V22, V23, V24, V25, V27 |
| F14 | V16, V28, V29 |
| F15 | V09, V27 |
| F16 | V12, V13 |
| F17 | V14, V21, V24 |
| F18 | V18, V29 |
| F19 | V10 |
| F20 | V28 |

## Callers que no deben quedar desincronizados

1. Cambiar `Config` afecta casi todos los componentes; V01/V11 preservan fachada y migran callers en una sola ruta.
2. Cambiar `AudioRecorder.stop` a AudioAsset requiere adaptar AppState/pipeline, tests y Smoke; no mantener duración visual como fallback silencioso.
3. Cambiar Paster a async/receipt exige await y interpretación honesta en pipeline, no descartar resultado.
4. `TranscriptStore.add` completion debe publicar el snapshot; no llamar refresh antes y confiar en timing.
5. `LicenseManager` es ObservableObject separado: vista lo observa o AppState retransmite; no esperar que let license publique a través de otro objeto.
6. Extraer vistas de SettingsView requiere eliminar definiciones duplicadas y mantener EnvironmentObject/dependencies; no solo copiar structs.
7. `VozaSmoke` usa @testable VozaKit: cambios de accesibilidad/targets deben compilar la suite real.
8. El catalogue/model policy comparte metadatos entre readiness, UI, downloader y transcriber: no corregir idioma en solo una ruta.
9. El empaquetado debe resolver el mismo engine manifest que runtime y release; tres listas de versiones separadas volverían a divergir.
10. Al cambiar mode, historial y copy deben registrar modo realmente aplicado, no solo solicitado.

## Anclas exactas del baseline

Símbolos extraídos del checkout actual. Índice completo legible por máquina: [symbols.json](evidence/symbols.json). Si HEAD cambió, usar el nombre como búsqueda y recalcular la línea; no editar por número a ciegas.

| Archivo | Línea | Símbolo |
|---|---:|---|
| [Sources/VozaKit/App/Localizer.swift](../../Sources/VozaKit/App/Localizer.swift) | 5 | `L` |
| [Sources/VozaKit/App/Localizer.swift](../../Sources/VozaKit/App/Localizer.swift) | 17 | `t` |
| [Sources/VozaKit/App/VozaApp.swift](../../Sources/VozaKit/App/VozaApp.swift) | 3 | `VozaApp` |
| [Sources/VozaKit/App/VozaApp.swift](../../Sources/VozaKit/App/VozaApp.swift) | 26 | `MenuBarLabel` |
| [Sources/VozaKit/App/VozaApp.swift](../../Sources/VozaKit/App/VozaApp.swift) | 43 | `AppDelegate` |
| [Sources/VozaKit/App/VozaApp.swift](../../Sources/VozaKit/App/VozaApp.swift) | 44 | `applicationDidFinishLaunching` |
| [Sources/VozaKit/Core/AudioRecorder.swift](../../Sources/VozaKit/Core/AudioRecorder.swift) | 4 | `AudioRecorderError` |
| [Sources/VozaKit/Core/AudioRecorder.swift](../../Sources/VozaKit/Core/AudioRecorder.swift) | 18 | `AudioRecorder` |
| [Sources/VozaKit/Core/AudioRecorder.swift](../../Sources/VozaKit/Core/AudioRecorder.swift) | 37 | `start` |
| [Sources/VozaKit/Core/AudioRecorder.swift](../../Sources/VozaKit/Core/AudioRecorder.swift) | 84 | `stop` |
| [Sources/VozaKit/Core/AudioRecorder.swift](../../Sources/VozaKit/Core/AudioRecorder.swift) | 102 | `cancel` |
| [Sources/VozaKit/Core/AudioRecorder.swift](../../Sources/VozaKit/Core/AudioRecorder.swift) | 121 | `enqueue` |
| [Sources/VozaKit/Core/AudioRecorder.swift](../../Sources/VozaKit/Core/AudioRecorder.swift) | 147 | `finalizeWAVHeader` |
| [Sources/VozaKit/Core/AudioRecorder.swift](../../Sources/VozaKit/Core/AudioRecorder.swift) | 163 | `wavHeader` |
| [Sources/VozaKit/Core/AudioRecorder.swift](../../Sources/VozaKit/Core/AudioRecorder.swift) | 165 | `appendStr` |
| [Sources/VozaKit/Core/AudioRecorder.swift](../../Sources/VozaKit/Core/AudioRecorder.swift) | 166 | `appendU32` |
| [Sources/VozaKit/Core/AudioRecorder.swift](../../Sources/VozaKit/Core/AudioRecorder.swift) | 167 | `appendU16` |
| [Sources/VozaKit/Core/BrewInstaller.swift](../../Sources/VozaKit/Core/BrewInstaller.swift) | 7 | `BrewInstaller` |
| [Sources/VozaKit/Core/BrewInstaller.swift](../../Sources/VozaKit/Core/BrewInstaller.swift) | 13 | `brewPath` |
| [Sources/VozaKit/Core/BrewInstaller.swift](../../Sources/VozaKit/Core/BrewInstaller.swift) | 20 | `installEngine` |
| [Sources/VozaKit/Core/Cleaner.swift](../../Sources/VozaKit/Core/Cleaner.swift) | 12 | `Cleaner` |
| [Sources/VozaKit/Core/Cleaner.swift](../../Sources/VozaKit/Core/Cleaner.swift) | 17 | `CleaningOutcome` |
| [Sources/VozaKit/Core/Cleaner.swift](../../Sources/VozaKit/Core/Cleaner.swift) | 25 | `providerChain` |
| [Sources/VozaKit/Core/Cleaner.swift](../../Sources/VozaKit/Core/Cleaner.swift) | 34 | `clean` |
| [Sources/VozaKit/Core/Cleaner.swift](../../Sources/VozaKit/Core/Cleaner.swift) | 66 | `ollamaClean` |
| [Sources/VozaKit/Core/Cleaner.swift](../../Sources/VozaKit/Core/Cleaner.swift) | 85 | `OllamaResp` |
| [Sources/VozaKit/Core/Cleaner.swift](../../Sources/VozaKit/Core/Cleaner.swift) | 93 | `ChatResponse` |
| [Sources/VozaKit/Core/Cleaner.swift](../../Sources/VozaKit/Core/Cleaner.swift) | 94 | `Choice` |
| [Sources/VozaKit/Core/Cleaner.swift](../../Sources/VozaKit/Core/Cleaner.swift) | 98 | `openAIClean` |
| [Sources/VozaKit/Core/Cleaner.swift](../../Sources/VozaKit/Core/Cleaner.swift) | 126 | `anthropicClean` |
| [Sources/VozaKit/Core/Cleaner.swift](../../Sources/VozaKit/Core/Cleaner.swift) | 143 | `AnthropicResp` |
| [Sources/VozaKit/Core/Cleaner.swift](../../Sources/VozaKit/Core/Cleaner.swift) | 144 | `Block` |
| [Sources/VozaKit/Core/Config.swift](../../Sources/VozaKit/Core/Config.swift) | 6 | `Config` |
| [Sources/VozaKit/Core/Config.swift](../../Sources/VozaKit/Core/Config.swift) | 45 | `reload` |
| [Sources/VozaKit/Core/Config.swift](../../Sources/VozaKit/Core/Config.swift) | 47 | `load` |
| [Sources/VozaKit/Core/Config.swift](../../Sources/VozaKit/Core/Config.swift) | 93 | `setModel` |
| [Sources/VozaKit/Core/Config.swift](../../Sources/VozaKit/Core/Config.swift) | 94 | `setWhisperBinary` |
| [Sources/VozaKit/Core/Config.swift](../../Sources/VozaKit/Core/Config.swift) | 95 | `setModelsDirectory` |
| [Sources/VozaKit/Core/Config.swift](../../Sources/VozaKit/Core/Config.swift) | 96 | `setLogDirectory` |
| [Sources/VozaKit/Core/Config.swift](../../Sources/VozaKit/Core/Config.swift) | 97 | `setCleanupMode` |
| [Sources/VozaKit/Core/Config.swift](../../Sources/VozaKit/Core/Config.swift) | 98 | `setOllamaModel` |
| [Sources/VozaKit/Core/Config.swift](../../Sources/VozaKit/Core/Config.swift) | 99 | `setLanguage` |
| [Sources/VozaKit/Core/Config.swift](../../Sources/VozaKit/Core/Config.swift) | 100 | `setPlaySound` |
| [Sources/VozaKit/Core/Config.swift](../../Sources/VozaKit/Core/Config.swift) | 101 | `setGumroadPermalink` |
| [Sources/VozaKit/Core/Config.swift](../../Sources/VozaKit/Core/Config.swift) | 103 | `persist` |
| [Sources/VozaKit/Core/HotKeyManager.swift](../../Sources/VozaKit/Core/HotKeyManager.swift) | 7 | `HotKeyManager` |
| [Sources/VozaKit/Core/HotKeyManager.swift](../../Sources/VozaKit/Core/HotKeyManager.swift) | 20 | `start` |
| [Sources/VozaKit/Core/HotKeyManager.swift](../../Sources/VozaKit/Core/HotKeyManager.swift) | 28 | `installTap` |
| [Sources/VozaKit/Core/HotKeyManager.swift](../../Sources/VozaKit/Core/HotKeyManager.swift) | 61 | `ensureTapAlive` |
| [Sources/VozaKit/Core/HotKeyManager.swift](../../Sources/VozaKit/Core/HotKeyManager.swift) | 71 | `handle` |
| [Sources/VozaKit/Core/HotKeyManager.swift](../../Sources/VozaKit/Core/HotKeyManager.swift) | 87 | `handleFlagsChanged` |
| [Sources/VozaKit/Core/HotKeyManager.swift](../../Sources/VozaKit/Core/HotKeyManager.swift) | 108 | `stop` |
| [Sources/VozaKit/Core/LicenseManager.swift](../../Sources/VozaKit/Core/LicenseManager.swift) | 12 | `LicenseManager` |
| [Sources/VozaKit/Core/LicenseManager.swift](../../Sources/VozaKit/Core/LicenseManager.swift) | 17 | `State` |
| [Sources/VozaKit/Core/LicenseManager.swift](../../Sources/VozaKit/Core/LicenseManager.swift) | 31 | `LicenseCache` |
| [Sources/VozaKit/Core/LicenseManager.swift](../../Sources/VozaKit/Core/LicenseManager.swift) | 37 | `VerifyResponse` |
| [Sources/VozaKit/Core/LicenseManager.swift](../../Sources/VozaKit/Core/LicenseManager.swift) | 40 | `Purchase` |
| [Sources/VozaKit/Core/LicenseManager.swift](../../Sources/VozaKit/Core/LicenseManager.swift) | 62 | `refreshIfNeeded` |
| [Sources/VozaKit/Core/LicenseManager.swift](../../Sources/VozaKit/Core/LicenseManager.swift) | 74 | `activate` |
| [Sources/VozaKit/Core/LicenseManager.swift](../../Sources/VozaKit/Core/LicenseManager.swift) | 98 | `computeTrialState` |
| [Sources/VozaKit/Core/LicenseManager.swift](../../Sources/VozaKit/Core/LicenseManager.swift) | 116 | `VerificationPurpose` |
| [Sources/VozaKit/Core/LicenseManager.swift](../../Sources/VozaKit/Core/LicenseManager.swift) | 121 | `verifyRequest` |
| [Sources/VozaKit/Core/LicenseManager.swift](../../Sources/VozaKit/Core/LicenseManager.swift) | 142 | `reverify` |
| [Sources/VozaKit/Core/LicenseManager.swift](../../Sources/VozaKit/Core/LicenseManager.swift) | 160 | `readCache` |
| [Sources/VozaKit/Core/LicenseManager.swift](../../Sources/VozaKit/Core/LicenseManager.swift) | 165 | `writeCache` |
| [Sources/VozaKit/Core/LicenseManager.swift](../../Sources/VozaKit/Core/LicenseManager.swift) | 172 | `clearCache` |
| [Sources/VozaKit/Core/ModelManager.swift](../../Sources/VozaKit/Core/ModelManager.swift) | 4 | `WhisperModel` |
| [Sources/VozaKit/Core/ModelManager.swift](../../Sources/VozaKit/Core/ModelManager.swift) | 16 | `WhisperCatalog` |
| [Sources/VozaKit/Core/ModelManager.swift](../../Sources/VozaKit/Core/ModelManager.swift) | 31 | `byId` |
| [Sources/VozaKit/Core/ModelManager.swift](../../Sources/VozaKit/Core/ModelManager.swift) | 35 | `HardwareProfile` |
| [Sources/VozaKit/Core/ModelManager.swift](../../Sources/VozaKit/Core/ModelManager.swift) | 53 | `recommendedModel` |
| [Sources/VozaKit/Core/ModelManager.swift](../../Sources/VozaKit/Core/ModelManager.swift) | 65 | `ModelManager` |
| [Sources/VozaKit/Core/ModelManager.swift](../../Sources/VozaKit/Core/ModelManager.swift) | 82 | `localPath` |
| [Sources/VozaKit/Core/ModelManager.swift](../../Sources/VozaKit/Core/ModelManager.swift) | 86 | `fileSize` |
| [Sources/VozaKit/Core/ModelManager.swift](../../Sources/VozaKit/Core/ModelManager.swift) | 92 | `isDownloaded` |
| [Sources/VozaKit/Core/ModelManager.swift](../../Sources/VozaKit/Core/ModelManager.swift) | 96 | `downloadedModels` |
| [Sources/VozaKit/Core/ModelManager.swift](../../Sources/VozaKit/Core/ModelManager.swift) | 103 | `resolvedModel` |
| [Sources/VozaKit/Core/ModelManager.swift](../../Sources/VozaKit/Core/ModelManager.swift) | 110 | `resolvedModelPath` |
| [Sources/VozaKit/Core/ModelManager.swift](../../Sources/VozaKit/Core/ModelManager.swift) | 115 | `download` |
| [Sources/VozaKit/Core/ModelManager.swift](../../Sources/VozaKit/Core/ModelManager.swift) | 205 | `sha256` |
| [Sources/VozaKit/Core/Paster.swift](../../Sources/VozaKit/Core/Paster.swift) | 6 | `Paster` |
| [Sources/VozaKit/Core/Paster.swift](../../Sources/VozaKit/Core/Paster.swift) | 12 | `paste` |
| [Sources/VozaKit/Core/Paster.swift](../../Sources/VozaKit/Core/Paster.swift) | 44 | `sendCmdV` |
| [Sources/VozaKit/Core/PerformanceMonitor.swift](../../Sources/VozaKit/Core/PerformanceMonitor.swift) | 5 | `PerformanceMonitor` |
| [Sources/VozaKit/Core/PerformanceMonitor.swift](../../Sources/VozaKit/Core/PerformanceMonitor.swift) | 8 | `Suggestion` |
| [Sources/VozaKit/Core/PerformanceMonitor.swift](../../Sources/VozaKit/Core/PerformanceMonitor.swift) | 9 | `Direction` |
| [Sources/VozaKit/Core/PerformanceMonitor.swift](../../Sources/VozaKit/Core/PerformanceMonitor.swift) | 15 | `Records` |
| [Sources/VozaKit/Core/PerformanceMonitor.swift](../../Sources/VozaKit/Core/PerformanceMonitor.swift) | 31 | `record` |
| [Sources/VozaKit/Core/PerformanceMonitor.swift](../../Sources/VozaKit/Core/PerformanceMonitor.swift) | 41 | `medianRTF` |
| [Sources/VozaKit/Core/PerformanceMonitor.swift](../../Sources/VozaKit/Core/PerformanceMonitor.swift) | 51 | `speedLabel` |
| [Sources/VozaKit/Core/PerformanceMonitor.swift](../../Sources/VozaKit/Core/PerformanceMonitor.swift) | 57 | `suggestion` |
| [Sources/VozaKit/Core/PerformanceMonitor.swift](../../Sources/VozaKit/Core/PerformanceMonitor.swift) | 82 | `dismiss` |
| [Sources/VozaKit/Core/PerformanceMonitor.swift](../../Sources/VozaKit/Core/PerformanceMonitor.swift) | 88 | `save` |
| [Sources/VozaKit/Core/PerformanceMonitor.swift](../../Sources/VozaKit/Core/PerformanceMonitor.swift) | 94 | `_test_setSamples` |
| [Sources/VozaKit/Core/PerformanceMonitor.swift](../../Sources/VozaKit/Core/PerformanceMonitor.swift) | 99 | `_test_clear` |
| [Sources/VozaKit/Core/Permissions.swift](../../Sources/VozaKit/Core/Permissions.swift) | 6 | `Permissions` |
| [Sources/VozaKit/Core/Permissions.swift](../../Sources/VozaKit/Core/Permissions.swift) | 26 | `requestMicrophone` |
| [Sources/VozaKit/Core/Permissions.swift](../../Sources/VozaKit/Core/Permissions.swift) | 36 | `openAccessibilitySettings` |
| [Sources/VozaKit/Core/Permissions.swift](../../Sources/VozaKit/Core/Permissions.swift) | 41 | `openMicrophoneSettings` |
| [Sources/VozaKit/Core/Permissions.swift](../../Sources/VozaKit/Core/Permissions.swift) | 46 | `openInputMonitoringSettings` |
| [Sources/VozaKit/Core/ReadinessChecker.swift](../../Sources/VozaKit/Core/ReadinessChecker.swift) | 4 | `Readiness` |
| [Sources/VozaKit/Core/ReadinessChecker.swift](../../Sources/VozaKit/Core/ReadinessChecker.swift) | 15 | `ReadinessChecker` |
| [Sources/VozaKit/Core/ReadinessChecker.swift](../../Sources/VozaKit/Core/ReadinessChecker.swift) | 16 | `check` |
| [Sources/VozaKit/Core/ReadinessChecker.swift](../../Sources/VozaKit/Core/ReadinessChecker.swift) | 31 | `requiredFreeMB` |
| [Sources/VozaKit/Core/ReadinessChecker.swift](../../Sources/VozaKit/Core/ReadinessChecker.swift) | 35 | `freeDiskMB` |
| [Sources/VozaKit/Core/Transcriber.swift](../../Sources/VozaKit/Core/Transcriber.swift) | 3 | `TranscriptionError` |
| [Sources/VozaKit/Core/Transcriber.swift](../../Sources/VozaKit/Core/Transcriber.swift) | 23 | `Transcriber` |
| [Sources/VozaKit/Core/Transcriber.swift](../../Sources/VozaKit/Core/Transcriber.swift) | 25 | `locateBinary` |
| [Sources/VozaKit/Core/Transcriber.swift](../../Sources/VozaKit/Core/Transcriber.swift) | 38 | `transcribe` |
| [Sources/VozaKit/Core/Transcriber.swift](../../Sources/VozaKit/Core/Transcriber.swift) | 72 | `isNonSpeechMarker` |
| [Sources/VozaKit/Core/Transcriber.swift](../../Sources/VozaKit/Core/Transcriber.swift) | 81 | `runProcess` |
| [Sources/VozaKit/Core/TranscriptStore.swift](../../Sources/VozaKit/Core/TranscriptStore.swift) | 3 | `TranscriptEntry` |
| [Sources/VozaKit/Core/TranscriptStore.swift](../../Sources/VozaKit/Core/TranscriptStore.swift) | 22 | `TranscriptStore` |
| [Sources/VozaKit/Core/TranscriptStore.swift](../../Sources/VozaKit/Core/TranscriptStore.swift) | 33 | `add` |
| [Sources/VozaKit/Core/TranscriptStore.swift](../../Sources/VozaKit/Core/TranscriptStore.swift) | 50 | `parseEntries` |
| [Sources/VozaKit/Core/TranscriptStore.swift](../../Sources/VozaKit/Core/TranscriptStore.swift) | 69 | `appendToFile` |
| [Sources/VozaKit/Core/TranscriptStore.swift](../../Sources/VozaKit/Core/TranscriptStore.swift) | 88 | `loadRecent` |
| [Sources/VozaKit/State/AppState.swift](../../Sources/VozaKit/State/AppState.swift) | 5 | `VozaPhase` |
| [Sources/VozaKit/State/AppState.swift](../../Sources/VozaKit/State/AppState.swift) | 22 | `AppState` |
| [Sources/VozaKit/State/AppState.swift](../../Sources/VozaKit/State/AppState.swift) | 47 | `refresh` |
| [Sources/VozaKit/State/AppState.swift](../../Sources/VozaKit/State/AppState.swift) | 61 | `startDictation` |
| [Sources/VozaKit/State/AppState.swift](../../Sources/VozaKit/State/AppState.swift) | 88 | `stopDictation` |
| [Sources/VozaKit/State/AppState.swift](../../Sources/VozaKit/State/AppState.swift) | 108 | `pipeline` |
| [Sources/VozaKit/State/AppState.swift](../../Sources/VozaKit/State/AppState.swift) | 175 | `downloadModel` |
| [Sources/VozaKit/State/AppState.swift](../../Sources/VozaKit/State/AppState.swift) | 219 | `applySuggestion` |
| [Sources/VozaKit/State/AppState.swift](../../Sources/VozaKit/State/AppState.swift) | 232 | `dismissSuggestion` |
| [Sources/VozaKit/State/AppState.swift](../../Sources/VozaKit/State/AppState.swift) | 239 | `formatETA` |
| [Sources/VozaKit/State/AppState.swift](../../Sources/VozaKit/State/AppState.swift) | 246 | `copyToClipboard` |
| [Sources/VozaKit/State/AppState.swift](../../Sources/VozaKit/State/AppState.swift) | 252 | `openLogFolder` |
| [Sources/VozaKit/UI/OnboardingView.swift](../../Sources/VozaKit/UI/OnboardingView.swift) | 5 | `OnboardingView` |
| [Sources/VozaKit/UI/OnboardingView.swift](../../Sources/VozaKit/UI/OnboardingView.swift) | 90 | `refresh` |
| [Sources/VozaKit/UI/OnboardingView.swift](../../Sources/VozaKit/UI/OnboardingView.swift) | 98 | `stepRow` |
| [Sources/VozaKit/UI/PopoverView.swift](../../Sources/VozaKit/UI/PopoverView.swift) | 3 | `PopoverView` |
| [Sources/VozaKit/UI/PopoverView.swift](../../Sources/VozaKit/UI/PopoverView.swift) | 142 | `TranscriptRow` |
| [Sources/VozaKit/UI/SettingsView.swift](../../Sources/VozaKit/UI/SettingsView.swift) | 5 | `SettingsView` |
| [Sources/VozaKit/UI/SettingsView.swift](../../Sources/VozaKit/UI/SettingsView.swift) | 29 | `StatusView` |
| [Sources/VozaKit/UI/SettingsView.swift](../../Sources/VozaKit/UI/SettingsView.swift) | 58 | `refreshNow` |
| [Sources/VozaKit/UI/SettingsView.swift](../../Sources/VozaKit/UI/SettingsView.swift) | 63 | `refreshSoon` |
| [Sources/VozaKit/UI/SettingsView.swift](../../Sources/VozaKit/UI/SettingsView.swift) | 154 | `hero` |
| [Sources/VozaKit/UI/SettingsView.swift](../../Sources/VozaKit/UI/SettingsView.swift) | 191 | `chip` |
| [Sources/VozaKit/UI/SettingsView.swift](../../Sources/VozaKit/UI/SettingsView.swift) | 220 | `suggestionCard` |
| [Sources/VozaKit/UI/SettingsView.swift](../../Sources/VozaKit/UI/SettingsView.swift) | 293 | `DictationSettings` |
| [Sources/VozaKit/UI/SettingsView.swift](../../Sources/VozaKit/UI/SettingsView.swift) | 358 | `ModelSettings` |
| [Sources/VozaKit/UI/SettingsView.swift](../../Sources/VozaKit/UI/SettingsView.swift) | 402 | `modelRow` |
| [Sources/VozaKit/UI/SettingsView.swift](../../Sources/VozaKit/UI/SettingsView.swift) | 441 | `AdvancedSettings` |
| [Sources/VozaKit/UI/SettingsView.swift](../../Sources/VozaKit/UI/SettingsView.swift) | 485 | `LicenseSettings` |
| [Sources/VozaKit/UI/SettingsView.swift](../../Sources/VozaKit/UI/SettingsView.swift) | 554 | `AboutSettings` |
| [Sources/VozaKit/UI/Theme.swift](../../Sources/VozaKit/UI/Theme.swift) | 4 | `Theme` |
