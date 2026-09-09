# Arquitectura objetivo y contratos entre tickets

Estado: propuesta de implementación. No contiene APIs que ya existan por haber sido escritas aquí. Los nombres nuevos están asignados en PLAN.json/CODE-MAP; verificar el árbol antes de crearlos. Rutas relativas al repositorio, resueltas desde el checkout de la sesión.

## 1. Situación actual y frontera del cambio

[VERIFIED] `VozaApp` compone singletons en `applicationDidFinishLaunching`; `AppState` lleva grabación, pipeline, descarga, configuración, rendimiento e historial. `Transcriber` es síncrono, lanzado mediante Task.detached, pero resuelve el binario leyendo Config.shared. `Cleaner.clean` recibe una referencia mutable Config. `Paster.paste` ejecuta efectos sin devolver resultado. `TranscriptStore` tiene cola propia y `recent` se modifica más tarde en main. Referencias exactas: [CODE-MAP.md](CODE-MAP.md).

[INFERED] Mantener VozaKit, Voza y los entrypoints. Introducir composición e interfaces gradualmente; no crear otro framework ni un segundo pipeline que quede vivo indefinidamente. Cada ticket debe mantener una ruta funcional; adapter legacy temporal con eliminación identificada, no dos arquitecturas sin dueño.

## 2. Propietarios de estado

| Propietario | Aislamiento | Estado que puede modificar | No puede modificar |
|---|---|---|---|
| AppDependencies, App/Dependencies.swift | MainActor al componer | Instancias y configuración inicial | Estado interno de recursos desde callbacks |
| AppState | MainActor | Proyección de sesión, settings snapshot, mensajes y estado observable de descarga | FileHandle/AVAudioConverter o proceso directamente |
| DictationPipeline | actor | ID vigente, task/cancelación, configuración y resultado de sesión | NSPasteboard/AX fuera de MainActor |
| AudioRecorder | lifecycle en executor definido + escritor serial acotado | engine, tap, buffers propios, archivo y frames | UI, configuración global o sesión siguiente |
| ProcessRunner | implementación Sendable con propiedad explícita por proceso | proceso, pipes, límite de salida y terminación | Config.shared, defaults o UI |
| ModelManager | actor o coordinación serial definida | solicitudes/leases de modelos, promoción de assets | DictationState |
| SettingsRepository | executor serial/MainActor definido | settings persistidos versionados | Config de sesiones ya iniciadas |
| TranscriptStore | I/O serial; snapshot publicado en main | historial sujeto a retención | Clipboard, estados del pipeline |
| RecoveryBuffer | MainActor | último resultado en RAM y TTL | Persistencia automática |
| LicenseManager | MainActor; transporte separado | entitlement y estado de operación | Disponibilidad de dictado local por error transitorio |

No pasar `AVAudioPCMBuffer` entre actores como si fuera un valor Sendable. Hacer copia propia del contenido necesario antes de salir del callback o usar una integración documentada que asegure ownership. No realizar red, disco ni bloqueo prolongado en el callback de tiempo real.

## 3. Tipos de contrato: V06

Estos campos definen semántica; GLM debe implementar tipos Swift completos y probarlos, no copiar pseudoimplementaciones.

### DictationMode

Enum Codable/Sendable: `literal`, `polished`. Texto UI traducido separado de rawValue. Ningún mode `auto`: auto pertenece a política de motor.

### SessionConfiguration

Valor inmutable Sendable: schema/policy version, mode solicitado, idioma (`auto/en/es` inicialmente), ID y versión del motor/modelo STT resuelto, configuración de procesador local seleccionado, política de fallback, proveedor opcional consentido, retención efectiva y máximo de duración. No contiene referencias Config ni UserDefaults. Credenciales no se copian a logs ni receipts; se obtienen mediante referencia segura del proveedor al ejecutar la operación.

### AudioAsset

sessionID, URL propia, frameCount, sampleRate, channels, sampleFormat y lifecycle owner. durationSeconds = Double(frameCount)/sampleRate. Validar sampleRate > 0, tamaño máximo y consistencia header/payload. AudioAsset no implica derecho a borrarlo si fue importado por el usuario: `ownership=temporarySession/importedReadOnly`.

### TranscriptionResult

originalText, detectedLanguage opcional, engine/model/version, elapsedSTT, audioDuration y metadatos solo si el motor los produce. No inventar confidence. Representar `noSpeech` aparte de `failed`, y texto válido que contenga corchetes como texto.

### ProcessingOutcome

originalText, outputText, requestedMode, appliedMode, processingStatus (`notRequested/succeeded/unavailable/rejected/cancelled`), didRewrite, providerKind (`none/local/explicitCloud`), model/version, elapsedProcessing y fallbackReason estable. Un output idéntico con finalización válida es succeeded, didRewrite=false. Salida vacía puede ser válida para entrada compuesta únicamente por muletillas si el contrato/corpus lo aprueba; no etiquetar cualquier vacío como error ni aceptar vacíos indiscriminadamente.

### TargetSnapshot y PrivacyVerdict

sessionID, PID/bundleID y referencia AX mínima retenida con su aislamiento; subrole/permitido/desconocido; instante de captura. No hacer Sendable con `@unchecked` para silenciar errores: aislar AX en MainActor y transferir solo identidad serializable necesaria. PrivacyVerdict: `allowed`, `secureField`, `sessionInactive`, `unknown(reason)`. Unknown admite salida a RAM sin autopegado; secureField/sessionInactive bloquean captura.

### InsertionReceipt

sessionID, targetIdentity mínima, result (`attempted/confirmed/failed/skipped`), strategy (`clipboard/ax/recoveryOnly`), reason, timestamp monotónico relativo a sesión y datos mínimos de reversión si verificables. `confirmed` requiere lectura de vuelta u otra confirmación fiable documentada; un evento enviado solo da `attempted`. No guardar un documento completo para poder deshacer.

### SessionResult

Agrupa transcription, processing, insertion, timings y status sin confundir entregado/guardado. Puede haber inserción enviada e historial fallido. Se publica una vez para la sesión vigente; un resultado tardío cancelado no crea historial, sonido ni pegado.

### ErrorCode

IDs estables separados del copy: microphoneDenied, hotkeyUnavailable, accessibilityDenied, secureTarget, inactiveSession, destinationChanged, engineUnavailable, modelUnavailable, insufficientDisk, diskUnknown, captureStartFailed, audioWriteFailed, audioConversionFailed, noSpeech, transcriptionTimeout, transcriptionFailed, processingUnavailable, processingRejected, historyWriteFailed, licenseIndeterminate, licenseRevoked, updateFailed. Cada código tiene ES/EN y acción contextual en UX.

## 4. Flujo de sesión

1. Usuario inicia mediante shortcut/botón. En MainActor se evalúa estado activo, snapshot de destino y configuración.
2. Si destino seguro o sesión inactiva: no crear archivo, no activar micrófono. Si foco desconocido: ruta RAM explícita y sin promesa de inserción.
3. Pipeline asigna UUID y toma una lease de modelo; download/update no pueden borrar ese recurso durante uso.
4. Recorder inicia con rollback total ante fallo parcial. Publicar listening solo cuando engine arrancó.
5. Stop es idempotente: desinstala tap, drena escritor, cierra/valida WAV y entrega AudioAsset. Duración corta se determina por frames.
6. SpeechEngine procesa fuera de MainActor con ProcessRunner cancelable. Cancellation invalida primero sessionID y después libera recursos; no esperar a que termine un proceso para bloquear pegados tardíos.
7. Eliminar temporal propio después de que el motor haya cerrado lectura. Con fallo/cancelación, mismo cierre. Nunca eliminar un WAV importadoReadOnly.
8. Literal pasa sin reescritura. Pulido verifica privacidad todavía válida y procesa según snapshot. Nunca cambia proveedor por una edición de Settings a mitad de sesión.
9. Validar resultado y destino. Si cambió, recoveryOnly; si sesión bloqueada, descartar; si sigue permitido, insertar.
10. Publicar receipt y poner resultado en RAM según TTL. Persistir historial solo si permitido; fallo de persistencia separado de fallo de inserción.
11. Liberar lease, volver idle y recién entonces permitir adaptación/update.

## 5. Máquina de estados

| Estado actual | Evento | Nuevo estado / efecto |
|---|---|---|
| idle/failed | start permitido | starting con ID nuevo |
| starting | engineStarted | listening |
| starting | failure/stop/cancel | cleanup → failed/idle según razón |
| listening | stop de tecla propietaria o botón | finalizing |
| finalizing | audio válido | transcribing |
| transcribing | texto + Literal | delivering |
| transcribing | texto + Pulido listo | processing |
| processing | validado | delivering |
| processing | error recuperable y fallback autorizado | delivering Literal con motivo |
| delivering | destino cambiado/unknown | recoveryOnly → idle con aviso |
| delivering | receipt | completed → idle |
| cualquier busy | cancel/bloqueo | invalidar ID → cancelar recursos → idle con causa |
| cualquier estado de dictado | downloadFailed | dictado SIN cambio; update DownloadState |
| cualquier busy | start adicional | ignoredBusy, sin crear sesión paralela |

No guardar `failed` por falta de disco de una descarga en la phase del recorder. No permitir que un timer viejo actualice la nueva sesión. No reanudar captura automáticamente tras sleep/wake.

## 6. ProcessRunner

Entradas: URL ejecutable ya validada, argumentos sin secretos/contenido personal, stdin Data/stream cuando corresponda, env allowlist, deadline, límite de stdout/stderr, cancellation. Usar Process sin shell. Drenar ambos pipes desde el arranque; serializar cancelación/cierre para que una continuación no se reanude dos veces. Ante exceso de output, fallar explícitamente y terminar; no devolver transcripción recortada como éxito. Ante SIGTERM ignorado, esperar un margen y escalar usando API adecuada al PID propietario, luego reap/recolección.

Pruebas con proceso hijo finito: stdout 1 MB, stderr 1 MB, ambos alternados, proceso dormido, salida no UTF-8, exit no cero, SIGTERM ignorado, stdin cerrado, cancel antes/después de run. No usar `yes` infinito como prueba concluyente de deadlock; productor finito y comparación antes/después de drenar.

## 7. Settings y migración

V11 implementa schema v1. Repositorio de settings produce un valor completo, valida enums/rutas y publica cambios. Defaults se construyen de forma pura; crear directorios solo al guardar/preparar recursos.

Superficie prevista: mode; speechLanguage; activationStyle; hotkey; performancePolicy=automatic; historyPolicy; recoveryTTLSeconds; playSound; launchAtLogin; advanced engineOverride; modelsDirectory opcional; cleanupProvider=local; cloudProviderReference opcional. Idioma UI es independiente. No persistir mediciones en settings.

Migración legacy:

1. Leer config.toml sin escribirlo; reconocer claves documentadas y comentarios/escapes mediante parser correcto o importador limitado con rechazo explícito.
2. Conservar rutas y valores válidos. Identificar claves desconocidas y dejarlas en el archivo original; no borrarlas.
3. `cleanup=cloud` legacy: pedir revisión del proveedor antes del primer envío en la nueva versión. No activar cloud por presencia de `.env`.
4. Escribir archivo nuevo atómico y comprobar lectura; conservar original. Error deja original intacto y explica modo seguro.
5. Mover secreto al Keychain solo mediante V12, verificando lectura antes de ofrecer borrar la copia anterior. Nunca borrar `.env` entero por contener claves migradas.
6. Importación de historial separada; no escribir logs desde tests ni getters.

## 8. Modelos y engine assets

Catálogo con metadata explícita de idioma, capability autoLanguage, tamaño, hash, origen, licencia, runtime y arquitectura. No deducir `.en` de suffix con cuantización. `isDownloaded` distingue absent/partial/presentUnverified/verified/corrupt; tamaño igual no basta para decir verificado.

DownloadState independiente: idle, preparing, downloading(received,total), verifying, ready, paused, failed(code). Reanudar requiere rango consistente; hash al final; promover mediante sustitución atómica que preserve modelo válido existente hasta éxito. No entregar `.part` a SpeechEngine. Contar espacio en volumen destinatario; capacity desconocida se comunica. No almacenar payloads cloud en diagnóstico.

Bundled engine: `Contents/Resources/Engines/whisper/` para assets y librerías si se necesitan; executable firmado en ubicación coherente con validación de bundle. V16 determina layout final y registra `otool -L`, rpaths, target architectures y licencias. No copiar una dylib local y asumir que Homebrew estará en el equipo destinatario. Modelos de usuario fuera del bundle; actualización de app no los borra.

## 9. Pulido local y verificación semántica

V22 decide modelo por benchmark y licencia; no se acepta “el modelo más nuevo”. V23 integra ejecución local sin servicio de red obligatorio, sin shell y sin Ollama externo requerido. Puede empezar con helper/CLI por sesión; mantener residencia solo si demuestra ventaja y tiene política de memoria/cancelación. No introducir servidor HTTP propio por comodidad.

V24 verifica finalización, longitud/estructura, idioma observado y cambios sensibles. Conservar spans de reparaciones explícitas cuando sea posible. No usar substring de “no” como prueba semántica. Un validador heurístico no garantiza equivalencia: la evidencia humana del corpus es obligatoria. No usar otro LLM como juez único de su propia seguridad.

## 10. Reversión y compatibilidad

- Cada cambio de persistencia incluye migrationVersion y lectura de versión anterior o error seguro.
- Rollback de app conserva modelos/settings/historial; no se elimina un archivo del usuario para que pase una prueba.
- Receipt caduca con cambio de app/campo/contenido; si no puede verificar contenido, recovery copy en vez de Cmd+Z global.
- Names de APIs futuras deben contrastarse con documentación Apple vigente antes de codificar. No introducir `@unchecked Sendable`, private APIs o sleeps como parche sin justificar y probar.
- La compatibilidad por app es un artefacto de V27 con versión OS/app, estrategia y resultado. Una lista de nombres en README no es evidencia de soporte.
