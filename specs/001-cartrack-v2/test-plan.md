# Plan de pruebas — Cartrack v2

## 1. Objetivo

Demostrar que Cartrack interpreta, valida, persiste, migra y presenta datos sin corrupción, y que una imagen insuficiente conduce a una recuperación segura.

## 2. Pirámide

### Núcleo

- Unidades y redondeos.
- Dinero y consistencia monto/precio/volumen.
- Continuidad de odómetro y reset de trip.
- Reglas de cargas parciales/completas.
- Confianza y selección de candidatos.
- Calibración y autonomía.
- DTO/versionado/conflictos.

**Gate:** `Scripts/check_core_coverage.sh 90`.

### Integración iOS

- Vision + preprocesamiento + parser.
- SwiftData + repositorios + migraciones.
- Archivos + hashes + optimización atómica.
- Exportación, validación y restauración.
- Reanudación de sesiones.

### Fixtures

Cada escenario declara:

- ID y tipo.
- Archivos requeridos.
- Campos visibles y valores esperados.
- Tolerancias.
- comportamiento de confianza/fallback.
- ejecución CI/simulador/dispositivo.

Fixtures privados permanecen ignorados. CI utiliza transcripciones y material sanitizado.

### UI/E2E

- Crear/seleccionar vehículo.
- Capturar/importar fotos.
- Ver precarga y confianza.
- Repetir foto problemática.
- Confirmar y guardar.
- Verificar historial y dashboard.
- Editar/eliminar/recalcular.
- Exportar/validar/restaurar.
- Recuperar borrador tras relanzar.

### Dispositivo físico

- Cámara real y permisos.
- Rendimiento/temperatura/memoria.
- Orientación y foreground/background.
- VoiceOver y Dynamic Type.
- Falta de espacio simulada cuando sea viable.

## 3. Matriz OCR mínima

| Clase | Gate | Resultado requerido |
|---|---|---|
| Factura clara | privado + parser | campos declarados dentro de tolerancia |
| Tablero nocturno | privado | odómetro/trip correctos o fallback seguro declarado |
| Tablero diurno | privado | odómetro/trip correctos o fallback seguro declarado |
| Indicador analógico | privado/UI | lectura calibrada o confirmación manual explícita |
| Imagen borrosa | integración/UI | issue de calidad y repetición selectiva |
| Imagen rotada/recomprimida | variantes | mismo resultado o degradación segura |
| Conflicto entre fotos | integración/UI | conflicto visible, sin selección silenciosa |

Tolerancias iniciales: odómetro ±1 mi, trip ±0.2 mi y valores impresos financieros ±0.01 salvo excepción del escenario.

## 4. Migración y respaldo

Fixtures de base/respaldo:

- v1 vacío.
- v1 con varios vehículos.
- v1 con fills, snapshots, ajustes e imágenes.
- respaldo v1 sin una imagen física.
- respaldo corrupto/hash inválido.
- UUID duplicado.
- interrupción simulada.

Se comparan IDs, conteos, relaciones, valores, timestamps y hashes antes/después.

## 5. Privacidad y red

- Escaneo de repositorio por fotos/secretos.
- Prueba que DTO no codifica rutas/bytes.
- Inspección de tráfico en recorridos v2: cero requests de captura/OCR.
- Gate que prohíbe el identificador de la base Supabase existente.

## 6. Rendimiento y almacenamiento

- Medir p50/p95 de preparación local con 1, 2 y 3 imágenes sintéticas de 1600×1200, después de warm-up.
- Medir memoria máxima incremental durante las mismas muestras.
- Verificar copia optimizada decodificable y ≤objetivo razonable.
- Ejecutar muestra representativa para proyectar ≤250 MB/año local.
- Serializar eventos futuros para proyectar ≤5 MB/año cloud.

**Evidencia T22 (iPhone 16 Pro, simulador iOS 18.2, Debug):** once muestras de
preparación local dieron: una foto p50 0.369 s/p95 0.404 s/+48.8 MB; dos fotos
p50 0.821 s/p95 0.856 s/+58.9 MB; tres fotos p50 1.232 s/p95 1.369 s/+59.0 MB
de pico incremental observado después de preparar cada imagen. En el simulador calibrado, el gate automatizado es p95 ≤5 s y aumento ≤160 MB. En GitHub Actions, el job declara un techo de regresión p95 ≤20 s mediante `CARTRACK_PERFORMANCE_P95_SECONDS`, porque su simulador compartido no es evidencia de rendimiento de producto; el reporte de las once muestras permanece adjunto. La evidencia
optimizada se limita a 450 KB/foto, por lo que 10 fotos semanales proyectan 234 MB/año.
`SyncPayloadBudget` serializa el DTO estructurado para mantenerlo bajo 5 MB/año.
Estas mediciones prueban el pipeline local reproducible; el corpus OCR privado y el
dispositivo físico se verifican en T23/T24 y no se sustituyen por imágenes sintéticas.

## 7. Accesibilidad/localización

- Recorrido P0 con VoiceOver.
- Dynamic Type XXL sin pérdida de controles.
- Contraste y estados no dependientes solo del color.
- Español/inglés y formatos regionales.
- Prueba de ausencia de literales críticos sin localizar.

**Evidencia T20:** `CartrackSmokeUITests.testP0CaptureWorkflowUsesEnglishAndExplicitPermissionActions` verifica navegación y etiquetas del recorrido P0 en inglés; el resto de la suite UI se inicia en español. `testP0CaptureControlsRemainReachableAtAccessibilityTextSize` verifica que los controles del registro de uso siguen alcanzables al tamaño de accesibilidad XXXL. `ReminderServiceTests` cubre copias de recordatorio en ambos idiomas. Los botones de cámara, fotos, ubicación y recordatorios exponen nombre y propósito para VoiceOver; la confianza conserva un estado textual además de su color. Las ubicaciones y notificaciones ya no se solicitan al abrir un formulario: sólo al tocar su acción explícita.

## 8. Gates y evidencia

**Evidencia T21:** `PersistenceIntegrationTests` cubre la clasificación de falta de
espacio, un respaldo corrupto que incluye una ruta privada en su error, la retención
de los 30 incidentes más recientes y la exportación JSON. La prueba verifica que el
archivo final contiene únicamente `formatVersion`, fecha, código estable, operación
permitida y acción sugerida; una operación que contiene una placa se sustituye por
`local.operation` y ni la placa ni la ruta aparecen en el artefacto.

**Evidencia T23:** en iPhone 16 Pro / iOS 18.2 de simulador, la suite UI limpia
terminó 17 aprobadas, 1 omitida intencionalmente y 0 fallos. El caso omitido es el
único que requiere una fototeca privada; se ejecutó aparte con esa fototeca y pasó
1/1. La matriz privada de Vision/OCR pasó 12/12, incluyendo tablero nocturno,
diurno, recomprimido, fallback seguro y una factura real. `PersistenceIntegrationTests`
pasó 15/15, incluida exportación, validación, restauración y rollback. Antes de
registrar esta evidencia, `check_v2_privacy.sh` confirmó que v2 no contiene APIs de
cliente de red ni configuración cloud, y que las fotos/PDF privados y su manifiesto
no están rastreados. Todas las ejecuciones usaron el mismo simulador, apagado al
finalizar; la comprobación física sigue en T24.

**Evidencia T24 (local):** `Scripts/verify_local.sh`, fijado al mismo UDID de
iPhone 16 Pro, pasó con 101 pruebas y 8 omisiones previstas por fixtures privados
ausentes en la suite pública. `Scripts/check_core_coverage.sh 90` pasó como parte
del gate. El Archive Release para `iphoneos` completó correctamente; la app es
exclusivamente iPhone y declara pantalla completa para no prometer multitarea de
iPad. El smoke físico y la confirmación de CI remoto siguen siendo gates manuales
de T24/T25, no evidencia implícita del simulador.

| Gate | Cuándo | Evidencia |
|---|---|---|
| pruebas focalizadas | cada commit | log local |
| core coverage | cada fase | salida ≥90% |
| suite pública | cada fase/final | `.xcresult` |
| suite privada | OCR/final | `.xcresult` + resumen por escenario |
| migración | fase B/final | fixture y reporte |
| E2E limpio | final | `.xcresult` |
| dispositivo físico | final | checklist con modelo/iOS |
| preflight | antes de push | salida limpia |
| CI remoto | después de push | URL del run |

Un test omitido por falta de fixture privado no cuenta como verde en la Mac del propietario.
