# Migración v1 → v2

## 1. Objetivo

Actualizar datos y evidencia local sin pérdida, introducir metadatos cloud-ready y permitir rollback verificable.

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

1. Adquirir bloqueo de migración.
2. Exportar respaldo v1 validado.
3. Crear staging v2.
4. Copiar vehículos y completar UUID/metadatos.
5. Copiar eventos y relaciones.
6. Hash/inventario de imágenes sin recomprimir todavía.
7. Crear evidencia OCR legado con confianza `unknown` y algoritmo `legacy-v1`.
8. Validar invariantes, conteos y checksums.
9. Activar staging como store principal.
10. Recalcular caches/analítica.
11. Optimizar imágenes de forma diferida, una por una y con reemplazo atómico.
12. Conservar respaldo v1 hasta confirmación del usuario o periodo seguro.

## 5. Rollback

Si falla cualquier paso antes de activar staging, se descarta staging y se conserva v1. Si falla después, se restaura el respaldo v1 y se mantiene un diagnóstico redactado.

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
