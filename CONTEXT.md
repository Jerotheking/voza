# Voza

Local dictation for macOS: hold a key, talk, release, and your words appear
wherever the cursor is. 100% offline by default; no accounts, no telemetry.

## Language

Canonical language is **English** (universal product). Every user-facing string
has an ES twin via `L.t("...", es: "...")`; this glossary tracks the EN terms,
with the ES word where it helps. _Avoid_-lists are written in Spanish — that is
the language of the team, not the product.

Owner decisions (grilling round 1, 2026-09-21): product is English-first; the
doc example word is **Sintelia** (owner-confirmed); the Settings UI keeps
"AI cleanup" as the user-facing label.

### The dictation

**Dictation**:
The whole act: hold the Hotkey, talk, release, and see the text pasted into the
focused field. (ES: el dictado)
_Avoid_: grabación, transcripción (son partes del dictado, no el todo)

**Hotkey**:
The key you **hold down** to dictate (Option by default). Releasing it ends
recording.
_Avoid_: shortcut, atajo (un atajo se pulsa una vez; el Hotkey se sostiene)

**Transcript**:
The text whisper produces from the audio, before any correction.
_Avoid_: resultado, output

**Literal**:
Default mode: the Transcript is pasted as spoken. Nobody rewrites it.
_Avoid_: raw, plain (nombre de la clave en config.toml)

**AI cleanup**:
Opt-in mode: the Transcript goes through a cloud LLM (user's own API key)
before pasting. Without a key configured, it degrades to Literal and announces
it once (owner decision, grilling Q4).
_Avoid_: Pulido (descartado en la ronda 1 — el producto es English-first),
cleanup mode, polishing, limpieza

**HUD**:
Floating overlay showing dictation state (recording / transcribing) with live
voice level. The owner calls it "la muesca" informally.
_Avoid_: overlay, notch (apodo, no término)

**History**:
The recent dictations, browsable from the menu, with a copy button and the ✏️
manual-correction path. (ES: historial)
_Avoid_: log (reservado para Daily Log y Learning Log)

**Daily Log**:
Every dictation appended immediately to `~/Dictation/YYYY-MM.md` with a
timestamp. Never deleted.
_Avoid_: historial (es el History), backup

### The learning

**Lesson**:
A learned pair: what whisper heard wrong → what the user actually wrote.
Applied automatically in future dictations. (ES: lección)
_Avoid_: corrección (es el acto, no la lección), entrada, mapeo

**Heard**:
One side of a Lesson: what whisper produced (the misheard word).
_Avoid_: original, from, error

**Said**:
The other side of a Lesson: what the user typed when correcting (the true
word).
_Avoid_: corrección, to, target

**Dictionary**:
The persistent set of Lessons (`~/.config/voza/corrections.json`). The single
mechanism by which dictation improves with use.
_Avoid_: vocabulario, base de datos, cache

**Auto-learn**:
Automatic capture of a Lesson: Voza watches the pasted field during the
Correction Window and learns from the user's typing. Can be disabled in
Settings.
_Avoid_: watching, monitoreo

**Correction Window**:
The ~20 s after a paste during which a user edit may become a Lesson. At most
one Lesson per paste.
_Avoid_: timeout, polling

**Confirmation read**:
A second read of the field after a pause: if it kept changing, the user was
still typing (accent menu, IME) and it is NOT time to learn (D036).
_Avoid_: double read, re-check

**Late-baseline**:
Learning mode for Electron/Chromium apps that don't expose their accessibility
tree at paste time: the "before" snapshot is taken AFTER the paste, once the
tree is awake.
_Avoid_: fallback mode, modo Electron

**Wake**:
Activating a Chromium app's accessibility tree via attributes on its web
areas. Attributes only: never launches VoiceOver, never posts keystrokes,
never touches audio (owner decision, D040).
_Avoid_: toggle VO, lanzar VoiceOver, forcing

**Learning Log**:
`~/Library/Logs/voza/learning.log` — one event per learning session
(start / learned / expired / ax-never-woke). The source of truth for
diagnosing why something didn't learn. (ES: bitácora)
_Avoid_: log de la app, consola

### The machine

**Model**:
A downloadable whisper from the catalog, verified by SHA-256. The preferred
one lives in config; if it isn't downloaded, the Fallback enters.
_Avoid_: LLM (no hay LLM en el camino por defecto), red neuronal

**Fallback**:
The downloaded Model used when the preferred one is unavailable. Announced in
Status, never fails silently.
_Avoid_: default (el default es el preferido elegido por adaptación)

**RTF**:
Real-time factor: seconds of transcription per second of audio. The
Performance Monitor records it per dictation.
_Avoid_: velocidad, latencia

**Hardware adaptation**:
Choosing the defaults (Model, RAM budget) based on the user's Mac, and
**explaining** them in Settings instead of demanding decisions.
_Avoid_: auto-tuning, presets (fuera de alcance del producto)

**Smoke**:
The hermetic verification binary (VozaSmoke): pure checks with no microphone,
no Model, no real profile. Must pass before any release.
_Avoid_: e2e, integration test

**Hermetic**:
Property of a test that touches nothing real: no accessibility, no keyboard
events, no log, no user profile. A living rule of the project.
_Avoid_: mockeado, aislado

**Sintelia**:
The canonical example word: any doc, test or lesson demo that needs a sample
word uses it (owner decision, grilling Q5). Lives in the repo as a real
Lesson.
_Avoid_: "foobar", "ejemplo", "xyz"

---

Owner decisions live in `docs/plan-glm/DECISIONS.md` (D001–D040); grilling
rounds, in `docs/plan-glm/GRILLING.md`. The code map, in
`docs/plan-glm/CODE-MAP.md`.
