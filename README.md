<div align="center">

# 🎙️ Voza

**Dictate. It pastes itself. And it learns when you fix a word.**
**Dicta. Se pega solo. Y aprende cuando corriges una palabra.**

Local, offline dictation for macOS that learns your vocabulary as you type — a private, one-time-price alternative to Wispr Flow and Superwhisper.
Dictado local y offline para macOS que aprende tu vocabulario mientras escribes — alternativa privada y de pago único a Wispr Flow y Superwhisper.

[![License: MIT](https://img.shields.io/badge/License-MIT-orange.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)]()
[![Price](https://img.shields.io/badge/Early%20Access-%2415%20once-success)](https://jerotherey.gumroad.com/l/voza)

</div>

---

## English

### What it does

| Action | How |
|---|---|
| **Dictate** | Hold **Option** (either side) anywhere in macOS, speak, release → text is pasted where your cursor is |
| **Auto-Learn** | Fix any misheard word by typing right after paste (e.g. *sin telia* → *Sintelia*) → Voza learns it automatically and gets it right next time |
| **Dictate + AI cleanup (opt-in)** | Turn on *Cloud AI* in Settings → Dictation and save your API key in the macOS Keychain → punctuation, fillers and spoken edit commands are cleaned before pasting |
| **History & Daily Log** | Click the menu bar mic → last 10 transcripts with copy/teach buttons, plus an automatic Markdown log at `~/Dictation/YYYY-MM.md` |

- Transcription runs **100% locally** with a bundled, statically compiled [whisper.cpp](https://github.com/ggml-org/whisper.cpp) v1.9.4 engine (Metal-accelerated, zero Homebrew dependencies required). Your audio never leaves the Mac.
- Audio files are **deleted immediately** after transcription, password fields (`AXSecureTextField`) are blocked, and synthetic pastes carry `TransientType` markers so clipboard managers ignore them. No accounts, no telemetry, no cloud STT.
- **Zero-effort vocabulary learning (`CorrectionWatcher`)**: Voza watches only the field it just pasted into for 20 seconds (including Electron/Chromium apps woken silently via AX attributes, never VoiceOver). When you fix a word, it applies both exact word-boundary replacement and Whisper `--prompt` conditioning on future dictations.
- **AI cleanup is an explicit opt-in** (off by default): when enabled in Settings, the already-transcribed text is sent over HTTPS (no redirects) to an OpenAI-compatible API (OpenAI, Groq, OpenRouter…) with Anthropic as backup, using your own key stored in the macOS Keychain. Never audio, never without the switch.
- **Automatic preset for your Mac and language**: Voza picks a multilingual model by default and only selects an English-optimized one when your speech language is English. Downloads are verified with SHA-256.
- Bilingual UI & docs: English / Español (auto-detected, override in Settings).

### Requirements

- macOS 14+ (Sonoma or newer, Apple Silicon)
- No Homebrew required (`whisper-cli` v1.9.4 with embedded Metal is bundled inside `Voza.app`)
- One model download on first run (verified automatically with SHA-256 — typically ~190 MB; on Macs with 16 GB+ Voza recommends `large-v3-turbo`, ~1.6 GB)

### Permissions macOS will ask for (first run)

1. **Microphone** — to record your voice while holding Option.
2. **Accessibility** — to paste text into the focused app and learn your typed corrections.
3. **Input Monitoring** — to detect the Option hotkey globally.

> If a permission was denied by accident: System Settings → Privacy & Security → Microphone / Accessibility / Input Monitoring → enable **Voza**.

### Build & run from source

```bash
git clone https://github.com/Jerotheking/voza && cd voza
./build.sh             # builds Voza + vendored static whisper.cpp v1.9.4 into build/Voza.app
open build/Voza.app
```

### Verification

```bash
swift test                           # full XCTest suite
swift run VozaSmoke                  # hermetic pure checks
swift run VozaSmoke v01              # V01 filesystem/clock isolation suite
swift run VozaSmoke corrections      # CorrectionStore + CorrectionWatcher suite
```

### Licensing & buying

Voza's source is **MIT** — build it yourself and it's free, forever. If you'd rather skip the build, the **pre-built Early Access app is $15 once** ([Gumroad](https://jerotherey.gumroad.com/l/voza), rising to $29 at v1.0): it includes a 14-day free trial, one-time activation (cached offline after the first check), one year of updates (then pay-what-you-want or keep your build forever), and no subscription.

---

## Español

### Qué hace

| Acción | Cómo |
|---|---|
| **Dictar** | Mantén **Option** (cualquier lado) en cualquier app, habla, suelta → el texto se pega donde está tu cursor |
| **Auto-Aprendizaje** | Corrige cualquier palabra tecleando después del pegado (ej. *sin telia* → *Sintelia*) → Voza la aprende sola y la escribe bien la próxima vez |
| **Dictar + limpieza IA (opt-in)** | Activa *IA en la nube* en Ajustes → Dictado y guarda tu API key en el Llavero de macOS → limpia muletillas, puntuación y comandos hablados antes de pegar |
| **Historial y Daily Log** | Clic en el micrófono de la barra de menú → últimos 10 dictados con botón de copiar y editar (✏️), más registro Markdown en `~/Dictation/YYYY-MM.md` |

- La transcripción corre **100% local** con `whisper.cpp` v1.9.4 compilado estáticamente con Metal embebido dentro de `Voza.app` (no necesitas instalar Homebrew). Tu audio nunca sale de la Mac.
- Los audios se **borran inmediatamente** después de transcribir y los campos de contraseña están protegidos. Sin cuentas, sin telemetría, sin STT en la nube.
- **La limpieza IA es opt-in explícito** (apagada por defecto): al activarla en Ajustes, el texto ya transcrito se envía por HTTPS a una API compatible con OpenAI (OpenAI, Groq, OpenRouter…) con Anthropic de respaldo, usando tu llave guardada en el Llavero de macOS. Nunca el audio, nunca sin el switch.
- UI y documentación 100% bilingües EN/ES.

---

<div align="center">

**Why $15 Early Access ($29 at 1.0) and not $180/yr?** Because speech-to-text runs on your own Mac — you pay once for a fast, private tool that learns your words. / **¿Por qué $15 en Early Access ($29 en 1.0) y no $180/año?** Porque el reconocimiento corre en tu propia Mac — pagas una sola vez por una herramienta rápida, privada y que aprende tus palabras.

MIT © 2026 [Jerónimo Rey](https://github.com/Jerotheking) · [Gumroad](https://jerotherey.gumroad.com/l/voza)

</div>
