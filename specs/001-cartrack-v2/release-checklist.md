# Checklist de lanzamiento — Cartrack v2

**Commit funcional validado:** `df5a3337d99993d433fd8c2754ddaebd63e4d607` en `codex/ci-green-release`
**Fecha de evidencia local/remota:** 2026-10-21
**Simulador:** iPhone 16 Pro / iOS 18.2 / UDID `24B0C7AF-22CB-42A3-A2E3-E340C8841FED`
**Dispositivo físico:** diferido explícitamente por el propietario el 2026-10-11. No se declara aprobado ni se usa como gate de v2.

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
- [x] Smoke en iPhone físico diferido por aprobación explícita; no ejecutado.
- [x] VoiceOver, Dynamic Type, español e inglés verificados en simulador.
- [x] Build Release y Archive completados.
- [x] Cero crashes críticos conocidos en los gates automatizados.

### Smoke físico diferido

- [x] El propietario autorizó diferir esta validación el 2026-10-11; no bloquea el cierre automatizado de v2.
- [ ] Antes de distribuir a un dispositivo físico: conectar un iPhone con iOS 17 o posterior y registrar modelo/iOS/UDID.
- [ ] Antes de distribuir a un dispositivo físico: instalar el Archive Release y recorrer US-01 a US-05 con modo avión activado.
- [ ] Antes de distribuir a un dispositivo físico: validar permisos de cámara, Fotos, ubicación y recordatorios bajo demanda.
- [ ] Antes de distribuir a un dispositivo físico: confirmar cámara real, orientación, foreground/background, VoiceOver y Dynamic Type.
- [ ] Antes de distribuir a un dispositivo físico: adjuntar el `.xcresult` o resultado manual sin fotos privadas.

## Git y publicación

- [x] Cada tarea completada corresponde a un commit.
- [x] Historial de rama revisable y sin secretos.
- [x] Worktree limpio después del commit candidato funcional.
- [x] `Scripts/preflight_publish.sh --require-remote` pasa después del commit candidato funcional.
- [x] Rama `codex/ci-green-release` publicada.
- [x] CI remoto verde sobre el mismo SHA funcional: [run 39660851167](https://github.com/khrizenriquez/car-fuel-notebook/actions/runs/39660851167).
- [x] PR creado: [#4](https://github.com/khrizenriquez/car-fuel-notebook/pull/4).
