# Soft launch — Voza Early Access ($15)

Estado: plan para ejecutar en orden. Regla madre (BUSINESS.md §5): no pedir votos, no
fabricar testimonios, no DMs sin autorización. Lo que se valida es si alguien PAGA.
Precio: $15 · Updates: 1 año → luego pay-what-you-want (D046) · Permalink: `voza`.

## Fase 0 — Preparación (hacer antes de darle el link a NADIE)

- [ ] Sesión de campo Pulido ejecutada (docs/FIELD-SESSION-PULIDO.md) → veredicto en DECISIONS
- [ ] Demo real en `site/demo.mp4` (docs/plan-glm/materiales/DEMO-VIDEO-GUIDE.md, lo ejecuta Luna 6)
- [ ] Producto Gumroad creado: $15, License keys ON, permalink `voza`, DMG + sha256 subidos
- [ ] Copy pegada de docs/GUMROAD-PAGE-COPY.md (EN arriba, ES abajo)
- [ ] Loop de licencia probado con compra propia: activar → offline → reembolso → revoca
- [ ] Landing desplegada (Cloudflare Pages: `npx wrangler pages deploy site --project-name=voza`
      — o arrastrar la carpeta `site/` al dashboard) y CTA apuntando a Gumroad
- [ ] Email de soporte decidido (el placeholder `voza.app/support` exige decisión de marca)

## Fase 1 — Círculo cercano (día 0–2)

A quién: X personal, amigos, grupos de confianza, devs que dicten en Mac.
Qué decir: "Lancé mi app de dictado local para Mac, $15 Early Access, esto hace: [demo].
Honestidad: sin notarizar aún, guía incluida."
Métricas a observar: clics → compras, fricciones reportadas, quién instala y quién no.
Meta: primeras 2–5 ventas + testimonio usable con consentimiento (BUSINESS.md §5 día 21).

## Fase 2 — Nichos en frío (día 3–7)

A quién: comunidades hispanas de dev/mac (Discords, Slack, grupos de Telegram), las
mismas de r/LocalLLaMA en español, newsletters pequeñas. Regla: leer reglas de cada
comunidad ANTES de postear; donde no se permite autopromo, pedir permiso a un mod.
Canal público paralelo: post en X con el demo GIF (los videos cortos se auto-difunden).

## Fase 3 — Reddit (día 7–14, solo si Fase 1–2 no reventó nada)

1. **r/macapps** — declaración de fundador, precio y límites explícitos. Leer reglas
   vigentes y el estado de ánimo del sub ese día (BUSINESS.md §5: re-consultar reglas).
2. **r/LocalLLaMA** — ángulo técnico: whisper.cpp v1.9.4 vendido, Metal embebido,
   0 deps brew (D043). Sin marketing, solo ingeniería.
3. **r/Spanish** o comunidades ES-EN — ángulo bilingüe (nadie más lo atiende).

## Fase 4 — Show HN + Product Hunt (día 14+, solo con todo verde)

- Show HN: título seco, primer comentario con detalles técnicos honestos (incluye lo que
  NO hace). El demo y la guía de instalación tienen que estar a prueba de multitudes.
- Product Hunt: después de corregir los primeros fallos que reporte la Fase 1.
- Regla: si hay reportes de que la instalación falla en macOS 26, pausar todo y correr
  `scripts/release.sh` (notarización) antes de seguir exponiendo.

## Métricas de 48h por fase (BUSINESS.md §6)

| Métrica | Fuente | Umbral para seguir |
|---|---|---|
| Visitas landing | Cloudflare Analytics | ≥100/fase activa |
| Conversión a Gumroad | Gumroad views → sales | ≥2% saludable; <0.5% revisar copy/precio |
| Refunds | Gumroad | <5% (kill criterion §7) |
| Fricción instalación | soporte directo | >1 reporte = auditar INSTALL.txt YA |
| Tiempo de respuesta | tú | <15 min/comprador (§6) |

## Gatillo Apple Developer ($99) — decisión del cuestionario 2026-09-25

**La primera venta de un extraño** (Fase 2 en adelante) → comprar ese día, crear el
certificado Developer ID + perfil notarytool, correr `scripts/release.sh`, subir DMG
notarizado. ~7 licencias pagan los $99.

## Después de cada fase

- [ ] Apuntar números y aprendizajes en DECISIONS.md (nueva fila D04x)
- [ ] Ajustar copy si la objeción recurrente es la misma 2+ veces
- [ ] No deshacer derechos de compradores anteriores (BUSINESS.md §2)
