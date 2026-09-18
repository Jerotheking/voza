# Auditoría de calidad con skills de Matt Pocock — Voza

*2026-09-18 · Metodología: `code-review` (smell baseline de Fowler), `codebase-design` (módulos profundos: depth/seam/leverage/locality), `tdd` (verificación por fase). Skills instaladas en `~/Developer/sintelia/skills/matt/` (29, desde github.com/mattpocock/skills).*

## Alcance
Inventario completo: 30 archivos Swift (~5,500 LOC) + smoke + tests. Hot spots por historial git: `MLXEngine`, `CorrectionWatcher`, `Cleaner`, `LearningLog`.

## Hallazgos y acciones

| # | Hallazgo | Severidad | Acción |
|---|----------|-----------|--------|
| 1 | 4 símbolos muertos: `ModelManager.resolvedModelPath`, `Config.setLogDirectory`, `Config.setenvOverride`, `Config.setGumroadPermalink` (verificados contra Sources+Tests+Smoke: cero usos) | Baja (ruido) | Eliminados |
| 2 | `LearningLog.timestamp()` construía un `DateFormatter` por evento (expensive; ráfagas de polls del watcher) | Media (perf) | Formatter cacheado `static let` |
| 3 | `TranscriptEntry`: `timeLabel`/`dayLabel`/`parseEntries` construían formatters por llamada (por fila de historial renderizada) | Media (perf) | 3 formatters cacheados compartidos |
| 4 | Duplicación temida watcher/store del extractor (D035) | — | **Falso positivo**: ya delega a las mismas funciones puras (`wordLevelPair`/`charLevelPair`) |
| 5 | Fugas de timers/observers | — | **Limpio**: `[weak self]` + `invalidate()` en AppState y HUD; sin observers colgados |
| 6 | Pipeline principal (AppState: transcripción detached, stores atómicos, prompt fuera del bloque RTF) | — | Sano, sin cambios |

## Verificación por fase
- Fase A (exploración): inventario + dead-symbol scan (script) + TODO/FIXME scan (**cero** activos).
- Fase B (edición): `swift build` 0 errores / 0 warnings.
- Fase C (optimización): build limpio + **101/101 tests** + smoke 54 checks + release.

## Estado
Sin cambios de comportamiento observables — solo eliminación de peso muerto y caching de formatters. D040 intacto.
