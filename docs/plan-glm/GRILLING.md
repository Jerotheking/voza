# Grilling — Voza

Método: skill `grilling` (Matt Pocock). Cada ronda hace TODAS las preguntas
que el estado actual permite, cada una con respuesta recomendada. El dueño
responde; las decisiones se aplican al glosario/código y la siguiente ronda se
deriva de ellas.

## Ronda 1 — 2026-09-21 (respondida)

| # | Pregunta | Decisión del dueño |
|---|----------|--------------------|
| Q1 | ¿"Pulido" o término EN? | **EN-canonical**: el producto es inglés para ser universal; las strings EN son fuente, ES via `L.t` |
| Q2 | La UI dice "Correcciones" pero el dominio dice *Lesson* | (implícita) la UI habla de Lessons; glossary es la fuente |
| Q3 | ¿Español-primero para Gumroad? | **No — English-first** para universalidad |
| Q4 | ¿Degradación de AI cleanup silenciosa o anunciada? | **Anunciada una vez** (Settings + primer dictado sin llave), después silenciosa |
| Q5 | ¿"Sintelia" como palabra canónica de la doc? | **Sí**, confirmado |

## Ronda 2 — 2026-09-21 (pendiente de respuesta)

Preguntas derivadas de las decisiones de la ronda 1. Todas tienen
recomendación; pueden contestarse en bloque ("de acuerdo a todo").

**Q1 — "History" en la UI**: El glosario dice *History* y la UI ya lo llama
así, pero en español el popover dice "Historial". ¿Es correcto mantener el par
EN "History" / ES "Historial", o prefieres que en ES se diga otra cosa?
→ Recomiendo: mantener History/Historial (natural en ambos idiomas).

**Q2 — ¿Qué pasa con las Lessons cuando cambias de idioma de dictado?**: Las
lecciones son pares de texto sin etiqueta de idioma. Si mañana dictas en
inglés y el diccionario tiene lecciones de español, `apply()` intentará
aplicarlas igual. ¿Es aceptado (así funciona hoy) o debe etiquetarse la
Lesson con el idioma del dictado?
→ Recomiendo: aceptar el comportamiento actual; etiquetar solo si algún día
producen falsos positivos reales.

**Q3 — ¿El Daily Log es un artefacto de producto o privado?**: `~/Dictation/`
crece para siempre con TODO lo dictado (decisión original: "nunca se borra").
Para un producto de pago: ¿es feature ("tu historial completo, tuyo") o debe
existir una opción de retención/borrado?
→ Recomiendo: feature documentada + una acción manual "Clear log" en Settings
(sin borrado automático); privacy primero.

**Q4 — ¿El HUD dicta modo único o muestra el modo activo?**: Literal y AI
cleanup comparten HUD. ¿El HUD debe indicar el modo en el que dictaste
(ANA badge pequeño) para que el usuario sepa si el texto fue reescrito?
→ Recomiendo: sí, un badge discreto solo cuando fue AI cleanup (el caso que
sorprende es "el texto cambió").

**Q5 — ¿Anuncio de degradación: dónde exactamente?** (deriva de Q4-r1): La
regla es "anunciada una vez". ¿El aviso vive solo en Settings (banner estático
mientras no haya llave) o también como un toast/HUD la primera vez que un
dictado degrada?
→ Recomiendo: banner en Settings + toast una sola vez; nunca en dictados
siguientes.

**Q6 — ¿Sintelia en la doc pública o solo interna?**: La palabra vive en
tus Lessons reales y los tests. ¿En README/website público se usa Sintelia
como ejemplo (da identidad/marca) o un ejemplo neutro?
→ Recomiendo: usarla en público también — es memorable y gratis branding.
