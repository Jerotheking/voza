# Demo video de Voza — brief de producción (para Luna 6 / ChatGPT)

Objetivo: un video de **40 segundos, sin cortes de edición engañosos**, mostrando el
binario real de Voza pegando dictados en apps reales. Va embebido en `site/index.html`
(reemplaza el placeholder). BUSINESS.md §4: captura real, nada de mockups.

## Herramienta (gratis)

**Cap** — https://cap.so — open source, macOS nativo, graba pantalla + editor con
cortes/zoom, exporta MP4 sin marca de agua. Instalar:
`brew install --cask cap` (o descargar de cap.so). Verificar que la versión free
exporta 1080p sin límite antes de grabar todo.
Alternativa si Cap falla: **ScreenKite** (screenkite.com, gratis, nativo, auto-zoom
estilo Screen Studio). Última opción: QuickTime (graba, no edita) + recorte en Cap.

## Preparación de la Mac (antes de grabar)

1. Pantalla limpia: Dock oculto, escritorio sin íconos visibles, cerrar notificaciones
   (`shortcuts`/Focus), Safari/Notes/fuentes grandes.
2. Display 1920×1080 o grabar región de ~1600×900 alrededor de la ventana de trabajo.
3. `open /Applications/Voza.app` — binario 0.3.0 REAL (no demo, no simulación).
4. Micrófono del sistema (el dictado se escucha en el video: es el punto).

## Guion — 40 segundos (una toma continua, zooms del editor sí, cortes no)

| t | Acción en pantalla | Audio (hablado) |
|---|---|---|
| 0–5s | Cursor en campo de texto vacío de Notes | "This is Voza. Dictation for macOS." / ES: "Esto es Voza. Dictado para Mac." |
| 5–12s | **Mantener hotkey y dictar**: "Hola, esto es una nota de voz que se escribe sola" — soltar → texto pegado | (el dictado real se escucha) |
| 12–18s | Mismo texto en modo **Pulido**: repetir dictado corto, mostrar cómo quita muletillas | "Polish removes fillers and adds punctuation." |
| 18–28s | Cambiar de app (Safari o Mail): dictar un mail corto EN, se pega | "Any text field. English or Spanish." |
| 28–35s | Mostrar ajustes 3s: modo Literal/Pulido toggle, idioma ES/EN | "Your call. Local, private, $15 once." |
| 35–40s | Volver al editor: texto final pegado. End card overlay: logo + "voza" + $15 | (silencio o nota musical) |

Reglas: NUNCA borrar/regrabar a medias (si sale mal una frase, cortar y empezar la
toma de nuevo desde 0). El paste debe verse EN TIEMPO REAL — es el producto.

## Export (para la landing)

- MP4 H.264, 1920×1080, **sin audio de fondo agregado** (solo voz real), ≤ 8 MB
  (bitrate ~1.5 Mbps), duración ≤ 45s.
- Archivos: `site/demo.mp4` + poster JPG `site/demo-poster.jpg` (frame del momento
  del paste).
- Nombres exactos — `site/index.html` ya los referencia.

## Criterios de aceptación

- [ ] Se ve la app real pegando en ≥2 apps distintas
- [ ] Se escucha la voz y el paste es sincrónico (sin jump cuts en el paste)
- [ ] ≤ 45s, ≤ 8 MB, 1080p, sin marca de agua
- [ ] ES y EN versiones: o dos archivos (demo-es.mp4) o subtítulos en el editor
