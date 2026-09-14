# Reporte de brechas de cobertura de pruebas — Voza

*2026-09-12 · Auditoría de Tests/VozaTests + VozaSmoke contra CODE-MAP.md y los módulos post-baseline. Solo diagnóstico: ningún test fue escrito ni modificado.*

## Metodología

1. Inventario completo de fuentes: 30 archivos Swift (~5,000 líneas; incluye 4 módulos **posteriores al baseline del CODE-MAP**: `CorrectionWatcher`, `CorrectionStore`, `MLXEngine`, `DictationHUD`).
2. Inventario de aserciones: **34 tests XCTest** (663 líneas en 5 suites) + **128 checks del smoke hermético** (`VozaSmoke`, corrido por CI en su modo default y `v01`).
3. Cruce símbolo-por-símbolo (grep dirigido por símbolo, no por archivo) contra ambas capas de prueba.

**Corrección a la conversación previa:** mi estimación inicial subestimó la cobertura real. La lógica pura del `CorrectionWatcher` (`extractPair`, `expectedField`) tiene **12+ casos adversariales en el smoke** — Unicode ES, edición fuera del paste, case-only, snapshot corrupto, campo vacío, reemplazo de selección, límite de tamaño, reset de estabilidad por undo. No era una brecha. Las brechas reales son otras y están abajo.

## Cobertura verificada (sin acción requerida)

| Módulo | Pinned por |
|---|---|
| Config (defaults, roundtrip, resolución, rutas QA, keep_alive, auto_learn) | ConfigTests (10) + smoke |
| TestEnvironment (aislamiento hermético V01) | TestEnvironmentTests (6) |
| Smoke: pureza/determinismo/aislamiento de perfil | SmokeIsolationTests (4) |
| Transcriber: argumentos beam-5 + prompt no vacío | ConfigTests (2) |
| ModelManager: catálogo, tiers por RAM/idioma, SHA-256 formato | ConfigTests (4) |
| Localizer, LicenseManager (reloj inyectado, trial sin sleep) | ConfigTests (3) |
| HUD: geometría de barras, dinámica VU, visibilidad por fase, render de vistas | PreviewRenderTests (7) |
| TranscriptStore: append/parse roundtrip | TestEnvironmentTests + smoke |
| Cleaner: `stripThinkingJunk`, cuerpo Ollama (keep_alive, num_predict), cadena de proveedores (5 asserts) | ConfigTests + smoke |
| CorrectionStore: record/persist/diff/prompt budget/orden/multi-lección | smoke (sección V01+) |
| CorrectionWatcher: lógica pura completa | smoke (12+ casos adversariales) |
| Paster: similitud, substring bounds | smoke |

## Brechas, ordenadas por riesgo

### R1 — Contrato del system prompt de limpieza (Alto)
**Archivo:** `Cleaner.swift:62` (`systemPrompt`, ~15 reglas). **Cubren:** nadie en tests; el smoke no lo toca.
**Por qué importa:** es la única implementación de tres features que salieron de debugging con el dueño (fillers ES, edit-commands "quita lo de X", preservación de proper nouns como "Type Whisper"). Todo texto es `static let` puro → hermético en una línea. **Probabilidad de regresión:** alta (cualquier edit de prompt pierde una regla sin que falle nada). **Costo de test:** trivial (aserciones de substring sobre constantes).
**Nota:** las pruebas de calidad contra modelo (live, Ollama/MLX) NO son reemplazo: validan una sesión, no invariantes permanentes.

### R2 — Contratos de la nube: `openAIClean` / `anthropicClean` (Alto)
**Archivo:** `Cleaner.swift:98,126`. **Cubren:** nada. Los builders de request y parsers de respuesta son puros salvo el `URLSession` (intercambiable en `Cleaner`? — verificar sesión inyectable al escribir el test).
**Por qué importa:** una rota no se nota hasta que un usuario paga y pone su API key; el fallback de D016 la enmascara como "salida cruda". Riesgo de revenue + confianza.CODE-MAP V24 (RewriteValidator) ya anticipa esta zona.

### R3 — `CorrectionStore.apply` / `diffCorrection` — núcleo del auto-learn (Alto)
**Archivo:** `CorrectionStore.swift:108,185`. **Cubren:** el smoke prueba `record`/`persist`/`initialPrompt` con fixtures sintéticos, pero la **aplicación** de lecciones sobre texto real (regex case-preserving, expansión a límites de palabra, caso ACUNCIADO del diff) solo está cubierta con un ejemplo feliz.
**Por qué importa:** es el código que reescribe cada dictado futuro. Un edge-case roto (palabra repetida, corrección que contiene a la original, Unicode) corrompe silenciosamente lo pegado — exactamente la clase de bug que el dueño no puede diagnosticar.

### R4 — MLXEngine: máquina de estado de residencia (Medio)
**Archivo:** `MLXEngine.swift:61-110`. **Cubren:** nada automatizable sin Metal (el contrato de evicción se verificó una vez a mano). Lo sí hermético y sin cubrir: `Model.rawValue` (los 2 IDs de HF son contratos de red), límites de `Config` (400 tokens/300 s = decisiones D023/D024 registradas), el corte defensivo de `<end_of_turn>` (lógica de string, extraíble a función pura).
**Por qué importa:** un typo en un repo ID no falla hasta el primer cleanup de un usuario nuevo (D016 lo degrada a crudo silencioso). El corte defensivo hoy no es testeable como función pura — es inline en `complete`.

### R5 — `wavHeader` / `isNonSpeechMarker` / `medianRTF` / `requiredFreeMB` (Medio-bajo)
Funciones puras, triviales de testear, cero cobertura. Cada una protege una clase de bug ya vivida o anticipada (WAV malformado — explícitamente prohibido por CODE-MAP F06; marcadores de no-habla pegados; sugerencias de perf con mediana rota; readiness con presupuesto erróneo). Riesgo moderado porque son estables y pequeñas — pero su costo de test es de minutos.

### R6 — Periferia sin cobertura, riesgo bajo
- `BrewInstaller.brewPath` (candidato a eliminación en V16; no invertir).
- `HotKeyManager` — puro AX/CGEvent; el plan ya lo cubre con V03 (HotkeyBinding/HotKeyManagerTests). No duplicar antes del ticket.
- `Permissions`, `Paster.sendCmdV`, vistas SwiftUI (render smoke), `MLXBench`/`make-metallib.sh` (harness de aceptación, verificado por build/release).
- `VozaEntryPoint`, `Theme`, `Previews` — triviales o visuales.

## Resumen ejecutivo

- **R1, R2, R3** son las brechas que valen un ticket de endurecimiento: contratos de texto puro, baratos de hermetizar, con impacto directo en la calidad que el dueño ya percibe (Pulido) o en revenue (cloud keys).
- **R4–R5** son ganancias de consolidación, no urgencias.
- **R6** queda deliberadamente para sus tickets del plan (V03, V16).
- El CODE-MAP basline no conoce los 4 módulos post-baseline; cuando se regenere (V-siguiente), `CorrectionWatcher`/`CorrectionStore`/`MLXEngine`/`DictationHUD` deben entrar al mapa con sus tickets dueños (auto-learn vive entre V10/V25/V31 del plan).

**Recomendación:** un solo ticket "Harden: contratos de Pulido y aprendizaje" (R1+R2+R3, ~15 tests herméticos estimados) antes de V03. V03 después, sin duplicar hotkey tests que el propio ticket creará.

---

## Resolución (2026-09-12, misma sesión)

Ejecutado en un solo pase, con dos seams mínimos en producción:

- **R1 cerrado** — `CleanupContractTests` fija las 4 invariantes del systemPrompt (edit-commands, preservación de idioma, capitalización, anti-comentario) + que el prompt viaja en los 3 bodies de proveedor.
- **R2 cerrado** — refactor quirúrgico: `Cleaner.CloudRequest` + `openAIRequest`/`anthropicRequest`/`parseOpenAIResponse`/`parseAnthropicResponse` como funciones puras; los wrappers async solo hacen red. Tests: defaults, overrides (CLEANUP_MODEL/OPENAI_BASE_URL), fallback de baseURL malformada, parsers happy/vacíos/basura.
- **R3 cerrado** — `LearningAndPureFnsTests`: apply con case-shape, múltiples lecciones, no-reaplicación sobre su propio reemplazo, word boundaries, diff case-only, rechazo de inserciones/deletes/ids.
- **R4 cerrado** — corte `<end_of_turn>` extraído a `MLXEngine.cutTurnMarker` (puro, testeado); IDs de checkpoint QAT y límites D023/D024 (400 tokens / 300 s) fijados.
- **R5 cerrado** — wavHeader byte-a-byte (layout RIFF/WAVE IEEE-float mono), isNonSpeechMarker (incluido el guard de longitud), medianRTF (impar/par/<3) con TestEnvironment, requiredFreeMB (tamaño + margen, trunca).

Resultado: **64/64 XCTest** (antes 34), smoke 56 checks puros en verde, v01 mode verde, validador del plan verde. R6 queda para sus tickets dueños (V03/V16) como se documentó.
