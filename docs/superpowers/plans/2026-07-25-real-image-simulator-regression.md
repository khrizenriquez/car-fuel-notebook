# Plan de implementacion: regresion con imagenes reales en simulador

Especificacion aprobada:
`docs/superpowers/specs/2026-07-25-real-image-simulator-regression-design.md`

## Reglas de ejecucion

- Preservar todos los cambios existentes del worktree que no pertenezcan a este plan.
- No reescribir el historial de Git.
- No borrar fotografias locales; una migracion de privacidad usa `git rm --cached` o cambios equivalentes que conservan los archivos fisicos.
- Empezar cada cambio de comportamiento con una prueba que falle por la razon esperada.
- Ejecutar pruebas focalizadas antes de los gates completos.
- Mantener el combustible analogico como confirmacion manual segun ADR-003.
- No aceptar tablas de resultados de produccion asociadas a hashes exactos de fixtures.

## Fase 1: arquitectura y fuente de verdad

### Tarea 1. Crear ADR-007

Archivos:

- Agregar `docs/adr/ADR-007-real-image-regression-and-private-fixtures.md`.
- Actualizar `Scripts/preflight_publish.sh` para exigir ADR-007.

Contenido:

- matriz hibrida de parser, Vision y UI;
- fixtures reales privados y fixtures sanitizados versionados;
- tolerancias `±1 mi` y `±0.2 mi`;
- combustible analogico `MANUAL_REQUIRED`;
- prohibicion de respuestas de produccion por firma exacta;
- simulador dedicado `Cartrack Private Fixtures`;
- gates publico y privado.

Verificacion:

```bash
Scripts/preflight_publish.sh
```

### Tarea 2. Definir el esquema de escenarios

Archivos:

- Agregar `CartrackTests/Fixtures/PrivateImageScenario.swift`.
- Agregar `CartrackTests/Fixtures/private-image-scenarios.example.json`.
- Crear localmente `CartrackTests/Fixtures/private-image-scenarios.json`.

Campos minimos:

- `id`, `kind`;
- rutas de factura, odometro y combustible;
- valores esperados opcionales;
- tolerancias;
- `manualFuelSpaces`;
- `runInSimulator`;
- notas de exclusion cuando una imagen no participa.

Pruebas:

- decodifica snapshot, fill-up y escenario excluido;
- rechaza IDs duplicados;
- rechaza escenarios sin imagenes;
- rechaza tolerancias negativas;
- exige una razon para exclusiones.

Comando:

```bash
destination="$(Scripts/select_ios_simulator.sh)"
xcodebuild -project Cartrack.xcodeproj -scheme Cartrack \
  -destination "$destination" \
  -only-testing:CartrackTests/PrivateImageScenarioManifestTests test
```

## Fase 2: regresion Vision general

### Tarea 3. Migrar `LocalExampleImageOCRTests`

Archivos:

- Modificar `CartrackTests/LocalExampleImageOCRTests.swift`.
- Consumir el manifiesto privado mediante un unico cargador.
- Eliminar arreglos duplicados y casos individuales redundantes.

Comportamiento:

- modo normal: `XCTSkip` explicito cuando falta el paquete privado;
- modo estricto: fallo si falta manifiesto o imagen;
- diagnostico incluye escenario, campo, esperado, observado y texto OCR;
- todos los campos declarados se validan.

Datos obligatorios:

- `108728 / 566.6`;
- `108749 / 587.3`;
- `108768 / 606.5`;
- todas las fotos historicas existentes;
- factura Texaco.

Comando:

```bash
CARTRACK_REQUIRE_PRIVATE_FIXTURES=1 \
xcodebuild -project Cartrack.xcodeproj -scheme Cartrack \
  -destination "$(Scripts/select_ios_simulator.sh)" \
  -only-testing:CartrackTests/LocalExampleImageOCRTests test
```

### Tarea 4. Quitar respuestas memorizadas de produccion

Archivos:

- Modificar `Cartrack/Services/OCRService.swift`.
- Modificar `CartrackTests/OCRServiceTests.swift`.
- Agregar casos algoritmicos a `CartrackCore/Tests/CartrackCoreTests/OCRTextParserCoreTests.swift` cuando correspondan.

Secuencia:

1. Agregar variantes de recompresion, reduccion y orientacion para demostrar que las firmas exactas no generalizan.
2. Ejecutar la matriz y registrar fallos reales.
3. Mejorar deteccion de display, segmentacion o reconciliacion de candidatos con reglas generales.
4. Eliminar `knownFixtureReading`, `fixtureSignature` y tablas equivalentes del lector de cluster.
5. Verificar que una discrepancia no confiable retorna correccion manual, no un numero inventado.

Pruebas focalizadas:

```bash
swift test --package-path CartrackCore
destination="$(Scripts/select_ios_simulator.sh)"
xcodebuild -project Cartrack.xcodeproj -scheme Cartrack \
  -destination "$destination" \
  -only-testing:CartrackTests/OCRServiceTests \
  -only-testing:CartrackTests/LocalExampleImageOCRTests test
```

## Fase 3: privacidad y reproducibilidad

### Tarea 5. Separar fixtures privados y sanitizados

Archivos:

- Modificar `.gitignore`.
- Modificar `docs/testing/ocr-fixtures.md`.
- Modificar `SECURITY.md`.
- Modificar `Scripts/preflight_publish.sh`.
- Agregar `Scripts/check_private_fixture_pack.sh`.

Comportamiento:

- fotografias y manifiesto real ignorados por git;
- esquema y plantilla sanitizada versionados;
- preflight falla si una evidencia privada nueva esta rastreada;
- la comprobacion privada informa con precision archivos faltantes;
- los archivos locales se conservan aunque dejen de estar rastreados.

Verificacion:

```bash
Scripts/check_private_fixture_pack.sh
Scripts/preflight_publish.sh
git ls-files Invoices Odometer FuelLevel
```

## Fase 4: flujo real en simulador

### Tarea 6. Preparar un simulador dedicado

Archivos:

- Agregar `Scripts/select_private_fixture_simulator.sh`.
- Agregar `Scripts/prepare_private_fixture_photos.sh`.

Reglas:

- nombre exacto `Cartrack Private Fixtures`;
- resolver un unico UDID;
- validar nombre y UDID antes de `simctl erase`;
- no usar globs, variables vacias ni el simulador por defecto como destino destructivo;
- importar medios en orden determinista con `simctl addmedia`;
- producir un inventario de escenario y orden de importacion.

Pruebas del script:

- modo `--dry-run`;
- rechazo de cero o multiples coincidencias;
- rechazo de manifiesto incompleto;
- validacion del runtime y device type.

### Tarea 7. Agregar E2E privados mediante Fotos

Archivos:

- Agregar `CartrackUITests/PrivateImageScenarioUITests.swift`.
- Modificar helpers compartidos en `CartrackUITests/CartrackSmokeUITests.swift` solo si se pueden extraer sin cambiar sus contratos.

Escenarios:

1. Crear BMW Z4 en simulador limpio.
2. Para cada snapshot nuevo:
   - elegir odometro desde Fotos;
   - elegir combustible desde Fotos;
   - validar prefill;
   - establecer combustible manual;
   - guardar;
   - validar historial.
3. Validar dashboard despues de los tres snapshots.
4. Ejecutar un llenado con factura, odometro y combustible.
5. Validar valores persistidos y metricas visibles.

Reglas:

- seleccionar fotos mediante la UI visible;
- no sustituir imagenes por strings inyectados;
- usar identificadores de accesibilidad estables;
- adjuntar screenshot y jerarquia accesible ante fallo.

Comando:

```bash
Scripts/verify_private_image_scenarios.sh
```

### Tarea 8. Crear el gate privado

Archivos:

- Agregar `Scripts/verify_private_image_scenarios.sh`.
- Modificar `Scripts/verify_local.sh` para respetar `CARTRACK_REQUIRE_PRIVATE_FIXTURES=1`.

Orden:

1. validar paquete;
2. ejecutar regresion Vision;
3. preparar simulador;
4. ejecutar E2E privados;
5. conservar rutas de `.xcresult`;
6. resumir escenarios aprobados, manuales y fallidos.

## Fase 5: documentacion y verificacion final

### Tarea 9. Actualizar evidencia documental

Archivos:

- Modificar `README.md`.
- Modificar `docs/testing/ocr-fixtures.md`.
- Modificar `docs/release/v1-readiness-audit.md`.

Contenido:

- comandos publicos y privados;
- fecha real del ultimo gate;
- cantidad de escenarios;
- salida esperada de las tres capturas nuevas;
- limitacion manual del combustible;
- instrucciones para replicar con el paquete privado.

### Tarea 10. Ejecutar el audit de finalizacion

Comandos:

```bash
Scripts/check_core_coverage.sh 90
Scripts/verify_local.sh
Scripts/verify_private_image_scenarios.sh
Scripts/preflight_publish.sh
git diff --check
```

Evidencia requerida:

- cobertura `CartrackCore >= 90%`;
- suite publica completa sin fallos;
- matriz privada completa sin fallos;
- E2E privado carga las imagenes desde Fotos;
- no quedan respuestas de produccion por firma exacta;
- ninguna evidencia privada nueva esta rastreada;
- ADR-007 y readiness coinciden con el comportamiento observado.

## Condicion de cierre

El objetivo no se marca completo por tener tests unitarios verdes. Se cierra solo cuando los cinco comandos finales terminan correctamente y la evidencia demuestra que las imagenes reales recorren OCR, revision, persistencia, historial y dashboard en el simulador dedicado.
