# Voza — Launch Checklist (Gumroad Early Access, $15)

Estado: template pendiente de ejecución por el dueño. Nada de esto publica ni cobra por sí solo.
Precio decidido: **$15 Early Access** (ver §"Precio" abajo para el texto que sube a la página).

## 1. Artefacto

- [ ] `./build.sh release` verde (0.3.0, whisper.cpp v1.9.4 vendido, Metal embebido)
- [ ] `./scripts/make-dmg.sh` → `build/Voza-0.3.0-early-access.dmg` + `.sha256`
- [ ] Instalar el DMG en esta Mac (drag a /Applications) y hacer 3 dictados completos:
      grabar → transcribir → pegar, con el modelo large-v3-turbo real
- [ ] Probar la activación de licencia con una llave de TEST de Gumroad (ver §3)
- [ ] Borrar `~/.config/voza/license.json` y verificar que el trial 14 días arranca limpio
- [ ] Desinstalar + reinstalar: los permisos TCC sobreviven (firma estable `voza-dev`)

## 2. Producto Gumroad

- [ ] Crear producto **Voza — Early Access** (digital, un solo archivo: el DMG + sha256)
- [ ] Precio **$15** USD
- [ ] Activar **License keys** (Gumroad genera llaves al comprar; LicenseManager ya las
      verifica contra `api.gumroad.com/v2/licenses/verify`, permalink `voza`)
- [ ] **Permalink del producto: `voza`** — la app arma `jerotherey.gumroad.com/l/voza`
      (Config.swift `gumroadPermalink`). Si el permalink real es otro, actualizar Config.
- [ ] Página del producto con la copy de §5 + el DMG + INSTALL.txt visible
- [ ] Tax: dejar que Gumroad gestione (es el merchant of record)

## 3. Probar el loop de licencia ANTES de publicar

1. Crear el producto con llaves activadas.
2. Comprar tú mismo ($15; Gumroad te reembolsa o te lo compras de verdad).
3. Activar la llave en la app → debe quedar `.licensed` y cachear offline
   (`~/.config/voza/license.json`, chmod 600).
4. Cortar internet → la app sigue licensed (offline grace).
5. Reembolsar la compra → a los 7 días la re-verificación la revoca y vuelve al trial.
   (Si no quieres esperar: borrar la cache y verificar que el estado cae a trial.)

## 4. Marca (advertencia de BUSINESS.md §3)

- [ ] Buscar "Voza" en GitHub, App Store, Google, X, Product Hunt — existe colisión con
      "Voxa" documentada. No comprar dominio ni handles hasta decidir nombre final.
- [ ] La app usa dominio provisional `voza.app/support` en INSTALL.txt — decidir antes
      de publicar (o cambiar el texto).

## 5. Copy de la página (borrador EN, ES después)

> **Voza — Dictate. It pastes itself. Pay once.**
>
> Push-to-talk dictation for macOS. Hold a hotkey, speak, release — your words
> appear wherever your cursor is. Whisper runs 100% on your Mac; your audio
> never leaves it. Optional AI polish (local or cloud) cleans up the text
> before it pastes.
>
> - **$15 once.** No subscription. (Early Access price — rises at 1.0.)
> - **14-day trial**, no card.
> - **MIT source** — build it yourself and no license is needed.
> - **English & Spanish**, app and docs.
> - macOS 14+, Apple Silicon.
>
> *Early Access: this build is not notarized by Apple yet. Install takes one
> extra right-click → Open (guide included in the download).*

## 6. Post-launch (reglas de BUSINESS.md §5/§7)

- [ ] No pedir votos, no fabricar testimonios, no DMs sin autorización
- [ ] Primer canal: r/macapps con declaración de fundador (reglas del sub primero)
- [ ] Calendario de 30 días de BUSINESS.md §5 cuando haya beta testers
- [ ] Refunds < 5% y soporte < 15 min/comprador = métricas de §6
- [ ] Kill criteria §7 intactos: grabación que no para o destino inseguro detiene features

## 7. Roadmap de distribución (de aquí a notarizado)

| Fase | Gatillo | Acción |
|---|---|---|
| Hoy | — | DMG Early Access + guía (este doc) |
| 2 | ~10 ventas | Apple Developer $99/año → `scripts/release.sh` completo |
| 3 | dmg notarizado | Instalación de doble click; quitar el paso right-click de la copy |
| 4 | Tracción | Landing estática (hero Literal/Pulido, demo sin cortes, comparación) |
| 5 | Volumen | Stripe/Polar como segunda tienda (BUSINESS.md §2: Polar Starter recomendado) |
