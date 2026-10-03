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
```

Solo `review` puede confirmar. `confirmed` es inmutable como sesión; editar el evento crea una nueva revisión auditada.

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
