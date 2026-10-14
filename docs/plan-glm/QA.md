# QA, evidencia y gates

> **Palanca canónica de verificación (`D055` / `D056`):** Ejecutar `./scripts/verify.sh` desde la raíz del repositorio. Este script selecciona automáticamente un SDK compatible (`MacOSX15.2.sdk`) para evitar el fallo de `dyld` / `MacOSX27.0.sdk` de CommandLineTools, compila `VozaKit` y `VozaSmoke` sin warnings, corre las 3 suites herméticas (`default`, `v01`, `corrections` — 129 checks) y ejecuta `python3 -B docs/plan-glm/tools/plan.py validate`.

Estado inicial: ningún gate de producto PASS. [evidence/baseline.json](evidence/baseline.json) prueba qué archivos se auditaron, no que la app funcione.

## 1. Pruebas herméticas antes de ejecutar suites

El Smoke baseline cambia UserDefaults y perf.json y puede grabar audio. XCTest escribe historial. No ejecutarlos sobre el perfil real para “comprobar rápido”. V01 prepara AppPaths/defaults inyectados; V02 adapta todos los tests y Smoke, y separa modos manuales opt-in.

Rutas QA: un directorio temporal propio por test, eliminable únicamente por el test que lo creó; snapshot de rutas reales antes/después sin leer secretos. UserDefaults suite aleatoria aislada, restaurada/eliminada solo esa suite. No repurpose HOME, CODEX_HOME o env global del usuario. El aislamiento debe venir de dependencias, no solo de cambiar HOME.

Clock inyectado, URLProtocol/transport fixture para red, procesos locales sintéticos sin contenido real. No compruebes “existe engine/modelo en mi Mac” como condición de un unit test universal. Marcar integración local manual separada. CI usa toolchain fijado y Xcode disponible; no asumir que CommandLineTools incluye lo necesario para XCTest.

## 2. Matriz por riesgo

| Familia | Automatización requerida | QA nativa adicional |
|---|---|---|
| Hotkey | Secuencias derecha/izquierda/ambas/release perdido, debounce y dueño de sesión | Teclado Apple y externo, Input Monitoring denegado |
| Audio | Header, frames, rollback, escritor fallido y cancel idempotente | 44,1/48 kHz, mic interno/USB/Bluetooth, desconexión |
| Process | 1 MB stdout/stderr, timeout, SIGTERM ignorado, cancel doble, output inválido | whisper-cli empaquetado con sample público local |
| Session | downloadFailed durante listening, resultado viejo después de cancel, cambio de settings | Bloqueo/sleep/wake mientras habla/procesa |
| Insertion | Destino estable/cambiado/unknown/secure, receipt y clipboard falso | TextEdit, Notes, browser text area, editor Electron, chat, terminal de prueba |
| History | Off no writes, TTL, retención, import, errores y fechas/headers especiales | Migración con copia QA de logs autorizados |
| License | 200 válida, 404 inválida documentada, 429, 5xx, {}, corrupta, refund/dispute | Sandbox/test purchase solo autorizado |
| Download | 200/206/416 con HTML, offsets erróneos, truncado, hash, volumen unknown | Cortar red solo en perfil QA; no requerir descarga real en unit suite |
| Pulido | Corpus semilla, finish reason, identidad de output, cifras/negación/injection | Evaluación humana separada ES/EN/mixed |
| Release | Checksum/version/metadata, validación de firma | Mac limpio sin Homebrew, Gatekeeper/update/rollback |

## 3. Diez escenarios mínimos

1. Input Monitoring denegado: UI explica o permite botón; no ready falso.
2. Campo contraseña: captura, cloud, historial y pegado bloqueados cuando es detectable; unknown no simula seguro.
3. Clipboard manager: múltiples ítems y copia concurrente; documentar que restaurar no borra la copia del gestor.
4. Red caída en licencia: indeterminate conserva entitlement válido.
5. Descarga 90% interrumpida: parcial reutilizable; protocolo validado.
6. Pulsaciones rápidas y simultáneas: una sesión y dueño de stop.
7. Bloqueo de pantalla: invalidación antes de resultados tardíos; sin texto al desbloquear.
8. Reset permisos con tccutil: SOLO perfil QA autorizado; recuperación real.
9. Silencio/ruido: no alucinación pegada; bracket content legítimo conservado.
10. Equipo no soportado/sin brew: incompatibilidad o instalación empaquetada explicada antes de permisos/compra.

## 4. Corpus Pulido y benchmark

`fixtures/polished-seed.json`: sintético, editable solo como contrato; no fingir audios ni humanValidated. V21 construye 200 casos revisados (80 ES, 80 EN, 40 mixtos); separa desarrollo y holdout antes de ajustar prompt. Cada caso: ID estable, locale, rawTranscript, outputs permitidos, mustPreserve, forbiddenChanges, categoría, origen/licencia, revisión humana, split. No subir textos del historial por comodidad.

Medir dos capas: texto→Pulido a partir de transcript controlado; audio→STT→Pulido a partir de audio consentido/público. No atribuir un fallo ASR al procesador ni ocultarlo en media global. Reportar tasa de abstención/fallback, error crítico, aceptación humana, latencia cold/warm, memoria máxima y tamaño de assets por hardware/OS. No usar “texto distinto” como éxito: puede estar peor.

Gate semántico propuesto: cero inversiones de negación, hechos/cifras/destinatarios inventados o truncamientos aceptados en el holdout; ≥95% aceptación humana no crítica; ausencia de instrucciones dictadas obedecidas. Si falla ES, no compensar con EN. P95 objetivos 1,5 s Literal/4 s Pulido en frases de 5–15 s son hipótesis a validar, no SLA. Si no se alcanzan, registrar y replantear, no remover muestras difíciles.

## 5. Gates de entrega

| Gate | Tickets previos | Evidencia adicional | No significa |
|---|---|---|---|
| G0 — núcleo aislable | V01,V02,V03,V04,V05,V06,V07 | Fixtures y build/tests del HEAD revisado | Producto distribuible |
| G1 — confianza local | V08,V09,V10,V11,V12,V13,V14,V15 | Seguridad, escritura, licencia y descarga; manual nativo registrado | Pulido aprobado |
| G2 — experiencia automática | V16,V17,V18,V19,V20 | Onboarding sin brew, estados y accesibilidad real | Semántica bilingüe demostrada |
| G3 — Pulido | V21,V22,V23,V24,V25,V26 | Holdout humano, memoria/latencia y fallback por equipo | Garantía universal de sentido |
| G4 — candidato distribuible | V27,V28,V29 | Compatibilidad, firma/ticket/update, claims y decisiones comerciales | Publicación autorizada |
| G5 — beta y decisión comercial | V30 | Beta consentida, funnel comercial y soporte medido | Product-market fit |

Los gates son juicios con evidencia humana/artefactos, no flags que el validador de documentos pueda aprobar. Registrar resultados en un cierre de gate, con SHA de binario, HEAD, equipo y fecha. No usar hash de source como hash del DMG.

## 6. Evidencia persistente

Guardar en `evidence/<ticket>/<session>/` logs redactados, resultados JSON y protocolos manuales. Nunca logs con texto de usuario, license key, emails, clipboard o variables env completas. Cada resultado indica synthetic/manual/native/external-source, comando completo, exit, versión, SHA y límites. Para grandes artefactos no sensibles, manifest con ruta/hash y disponibilidad; no decir “adjunto” si vive en un /tmp que desaparecerá.

Campos mínimos al cerrar un AC: status, evidence paths, verified_at, verified_by, code revision y kind. `PASS` es solo de ese criterio bajo ese entorno. `NOT_RUN` no pasa a PASS por falta de hardware. El revisor puede ser el mismo agente en una sesión separada si no se pidió independencia; debe decirlo, no inventar revisión externa.

## 7. Verificación del paquete documental

`python3 -B docs/plan-glm/tools/plan.py validate` verifica referencias, DAG, IDs, estado y contenido derivado. `baseline` compara los hashes originales. `selftest` comprueba que el validador rechace ciclos/dependencias falsas/estados done sin evidencia, en memoria. Ninguno ejecuta la app ni aprueba gates.
