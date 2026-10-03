# Quickstart de desarrollo y verificación

## Requisitos

- macOS y Xcode compatibles con el proyecto.
- iOS Simulator.
- Paquete privado de fixtures en las rutas ignoradas para el gate estricto.
- Git remoto `origin` para publicación final.

No se requiere Supabase para v2.

## Rama

```bash
git switch codex/cartrack-v2
git status --short --branch
```

El worktree debe revisarse antes de cada commit. No usar comandos destructivos para limpiar cambios ajenos.

## Gates rápidos

```bash
Scripts/check_core_coverage.sh 90
Scripts/verify_local.sh
```

## Gate privado

```bash
Scripts/verify_private_image_scenarios.sh
```

El script usa un simulador dedicado. No debe crear/borrar simuladores adicionales por coincidencias parciales. En la Mac propietaria, un fixture ausente u omitido es fallo.

## Preflight

```bash
Scripts/preflight_publish.sh --require-remote
```

Antes del push final, el comando debe ejecutarse sin `--allow-dirty`.

## Flujo por tarea

1. Elegir la primera tarea no completada de `tasks.md`.
2. Verificar dependencias y archivos permitidos.
3. Implementar junto con sus pruebas.
4. Ejecutar el gate de esa tarea.
5. Revisar `git diff` y privacidad.
6. Actualizar estado/evidencia documental cuando corresponda.
7. Crear exactamente un commit con el asunto indicado.

## Cierre

1. Ejecutar `release-checklist.md` sobre un commit limpio.
2. Subir `codex/cartrack-v2`.
3. Crear PR hacia `main` y adjuntarlo a la tarea de Codex.
4. Si no se puede crear automáticamente, entregar URL de comparación, commit candidato y resultados de gates.
