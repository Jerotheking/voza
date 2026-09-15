<div align="center">

# 🎙️ Voza

**Dictate. It pastes itself. Pay once.**
**Dicta. Se pega solo. Pago único.**

Local, offline, AI-powered dictation for macOS — a faster, cheaper, private Superwhisper replacement.
Dictado local, offline y con IA para macOS — reemplazo de Superwhisper: más rápido, más barato, privado.

[![License: MIT](https://img.shields.io/badge/License-MIT-orange.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)]()
[![Price](https://img.shields.io/badge/price-%2429%20once-success)]()

</div>

---

## English

### What it does

| Action | How |
|---|---|
| **Dictate** | Hold **Option** (either side) anywhere in macOS, speak, release → text is pasted where your cursor is |
| **Dictate + AI cleanup (opt-in)** | Turn on *Cloud AI* in Settings and set `OPENAI_API_KEY` in `~/.config/voza/.env` → same hotkey, then punctuation/fillers are fixed by your chosen model (Wispr-Flow-style polish, sent only when you opt in) |
| **History** | Click the menu bar mic → last 10 transcripts with copy buttons |
| **Log** | Every transcript is appended to `~/Dictation/YYYY-MM.md` with a timestamp |

- Transcription runs **100% locally** with [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (Metal-accelerated). Your audio never leaves the Mac. By default the transcript is pasted **exactly as dictated** — no network, no processing.
- Audio files are **deleted immediately** after transcription. No accounts, no telemetry, no cloud STT.
- **AI cleanup is an explicit opt-in** (off by default): when enabled in Settings, the already-transcribed text is sent to an OpenAI-compatible API (OpenAI, OpenRouter, Groq…) with Anthropic as backup, using your own key in `~/.config/voza/.env` (see `.env.example`). Never audio, never without the switch.
- **Automatic preset for your Mac and language**: Voza picks a multilingual model by default and only selects an English-optimized one when your speech language is English. Downloads are verified with SHA-256. Override in Settings → Models.
- Bilingual UI: English / Español (auto-detected, override in Settings).

### Requirements

- macOS 14+ (Apple Silicon)
- [Homebrew](https://brew.sh) with `whisper-cpp`: `brew install whisper-cpp`
- One model download (done from the app, verified automatically — typically ~190 MB; on Macs with 32 GB+ Voza recommends large-v3-turbo, ~1.6 GB)

### Permissions macOS will ask for (first run)

Voza triggers up to three system prompts on first use — this is normal, and each one is explained in the app's onboarding:

1. **Microphone** — to record your voice. Prompt appears the first time you hold the hotkey (or press *Grant* in onboarding).
2. **Accessibility** — to paste text into the focused app. Prompt appears on the first paste; you can also open it via onboarding → *Open Settings*. Without it, transcripts still appear in history but are not pasted.
3. **Input Monitoring** — to detect the Option hotkey globally. macOS shows this prompt when the event tap starts.

> If a permission was denied by accident: System Settings → Privacy & Security → Microphone / Accessibility / Input Monitoring → enable **Voza**.

### Build & run

```bash
git clone https://github.com/Jerotheking/voza && cd voza
swift build            # verify
./build.sh             # produces build/Voza.app (signed ad-hoc)
open build/Voza.app
```

First launch: grant the permissions above, then open the menu bar mic → onboarding walks you through downloading the recommended model. After that, hold Option and talk.

### Configuration (optional)

Everything works with defaults. Config lives at `~/.config/voza/config.toml`:

```toml
model = "small.en-q5_1"        # whisper model id (see catalog in app)
language = "auto"              # auto | en | es
cleanup = "plain"              # plain (default, no network) | cloud (explicit opt-in)
log_dir = "/Users/you/Dictation"
play_sound = false
```

Cloud cleanup keys go in `~/.config/voza/.env` (copy `.env.example`).

### Verification

```bash
swift run VozaSmoke          # unit + integration checks
swift run VozaSmoke e2e /tmp/jfk.wav   # full pipeline: download → SHA-256 → transcribe
```

### Licensing & buying

Voza's source is **MIT** — build it yourself and it's free, forever. If you'd rather skip the build, the **pre-built, notarized app is $29** ([Gumroad](https://jerotherey.gumroad.com/l/voza)): it includes a 14-day trial, one-time Gumroad activation (cached offline after the first check, 7-day silent re-verify), and no subscription. Your purchase funds development.

### Releasing (maintainers)

```bash
export VOZA_SIGNING_ID="Developer ID Application: ... (TEAMID)"
export VOZA_KEYCHAIN_PROFILE="notarytool-profile"
./scripts/release.sh        # build → sign → notarize → staple → DMG
# bump packaging/voza.rb (cask) with the new DMG SHA-256
```

See [docs/market-analysis.md](docs/market-analysis.md) for the full competitive and pricing research.

---

## Español

### Qué hace

| Acción | Cómo |
|---|---|
| **Dictar** | Mantén **Option** (cualquier lado) en cualquier app, habla, suelta → el texto se pega donde está tu cursor |
| **Dictar + limpieza IA** | Mantén **⌘ derecha** → mismo flujo, y un LLM local arregla puntuación y quita muletillas |
| **Historial** | Clic en el micrófono de la barra de menú → últimos 10 dictados con botón de copiar |
| **Log** | Cada dictado se agrega a `~/Dictation/YYYY-MM.md` con fecha y hora |

- La transcripción corre **100% local** con whisper.cpp (acelerado por Metal). Tu audio nunca sale de la Mac. Por defecto el dictado se pega **exactamente como lo dijiste** — sin red, sin procesamiento.
- Los audios se **borran inmediatamente** después de transcribir. Sin cuentas, sin telemetría, sin STT en la nube.
- **La limpieza IA es opt-in explícito** (apagada por defecto): al activarla en Ajustes, el texto ya transcrito se envía a una API compatible con OpenAI (OpenAI, OpenRouter, Groq…) con Anthropic de respaldo, usando tu llave en `~/.config/voza/.env`. Nunca el audio, nunca sin el switch.
- **Preset automático para tu Mac y tu idioma**: Voza elige un modelo multilingüe por defecto y solo usa uno optimizado para inglés cuando tu idioma de dictado es inglés. Descargas verificadas con SHA-256.
- UI bilingüe EN/ES.

### Permisos que macOS pedirá (primera vez)

1. **Micrófono** — para grabar tu voz.
2. **Accesibilidad** — para pegar el texto en la app enfocada.
3. **Input Monitoring** — para detectar las teclas Option / ⌘ derecha globalmente.

Si negaste alguno por accidente: Ajustes del Sistema → Privacidad y seguridad → Micrófono / Accesibilidad / Input Monitoring → activa **Voza**.

### Compilar y correr

```bash
swift build && ./build.sh && open build/Voza.app
```

---

<div align="center">

**Why $29 and not $249?** Because transcription is a commodity — the value is the polish. Voza is the affordable, private, one-time option. / **¿Por qué $29 y no $249?** Porque la transcripción es commodity; el valor está en el pulido.

MIT © 2026 [Jerónimo Rey](https://github.com/Jerotheking) · [Gumroad](https://jerotherey.gumroad.com/l/voza)

</div>
