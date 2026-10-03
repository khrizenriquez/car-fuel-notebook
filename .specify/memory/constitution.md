# Constitución de Cartrack

**Versión:** 1.0.0
**Ratificada:** 2026-10-03
**Aplica a:** Cartrack v2 y preparación de sincronización v2.1

## 1. Integridad antes que automatización

Cartrack no inventa, completa silenciosamente ni convierte en cero un dato que no pudo leer. El OCR propone valores con procedencia y confianza por campo; las reglas de dominio determinan si son aceptables. Todo registro se confirma antes de guardarse. Una alternativa manual segura es preferible a persistir una lectura incorrecta.

Toda operación que cambie datos debe mantener las invariantes documentadas, ser comprobable y producir un error recuperable cuando no pueda completarse.

## 2. Local-first y privacidad por diseño

La aplicación debe funcionar completamente sin conexión. Fotografías, recortes, miniaturas, coordenadas de Vision y artefactos intermedios permanecen en el dispositivo. V2 no requiere cuentas, servidor ni red.

La preparación de v2.1 solo permite sincronizar datos estructurados mínimos. Queda prohibido subir imágenes, Base64, rutas locales o diagnósticos sensibles. La base Supabase preexistente de aproximadamente 20 MB está fuera del alcance y no puede consultarse, migrarse ni modificarse. Cartrack utilizará un proyecto independiente cuando se implemente v2.1.

## 3. Evidencia, confianza y confirmación

Cada campo automatizado debe conservar su fuente lógica, texto reconocido mínimo, valor normalizado, confianza y estado de corrección. El usuario confirma el formulario precargado antes del guardado. Los campos de confianza media se resaltan; los de confianza baja permanecen vacíos o presentan candidatos sin seleccionarlos automáticamente.

Después de un OCR exitoso y de la confirmación, la evidencia local se conserva como JPEG optimizado, máximo 2000 px y calidad objetivo 70–75%, salvo que una prueba de legibilidad exija otro límite. El original temporal se elimina solo después de verificar la copia optimizada.

## 4. Requisitos trazables y pruebas proporcionales al riesgo

Todo requisito funcional o no funcional debe tener:

1. identificador estable;
2. escenario de aceptación;
3. prueba o gate asociado;
4. estado observable;
5. evidencia de verificación.

La cobertura del núcleo debe ser al menos 90%, pero nunca sustituye pruebas de comportamiento. OCR requiere fixtures sanitizados en CI y fixtures privados reales en el gate local. Persistencia, migraciones, respaldo y eliminación exigen pruebas de integración. Los recorridos críticos exigen UI/E2E y validación final en un iPhone físico.

## 5. Migraciones y recuperación sin pérdida

Los datos existentes son patrimonio del usuario. Antes de una migración potencialmente destructiva se crea y valida un respaldo. Las migraciones son versionadas, idempotentes y probadas desde cada versión compatible. Una importación se valida antes de reemplazar datos y se aplica transaccionalmente.

Supabase nunca será el único respaldo de fotografías. Una restauración desde nube futura recuperará datos estructurados; las imágenes solo se recuperarán desde un respaldo local que las incluya.

## 6. V2 cloud-ready, no cloud-dependent

Las entidades sincronizables usan UUID estable, `createdAt`, `updatedAt`, versión de esquema, revisión y `deletedAt`. El dominio no depende de SwiftData ni de Supabase directamente. Repositorios y operaciones de sincronización deben ser idempotentes.

V2.1 puede añadir autenticación y sincronización estructurada sin cambiar las reglas del dominio. No se incorporan SDK, credenciales, endpoints ni tráfico de Supabase durante v2.

## 7. Flujo trunk-based con commits atómicos

Todo el trabajo de Cartrack v2 vive en una sola rama: `codex/cartrack-v2`. No se crean ramas por tarea. Cada elemento ejecutable de `specs/001-cartrack-v2/tasks.md` corresponde exactamente a un commit funcional y verificable.

Cada commit debe:

- tener un único propósito;
- incluir sus pruebas y documentación relacionadas;
- dejar el proyecto compilable;
- ejecutar el gate especificado en la tarea;
- no mezclar cambios ajenos o secretos;
- usar el asunto de commit definido en `tasks.md`.

Al terminar se ejecutan todos los gates sobre el mismo commit candidato, se sube la rama y se crea un pull request. Si la creación automática del PR no está disponible, se entrega la rama publicada y la información necesaria para crearlo manualmente.

## 8. Estados normativos

- `CURRENT`: existe en la línea base, sin afirmar que cumpla v2.
- `GAP`: falta, falla o no está verificado.
- `TARGET-V2`: comportamiento obligatorio de v2.
- `DEFERRED-2.1`: diseño preparado, implementación pospuesta.
- `VERIFIED`: existe evidencia vigente en el commit candidato.

Solo `VERIFIED` equivale a terminado.

## Gobierno

Esta constitución prevalece sobre planes, ADR anteriores y conveniencia de implementación. Los ADR siguen siendo contexto histórico. Toda excepción requiere una enmienda explícita con motivo, impacto, plan de migración y actualización de versión.

Antes de marcar v2 como lista deben estar verificados `spec.md`, `acceptance-matrix.md`, `test-plan.md`, `migration.md` y `release-checklist.md` en el mismo commit candidato.
