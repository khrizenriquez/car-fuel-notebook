# Modelo de datos — Cartrack v2

## 1. Convenciones

- UUID estable como identidad.
- Fechas UTC en persistencia; zona local solo en presentación.
- Unidades canónicas: kilómetros, galones estadounidenses y moneda ISO/importe decimal.
- Valores financieros con representación decimal segura; no `Double` en contratos cloud.
- Entidades sincronizables incluyen `createdAt`, `updatedAt`, `schemaVersion`, `revision` y `deletedAt`.
- Las imágenes son locales y no forman parte del DTO cloud.

## 2. Entidades

### Vehicle

| Campo | Tipo | Regla |
|---|---|---|
| `id` | UUID | estable, único |
| `name` | String | obligatorio |
| `make`, `modelName`, `engine` | String | opcionales en presentación |
| `year` | Int? | rango razonable |
| `plate` | String? | local/sensible; sync opcional explícito en 2.1 |
| `odometerUnit` | enum | mi/km |
| `tankCapacityGallons` | Decimal | >0 |
| `fuelScaleMax` | Decimal | >0, inicial 8 |
| `fuelScaleStep` | Decimal | >0, inicial 0.25 |
| `reserveThresholdRatio` | Decimal | 0...1 |
| `notes` | String | local por defecto |
| metadatos sync | SyncMetadata | obligatorios |

### FuelEntry

Representa una carga parcial o completa.

| Campo | Tipo | Regla |
|---|---|---|
| `id`, `vehicleID` | UUID | relación obligatoria |
| `occurredAt` | Date | obligatorio |
| `odometerKilometers` | Decimal | >0, continuidad validada |
| `tripKilometers` | Decimal? | ≥0 |
| `volumeGallons` | Decimal | >0 |
| `unitPrice` | Decimal | >0 |
| `totalCost` | Decimal | >0 |
| `currencyCode` | String | ISO 4217, inicial GTQ |
| `isFullTank` | Bool | cierra ciclo según reglas |
| `fuelLevelRemaining` | Decimal? | escala del vehículo |
| `stationName` | String? | opcional |
| `location` | LocationRecord? | opcional |
| `notes` | String? | opcional |
| `sourceSessionID` | UUID? | trazabilidad local |
| metadatos sync | SyncMetadata | obligatorios |

### UsageSnapshot

| Campo | Tipo | Regla |
|---|---|---|
| `id`, `vehicleID` | UUID | relación obligatoria |
| `occurredAt` | Date | obligatorio |
| `odometerKilometers` | Decimal | >0 |
| `tripKilometers` | Decimal? | ≥0 |
| `fuelLevelRemaining` | Decimal? | escala del vehículo |
| `location`, `notes` | opcionales | privacidad local configurable |
| `sourceSessionID` | UUID? | trazabilidad local |
| metadatos sync | SyncMetadata | obligatorios |

### CaptureSession (solo local)

| Campo | Tipo | Regla |
|---|---|---|
| `id` | UUID | único |
| `vehicleID` | UUID? | puede asignarse durante flujo |
| `kind` | fillUp/snapshot | obligatorio |
| `state` | draft/analyzing/review/confirmed/failedRecoverable/failedTerminal/discarded | máquina de estados |
| `createdAt`, `updatedAt` | Date | recuperación |
| `revision` | Int64 | control optimista de concurrencia |
| `lastErrorCode` | String? | sin datos sensibles |
| `confirmedEventID` | UUID? | obligatorio al confirmar |
| `draftPayload`, `draftSHA256` | Data codificable + digest | escritura atómica, integridad verificada al recuperar |

El borrador guarda valores canónicos y solo IDs de fotos, nunca bytes ni rutas. Al relanzar, `analyzing` pasa a `failedRecoverable` con `session.interruptedAnalysis`. El descarte vacía el borrador y elimina evidencia OCR no confirmada; la limpieza de archivos y `LocalPhotoAsset` corresponde a T14.

### LocalPhotoAsset (solo local)

| Campo | Tipo | Regla |
|---|---|---|
| `id`, `sessionID` | UUID | relación |
| `kind` | invoice/odometer/fuelLevel | obligatorio |
| `localRelativePath` | String | nunca cloud |
| `sha256` | String | integridad/deduplicación |
| `pixelWidth`, `pixelHeight` | Int | diagnóstico |
| `byteCount` | Int | presupuesto |
| `mimeType` | String | JPEG esperado |
| `capturedAt` | Date? | opcional |
| `optimizationState` | enum | original/optimizing/optimized/failed |
| `createdAt` | Date | obligatorio |

### OCRFieldEvidence

Conserva evidencia mínima por campo, no el grafo completo de Vision.

| Campo | Tipo | Regla |
|---|---|---|
| `id`, `sessionID` | UUID | relación |
| `field` | enum | odometer/trip/fuel/amount/price/volume/date/station |
| `rawText` | String? | mínimo necesario |
| `normalizedValue` | String? | representación estable |
| `unit` | String? | explícita |
| `confidence` | Decimal | 0...1 |
| `confidenceBand` | high/medium/low/critical | derivada versionada |
| `sourcePhotoID` | UUID? | local; no se sincroniza como ruta |
| `validationCodes` | [String] | causas estables |
| `wasManuallyCorrected` | Bool | auditoría |
| `algorithmVersion` | String | reproducibilidad |

Para v2.1 se sincroniza únicamente campo, valor final, confianza, corrección, versión y códigos mínimos. `rawText` puede excluirse si contiene información sensible no necesaria.

### GaugeCalibrationPoint

| Campo | Tipo | Regla |
|---|---|---|
| `id`, `vehicleID` | UUID | relación |
| `eventID` | UUID | fill o snapshot |
| `distanceSinceFullKilometers` | Decimal | ≥0 |
| `fuelLevelRemaining` | Decimal | escala del vehículo |
| `isConfirmed` | Bool | solo confirmados entrenan curva |

### SyncMetadata (embebido)

En el DTO de dominio está embebido en `VehicleRecord`, `FuelEntryRecord` y `UsageSnapshotRecord`. En SwiftData v2 se almacena como `SyncMetadataRecord` 1:1 por UUID, junto a `V2RecordExtras` para campos nuevos que no existían en las tablas físicas v1. Esta separación conserva la lectura v1 sin modificar su esquema.

| Campo | Tipo | Regla |
|---|---|---|
| `schemaVersion` | Int | ≥2 |
| `revision` | Int64 | monotónica por registro |
| `createdAt`, `updatedAt` | Date | UTC |
| `deletedAt` | Date? | tombstone |
| `originDeviceID` | UUID? | seudónimo local |
| `lastSyncedRevision` | Int64? | v2.1 |

## 3. Relaciones

```text
Vehicle 1 ── * FuelEntry
Vehicle 1 ── * UsageSnapshot
Vehicle 1 ── * GaugeCalibrationPoint
CaptureSession 1 ── * LocalPhotoAsset
CaptureSession 1 ── * OCRFieldEvidence
FuelEntry/UsageSnapshot 0..1 ── 1 CaptureSession (referencia de origen)
```

## 4. Invariantes

1. Un evento confirmado pertenece a un vehículo existente/no eliminado.
2. El odómetro no retrocede sin una corrección explícita y auditada.
3. `totalCost`, `unitPrice` y `volumeGallons` concuerdan dentro de tolerancia o requieren confirmación reforzada.
4. El nivel respeta máximo y paso del vehículo.
5. Una carga parcial no cierra un ciclo.
6. Solo puntos confirmados alimentan calibración.
7. Ninguna entidad cloud contiene bytes o rutas de imágenes.
8. Un tombstone conserva ID y revisión suficientes para sincronización futura.

## 5. Datos derivados no persistidos/sincronizados

- Resúmenes semanales y mensuales.
- Series para gráficas.
- Autonomía vigente.
- Detección de anomalías recalculable.
- Bounding boxes y tokens completos de Vision.
- Cachés de OCR/preprocesamiento.

Pueden existir cachés locales desechables, nunca como fuente de verdad.

## 6. Compatibilidad local durante v2

- Las cinco entidades SwiftData v1 permanecen físicamente intactas. `LocalPhotoAsset`, `OCRFieldEvidence`, `SyncMetadataRecord` y `V2RecordExtras` son aditivas.
- Las fotos antiguas conservan `ImageAsset.localPath`; las nuevas usan `LocalPhotoAsset.localRelativePath`. T14 verificará y optimizará archivos antes de migrar el índice legado.
- La evidencia OCR legada se crea solo cuando había texto OCR en el evento. Usa `algorithmVersion = legacy-v1`, banda `unknown`, confianza `0` y valor canónico; no duplica el texto OCR ni los bytes de la foto. La banda `unknown` es exclusiva de la procedencia legada.
- Las rutas, bytes de foto y texto OCR bruto son locales. T19 define por separado el DTO cloud mínimo y demuestra que no contiene esos campos.
