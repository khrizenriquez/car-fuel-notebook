# Checklist de lanzamiento — Cartrack v2

**Commit candidato:** pendiente
**Fecha:** pendiente
**Dispositivo físico:** pendiente

## Producto

- [ ] US-01 a US-07 están `VERIFIED`.
- [ ] No quedan requisitos P0/P1 en `GAP`.
- [ ] Los no objetivos no se incorporaron accidentalmente.

## Datos y migración

- [ ] Migración v1→v2 pasa con dataset representativo.
- [ ] Rollback probado mediante fallo inyectado.
- [ ] Respaldo v1 y v2 validados/restaurados.
- [ ] Conteos, UUID, relaciones y hashes coinciden.
- [ ] No hay pérdida de fotografías locales.

## OCR y captura

- [ ] Todos los fixtures privados prioritarios pasan.
- [ ] Variantes rotadas/recomprimidas pasan o degradan de forma segura.
- [ ] No existen respuestas por hash/firma exacta.
- [ ] Confianza baja nunca guarda automáticamente.
- [ ] Confirmación y repetición selectiva funcionan.
- [ ] El caso `z4-2026-07-26-1305` está resuelto y verificado.

## Analítica

- [ ] Cargas parciales/completas producen ciclos correctos.
- [ ] Unidades y costos concuerdan.
- [ ] Autonomía muestra intervalo/confianza.
- [ ] Curva del medidor utiliza solo datos confirmados.
- [ ] Edición/eliminación recalculan resultados.

## Privacidad y almacenamiento

- [ ] Cero imágenes, Base64 o rutas locales en DTO cloud-ready.
- [ ] Cero tráfico de captura/OCR en v2.
- [ ] La base Supabase existente no aparece en configuración/código.
- [ ] No hay fixtures privados ni secretos rastreados.
- [ ] Optimización local es atómica y cumple presupuesto.

## Calidad

- [ ] `Scripts/check_core_coverage.sh 90` pasa.
- [ ] `Scripts/verify_local.sh` pasa.
- [ ] `Scripts/verify_private_image_scenarios.sh` pasa.
- [ ] E2E pasa en simulador limpio.
- [ ] Smoke pasa en iPhone físico.
- [ ] VoiceOver, Dynamic Type, español e inglés verificados.
- [ ] Build Release y Archive completados.
- [ ] Cero crashes críticos conocidos.

## Git y publicación

- [ ] Cada tarea completada corresponde a un commit.
- [ ] Historial de rama revisable y sin secretos.
- [ ] Worktree limpio.
- [ ] `Scripts/preflight_publish.sh --require-remote` pasa.
- [ ] Rama `codex/cartrack-v2` publicada.
- [ ] CI remoto verde sobre el mismo commit.
- [ ] PR creado o instrucciones manuales entregadas.
