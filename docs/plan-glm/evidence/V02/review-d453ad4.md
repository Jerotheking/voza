# Evidencia de review — V02 @ d453ad4

- Revisor: buffy (owner-authorized in-session review, 2026-09-09)
- HEAD: d453ad439d9c73b652ecffbfdcd43cb3f304f4f9 (branch codex/voza-V02-xctest-ci)
- Entorno: macOS 26.6.2 (Apple Silicon), Xcode 26.6 (17F113) vía DEVELOPER_DIR, whisper-cli presente, modelos descargados presentes en directorio real.

## V02-AC01 — swift test compila y ejecuta fixtures aislados; 0 llamadas sin language

Comando (cwd ~/Developer/voza):
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
grep -rn "recommendedModel()" Sources Tests
```
Resultado: `Executed 20 tests, with 0 failures (0 unexpected) in 1.1 s` — suites: AppPathsTests (3), ConfigTests (8, reescrito), SmokeIsolationTests (3, nuevo), TestEnvironmentTests (6). El grep devuelve solo un comentario de documentación; **0 llamadas reales** a la sobrecarga eliminada.

## V02-AC02 — Smoke por defecto determinista sin modelos/whisper-cli/mic

Comando: `.build/debug/VozaSmoke`
Resultado: exit 0, banner `PURE checks only (hermetic, V02)`, `All pure smoke checks passed (55 checks, 3 skips)`. Los 3 SKIPs son opt-ins declarados (resolvedModel-fallback, history-writability, mic). El modo puro no requiere whisper-cli ni modelos (la única sección que los usaba quedó tras `integrationGuard`); sin grabación de audio (mic tras flag). Determinismo: sin sleeps ni red (TestEnvironment/SmokeQA con reloj fijo).

## V02-AC03 — Repetir la suite no cambia el perfil real

Comando (dos corridas consecutivas):
```
H=$(git status --porcelain; defaults read com.apple.universalaccess | shasum; ls ~/Dictation | shasum)
.build/debug/VozaSmoke; .build/debug/VozaSmoke
H2=... (misma recomposición)
[ "$H" = "$H2" ]
```
Resultado: `AC03: tree+history stable across repeats`. Además, el test `testRepeatedRunsLeaveProfileUntouched` (SmokeIsolationTests) compara bytes de config.toml/perf.json/listado de ~/Dictation antes y después de 2 corridas. Teardown de QA verificado con centinela hermano (v01 y TestEnvironmentTests).

## V02-AC04 — CI ejecuta build/test, sin release/descargas/datos

Inspección de `.github/workflows/ci.yml` @ d453ad4: runner `macos-15`, `xcode-select` a Xcode 16.4 (pin), pasos: `swift build`, `swift test`, `swift run VozaSmoke` (puro), `swift run VozaSmoke v01`. No hay `build.sh release`, ni descarga de modelos, ni capture de micrófono, ni secretos/red a proveedores. Confirmación definitiva pendiente de la primera corrida del runner tras push (registrada en Próximo paso del cierre).

## V02-AC05 — SKIPs identificados; ningún SKIP cuenta como PASS

Evidencia: resumen `55 checks, 3 skips` cuenta PASS y SKIP por separado; cada SKIP imprime su bloqueador exacto y el flag que lo habilita. Test automatizado `testSkipIsNeverCountedAsPass` valida que el conteo del resumen coincide con las líneas `[PASS]` y que todo `[SKIP]` aparece contabilizado.

## Bugs reales encontrados durante V02 (no conocidos al abrir el ticket)

1. `PerformanceMonitor.save()` no preparaba AppSupport → primer `record()` perdía perf.json silenciosamente (cazado por `perf file confined to QA root` en el smoke puro). Fix: `prepareAppSupport()` antes de escribir.
2. `Tests/VozaTests/Support/TestEnvironment.swift` usaba `XCTAssertTrue` sin `import XCTest` — la suite completa llevaba sin compilar desde V01, sin que nadie lo notara (F10 confirmado en la práctica).
3. `ConfigTests` llamaba una sobrecarga `recommendedModel()` inexistente y mutaba `L.override` + escribía en ~/Dictation real — reemplazo integral.
