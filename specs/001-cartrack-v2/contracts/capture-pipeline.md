# Contrato — Canalización de captura y OCR

## Entrada

```swift
CaptureRequest(
  sessionID: UUID,
  vehicleContext: VehicleContext?,
  kind: .fillUp | .snapshot,
  images: [CaptureImage]
)
```

Cada imagen incluye ID, tipo declarado opcional, orientación y ubicación local temporal. No incluye URLs remotas.

## Etapas

1. `quality`: produce métricas y problemas recuperables.
2. `classification`: determina factura/odómetro/combustible/otra.
3. `preprocessing`: genera variantes temporales; no se persisten.
4. `recognition`: Vision produce observaciones.
5. `candidateExtraction`: asigna observaciones a campos.
6. `crossValidation`: aplica contexto, continuidad, rangos y ecuaciones.
7. `confidence`: puntúa por campo y produce banda.
8. `draftAssembly`: crea un borrador precargado.

T08 implementa la preparación local previa a OCR: normaliza orientación, muestrea una imagen de 96 px para métricas de nitidez/exposición/color/borde, clasifica de forma conservadora con el tipo declarado como pista y genera variantes temporales de máximo 2200 px (`normalized`, `highContrast`, `monochrome`, `redDisplay` para tablero). La salida son objetos `CGImage` en memoria, sin rutas ni escritura a disco. El tablero no se divide automáticamente en odómetro frente a nivel de tanque si falta una pista confiable; se devuelve `other`. T10 conectará esta preparación al flujo de captura. Las métricas de calidad no equivalen por sí solas a confirmación automática.

T09 implementa `FieldCandidateScorer` en el dominio (`field-confidence-v1`). Cada candidato conserva ID, campo canónico, valor tipado, texto bruto, unidad, ID de foto, método, confianza OCR y calidad de imagen. La puntuación inicial es `0.75 × confianza OCR + 0.25 × calidad`; acuerdo de al menos dos fotos independientes suma 0.05 (máximo 1). Variantes de una misma foto no se cuentan como corroboración. Alta es ≥0.85; media ≥0.65; baja <0.65 y no se selecciona; crítica representa candidato ausente requerido, rango/tipo inválido, contradicción confiable o ecuación incoherente. Un medidor analógico sin calibración queda topado en 0.60. Se preservan todos los candidatos, incluso alternativas rechazadas, para revisión y auditoría. T10 conecta los valores reales del llenado con estos candidatos; T11 hará lo mismo con registros de uso y T12 aplicará las bandas a la UI y confirmación.

T10 conecta el llenado con `CaptureSessionRepository`: al analizar, copia cada foto seleccionada a `CartrackImages/CaptureSessions/<session-id>/<photo-id>.jpg` en almacenamiento local protegido, registra solo ruta relativa/hash/dimensiones/tamaño en SwiftData, conserva la imagen original para el OCR principal y usa T08 para medir calidad. Repetir con el mismo contenido deduplica por hash dentro de la sesión; una foto distinta queda disponible para el reemplazo selectivo de T12. Las lecturas del OCR existente se convierten a candidatos canónicos T09; galones, precio, total, odómetro y trip de confianza suficiente precargan el borrador. El indicador analógico queda sin valor automático. Se guarda evidencia OCR local por campo, nunca píxeles en la base. Al reanalizar una sesión se verifican ruta y SHA-256 antes de leer sus fotos. Cámara y `PhotosPicker` usan permisos del sistema al elegir evidencia; la política completa de permisos y recordatorios queda para T20. El reconocimiento principal mantiene resolución completa hasta confirmar. T14 reemplaza entonces la copia temporal mediante la optimización posterior descrita abajo.

T11 comparte la persistencia/verificación de fotos y evidencias OCR de T10 con el registro de uso, pero acepta únicamente odómetro y nivel de combustible. Crea una sesión `.snapshot`, reanaliza tras relanzar desde JPEG locales verificados, deduplica la misma selección y preserva el borrador `review`. Odómetro y trip digital se convierten de millas a kilómetros canónicos; trip es opcional. El nivel analógico sigue sin precarga automática cuando no alcanza confianza suficiente, y ningún campo financiero entra al snapshot. El formulario nuevo usa este workflow para fotos de cámara/`PhotosPicker` y entrada manual; la edición existente conserva su camino v1. El guardado de evento todavía usaba la ruta v1 al cerrar T11; T12 unifica la confirmación de nuevas capturas, conflictos, repetición selectiva y reanudación visible. T14 gestionará originales/optimización local.

T12 completa la revisión local: cada candidato visible indica campo, banda, fuente y lectura; media pide revisión, baja/crítica ofrece repetir solamente la foto de origen o corregir manualmente. El nivel analógico no confiable exige confirmación visual explícita. Los campos corregidos se marcan en el borrador y no son sobrescritos por un nuevo OCR; los demás sí se actualizan al reemplazar su foto. Los cambios manuales se guardan con debounce y al salir del formulario; la pantalla Capturar lista sesiones recuperables y las reabre desde las fotos locales, sin necesitar la biblioteca original. Confirmar una captura nueva usa un contexto SwiftData sin autosave: crea evento, índice de imágenes, metadatos, vincula fotos/evidencias OCR, anota correcciones y cambia la sesión a `confirmed` en un único `save()`. Un fallo revierte la base y elimina copias de imágenes recién preparadas; una segunda confirmación de la misma sesión se rechaza. T13 añade los invariantes de negocio antes de todo guardado; T14 realiza la limpieza/optimización local posterior sin perder evidencia.

## Salida

```swift
CaptureAnalysisResult(
  sessionID: UUID,
  draft: CaptureDraft,
  fields: [FieldResult],
  imageIssues: [ImageIssue],
  blockingIssues: [ValidationIssue],
  algorithmVersion: String
)
```

`FieldResult` contiene campo, candidatos, candidato seleccionado opcional, confianza, unidad, fuente y códigos de validación.

## Estados

```text
draft → analyzing → review → confirmed
                 ↘ failedRecoverable → analyzing
                 ↘ failedTerminal
draft/analyzing/review/failedRecoverable/failedTerminal → discarded
```

Solo `review` puede confirmar. `confirmed` es inmutable como sesión; editar el evento crea una nueva revisión auditada.
La sesión y su borrador son locales; cada escritura verifica la revisión esperada. Al relanzar, `analyzing` se convierte en `failedRecoverable`, preservando el borrador para reintento. Una sesión corrupta se reporta por ID sin impedir la recuperación de otras. Descartar elimina el contenido del borrador y su evidencia OCR no confirmada; T14 gestionará los archivos de fotos locales. La vinculación transaccional del evento confirmado se implementa en T12.

## Reglas de selección

- Alta: puede seleccionarse automáticamente.
- Media: puede seleccionarse, pero se resalta.
- Baja: ningún candidato se selecciona automáticamente.
- Crítica: bloquea confirmación hasta resolver.

El puntaje numérico y la banda se versionan. Cambiar umbrales exige pruebas de regresión. La validación cruzada T09 usa tolerancia de acuerdo de ±1.61 km en odómetro, ±0.32 km en trip, ±0.25 secciones de tanque y ±0.01 en campos financieros. La ecuación `galones × precio ≈ total` tolera Q0.05; si discrepa, bloquea los tres campos. Si existe odómetro del último llenado, el trip se contrasta con esa distancia con tolerancia máxima entre 2 km y 3%. Estas reglas son de confianza OCR: T13 validará de nuevo los invariantes antes de guardar.

## Errores

| Código | Recuperación |
|---|---|
| `image.tooBlurred` | repetir esa imagen |
| `image.overexposed` | repetir o aceptar si campos pasan |
| `image.underexposed` | repetir con más luz o corregir manualmente |
| `image.orientationCorrected` | continuar con imagen normalizada |
| `image.lowResolution` | repetir si los campos no son legibles |
| `image.possibleGlare` | revisar reflejo y repetir esa imagen si afecta lectura |
| `image.possibleCrop` | revisar bordes de factura y repetir si falta información |
| `image.wrongKind` | reclasificar/reemplazar |
| `ocr.noText` | repetir o entrada manual |
| `field.conflict` | elegir candidato/corregir |
| `field.outOfRange` | corregir; no guardar |
| `storage.insufficientSpace` | liberar espacio; conservar borrador |
| `session.corruptDraft` | aislar borrador y exportar diagnóstico |

## Tolerancias iniciales de fixture

- Odómetro digital: ±1 mi o equivalente.
- Trip digital: ±0.2 mi o equivalente.
- Moneda/volumen/precio: tolerancia declarada por escenario; por defecto ±0.01 en la unidad impresa.
- Nivel analógico: no se afirma automáticamente sin confianza calibrada; recuperación manual es salida válida documentada.

## Optimización posterior

Después de confirmar, el proceso local reintentable hace lo siguiente por cada evidencia:

1. genera bajo un nombre UUID nuevo un JPEG protegido, con calidad fija 72%, lado máximo inicial de 2000 px y reducción adicional de dimensiones si necesita respetar 450 KB;
2. vuelve a leer los bytes, verifica hash SHA-256, decodificación, dimensiones y que no se haya introducido un problema nuevo de resolución, desenfoque o exposición;
3. en un solo `save()` cambia `LocalPhotoAsset` y, para la foto seleccionada, el índice `ImageAsset` al archivo verificado;
4. sólo después de ese `save()` elimina los originales o reemplazos que ya no tengan referencias.

Si falla escritura, decodificación, validación o guardado de SwiftData, se borran los archivos nuevos de staging y se preservan tanto las rutas como los bytes originales. Los borradores descartados sin evento eliminan su evidencia local después de borrar sus filas. Al iniciar la app se reintentan las sesiones confirmadas pendientes; un barrido elimina únicamente JPEGs huérfanos, con más de una hora, dentro del árbol propio de evidencia.

El presupuesto deliberado es un máximo de 450 KB por foto optimizada. Con cinco capturas por semana y dos fotos retenidas por captura son `450,000 × 10 × 52 = 234 MB/año` (decimal), por debajo del máximo local de 250 MB/año. La base sólo conserva los metadatos, hash y rutas; no sube ni duplica píxeles.
