# CartrackCore: cobertura de 95% y rutas no felices

## Objetivo

Elevar la cobertura de líneas de `CartrackCore` de la línea base observada de
90.69% a un mínimo estricto de 95.00%, sin excluir archivos ni cambiar la
implementación de producción únicamente para satisfacer la métrica. El umbral
se aplica exclusivamente al paquete `CartrackCore`.

La entrega debe demostrar comportamiento correcto tanto para resultados
válidos como para entradas inválidas, conflictos, límites y recuperación de
estado.

## Alcance y medición

`Scripts/check_core_coverage.sh` continuará ejecutando `swift test
--enable-code-coverage` y calculando sólo las líneas ejecutables bajo
`CartrackCore/Sources/CartrackCore/`. El valor recibido por el script cambiará
de `90` a `95`; cualquier resultado menor hará fallar el job `Core Coverage`.

La cobertura de los targets `CartrackTests` y `CartrackUITests` no se sumará a
este porcentaje. Siguen siendo obligatorios en sus jobs de CI para validar
SwiftData, flujos de usuario y accesibilidad; no deben usarse para ocultar
déficits de la lógica Core.

## Estrategia de pruebas

Las pruebas nuevas se ubicarán junto a la suite Core existente y se agruparán
por contrato observable. Cada caso debe verificar una salida, error o cambio
de estado; no se añadirán llamadas sin aserciones sólo para ejecutar líneas.

### Valores, formatos y conversiones

Cubrir todos los casos de `CaptureImageKind`, `MonthlyAllocationMode`,
`OdometerUnit`, `HistoryEventKind` e `ImageOwnerKind`; títulos, etiquetas e
identificadores deben permanecer estables. Las pruebas de formatter verificarán
las unidades de millas/kilómetros, sufijos vacíos y valores decimales. Las de
parsing incluirán vacío, separadores repetidos o mixtos, miles, decimales,
texto inválido y el comportamiento de valor por defecto para cero.

### Integridad, dominio y analítica

`EventIntegrityPolicy` recibirá casos para cada error: odómetro no válido,
trip negativo o superior al odómetro, escala de combustible inválida, paso no
alineado, valores financieros no positivos, total inconsistente y regresión
sin motivo suficiente. También verificará los dos resultados no felices que
siguen siendo aceptables: reset de trip y regresión con motivo auditado.

Las pruebas de analítica cubrirán entradas vacías, ciclos abiertos, límites de
fecha, filtros de vehículo, ajustes manuales y valores fuera de rango que
deben ignorarse o marcarse sin contaminar los totales.

### OCR y captura recuperable

La suite de OCR cubrirá datos incompletos, candidatos incompatibles, números
ambiguos, conflicto entre evidencia independiente, falta de contexto histórico
y retorno explícito a revisión manual. La captura debe conservar evidencia y
borrador cuando falle el análisis o la persistencia, no duplicar fotos al
reintentar y rechazar transiciones de estado inválidas.

### Persistencia, migración y sync local

Se probarán conflictos de `SyncMetadataMaintainer`, borrado de metadata y
extras, modelos V2 con opcionales presentes y ausentes, y errores de repositorio
sin exponer datos sensibles. Los escenarios de SwiftData comprobarán migración
sin datos, restauración de evidencia local, importación corrupta, rollback y
que los vehículos no compartan eventos, fotos ni revisiones.

## Criterios de aceptación

1. `Scripts/check_core_coverage.sh 95` termina exitosamente y comunica una
   cobertura de líneas de Core no menor a 95.00%.
2. Las pruebas Core incluyen aserciones de cada categoría de fallo descrita
   arriba y todas pasan de forma determinista.
3. Ningún archivo de producción se excluye del cálculo de cobertura y no se
   añade código muerto para elevar el porcentaje.
4. Los targets de integración y UI existentes continúan pasando.
5. El cambio de umbral se documenta en `ADR-006` o en la documentación de CI
   correspondiente, incluyendo que la cobertura es exclusiva de Core.

## Riesgos y controles

Los formatters de Foundation pueden variar por locale; los tests fijarán locale
cuando el contrato sea textual y asertarán propiedades de unidad/valor cuando
la puntuación dependa del sistema. Las pruebas de fecha usarán instantes
explícitos y calendarios conocidos. SwiftData se ejecutará con contenedores en
memoria y directorios temporales aislados para impedir que un escenario altere
otro.

No se añadirán llamadas reales a cámara, ubicación, iCloud o Supabase: esos
límites pertenecen a integración/UI y el contrato Core debe seguir siendo
repetible offline.

