# Sesión de campo — Pulido cloud con dictados reales

Objetivo: decidir con evidencia si el Pulido cloud justifica el precio de lanzamiento
($15) y si la degradación honesta (P1-b) se siente bien en uso real. ~30 minutos.

## Preparación (2 min)

- [ ] App corriendo: `open /Applications/Voza.app` (instalada desde el DMG, 0.3.0)
- [ ] Modelo: `~/.config/voza/models/ggml-large-v3-turbo.bin` presente
- [ ] Provider cloud: poner la key en `~/.config/voza/.env` (NO en shell — precedencia
      verificada en `testHasCleanupProviderIgnoresShellWhenFileEmpty`)
- [ ] Ajustes → Cleanup: modo **cloud**, y confirmar que el picker NO ofrece la opción
      gated sin provider (P2-d) y que el hint de descubribilidad desaparece al configurar

## Protocolo (3 bloques × ~8 min)

### Bloque A — Español conversacional
Dicta 5 frases típicas tuyas (mensaje, prompt, nota). Para cada una anota:

| # | Frase | Literal usable? | Pulido: mejora real? | Latencia percibida |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |
| 4 | | | | |
| 5 | | | | |

### Bloque B — Inglés técnico (prompts, código en prosa)
Mismo protocolo con 5 dictados EN. Atención a: términos técnicos intactos, markdown,
nombres de APIs.

### Bloque C — Fracasos honestos
1. Quita la key del `.env` (simula provider caído) y dicta en modo cloud:
   **esperado** (P1-b): pegado directo + status bilingüe "Cloud cleanup unavailable —
   pasted raw". Si pega silencioso sin avisar → bug, reportar.
2. Dicta ruido (tipear con micrófono lejos): ¿el pipeline falla con gracia?
3. Correcciones: dicta, pega mal una palabra, corrígela a mano — el watcher D041 debe
   aprender (verificar en la siguiente dictada).

## Criterios de decisión (al terminar)

- **Vende a $15**: si ≥7/10 dictados pulidos son "mejora real" y la latencia no molesta
  → el Pulido es el pitch. La landing ya lo vende así.
- **No vende el Pulido solo**: si la mejora es marginal → el pitch pasa a ser
  "local + barato + privado" y el Pulido se desciende a bonus. Ajustar copy de
  `site/index.html` y `docs/GUMROAD-PAGE-COPY.md` en consecuencia.
- **Degradación molesta**: si el aviso de "pasted raw" asusta → revisar wording con agy.

## Después

- [ ] Anotar veredicto en DECISIONS.md (nueva fila D04x)
- [ ] Si hubo bugs: tickets en docs/plan-glm/tickets/ y loop de re-review con agy
