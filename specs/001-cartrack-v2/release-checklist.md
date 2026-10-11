# Checklist de lanzamiento — Cartrack v2

**Commit candidato:** `Finalize Cartrack v2 release candidate` en `codex/cartrack-v2`
**Fecha de evidencia local:** 2026-10-11
**Simulador:** iPhone 16 Pro / iOS 18.2 / UDID `24B0C7AF-22CB-42A3-A2E3-E340C8841FED`
**Dispositivo físico:** pendiente; no se declara aprobado hasta ejecutarlo.

## Producto

- [x] US-01 a US-07 están `VERIFIED`.
- [x] No quedan requisitos P0/P1 en `GAP`.
- [x] Los no objetivos no se incorporaron accidentalmente; cloud/sincronización activa sigue diferida a v2.1.

## Datos y migración

- [x] Migración v1→v2 pasa con dataset representativo.
- [x] Rollback probado mediante fallo inyectado.
- [x] Respaldo v1 y v2 validados/restaurados.
- [x] Conteos, UUID, relaciones y hashes coinciden.
- [x] No hay pérdida de fotografías locales en restauración verificada.

## OCR y captura

- [x] Todos los fixtures privados prioritarios pasan (12/12).
- [x] Variantes rotadas/recomprimidas pasan o degradan de forma segura.
- [x] No existen respuestas por hash/firma exacta.
- [x] Confianza baja nunca guarda automáticamente.
- [x] Confirmación y repetición selectiva funcionan.
- [x] El caso `z4-2026-07-26-1305` está resuelto y verificado.

## Analítica

- [x] Cargas parciales/completas producen ciclos correctos.
- [x] Unidades y costos concuerdan.
- [x] Autonomía muestra intervalo/confianza.
- [x] Curva del medidor utiliza solo datos confirmados.
- [x] Edición/eliminación recalculan resultados.

## Privacidad y almacenamiento

- [x] Cero imágenes, Base64 o rutas locales en DTO cloud-ready.
- [x] No hay cliente de red para captura/OCR en v2; el gate estático lo prohíbe.
- [x] La base Supabase existente no aparece en configuración/código.
- [x] No hay fixtures privados ni secretos rastreados.
- [x] Optimización local es atómica y cumple presupuesto.

## Calidad

- [x] `Scripts/check_core_coverage.sh 90` pasa.
- [x] `Scripts/verify_local.sh` pasa: 101 aprobadas, 8 omisiones previstas.
- [x] `Scripts/verify_private_image_scenarios.sh` pasa: 12/12.
- [x] E2E pasa en simulador limpio: UI 17/17, más Fotos privadas 1/1.
- [ ] Smoke pasa en iPhone físico.
- [x] VoiceOver, Dynamic Type, español e inglés verificados en simulador.
- [x] Build Release y Archive completados.
- [x] Cero crashes críticos conocidos en los gates automatizados.

### Smoke físico pendiente

- [ ] Conectar un iPhone con iOS 17 o posterior y registrar modelo/iOS/UDID en esta sección.
- [ ] Instalar el Archive Release y recorrer US-01 a US-05 con modo avión activado.
- [ ] Validar permisos de cámara, Fotos, ubicación y recordatorios bajo demanda.
- [ ] Confirmar cámara real, orientación, foreground/background, VoiceOver y Dynamic Type.
- [ ] Adjuntar el `.xcresult` o el resultado manual sin fotos privadas y marcar el smoke como aprobado.

## Git y publicación

- [x] Cada tarea completada corresponde a un commit.
- [x] Historial de rama revisable y sin secretos.
- [ ] Worktree limpio después del commit candidato.
- [ ] `Scripts/preflight_publish.sh --require-remote` pasa después del commit candidato.
- [x] Rama `codex/cartrack-v2` publicada.
- [ ] CI remoto verde sobre el mismo commit.
- [ ] PR creado o instrucciones manuales entregadas.
