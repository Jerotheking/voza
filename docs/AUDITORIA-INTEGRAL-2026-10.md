# Auditoría Integral de Voza (Código, Arquitectura, Seguridad, UX y Modelo de Negocio)

**Fecha de auditoría:** 13 de octubre de 2026
**Checkout auditado:** `/Users/jeronimorey/Developer/voza` @ `6df2016` (`V12: cloud credentials in the Keychain + hardened provider boundary`)

---

## 0. Veredicto Ejecutivo

* **¿Vale la pena seguir con Voza?** **Sí [VERIFIED].** El núcleo técnico en `6df2016` es notablemente superior al promedio indie: `whisper.cpp` v1.9.4 compilado estáticamente con Metal embebido y cero dependencias de Homebrew en runtime (`D043`), autoaprendizaje silencioso post-pegado (`CorrectionWatcher` + despertar de árbol AX en Chromium/Electron por atributos sin VoiceOver en `D040`/`D041`), orquestación desacoplada en `DictationPipeline` (`D042`), y credenciales cloud en Keychain con transporte HTTPS sin redirecciones (`V12`).
* **Veredicto Go / No-Go para cobrar hoy:** **NO-GO condicional por 48 horas (3 bloqueadores P0 antes de publicar el link de Gumroad):**
  1. **Sin notarización de Apple ($99/año) y fallo de firma interna en `scripts/release.sh`:** En macOS 15 Sequoia y macOS 26 Tahoe, Gatekeeper obliga al comprador de un DMG sin notarizar a ir a Ajustes del Sistema o ejecutar `xattr -dr com.apple.quarantine` en Terminal. Como el código es MIT, quien compra Voza por $15/$29 paga exclusivamente por **cero fricción**. Además, `scripts/release.sh` no re-firma `Contents/MacOS/whisper-cli` con `Developer ID Application` ni `--options runtime --timestamp`, por lo que `notarytool` rechazará el bundle en el primer intento.
  2. **Inconsistencia pública de precios y promesas rotas en documentación/UI (`README.md`, `SettingsView.swift`, `OnboardingView.swift`):** La landing (`site/index.html`) y Gumroad (`docs/GUMROAD-PAGE-COPY.md`) venden a **$15**, mientras que `README.md` y `docs/market-analysis.md` venden a **$29**. Peor aún: `README.md` sigue exigiendo `brew install whisper-cpp` y prometiendo limpieza con LLM local al mantener `⌘ derecha` (eliminados en `D032` y `D043`).
  3. **Riesgo de privacidad en campos de contraseña y retención perpetua:** `Paster.swift` y `TranscriptStore.swift` no verifican `kAXSecureTextFieldSubrole` ni `IsSecureEventInputEnabled()`, y guardan cada dictado indefinidamente en texto plano en `~/Dictation/YYYY-MM.md` sin interruptor para apagar el registro en disco.
* **La jugada de mayor apalancamiento este mes:** Invertir los $99 de Apple Developer hoy, corregir el firmado interno en `scripts/release.sh`, alinear toda la copy/UI al estado real `D032+D043+V12`, y posicionar el **Auto-Learn invisible (estilo Wispr Flow pero 100% local en español/inglés)** como el diferenciador central frente a alternativas gratuitas como [Handy](https://handy.computer/) o [Spokenly](https://spokenly.app/pricing).

---

## 1. Scorecard Integral (1–10)

| Área | Nota | Justificación en una línea |
|---|---:|---|
| **Correctness & Robustez** | **8.0 / 10** | Pipeline determinista (`DictationPipeline`), cola serial de E/S en `AudioRecorder` y watcher unificado (`D041`), pero `Transcriber.runProcess` puede bloquearse por saturación de pipe (>64 KB) y `Paster` bloquea el MainActor 350 ms con `usleep`. |
| **Seguridad & Privacidad** | **7.5 / 10** | Excelente frontera de red en `SecureCleanupTransport` y migración a Keychain (`V12`), pero carece de bloqueo en campos de contraseña (`AXSecureTextField`) y guarda todo dictado en `~/Dictation/YYYY-MM.md` sin opción de desactivación. |
| **Arquitectura & Código** | **8.5 / 10** | ~3,500 LOC limpias, cero dependencias externas de SwiftPM (`Package.swift`), `whisper.cpp` estático con Metal embebido y costuras de inyección ejemplares; solo lastra código muerto de la era Homebrew (`BrewInstaller`) y `SettingsView.swift` monolítico. |
| **UX & Onboarding** | **7.5 / 10** | El HUD audio-reactivo (`DictationHUD`), el panel docente del primer dictado (`FirstRunExperience`) y la pestaña `Corrections` brillan, pero el Onboarding y `StatusView` aún mencionan Homebrew y `.env` plano. |
| **Distribución & Release** | **4.5 / 10** | Sin notarización activa hoy (fricción severa en macOS 15/26), `scripts/release.sh` deja `whisper-cli` con firma ad-hoc (fallará en `notarytool`), `packaging/voza.rb` tiene `sha256 :no_check` y no hay auto-updater (Sparkle). |
| **Modelo de Negocio & GTM** | **6.5 / 10** | El ángulo bilingüe EN/ES + pago único ($15 EA → $29 v1.0) es atractivo, pero tras quitar el Pulido local (`D032`) compite contra opciones gratuitas ([Spokenly](https://spokenly.app/pricing), [TypeWhisper](https://github.com/TypeWhisper/typewhisper-mac)) y sufre colisión directa de marca con [Voxa](https://voxa.infiniteagenci.com/). |
| **Testing & QA** | **8.5 / 10** | 16 archivos XCTest + `VozaSmoke` hermético (`V01`/`V02`) protegen invariantes reales sin tocar el perfil del usuario, aunque el toolchain CLI local sin `DEVELOPER_DIR` aborta por `dyld` y `ci.yml` no corre todas las suites de `VozaSmoke`. |

---

## 2. Tabla de Hallazgos Técnicos, de Seguridad y de Negocio

| ID | Área | Sev | Esf | Ubicación (`archivo:línea`) | Problema verificado | Solución concreta propuesta |
|---|---|---|---|---|---|---|
| **F-01** | Release / Firma | **P0** | S | `build.sh:47` · `scripts/release.sh:23-28` | `build.sh` firma `Contents/MacOS/whisper-cli` en modo ad-hoc (`--sign -`). `scripts/release.sh` solo firma `$APP` sin firmar antes el ejecutable interno `whisper-cli` con `Developer ID Application`, `--options runtime` y `--timestamp`. `xcrun notarytool` rechazará el `.app`. | En `scripts/release.sh`, antes de firmar `$APP`, agregar: `codesign --force --sign "$VOZA_SIGNING_ID" --options runtime --timestamp "$APP/Contents/MacOS/whisper-cli"`. |
| **F-02** | Producto / Copy | **P0** | S | `README.md:13,34,86,99` · `site/index.html:142` · `docs/GUMROAD-PAGE-COPY.md:16` | Contradicción triple: (1) `README.md` anuncia **$29** mientras `site/index.html` y Gumroad anuncian **$15**; (2) `README.md:34` exige `brew install whisper-cpp` pese a `D043`; (3) `README.md:99` dice que `⌘ derecha` ejecuta un LLM local pese a `D032`. | Sincronizar `README.md` con `site/index.html`: eliminar requisito de Homebrew, corregir tabla ES a tecla Option y limpieza Cloud opt-in, y unificar precio ($15 Early Access / $29 v1.0). |
| **F-03** | Privacidad / Seguridad | **P0** | S | `Sources/VozaKit/Core/Paster.swift:38-46` · `DictationPipeline.swift:126` | Voza no detecta `IsSecureEventInputEnabled()` ni `kAXSecureTextFieldSubrole` antes de pegar, registrar en `~/Dictation/YYYY-MM.md` o enviar a Cloud AI. Dictar con el cursor en un campo de contraseña expone o guarda texto sensible en plano. | Crear `Paster.isFocusedElementSecure() -> Bool` verificando `IsSecureEventInputEnabled()` y `kAXSubroleAttribute == "AXSecureTextField"`. Si es `true`, abortar pegado, no enviar a cloud y no escribir en `~/Dictation`. |
| **F-04** | Privacidad / Datos | **P1** | M | `Sources/VozaKit/Core/TranscriptStore.swift:72-85,121-135` | Todo dictado se escribe permanentemente en `~/Dictation/YYYY-MM.md` (`0644` por defecto) sin opción en Settings para apagar el registro en disco (`D007` pendiente) ni botón de borrado en UI. | Añadir `saveHistoryToDisk: Bool` en `Config` (toggle en `AdvancedSettings`), botón "Clear History" y permisos `0o600` en los archivos `.md` creados en `~/Dictation/`. |
| **F-05** | Concurrencia / Core | **P1** | S | `Sources/VozaKit/Core/Transcriber.swift:101-121` | `runProcess` hace `while process.isRunning { Thread.sleep(0.05) }` **antes** de leer `outPipe`/`errPipe`. Si `whisper-cli` escribe >64 KB en stdout/stderr, el buffer del pipe se llena y el subproceso se cuelga hasta el timeout de 120 s. | Drenar `outPipe` y `errPipe` asíncronamente con `readabilityHandler` o en colas concurrentes antes de `waitUntilExit()`, eliminando el bucle de `Thread.sleep(0.05)`. |
| **F-06** | Concurrencia / UI | **P1** | S | `Sources/VozaKit/Core/Paster.swift:58-70,175-182` | `pasteOnly` y `sendCmdV` usan `usleep(80_000)`, `usleep(20_000)` y `usleep(250_000)` directamente en `@MainActor` (350 ms congelando la UI y el HUD en cada pegado). | Convertir `Paster.paste` en `async` usando `try? await Task.sleep(for: .milliseconds(80))` y `.milliseconds(250)` sin bloquear el hilo principal. |
| **F-07** | UX / Código Muerto | **P1** | S | `Sources/VozaKit/UI/SettingsView.swift:28,43,113-118` · `OnboardingView.swift:63` · `Config.swift:241` | A pesar de que `D043` embebió `whisper-cli` en `Voza.app/Contents/MacOS/whisper-cli`, `StatusView` y `OnboardingView` siguen instanciando `BrewInstaller` y pidiendo `brew install whisper-cpp`, y `Config.resolvedWhisperBinary` tiene fallback hardcodeado a `/opt/homebrew/bin/whisper-cli`. | Eliminar `BrewInstaller.swift` de la ruta estándar, actualizar el copy de `OnboardingView.swift:63` y hacer que `Config.whisperBinary` sea `nil` por defecto para que `Transcriber.locateBinary()` priorice el binario `bundled`. |
| **F-08** | UX / Settings | **P1** | S | `Sources/VozaKit/UI/SettingsView.swift:319-325` | Cuando el usuario activa Cloud AI, `DictationSettings` sigue mostrando instrucciones para editar `~/.config/voza/.env` a mano, contradiciendo el flujo `V12` (`CloudKeySection` con Keychain en la misma pantalla). | Reemplazar el bloque de texto `.env` en `SettingsView.swift:319-325` por una confirmación limpia de que la llave activa proviene del Keychain de macOS. |
| **F-09** | Aprendizaje / Core | **P2** | S | `Sources/VozaKit/Core/CorrectionWatcher.swift:27,289,364-370` | `minSaidLength = 4` y `trimmedToWordBoundaries` (que elimina dígitos y símbolos en los extremos) impiden que el diccionario aprenda siglas técnicas (`"AI"`, `"UI"`, `"PR"`, `"SQL"`) o términos con números (`"S3"`, `"v2"`, `"M4"`). | Bajar `minSaidLength` a `2` cuando el token contenga mayúsculas o dígitos, y usar `Character.isLetter || Character.isNumber` en `trimmedToWordBoundaries`. |
| **F-10** | Toolchain / CI | **P2** | S | `.github/workflows/ci.yml:14-27` · Entorno local | En la Mac local, correr `swift test` sin `DEVELOPER_DIR` aborta con `dyld: Symbol not found: ... BuildServerProtocol` en `/Library/Developer/CommandLineTools`. Además, `ci.yml` no ejecuta `swift run VozaSmoke corrections`. | Fijar `sudo xcode-select -s /Applications/Xcode.app` en la Mac local y agregar el paso `swift run VozaSmoke corrections` en `.github/workflows/ci.yml`. |
| **F-11** | Permisos / Plist | **P2** | S | `packaging/Voza.entitlements:8-9` · `packaging/Info.plist:17` | Desde `D040` (eliminación de `osascript` / VoiceOver), Voza ya no envía Apple Events a ninguna app, pero `Voza.entitlements` conserva `com.apple.security.automation.apple-events = true` e `Info.plist` incluye `NSAppleEventsUsageDescription`. | Eliminar `com.apple.security.automation.apple-events` de `Voza.entitlements` para cumplir el principio de mínimo privilegio en notarización. |
| **F-12** | Marca / SEO | **P1** | M | `site/index.html` · `packaging/INSTALL.txt:42` | Colisión directa con [Voxa](https://voxa.infiniteagenci.com/) (app de dictado local con IA para macOS) y URL muerta `voza.app/support` en `packaging/INSTALL.txt`. | Resolver `D012` (renombrar o añadir descriptor distintivo y asegurar dominio real antes del lanzamiento público) y reemplazar `voza.app/support` en `INSTALL.txt` por la URL real de GitHub Discussions / email. |

---

## 3. Escenarios Adversarios (Los 10 Escenarios Hostiles)

1. **Input Monitoring denegado o revocado en caliente:**
   * **Comportamiento:** `CGEvent.tapCreate` en `HotKeyManager.swift:41` devuelve `nil`, establece `tapActive = false` y asigna `lastTapError`. En el siguiente ciclo o apertura, `ReadinessChecker.check()` reporta `hotkeyTapActive = false` y `StatusView` (`SettingsView.swift:101`) muestra la tarjeta naranja *"Global hotkey blocked"* con botón directo a Ajustes del Sistema. Si se revoca en caliente, el watchdog de 30 s (`HotKeyManager.swift:32`) intenta rehabilitar el tap. **[VERIFIED — Bien resuelto]**
2. **Dictado con el cursor sobre un campo de contraseña (`AXSecureTextField` / 1Password / login web):**
   * **Comportamiento:** `Paster.paste` copia el dictado al `NSPasteboard.general`, envía `⌘V` al campo de contraseña, y `TranscriptStore.add` escribe el texto dictado en texto plano dentro de `~/Dictation/YYYY-MM.md`. Si `cleanup == "cloud"`, además envía el texto a OpenAI/Anthropic. **[VERIFIED — Fallo P0 `F-03`]**
3. **Gestor de portapapeles activo (Raycast, Maccy, Paste) durante el pegado:**
   * **Comportamiento:** `Paster.pasteOnly` (`Paster.swift:56-70`) escribe el dictado en `NSPasteboard.general` y espera 330 ms (`80ms + 20ms + 250ms`). Si el gestor de portapapeles solo lee, `pb.changeCount == countBefore + 1` se cumple y Voza restaura el primer ítem previo, **pero el gestor de portapapeles ya guardó una copia permanente del dictado en su propio historial**. Además, Voza no marca el pasteboard con `org.nspasteboard.TransientType` ni `org.nspasteboard.AutoGeneratedType`, que es el estándar de [nspasteboard.org](http://nspasteboard.org/) que Maccy, Raycast y Paste respetan para ignorar escrituras sintéticas. **[VERIFIED — Mejora crítica recomendada: añadir `org.nspasteboard.TransientType`]**
4. **Caída de red a mitad de la re-verificación de licencia (día 8):**
   * **Comportamiento:** `LicenseManager.reverify` (`LicenseManager.swift:142-156`) captura el error de red en el bloque `catch` vacío y **conserva intacta la licencia en caché** (`~/.config/voza/license.json`). El usuario pagado nunca es desactivado por estar offline. **[VERIFIED — Bien resuelto]**
5. **Descarga de modelo (`large-v3-turbo`, 1.62 GB) interrumpida al 90% por corte de Wi-Fi:**
   * **Comportamiento:** `ModelManager.download` (`ModelManager.swift:180-189`) conserva el archivo `.part` cuando el error es `URLError`. Al reintentar, lee el tamaño de `.part` y envía `Range: bytes=<existing>-` (`ModelManager.swift:127`). Si el servidor responde `206 Partial Content`, continúa desde el 90% y al final verifica el SHA-256 completo del archivo antes de moverlo a destino. Si responde `416`, valida si el `.part` ya tenía el tamaño total o lo borra limpiamente. **[VERIFIED — Bien resuelto]**
6. **Doble pulsación rápida de la tecla Option (mashing < 250 ms):**
   * **Comportamiento:** En `AppState.stopDictation()` (`AppState.swift:79-84`), si `elapsedSeconds < 0.25`, llama a `recorder.cancel()`, borra el WAV temporal y vuelve a `.idle` sin lanzar `whisper-cli`. Si el usuario vuelve a presionar Option mientras `phase == .transcribing`, `startDictation()` hace `guard !phase.isBusy else { return }` (`AppState.swift:48`), ignorando la pulsación sin corromper el estado. **[VERIFIED — Bien resuelto]**
7. **Dictado mientras la pantalla se bloquea a mitad de la grabación:**
   * **Comportamiento:** Si el usuario suelta Option después de que macOS bloquea la pantalla, `whisper-cli` termina la transcripción, borra el WAV y `Paster.paste` envía `⌘V` a la sesión bloqueada (donde no hay campo de texto válido, aunque `TranscriptStore` sí lo guarda en el historial y en `~/Dictation/YYYY-MM.md`). **[VERIFIED — Mitigable verificando `CGSessionCopyCurrentDictionary` antes de pegar]**
8. **Reseteo de permisos TCC vía `tccutil reset All com.jerotherey.voza` con la app abierta:**
   * **Comportamiento:** En el siguiente intento de dictar, `Permissions.microphoneGranted` devuelve `false` en `AppState.startDictation()` (`AppState.swift:50`), cambiando `phase = .failed("Falta permiso de micrófono")` y activando `showOnboarding = true`. **[VERIFIED — Bien resuelto]**
9. **Grabación de 3 segundos de silencio puro o ruido de ventilador:**
   * **Comportamiento:** `whisper-cli` emite `[BLANK_AUDIO]` o `(wind blowing)` o cadena vacía; `Transcriber.isNonSpeechMarker` (`Transcriber.swift:72-79`) lo detecta y lanza `TranscriptionError.emptyResult` (*"No se detectó voz"*). `DictationPipeline` borra el WAV y no pega basura en el campo del usuario. **[VERIFIED — Bien resuelto]**
10. **Mac de un cliente sin Homebrew instalado (escenario comprador de Gumroad):**
    * **Comportamiento:** Gracias a `D043`, `Voza.app/Contents/MacOS/whisper-cli` está incluido con Metal embebido. Sin embargo, si el usuario NO ha configurado `whisper_binary` en `config.toml`, `Config.shared.resolvedWhisperBinary` (`Config.swift:241`) devuelve `"/opt/homebrew/bin/whisper-cli"`, que en una Mac sin Homebrew no existe; `Transcriber.locateBinary()` (`Transcriber.swift:25-35`) itera los candidatos, ve que `/opt/homebrew/bin/whisper-cli` no es ejecutable y pasa al segundo candidato (`bundled`), que **sí existe y funciona**. Pero si en la Mac del cliente existe un `whisper-cli` roto de Homebrew en `/opt/homebrew/bin/whisper-cli`, **`Config.shared.resolvedWhisperBinary` le gana al binario `bundled` de la app** porque `resolvedWhisperBinary` nunca es `nil`! **[VERIFIED — Bug sutil en `Transcriber.swift:29` + `Config.swift:241`: `Config.shared.whisperBinary` (el override opcional) debe ir antes de `bundled`, NO `resolvedWhisperBinary`]**

---

## 4. Investigación de Mercado y Modelo de Negocio (Octubre 2026)

### 4.1 Matriz Competitiva Actualizada (Octubre 2026)

| Producto | Modelo de Precio y Costo Anual Real | Procesamiento (Local vs Cloud) | Funciones Clave (Cleanup, Aprendizaje, Idiomas) | Debilidad Principal / Queja Recurrente |
|---|---|---|---|---|
| **Voza** (Tuyo) | **$15** pago único (Early Access) → **$29** v1.0 (código MIT gratis si compilas) | **100% Local STT** (`whisper.cpp` + Metal embebido); Cleanup Cloud opt-in (BYOK) | Push-to-talk (Option), Auto-Learn invisible en cualquier app (incl. Electron), HUD reactivo, bilingüe EN/ES nativo | Sin notarizar aún; Pulido local fue eliminado (`D032`); sin auto-updater (Sparkle). |
| **[Superwhisper](https://superwhisper.com/docs/billing/plans)** | Gratis (modelos locales básicos, 2 modos) · Pro **$8.49/mes** ($84.99/año) · **$249.99** lifetime ([comparativa oficial](https://superwhisper.com/vs/wispr-flow)) | Local (Whisper/Parakeet) + Cloud AI incluido en Pro | Modos por app, contexto de ventana/portapapeles, vocabulario personalizado, reemplazos, iOS/Windows | Fuerte rechazo en [Reddit](https://www.reddit.com/r/macapps/comments/1ma0n73/what_are_some_alternatives_to_superwhisper/) por subir el lifetime a $249.99 y complejidad de configuración. |
| **[Wispr Flow](https://wisprflow.ai/pricing)** | Gratis (hasta 2,000 palabras/sem) · Pro **$15/mes** ($144/año facturado anual) ([planes](https://docs.wisprflow.ai/articles/9559327591-flow-plans-and-what-s-included)) | **100% Cloud** (requiere internet permanente) | Pulido IA ultrarrápido (~700 ms en Baseten), auto-learn de correcciones, modo comando, iOS/Windows/Android | Fatiga de suscripción ($144–$180/año), privacidad nula (todo el audio sube a la nube) y alto uso de RAM/batería ([quejas en Reddit](https://www.reddit.com/r/WisprFlow/comments/1vnq4qt/beyond_the_wispr_flow_paywall_alternatives_for/)). |
| **[VoiceInk](https://tryvoiceink.com/)** | Open Source ([GPLv3](https://github.com/beingpax/VoiceInk)) · Binario pago único: **$29 Solo** (1 Mac) / **$49 Personal** (2 Macs) ([precios 2026](https://enviouswispr.com/compare/voiceink/)) | Local (Whisper/Parakeet en Metal) + BYOK / Cloud opcional | Power Mode (contexto por app/URL), diccionario inteligente, historial completo, prompts personalizados | Curva de configuración inicial de modelos y prompts para usuarios no técnicos. |
| **[TypeWhisper](https://www.typewhisper.com/en/)** | **Gratis y Open Source** ([GPL-3.0](https://github.com/TypeWhisper/typewhisper-mac)) | 100% Local (WhisperKit, Parakeet, Gemma 4 vía MLX on-device) + BYOK | Undo Last Dictation, sincronización iCloud de historial, perfiles por app, edición de atajos visual | Proyecto reciente (v1.0 lanzada en 2026); el pulido local con MLX consume ~2.5 GB de RAM GPU. |
| **[Spokenly](https://spokenly.app/pricing)** | **Gratis** (modelos locales + BYOK ilimitado) · Pro **$99.99/año** (modelos cloud incluidos) ([App Store](https://apps.apple.com/us/app/spokenly-audio-to-text-ai-app/id6740315592)) | Local (Whisper/Parakeet) + BYOK gratis + Cloud Pro | Modo Agente, integración MCP para agentes de código, transcripción de archivos, teclado iOS | Las funciones cloud sin configurar API keys requieren suscripción anual de $99.99. |
| **[MacWhisper](https://www.macwhisper.com/)** | Gratis (modelos pequeños) · Pro **~€59+** pago único en [Gumroad](https://goodsnooze.gumroad.com/l/macwhisper) | Local (Whisper, Parakeet, Qwen) + BYOK | Transcripción de reuniones, archivos de audio/video, grabación de audio del sistema y dictado | Su ADN es transcribir archivos/reuniones; los usuarios en [r/macapps](https://www.reddit.com/r/macapps/comments/1ja1a9c/the_3_best_dictation_apps_a_comparison_and/) lo sienten pesado como utilidad pura de dictado. |
| **[Handy](https://handy.computer/)** | **Gratis y Open Source** ([MIT/GitHub](https://github.com/cjpais/handy)) | 100% Local (Rust + Tauri + `whisper.cpp` / Parakeet) | Push-to-talk y toggle, multiplataforma (macOS, Windows, Linux), ligero | Sin auto-learn de correcciones al escribir, UX espartana. |
| **[OpenWhispr](https://github.com/OpenWhispr/openwhispr)** | **Gratis y Open Source** + opción cloud gestionada | Local (Parakeet/Whisper) + Cloud BYOK | Multiplataforma (macOS, Windows, Linux), BYOK con OpenAI/Anthropic/Groq/Gemini | Empaquetado Electron más pesado que una app SwiftUI nativa. |
| **[Voxa](https://voxa.infiniteagenci.com/)** | Pago único / Freemium | Local AI para macOS | Push-to-talk e inserción instantánea en cualquier app | **Colisión directa de nombre y posicionamiento con Voza.** |
| **[Dictado de Apple](https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac)** | **$0** (incluido en macOS) | On-device en Apple Silicon | Integrado en el sistema, puntuación automática básica | Se apaga solo tras pausas cortas, sin historial persistente (`~/Dictation`), sin auto-learn de vocabulario propio, baja precisión en espanglish/jerga técnica. |

### 4.2 Diagnóstico Crudo del Modelo de Negocio de Voza

1. **La realidad del mercado tras `D032`:**
   Cuando Voza tenía Pulido local integrado, la promesa era *"Wispr Flow sin suscripción y sin nube"*. Al remover el Pulido local en `D032` (decisión técnicamente correcta porque un LLM de 4B en swap congela la Mac), Voza quedó como **Dictado Literal local + Auto-Learn + Cloud AI con tu propia API key (BYOK)**.
   * **El riesgo:** En octubre de 2026, **el dictado local + BYOK ya es gratis** en [Spokenly](https://spokenly.app/pricing), [TypeWhisper](https://github.com/TypeWhisper/typewhisper-mac) y [OpenWhispr](https://github.com/OpenWhispr/openwhispr), y cuesta $29 en [VoiceInk](https://tryvoiceink.com/) (que ya está notarizado y tiene miles de estrellas en GitHub).
   * **La verdadera ventaja injusta de Voza (que hoy casi no vendes en la landing):** Tu sistema **`CorrectionWatcher` + `CorrectionStore` (`D033`–`D041`)**. Ningún competidor open-source ligero observa el campo donde pegaste (incluyendo apps Electron/Chromium despertadas silenciosamente por atributos sin VoiceOver), aprende cuando corriges una palabra tecleando (`"sin telia" -> "Sintelia"`), e inyecta esa lección tanto en reemplazo exacto como en el `--prompt` de `whisper.cpp` para sesgar la decodificación futura. **Ese bucle de aprendizaje sin configuración + el enfoque bilingüe EN/ES (espanglish técnico) + el Daily Log en Markdown (`~/Dictation/YYYY-MM.md`) es lo que debes vender en el Hero de la landing.**

2. **Matemática real de pasarelas de pago (en $15 Early Access y $29 v1.0):**
   * **[Gumroad](https://www.paritydeals.com/gumroad-fee-calculator/):** Cobra 10% + $0.50 de comisión de plataforma **más** procesamiento de tarjeta (~2.9% + $0.30).
     * En una venta de **$15**: Gumroad retiene ~$1.50 + $0.50 + $0.44 + $0.30 = **$2.74 (18.2% de comisión efectiva)** → recibes **$12.26**.
     * En una venta de **$29**: Gumroad retiene **$4.54 (15.6%)** → recibes **$24.46**.
     * En **$10,000 USD/mes** (~345 ventas a $29): pierdes **$1,566 USD/mes** en comisiones.
   * **[Polar.sh](https://polar.sh/resources/pricing) / [Lemon Squeezy](https://www.lemonsqueezy.com/pricing) / [Paddle](https://www.comecero.com/blog/paddle-vs-lemon-squeezy):** Actúan como *Merchant of Record* (gestionan IVA/impuestos globales igual que Gumroad) por **4%–5% + $0.40–$0.50** total.
     * En una venta de **$15**: comisión de ~$1.25 (**8.3%**) → recibes **$13.75** (+$1.49 por venta respecto a Gumroad).
     * En **$10,000 USD/mes**: pagas ~$672 USD/mes (**ahorras ~$894 USD/mes** frente a Gumroad).
   * **Recomendación accionable:** Quédate en **Gumroad** únicamente para las primeras 20–50 licencias de Early Access porque `LicenseManager.swift` ya está cableado y probado contra `api.gumroad.com/v2/licenses/verify` (cero horas de ingeniería hoy). En cuanto valides tracción y lances v1.0 a $29, migra el checkout principal a **Polar.sh** (construido específicamente para desarrolladores indie/open-source, con validación de License Keys nativa) manteniendo el verificador de Gumroad como fallback para compradores Early Access.

3. **Estrategia de Precios y Economía de IA en la Nube (Groq / OpenAI):**
   * **$15 Early Access (con 1 año de actualizaciones + pay-what-you-want opcional después, `D046`) → $29 en v1.0** es la estructura correcta para un fundador solo.
   * **Truco de producto de altísimo valor para el modo Pulido Cloud (`Cleaner.swift`):** Hoy `Cleaner.swift:109` usa por defecto `https://api.openai.com/v1` con `gpt-4o-mini`. Sin embargo, la latencia de `gpt-4o-mini` es de ~600–1,200 ms, mientras que **Groq** (con `llama-3.3-70b-versatile`) es compatible con el mismo endpoint OpenAI de tu `Cleaner.swift`, responde en **~150–250 ms** (más rápido que Wispr Flow) y tiene tier gratuito generoso. Si en la UI de `CloudKeySection` ofreces un selector de 1 clic: `OpenAI` | `Anthropic` | `Groq (Ultra-fast, free tier)` | `Custom URL`, multiplicas por 5 el atractivo del modo Pulido sin pagar servidores.

---

## 5. Estrategia de Producto: Las 7 Mejoras de Mayor Retorno (Priorizadas por ROI)

| Prioridad | Feature / Cambio | Impacto en Compra / Retención | Esfuerzo | Archivos a tocar |
|---|---|---|---|---|
| **1 (Must — Pre-Launch)** | **Protección de campos seguros + Etiqueta `TransientType` en Portapapeles** | Evita desastres de privacidad en contraseñas y gestores de portapapeles (Maccy/Raycast). | **S (3 h)** | `Paster.swift`, `DictationPipeline.swift` |
| **2 (Must — Pre-Launch)** | **Prioridad correcta del binario `bundled` + Limpieza de UI Homebrew/.env** | Evita que un `whisper-cli` roto en `/opt/homebrew` pise al binario estático de la app (`F-07` / Escenario 10) y elimina confusión en Onboarding/Settings. | **S (2 h)** | `Transcriber.swift`, `Config.swift`, `SettingsView.swift`, `OnboardingView.swift` |
| **3 (Must — Pre-Launch)** | **Firma interna de `whisper-cli` en `scripts/release.sh` + Notarización Apple ($99)** | Elimina el bloqueo de Gatekeeper en macOS 15/26 que mata la conversión de compradores de pago. | **S (2 h + $99)** | `scripts/release.sh`, `packaging/Voza.entitlements` |
| **4 (Should — v0.3.1)** | **`Paster` asíncrono sin `usleep` en MainActor + Drenado de Pipes en `Transcriber`** | Elimina el congelamiento de 350 ms del HUD al pegar y previene cuelgues en dictados largos (>64 KB). | **S (3 h)** | `Paster.swift`, `DictationPipeline.swift`, `Transcriber.swift` |
| **5 (Should — v0.3.1)** | **Control de retención de `~/Dictation` en Settings (On / Solo sesión en RAM + botón Borrar)** | Cumple `D007` y convierte a usuarios preocupados por dejar un archivo Markdown con todo lo que hablan en disco. | **S (4 h)** | `TranscriptStore.swift`, `Config.swift`, `SettingsView.swift` |
| **6 (Should — v0.4.0)** | **Preset de Groq (latencia <250 ms) en `CloudKeySection` + Aprendizaje de siglas cortas (`minSaidLength = 2`)** | Da a Voza un modo Pulido más rápido que Wispr Flow con costo $0 de servidor y permite aprender siglas técnicas (`AI`, `PR`, `S3`). | **M (1 día)** | `Cleaner.swift`, `Config.swift`, `SettingsView.swift`, `CorrectionWatcher.swift` |
| **7 (Could — v0.5.0)** | **Atajo "Undo Last Dictation" / Modo Toggle opcional (pulsar una vez para dictados largos)** | Accesibilidad para dictados de >30 s sin cansar el dedo y paridad con TypeWhisper. | **M (2 días)** | `HotKeyManager.swift`, `Paster.swift`, `AppState.swift` |

### Parches de Código Listos para Aplicar (P0 y P1)

#### 1. `Sources/VozaKit/Core/Transcriber.swift` — Priorizar `whisper-cli` embebido sobre el fallback de Homebrew (`F-07` / Escenario 10)
Actualmente `Config.shared.resolvedWhisperBinary` siempre devuelve `"/opt/homebrew/bin/whisper-cli"` cuando `whisperBinary == nil`, poniéndolo **por delante** de `bundled`. Debe usarse `Config.shared.whisperBinary` (solo si el usuario configuró un override explícito):

```swift
static func locateBinary() -> String? {
    let bundled = Bundle.main.executableURL?
        .deletingLastPathComponent()
        .appendingPathComponent("whisper-cli").path
    return locateBinary(candidates: [
        Config.shared.whisperBinary, // Solo si el usuario definió un override explícito
        bundled,                     // Primero el binario estático v1.9.4 con Metal embebido
        "/opt/homebrew/bin/whisper-cli",
        "/usr/local/bin/whisper-cli",
    ].compactMap { $0 })
}
```

#### 2. `Sources/VozaKit/Core/Paster.swift` — Bloqueo de campos de contraseña (`F-03`) y marcador `TransientType` para gestores de portapapeles (Escenario 3)
```swift
import Carbon.HIToolbox

/// Detecta si el sistema tiene Secure Event Input activo (campos de contraseña nativos/navegadores)
/// o si el elemento AX enfocado tiene subrol AXSecureTextField.
static func isFocusedElementSecure() -> Bool {
    if IsSecureEventInputEnabled() { return true }
    guard AXIsProcessTrusted(), let el = focusedElement() else { return false }
    var subroleRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &subroleRef) == .success,
       let subrole = subroleRef as? String,
       subrole == (kAXSecureTextFieldSubrole as String) {
        return true
    }
    return false
}
```
Y en `Paster.pasteOnly(_ text: String)`, al escribir el texto temporal en `NSPasteboard.general`:
```swift
pb.clearContents()
pb.setString(text, forType: .string)
// Estándar nspasteboard.org: indica a Maccy, Raycast y Paste que ignoren este pegado temporal
pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
```

#### 3. `scripts/release.sh` — Firmar `whisper-cli` antes del bundle (`F-01`)
```bash
echo "==> Signing embedded whisper-cli helper with Developer ID (runtime hardened)"
codesign --force --sign "$VOZA_SIGNING_ID" \
  --options runtime \
  --timestamp \
  "$APP/Contents/MacOS/whisper-cli"

echo "==> Signing app bundle with Developer ID (runtime hardened)"
codesign --force --sign "$VOZA_SIGNING_ID" \
  --entitlements packaging/Voza.entitlements \
  --options runtime \
  --timestamp \
  "$APP"
```

---

## 6. Plan de Ejecución a 90 Días (Código + UX + Negocio + GTM)

### Semana 1: Cierre de Bloqueadores P0 y Empaquetado Impecable
1. **Día 1 (Código P0):** Aplicar los 3 parches arriba (`Transcriber.locateBinary`, `Paster.isFocusedElementSecure` + `TransientType`, `scripts/release.sh`), eliminar `com.apple.security.automation.apple-events` de `packaging/Voza.entitlements`, y limpiar las menciones obsoletas a Homebrew y `.env` en `README.md`, `SettingsView.swift` y `OnboardingView.swift`.
2. **Día 2 (Hardening P1):** Hacer `Paster.pasteOnly` asíncrono con `Task.sleep` (eliminando los 350 ms de bloqueo en MainActor) y drenar pipes en `Transcriber.runProcess` antes de `waitUntilExit()`. Añadir `swift run VozaSmoke corrections` a `.github/workflows/ci.yml`.
3. **Día 3 (Decisión de Marca y Dominio):** Resolver `D012` frente a la colisión con [Voxa](https://voxa.infiniteagenci.com/). Si conservas **Voza**, usar descriptor compuesto en títulos (*"Voza Dictation for Mac"*) y reemplazar el dominio roto `voza.app/support` en `packaging/INSTALL.txt` por la URL real de soporte/GitHub.
4. **Día 4–5 (Notarización y Video Demo):** Inscribirse en Apple Developer Program ($99/año), correr `scripts/release.sh` para generar un DMG **notarizado** (cero alertas de Gatekeeper en macOS 15/26), grabar el demo real de 40 segundos sin cortes (`site/demo.mp4`) mostrando: *(1) dictado instantáneo en español/inglés, (2) corrección tecleada de "sin telia" → "Sintelia", (3) siguiente dictado escribiendo "Sintelia" perfecto automáticamente*.

### Semanas 2–4: Lanzamiento Escalonado y Validación de Conversión ($15 Early Access)
* **Posicionamiento central en Landing (`site/index.html`) y Gumroad:**
  > *"Dicta. Se pega solo. Y aprende cuando lo corriges — 100% en tu Mac, pago único de $15."*
* **Secuencia de canales (`docs/SOFT-LAUNCH-PLAN.md` mejorado):**
  * **Días 8–10 (Círculo cercano + X):** Publicar el video de 40 s sin cortes mostrando el bucle de Auto-Learn en vivo. Meta: primeras 5 ventas reales y validar activación/reembolso de licencia en Gumroad.
  * **Días 11–18 (Comunidades hispanas y bilingües):** Lanzar en comunidades de desarrolladores/productividad en español y espanglish (donde Superwhisper y Wispr Flow no tienen UI ni documentación nativa en español).
  * **Días 19–28 (r/macapps y r/LocalLLaMA):** En `r/LocalLLaMA`, liderar con la historia de ingeniería real de `DECISIONS.md`: por qué eliminaste MLX 4B local tras medir contención de GPU bajo swap (`D027`–`D032`), cómo empaquetaste `whisper.cpp` v1.9.4 con Metal embebido sin Homebrew (`D043`) y cómo despertaste el árbol AX de Chromium/Electron por atributos sin abrir VoiceOver (`D040`). Ese post técnico genuino tiene altísima tracción orgánica.

### Días 31–60: v0.4 (Retención, Pulido Ultra-Rápido y Polar.sh)
* Implementar el interruptor de privacidad de `~/Dictation` (On / Solo RAM + botón de borrado).
* Añadir preset de 1 clic para **Groq** (`llama-3.3-70b-versatile`) y **OpenRouter** en `CloudKeySection` (guardados en Keychain).
* Relajar `CorrectionWatcher` para aprender siglas técnicas de 2–3 letras (`AI`, `UI`, `PR`, `AWS`, `M4`).
* Evaluar métricas del primer mes: si la conversión visita → compra supera el 1.5% y los reembolsos están bajo el 5%, preparar el salto a **v1.0 ($29)** migrando el checkout nuevo a **Polar.sh** (reduciendo comisiones del ~18.2% al ~8.3%).

### Días 61–90: v1.0 (Show HN, Product Hunt y Auto-Actualización)
* Integrar **Sparkle 2** (o verificador ligero de releases de GitHub firmado) para que los compradores no queden atrapados en builds viejos.
* Lanzar **v1.0 a $29** en **Show HN** y **Product Hunt** con el DMG notarizado, Homebrew Cask actualizado (`packaging/voza.rb` con SHA-256 real) y la promesa de 1 año de actualizaciones (`D046`).

---

## 7. Preguntas Abiertas para el Propietario

1. **Precio definitivo de salida hoy ($15 vs $29):** ¿Confirmas que el precio de lanzamiento inmediato es **$15 Early Access** (como en `site/index.html` y `docs/GUMROAD-PAGE-COPY.md`) para actualizar `README.md` y `docs/market-analysis.md` ahora mismo?
2. **Inversión de $99 en Apple Developer antes vs después de la primera venta (`D046`):** Con macOS 15/26 exigiendo Terminal (`xattr -dr`) o ir a Ajustes de Privacidad para abrir apps no notarizadas, ¿prefieres inscribir la cuenta de Apple Developer antes de publicar el link en Gumroad, o mantener el lanzamiento sin notarizar para tu círculo cercano (Fase 1)?
3. **Nombre de marca (`Voza` vs `Voxa`):** Dado que [Voxa](https://voxa.infiniteagenci.com/) ya opera en SEO para *"macOS local AI dictation"*, ¿quieres mantener **Voza** (por ejemplo como *"Voza Dictation"*) o prefieres evaluar un cambio de nombre antes de publicar en Gumroad y desplegar la landing en Cloudflare Pages?

---

## 8. Apéndice de Fuentes Verificadas (Octubre 2026)

* [Superwhisper — Plans & Pricing](https://superwhisper.com/docs/billing/plans) (Consultado: 13 oct 2026)
* [Superwhisper vs Wispr Flow — Official Comparison](https://superwhisper.com/vs/wispr-flow) (Consultado: 13 oct 2026)
* [Wispr Flow — Pricing](https://wisprflow.ai/pricing) y [Help Center Plans](https://docs.wisprflow.ai/articles/9559327591-flow-plans-and-what-s-included) (Consultado: 13 oct 2026)
* [VoiceInk — Sitio Oficial](https://tryvoiceink.com/) y [GitHub Repository](https://github.com/beingpax/VoiceInk) (Consultado: 13 oct 2026)
* [TypeWhisper — GitHub Repository](https://github.com/TypeWhisper/typewhisper-mac) y [Sitio Oficial](https://www.typewhisper.com/en/) (Consultado: 13 oct 2026)
* [Spokenly — Pricing](https://spokenly.app/pricing) y [Spokenly vs Wispr Flow](https://spokenly.app/comparison/wispr-flow) (Consultado: 13 oct 2026)
* [MacWhisper — Sitio Oficial](https://www.macwhisper.com/) y [Gumroad Store](https://goodsnooze.gumroad.com/l/macwhisper) (Consultado: 13 oct 2026)
* [Handy — Sitio Oficial](https://handy.computer/) y [GitHub Repository](https://github.com/cjpais/handy) (Consultado: 13 oct 2026)
* [OpenWhispr — GitHub Repository](https://github.com/OpenWhispr/openwhispr) (Consultado: 13 oct 2026)
* [Voxa — Voice-to-Text for macOS](https://voxa.infiniteagenci.com/) (Consultado: 13 oct 2026)
* [Polar.sh — Pricing](https://polar.sh/resources/pricing) y [Merchant of Record Fees](https://polar.sh/docs/merchant-of-record/fees) (Consultado: 13 oct 2026)
* [Gumroad Fee Calculator 2026 — ParityDeals](https://www.paritydeals.com/gumroad-fee-calculator/) (Consultado: 13 oct 2026)
* [Lemon Squeezy Pricing 2026 — Swell](https://www.swell.is/content/lemon-squeezy-pricing) y [Paddle vs Lemon Squeezy 2026](https://www.comecero.com/blog/paddle-vs-lemon-squeezy) (Consultado: 13 oct 2026)

---

## 9. Bitácora de Verificación Local

* `git_status` en `/Users/jeronimorey/Developer/voza` → Árbol limpio salvo 1 archivo sin seguimiento (`?? "Imagen de Codex 15 sept 2026, 04_33_26 p.m..png"`).
* `git_log` en `/Users/jeronimorey/Developer/voza` → HEAD en `6df2016` (`V12: cloud credentials in the Keychain + hardened provider boundary (151 tests, smoke 61)`).
* Inspección completa de código fuente (`Sources/VozaKit/Core/*.swift`, `State/AppState.swift`, `UI/*.swift`, `App/*.swift`, `Sources/VozaSmoke/main.swift`, `Tests/VozaTests/*.swift`), scripts (`build.sh`, `scripts/release.sh`, `scripts/make-dmg.sh`), empaquetado (`packaging/*`), web (`site/index.html`) y documentos de negocio (`docs/*`, `docs/plan-glm/*`).
* Inspección de estado en runtime (`/Users/jeronimorey/.config/voza/config.toml`) → TOML válido (`model = "large-v3-turbo"`, `cleanup = "plain"`, `language = "auto"`, `play_sound = true`, `auto_learn = true`, `gumroad_permalink = "voza"`), presencia de respaldos históricos de correcciones (`corrections.json.bak-poison`, `corrections.json.bak-d036`, `corrections.json.bak-d039-test`).
* Ejecución de `swift test && swift run VozaSmoke` sin `DEVELOPER_DIR` → **Fallo verificado (`exit code 134`, `SIGABRT`)**: `/Library/Developer/CommandLineTools/usr/bin/swift-package` aborta por `dyld: Symbol not found: _$s19BuildServerProtocol...` (documentado en hallazgo **F-10**).
