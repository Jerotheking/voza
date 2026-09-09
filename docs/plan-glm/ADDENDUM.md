# Addendum y límites de la auditoría

Fecha: 2026-09-07. Estado: DOCUMENTACIÓN; app no modificada.

## Revalidación en la sesión de handoff

[VERIFIED] HEAD continúa en `44caaf145c4e1e77d53afbc31dfdd1e3c79aaabf`. Se volvieron a localizar los símbolos afectados, el recorder, el paquete y los callers. `git status --short` no reportó cambios antes de crear `docs/plan-glm/`. Los hashes de los archivos originales están en [evidence/baseline.json](evidence/baseline.json).

[VERIFIED] La auditoría original se copió íntegra de la respuesta final de esta tarea: 104.964 caracteres antes de la cabecera de archivo histórico. No se copiaron transcriptos privados, secretos, otras tareas ni dumps del perfil. Su última frase de “no creé un archivo” describe aquella fase; la petición posterior autoriza ahora este paquete documental.

## No confundir evidencia con hipótesis

- F01: discrepancia de constantes confirmada por código y SDK. No se realizó una prueba de teclado físico de Voza.
- F04: el camino de estado que puede dejar la captura activa está establecido en código; no se provocó el fallo durante una grabación real.
- F05: se reprodujo bloqueo de un productor finito con pipe; no una transcripción larga bloqueada dentro de la app.
- F06: ausencia de aislamiento/errores explícitos es observable; la carrera exacta depende de garantías de AVAudioEngine y debe investigarse antes de afirmar un crash reproducido.
- F02: falta política de campos seguros; no se grabó una contraseña ni se demostró exfiltración.
- El CLI transcribió el sample de 11 s en 0,805 s en la fase anterior. No se repitió aquí; no es un benchmark de otros equipos ni E2E de la app.
- El binario existente tenía firma ad hoc. Eso no establece por sí solo el estado actual de la cuenta Apple del propietario.
- El código usa swift-tools-version 5.9. La versión instalada del compilador Swift 6.3.3 no prueba que el paquete esté en modo de concurrencia estricta Swift 6.
- Las búsquedas de mercado pertenecen a la fecha del informe. Revalidar tarifas, planes, licencias de modelos y claims antes de comprar, empaquetar o publicar.
- `SHA-256 coincide con catálogo` no demuestra confianza de toda la cadena de suministro. Hay que verificar origen y licencia del artefacto seleccionado.

## Precisiones nuevas para ejecutar bien

1. No interpretar todos los textos entre paréntesis como ruido: `(no enviar)` es contenido válido.
2. No implementar booleanos paralelos `cleanup`, `polished`, `smart` sin un modo canónico. Migración explícita.
3. `requestedMode`, `processingStatus` y `appliedMode` son distintos. Procesar un texto ya correcto puede no modificarlo; no implica fallo del modelo.
4. Decir “el modelo es multilingüe” no garantiza que preserve una mezcla de idiomas dentro de la misma frase.
5. Un check de `NSPasteboard.changeCount` no evita lectura de un gestor de clipboard. Verificar la semántica real de contador después de escribir; no fijar aritmética por un comentario del código.
6. AX no cubre todas las apps. Con destino desconocido se permite transcribir a recuperación en RAM, sin pegado automático; con destino seguro o sesión bloqueada se prohíbe captura. No convertir unknown en seguro ni en una prohibición total del producto.
7. Un evento de sesión no equivale necesariamente a todos los casos de bloqueo de pantalla. V08 debe identificar APIs soportadas, contrastar fuentes oficiales y probar el comportamiento del SO.
8. Empaquetar whisper-cli no hace una primera instalación offline: también hace falta modelo. Ofrecer paquete offline importable y probarlo si se anuncia.
9. No ampliar la eliminación de temporales a `~/Dictation`, `/tmp/*.wav`, modelos ajenos o directorios completos. La app solo elimina recursos cuya propiedad puede demostrar.
10. Un `settings.json` nuevo debe conservar los valores legacy observables y los archivos originales. Si no puede importar, mostrar error y usar un modo seguro sin enviar texto a cloud.
11. La salida literal de ASR puede normalizar puntuación. Literal significa sin etapa adicional de reescritura, no transcripción judicial palabra por palabra.
12. El usuario aprobó dos modos y automatización técnica. Precio, plataforma de pagos, nombre, modelo de Pulido y alcance de licencias siguen siendo propuestas, no decisiones cerradas.

## Puntos históricos que deben preservarse

El informe completo mantiene las 14 correcciones de Sprint 0, los 20 hallazgos, los escenarios, la matriz de competidores, diez testimonios, 18 funciones, los cálculos de comisiones, copy, plan y log. Las especificaciones de este paquete detallan cómo convertirlos en trabajo; no sustituyen la fuente histórica ni borran sus límites.
