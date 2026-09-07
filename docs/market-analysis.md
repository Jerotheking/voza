# Voza — Market, Competition & Pricing Analysis
*Research date: September 2026. Prices verified against vendor pages and third-party comparison sites; [V] = verified via live source.*

## 1. Competitive landscape

| App | Model | Price [V] | Engine | Core weakness |
|---|---|---|---|---|
| **Superwhisper** | Sub + lifetime | $8.49/mo · $84.99/yr · $249.99 lifetime | Whisper local + cloud | Lifetime price jumped from ~$69 → $249.99; visible backlash on r/superwhisper & r/macapps |
| **Wispr Flow** | Sub only | $15/mo ($12 annual), free tier 2k words/wk | Cloud | No lifetime; audio leaves the machine; ~$900 over 5 years |
| **MacWhisper** | One-time | €59–64 (Gumroad) · $99.99 App Store | Whisper local | File-transcription DNA; dictation secondary; confusing multi-tier pricing |
| **VoiceInk** | OSS + paid binary | $0 build it · $25–49 binary | Whisper local (Metal) | macOS-only, single maintainer, manual model setup |
| **TypeWhisper** | OSS core | Free core, paid add-ons | Swappable engines | New (1.0 in Mar 2026), small installed base |
| **Handy** | OSS | $0 (Rust + whisper.cpp) | Local | Unsigned builds → Gatekeeper friction; barebones UX |
| **OpenWhispr** | OSS (MIT) | Free + managed cloud option | Local + cloud | Unclear monetization story |
| **Voibe** | Sub + lifetime | $7.50/mo · $59/yr · $99–149 lifetime | Local | Newer brand, higher price than mid-tier |
| **Spokenly** | Free + Pro | $0 local + BYOK · $99.99/yr Pro | Local + cloud | Pro features behind subscription |
| **Apple Dictation** | Bundled | $0 (Tahoe ships on-device models) | Apple on-device | No AI cleanup, no history, no control, no presets |

## 2. The niche (evidence)

1. **Price is the #1 public complaint** — recurring Reddit threads on r/macapps, r/LocalLLaMA, r/superwhisper asking for cheaper/open alternatives; "SuperWhisper open source alternatives?" is a recurring LocalLLaMA post.
2. **The proven one-time sweet spot is $25–39**: VoiceInk sells at $25–39 (Wirecutter lists it as the $25 one-time option), Fluidvox/Embertype at $39. Above $50 you meet MacWhisper's €59 brand equity; below $20 money is left on the table.
3. **People don't pay for transcription — it's a commodity** (whisper.cpp is MIT, free, Metal-fast). They pay for *packaging*: install → works → pastes reliably → permission onboarding that doesn't lose them.
4. **Apple is the real long-term threat** (Tahoe built-in dictation), not competitors. Defensible ground: AI cleanup + full control + fair price — things Apple won't provide.

## 3. Voza's positioning

> **"Dictate. It pastes itself. Pay once."** — 10% of Superwhisper lifetime, zero subscriptions, 100% local.

- **Price**: **$29 launch (first ~200 licenses) → $39 regular.** Gumroad (~10% fee) → ~85% margin. Fixed costs: Apple Developer Program $99/yr.
- **Distribution** (VoiceInk playbook): public MIT repo (marketing engine: GitHub/Reddit/HN) + paid notarized binary (Gumroad) + Homebrew cask.
- **Conversion hooks**: comparison table on the landing ("dictation tax"), founder pricing with deadline, "it doesn't paste, you don't pay" guarantee, bilingual EN/ES from day 1 (nobody else targets the Spanish-speaking macOS power user).
- **Cleanup economics**: local Ollama default → $0 inference cost per user, structurally impossible for cloud-dependent competitors to match without margin loss.

## 4. Moat & risks (honest)

| Risk | Severity | Mitigation |
|---|---|---|
| Apple ships AI cleanup in dictation | High | Move up-stack: presets, command dictation, multi-model (Parakeet) |
| Free OSS rivals improve UX | Medium | Speed of iteration + brand + notarized distribution + bilingual niche |
| Superwhisper cuts price | Medium | Their sub-revenue incentive conflicts; we win on one-time principle |
| Parakeet-class models obsolete Whisper v1 | Medium | Already scoped: brew whisper-cpp ships `parakeet-cli`; phase 2 swaps engine behind same UI |
| Single-founder bus factor | Real | MIT license + docs mean the community can fork and live |

## 5. Roadmap tie-in

- **v1.0 (this release)**: push-to-talk, cleanup, history, licensing, release pipeline.
- **v1.1**: floating live overlay, per-model A/B, Parakeet engine toggle.
- **v1.2+**: command mode ("new line", "delete that"), multi-lingual auto-switching, Gumroad webhooks for license updates.
