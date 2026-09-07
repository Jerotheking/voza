# Voza — Documento Maestro de Especificaciones para Auditoría Externa

> **ADDENDUM (2026-09-06, auditoría externa v2 — Sprint 0 ejecutado).** La segunda
> pasada de auditoría externa (Voza_Auditoria_Integral_Roadmap_v2) levantó 14
> hallazgos P0. Los 14 fueron verificados contra el código (14/14 confirmados) y
> corregidos en el mismo ciclo. Resumen para el auditor:
> 1. **Idioma**: `resolvedLanguage` ya no deriva el idioma del habla del idioma de la UI — `auto` llega a whisper.cpp como `-l auto` (§3.1).
> 2. **Modelo default**: `small-q5_1` multilingüe (190,085,487 B, SHA-256 `ae85e4a9…`) agregado; `recommendedModel(language:)` nunca recomienda English-only para auto/es (§3.2).
> 3. **Atribución RTF**: `resolvedModel()` devuelve descriptor+path; PerformanceMonitor registra el modelo REALMENTE usado; el fallback se muestra en UI (§3.3).
> 4. **MainActor**: la transcripción corre en `Task.detached`; propiedad muerta `transcriber` eliminada (§3.4).
> 5. **Header WAV**: format code 3 (IEEE float) — y un bug más profundo que la auditoría no vio: literales `Int` sin tipo escribían campos de 8 bytes (header de 64). Ahora con tipos explícitos, exactamente 44 bytes; el smoke verifica que whisper-cli consume un WAV grabado por Voza (§3.5 y más allá).
> 6. **Permisos**: `inputMonitoringGranted` (CGPreflightListenEventAccess) agregado a Permissions/allGranted/Readiness/Status UI; el fallo del event tap se reporta, nunca es silencioso (§3.6).
> 7. **Licencia**: activación vs revalidación separadas (`increment_uses_count` false en reverify); refunded/disputed/chargebacked validados (§3.7).
> 8. **Frontera de privacidad**: cleanup `auto` = solo local, sin local→cloud implícito; la cadena de proveedores es pura y testeada; la UI ya no promete "Ollama → cloud" (§3.8).
> 9. **Historial**: marcador ✨ parseado correctamente (las entradas cleaned sobreviven al reload); el historial registra el estado real `applied`, no la intención (§3.9).
> 10. **Descargas**: `.part` se conserva en errores de red (resume real); 416 validado contra tamaño esperado; disk guard por modelo + margen (§3.10).
> 11. **Firma**: `--deep` eliminado de build.sh y release.sh (§3.11).
> 12. **Copy**: README/landing/prompt de mic actualizados — "el audio nunca sale de esta Mac", tamaños de modelo dinámicos, sin sobre-promesa de "100% local" (§3.14).
> 13. **Robustez**: marcadores no-speech de whisper (`[BLANK_AUDIO]`…) ya no se pegan como dictado.
> 14. **Verificación**: suite completa de smoke (57 checks, incluidos los nuevos de idioma/modelo/historial/privacidad/disco/WAV) en verde; E2E re-corrido con el modelo multilingüe + auto language → sample JFK transcrito perfecto.

**Versión del documento:** 1.0 · **Código auditado:** commit `0d55dc5` (rama `main`)
**Fecha:** 6 de septiembre de 2026 · **Contacto del proyecto:** vía GitHub (ver README)

> **Instrucciones para el auditor (IA sin acceso a la máquina):** este documento es
> autocontenido. Todo lo que necesitas para auditar el proyecto — técnico, producto,
> negocio, legal y estado real — está aquí. Cuando algo sea *claims del autor sin
> verificación posible por ti*, se marca explícitamente `[CLAIM]`. Puntos donde el
> auditor debería profundizar se marcan `⚠️ AUDITAR`. El código fuente completo está
> en el repo público (ver §16); este doc describe lo que contiene y por qué.

---

## 1. Qué es Voza (resumen ejecutivo)

Voza es una app de **dictado push-to-talk para macOS 14+** que corre **100% local**:

1. El usuario mantiene presionada **Option derecha** → la app graba el micrófono.
2. Al soltar, transcribe con **whisper.cpp** (acelerado por Metal) usando un modelo
   descargado y verificado con SHA-256.
3. Opcionalmente (**Control derecha**), un LLM "limpia" el texto: puntuación,
   mayúsculas, muletillas. Prioridad: Ollama local → API cloud → pegado plano.
4. El texto se **pega en la app activa** (Cmd+V sintético) y se restaura el
   portapapeles previo.
5. Cada transcripción se agrega a `~/Dictation/YYYY-MM.md` y el audio se **borra**
   inmediatamente después de transcribir.

**Promesas de producto (verificables en el código):** sin cuentas, sin telemetría,
el audio nunca sale de la Mac, el texto solo sale si el usuario configura una API
cloud de limpieza, código fuente MIT, binario pre-compilado de pago con licencia
Gumroad, interfaz bilingüe EN/ES.

---

## 2. Contexto de negocio (resumen del análisis de mercado)

Detalles completos con fuentes en `docs/market-analysis.md`. Datos clave:

- **Competidores**: Superwhisper ($249.99 lifetime, $8.49/mo), Wispr Flow ($15/mo,
  cloud), MacWhisper (€59–64), VoiceInk ($0 build / $25–49 binario), TypeWhisper,
  Handy, OpenWhispr (OSS gratis), Voibe ($99–149), Spokenly, Apple Dictation (gratis
  en Tahoe).
- **Nicho elegido**: usuarios que rechazan suscripciones y precios lifetime altos.
  Punto dulce probado del mercado one-time: **$25–39**.
- **Precio**: **$29 de lanzamiento → $39 regular**. Vía Gumroad (~10% comisión).
  Costo fijo: Apple Developer Program $99/año. Margen ~85%. Costo de inferencia por
  usuario: **$0** (todo local).
- **Distribución** (playbook VoiceInk): repo público MIT (marketing) + DMG firmado y
  notarizado de pago (Gumroad) + Homebrew cask.
- **Posicionamiento**: *"Dictate. It pastes itself. Pay once."* — 10% del precio de
  Superwhisper lifetime, 100% local, bilingüe EN/ES desde el día 1.

⚠️ AUDITAR: los precios de la competencia y las quejas de Reddit provienen de
investigación web de sept 2026 documentada en `docs/market-analysis.md`; el auditor
puede verificarlos contra las fuentes vivas.

---

## 3. Decisiones de producto y su justificación

| Decisión | Elección | Por qué |
|---|---|---|
| Plataforma | macOS 14+ (Sonoma) | `MenuBarExtra` con estilo `.window` requiere 13+; 14 da margen de APIs |
| Forma de app | Menu bar app (`LSUIElement`) | Dictado global: no debe vivir en el Dock |
| Hotkeys | Fijas: Option derecha = dictar, Control derecha = dictar+limpieza | Un solo modo general (scope decidido); keys derechas distinguibles por keyCode |
| Motor STT | whisper.cpp via binario de Homebrew | MIT, Metal, mantenimiento activo; evitar binario propio reduce superficie |
| Modelos | Catálogo de 7 (tiny.en → large-v3-turbo), descarga bajo demanda | No bundle de modelos: la app pesa <5 MB y el usuario elige |
| Limpieza IA | Ollama local por defecto, cloud opcional, plain como fallback | $0 de costo por usuario; privacidad; graceful degradation |
| Idioma UI | EN/ES inline con detección del sistema + override | Diferenciador: nadie más apunta al power user macOS hispano |
| Fuera de alcance v1 | Presets por app, vocabulario custom, hotkeys configurables | Simplicidad: "un buen modo general" |
| Monetización | Trial 14 días que nunca bloquea + licencia Gumroad offline-first | "It doesn't paste, you don't pay": el trial degrada a nag, no a paywall |

---

## 4. Arquitectura técnica

### 4.1 Estructura del paquete (SwiftPM puro, sin proyecto Xcode)

```
Voza (repo)
├── Package.swift            swift-tools 5.9, platform macOS 14
├── Sources/
│   ├── VozaKit/             Biblioteca con toda la lógica (importable por tests)
│   │   ├── Core/            11 tipos: pipeline + estado + persistencia
│   │   ├── App/             VozaApp (Scene SwiftUI) + Localizer (L)
│   │   ├── State/           AppState (ObservableObject central)
│   │   └── UI/              PopoverView, SettingsView, OnboardingView, Theme
│   ├── Voza/                main.swift (8 líneas): solo llama VozaApp.main()
│   └── VozaSmoke/           Suite de verificación executable (reemplaza XCTest)
├── Tests/VozaTests/         4 pruebas XCTest (requieren Xcode completo para correr)
├── packaging/               Info.plist, entitlements, cask de Homebrew
├── scripts/                 build.sh (app bundle), release.sh (sign+notarize+DMG)
├── design/                  landing.html, wireframes, icono SVG
└── docs/                    market-analysis.md, design-adaptive-ux.md, este doc
```

**Justificación VozaKit/Voza/VozaSmoke**: la librería separada existe porque
XCTest no está disponible en el toolchain de CommandLineTools (sin Xcode) y los
executable targets no exportan símbolos; `VozaSmoke` importa `@testable VozaKit`
y corre sin Xcode. ⚠️ AUDITAR: `Package.swift` declara `VozaTests` dependiendo de
`VozaKit` (correcto desde el commit de auditoría; antes dependía de `Voza`, lo cual
era un defecto).

### 4.2 Flujo de datos del pipeline (secuencia exacta)

```
CGEventTap (flagsChanged)
  → HotKeyManager.handleFlagsChanged (main actor)
  → AppState.startDictation(cleanup:)     [fases: idle → recording]
      AudioRecorder.start(): AVAudioEngine + tap 4096 frames
        → AVAudioConverter (hw → float32 16k mono)
        → bytes PCM a FileHandle (WAV con header placeholder de 44 bytes)
  → AppState.stopDictation()              [recording → transcribing]
      - descarta taps < 0.25 s
      - AudioRecorder.stop() escribe header WAV real (RIFF/PCM 32-bit float)
  → Transcriber.transcribe()              [proceso síncrono con timeout 120 s]
      whisper-cli -m <model> -f <wav> -nt -np -ml 1 -sow -l <lang> (+ -bs 1 si en)
  → PerformanceMonitor.record(rtf:)       (tiempo_transcripción / duración_audio)
  → DELETE del WAV (inmediato, antes de cleanup)  ← garantía de privacidad
  → si cleanup: Cleaner.clean()           [transcribing → cleaning]
      ollama → openai-compat → anthropic → texto plano
  → Paster.paste()                        [→ idle]
      guarda clipboard → escribe texto → Cmd+V sintético → restaura clipboard
      (solo si changeCount == countBefore+1: nadie más tocó el portapapeles)
  → TranscriptStore.add()                 ring de 50 en memoria + append a .md
```

### 4.3 Los 12 componentes de Core — por qué existen y qué garantizan

| Componente | Responsabilidad única | Garantías clave |
|---|---|---|
| `Config.swift` (141 l) | Config TOML simple en `~/.config/voza/config.toml` + `.env` | Setters explícitos que persisten; defaults sensatos; claves cloud por `.env` **o** variables de proceso |
| `AudioRecorder.swift` (171 l) | Captura → WAV 16k float32 mono | Sin dependencias externas; convierte cualquier sample rate de hardware; borra en `cancel()` |
| `Transcriber.swift` (88 l) | Ejecuta `whisper-cli` con timeout | Localiza binario en 3 rutas; errores localizados; mata proceso en timeout |
| `ModelManager.swift` (189 l) | Catálogo + descarga HF con SHA-256 + resume | Hash real obtenido de la API de HF (upstream solo publica SHA-1); borra `.part` en fallo; verifica tamaño Y hash |
| `HardwareProfile` (en ModelManager) | RAM vía `sysctl hw.memsize` → modelo recomendado | ≥30 GB → large-v3-turbo; <30 GB → small.en-q5_1 (q5_1: 190 MB, para Macs de 8 GB) |
| `Cleaner.swift` (130 l) | Cadena de limpieza con degradación | Prompt que preserva idioma/tono y prohíbe comentario; timeout 60–90 s; nunca lanza, siempre degrada |
| `Paster.swift` (54 l) | Paste + restauración de clipboard | Restauración condicionada a changeCount (no pisa copias ajenas) |
| `HotKeyManager.swift` (103 l) | Event tap global + watchdog 30 s | Right Option (58) / Right Control (54) por keyCode; **devuelve eventos unretained** (fix de leak, §8) |
| `TranscriptStore.swift` (95 l) | Ring memoria + log append-only | Escribe en cola serial; re-hidrata últimos 10 desde los logs de este y el mes previo |
| `LicenseManager.swift` (153 l) | Gumroad verify + cache offline + trial | Cache 0600; re-verifica cada 7 días; fallo de red NUNCA desactiva; solo "invalid" definitivo revoca |
| `PerformanceMonitor.swift` (103 l) | RTF medido → sugerencias | Mediana de ≥3 muestras; lighter si RTF>0.5; heavier si RTF<0.08 Y ≥32 GB; ventana de descarte 14 días |
| `ReadinessChecker.swift` (33 l) + `BrewInstaller.swift` (70 l) | Snapshot de salud + instalación de whisper.cpp vía brew | Alimenta Status home; descarga bloqueada <400 MB libres |

### 4.4 Capa de estado y UI

- **`AppState`** (237 l): único `ObservableObject` compartido; máquina de fases
  `idle → recording(cleanup) → transcribing → cleaning → idle | failed(msg)`.
  Arranca pipeline en Task; publica progreso/ETA de descarga; aplica sugerencias.
- **`VozaApp`** (60 l): `MenuBarExtra(.window)` + `Settings` scene; `AppDelegate`
  instala hotkeys, carga historial, refresca licencia.
- **Icono de menú por fase**: `mic` idle/failed · `mic.fill` rojo grabando ·
  `waveform` transcribiendo · `sparkles` limpiando.
- **`SettingsView`** (557 l): tabs en orden dictado por la spec de UX adaptativa:
  **Status** (home con veredicto y botones de arreglo) → Dictado → Modelos →
  Avanzado → Licencia → Acerca de.
- **`OnboardingView`** (115 l): 4 pasos (mic, accesibilidad, motor, modelo) que
  anticipan los prompts de macOS; si el usuario ya negó el mic, deep-link a
  System Settings (el sistema no re-pregunta).
- **`Theme.swift`** (11 l): tokens mínimos vivos (acento coral, radio, ancho).
  Colores rojo/verde de estado: deliberadamente los del sistema.

### 4.5 Convenciones transversales

- **Localización**: función `L.t("EN", es: "ES")` inline en cada call site; override
  en `UserDefaults "voza.language"`; auto por `AppleLanguages`. Sin archivos .strings.
- **Concurrencia**: Swift 6 estricto donde aplica; `@MainActor` en AppState/
  LicenseManager/BrewInstaller; cola serial en TranscriptStore; pipeline en Task.
- **Rutas**: config/modelos/licencia en `~/.config/voza/`; logs en `~/Dictation/`;
  WAV en `$TMPDIR`.

---

## 5. Modelo de datos

```
WhisperModel  { id, file, bytes, sha256 }   // catálogo hardcodeado de 7
TranscriptEntry { id: UUID, date, text, cleaned: Bool }
Readiness     { micGranted, accessibilityGranted, engineFound, modelAvailable,
                brewAvailable, freeDiskMB }  // + constante minimumDownloadMB = 400
Config (valores): model?, whisper_binary?, models_dir?, log_dir?,
                cleanup(auto|ollama|cloud|plain), ollama_model, language(auto|en|es),
                play_sound, gumroad_permalink
Env soportado: OPENAI_API_KEY, OPENAI_BASE_URL, ANTHROPIC_API_KEY, CLEANUP_MODEL, OLLAMA_MODEL
```

**Catálogo de modelos** (bytes y SHA-256 obtenidos de la API de HuggingFace,
`ggerganov/whisper.cpp`, verificado por el smoke test en formato):

| id | archivo | bytes |
|---|---|---|
| tiny.en | ggml-tiny.en.bin | 77,704,715 |
| base.en | ggml-base.en.bin | 147,964,211 |
| small.en-q5_1 | ggml-small.en-q5_1.bin | 190,098,681 |
| small.en | ggml-small.en.bin | 487,614,201 |
| small | ggml-small.bin | 487,601,967 |
| medium | ggml-medium.bin | 1,533,763,059 |
| large-v3-turbo | ggml-large-v3-turbo.bin | 1,624,555,275 |

⚠️ AUDITAR: recomendar re-verificar los 7 hashes contra HF al momento de la
auditoría (smoke test valida formato, no coincidencia remota).

---

## 6. Seguridad y privacidad (claims verificables en código)

| Claim | Dónde se cumple |
|---|---|
| Audio nunca sale de la Mac | No existe código de red en AudioRecorder; WAV se borra tras transcribir (`AppState.pipeline`, paso 1) |
| STT 100% local | Transcriber solo ejecuta binario local |
| Texto solo sale si el usuario configura cloud | Cleaner solo llama red con `OPENAI_API_KEY`/`ANTHROPIC_API_KEY` presentes; modo Ollama es 127.0.0.1 |
| Sin telemetría | No hay Analytics, ni posters, ni endpoints de métricas en todo el repo |
| Sin cuentas | La identidad solo aparece si el usuario activa licencia (email que devuelve Gumroad, cacheado local) |
| License cache protegida | `chmod 600` en `~/.config/voza/license.json` |
| Descarga verificada | SHA-256 + tamaño exacto antes de mover `.part` a definitivo |

⚠️ AUDITAR (superficie de riesgo conocida, honesta):
1. El evento tap es **listen-only** y devuelve eventos sin modificar — no es
   keylogger (no persiste teclas), pero el permiso de Input Monitoring es el mismo
   que usaría uno. El README debe explicar esto al usuario.
2. `Paster` escribe en el portapapeles ~330 ms; un sniffer de clipboard podría leer
   el texto en esa ventana (inherente a cualquier dictado por paste).
3. `Config` parsea TOML sin librería: acepta el subconjunto que la app escribe.
   Malformed input degrada a defaults, no crashea.
4. Los prompts del LLM de limpieza no son injection-hardened (el texto dictado va
   como user message; el system prompt prohíbe comentario — aceptable porque el
   resultado solo se pega en la app del usuario).

---

## 7. Verificación y calidad (estado real)

- **`VozaSmoke`** (122 l): 16 checks sin Xcode — integridad del catálogo (hash
  format, tamaños plausibles, unicidad), preset de hardware, localizador, valores
  resueltos de Config, directorio de logs escribible, **roundtrip real de micrófono
  si hay permiso** (graba 0.6 s, valida header RIFF y payload), lógica completa del
  PerformanceMonitor, formato de ETA, snapshot de readiness.
- **Modo E2E**: `swift run VozaSmoke e2e <wav>` descarga small.en-q5_1, verifica
  SHA-256, transcribe el sample y valida plausibilidad. **Último resultado real
  [CLAIM del autor, replicable]:** transcripción exacta de `jfk.wav` con puntuación
  perfecta, tras el commit de auditoría.
- **`VozaTests`** (XCTest, 4 tests): catálogo, hardware, localizador, escritura/lectura
  del log. Requieren Xcode completo (no corren en CommandLineTools) — conocida deuda.
- **Lo que NINGÚN test automático cubre hoy** ⚠️ AUDITAR: paste real en apps
  reales (el Paster es puro side-effect de sistema), mashing de hotkeys, getters
  de permisos reales, restauración de clipboard con contenido RTF/fileURL, latencia
  percibida.

---

## 8. Auditoría interna ya realizada (hallazgos y resolución)

El autor completó una auditoría línea-por-línea (2,728 → 2,675 líneas) con estos
hallazgos, **todos resueltos** en commit `0d55dc5`:

| # | Hallazgo | Severidad | Resolución |
|---|---|---|---|
| 1 | `HotKeyManager` retenía cada CGEvent del tap (`passRetained`) → leak por tecla | **Alta** | `passUnretained` (tap listen-only nunca consume) |
| 2 | `Config.persist()` escribía `gumroad_permalink` sin comillas → TOML inválido | Media | Comillas agregadas |
| 3 | Redictar tras `.failed` bloqueado por guard redundante | Media | Guard simplificado (`!phase.isBusy`) |
| 4 | Onboarding: negar micrófono = callejón (sistema no re-pregunta) | Media | Deep-link a System Settings como fallback |
| 5 | Launch-at-login con estado inicial falso (`@State false`) | Baja | Lee `SMAppService.mainApp.status` real |
| 6 | Toggle decorativo deshabilitado en Settings (feature falsa) | Baja | Eliminado |
| 7 | Código muerto: `knownBrewPaths`, `AudioRecorder.inputFormat`, `Theme.recordingRed/.success`, `TranscriptEntry: Codable`, `OnboardingView.closeWindow()` | Baja | Eliminados con verificación de uso |
| 8 | `VozaTests` dependía del target equivocado (`Voza` en vez de `VozaKit`) | Baja | Corregido en este mismo ciclo |
| 9 | `Info.plist` decía macOS 13.0 mientras Package.swift exige 14 | Baja | Alineado a 14.0 |
| 10 | Cask de Homebrew congelado en 0.2.0 | Baja | Actualizado a 0.3.0 |

Símbolos sospechosos que **sobrevivieron con prueba de uso**: `machineLabel` (chip
del Status home), `AudioRecorder.cancel()` (taps cortos), `sendCmdV` público,
`Readiness.minimumDownloadMB` (guard de descarga).

---

## 9. Empaquetado y distribución

- **`build.sh`**: `swift build` → bundle `Voza.app` (Info.plist, icono .icns
  generado del SVG vía script, firma ad-hoc). Salida: `build/Voza.app`.
- **`release.sh`** (producción): Developer ID + hardened runtime + entitlements →
  `codesign --verify --strict` → zip → `notarytool submit --wait` → `stapler` →
  DMG UDZO → notarización del DMG. Requiere `VOZA_SIGNING_ID` y
  `VOZA_KEYCHAIN_PROFILE`.
- **Entitlements**: sandbox **off** (necesario para event tap + paste global —
  compensación consciente), audio-input on, apple-events on.
- **Cask** (`packaging/voza.rb`): template listo; requiere SHA-256 real del DMG en
  cada release (`sha256 :no_check` es placeholder **a reemplazar**). ⚠️ AUDITAR.
- **Info.plist**: `LSUIElement`, `NSMicrophoneUsageDescription` y
  `NSAppleEventsUsageDescription` bilingües. Nota: el flujo usa CGEvent (Input
  Monitoring/Accesibilidad), no AppleEvents; la key existe por si el paste sintético
  lo dispara. ⚠️ AUDITAR si sobra o falta `NSAccessibilityUsageDescription`
  (macOS no la requiere para AXIsProcessTrusted).

**Estado de bloqueo comercial [CLAIM]:** falta inscripción al Apple Developer
Program ($99/año) del autor para firmar/notarizar; sin eso la distribución del
binario requiere right-click→Open (Gatekeeper).

---

## 10. Licensing y monetización (lógica completa)

- **Fuente**: MIT en todo el repo — compilarlo tú mismo = sin licencia, para siempre.
- **Binario**: trial 14 días (fecha de inicio en `UserDefaults "voza.trialStart"`).
  Trial vencido: **la app sigue funcionando**; solo persiste un recordatorio en el
  popover y el tab de licencia. Activación: verify contra `api.gumroad.com/v2/
  licenses/verify` con `increment_uses_count=true`; success → cache local (key,
  email, lastVerified); re-verificación silenciosa cada 7 días; 5xx o error de red
  = gracia offline; 4xx con `success:false` = revoca cache y vuelve a trial.
- **Permalink de producto**: configurable (`gumroad_permalink`, default "voza") —
  el enlace de compra es `https://jerotherey.gumroad.com/l/<permalink>`.
- ⚠️ AUDITAR: el default "voza" apunta a un producto Gumroad que **aún no existe**
  [CLAIM]; hasta que exista, activar licencia fallará con mensaje de red.

---

## 11. Diseño y UX (Fase 0 + pulido adaptativo)

- **Sistema visual**: dark-first, materiales del sistema (`.quinary`), acento coral
  `rgb(0.98, 0.45, 0.28)`, rojo universal para grabando, SF Pro, radios 10 pt,
  popover 320 pt. Tokens en `Theme.swift`; specs completas en
  `docs/design-adaptive-ux.md` (principios, umbrales RTF, copy EN/ES).
- **Principio rector**: *zero-config* — la instalación fresca llega a dictar sin
  ninguna decisión; Settings **explica** lo elegido, no exige elegir.
- **Status home**: veredicto único con prioridad estricta (disco → mic → accesibilidad
  → motor → modelo → sugerencia → listo), cada problema con un botón de arreglo.
- **Auto-ajuste por medición**: sugerencias de modelo basadas en RTF real medido
  (no en RAM), con histéresis (≥3 muestras, mediana) y ventana de descarte de 14 días.
- **Assets**: wireframes navegables (`design/wireframes/wireframes.html`), landing
  bilingüe con tabla comparativa de precios (`design/landing.html`), icono SVG con
  pipeline a .icns (`scripts/make-icons.sh`).

---

## 12. Roadmap

- **v0.3.0 (actual)**: núcleo completo + pulido adaptativo + auditoría interna.
- **v1.0 (pre-lanzamiento)**: firma/notarización reales (bloqueado por Apple
  Developer Program), QA hostil manual (paste en apps reales, mashing, red
  interrumpida), README público, repo público.
- **v1.1**: overlay flotante de grabación (wireframe listo), hotkeys configurables.
- **Fase 2**: motor Parakeet TDT (brew ya distribuye `parakeet-cli`), presets por
  app (hoy fuera de alcance por decisión de producto), command dictation.

---

## 13. Métricas del proyecto (hecho verificable con el repo)

- **Código**: 2,675 líneas Swift en 23 archivos; mayor archivo SettingsView (557 l).
- **Historial**: 4 commits limpios (v0.1 núcleo → Fase B comercial → pulido UX →
  auditoría). Sin push a remoto aún [CLAIM].
- **Tests**: 16 checks de smoke (corren sin Xcode) + 4 XCTest (requieren Xcode).

---

## 14. Riesgos declarados (los que el autor reconoce)

| Riesgo | Severidad | Mitigación actual |
|---|---|---|
| Apple mete limpieza IA al dictado de sistema (Tahoe ya dicta on-device) | Alta | Subir de nivel: presets, multi-motor (Parakeet), nicho bilingüe |
| Dependencia de Homebrew para el motor (usuario sin brew no puede instalar in-app) | Media | Detección + instrucciones; futuro: bundle del binario |
| XCTest muerto en CI sin Xcode | Media | VozaSmoke como sustituto; falta CI real ⚠️ AUDITAR |
| Event tap puede ser deshabilitado por el SO | Media | Watchdog de 30 s re-instala |
| Producto Gumroad inexistente aún | Media | Bloquea solo la activación de licencias, no el uso |
| Un solo maintainer | — | Riesgo estructural aceptado, igual que toda la competencia del nicho |

---

## 15. Qué debería auditar la IA revisora (checklist sugerido)

1. **Pipeline de audio**: header WAV correcto para float32 (byte rate, block align,
   bits=32) — leer `finalizeWAVHeader` y confirmar aritmética.
2. **Conversión de audio**: el input block de `AVAudioConverter` devuelve el mismo
   buffer una vez y `.noDataNow` después — validar que no se pierden ni duplican
   frames al final de cada buffer.
3. **Threading del tap**: callback en hilo del run loop → dispatch a main con
   `MainActor.assumeIsolated` — validar la garantía de aislamiento.
4. **Descarga**: manejo de 200/206/416, resume con Range, truncado en 200, cleanup
   de `.part` — buscar edge cases (red caída a mitad, hash mismatch).
5. **Restauración de clipboard**: semántica de changeCount; ¿qué pasa si el usuario
   copia algo DURANTE los 330 ms de la ventana?
6. **LicenseManager**: estados y transiciones; ¿puede un MITM falsificar success?
   (HTTPS sí; ¿validación de la respuesta suficientemente estricta?)
7. **Config**: el parser TOML mínimo frente a inputs hostiles (valores con `=`,
   comillas internas, BOM).
8. **Coherencia producto↔código**: cada promesa de §1 y §6 contra el código real.
9. **Coherencia doc↔código**: este documento contra los archivos del repo.
10. **Costos de operación**: estimar mantenimiento real (1 dev, modelo de negocio
    one-time → ingresos puntuales) — desafío honesto al plan de negocio.

---

## 16. Índice de fuentes de verdad (mapa doc↔archivo)

| Tema | Archivo canónico |
|---|---|
| Este documento | `docs/AUDIT-SPEC.md` |
| Análisis de mercado/precios con fuentes | `docs/market-analysis.md` |
| Spec de UX adaptativa (principios, umbrales, copy) | `docs/design-adaptive-ux.md` |
| Instalación/permisos/modelos para usuarios | `README.md` |
| Código | `Sources/VozaKit/**` (+ `Sources/Voza`, `Sources/VozaSmoke`) |
| Empaquetado/release | `build.sh`, `scripts/release.sh`, `packaging/*` |
| Diseño | `design/*` |
| Verificación | `swift run VozaSmoke` (+ `e2e <wav>`), `Tests/VozaTests` |
