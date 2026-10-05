# Todo list ejecutable — Cartrack v2

## Contrato de ejecución

- Orden secuencial salvo que una tarea indique lo contrario.
- Una tarea = un commit en `codex/cartrack-v2`.
- El asunto entre comillas se usa exactamente como mensaje de commit.
- Código, pruebas y documentación de una tarea van en el mismo commit.
- No marcar `[x]` hasta que pase el gate indicado.
- El hash se obtiene del historial; el archivo no intenta autorreferenciarlo.
- No crear ramas adicionales.

## Fase 0 — Especificación y consolidación

- [x] **T00 — Formalizar Cartrack v2 en Spec Kit**
  - Commit: `Formalize Cartrack v2 specification`
  - Alcance: constitución, spec, plan, contratos, modelo, pruebas, migración, matriz, checklist y todo list.
  - Gate: enlaces internos, IDs completos, `git diff --check`.

- [x] **T01 — Aislar fixtures privados y cerrar la frontera de privacidad**
  - Commit: `Keep private vehicle evidence out of git`
  - Alcance: `.gitignore`, dejar de rastrear fotos privadas sin borrarlas localmente, ADR-007 y preflight.
  - Gate: archivos locales preservados; `git ls-files` no devuelve evidencia privada; preflight focalizado.

- [x] **T02 — Consolidar parser, OCR y pruebas existentes sin firmas de archivo**
  - Commit: `Generalize dashboard OCR for real image variants`
  - Alcance: cambios pendientes de `OCRService`, parser, orientación, variantes y tests; prohibido lookup por hash/firma.
  - Gate: parser/OCR unitario e integración focalizada, orientación, reconciliación contextual y ausencia de respuestas por firma exacta.

- [x] **T03 — Consolidar manifiesto y runner de escenarios privados**
  - Commit: `Add private image scenario regression harness`
  - Alcance: `CartrackTests/Fixtures`, plantilla sanitizada, cargador, cobertura del manifiesto y scripts de simulador.
  - Gate: tests de manifiesto, variantes prioritarias y preparación del simulador dedicado; ningún segundo simulador queda abierto.

- [x] **T04 — Cerrar el baseline público y privado de v1**
  - Commit: `Verify the Cartrack v2 migration baseline`
  - Alcance: integrar cambios pendientes de UI/analytics/formato que pertenezcan al baseline, actualizar evidencia real y corregir únicamente regresiones necesarias.
  - Gate: core ≥90%, suite pública verde, suite privada verde incluyendo `z4-2026-07-26-1305`.
  - Evidencia: 87 pruebas core y 93.75% de cobertura; suite pública y UI sin fallos; suite privada OCR 8/8 y recorrido Photos E2E 1/1, incluido `z4-2026-07-26-1305`.

## Fase 1 — Datos, migración y límites

- [x] **T05 — Introducir esquema versionado y migración v1 a v2**
  - Commit: `Add versioned v1 to v2 data migration`
  - Alcance: esquema, staging, respaldo previo, fixtures de migración y rollback.
  - Gate: migración vacía/multivehículo/con imágenes + fallos inyectados.
  - Evidencia: 5 pruebas de migración (instalación limpia, v1 vacío, multivehículo/foto, foto ausente y 3 checkpoints de fallo); 92/92 core y 7/7 pruebas iOS de persistencia. V1 y fotos permanecen locales e intactos.

- [x] **T06 — Separar dominio, repositorios y metadatos cloud-ready**
  - Commit: `Separate domain repositories from local persistence`
  - Alcance: protocolos, adaptadores SwiftData, SyncMetadata, DTO internos, `LocalPhotoAsset` y `OCRFieldEvidence`.
  - Gate: unitarias puras + integración de repositorios; app compila.
  - Evidencia: 99/99 core, cobertura de fuentes 90.20%; integración iOS sin fallos, suite pública UI de 14 pruebas (1 omitida por fixture privado), OCR privado 8/8 y Photos E2E 1/1. Migración de store T05 a esquema aditivo v2 verificada; simuladores apagados.

- [x] **T07 — Persistir sesiones de captura recuperables**
  - Commit: `Persist recoverable capture sessions`
  - Alcance: máquina de estados, borradores atómicos, reanudación y descarte explícito.
  - Gate: relanzamiento durante draft/analyzing/review.
  - Evidencia: 9 pruebas de sesión cubren relanzamiento en `draft`, `analyzing` y `review`, fallo antes del commit, corrupción aislada, descarte de borrador/evidencia OCR, revisión obsoleta y actualización de store T06→T07. Core 108/108 con cobertura 90.34%; integración iOS 43 pruebas (3 privadas omitidas), UI 14 (1 privada omitida), sin fallos. La vinculación transaccional del evento confirmado y la limpieza de fotos locales corresponden a T12 y T14.

## Fase 2 — Canalización OCR

- [x] **T08 — Agregar calidad, clasificación y preprocesamiento de imágenes**
  - Commit: `Add capture quality and image classification pipeline`
  - Alcance: blur/exposición/orientación/clase y variantes temporales.
  - Gate: fixtures por problema y cero persistencia de variantes.
  - Evidencia: 6 pruebas sintéticas cubren factura/tablero, tipo erróneo, desenfoque, sobre/subexposición, orientación, reflejo, recorte y tamaño máximo; 1 prueba privada pasó sobre 15 escenarios/30 posiciones de imagen sin falsas alertas de clase. Integración pública iOS: 46 aprobadas, 4 privadas omitidas, 0 fallidas. Las variantes son solo `CGImage` en memoria; T10 conectará el servicio al flujo de captura.

- [x] **T09 — Modelar candidatos, validación cruzada y confianza por campo**
  - Commit: `Add field candidates and confidence scoring`
  - Alcance: candidatos, bandas, conflictos, algoritmo versionado y reglas por campo.
  - Gate: matriz unitaria de alta/media/baja/crítica + multiimagen.
  - Evidencia: 10 pruebas nuevas de candidatos cubren las cuatro bandas, corroboración entre fotos sin contar variantes de la misma, conflictos, alternativas débiles, medidor analógico manual, tipos/rangos, ecuación financiera, trip/odómetro, tolerancias y codificación sin imagen. Core 118/118, cobertura de fuentes 90.79%; app iOS compila. T10–T11 conectarán las observaciones Vision a estos candidatos.

- [x] **T10 — Orquestar captura de carga de combustible**
  - Commit: `Build the v2 fuel entry capture workflow`
  - Alcance: factura/tablero/combustible, precarga financiera, permisos y sesión.
  - Gate: integración completa sin UI + UI happy path.
  - Evidencia: 6 pruebas de integración del workflow cubren tres fotos, borrador `review` tras relanzar, OCR/evidencia local, reanálisis sin fotos originales, deduplicación, desacuerdo financiero, captura manual sin fotos y protección de ruta/hash. El llenado real privado de tres fotos pasó y volvió a leer galones desde los JPEG locales recuperados. UI happy path de guardar llenado y snapshot pasó; integración pública iOS 52 aprobadas, 5 privadas omitidas, 0 fallos. Core 118/118 y cobertura 90.77%. T12 cerrará confirmación atómica, reanudación visible y conflictos UI; T14 optimizará/limpiará fotos.

- [x] **T11 — Orquestar captura de registro de uso**
  - Commit: `Build the v2 usage snapshot capture workflow`
  - Alcance: odómetro/trip/combustible, cámara/biblioteca y sesión.
  - Gate: integración completa sin UI + UI happy path.
  - Evidencia: 5 pruebas nuevas del workflow cubren dos fotos, odómetro/trip, ausencia de campo financiero y lectura analógica automática, trip opcional, captura manual, deduplicación, relanzamiento/reanálisis local y aislamiento por vehículo; 6 pruebas de llenado siguen pasando tras compartir el almacenamiento. Un escenario privado real leyó 108,768 mi/606.5 mi y volvió a leerlo desde JPEG locales. La UI guardó llenado+snapshot y la prueba privada de `PhotosPicker` precargó/guardó el snapshot real. Integración pública iOS: 57 aprobadas, 6 privadas omitidas, 0 fallos. Core: 118/118 y cobertura 90.77%. T12 cerrará confirmación atómica, reanudación visible y conflictos; T14 optimizará/limpiará fotos locales.

- [x] **T12 — Implementar confirmación, conflictos y repetición selectiva**
  - Commit: `Add confidence aware capture confirmation`
  - Alcance: formulario precargado, resaltado, explicación, reemplazo de una foto y confirmación única.
  - Gate: UI alta/media/baja/conflicto y recuperación tras relanzar.
  - Evidencia: las cuatro bandas tienen textos/acciones/tintes probados; UI pública verificó conflicto sin odómetro, acción de repetir solo tablero, borrador manual que se reabre y confirma una vez, y flujo llenado+snapshot. La UI privada con foto real mostró confianza media y guardó 108,768 mi/606.5 mi. Integración verificó reemplazar solo foto de factura u odómetro conservando correcciones manuales, fotos locales recuperadas y confirmación de evento+sesión+evidencia OCR en un único `save()` con rollback y rechazo del segundo guardado. Core 120/120 y cobertura 90.75%; iOS público 62 aprobadas/6 privadas omitidas; UI pública 14 aprobadas/1 privada omitida; Photos privado 1/1, todos sin fallos. T13 aplicará invariantes definitivos también a ediciones; T14 optimizará/limpiará originales locales.

- [x] **T13 — Aplicar invariantes antes del guardado**
  - Commit: `Enforce vehicle event integrity rules`
  - Alcance: odómetro, reset trip, carga parcial, ecuación financiera, nivel/paso y auditoría de override.
  - Gate: unitarias de límites + integración que prueba rollback.
  - Evidencia: 124/124 pruebas core y cobertura 90.58%; integración iOS pública 64 aprobadas/6 privadas omitidas, 0 fallos; 4/4 pruebas enfocadas de confirmación verifican rollback, rechazo de doble guardado y override auditado. La suite UI pública final pasó 14/14 (1 privada omitida). La prueba de edición se corrigió de 13 gal × Q35 = Q450 a su total coherente Q455 y pasó nuevamente. La validación es obligatoria en el servicio de confirmación y corre antes de mutar nuevos eventos y ediciones. Preflight y `git diff --check` verdes. T14 seguirá con atomicidad/limpieza de archivos de imagen.

- [x] **T14 — Optimizar evidencia local de forma atómica**
  - Commit: `Optimize confirmed evidence for local storage`
  - Alcance: máximo 2000 px, JPEG 70–75%, hash, verificación, file protection y limpieza.
  - Gate: originales de fixture, fallo de disco/decodificación y presupuesto anual.
  - Evidencia: cinco pruebas de optimización validan reemplazo sólo después de copia verificada, SHA-256, dimensiones, JPEG ≤450 KB, retención ante fallo de guardado/decodificación/staging y eliminación de captura descartada; las cinco pruebas de integración de imágenes siguen verdes. El fixture privado original de odómetro/trip pasó después de optimizarse (1/1). La suite iOS pública pasó 76 pruebas, con 7 privadas omitidas y 0 fallos; core 124/124 con cobertura 90.56%. A 10 fotos/semana × 450 KB el presupuesto es 234 MB/año, bajo el límite de 250 MB. El OCR privado completo se mantiene como gate del runtime de referencia: iOS 18.2 mostró una lectura heredada distinta para `z4-2026-06-14-1733` (77,299 vs. 107,729), por lo que no se usa ese runtime como señal de regresión.

## Fase 3 — Analítica y experiencia

- [x] **T15 — Consolidar ciclos, costos y unidades de consumo**
  - Commit: `Harden tank cycle and cost analytics`
  - Alcance: fills parciales/completos, MPG, km/gal, km/L, L/100 km, costos y edición/eliminación.
  - Gate: casos multi-vehículo y límites mensuales.
  - Evidencia: un caso de regresión con llenados intercalados de dos vehículos reproducía tres ciclos inválidos (0 km/4,000 km); el cálculo global ahora usa primero el camino monovehículo y luego combina los ciclos. Se probaron MPG, km/gal, km/L y L/100 km de un ciclo cerrado; los tests existentes cubren parcial+full, edición, eliminación, asignación mensual final/prorrateada y resúmenes multi-vehículo. Core 125/125 con 90.35% de cobertura; integración iOS pública 76 aprobadas, 7 privadas omitidas, 0 fallos.

- [x] **T16 — Calibrar medidor, autonomía y anomalías**
  - Commit: `Add calibrated range and anomaly estimates`
  - Alcance: puntos confirmados, curva no lineal, suficiencia, intervalos y anomalías.
  - Gate: datasets suficiente/insuficiente/no lineal/outlier.
  - Evidencia: `FuelGaugeCalibration` normaliza puntos de consumo/recorrido por vehículo, exige 3/8 observaciones para estados limitada/suficiente, interpola una curva no lineal y usa la mediana por banda del indicador para que un outlier no la doble. `TankCycleAnomaly` necesita al menos cuatro ciclos y usa mediana/MAD con un piso del 15%. Los datasets insuficiente, no lineal, outlier, historia suficiente y aislamiento por vehículo pasaron. Core 129/129, cobertura 90.57%; integración iOS pública 76 aprobadas, 7 privadas omitidas, 0 fallos.

- [ ] **T17 — Incorporar dashboard y gráficas v2**
  - Commit: `Present Cartrack v2 analytics and projections`
  - Alcance: tanque, curva, consumo, costos, proyección vs realidad y procedencia.
  - Gate: UI/snapshot de estados vacío/parcial/completo.

- [ ] **T18 — Versionar respaldo, validación y restauración transaccional**
  - Commit: `Add versioned transactional backups`
  - Alcance: paquete, manifiesto, hashes, imágenes opcionales, staging, duplicados y rollback.
  - Gate: fixtures v1/v2/corrupto/duplicado/interrumpido.

- [ ] **T19 — Definir DTO y conflictos estructurados para v2.1**
  - Commit: `Add structured sync readiness contracts`
  - Alcance: codificación mínima, tombstones, revisiones, conflictos y presupuesto; sin SDK/red.
  - Gate: DTO no contiene imagen/ruta; tamaño anual ≤5 MB; identificador Supabase existente prohibido.

- [ ] **T20 — Completar accesibilidad, localización y permisos**
  - Commit: `Complete accessible localized v2 workflows`
  - Alcance: VoiceOver, Dynamic Type, contraste, español/inglés, permisos bajo demanda y recordatorios.
  - Gate: recorrido P0 en ambos idiomas + auditoría de accesibilidad.

- [ ] **T21 — Agregar diagnóstico local redactado y recuperación de errores**
  - Commit: `Add privacy safe diagnostics and recovery`
  - Alcance: códigos estables, export redactado, errores de persistencia/espacio/archivo y acciones.
  - Gate: inyección de errores y revisión del artefacto exportado.

## Fase 4 — Verificación y entrega

- [ ] **T22 — Medir rendimiento y presupuestos de almacenamiento**
  - Commit: `Verify v2 performance and storage budgets`
  - Alcance: p50/p95, memoria, bytes locales y payload estructurado.
  - Gate: NFR-004/005/006 documentados con mediciones.

- [ ] **T23 — Completar recorridos E2E y controles de privacidad**
  - Commit: `Add end to end v2 release scenarios`
  - Alcance: US-01 a US-07, red desactivada, simulador limpio y fixtures privados.
  - Gate: E2E completo; cero tráfico y cero evidencia privada rastreada.

- [ ] **T24 — Cerrar candidato de lanzamiento v2**
  - Commit: `Finalize Cartrack v2 release candidate`
  - Alcance: actualizar matriz/checklist/README/ADRs, resolver todos los gaps P0/P1 y registrar dispositivo físico.
  - Gate: todos los gates locales y privados, Archive Release y worktree limpio después del commit.

- [ ] **T25 — Publicar rama y preparar pull request**
  - Commit: `Prepare Cartrack v2 pull request`
  - Alcance: solo metadatos finales de evidencia si son necesarios; no cambios funcionales. Subir rama y verificar CI del mismo SHA.
  - Gate: CI remoto verde. Crear PR hacia `main`; si no es posible, entregar URL de comparación e instrucciones manuales.

## Estado global

- Especificación: completa.
- Baseline v1 / fase 0: completado.
- Implementación v2: T16 completado; sigue T17 (dashboard y gráficas v2).
- Bloqueo actual: ninguno.
- Fuente de verdad del progreso: este archivo y el historial de `codex/cartrack-v2`.
