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

- Medir p50/p95 de análisis con 1, 2 y 3 imágenes.
- Medir memoria máxima.
- Verificar copia optimizada decodificable y ≤objetivo razonable.
- Ejecutar muestra representativa para proyectar ≤250 MB/año local.
- Serializar eventos futuros para proyectar ≤5 MB/año cloud.

## 7. Accesibilidad/localización

- Recorrido P0 con VoiceOver.
- Dynamic Type XXL sin pérdida de controles.
- Contraste y estados no dependientes solo del color.
- Español/inglés y formatos regionales.
- Prueba de ausencia de literales críticos sin localizar.

**Evidencia T20:** `CartrackSmokeUITests.testP0CaptureWorkflowUsesEnglishAndExplicitPermissionActions` verifica navegación y etiquetas del recorrido P0 en inglés; el resto de la suite UI se inicia en español. `testP0CaptureControlsRemainReachableAtAccessibilityTextSize` verifica que los controles del registro de uso siguen alcanzables al tamaño de accesibilidad XXXL. `ReminderServiceTests` cubre copias de recordatorio en ambos idiomas. Los botones de cámara, fotos, ubicación y recordatorios exponen nombre y propósito para VoiceOver; la confianza conserva un estado textual además de su color. Las ubicaciones y notificaciones ya no se solicitan al abrir un formulario: sólo al tocar su acción explícita.

## 8. Gates y evidencia

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
