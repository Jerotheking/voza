# Registro de decisiones

Fecha inicial: 2026-09-07. No editar retrospectivamente una decisión aceptada; agregar una entrada que la sustituya, con razón y autorización.

| ID | Estado | Decisión / origen | Consecuencia |
|---|---|---|---|
| D001 | ACCEPTED_OWNER | Dos modos: Literal rápido; Pulido con procesamiento adicional. Respuesta explícita del propietario en esta tarea. | No añadir un tercer modo principal ni confundir modo con tamaño de modelo. |
| D002 | ACCEPTED_OWNER | Preparación y adaptación técnica lo más hands off posible, según hardware. | No exigir modelo, terminal, Ollama o API key en el camino estándar. |
| D003 | ACCEPTED_OWNER | Handoff detallado para GLM 5.3 Flash, sobreviviente a sesiones y agentes distintos. | Tickets, estado, evidencia y cierre son parte de la entrega. |
| D004 | ACCEPTED_SCOPE | Esta sesión escribe documentación; no implementa la app. | Todos los tickets empiezan todo/deferred; ningún gate de producto aprobado. |
| D005 | PROPOSED | STT local y Pulido local por defecto, cloud solo opt-in avanzado. | Preservar frontera de privacidad existente; no fallback local→cloud. |
| D006 | PROPOSED | Literal sin reescritura adicional; Pulido conserva intención y tono. | Corpus separado y validación de cambios sensibles. |
| D007 | PROPOSED | Historial en disco off para instalación nueva; recuperación RAM breve. | No borrar ni desactivar historial legacy silenciosamente; consentimiento migratorio. |
| D008 | PROPOSED | Mac Apple Silicon como plataforma inicial; mantener macOS 14 hasta justificar un cambio. | Modelo Apple opcional con availability, no elevar mínimo por conveniencia. |
| D009 | PENDING_EVIDENCE | Modelo local de Pulido y modelo STT predeterminado final. | V22 registra benchmark/licencia/hash; nadie los inventa por intuición. |
| D010 | PROPOSED | $29 fundador → $39 estándar; ambos modos incluidos. | Validar negocio, términos existentes y coste antes de publicar. |
| D011 | PENDING_OWNER | Polar para nuevas ventas; compatibilidad Gumroad si hay compradores. | V13 endurece proveedor existente. No migrar cobro hasta decisión registrada en V29. |
| D012 | PENDING_OWNER | Renombrar o conservar Voza. | No cambiar bundle ID, dominios, cuentas o marca antes de resolver. |
| D013 | PENDING_OWNER | Política de actualización/licencia por persona/dispositivos y garantía. | Respetar derechos y promesas a compradores existentes; V29 debe verificarlos. |
| D014 | PROPOSED | Un agente activo de implementación por defecto; integrador único para STATE. | No asumir autorización para paralelizar; no usar state de ramas como lock distribuido. |
| D015 | PROPOSED | Nuevos modelos no se descargan silenciosamente; ajustes con assets presentes sí pueden aplicarse entre sesiones. | Automatización sin sorpresa de consumo/red. |
| D016 | PROPOSED | Si Pulido falla, usar Literal con indicador explícito cuando el destino siga siendo seguro y válido. | Nunca mostrar Pulido aplicado cuando no lo fue; recuperación sin diálogos rutinarios. |
| D017 | PROPOSED | Con foco desconocido, resultado a RAM; con campo seguro/bloqueo, no capturar. | Preservar utilidad sin pegar a ciegas. |
| D018 | PROPOSED | No streaming externo, Windows, control general ni comandos destructivos en el primer compromiso. | V31/V32 son backlog condicionado a evidencia. |
| D019 | ACCEPTED_OWNER | Xcode 26.6 es el toolchain local del proyecto (instalado y autorizado por el propietario 2026-09-09); `xcode-select` global apunta a /Applications/Xcode.app. XCTest disponible en máquina; el CI mantiene su propio pin de Xcode. No se usa el IDE: todo fluye por CLI (swift build/test, xcodebuild, xcrun). | swift test/xcodebuild funcionan en cualquier sesión sin DEVELOPER_DIR. V28 (Developer ID + notarización) sigue requiriendo autorización específica; este registro NO la otorga. |
| D020 | ACCEPTED_OWNER | HUD flotante de dictado estilo TypeWhisper (pedido explícito del propietario 2026-09-09): panel pequeño no activador abajo-centro que hace visible la fase recording→transcribing→cleaning sin abrir el popover. No estaba en el plan (verificado: 0 hits en tickets/ROADMAP/UX); se integra fuera de ticket como el ciclo de aprendizaje. | El HUD no captura foco ni teclado (nonactivatingPanel, statusBar level, canJoinAllSpaces); es solo presentación, consume AppState publicado; no lógica de pipeline. |
| D021 | ACCEPTED_OWNER | Paquete de refinamiento de dictado 2026-09-09: (a) HUD audio-reactivo con nivel RMS real del micrófono; (b) cleanup RE-BOUND temporalmente a Option izquierda (0x3A) porque Right ⌘ colisiona con Wispr del propietario — el destino final es un solo botón; (c) beam search 5 en todos los idiomas para cerrar la brecha de calidad de Literal vs TypeWhisper. | El bind temporal hace que ⌥-shortcuts con Option presionada primero disparen sesión stray; revertir antes de release. Level meter es lock-based 0...1, medición en capture thread. |
| D022 | ACCEPTED_OWNER | (Registrada con retraso — referida en commit 7243843 sin entrada) Dinámica VU real para las barras del HUD (attack/release smoothing observable a 30 Hz) y notch compacto 148×42, por feedback del propietario: "no son responsive con la voz… y el notch debe ser más pequeño". | El TimelineView previo no disparaba de forma fiable dentro del non-activating panel; el modelo observable determinista sí. Rango visual ampliado para que el movimiento sea evidente. |
| D023 | ACCEPTED_OWNER | Presupuesto RAM/latencia de Pulido local (2026-09-10, medido en la Mac del propietario, M4 14): (1) modelo default gemma3:4b en vez de qwen3:8b/4b — qwen3 es híbrido thinking: incluso con /no_think y think:false quemó 1024 tokens razonando antes de emitir (16 s, respuesta vacía); gemma3 no tiene fase thinking: 30 tokens, 0.5 s warm, salida limpia verificada. (2) Endpoint /api/chat con roles separados — la concatenación prompt+system de /api/generate invitaba meta-comentario ("We are given a text…") al paste. (3) keep_alive "5m" explícito en cada request (knob ollama_keep_alive + OLLAMA_KEEP_ALIVE): el default del servidor mantenía 6.8 GB RSS residentes permanentes. (4) num_predict 400 como techo de latencia. (5) stripThinkingJunk como red de seguridad: razonamiento jamás llega al paste; bloque <think> sin cerrar → vacío → fallback a transcript crudo. | gemma3:12b (instalado) preserva mejor matices finos; el propietario puede fijarlo explícitamente en config. qwen3 queda desaconsejado como cleaner hasta que su stack honre think:false. Trade-off aceptado: cold-start (~3 s) tras >5 m de inactividad. |

## Cómo proponer una decisión

Entrada con ID nuevo, fecha, autor, estado, evidencia, alternativas consideradas, elección recomendada, trade-off, archivos/tickets afectados y qué decisión sustituye. No usar “el usuario seguramente quiere” como fuente. Resolver implementación local reversible dentro del ticket; consultar solo decisiones que cambian comportamiento, privacidad, costes o alcance de forma material.

## Preguntas que no bloquean V01–V07

- Compradores existentes y términos prometidos.
- Cuenta Apple/Developer ID real y entidad de cobro.
- Horas semanales y equipos QA disponibles.
- Lista priorizada de apps y dialectos.
- Acceso a beta testers con consentimiento.
- Nombre y política comercial definitiva.

V01–V07 pueden avanzar con fixtures y el comportamiento seguro propuesto. Publicación, cobro y cambios de marca permanecen fuera de esa autorización.
