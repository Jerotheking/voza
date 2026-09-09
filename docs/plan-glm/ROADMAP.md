# Roadmap ejecutable y dependencias

## 1. Presupuesto corregido al detallar el plan

[ASSUMED] Los 30 tickets comprometidos suman **54 días de ingeniería**; V31/V32 son backlog y suman 5 días orientativos adicionales de definición/implementación si se autorizan. Es una estimación por tareas, no una fecha garantizada. El informe histórico estimaba 35–42 días: el desglose amplió aislamiento, corpus, seguridad, UI y validación; prevalece este presupuesto operativo.

A 28 h/semana de ingeniería son aproximadamente 15,4 semanas para 54 días de 8 h, antes de bloqueos externos. Con 8 h QA y 4 h mercado/operación semanales, se mantiene un presupuesto personal de 40 h. A 24 h de ingeniería/semana serían unas 18 semanas. **No prometer 1.0 en 90 días** por copiar el calendario original. En 13 semanas a 28 h caben 45,5 días de ingeniería: objetivo orientativo G3, condicionado a evaluación humana/hardware; G4/G5 pueden quedar después.

Los tiempos de V27/V30 incluyen trabajo técnico de verificación/protocolo; disponibilidad de hardware, humanos, cuenta Apple o compradores puede añadir espera. Un gate no se aprueba por haber llegado al día del calendario.

## 2. Secuencia y ownership

Cada ticket contiene lecturas, archivos, pasos, pruebas, cinco AC, límites y cierre. PLAN.json es la fuente; tickets Markdown y maestro son derivados. STATE.json es ejecución. No marcar checkboxes de estado aquí.

| Ticket | Trabajo | Dependencias | Gate | Días ingeniería |
|---|---|---|---|---|
| [V01](tickets/V01.md) | Aislar rutas, preferencias y reloj antes de ejecutar pruebas | ninguna | G0 | 1.5 |
| [V02](tickets/V02.md) | Reparar XCTest, hacer Smoke hermético y establecer CI | V01 | G0 | 1.5 |
| [V03](tickets/V03.md) | Corregir atajos y modelar la tecla dueña de la sesión | V02 | G0 | 1 |
| [V04](tickets/V04.md) | Crear ProcessRunner cancelable sin deadlock de pipes | V02 | G0 | 2 |
| [V05](tickets/V05.md) | Asegurar captura, escritura WAV y cleanup de recursos | V04 | G0 | 2 |
| [V06](tickets/V06.md) | Definir contratos de sesión y composición inyectable | V02, V05 | G0 | 1 |
| [V07](tickets/V07.md) | Integrar pipeline con sesión única y descarga independiente | V03, V04, V05, V06 | G0 | 1.5 |
| [V08](tickets/V08.md) | Proteger campos seguros, bloqueo y cambios de foco | V07 | G1 | 2 |
| [V09](tickets/V09.md) | Hacer inserción y clipboard recuperables y no bloqueantes | V08, V04 | G1 | 2 |
| [V10](tickets/V10.md) | Implementar privacidad del historial y recuperación RAM | V09, V01, V06 | G1 | 2 |
| [V11](tickets/V11.md) | Migrar configuración a un esquema tipado observable | V01, V06 | G1 | 1.5 |
| [V12](tickets/V12.md) | Guardar credenciales en Keychain y fijar frontera de proveedores | V11 | G1 | 1 |
| [V13](tickets/V13.md) | Endurecer licencia offline-first con fixtures de respuesta | V11, V12 | G1 | 1.5 |
| [V14](tickets/V14.md) | Unificar catálogo, capacidad de idiomas y salida no lingüística | V11, V06 | G1 | 1.5 |
| [V15](tickets/V15.md) | Descargas verificadas, resume correcto y disco del destino | V14, V04 | G1 | 2 |
| [V16](tickets/V16.md) | Empaquetar motor y dependencias sin requerir Homebrew | V14, V04 | G2 | 2.5 |
| [V17](tickets/V17.md) | Unificar readiness y publicación observable de resultados | V07, V08, V09, V15, V16 | G2 | 1.5 |
| [V18](tickets/V18.md) | Introducir UI Literal/Pulido y ajustes por intención | V17, V11, V06, V03 | G2 | 2 |
| [V19](tickets/V19.md) | Construir onboarding de cinco pasos con primera dictación | V18, V17, V16 | G2 | 2 |
| [V20](tickets/V20.md) | Panel visible de grabación y accesibilidad completa | V18, V19 | G2 | 1.5 |
| [V21](tickets/V21.md) | Construir corpus bilingüe independiente para Pulido | V06 | G3 | 2 |
| [V22](tickets/V22.md) | Seleccionar motores por benchmark y licencia, no intuición | V21, V04, V14, V16 | G3 | 2 |
| [V23](tickets/V23.md) | Integrar runtime de Pulido local administrado por Voza | V22, V15, V16 | G3 | 2 |
| [V24](tickets/V24.md) | Validar reescritura, autocorrecciones y abstención | V23, V21 | G3 | 2 |
| [V25](tickets/V25.md) | Completar Literal/Pulido, fallback honesto y reversión segura | V24, V18, V09, V10, V12 | G3 | 2 |
| [V26](tickets/V26.md) | Adaptar recursos automáticamente sin cambiar intención | V25, V14, V05 | G3 | 1.5 |
| [V27](tickets/V27.md) | Ejecutar matriz adversarial y compatibilidad de apps | V19, V20, V25, V26, V13, V15 | G4 | 3 |
| [V28](tickets/V28.md) | Firmar distribución, updater y rollback verificable | V27, V16, V13 | G4 | 2.5 |
| [V29](tickets/V29.md) | Cerrar decisiones comerciales y alinear claims con evidencia | V27 | G4 | 1.5 |
| [V30](tickets/V30.md) | Ejecutar beta y decidir continuar con métricas honestas | V28, V29 | G5 | 2 |
| [V31](tickets/V31.md) | Backlog condicionado: vocabulario y preferencias por aplicación | V30 | BACKLOG | 4 |
| [V32](tickets/V32.md) | Backlog condicionado: parciales, traducción y comandos; Windows fuera | V30 | BACKLOG | 1 |

## 3. Hitos acumulados

| Gate | Incremento estimado | Acumulado | Resultado |
|---|---|---|---|
| G0 | 10.5 d | 10.5 d | Núcleo aislable y sesión cancelable |
| G1 | 13.5 d | 24 d | Privacidad/destino/archivos/licencia/modelos fiables |
| G2 | 9.5 d | 33.5 d | Preparación sin brew, dos modos visibles y onboarding accesible |
| G3 | 11.5 d | 45 d | Pulido bilingüe validado, recuperación y adaptación |
| G4 | 7 d | 52 d | Compatibilidad/release/claims |
| G5 | 2 d | 54 d | Beta y decisión comercial |

## 4. Calendario de 13 semanas, condicionado

| Semana | Prioridad técnica | Actividad paralela humana/comercial |
|---|---|---|
| 1 | V01/V02: aislamiento y suites | Confirmar disponibilidad de equipos y horas |
| 2 | V03/V04 | Lista de apps y dialectos del ICP |
| 3 | V05/V06/V07: captura y pipeline | Reclutamiento autorizado para pruebas futuras |
| 4 | V08/V09: destino y clipboard | Protocolo de privacidad/consentimiento |
| 5 | V10/V11: historial/config | Revisar compradores y términos previos |
| 6 | V12/V13/V14: keys/licencia/política | Entidad de cobro y nombre: decisión pendiente |
| 7 | V15/V16: descarga/bundle | Preparar máquina limpia y artefactos QA |
| 8 | V17/V18: readiness/UI | Prueba de comprensión de dos modos |
| 9 | V19/V20: onboarding/panel | Observar primer uso y VoiceOver |
| 10 | V21: corpus; preparar V22 | Revisores humanos ES/EN/mixed |
| 11 | V22/V23: benchmark/runtime | Registrar NO_GO si no hay candidato viable |
| 12 | V24/V25: validación y recuperación | Validar utilidad/tiempo hasta texto aceptable |
| 13 | V26 y revisión G3 si hay evidencia | Replanificar G4/G5 con resultados reales |

El calendario es aproximado: seguir dependencias de PLAN, no forzar el ticket de la semana. V21 puede investigarse antes con archivos disjuntos si la sesión lo autoriza; no se paralelizan agentes automáticamente. V16 pertenece G2 pero es dependencia de V17. G0–G5 exigen todos sus tickets y evidencias de QA.

## 5. Primeras sesiones: instrucciones concretas

1. Sesión V01: encontrar escrituras implícitas; preparar AppPaths/TestEnvironment; no correr Smoke original. Salida: inicialización pura y cierre que indique componentes migrados y pendientes.
2. Sesión V02: reparar target/test signatures; aislar Localizer/perf/history; correr build/tests donde exista Xcode; CI sin recursos del Mac del propietario.
3. Sesión V03: constantes correctas y reducer de teclas; fixture protege 0x3D/0x3E; QA física separada.
4. Sesión V04: runner con productores finitos, drenaje, timeout y cancel; transcriber conserva flags sin llamada global a config en background.
5. Sesión V05: recorder lifecycle/escritor/frames/header; fallos de start/disk no dejan recursos.
6. Sesión V06: value types y composición, sin otro pipeline operativo. Depende de V05 para reutilizar AudioAsset sin duplicación; no adelantarlo antes de que exista ese contrato.
7. Sesión V07: integrar actor/session ID; reproducir downloadFailed/listening y resultados tardíos con fakes antes de ir a UI.

Estas son unidades retomables, no turnos artificiales de “plan primero, vuelve mañana”. Un agente autorizado completa su ticket y cierra estado con evidencia; si interrumpido deja el próximo paso exacto. No salta a otra función porque compile.

## 6. Cómo cambiar el plan sin perder continuidad

Agregar ticket nuevo a PLAN con ID nuevo, dependencias y AC. Crear su entrada STATE en todo o deferred. Actualizar CODE-MAP y contratos afectados. Ejecutar build/validate; registrar decisión que motivó el cambio. No reutilizar IDs borrados ni renumerar sesiones antiguas.

Si una tarea se divide, mantener el ticket anterior con alcance histórico y decisión de sustitución; no marcarlo done hasta satisfacer o reemplazar formalmente sus AC. Si un AC deja de aplicar, registrar razón/decisión, no convertir NOT_RUN en PASS.

## 7. Reglas de evidencia de estado

- todo: nadie ejecutó ni reclamó trabajo; que el archivo de ticket exista no cambia eso.
- in_progress: actor/session/branch/base/worktree registrados; dependencias done.
- blocked: causa concreta, trabajo preservado y próxima condición; no expiry automático del owner.
- review: implementación y cierre disponibles; puede haber QA pendiente, no equivale a integrado.
- done: commit integrado, revisión registrada y cada AC PASS para esa revisión con evidencia persistente.
- deferred: no pertenece al compromiso; solo decisión explícita habilita iniciar.

El validador comprueba estructura y disponibilidad de archivos; **no autentica la evidencia ni decide si un resultado humano fue verdadero**. El integrador contrasta source/diff/log/artefacto y publica estado honesto.
