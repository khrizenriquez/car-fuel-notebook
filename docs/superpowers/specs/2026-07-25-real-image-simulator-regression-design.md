# Cartrack: regresion con imagenes reales en simulador

Fecha: 2026-07-25

Estado: aprobado para planificacion

Alcance: pruebas con evidencias reales, OCR local, flujo de captura en simulador y documentacion reproducible

## 1. Contexto

Cartrack ya cuenta con pruebas unitarias del dominio, pruebas de integracion iOS, pruebas UI en simulador y un conjunto local de fotografias reales del BMW Z4. Las pruebas actuales demuestran que `OCRService` puede analizar varias imagenes reales, pero no demuestran de forma sistematica que esas mismas imagenes atraviesen el formulario de captura, la revision manual, la persistencia, el historial y el dashboard en el simulador.

La auditoria del estado actual encontro tres brechas:

1. Los valores esperados de las fotografias estan repartidos entre arreglos de pruebas, casos individuales y respuestas asociadas a firmas exactas de archivos.
2. Las pruebas UI usan datos escritos por XCTest, pero no cargan las fotografias reales mediante el flujo de seleccion de imagenes.
3. La politica de privacidad documentada indica que las fotografias privadas no deben versionarse, mientras que la configuracion y el historial actual permiten que algunas evidencias reales se incorporen al repositorio.

Este diseño agrega una matriz unica de escenarios, una capa de regresion OCR con evidencias reales y recorridos representativos mediante la fototeca del simulador. Tambien elimina la dependencia funcional de respuestas memorizadas por hash dentro del codigo de produccion.

## 2. Decisiones heredadas

El diseño conserva las decisiones aceptadas existentes:

- ADR-001: la aplicacion sigue siendo local-first y no incorpora servicios de OCR en la nube.
- ADR-003: Vision propone valores; el usuario revisa y corrige antes de guardar.
- ADR-003: el combustible analogico permanece `review-first`; si no existe una lectura confiable, el OCR debe devolver `nil` y el usuario confirma los espacios.
- ADR-005: los valores corregidos manualmente son autoritativos y recalculan los resultados.
- ADR-006: las reglas de dominio se prueban en `CartrackCore`; Vision, persistencia y UI se verifican por separado en el simulador.

La implementacion agregara ADR-007 para formalizar la regresion con imagenes reales, la politica de fixtures privados y el contrato de ejecucion en simulador.

## 3. Objetivos

1. Ejecutar una matriz extensible de fotos reales y comparar la salida observada con valores esperados explicitos.
2. Detectar regresiones de odometro, trip, factura y comportamiento manual del combustible.
3. Cargar casos representativos desde la fototeca del simulador y recorrer revision, guardado, historial y dashboard.
4. Corregir algoritmos generales cuando una imagen falla, evitando respuestas de produccion vinculadas al hash exacto de una foto.
5. Mantener las evidencias privadas fuera del control de versiones y conservar fixtures sanitizados suficientes para CI.
6. Proporcionar comandos y documentacion que permitan repetir la validacion en otra Mac con Xcode y el paquete privado de fixtures.

## 4. No objetivos

- Entrenar un modelo de vision para interpretar agujas analogicas.
- Guardar automaticamente un valor de combustible ambiguo.
- Subir fotografias, bases de datos o resultados OCR a un servicio externo.
- Ejecutar toda la matriz privada en GitHub Actions.
- Sustituir los tests unitarios del parser por pruebas UI.

## 5. Contrato funcional

### 5.1 Campos digitales

Para una foto de cluster aceptada:

- El odometro debe coincidir con el valor esperado con tolerancia de `±1 mi`.
- El trip debe coincidir con tolerancia de `±0.2 mi`.
- Una lectura especializada puede complementar Vision, pero no puede ignorar evidencia contradictoria sin marcar el resultado como pendiente de correccion.
- Si no existe una lectura suficientemente confiable, ambos campos afectados deben permanecer vacios para correccion manual; nunca se debe guardar una lectura inventada.

### 5.2 Combustible analogico

- El resultado OCR esperado de las fotos analogicas actuales es `nil`.
- La pantalla de revision debe mostrar el control manual de `0...8` espacios con pasos de `0.25`.
- El valor seleccionado manualmente se vuelve autoritativo al guardar.
- Las descripciones aproximadas como `~1/4 de tanque` se representan como entrada manual validada, no como una afirmacion automatica de Vision.

### 5.3 Facturas

Cada escenario de factura declara los campos que deben extraerse:

- galones,
- precio por galon,
- total,
- y texto minimo identificable cuando corresponda.

La ausencia de un campo no puede convertirse silenciosamente en cero.

## 6. Matriz de escenarios

La fuente de verdad sera un manifiesto decodificable, no listas duplicadas dentro de XCTest. Cada escenario contiene:

```json
{
  "id": "z4-2026-07-24-2255",
  "kind": "snapshot",
  "odometerImage": "Odometer/Examples/2026-07-24_225500_odometer.jpg",
  "fuelImage": "FuelLevel/Examples/2026-07-24_225500_fuel-level.jpg",
  "expected": {
    "odometerMiles": 108768,
    "tripMiles": 606.5,
    "fuelLevelOCR": null
  },
  "tolerance": {
    "odometerMiles": 1,
    "tripMiles": 0.2
  },
  "ui": {
    "manualFuelSpaces": 2.0,
    "runInSimulator": true
  }
}
```

El manifiesto privado usa rutas relativas a la raiz del paquete de fixtures. Un archivo plantilla sanitizado y su esquema se versionan; el manifiesto con rutas y metadatos personales permanece local.

La primera secuencia obligatoria incluye:

| Escenario | Odometro | Trip | Combustible OCR |
| --- | ---: | ---: | --- |
| `z4-2026-07-23-1941` | 108728 mi | 566.6 mi | `nil` |
| `z4-2026-07-24-1351` | 108749 mi | 587.3 mi | `nil` |
| `z4-2026-07-24-2255` | 108768 mi | 606.5 mi | `nil` |

Las fotos historicas ya disponibles y la factura Texaco tambien forman parte de la matriz OCR completa. Los tres casos anteriores son, ademas, candidatos obligatorios para el recorrido de snapshots consecutivos.

## 7. Arquitectura de pruebas

### 7.1 Pruebas de parser

`CartrackCore` conserva transcripciones OCR sanitizadas y verifica parsing determinista sin Vision. Estas pruebas cubren separadores, caracteres confundibles, decimales omitidos y etiquetas ruidosas.

### 7.2 Regresion Vision con fotos reales

Una prueba de integracion iOS:

1. carga el manifiesto privado,
2. resuelve cada imagen,
3. ejecuta `OCRService`,
4. compara todos los campos declarados,
5. produce un diagnostico por escenario con esperado, observado y texto OCR,
6. falla si falta una imagen cuando el modo estricto esta habilitado.

La prueba no duplica casos individuales salvo que un caso represente una regresion algoritmica que merezca un nombre propio.

### 7.3 Variantes contra memorizacion

Los escenarios digitales prioritarios se verifican tambien con variantes temporales generadas durante la prueba:

- recompresion JPEG moderada,
- reduccion de resolucion conservando legibilidad,
- correccion de orientacion EXIF.

Los valores deben seguir siendo correctos o caer de forma segura a correccion manual. Esto impide que una respuesta asociada unicamente a la firma binaria del archivo se considere una solucion valida.

### 7.4 Recorrido UI en simulador

Un script dedicado prepara un simulador limpio:

1. crea o reutiliza un dispositivo dedicado llamado `Cartrack Private Fixtures`,
2. valida su nombre y UDID antes de modificar su estado,
3. borra exclusivamente ese simulador dedicado para obtener una fototeca determinista,
4. lo arranca e importa con `simctl addmedia` las imagenes marcadas con `runInSimulator`,
5. ejecuta los tests UI privados.

El script nunca borra ni modifica otro simulador por coincidencia parcial, dispositivo por defecto o variable no resuelta.

Los tests UI operan el flujo visible:

1. crear o seleccionar el BMW Z4,
2. abrir `Capturar > Snapshot`,
3. elegir odometro y combustible desde `Fotos`,
4. avanzar a revision,
5. comprobar odometro y trip,
6. confirmar manualmente los espacios de combustible,
7. guardar,
8. verificar historial,
9. verificar lectura mas reciente y metricas derivadas en dashboard.

La matriz completa permanece en integracion Vision. El E2E usa los tres snapshots consecutivos y al menos un llenado con factura porque repetir todas las fotos mediante la UI agregaria tiempo sin aumentar proporcionalmente la cobertura.

## 8. Limites de produccion y de prueba

- Los cargadores, argumentos y ayudas de fixture solo se activan con `--uitesting` y compilaciones `DEBUG`.
- La aplicacion distribuida no contiene fotografias privadas ni rutas locales del desarrollador.
- `OCRService` de produccion no devuelve valores mediante una tabla de firmas exactas de fixtures.
- Los adaptadores de prueba pueden controlar seleccion, fechas y vehiculo, pero deben atravesar el mismo formulario, validacion, persistencia y analytics usados por el usuario.
- El recorrido principal mediante `Fotos` no puede ser sustituido exclusivamente por asignacion directa de strings.

## 9. Privacidad y reproducibilidad

Se adoptan dos niveles:

### Privado local

- Fotografias reales y manifiesto real.
- Ignorados por git.
- Requeridos por el comando estricto del propietario del proyecto.
- Distribuidos, si se necesita otra Mac, como paquete privado fuera del repositorio.

### Sanitizado versionado

- Transcripciones OCR sin identificadores personales.
- Esquema y plantilla del manifiesto.
- Fixtures sinteticos o recortes anonimizados solo cuando no permiten reconstruir informacion personal.
- Pruebas unitarias y de integracion que CI puede ejecutar sin el paquete privado.

La implementacion corregira `.gitignore`, el preflight y cualquier fixture personal actualmente rastreado. La migracion no reescribira el historial de Git automaticamente; una limpieza historica requeriria una decision destructiva separada.

## 10. Manejo de errores

Cada fallo debe identificar:

- `scenarioID`,
- archivo,
- campo,
- valor esperado,
- valor observado,
- tolerancia,
- texto reconocido relevante,
- y si el lector retorno valor o solicito correccion manual.

El script distingue cuatro estados:

- `PASS`: salida dentro de tolerancia;
- `MANUAL_REQUIRED`: comportamiento esperado para evidencia ambigua;
- `SKIP_PRIVATE_FIXTURES`: paquete privado ausente en ejecucion no estricta;
- `FAIL`: imagen requerida ausente, lectura incorrecta o flujo UI incompleto.

En el entorno local del propietario, `SKIP_PRIVATE_FIXTURES` se considera fallo mediante modo estricto.

## 11. Comandos y gates

Se mantendra:

```bash
Scripts/check_core_coverage.sh 90
Scripts/verify_local.sh
```

Se agregara un comando explicito:

```bash
Scripts/verify_private_image_scenarios.sh
```

Este comando:

- exige el manifiesto y todas las imagenes privadas,
- resuelve y valida el UDID del simulador dedicado,
- ejecuta la regresion Vision completa,
- prepara la fototeca del simulador,
- ejecuta los E2E privados,
- y conserva el `.xcresult` para diagnostico.

`verify_local.sh` seguira siendo reproducible en un clon sin fotos privadas. En la Mac del propietario podra invocar el gate privado cuando `CARTRACK_REQUIRE_PRIVATE_FIXTURES=1`.

## 12. ADR-007

ADR-007 registrara:

- por que se usa una matriz hibrida,
- por que las fotos privadas no se ejecutan en CI,
- por que el combustible analogico sigue siendo manual,
- por que se prohiben respuestas de produccion basadas en firmas de fixtures,
- las tolerancias aceptadas,
- y la diferencia entre ejecucion normal y modo local estricto.

## 13. Criterios de aceptacion

La fase se considera completa solo cuando:

1. existe una unica matriz de escenarios y no hay listas esperadas duplicadas;
2. todas las imagenes disponibles estan clasificadas o documentadas como excluidas con una razon;
3. las tres capturas nuevas producen exactamente `108728/566.6`, `108749/587.3` y `108768/606.5` dentro de tolerancia;
4. las variantes de imagen no dependen de hashes exactos para aprobar;
5. las fotos analogicas actuales regresan `nil` y la UI exige confirmacion manual;
6. un E2E carga las tres parejas desde la fototeca del simulador, guarda snapshots y valida historial/dashboard;
7. un E2E de llenado carga una factura y valida los campos extraidos y persistidos;
8. `Scripts/verify_private_image_scenarios.sh` termina correctamente;
9. `Scripts/verify_local.sh` conserva cobertura de nucleo igual o superior a 90% y toda la suite publica pasa;
10. ADR-007, la guia de fixtures y la auditoria de readiness reflejan el comportamiento real;
11. el preflight impide versionar nuevas evidencias privadas;
12. la aplicacion de produccion no contiene respuestas memorizadas por firma de fixture.

## 14. Orden de implementacion

1. Crear ADR-007, esquema, plantilla y cargador del manifiesto.
2. Migrar las pruebas OCR reales a la matriz unica.
3. Introducir variantes y retirar dependencias de firmas exactas mediante mejoras generales del lector.
4. Corregir privacidad, `.gitignore`, preflight y documentacion.
5. Crear el preparador de fototeca y los recorridos UI privados.
6. Ejecutar gates privados y publicos.
7. Actualizar la auditoria de readiness con resultados y fecha reales.

Este orden mantiene diagnosticos rapidos al principio y reserva los recorridos UI mas costosos para cuando el OCR general ya sea estable.
