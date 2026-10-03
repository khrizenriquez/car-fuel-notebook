# Contrato — Respaldo local v2

## Contenedor

Paquete con extensión `.cartrackbackup` que contiene:

```text
manifest.json
records.json
images/          # opcional
diagnostics/     # opcional, redactado
```

## Manifiesto

Campos obligatorios:

- `formatVersion`
- `schemaVersion`
- `exportedAt`
- `appVersion`
- conteos por entidad
- presencia/ausencia de imágenes
- SHA-256 de `records.json` y cada archivo incluido
- tamaño total esperado

No incluye credenciales, tokens ni rutas absolutas.

## Exportación

- Escritura en directorio temporal.
- Verificación de hashes antes de publicar el archivo.
- Opción explícita de incluir imágenes.
- Si no se incluyen, los registros conservan `hasLocalEvidence` como información, sin rutas inválidas.

## Validación previa

Debe comprobar:

- versión soportada;
- JSON decodificable;
- hashes y conteos;
- UUID únicos;
- referencias a vehículos;
- unidades/rangos;
- espacio disponible;
- conflictos con datos actuales.

Produce un `BackupImportPlan` sin modificar persistencia.

## Restauración

1. crear respaldo de seguridad del estado actual;
2. importar a staging;
3. aplicar migraciones;
4. validar invariantes y conteos;
5. intercambiar estado de forma atómica;
6. conservar respaldo anterior hasta confirmación.

Ante error se restaura el estado original.

## Compatibilidad

- V2 importa formato v1 mediante adaptador probado.
- V1 no necesita importar formato v2.
- Cambiar `formatVersion` exige fixture y prueba de migración.
