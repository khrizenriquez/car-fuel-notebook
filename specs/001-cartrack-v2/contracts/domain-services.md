# Contrato — Servicios de dominio

## Repositorios

```swift
protocol VehicleRepository
protocol FuelEntryRepository
protocol UsageSnapshotRepository
protocol PhotoAssetRepository
protocol OCRFieldEvidenceRepository
protocol CaptureSessionRepository
// T16: CalibrationRepository
```

Los cinco contratos T06 y `CaptureSessionRepository` de T07 exponen operaciones asíncronas/throwing, aceptan IDs de dominio y no filtran tipos de SwiftData a capas superiores. Sus adaptadores `SwiftData*Repository` trabajan con registros codificables de dominio y un `ModelContext` confinado al actor principal. Calibración se incorpora en T16.

`CaptureSessionRepository` permite crear, leer, enumerar sesiones reanudables, actualizar borradores por revisión, transicionar estado, descartar y recuperar análisis interrumpido. El adaptador guarda cada borrador en una sola fila con digest SHA-256 y contexto sin autosave. El arranque de la app realiza la recuperación de `analyzing` antes de mostrar la UI. La confirmación de eventos mediante caso de uso queda para T12.

El dominio usa `Decimal` para dinero, volumen, distancia y nivel; el adaptador traduce hacia/desde los `Double` físicos v1 sin exponerlos al consumidor. `SyncMetadata` es un valor del dominio; físicamente se guarda en `SyncMetadataRecord` 1:1 por UUID. `V2RecordExtras` conserva los nuevos valores que las cinco tablas v1 no tienen, sin alterarlas. Las revisiones obsoletas dan `repository.conflict`; un vehículo ausente da `entity.notFound`.

La app v1 heredada aún consulta algunas entidades SwiftData directamente durante la transición. Sus rutas de guardado actuales actualizan `SyncMetadataRecord` en el mismo `ModelContext`; T10–T12 reemplazarán los flujos de captura por casos de uso sobre estos repositorios. Ningún adaptador usa red, Supabase ni CloudKit.

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

T13 aplica `EventIntegrityPolicy` antes de crear una captura nueva y antes de mutar un evento editado. Exige odómetro positivo y coherente con los registros estrictamente anteriores/posteriores del mismo vehículo según fecha; un retroceso solo se autoriza con motivo explícito de al menos ocho caracteres. El motivo, valor corregido y código `odometer.regression` se anotan en la evidencia local del evento (`integrity-override-v1`) en el mismo guardado. El trip opcional admite reinicio: si es menor que el trip anterior se devuelve `tripResetDetected`, sin convertir la diferencia de trip en distancia negativa; un trip negativo o mayor que el odómetro se rechaza. Dos lecturas con idéntica fecha no se ordenan artificialmente.

El nivel debe estar en `[0, fuelScaleMax]` y en un múltiplo de `fuelScaleStep`; no se normaliza silenciosamente un valor inválido para aprobarlo. En llenados, galones, precio y monto deben ser positivos y `|galones × precio − monto| ≤ Q0.05` (tolerancia inyectable en el dominio). Una carga parcial no cierra el tanque ni produce consumo definitivo por sí sola: su volumen y costo se acumulan hasta el siguiente llenado completo, que cierra el ciclo iniciado por el llenado completo anterior. Las imágenes y el motivo permanecen locales; el contrato remoto v2.1 sigue limitado a metadatos estructurados mínimos.

## Idempotencia

- Confirmar dos veces el mismo `sessionID` devuelve el evento existente.
- Reintentar una migración completada no duplica datos.
- Aplicar una revisión remota ya observada no cambia el registro.
- Eliminar un archivo ya ausente es éxito solo si el registro confirma que debía estar eliminado.
