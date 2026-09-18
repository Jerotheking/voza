# Voza

Dictado local para macOS: mantienes una tecla, hablas, sueltas, y el texto queda
escrito donde esté el cursor. 100% offline por defecto; sin cuentas, sin telemetría.

## Language

### El dictado

**Dictation (dictado)**:
El acto completo: mantener el Hotkey, hablar, soltar, y ver el texto pegado en el
campo enfocado.
_Avoid_: grabación, transcripción (son partes del dictado, no el todo)

**Hotkey**:
Tecla que se **mantiene presionada** para dictar (Option por defecto). Soltarla
termina la grabación.
_Avoid_: shortcut, atajo (un atajo se pulsa una vez; el Hotkey se sostiene)

**Transcript (transcripción)**:
El texto que produce whisper a partir del audio, antes de cualquier corrección.
_Avoid_: resultado, output

**Literal**:
Modo por defecto: el Transcript se pega tal cual. Nadie lo reescribe.
_Avoid_: raw, plain (nombre de la clave en config.toml)

**Pulido**:
Modo opt-in: el Transcript pasa por un LLM en la nube (llave propia del usuario)
antes de pegarse. Sin llave configurada, degrada a Literal.
_Avoid_: cleanup (nombre legacy del código), polishing, limpieza

**HUD**:
Superposición flotante que muestra el estado del dictado (grabando /
transcribiendo) con nivel de voz en vivo. El usuario la llama "la muesca".
_Avoid_: overlay, notch (apodo, no término)

**History (historial)**:
Los últimos dictados, consultables desde el menú, con botón de copiar y la vía
✏️ de corrección manual.
_Avoid_: log (reservado para Daily Log y Learning Log)

**Daily Log**:
Anexo inmediato de cada dictado a `~/Dictation/YYYY-MM.md` con marca de tiempo.
Nunca se borra.
_Avoid_: historial (es el History), backup

### El aprendizaje

**Lesson (lección)**:
Un par aprendido: lo que whisper oyó mal → lo que el usuario realmente escribió.
Se aplica sola en dictados futuros.
_Avoid_: corrección (es el acto, no la lección), entrada, mapeo

**Heard**:
Lado de la Lesson: lo que whisper produjo (la palabra mal oída).
_Avoid_: original, from, error

**Said**:
Lado de la Lesson: lo que el usuario escribió al corregir (la palabra verdadera).
_Avoid_: corrección, to, target

**Dictionary (diccionario)**:
El conjunto persistente de Lessons (`~/.config/voza/corrections.json`). Único
mecanismo por el que el dictado mejora con el uso.
_Avoid_: vocabulario, base de datos, cache

**Auto-learn (autoaprendizaje)**:
Captura automática de una Lesson: Voza observa el campo pegado durante la
Correction Window y aprende del tecleo del usuario. Desactivable en Settings.
_Avoid_: watching, monitoreo

**Correction Window (ventana)**:
Los ~20 s tras pegar en los que una edición del usuario puede volverse Lesson.
A lo sumo una Lesson por paste.
_Avoid_: timeout, polling

**Confirmation read (lectura de confirmación)**:
Segunda lectura del campo tras una pausa: si siguió cambiando, el usuario seguía
tecleando (menú de acentos, IME) y NO es el momento de aprender.
_Avoid_: double read, re-check

**Late-baseline**:
Modo del aprendizaje para apps Electron/Chromium que no exponen su árbol de
accesibilidad al pegar: el "antes" se captura DESPUÉS del paste, una vez
despierto el árbol.
_Avoid_: fallback mode, modo Electron

**Wake (despertar)**:
Activar el árbol de accesibilidad de una app Chromium mediante atributos en sus
áreas web. Solo atributos: nunca lanza VoiceOver, nunca postea teclas, nunca
toca audio (decisión del dueño, D040).
_Avoid_: toggle VO, lanzar VoiceOver, forcing

**Learning Log (bitácora)**:
`~/Library/Logs/voza/learning.log` — un evento por sesión de aprendizaje
(start / learned / expired / ax-never-woke). Fuente de verdad para diagnosticar
por qué algo no aprendió.
_Avoid_: log de la app, consola

### La máquina

**Model (modelo)**:
Un whisper descargable del catálogo, verificado por SHA-256. El preferido vive
en config; si no está descargado, entra el Fallback.
_Avoid_: LLM (no hay LLM en el camino por defecto), red neuronal

**Fallback (modelo de respaldo)**:
El Model descargado que se usa cuando el preferido no está disponible. Se
anuncia en el Estado, nunca falla en silencio.
_Avoid_: default (el default es el preferido elegido por adaptación)

**RTF**:
Real-time factor: segundos de transcripción por segundo de audio. Métrica que
el Performance Monitor registra por dictado.
_Avoid_: velocidad, latencia

**Hardware adaptation (adaptación)**:
Elegir los defaults (Model, presupuesto de RAM) según la Mac del usuario, y
**explicarlos** en Settings en vez de pedir decisiones.
_Avoid_: auto-tuning, presets (fuera de alcance del producto)

**Smoke**:
Binario de verificación hermética (VozaSmoke): pruebas puras sin micrófono,
sin Model, sin perfil real. Debe pasar antes de cualquier release.
_Avoid_: e2e, integration test

**Hermetic (hermético)**:
Propiedad de una prueba que no toca nada real: ni accesibilidad, ni eventos de
teclado, ni la bitácora, ni el perfil del usuario. Regla viva del proyecto.
_Avoid_: mockeado, aislado

---

Las decisiones registradas (por qué, cuándo y a cambio de qué) viven en
`docs/plan-glm/DECISIONS.md` (D001–D040). El mapa de código, en
`docs/plan-glm/CODE-MAP.md`.
