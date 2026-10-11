# Matriz de aceptación y trazabilidad

**Regla:** `CURRENT` describe capacidad existente, no verificación v2. Cada fila debe terminar en `VERIFIED` con evidencia del commit candidato.

## Requisitos funcionales

| ID | Estado v2 | Evidencia/prueba objetivo | Tarea |
|---|---|---|---|
| FR-001 | VERIFIED | UI e integración de crear, editar, archivar y eliminar | T06, T20 |
| FR-002 | VERIFIED | validación y configuración por vehículo | T06 |
| FR-003 | VERIFIED | repositorios, analítica y filtros aislados por vehículo | T06, T15 |
| FR-004 | VERIFIED | UI de llenado y snapshot | T10, T11 |
| FR-005 | VERIFIED | cámara/biblioteca y permisos bajo demanda | T10, T11, T20 |
| FR-006 | VERIFIED | borrador, reanudación y relanzamiento | T07, T12 |
| FR-007 | VERIFIED | fixtures y evaluación de calidad | T08 |
| FR-008 | VERIFIED | clasificación unitaria e integración | T08 |
| FR-009 | VERIFIED | reemplazo selectivo desde UI | T12 |
| FR-010 | VERIFIED | OCR local privado y gate sin cliente de red | T02, T23 |
| FR-011 | VERIFIED | candidatos y confianza unitarios | T08, T09 |
| FR-012 | VERIFIED | conflicto multiimagen seguro | T09 |
| FR-013 | VERIFIED | selección de evidencia por bandas | T09, T12 |
| FR-014 | VERIFIED | UI de resaltado y explicación | T12 |
| FR-015 | VERIFIED | confirmación obligatoria antes de guardar | T12 |
| FR-016 | VERIFIED | evidencia y corrección persistidas | T06, T13 |
| FR-017 | VERIFIED | matriz privada con tolerancias y fallback | T02, T03, T04, T23 |
| FR-018 | VERIFIED | factura real privada y parser financiero | T02, T03, T09, T23 |
| FR-019 | VERIFIED | fallback seguro y calibración confirmada | T09, T16 |
| FR-020 | VERIFIED | conversión y DTO unitarios | T06 |
| FR-021 | VERIFIED | archivo optimizado atómico | T14 |
| FR-022 | VERIFIED | hash/ruta local; DTO cloud sin imagen/ruta | T06, T14, T19 |
| FR-023 | VERIFIED | limpieza sin huérfanos | T14 |
| FR-024 | VERIFIED | metadatos v2, tombstones y DTO estructurado | T05, T06, T19 |
| FR-025 | VERIFIED | validación y override auditado | T13 |
| FR-026 | VERIFIED | reset de trip cubierto por pruebas | T13 |
| FR-027 | VERIFIED | ciclos de tanque | T15 |
| FR-028 | VERIFIED | cargas parciales | T13, T15 |
| FR-029 | VERIFIED | consistencia financiera | T13 |
| FR-030 | VERIFIED | analítica unitaria | T15 |
| FR-031 | VERIFIED | resúmenes y regresión | T15 |
| FR-032 | VERIFIED | calibración y autonomía | T16 |
| FR-033 | VERIFIED | suficiencia, rango y confianza | T16 |
| FR-034 | VERIFIED | UI, gráficas y snapshots | T17 |
| FR-035 | VERIFIED | detección de anomalías | T16 |
| FR-036 | VERIFIED | UI y recálculo | T15, T20 |
| FR-037 | VERIFIED | exportación y origen visible | T18 |
| FR-038 | VERIFIED | paquete v2, manifiesto SHA-256 e imágenes opcionales | T18 |
| FR-039 | VERIFIED | plan validado, staging y rollback | T18 |
| FR-040 | VERIFIED | rechazo de UUID/hash duplicado | T18 |
| FR-041 | VERIFIED | códigos estables, acciones y JSON local redactado | T21 |
| FR-042 | VERIFIED | tests de recordatorios | T20 |
| FR-043 | VERIFIED | protocolos/adaptadores | T06 |
| FR-044 | DEFERRED-2.1 | tests de DTO/conflictos sin red | T19 |
| FR-045 | DEFERRED-2.1 | codificación excluye imágenes | T19 |
| FR-046 | DEFERRED-2.1 | gate de proyecto prohibido | T19, T23 |

## Requisitos no funcionales

| ID | Estado v2 | Evidencia/prueba objetivo | Tarea |
|---|---|---|---|
| NFR-001 | VERIFIED | `check_v2_privacy.sh` no detecta clientes de red, configuración cloud ni evidencia privada rastreada; DTO estructurado sin imagen/ruta | T19, T23 |
| NFR-002 | VERIFIED | E2E de simulador y OCR privado ejecutados sin cliente de red v2 | T23 |
| NFR-003 | VERIFIED | fallos inyectados y transacciones de respaldo | T05, T18 |
| NFR-004 | VERIFIED | p50/p95 1–3 fotos, p95 de 3 fotos 1.369 s | T22 |
| NFR-005 | VERIFIED | pico de preparación ≤59.0 MB y proyección local 234 MB/año | T14, T22 |
| NFR-006 | VERIFIED | payload estructurado anual <5 MB, sin píxeles ni rutas | T19, T22 |
| NFR-007 | VERIFIED | VoiceOver: nombres/estado explícitos; UI P0 con tamaño de accesibilidad | T20 |
| NFR-008 | VERIFIED | recorrido P0 español/inglés y recordatorio localizado | T20 |
| NFR-009 | VERIFIED | fixtures y pruebas de migración | T05 |
| NFR-010 | VERIFIED | cobertura core ≥90% y gates locales completos | T24 |
| NFR-011 | VERIFIED | inyección y revisión de export sin datos sensibles | T21 |
| NFR-012 | VERIFIED | preflight, permisos bajo demanda y protección | T01, T23 |
| NFR-013 | VERIFIED | repositorios y unitarias puras | T06 |
| NFR-014 | VERIFIED | inspección de persistencia/DTO | T06, T19 |
| NFR-015 | PENDING-CI | gate remoto del mismo SHA | T24, T25 |

## Historias y recorridos

| Historia | Prueba E2E | Estado v2 |
|---|---|---|
| US-01 | snapshot con fotos reales → confirmación → historial/dashboard | VERIFIED — Fotos privadas 1/1 y E2E UI limpio |
| US-02 | factura+tablero → fill → tanque/costos | VERIFIED — matriz privada 12/12 y recorrido UI de llenado |
| US-03 | foto ilegible → repetir solo esa foto | VERIFIED — `testMissingSnapshotOdometerReturnsToReviewForManualCorrection` |
| US-04 | historial suficiente/insuficiente → rango explicado | VERIFIED — escenarios de analítica/rango del E2E UI |
| US-05 | exportar → validar → restaurar/rollback | VERIFIED — `PersistenceIntegrationTests` 15/15 y acciones UI visibles |
| US-06 | filtros y comparación de periodos | VERIFIED — filtros multivehículo y reportes UI |
| US-07 | dos vehículos sin cruce de datos | VERIFIED — `testMultiVehicleFilteringAcrossDashboardCaptureAndHistory` |
| US-08 | DTO/conflicto sin conexión real | DEFERRED-2.1 |

## Criterios medibles

| ID | Evidencia objetivo | Tarea de cierre |
|---|---|---|
| SC-001 | VERIFIED: matriz OCR privada 12/12; valores declarados o recuperación manual segura | T02, T03, T04, T23 |
| SC-002 | VERIFIED: factura privada real y parser financiero verificados dentro de tolerancia | T02, T03, T23 |
| SC-003 | PENDING-PHYSICAL: simulador completo; falta ejecutar checklist en iPhone físico | T23, T24 |
| SC-004 | VERIFIED: integración/UI de borrador reanudable | T07, T12 |
| SC-005 | VERIFIED: migración/restauración, hashes y rollback cubiertos | T05, T18 |
| SC-006 | VERIFIED: `check_v2_privacy.sh` prohíbe APIs cliente de red y confirma que no se rastrea evidencia privada | T23 |
| SC-007 | VERIFIED: payload estructurado proyectado ≤5 MB/año | T19, T22 |
| SC-008 | VERIFIED: máximo local proyectado 234 MB/año | T14, T22 |
| SC-009 | VERIFIED-LOCAL: cobertura ≥90%, suite local y Archive Release exitosos; falta CI remoto del SHA de T25 | T24 |
| SC-010 | VERIFIED: no hay filas P0/P1 en `GAP`; v2.1 queda explícitamente diferido | T24 |

## Evidencia final

Al cerrar una fila se registra en el PR:

- commit que la implementa;
- nombre de prueba/gate;
- resultado y fecha;
- `.xcresult` o log cuando aplique;
- limitación residual, si existe.
