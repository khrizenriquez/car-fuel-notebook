# Reportes y Exportacion - Diseno

## Resumen
Este bloque extiende Cartrack con una pantalla dedicada de reportes y con exportacion local `PDF` y `CSV`, alineada con la especificacion funcional del BMW Z4. El objetivo es cubrir la brecha principal restante del producto sin romper los flujos ya estabilizados de captura, OCR, correccion manual, persistencia local y pruebas con evidencia real.

La implementacion debe preservar dos reglas del producto:
- los calculos definitivos solo salen de tanques cerrados;
- las fotos reales locales ignoradas por git se mantienen como fixtures de prueba privados y no se borran ni se reemplazan.

## Objetivos
- Agregar una pantalla `Reportes` separada del dashboard.
- Mostrar reportes `Semanales` y `Mensuales` filtrables por vehiculo.
- Cubrir las metricas faltantes de la especificacion con separacion clara entre `real` y `estimado`.
- Permitir exportar el reporte visible a `CSV` y `PDF` sin depender de red.
- Mantener pruebas automatizadas locales, incluyendo el uso de las fotos reales privadas actuales.

## No Objetivos
- OCR manual con recorte interactivo.
- Alertas inteligentes de reserva o consumo anormal.
- Exportacion a nube, email automatico o sincronizacion.
- Importacion historica de reportes externos.

## Alcance Funcional

### Nueva Pantalla de Reportes
Se agregara una nueva pantalla `ReportsView` dentro del shell principal de tabs. Esta pantalla tendra:
- selector de vista: `Semanal` o `Mensual`;
- filtro por vehiculo reutilizando `VehicleFilterPicker`;
- seccion de resumen visible;
- seccion de comparativos por tanque cuando aplique;
- acciones `Exportar CSV` y `Exportar PDF`.

La pantalla no debe recalcular logica compleja dentro de SwiftUI. Solo consume modelos de reporte ya preparados en `CartrackCore`.

### Reporte Semanal
Cada semana reportada debe incluir, cuando exista evidencia suficiente:
- kilometros recorridos;
- millas recorridas;
- galones consumidos estimados o reales segun disponibilidad;
- costo estimado o real segun disponibilidad;
- km/gal promedio;
- dias de uso;
- promedio diario de kilometros;
- indicacion visible cuando una semana se base en consumo estimado en lugar de tanque cerrado.

Reglas:
- si existe tanque cerrado en esa semana, usar sus datos reales para distancia, galones y costo;
- si solo existe tanque activo o snapshots, calcular valores estimados desde la referencia del vehiculo o el promedio historico reciente;
- los datos estimados deben etiquetarse como `Estimado`.

### Reporte Mensual
Cada mes reportado debe incluir:
- total de llenados;
- total pagado;
- kilometros recorridos;
- consumo promedio;
- costo por km;
- autonomia promedio por tanque cerrado;
- mejor tanque;
- peor tanque;
- comparacion basica entre `pagado` y `consumido estimado`.

Reglas:
- `total pagado` sale de compras del mes;
- `km recorridos` se apoya en ciclos cerrados, ajustes manuales y progreso del tanque activo cuando aplique;
- `mejor` y `peor` tanque solo usan tanques cerrados;
- `autonomia promedio` usa tanques cerrados y datos de vehiculo, nunca snapshots ruidosos como verdad final.

### Comparativo por Tanque
Cuando existan tanques cerrados suficientes para el vehiculo filtrado, la vista de reportes debe mostrar:
- fecha de inicio;
- fecha de cierre;
- odometro inicio y fin;
- km;
- galones;
- total;
- km/gal;
- costo/km;
- etiqueta de mejor o peor rendimiento cuando corresponda.

## Arquitectura Tecnica

### Core
`CartrackCore/Sources/CartrackCore/AnalyticsEngine.swift` se ampliara con modelos y funciones nuevas, manteniendo la logica actual separada de la UI.

Nuevos modelos propuestos:
- `DetailedWeeklyReport`
- `DetailedMonthlyReport`
- `TankComparisonReport`
- `ReportValueOrigin` con opciones como `real` y `estimated`

Capacidades nuevas del core:
- resumen semanal detallado por vehiculo;
- resumen mensual detallado por vehiculo;
- comparativos de tanques cerrados;
- conversion dual km/millas para presentacion;
- serializacion a filas `CSV` a partir de los modelos de reporte.

### App
Se agregaran nuevas piezas en la app:
- `Cartrack/Features/Reports/ReportsView.swift`
- vistas de apoyo para tarjetas o tablas de reportes;
- un servicio local de exportacion, por ejemplo:
  - `ReportExportService`
  - `CSVReportRenderer`
  - `PDFReportRenderer`

La generacion `PDF` debe usar APIs locales de Apple, por ejemplo `ImageRenderer` o `UIGraphicsPDFRenderer`, evitando dependencias de red.

### Navegacion
La app agregara un tab `Reportes`. No se debe recargar el dashboard con responsabilidades nuevas de exportacion pesada.

## Reglas de Datos y Calculo

### Semanas
- la semana se agrupa por `startOfWeek`;
- `dias de uso` se calcula por dias calendario distintos con al menos un fill o snapshot del vehiculo;
- `promedio diario` = distancia semanal / dias de uso;
- cuando no haya galones reales cerrados, `galones consumidos` = distancia / referencia km por galon;
- la referencia sale del promedio reciente de ciclos cerrados o, en su defecto, de `vehicle.fuelEconomyReferenceKilometersPerGallon`.

### Meses
- se respetan los modos ya existentes de asignacion mensual si aplican a la vista mensual;
- `autonomia promedio` se calcula desde tanques cerrados y capacidad/configuracion del vehiculo;
- `mejor tanque` = mayor `kmPerGallon`;
- `peor tanque` = menor `kmPerGallon`;
- si no hay tanques cerrados suficientes, `mejor`, `peor` y `autonomia promedio` muestran `N/A`.

### Origen de Valores
Toda metrica sensible debe exponer su origen:
- `real`: basada en tanque cerrado;
- `estimated`: basada en tanque activo, snapshots o referencia historica.

La UI y las exportaciones deben reflejar ese origen.

## Exportacion

### CSV
La exportacion `CSV` debe:
- generarse localmente;
- incluir encabezados estables;
- cubrir la vista activa (`Semanal` o `Mensual`);
- incluir columna de origen `real/estimated` donde aplique;
- guardarse temporalmente para compartir/exportar desde iOS.

### PDF
La exportacion `PDF` debe:
- generarse localmente;
- reflejar el filtro y vista activos;
- incluir encabezado con vehiculo, fecha de generacion y tipo de reporte;
- resumir metricas principales y, cuando aplique, la tabla de tanques comparativos;
- poder abrirse o compartirse sin salir de la app.

## Manejo de Errores
- Si no hay datos suficientes, la pantalla debe mostrar estado vacio claro, no valores inventados.
- Si falla la generacion de archivo, se muestra alerta y no se pierde ningun dato local.
- Si una metrica no puede calcularse con confianza, debe mostrarse `N/A` o `Estimado no disponible`.

## Pruebas

### Pruebas Core
Agregar cobertura para:
- resumen semanal detallado;
- resumen mensual detallado;
- dias de uso;
- promedio diario;
- autonomia promedio;
- mejor y peor tanque;
- separacion entre valores reales y estimados;
- filas `CSV` generadas desde reportes.

### Pruebas de App / Integracion
Agregar cobertura para:
- generacion local de archivos `CSV` y `PDF`;
- existencia del archivo exportado;
- contenido basico esperado de exportacion;
- preservacion de reportes por vehiculo.

### Pruebas UI
Agregar smoke coverage para:
- abrir tab `Reportes`;
- cambiar entre `Semanal` y `Mensual`;
- filtrar por vehiculo;
- disparar exportacion `CSV` y `PDF` en simulador sin fallo.

### Fotos Reales Privadas
Las fotos privadas actuales en:
- `Invoices/Examples/IMG_4802.jpeg`
- `Odometer/Examples/IMG_4998.jpeg`
- `FuelLevel/Examples/IMG_4999.jpeg`

se conservan como fixtures locales privados. No deben borrarse ni moverse fuera de esas carpetas ignoradas por git. Seguiran formando parte de las pruebas locales OCR actuales mientras se agregan futuras fotos reales.

## Orden de Implementacion
1. Extender `AnalyticsEngine` con reportes detallados y comparativos.
2. Agregar pruebas core para esas metricas.
3. Crear `ReportsView` y conectarla al filtro por vehiculo.
4. Agregar exportacion `CSV`.
5. Agregar exportacion `PDF`.
6. Agregar pruebas de integracion y UI.
7. Revalidar con `./Scripts/verify_local.sh`.

## Riesgos y Mitigaciones
- Riesgo: mezclar gasto pagado con consumo real y confundir al usuario.
  Mitigacion: marcar cada metrica con origen `real` o `estimated`.
- Riesgo: reportes pesados en SwiftUI.
  Mitigacion: mover calculo al core y dejar la vista como presentacion.
- Riesgo: exportes rotos en simulador o sin permisos.
  Mitigacion: cubrir flujo local con pruebas de integracion y smoke tests.
- Riesgo: romper las pruebas OCR privadas actuales.
  Mitigacion: no tocar las carpetas ignoradas de ejemplos privados y mantenerlas como parte de la verificacion local.
