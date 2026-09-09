# UX integral — mapa de pantallas y estados

Estado: propuesta que implementa D001/D002. Conservar controles nativos SwiftUI/AppKit y semántica macOS. No rediseñar marca mientras D012 esté pendiente. La app actual no fue validada visualmente ni con VoiceOver en esta auditoría.

## 1. Jerarquía y destino de componentes

| Superficie | Ubicación propuesta | Responsabilidad |
|---|---|---|
| Popover | Sources/VozaKit/UI/PopoverView.swift | Modo, start/stop accesible, estado, recuperar, ajustes/salir |
| Selector compartido | Sources/VozaKit/UI/ModePicker.swift | Literal/Pulido, una binding al modo canónico |
| Panel de grabación | Sources/VozaKit/UI/RecordingPanel.swift | NSPanel no activante; escuchar/procesar/entregar/cancelar |
| Recuperación | Sources/VozaKit/UI/RecoveryView.swift | Original/procesado y acción permitida por receipt |
| Onboarding | Sources/VozaKit/UI/OnboardingView.swift | Cinco pasos sobre OnboardingState, no otro readiness paralelo |
| Contenedor ajustes | Sources/VozaKit/UI/SettingsView.swift | Navegación y composición; retirar lógica de múltiples recursos |
| Inicio/estado | Sources/VozaKit/UI/Settings/StatusView.swift | Siguiente acción, modos disponibles, prueba y diagnósticos |
| Dictado | Sources/VozaKit/UI/Settings/DictationSettings.swift | Modo, atajo, hold/toggle, idioma, sonido |
| Privacidad | Sources/VozaKit/UI/Settings/PrivacySettings.swift | Historial, buffer RAM, cloud opt-in |
| Avanzado/modelos | Sources/VozaKit/UI/Settings/AdvancedSettings.swift | Engine seleccionado, overrides, ubicación, recursos y reporte |
| Licencia y Acerca | Sources/VozaKit/UI/Settings/LicenseSettings.swift, AboutSettings.swift | Observar licencia directamente; compra secundaria |
| Localización | Sources/VozaKit/App/Localizer.swift inicialmente | IDs/copy ES/EN; evitar otra fuente de traducciones simultánea |

Extracción de vistas en V18/V19, conservando nombres usados por callers hasta adaptar sus imports/composición. No crear carpetas de componentes genéricos sin reutilización real.

## 2. Onboarding pantalla por pantalla

### O01 — modos

ES título “Tu voz, de dos maneras.” EN “Two ways to write with your voice.” Mostrar dos opciones con el copy de PRODUCT. Ambas describen beneficio/coste; ninguna se llama “difícil”. CTA ES “Continuar”, EN “Continue”. Si el usuario no elige, Literal puede ser preselección propuesta; no forzar Pulido en equipos rápidos. Selección persiste solo al continuar. Atrás conserva elecciones.

### O02 — permisos

ES “Permite que Voza funcione.” EN “Let Voza work.” Filas micrófono, atajo global, inserción. Cada una dice para qué y tiene acción contextual. Micrófono notDetermined dispara solicitud; denied abre ajustes. AX abre panel y muestra instrucciones comprobadas para localizar/añadir la app; no prometer que macOS solicitará un permiso que el código nunca solicita. Al volver al foreground, refrescar los permisos reales. No timer de 0,6 s como única actualización.

Input Monitoring depende de la estrategia seleccionada y capacidad real del hotkey; no pedirlo si una implementación futura probada no lo necesita. Si no se obtiene, ofrecer botón dentro de Voza cuando sea funcional. Cerrar/cancelar el onboarding y abrir ajustes siempre posibles. Botón Continuar distingue configurar más tarde de “listo para insertar”.

### O03 — preparar

ES “Preparando Voza para esta Mac.” EN “Preparing Voza for this Mac.” Modelo elegido automáticamente; nombre técnico bajo Detalles. Mostrar bytes a descargar, origen, espacio requerido, progreso y estado de verificación. ETA solo cuando hay muestra suficiente y expresa incertidumbre. Pausa/reanudar, cancel y error recuperable. Si Literal está listo y Pulido no, CTA “Usar Literal mientras termina” / “Use Literal while setup finishes”, sin cambiar preferencia definitiva.

Sin red: “Puedes reanudar cuando tengas conexión o importar un paquete offline.” / “Resume when you’re online or import an offline package.” No decir offline-ready si el paquete de modelos falta. No elevar a ready porque llegó 100% antes del hash.

### O04 — prueba

ES “Prueba tu primer dictado.” EN “Try your first dictation.” Campo dentro de Voza que no envía datos a otra app. Ejemplo: “Nos vemos el martes, perdón, el jueves.” / “Let’s meet Tuesday, sorry, Thursday.” Botón iniciar accesible y atajo visible. Muestra modo solicitado/aplicado y recuperación del original. No afirmar que se probó la inserción externa por completar este paso. Comparar modos es opcional.

### O05 — salida

ES “Listo para tus apps.” EN “Ready for your apps.” Solo si requisitos reales de inserción están verificados; de lo contrario “Listo para dictar en Voza” / “Ready to dictate in Voza”. Mostrar atajo y modo, explicar acceso por micrófono del menú. Proponer prueba externa opt-in sin abrir documentos personales. CTA finalizar no descarga paquetes ni habilita historial por sorpresa.

## 3. Popover y panel

Popover objetivo orientativo 340–380 pt de ancho, adaptable a texto/traducción; no validar diseño por un número. Selector de modos en cabecera, acción principal accesible, mensaje de estado y recuperar último dictado. Historial solo si habilitado; no mostrar lista vacía enorme cuando está off. Ajustes y salir siempre presentes. Licencia no desplaza grabación ni oculta contenido.

Panel no toma foco al aparecer o actualizarse. Visible durante starting/listening/finalizing/transcribing/processing/delivering. Listening: indicador y tiempo; waveform RMS opcional, nunca “confianza”. Processing distingue Literal/Pulido. Cancel accesible, teclado Escape cuando sea compatible sin interceptar contenido ajeno. En bloqueo, ocultar texto y cancelar; no reaparecer con transcripción sensible al desbloquear.

En idle normal, panel se retira sin cambiar foco. En fallo recuperable, mensaje permanece en popover y señal del panel no desaparece antes de poder leerse. Evitar parpadeo/animación continua y respetar Reduce Motion. Cambiar modo durante busy se anuncia “Se aplicará al siguiente dictado” / “Applies to the next dictation”.

## 4. Status home

Priority: sesión bloqueada/seguridad → recurso necesario para el modo → permiso requerido → asset pendiente/corrupto → prueba disponible → ready. La descarga tiene estado propio. Ready puede ser específico: “Literal listo; Pulido preparándose”, no booleano global. Cada problema ofrece una acción posible; si falta un recurso no instalable automáticamente, no presentar un botón que no hará nada.

No mostrar todos los chips de CPU/RAM/modelos al usuario normal. En Detalles: motor real resuelto, idioma, modo, versión y latencia medida con muestra. Rendimiento nunca afirma precisión. Reporte exportable se previsualiza y excluye texto/audio/keys/rutas personales.

## 5. Catálogo de errores canónico

| Código | ES | EN | Acción |
|---|---|---|---|
| microphoneDenied | Activa el micrófono para dictar. | Enable the microphone to dictate. | Abrir ajustes/request según estado |
| hotkeyUnavailable | El atajo global necesita permiso. | The global shortcut needs permission. | Reparar o botón si disponible |
| accessibilityDenied | El texto está listo. Falta permiso para insertarlo. | Your text is ready. Permission is needed to insert it. | Conceder/copiar explícito |
| secureTarget | Voza no dicta en campos de contraseña. | Voza doesn’t dictate into password fields. | No capturar |
| inactiveSession | Se canceló el dictado al bloquear la sesión. | Dictation was cancelled when the session locked. | Ningún pegado tardío |
| destinationChanged | El destino cambió. Tu texto está listo. | The destination changed. Your text is ready. | Recuperar en RAM |
| engineUnavailable | Falta completar la preparación de Voza. | Voza setup needs to finish. | Reparar instalación |
| modelUnavailable | Falta el modelo necesario para este modo. | The model for this mode is missing. | Descargar/importar |
| insufficientDisk | Necesitas {size} más de espacio. | You need {size} more free space. | Ubicación/liberar espacio |
| diskUnknown | No pudimos comprobar el espacio disponible. | We couldn’t check available storage. | Reintentar |
| captureStartFailed | No se pudo iniciar el micrófono. | The microphone couldn’t start. | Elegir/reconectar |
| audioWriteFailed | No se pudo guardar el audio temporal. | Temporary audio couldn’t be written. | Cancelar/liberar espacio |
| audioConversionFailed | No se pudo procesar el audio del micrófono. | Microphone audio couldn’t be processed. | Reintentar/diagnóstico |
| noSpeech | No se detectó voz. | No speech detected. | Reintentar sin pegado |
| transcriptionTimeout | La transcripción tardó demasiado. | Transcription took too long. | Cancelar/reintentar |
| transcriptionFailed | No se pudo transcribir este dictado. | This dictation couldn’t be transcribed. | Diagnóstico sin contenido |
| processingUnavailable | Se usó Literal: Pulido no respondió. | Used Literal: Polished didn’t respond. | Ver original/reintentar |
| processingRejected | Se conservó el original para evitar cambiar el sentido. | Kept the original to avoid changing the meaning. | Indicador discreto |
| historyWriteFailed | El dictado terminó, pero no se pudo guardar el historial. | Dictation finished, but history couldn’t be saved. | Recuperar desde RAM |
| licenseIndeterminate | Tu licencia sigue activa. Verificaremos después. | Your license remains active. We’ll check later. | Solo si caché válida existe |
| licenseRevoked | La licencia ya no está activa. El dictado sigue disponible. | The license is no longer active. Dictation remains available. | Revisar compra/soporte |
| updateFailed | No se pudo actualizar. Tu versión actual sigue disponible. | The update failed. Your current version remains available. | Reintentar sin borrar app válida |

Errores nativos detallados a diagnóstico, no stacktrace en UI. No mostrar éxito y fallo simultáneos para la misma operación. Cada mensaje tiene lifetime, severidad y operación/session ID: ningún éxito viejo sobrevive como subtítulo verde de un fallo nuevo.

## 6. Accesibilidad verificable

VoiceOver: nombres “Copiar dictado”, “Cancelar grabación”, “Abrir ajustes”, “Cambiar a Literal/Pulido”, “Cerrar aviso”. No depender solo de icono/color/tooltip. Orden: modo → acción principal → estado → recuperación → navegación. Focus ring visible, Tab/Shift-Tab completos, controles accionables sin mouse. Anunciar cambios de fase relevantes sin hablar cada tick de timer.

Ventanas: probar dark/light, texto ES largo, tamaño de sistema y Zoom, pantalla pequeña, monitores múltiples, pantalla completa y menú oculto. Revisar truncamiento, contraste y estado disabled con runtime real; no cerrar AC manual por lectura de SwiftUI.

Prueba de movilidad: toggle permite iniciar/terminar sin sostener una tecla. No prometer sustituto completo de Voice Control. La onda no es necesaria para usuarios ciegos; anunciar micrófono activo/inactivo y permitir detener con teclado.
