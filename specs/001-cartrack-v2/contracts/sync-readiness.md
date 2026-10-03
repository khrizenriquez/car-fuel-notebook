# Contrato — Preparación de sincronización v2.1

**Estado:** `DEFERRED-2.1`; v2 implementa tipos y límites, no red.

## Aislamiento obligatorio

- La base Supabase existente (~20 MB) no se toca.
- V2.1 requiere un proyecto nuevo y un identificador de proyecto distinto.
- Ninguna configuración real se versiona.
- Un gate debe fallar si el identificador prohibido aparece en el proyecto.

## Datos permitidos

- Vehículos con campos autorizados.
- Cargas y snapshots.
- Evidencia OCR mínima por campo.
- Calibración confirmada.
- Metadatos de versión, revisión y tombstone.
- Preferencias sincronizables no sensibles.

## Datos prohibidos

- Originales, copias optimizadas, miniaturas o recortes.
- Base64/blob de imagen.
- Rutas locales.
- Tokens completos/bounding boxes de Vision.
- Cachés, gráficas o métricas recalculables.
- Diagnósticos o notas sensibles sin consentimiento específico.

## DTO

Cada DTO usa:

- UUID estable;
- `ownerID` asignado por Auth en 2.1;
- `schemaVersion`;
- `revision`;
- timestamps UTC;
- `deletedAt` opcional;
- valores decimales serializados sin pérdida.

## Conflictos

- Campos no críticos pueden usar revisión más nueva con auditoría.
- Odómetro, datos financieros y relación con vehículo requieren validación semántica.
- Conflictos concurrentes críticos quedan pendientes de resolución del usuario.
- Las operaciones son idempotentes por `(id, revision)`.

## Presupuesto

- Objetivo: ≤5 MB por usuario/año a cinco eventos por semana.
- No guardar payloads duplicados ni resultados derivados.
- Medir tamaño serializado e impacto real de índices antes del lanzamiento 2.1.

## Recuperación

Una instalación nueva puede restaurar datos estructurados. Debe indicar claramente que las fotografías no están disponibles y ofrecer importar un respaldo local con imágenes.
