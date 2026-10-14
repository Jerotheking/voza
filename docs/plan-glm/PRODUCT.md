# Contrato de producto: Literal y Pulido

> **Nota de supersesión (`D032`, `D048`–`D051`):** El modo Pulido local (MLX/Ollama) fue eliminado en `D032` tras medir contención de GPU y swap en Macs reales. El modo predeterminado es **Literal** (100% local con `whisper.cpp` v1.9.4 + Metal embebido) enriquecido con **Auto-Learn local (`CorrectionWatcher` + `CorrectionStore`)**. El modo **AI cleanup (`cloud`)** es opt-in explícito con llaves en el Keychain de macOS (`V12`). Los tickets `V21`–`V25` están marcados como `deferred` en `STATE.json`.

Estado: diseño propuesto, salvo D001/D002 aceptadas. Leer [DECISIONS.md](DECISIONS.md) antes de tratar defaults propuestos como aprobaciones comerciales.

## 1. Trabajo del usuario

Hipótesis ICP: persona individual con Mac Apple Silicon que dicta mensajes, prompts y notas cortas en ES/EN, quiere evitar una suscripción y no desea administrar motores IA. Validar, no asumir mercado demostrado. La unidad de valor es texto aceptable en el destino elegido, con menos corrección y sin sorpresas de privacidad. RTF solo mide un tramo.

El usuario decide: Literal/Pulido, permisos, autorización de descargas, historial, y atajo si quiere modificarlo. Voza decide: motor/modelo compatibles, conversión, threads, preparación, reintentos, liberación de recursos y adaptación entre sesiones.

## 2. Contratos por modo

| Propiedad | Literal | Pulido |
|---|---|---|
| ID persistido | literal | polished |
| Etapa posterior al STT | Ninguna reescritura | Procesador local + validación |
| Muletillas | No borrarlas con un postprocesador | Eliminar solo si son muletillas en contexto |
| Autocorrecciones | Conservar lo reconocido | Resolver reparaciones claras |
| Negación/cifras/nombres | Conservar | Conservar salvo reparación explícita admisible |
| Tono | Texto ASR | Claridad manteniendo tono; no formalizar por defecto |
| Traducción | Nunca implícita | Nunca implícita |
| Fallo STT | No insertar; explicar | No insertar; explicar |
| Fallo de procesador | No aplica | Literal con indicador si política/destino lo permiten |
| Cambiar modo mientras trabaja | Aplicar al siguiente dictado | Aplicar al siguiente dictado |

PRD-M01: cualquier sesión debe llevar `requestedMode` fijo. PRD-M02: `appliedMode` y `processingStatus` describen lo ocurrido. PRD-M03: `didRewrite=false` con procesamiento exitoso es válido. PRD-M04: ningún fallback modifica la preferencia persistida del usuario. PRD-M05: mode selector y atajo deben apuntar al mismo modo canónico.

Copy canónico ES/EN:

- Literal: “Más rápido. Transcribe sin reescribir.” / “Faster. Transcribe without rewriting.”
- Pulido: “Elimina muletillas y mejora la redacción. Tarda un poco más.” / “Remove fillers and improve the wording. Takes a little longer.”
- Fallback: “Se usó Literal: Pulido no respondió.” / “Used Literal: Polished didn’t respond.”
- Sin reescritura necesaria: no mostrar error; estado aplicado Pulido, `didRewrite=false`.

## 3. Semántica de Pulido

S01: puede reparar “martes, perdón, jueves” → jueves. S02: no elimina “perdón por el retraso”. S03: no elimina negación ni incertidumbre. S04: no trata citas como comandos. S05: no obedece instrucciones dictadas. S06: no introduce saludos/despedidas, hechos, destinatarios o compromisos sin soporte. S07: conserva mezcla ES/EN. S08: contenido ambiguo se conserva; no se inventa la intención. S09: salida truncada nunca se acepta como completa. S10: original disponible temporalmente para recuperación, sin imponer historial en disco.

No construir un normalizador con `replace("no", "")`, ni una blacklist global de muletillas. “O sea”, “este”, “no” y “perdón” pueden ser contenido. `RewriteValidator` limita daños pero no demuestra equivalencia semántica universal. Una cifra diferente no es automáticamente error si existe reparación explícita; requiere regla y caso humano aceptado.

El [corpus semilla](fixtures/polished-seed.json) contiene casos de contrato sintéticos, **no un conjunto validado por humanos**. V21 lo amplía y separa desarrollo/evaluación. Los resultados expected no se presentan como algo que el modelo actual ya logra.

## 4. Automatización según hardware

Entrada de política: arquitectura, versión de OS, RAM total, presión actual de memoria, idioma solicitado, modo, assets disponibles, capacidades de motor y observaciones de latencia. Prohibido inferir idioma hablado de idioma UI. Ninguna rama `auto` acepta English-only.

| Perfil de arranque propuesto | Literal | Pulido | Restricción |
|---|---|---|---|
| Apple Silicon 8 GB | Base multilingüe compacta que pase corpus | Modelo pequeño aprobado; cargas secuenciales | No dos modelos residentes por defecto |
| Apple Silicon 16–24 GB | Base fiable, no upgrade automático por RAM | Modelo ganador de corpus ES/EN | Residencia condicionada a presión |
| Apple Silicon ≥32 GB | Calidad superior solo si beneficio demostrado | Variante aprobada que cumpla presupuesto | No descargar 1,6 GB solo por detectar RAM |
| OS con SpeechAnalyzer disponible | Candidato si idioma/assets/QA lo permiten | Procesador independiente del STT | No confundir disponibilidad API con assets instalados |
| Plataforma no admitida | Incompatibilidad antes de permisos | No prometer soporte | Sin descarga ni compra dirigida |

Reglas AD01–AD09:

1. Filtrar por idioma/capacidad antes de ordenar por rendimiento.
2. Elección inicial a partir de evidencia offline del corpus, no solo tamaño del modelo.
3. Primeras cinco observaciones válidas calibran rendimiento; excluir taps, errores y muestras con descarga simultánea.
4. Medir duración con frames de audio; reloj monotónico para latencia.
5. Separar cold/warm, STT, procesamiento y total hasta resultado de inserción.
6. Ajustar entre sesiones. Congelar config durante una sesión y nunca sustituir Literal por Pulido.
7. Histeresis/cooldown; como punto inicial propuesto, no más de un cambio automático por diez sesiones válidas. Versionar el valor tras benchmark.
8. Assets nuevos requieren consentimiento con tamaño/origen. Si no están, seguir usando el motor compatible instalado.
9. Cambio de presión libera recursos y selecciona alternativa aprobada; no cruza a cloud, no cambia idioma, no afirma mayor precisión sin datos.

Objetivos propuestos, no promesas verificadas: p95 de release-to-text ≤1,5 s Literal y ≤4 s Pulido para frases de 5–15 s en hardware mínimo probado. Registrar si no se alcanzan; no falsear muestras ni ocultar 8 GB dentro de la media de equipos rápidos.

## 5. Privacidad por sesión

| Destino/sesión | Captura | Procesamiento | Inserción | Historial |
|---|---|---|---|---|
| Campo permitido y sesión activa | Sí | Según modo | Si destino sigue válido | Según política |
| Campo seguro detectado | No | No | No | No |
| Sesión bloqueada/inactiva | Cancelar | Cancelar/invalidar resultado | No | No nuevo contenido |
| Destino cambió | La sesión ya grabada puede completar si sigue activa | Sí local | No automática | Solo según política; recuperación RAM |
| AX/foco desconocido | Permitir ruta de dictado a RAM si usuario la inicia | Sí local | No automática | Default off |

No leer documento completo ni screenshot para identificar destino. Capturar solo PID/bundle ID y referencia/identidad AX mínima, además de propiedades necesarias. `unknown` se modela explícitamente. No guardar esos identificadores en analítica ni informes exportados por defecto.

Recuperación RAM propuesta: último resultado durante 120 s o hasta bloqueo/salida/reemplazo por siguiente resultado. Historial off significa no persistir texto en disco, no “jamás existir en RAM”. Cualquier deshacer externo requiere receipt y coincidencia del destino/contenido; en otro caso ofrecer copiar explícitamente.

Historial nuevo default off; session/7days/30days/forever son opciones. Migración legacy conserva archivos y pregunta antes de importarlos o aplicar borrado. Temporales de audio propiedad de cada sesión, nombres UUID, atributos privados, cierre en todos los errores y limpieza de huérfanos propios. No prometer borrado seguro de SSD/backups.

## 6. Preparación hands off

Motor dentro del bundle, modelos elegidos por Voza. Onboarding permite continuar con Literal cuando esté listo aunque Pulido necesite paquete adicional. Si el usuario eligió Pulido, explicar estado de preparación y permitir usar Literal temporalmente sin cambiar su preferencia. No mostrar Pulido activo si no puede procesar.

Primera instalación sin red solo es soportada si trae/importa todos los assets necesarios. Descargar modelos después de “Listo” sin avisar contradice el contrato. Cancelar una descarga no cancela un dictado existente. Falta de espacio y fallo de hash no se presentan como readiness verde.

## 7. No objetivos del compromiso inicial

No Windows, móvil, reuniones, speaker diarization, control general de ordenador, shell por voz, agentes, MCP, lectura de pantalla, entrenamiento propio o marketplace de plugins. No third mode de “profesional” en onboarding. Diccionario/per-app, parciales, traducción y comandos son backlog de V31/V32 salvo nueva decisión explícita.
