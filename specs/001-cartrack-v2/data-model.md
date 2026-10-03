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
| `state` | draft/analyzing/review/confirmed/failed | máquina de estados |
| `createdAt`, `updatedAt` | Date | recuperación |
| `lastErrorCode` | String? | sin datos sensibles |
| `draftPayload` | codificable | escritura atómica |

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
