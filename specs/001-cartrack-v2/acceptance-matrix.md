# Matriz de aceptación y trazabilidad

**Regla:** `CURRENT` describe capacidad existente, no verificación v2. Cada fila debe terminar en `VERIFIED` con evidencia del commit candidato.

## Requisitos funcionales

| ID | Estado inicial | Evidencia/prueba objetivo | Tarea |
|---|---|---|---|
| FR-001 | GAP | UI + integración de archivo/eliminación | T06, T20 |
| FR-002 | CURRENT | unitarias de validación de vehículo | T06 |
| FR-003 | CURRENT | analítica/repositorios multivehículo | T06, T15 |
| FR-004 | CURRENT | UI de ambos tipos de sesión | T10, T11 |
| FR-005 | GAP | UI cámara/biblioteca y permisos | T10, T11 |
| FR-006 | GAP | integración de borrador y relanzamiento | T07, T12 |
| FR-007 | GAP | fixtures de calidad | T08 |
| FR-008 | GAP | clasificación unitaria/integración | T08 |
| FR-009 | CURRENT | UI de reemplazo selectivo | T12 |
| FR-010 | CURRENT | test offline/red y OCR real | T03, T23 |
| FR-011 | GAP | candidatos/confianza unitarios | T08, T09 |
| FR-012 | GAP | conflicto multiimagen | T09 |
| FR-013 | GAP | selección por bandas | T09, T12 |
| FR-014 | GAP | UI resaltado/explicación | T12 |
| FR-015 | CURRENT | UI confirmación obligatoria | T12 |
| FR-016 | GAP | persistencia de evidencia/corrección | T06, T13 |
| FR-017 | GAP | matriz privada; tolerancias | T03, T04 |
| FR-018 | GAP | fixtures de factura | T03, T09 |
| FR-019 | GAP | fallback y calibración confirmada | T09, T16 |
| FR-020 | CURRENT | unitarias de conversión/DTO | T06 |
| FR-021 | GAP | archivo optimizado atómico | T14 |
| FR-022 | GAP | hash/ruta local; DTO sin imagen | T06, T14, T19 |
| FR-023 | CURRENT | integración de limpieza sin huérfanos | T14 |
| FR-024 | GAP | modelos v2/migración | T05, T06 |
| FR-025 | GAP | validación y override auditado | T13 |
| FR-026 | GAP | unitarias de reset de trip | T13 |
| FR-027 | CURRENT | ciclos de tanque | T15 |
| FR-028 | GAP | cargas parciales | T13, T15 |
| FR-029 | GAP | consistencia financiera | T13 |
| FR-030 | CURRENT | unitarias analíticas | T15 |
| FR-031 | CURRENT | resúmenes y regresión | T15 |
| FR-032 | GAP | calibración/autonomía | T16 |
| FR-033 | GAP | suficiencia, rango y confianza | T16 |
| FR-034 | GAP | UI/gráficas y snapshots | T17 |
| FR-035 | GAP | detección de anomalías | T16 |
| FR-036 | CURRENT | UI + recalculo | T15, T20 |
| FR-037 | CURRENT | export tests y origen visible | T18 |
| FR-038 | GAP | contrato/fixture de respaldo v2 | T18 |
| FR-039 | GAP | staging/rollback de restauración | T18 |
| FR-040 | GAP | UUID/hash duplicado | T18 |
| FR-041 | GAP | diagnóstico redactado | T21 |
| FR-042 | CURRENT | tests de recordatorios | T20 |
| FR-043 | GAP | protocolos/adaptadores | T06 |
| FR-044 | DEFERRED-2.1 | tests de DTO/conflictos sin red | T19 |
| FR-045 | DEFERRED-2.1 | codificación excluye imágenes | T19 |
| FR-046 | DEFERRED-2.1 | gate de proyecto prohibido | T19, T23 |

## Requisitos no funcionales

| ID | Estado inicial | Evidencia/prueba objetivo | Tarea |
|---|---|---|---|
| NFR-001 | CURRENT | prueba/red + escaneo DTO | T19, T23 |
| NFR-002 | CURRENT | E2E con red desactivada | T23 |
| NFR-003 | GAP | fallos inyectados/transacciones | T05, T18 |
| NFR-004 | GAP | medición p50/p95 | T22 |
| NFR-005 | GAP | benchmark de optimización/proyección | T14, T22 |
| NFR-006 | TARGET-V2 | test de tamaño serializado | T19, T22 |
| NFR-007 | GAP | auditoría VoiceOver/Dynamic Type | T20 |
| NFR-008 | GAP | pruebas español/inglés | T20 |
| NFR-009 | GAP | fixtures de migración | T05 |
| NFR-010 | CURRENT | coverage + gates completos | T24 |
| NFR-011 | GAP | export diagnóstico | T21 |
| NFR-012 | CURRENT | preflight/permisos/protección | T01, T23 |
| NFR-013 | GAP | repositorios y unitarias puras | T06 |
| NFR-014 | GAP | inspección de persistencia/DTO | T06, T19 |
| NFR-015 | GAP | gate final mismo SHA | T24, T25 |

## Historias y recorridos

| Historia | Prueba E2E | Estado inicial |
|---|---|---|
| US-01 | snapshot con fotos reales → confirmación → historial/dashboard | GAP |
| US-02 | factura+tablero → fill → tanque/costos | GAP |
| US-03 | foto ilegible → repetir solo esa foto | GAP |
| US-04 | historial suficiente/insuficiente → rango explicado | GAP |
| US-05 | exportar → validar → restaurar/rollback | GAP |
| US-06 | filtros y comparación de periodos | CURRENT |
| US-07 | dos vehículos sin cruce de datos | CURRENT |
| US-08 | DTO/conflicto sin conexión real | DEFERRED-2.1 |

## Criterios medibles

| ID | Evidencia objetivo | Tarea de cierre |
|---|---|---|
| SC-001 | reporte de fixtures digitales y fallback seguro | T03, T04, T23 |
| SC-002 | reporte de fixtures de factura | T03, T23 |
| SC-003 | `.xcresult` de simulador + checklist de iPhone físico | T23, T24 |
| SC-004 | integración/UI de reanudación | T07, T12 |
| SC-005 | reporte de migración/restauración | T05, T18 |
| SC-006 | inspección de red sin transmisión de imágenes | T23 |
| SC-007 | medición serializada ≤5 MB/año | T19, T22 |
| SC-008 | medición local ≤250 MB/año | T14, T22 |
| SC-009 | gates finales, cobertura y crash review | T24 |
| SC-010 | esta matriz sin filas P0/P1 pendientes | T24 |

## Evidencia final

Al cerrar una fila se registra en el PR:

- commit que la implementa;
- nombre de prueba/gate;
- resultado y fecha;
- `.xcresult` o log cuando aplique;
- limitación residual, si existe.
