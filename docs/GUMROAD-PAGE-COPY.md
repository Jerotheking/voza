# Voza — Gumroad Page Copy (bilingüe, lista para pegar)

Estado: borrador para el dueño. Ajustar soporte/dominio cuando se decida marca (D045 §4).
Claims disciplina (BUSINESS.md §3): offline = con modelos descargados; audio local SIEMPRE;
cloud envía TEXTO (nunca audio) solo si el usuario activa Pulido cloud; sin cifras de
precisión no medidas. Nada aquí promete actualizaciones de por vida.

---

## ENGLISH (page top)

### Product summary (Gumroad "Summary" field)

Push-to-talk dictation for macOS. Hold a hotkey, speak, release — your words paste
wherever your cursor is. 100% local Whisper. $15 once, no subscription.

### Full description

**Dictate. It pastes itself. Pay once.**

Voza turns any text field into a voice field. Hold your hotkey, speak naturally,
release — the transcription is already pasted where your cursor is. No windows to
manage, no export step, no waiting room.

**How it works**

1. Hold your hotkey and speak.
2. Whisper (running 100% on your Mac) transcribes — your audio never leaves your machine.
3. Optional **Polish** cleans up the text before it pastes: filler-word removal, punctuation,
   formatting. Choose **Literal** (raw, fast) or **Polished** per dictation.
   Polish uses YOUR OWN cloud provider key (OpenAI/Anthropic), stored in your Mac's
   Keychain — it processes the *text*, never your audio, and it never runs without
   your explicit setup.

**What your $15 includes**

- Voza for macOS 14+ (Apple Silicon), one-time payment
- License key — verified once, then Voza works fully offline
- Bilingual app: English & Spanish, every screen
- 14-day free trial *before* paying, no card required
- MIT-licensed source: build it yourself and no license is needed at all

**Early Access, honest terms**

- This build is not notarized by Apple yet. First launch takes one extra
  approval: right-click → Open, **Open Anyway** in System Settings →
  Privacy & Security, or one Terminal command (30 seconds, illustrated
  guide inside the download).
- The speech model downloads on first run and stays on your Mac.
- **Your license includes one year of updates.** After that, pay what you
  want to stay current — or keep your last Early Access build forever; it
  keeps working either way. The Early Access price ($15) rises at 1.0;
  your price never does.

**Requirements**

- macOS 14 (Sonoma) or newer, Apple Silicon
- Microphone permission (to hear you), Accessibility + Input Monitoring (to paste
  and to learn your corrections). Voza walks you through each prompt in-app.

**FAQ**

- *Is my audio sent anywhere?* No. Transcription is local. Only if you enable cloud
  Polish does the transcribed *text* go to the provider you configured.
- *Does it work offline?* Transcription and Literal paste: yes, once the model is
  downloaded. License checks: verified once, then cached. (Optional cloud Polish
  needs internet, by definition.)
- *Can I get a refund?* Gumroad handles refunds; if Voza doesn't paste for you,
  write to support and we'll make it right.
- *Why cheaper than the alternatives?* No subscription, no investor, no server bill.
  Whisper is free software — you're paying for packaging that respects you.

**Support:** GitHub Discussions (link in the repo) · support email in your receipt.

---

## ESPAÑOL (section below, same order)

### Resumen del producto

Dictado push-to-talk para macOS. Mantén un atajo, habla, suelta — tus palabras se
pegan donde esté tu cursor. Whisper 100% local. $15 una vez, sin suscripción.

### Descripción completa

**Dicta. Se pega solo. Pago único.**

Voza convierte cualquier campo de texto en un campo de voz. Mantén tu atajo, habla
con naturalidad, suelta — la transcripción ya está pegada donde está tu cursor. Sin
ventanas que administrar, sin paso de exportación, sin sala de espera.

**Cómo funciona**

1. Mantén tu atajo y habla.
2. Whisper (corriendo 100% en tu Mac) transcribe — tu audio nunca sale de tu máquina.
3. El **Pulido** opcional limpia el texto antes de pegarlo: muletillas, puntuación,
   formato. Elige **Literal** (crudo, rápido) o **Pulido** por dictado.
   El Pulido usa TU PROPIA key cloud (OpenAI/Anthropic), guardada en el Llavero de
   tu Mac — procesa el *texto*, nunca tu audio, y nunca corre sin tu configuración
   explícita.

**Qué incluye tu pago de $15**

- Voza para macOS 14+ (Apple Silicon), pago único
- Llave de licencia — se verifica una vez y Voza funciona 100% offline
- App bilingüe: inglés y español, en todas las pantallas
- Prueba gratis de 14 días *antes* de pagar, sin tarjeta
- Código fuente con licencia MIT: compílalo tú mismo y no necesitas licencia

**Early Access, términos honestos**

- Este build aún no está notarizado por Apple. El primer arranque lleva una
  aprobación extra: clic derecho → Abrir, **Abrir igualmente** en Ajustes
  del Sistema → Privacidad y Seguridad, o un comando de Terminal (30
  segundos, guía ilustrada dentro de la descarga).
- El modelo de voz se descarga en el primer arranque y se queda en tu Mac.
- **Tu licencia incluye un año de actualizaciones.** Después, paga lo que
  quieras por seguir al día — o quédate con tu último build Early Access
  para siempre; sigue funcionando de cualquier forma. El precio Early
  Access ($15) sube en 1.0; el tuyo, nunca.
- Precio Early Access: **$15**. Sube en 1.0. El tuyo, nunca.

**Requisitos**

- macOS 14 (Sonoma) o más nuevo, Apple Silicon
- Permiso de micrófono (para escucharte), Accesibilidad y Monitoreo de entrada (para
  pegar y para aprender tus correcciones). Voza te guía por cada permiso en la app.

**Preguntas frecuentes**

- *¿Mi audio se envía a algún lado?* No. La transcripción es local. Solo si activas
  el Pulido cloud va el *texto* transcrito al proveedor que tú configuraste.
- *¿Funciona sin internet?* Transcripción y pegado Literal: sí, con el modelo
  descargado. Verificación de licencia: una vez, luego queda en caché. (El Pulido
  cloud opcional necesita internet, por definición.)
- *¿Puedo pedir reembolso?* Gumroad maneja los reembolsos; si Voza no te pega,
  escríbenos a soporte y lo arreglamos.
- *¿Por qué es más barato que las alternativas?* Sin suscripción, sin inversores, sin
  factura de servidores. Whisper es software libre — pagas por un empaquetado que te
  respeta.

**Soporte:** GitHub Discussions (link en el repo) · email de soporte en tu recibo.

---

## Checklist de publicación (dueño)

- [ ] Pegar EN arriba, ES abajo (Gumroad soporta secciones)
- [ ] Subir `Voza-0.3.0-early-access.dmg` + `.sha256` como archivos del producto
- [ ] Price $15 USD · License keys ON · permalink **`voza`**
- [ ] Summary field = el texto corto de arriba
- [ ] Cover: captura real de la app + logo SVG (nada de mockups, BUSINESS.md §4)
- [ ] Decir en algún lado que es bilingüe EN/ES — nadie más lo hace
