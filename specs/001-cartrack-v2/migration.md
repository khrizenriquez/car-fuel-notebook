# Migración v1 → v2

## 1. Objetivo

Actualizar datos y evidencia local sin pérdida, introducir metadatos cloud-ready y permitir rollback verificable. T05 establece el contenedor v2, la copia protegida y el versionado; T06 agrega los metadatos y repositorios de dominio sin mutar las cinco entidades físicas v1.

## 2. Precondiciones

- Detectar versión de esquema actual.
- Verificar espacio suficiente.
- Crear respaldo v1 y comprobar que puede decodificarse.
- Inventariar vehículos, fills, snapshots, ajustes e imágenes.
- No modificar la base Supabase existente ni depender de red.

## 3. Mapeo

| V1 | V2 |
|---|---|
| `Vehicle` | `Vehicle` + SyncMetadata |
| `FuelFillEvent` | `FuelEntry` + evidencia OCR mínima |
| `SnapshotEvent` | `UsageSnapshot` + evidencia OCR mínima |
| `ImageAsset` | `LocalPhotoAsset` con hash/dimensiones/bytes |
| OCR strings en evento | `OCRFieldEvidence` cuando pueda inferirse; texto legado conservado |
| timestamps existentes | conservar; completar faltantes de manera documentada |

Los valores canónicos actuales no se recalculan destructivamente durante migración. La nueva analítica se calcula después desde los registros migrados.

## 4. Secuencia

1. Adquirir bloqueo local exclusivo y verificar espacio libre para respaldo + staging.
2. Abrir el store v1 con las cinco entidades físicas originales e inventariar campos, relaciones e imágenes con huella SHA-256; una foto ausente queda como referencia ausente, no se inventa evidencia.
3. Crear respaldo SQLite online consistente y comprobar `integrity_check`; guardar manifiesto con huellas del respaldo y del inventario.
4. Crear un store v2 candidato con nombre UUID, sin tocar el store v1.
5. Copiar vehículos, eventos, ajustes e índices de fotos preservando UUID, relaciones, timestamps, valores y texto OCR legado.
6. Recalcular el inventario del candidato y exigir igualdad exacta de conteos y huella de campos/relaciones/imágenes.
7. Guardar marcador de versión 2 y activar el candidato con un archivo puntero escrito atómicamente.
8. En T06 crear los metadatos `SyncMetadata`, `LocalPhotoAsset` y `OCRFieldEvidence` como entidades adicionales; en T14 optimizar las fotos locales de manera diferida. La analítica derivada se recalcula, no se migra como fuente de verdad.
9. Conservar el store y respaldo v1 mientras sea necesaria la recuperación; no existe acceso a red ni a Supabase en esta secuencia.

## 5. Rollback

Si falla cualquier paso antes de activar el candidato, el puntero no cambia y v1 sigue utilizable; un candidato incompleto queda inactivo y puede eliminarse de forma segura en una limpieza posterior. La activación atómica es la última operación de la migración. Si un arranque posterior detecta un puntero o marcador corrupto, la app muestra error de persistencia y conserva v1 y su respaldo para recuperación explícita; nunca crea silenciosamente una base vacía.

Nunca se elimina el único original de una imagen durante la misma transacción que migra el store.

## 6. Compatibilidad de respaldo

- V2 puede importar respaldo v1.
- La validación informa imágenes ausentes sin convertirlas en corrupción de registros.
- V2 exporta formato v2 con imágenes opcionales.
- Un respaldo cloud futuro restaura solo estructura y marca evidencia local como no disponible.

## 7. Criterios de aceptación

- Conteos por entidad iguales antes/después.
- UUID y relaciones preservados.
- Valores financieros y distancias sin cambio no autorizado.
- Todas las imágenes existentes abren y coinciden con hash inventariado.
- Repetir migración no duplica registros.
- Fallo inyectado en cada etapa deja v1 utilizable.
- Suite de analítica pasa sobre datos migrados.
- La transición T06 no modifica en sitio las cinco entidades físicas v1; las nuevas entidades v2 se agregan al esquema v2.
