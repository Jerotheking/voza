# Voza — Design Spec: Adaptive UX & Zero-Config Settings
*Fase 0.5 (polish pass). Companion to docs/market-analysis.md. English copy shown; every string has an ES twin via `L.t`.*

## Principles

1. **Zero-config default.** A fresh install must reach working dictation with zero decisions. Everything has a sane, hardware-aware default; Settings *explains* what was chosen and why, it never demands choices.
2. **One home screen.** The first Settings tab is **Status**: either "everything ready" with a green hero, or the exact next fix with a one-tap button. Users never hunt through tabs to know if the app works.
3. **Measure, don't guess.** The install-time RAM heuristic picks the starting model; from then on Voza uses **runtime evidence** (real-time-factor of actual dictations) to suggest — never force — lighter or heavier models.
4. **Progressive disclosure.** Tab order: Status → Dictation (the 3 knobs people actually touch) → Models (with Automatic default) → Advanced (paths, sound, launch-at-login) → License → About. Power knobs live where power users expect them; normal users never need to open them.
5. **Explain every permission inline.** Each pending permission shows what it's for and a single button that opens the right System Settings pane or fires the OS prompt.
6. **Failures teach.** Errors carry the fix: binary missing → "Install for me (brew)" button; no disk space → says how much is needed; model too slow → shows the measured speed and the one-tap switch.

## Status home (settings hero card)

States, in priority order (first match wins):

| # | Condition | Hero | Primary button |
|---|---|---|---|
| 1 | Disk < 400 MB free and model download pending | "Not enough disk space" | none (info) |
| 2 | !micGranted | "Microphone needed" | Grant / Open Settings |
| 3 | !accessibilityGranted | "Paste permission needed" | Open Settings |
| 4 | whisper binary missing | "Speech engine missing" | Install with Homebrew (in-app, live log) |
| 5 | no model downloaded | "Download your voice model" | Download recommended |
| 6 | perf suggestion active | "Try a [lighter/heavier] model" | Switch now |
| 7 | all good | "Voza is ready" + green mic + machine label + current model | — |

Below the hero: readiness checklist chips (Mic · Paste · Engine · Model) with ✓/✗, and a compact "Recent transcriptions" list. Dictation still works during 4–7; only 1–3 block.

## Runtime self-tuning

- `PerformanceMonitor` records per-dictation **real-time factor** (audio seconds ÷ transcription seconds), keeping the last 20 samples per model, persisted to `~/.config/voza/perf.json`.
- Suggestions fire after ≥ 3 samples (suppressible, never twice in a row, never while recording):
  - median RTF > 0.5 → suggest the next lighter model ("transcription took longer than speaking").
  - median RTF < 0.08 **and** ≥ 32 GB RAM and not already on the heaviest → suggest heavier ("your Mac handles it easily").
- One-tap "Switch now" downloads (if needed), swaps the model, keeps the old one on disk. Dismiss = remember for 14 days per model direction.

## Model picker (Models tab)

- First row: **Automatic (recommended for this Mac)** — resolves to the hardware preset; selected by default.
- Downloaded models show measured median speed ("1.8× realtime on this Mac") when known.
- Rows: name, size, EN/multilingual badge, state (active / use / download %).
- All downloads show byte-level progress + **ETA**; blocked up-front with a clear message if disk < 400 MB free.

## Hardware preset (unchanged contract, explicit)

| RAM | Model | Rationale |
|---|---|---|
| < 14 GB | small.en-q5_1 (190 MB) | quantized: fast + accurate on base M-series |
| 14–30 GB | small.en-q5_1 | same — proven sweet spot |
| 30+ GB | large-v3-turbo (1.6 GB) | headroom for max accuracy |

## BrewInstaller (engine bootstrap)

- Detect `whisper-cli` at `/opt/homebrew/bin` and `/usr/local/bin`.
- Missing → one-tap install: `brew install whisper-cpp` streamed line-by-line into an activity sheet, then re-check. Requires brew present (`/opt/homebrew/bin/brew`); otherwise the card shows the manual command with copy button.
- Post-install: permissions re-check + Status re-evaluates.

## Non-goals (this pass)

Streaming partials (v1.1 overlay), per-app profiles (explicitly out of scope), custom vocabulary, model fine-tuning.
