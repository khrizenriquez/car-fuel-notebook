# Plan técnico — Cartrack v2

**Estado:** Diseño aprobado; fase 0 y T05–T12 implementadas
**Rama única:** `codex/cartrack-v2`

## 1. Línea base

La línea base contiene SwiftUI, SwiftData, Vision, CoreLocation, UserNotifications, almacenamiento local de imágenes, respaldo, reportes y analítica. El gate T04 quedó verificado con:

- CartrackCore: 87/87, cobertura 93.75%.
- Suite pública iOS de integración: 42 ejecutadas, 0 fallidas; 3 privadas omitidas sin fixture.
- Suite pública UI: 14 ejecutadas, 0 fallidas; 1 privada omitida sin fixture.
- Gate privado OCR: 8/8 aprobadas, incluido `z4-2026-07-26-1305`.
- Gate privado Photos E2E: 1/1 aprobado.

T05 agregó la migración v1→v2 con respaldo validado y activación atómica: 5 pruebas de migración, 92/92 del core y 7/7 de persistencia iOS. T06 separó DTO de dominio y repositorios SwiftData, agregó metadatos/fotos/evidencia OCR locales y verificó 99/99 core, cobertura real de fuentes 90.20%, gate público y gate privado OCR/Photos. T07 añadió sesiones locales recuperables y pasó 108/108 core con 90.34% de cobertura, integración iOS 43 pruebas sin fallos y UI 14 sin fallos; 3 y 1 casos privados, respectivamente, se omiten en ese gate público. Estos números son evidencia de esos commits, no verificación del futuro commit candidato.

T08 incorporó preparación de imágenes totalmente local, con seis pruebas sintéticas por problema y una prueba privada sobre 15 escenarios/30 imágenes; la integración pública iOS pasó 46 pruebas con cuatro privadas omitidas. T09 añadió candidatos auditables y confianza versionada por campo, con 10 pruebas nuevas; el core pasó 118/118 con 90.79% de cobertura y la app compiló. La orquestación con Vision y la UI queda para T10–T12.

T10 incorporó almacenamiento protegido por sesión y el flujo de llenado con análisis de factura/tablero/combustible. Se verificó con seis pruebas de integración, un llenado real privado original y reanalizado desde archivos locales, una prueba UI de guardado y 52 pruebas públicas iOS aprobadas (5 privadas omitidas). La confirmación transaccional y la reanudación visible quedan para T12.

T11 añadió el flujo de registro de uso con sesión recuperable, odómetro/trip y combustible conservador. Pasó cinco pruebas nuevas, seis de regresión de llenado, lectura real privada con reanálisis local, UI happy path y UI privada con foto en `PhotosPicker`. La integración pública iOS pasó 57 pruebas (6 privadas omitidas), el core 118/118 y cobertura 90.77%. La confirmación transaccional y la reanudación visible quedan para T12.

T12 añadió bandas y explicación por campo/foto, repetición selectiva, borradores manuales recuperables en Capturar, y confirmación transaccional única de capturas nuevas con vínculos locales y auditoría OCR. Verificó rollback, segundo guardado rechazado y reemplazo de factura/odómetro sin perder una corrección manual. Pasó 120/120 core con cobertura 90.75%, integración iOS pública 62 aprobadas (6 privadas omitidas), UI pública 14 aprobadas (1 privada omitida) y Photos privado 1/1. Las reglas de integridad definitivas para nuevos registros y ediciones quedan para T13; T14 resolverá optimización/limpieza de imágenes.

T13 conecta una política de integridad de dominio a capturas nuevas y ediciones antes de mutar datos: odómetro por vehículo/fecha con override auditado, reinicio de trip, nivel/paso y ecuación financiera. Una carga parcial queda pendiente hasta el próximo tanque completo, y entonces se suma al volumen/costo real del ciclo. Las pruebas de límites, rollback y UI pasaron; la prueba UI de edición ahora usa un total coherente con sus galones y precio. T13 se registra como un solo commit, separado de T01–T12.

T14 optimiza evidencia confirmada únicamente en el dispositivo. Cada original se conserva hasta que un JPEG protegido de calidad 72%, máximo 2000 px y máximo 450 KB se escribe, se reabre y pasa hash, dimensiones, decodificación y calidad. Las filas y referencias se intercambian en un único guardado, y los archivos antiguos se retiran sólo después; un fallo conserva los originales. También limpia capturas descartadas y huérfanos con antigüedad. Cinco capturas semanales de dos fotos, al límite de 450 KB, proyectan 234 MB/año y cumplen el límite de 250 MB. La verificación incluye original privado OCR, fallos inyectados de staging/guardado/decodificación, core y suites iOS.

T15 endurece el cálculo de ciclos y unidades: los llenados parciales se acumulan hasta el siguiente lleno del mismo vehículo, y una consulta global agrupa primero por vehículo para que líneas de tiempo intercaladas nunca generen ciclos cruzados. Los ciclos y resúmenes exponen MPG, km/gal, km/L, L/100 km y costo por distancia a partir de los mismos datos canónicos. Los límites mensual final/prorrateado, edición y eliminación continúan cubiertos; core 125/125 y la integración iOS pública 76/76 pasaron.

T16 incorpora calibración local del medidor no lineal. Cada punto combina proporción de combustible consumido y distancia normalizada dentro de un ciclo confirmado del mismo vehículo; la curva usa mediana por banda y sólo declara suficiencia tras historia real. La autonomía existente conserva su intervalo de ciclos y ahora cuenta con una curva explícita disponible para T17. La detección de anomalías no borra datos: señala eficiencia alta/baja sólo con cuatro o más ciclos y umbral robusto mediana/MAD. Los conjuntos insuficiente, suficiente, no lineal y outlier están cubiertos; core 129/129 e iOS público 76/76 verdes.

T17 lleva esos datos al dashboard: primero el estado del tanque y su explicación, luego una tendencia de rendimiento por ciclo y la curva observada de combustible contra odómetro. Si no hay ciclos se explica el siguiente dato requerido; la calibración declara explícitamente si es preliminar o suficiente. Una prueba UI con historial completo confirma ambas gráficas y las pruebas existentes cubren los estados sin vehículo y de actividad parcial.

## 2. Arquitectura objetivo

```text
SwiftUI Features
    ↓
Application Use Cases
    ↓
Domain Models + Validation + Analytics
    ↓
Repository Protocols
    ↓
SwiftData / Local Files

Capture Input
    ↓
Quality → Classification → Preprocessing → OCR
    ↓
Candidates → Cross-validation → Confidence
    ↓
Draft → User Confirmation → Transactional Save
```

### Módulos y responsabilidades

- `CartrackCore`: entidades de dominio, unidades, validaciones, confianza, analítica y contratos sin UI.
- `Cartrack`: composición de aplicación, SwiftUI, Vision, SwiftData, archivos, permisos y exportación.
- `CartrackTests`: integración de OCR, persistencia, migraciones, archivos y fixtures privados.
- `CartrackUITests`: recorridos visibles públicos y privados.
- `Scripts`: gates deterministas, preparación de simulador, privacidad y publicación.

### Límites

- Las vistas no calculan reglas de tanque ni confianza.
- OCR no guarda directamente.
- SwiftData implementa repositorios; no define las reglas.
- Analítica solo consume datos canónicos confirmados.
- Supabase no aparece como dependencia compilada en v2.

## 3. Estrategia de implementación

### Fase A — Consolidar la línea base

Separar y confirmar el trabajo privado existente, hacer pasar la matriz actual y establecer un baseline reproducible. Esta fase evita construir v2 sobre pruebas rojas o cambios mezclados.

### Fase B — Dominio y migración

Introducir versionado, metadatos de sincronización, evidencia OCR por campo, borradores y repositorios. Implementar migración v1→v2 con respaldo y rollback.

### Fase C — Canalización OCR

Agregar calidad, clasificación, variantes de preprocesamiento, candidatos, validación cruzada y confianza. Corregir por algoritmo general, nunca por firma exacta de fixture.

### Fase D — Captura y confirmación

Orquestar sesiones recuperables, precarga, resolución de conflictos, repetición selectiva y optimización local posterior a la confirmación.

### Fase E — Analítica y experiencia

Calibrar medidor no lineal, rangos de autonomía, anomalías, gráficas, accesibilidad y localización.

### Fase F — Respaldo, cloud-readiness y release

Versionar respaldo, probar restauración/migración, formalizar DTO estructurado v2.1 sin red y cerrar gates en simulador/dispositivo.

## 4. Decisiones técnicas

- SwiftUI y SwiftData continúan en v2.
- Vision ejecuta OCR en el dispositivo.
- El formulario siempre requiere confirmación.
- Las fotos se procesan con calidad completa temporal; después se conserva localmente una copia optimizada verificada.
- La nube futura recibe solo datos estructurados mínimos.
- Los valores derivados se recalculan, no se sincronizan, excepto una versión de algoritmo cuando sea necesaria para reproducibilidad.
- La resolución futura de conflictos es por registro/campo con revisión y fecha; no `last-write-wins` ciego para valores financieros u odómetro.

## 5. Estrategia Git

1. Toda v2 se implementa en `codex/cartrack-v2`.
2. Cada fila ejecutable de `tasks.md` produce un commit.
3. No se usan ramas auxiliares.
4. Cada commit incluye código, pruebas y documentación de su propósito.
5. Un commit no se marca completado si su gate falla.
6. El paquete privado nunca se añade al índice.
7. Al finalizar se ejecutan los gates sobre el commit candidato, se publica la rama y se crea el PR.

## 6. Gates

### Por commit

- Pruebas unitarias focalizadas.
- Compilación del módulo afectado.
- `git diff --check`.
- Revisión de secretos/fixtures si toca archivos o configuración.

### Por fase

- `Scripts/check_core_coverage.sh 90`.
- Tests de integración afectados.
- Tests UI del recorrido modificado.

### Candidato final

- `Scripts/verify_local.sh`.
- `Scripts/verify_private_image_scenarios.sh`.
- `Scripts/preflight_publish.sh --require-remote` sin excepciones de suciedad.
- Migración/restauración con copia representativa.
- E2E en simulador limpio.
- Smoke en iPhone físico.
- Build Release/Archive.

## 7. Riesgos

| Riesgo | Impacto | Mitigación |
|---|---|---|
| OCR sobreajustado al BMW/fotos actuales | Alto | Variantes, fixtures diversos y prohibición de hashes |
| Migración SwiftData no reversible | Alto | Respaldo validado, migración por etapas y prueba de rollback |
| Pérdida de original durante optimización | Alto | Escritura temporal, verificación, reemplazo atómico |
| Confianza mal calibrada | Alto | Métricas por campo y corpus etiquetado |
| Trabajo previo mezclado | Medio | Primeros commits de consolidación con pathspecs y gates |
| Crecimiento local | Medio | 2000 px, JPEG 70–75%, presupuesto y diagnóstico |
| Expectativa de restaurar fotos desde nube | Medio | UX y documentación explícitas |
| Supabase accidentalmente conectado a la BD existente | Crítico | ID de proyecto separado, configuración ausente en v2 y gate de secretos |
| Rama larga difícil de revisar | Medio | Commits pequeños, compilables y ordenados por tareas |

## 8. Entregables

- Código y pruebas v2.
- Migración y respaldo verificados.
- Matriz privada de OCR en verde.
- Spec Kit actualizado con evidencia real.
- Rama remota `codex/cartrack-v2`.
- Pull request o instrucciones completas para creación manual.
