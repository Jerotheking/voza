# Negocio, distribución y operación

> **Actualización ejecutiva (2026-10-14, D048–D054):**
> - **Propuesta de valor (Hero):** *"Dicta. Se pega solo. Y aprende cuando corriges una palabra."* El diferenciador competitivo frente a opciones gratuitas (Spokenly, TypeWhisper, Handy) es el **bucle de Auto-Learn invisible (`CorrectionWatcher` + `CorrectionStore`, incl. Electron/Chromium sin VoiceOver)** + **soporte bilingüe EN/ES nativo** + **Daily Log en Markdown (`~/Dictation/YYYY-MM.md`)** + **Cloud AI opt-in en Keychain (Groq / OpenAI / Anthropic)**.
> - **Precio y pasarela en 2 etapas (`D053`):** Etapa 1 (Early Access): **$15 pago único** en Gumroad (`jerotherey.gumroad.com/l/voza`, incluye 1 año de actualizaciones + pay-what-you-want opcional posterior per `D046`). Etapa 2 (v1.0 notarizado): **$29 pago único**, migrando nuevas ventas a **Polar.sh** (~4%+$0.40 MoR, ~8.3% efectivo vs ~18.2% en Gumroad) y manteniendo compatibilidad Gumroad en `LicenseManager` para compradores EA.
> - **Informe completo de auditoría:** Ver [AUDITORIA-INTEGRAL-2026-10.md](../AUDITORIA-INTEGRAL-2026-10.md).

Estado: propuestas; ver decisiones D010–D013. La investigación y cálculos completos están preservados en AUDITORIA-ORIGINAL, secciones 4 y 6. No reconsultados en esta fase de documentación; tarifas y licencias deben revalidarse antes de usarse para una decisión real.

## 1. Posicionamiento a validar

“Dictado local para Mac: Literal cuando quieres rapidez, Pulido cuando quieres escribir mejor. Tú eliges; Voza prepara el resto.” Solo publicable después de implementación y evidencia de ambas rutas. No “10% de Superwhisper”: el informe encontró alternativa Whisper local gratuita, VoiceInk $25 y $29/$249,99=11,6%, además de diferencias de alcance.

ICP propuesto: personas individuales con Apple Silicon que dictan mensajes/prompts/notas cortas ES/EN y no quieren administrar IA. No afirmar que nadie atiende español. Validar con uso y pago, no solo quejas públicas sobre suscripciones.

## 2. Precio y proveedores

$29 founder → $39 estándar es propuesta, no precio aprobado por este handoff. Ambos modos incluidos. Trial 14 días sin tarjeta y sin bloqueo sigue siendo hipótesis inicial; no castigar offline ni añadir DRM. Antes de cambiar términos averiguar compradores existentes y promesa de actualizaciones de por vida de la landing. No deshacer derechos anteriores por conveniencia.

Snapshot de tarifas consultado 2026-09-07: Gumroad directo/tarjeta se calculó con 12,9%+$0,80; Polar Starter/Paddle/Lemon base 5%+$0,50; Polar Pro 3,8%+$0,40 y $20/mes. Sobre $29 y $10k/mes, original calcula costes respectivos $4,54/$1.565,86; $1,95/$672,41; $1,50 variable/$537,93 incluyendo mensualidad. Son escenarios sin impuestos añadidos, payout, FX, afiliados ni refunds. Stripe México+Tax usa FX hipotético 18, no tipo actual. No reutilizar como cotización sin país/banco/tarjetas.

Recomendación original Polar Starter sujeta a elegibilidad/payout y decisión del propietario. V13 arregla Gumroad existente; V29 decide migración y, si se aprueba, debe abrir un ticket específico con fixtures del nuevo adapter. No esconder una migración de pagos dentro de un refactor de licencia.

## 3. Marca y claims

Se encontraron productos Voxa de dictado y un proyecto OSS. Es evidencia de colisión de búsqueda, no dictamen jurídico. Antes de marca final: pronunciación ES/EN, dominio/handles, búsquedas en categoría y revisión de marcas de mercados pertinentes. No cambiar bundle ID ni ruta de datos junto con logo sin plan de migración de permisos/licencias.

Claims deben apuntar a evidencia: app/OS, versión, checksum del binario, escenario probado. Offline solo si assets presentes; no telemetry distinto de cero red; privacidad de audio distinta de clipboard/historial/texto cloud; attempted distinto de confirmed. No anunciar tasas de precisión del proveedor como medición de Voza.

## 4. Landing y materiales

Orden: hero con Literal/Pulido → demo sin cortes → comparación de modos → preparación por hardware → privacidad concreta → apps realmente probadas → precio/trial → FAQ/soporte. Tres titulares propuestos: “Habla. Elige Literal o Pulido. Sigue trabajando.”; “Tu voz, sin configurar modelos.”; “Dicta rápido. O deja que Voza lo pula.”

Press kit: icono/logo definitivo, capturas sintéticas del binario real, video ES/EN, descripción 50/150 palabras, requisitos, límites, política de datos, precio, soporte y changelog. Sin mockups presentados como captura real. GitHub Discussions antes de abrir otro canal Discord sin demanda.

## 5. Lanzamiento y contenido

Beta privada primero; luego r/macapps con declaración de fundador y demo; r/LocalLLaMA con motor/corpus/memoria; Show HN con producto utilizable; Product Hunt después de corregir primeros fallos. Consultar reglas actuales antes de publicar. No pedir votos, fabricar testimonios ni enviar mensajes sin autorización. Patrocinios solo con presupuesto aprobado y conversión orgánica observada.

Calendario de 30 días posterior al gate de beta (producción/reutilización de una pieza principal por semana):

| Día | Trabajo |
|---|---|
| 01 | Demo Literal/Pulido sin cortes |
| 02 | Ejemplo español y modo aplicado |
| 03 | Ejemplo inglés comparable |
| 04 | Problema que motivó el producto |
| 05 | Recoger preguntas y agrupar fricciones |
| 06 | FAQ de permisos con capturas actuales |
| 07 | Responder soporte autorizado |
| 08 | Instalación sin Homebrew demostrada |
| 09 | Qué significa offline con modelos presentes |
| 10 | Fallos corregidos con evidencia |
| 11 | Autocorrección martes/perdón/jueves |
| 12 | Negaciones que no se eliminan |
| 13 | Caso de abstención de Pulido |
| 14 | Recuperar el original |
| 15 | Experiencia de beta tester con consentimiento |
| 16 | Comparación honesta con alternativa gratuita |
| 17 | Precio único y límites de actualizaciones |
| 18 | Hardware mínimo probado |
| 19 | Protección de destino y sus límites |
| 20 | Changelog de la semana |
| 21 | Historia de uso bilingüe autorizada |
| 22 | Atajo y toggle |
| 23 | VoiceOver solo si validado |
| 24 | Historial off y recuperación RAM |
| 25 | Preguntas públicas si autorizado |
| 26 | Tutorial corto completo |
| 27 | Demo en app pedida y probada |
| 28 | Límites conocidos |
| 29 | Mejoras a partir de beta |
| 30 | Resultados y siguiente decisión |

## 6. Métricas y experimentos

Objetivos originales, no datos: 20 beta testers, ≥80% primera dictación sin asistencia, ≥60% uso a una semana en cohorte voluntaria; 3.000 visitas→300 descargas→30 compras; refunds<5%; soporte<15 min/comprador. No tratar muestras pequeñas como significancia estadística. 30 ventas a $29=$870 brutos: validación, no retorno de tres meses.

Web/downloads pueden contarse agregadamente con sesgo de retries/devices. Pago/licencia son datos comerciales. Primera dictación y retención solo mediante cohortes consentidas/exportación voluntaria local; no deducirlas de activar licencia. No agregar identificador persistente de uso para completar el funnel. Exportar diagnóstico con previsualización y sin texto/audio/keys/rutas personales.

## 7. Checkpoints y kill criteria

Día 14: si hay grabaciones que no paran o destino inseguro, detener features. Día 30: si preparación requiere soporte frecuente, no vender hands off. Día 45–60: si ningún procesador local pasa ES con latencia viable, reformular alcance de Pulido sin cloud silencioso. Tras beta: si no hay beneficio identificable frente a gratis, recortar/pivotar. Día 90: analizar activación y soporte antes de bajar precio. Incidente de privacidad o edición crítica detiene la versión afectada.

Ventanas relativas a trabajo/etapa reales; el calendario no convierte un gate pendiente en aprobado. Leer ROADMAP para presupuesto revisado: el plan detallado puede superar 90 días.

## 6. Benchmark competitivo macOS (2026-10, D065)

| Producto | Precio / Modelo | Motor STT y Pulido IA | Fortalezas | Debilidades frente a Voza | Diferenciador de Voza (`HEAD` + `D064`–`D065`) |
|---|---|---|---|---|---|
| [Wispr Flow](https://wisprflow.ai/pricing) | `$15/mes` (`$144/año`) | 100% Cloud (sube audio a servidores) | UX pulida, comandos de voz y formateo rápido (~700 ms) | Suscripción anual cara, requiere internet siempre, envía audio a la nube, app Electron pesada | Binario nativo Swift (~5 MB), audio 100% local (`whisper.cpp` Metal embebido), activación híbrida Tap/Hold en `Option` (`D064`) y pago único (`$15` Early Access / `$29` v1.0). |
| [Superwhisper](https://superwhisper.com/docs/billing/plans) | Gratis limitado · `$8.49/mes` · `$249.99` lifetime | Whisper/Parakeet local + LLMs locales/Cloud | Modos personalizables y soporte offline/cloud | Lifetime de `$249.99`, configuración compleja de modelos/modos y diccionario manual | `8–16×` más accesible en pago único, selección automática de modelo por RAM (`HardwareProfile`) y **Auto-Learn invisible** (`CorrectionWatcher` + `CorrectionStore`). |
| [Aqua Voice](https://aquavoice.com/pricing) | `$8–$24/mes` suscripción | Cloud propietario de baja latencia | Inserción rápida y buena precisión en código/inglés | Solo suscripción mensual y dependiente de la nube | Con el preset 1-clic de **Groq (`llama-3.3-70b-versatile`, ~180 ms)** (`V18`/`D065`), Voza logra pulido instantáneo BYOK manteniendo el audio 100% en la Mac. |
| [MacWhisper](https://goodsnooze.gumroad.com/l/macwhisper) | Gratis básico · `€64` Pro pago único | Whisper / Parakeet local | Transcripción de archivos de audio/video y reuniones | El dictado en vivo es secundario dentro de una app de archivos | Voza vive 100% en la barra de menú (`LSUIElement`) con HUD flotante no intrusivo (`D020`), popover amplio de 20 transcripciones (`D064`) y aprendizaje automático post-pegado. |
| [VoiceInk](https://tryvoiceink.com/) / [TypeWhisper](https://www.typewhisper.com/en/) / [Spokenly](https://spokenly.app/) | Gratis / Open-source / `$19–$39` pago único | Whisper local + BYOK API keys | Ligeras, privadas y sin suscripción | Diccionario manual: si falla un nombre propio o término técnico hay que abrir ajustes y agregarlo a mano | Bucle cerrado de aprendizaje local (`CorrectionWatcher` + `CorrectionStore` + `--prompt` de Whisper + reemplazo exacto con bordes Unicode `D063`). |

