# Contrato — Servicios de dominio

## Repositorios

```swift
protocol VehicleRepository
protocol FuelEntryRepository
protocol UsageSnapshotRepository
protocol CaptureSessionRepository
protocol PhotoAssetRepository
protocol CalibrationRepository
```

Todos exponen operaciones asíncronas/throwing, aceptan IDs de dominio y no filtran tipos de SwiftData a capas superiores.

## Casos de uso

### AnalyzeCapture

- Entrada: sesión e imágenes locales.
- Salida: borrador y evidencia por campo.
- Efectos: guarda progreso de sesión; no crea evento definitivo.

### ConfirmFuelEntry / ConfirmUsageSnapshot

- Valida invariantes y revisión del usuario.
- Persiste evento, evidencia mínima y vínculos locales en una transacción lógica.
- Programa optimización de imágenes únicamente después de guardar de forma recuperable.
- Devuelve el registro canónico o error; nunca éxito parcial silencioso.

### EditEvent

- Conserva ID, incrementa revisión, actualiza `updatedAt` y recalcula analítica.
- Conserva auditoría de campos OCR/corregidos.

### DeleteEvent

- V2 local: elimina/archiva según política y limpia imágenes sin huérfanos.
- Preparación v2.1: crea `deletedAt` para entidades sincronizables.

### CalculateAnalytics

- Entrada: registros confirmados canónicos.
- Salida: métricas y procedencia real/estimada.
- No persiste resultados recalculables como fuente de verdad.

### ExportBackup / ValidateBackup / RestoreBackup

- Separación obligatoria entre validación y aplicación.
- Restauración atómica con resumen y rollback.

## Errores de dominio

Los errores usan códigos estables y contexto redactado:

- `odometer.regression`
- `trip.resetDetected`
- `financial.inconsistent`
- `fuelLevel.invalidStep`
- `tank.insufficientData`
- `entity.notFound`
- `repository.conflict`
- `migration.unsupportedVersion`
- `backup.integrityFailed`

La UI traduce códigos; no analiza strings técnicos.

## Idempotencia

- Confirmar dos veces el mismo `sessionID` devuelve el evento existente.
- Reintentar una migración completada no duplica datos.
- Aplicar una revisión remota ya observada no cambia el registro.
- Eliminar un archivo ya ausente es éxito solo si el registro confirma que debía estar eliminado.
