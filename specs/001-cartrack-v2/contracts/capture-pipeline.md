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

T10 conecta el llenado con `CaptureSessionRepository`: al analizar, copia cada foto seleccionada a `CartrackImages/CaptureSessions/<session-id>/<photo-id>.jpg` en almacenamiento local protegido, registra solo ruta relativa/hash/dimensiones/tamaño en SwiftData, conserva la imagen original para el OCR principal y usa T08 para medir calidad. Repetir con el mismo contenido deduplica por hash dentro de la sesión; una foto distinta queda disponible para el reemplazo selectivo de T12. Las lecturas del OCR existente se convierten a candidatos canónicos T09; galones, precio, total, odómetro y trip de confianza suficiente precargan el borrador. El indicador analógico queda sin valor automático. Se guarda evidencia OCR local por campo, nunca píxeles en la base. Al reanalizar una sesión se verifican ruta y SHA-256 antes de leer sus fotos. Cámara y `PhotosPicker` usan permisos del sistema al elegir evidencia; la política completa de permisos y recordatorios queda para T20. El reconocimiento principal mantiene resolución completa: una variante reducida a 2200 px degradó la lectura de una factura real en el gate privado. La confirmación transaccional y la reanudación visible en UI corresponden a T12; la optimización/limpieza final de originales locales corresponde a T14.

T11 comparte la persistencia/verificación de fotos y evidencias OCR de T10 con el registro de uso, pero acepta únicamente odómetro y nivel de combustible. Crea una sesión `.snapshot`, reanaliza tras relanzar desde JPEG locales verificados, deduplica la misma selección y preserva el borrador `review`. Odómetro y trip digital se convierten de millas a kilómetros canónicos; trip es opcional. El nivel analógico sigue sin precarga automática cuando no alcanza confianza suficiente, y ningún campo financiero entra al snapshot. El formulario nuevo usa este workflow para fotos de cámara/`PhotosPicker` y entrada manual; la edición existente conserva su camino v1 hasta T12. El guardado de evento aún usa la ruta v1 y no confirma la sesión de manera transaccional: T12 unificará confirmación, conflictos, repetición selectiva y reanudación visible. T14 gestionará originales/optimización local.

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

Después de confirmar:

1. generar archivo temporal JPEG máximo 2000 px, 70–75%;
2. decodificarlo y comprobar dimensiones/hash;
3. comprobar que el recorte necesario continúa legible cuando aplique;
4. mover atómicamente a almacenamiento protegido;
5. actualizar `LocalPhotoAsset`;
6. eliminar el original temporal.

Ante cualquier fallo, el original permanece y el evento no pierde su evidencia.
