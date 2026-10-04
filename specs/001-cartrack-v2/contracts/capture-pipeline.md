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

T08 implementa la preparación local previa a OCR: normaliza orientación, muestrea una imagen de 96 px para métricas de nitidez/exposición/color/borde, clasifica de forma conservadora con el tipo declarado como pista y genera variantes temporales de máximo 2200 px (`normalized`, `highContrast`, `monochrome`, `redDisplay` para tablero). La salida son objetos `CGImage` en memoria, sin rutas ni escritura a disco. El tablero no se divide automáticamente en odómetro frente a nivel de tanque si falta una pista confiable; se devuelve `other`. T10 conectará esta preparación al flujo de captura y T09 añadirá confianza por campo, por lo que sus umbrales iniciales no equivalen a confirmación automática.

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

El puntaje numérico y la banda se versionan. Cambiar umbrales exige pruebas de regresión.

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
