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

- [ ] **T05 — Introducir esquema versionado y migración v1 a v2**
  - Commit: `Add versioned v1 to v2 data migration`
  - Alcance: esquema, staging, respaldo previo, fixtures de migración y rollback.
  - Gate: migración vacía/multivehículo/con imágenes + fallos inyectados.

- [ ] **T06 — Separar dominio, repositorios y metadatos cloud-ready**
  - Commit: `Separate domain repositories from local persistence`
  - Alcance: protocolos, adaptadores SwiftData, SyncMetadata, DTO internos, `LocalPhotoAsset` y `OCRFieldEvidence`.
  - Gate: unitarias puras + integración de repositorios; app compila.

- [ ] **T07 — Persistir sesiones de captura recuperables**
  - Commit: `Persist recoverable capture sessions`
  - Alcance: máquina de estados, borradores atómicos, reanudación y descarte explícito.
  - Gate: relanzamiento durante draft/analyzing/review.

## Fase 2 — Canalización OCR

- [ ] **T08 — Agregar calidad, clasificación y preprocesamiento de imágenes**
  - Commit: `Add capture quality and image classification pipeline`
  - Alcance: blur/exposición/orientación/clase y variantes temporales.
  - Gate: fixtures por problema y cero persistencia de variantes.

- [ ] **T09 — Modelar candidatos, validación cruzada y confianza por campo**
  - Commit: `Add field candidates and confidence scoring`
  - Alcance: candidatos, bandas, conflictos, algoritmo versionado y reglas por campo.
  - Gate: matriz unitaria de alta/media/baja/crítica + multiimagen.

- [ ] **T10 — Orquestar captura de carga de combustible**
  - Commit: `Build the v2 fuel entry capture workflow`
  - Alcance: factura/tablero/combustible, precarga financiera, permisos y sesión.
  - Gate: integración completa sin UI + UI happy path.

- [ ] **T11 — Orquestar captura de registro de uso**
  - Commit: `Build the v2 usage snapshot capture workflow`
  - Alcance: odómetro/trip/combustible, cámara/biblioteca y sesión.
  - Gate: integración completa sin UI + UI happy path.

- [ ] **T12 — Implementar confirmación, conflictos y repetición selectiva**
  - Commit: `Add confidence aware capture confirmation`
  - Alcance: formulario precargado, resaltado, explicación, reemplazo de una foto y confirmación única.
  - Gate: UI alta/media/baja/conflicto y recuperación tras relanzar.

- [ ] **T13 — Aplicar invariantes antes del guardado**
  - Commit: `Enforce vehicle event integrity rules`
  - Alcance: odómetro, reset trip, carga parcial, ecuación financiera, nivel/paso y auditoría de override.
  - Gate: unitarias de límites + integración que prueba rollback.

- [ ] **T14 — Optimizar evidencia local de forma atómica**
  - Commit: `Optimize confirmed evidence for local storage`
  - Alcance: máximo 2000 px, JPEG 70–75%, hash, verificación, file protection y limpieza.
  - Gate: originales de fixture, fallo de disco/decodificación y presupuesto anual.

## Fase 3 — Analítica y experiencia

- [ ] **T15 — Consolidar ciclos, costos y unidades de consumo**
  - Commit: `Harden tank cycle and cost analytics`
  - Alcance: fills parciales/completos, MPG, km/gal, km/L, L/100 km, costos y edición/eliminación.
  - Gate: casos multi-vehículo y límites mensuales.

- [ ] **T16 — Calibrar medidor, autonomía y anomalías**
  - Commit: `Add calibrated range and anomaly estimates`
  - Alcance: puntos confirmados, curva no lineal, suficiencia, intervalos y anomalías.
  - Gate: datasets suficiente/insuficiente/no lineal/outlier.

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
- Implementación v2: inicia en T05 (migración versionada).
- Bloqueo actual: ninguno.
- Fuente de verdad del progreso: este archivo y el historial de `codex/cartrack-v2`.
