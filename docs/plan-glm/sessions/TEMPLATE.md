# Cierre de sesión — completar antes de registrarlo como evidencia

## Identidad

- Fecha UTC:
- Ticket:
- Actor / modelo:
- Revisor:
- Checkout absoluto:
- Branch:
- Base SHA:
- HEAD SHA o sin commit autorizado:
- Estado de salida: in_progress / blocked / review / done

## Encargo y alcance autorizado

Registrar instrucción de la sesión y exclusiones. Distinguir revisión, implementación, pruebas con permisos/datos y release.

## Revalidación de entrada

Resultado de Git, dependencias, contratos leídos y cambios ajenos encontrados. Si se retomó una sesión interrumpida, explicar qué se conservó.

## Cambios por archivo

Ruta · símbolo · antes/después · motivo · migración o compatibilidad.

## Criterios de aceptación

AC ID · PASS / FAIL / NOT_RUN · comando/procedimiento exacto · HEAD/artefacto · evidencia · límite.

## Pruebas y comandos

Cada comando completo, cwd, entorno no sensible relevante, exit code, resultado, ruta persistente del log. No pegar secretos, transcripciones personales ni valores del clipboard real. La ausencia de salida no implica PASS si no se comprobó exit code.

## Verificación manual

Equipo/OS/app/micrófono · procedimiento · observación · limitaciones. Si no se ejecutó, decir NOT_RUN y qué impide hacerla; no sustituirla con un mock.

## Estado, recursos y datos

Qué está implementado, qué está integrado, procesos abiertos, temporales propios pendientes, datos del usuario tocados, riesgo de rollback. Un proceso arrancado no es una implementación terminada.

## Decisiones

ID de DECISIONS aceptado/propuesto, evidencia y decisión del propietario si fue necesaria. No atribuir al propietario una recomendación del agente.

## Próximo paso exacto

Archivo/símbolo a leer primero, AC pendiente, hipótesis que comprobar, comando de reproducción y condición para terminar. Debe ser utilizable sin leer la conversación.
