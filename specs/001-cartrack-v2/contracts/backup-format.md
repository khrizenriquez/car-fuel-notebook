# Contrato — Respaldo local v2

## Contenedor

Directorio-paquete con extensión `.cartrackbackup` que contiene:

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
- arreglo `files` con ruta relativa, tamaño y SHA-256 de `records.json` y cada archivo de evidencia incluido
- tamaño total esperado

No incluye credenciales, tokens ni rutas absolutas.

`records.json` conserva la bandera `hasLocalEvidence` cuando se omiten bytes. Así una
restauración puede distinguir “no había foto” de “había foto en el teléfono de origen,
pero este respaldo estructurado no la copió”. Las fotos de captura v2 se restauran con
su UUID, hash y ruta relativa regenerada; nunca con la ruta absoluta del dispositivo de origen.

## Exportación

- Escritura en directorio temporal.
- Verificación de hashes antes de publicar el archivo.
- Opción explícita de incluir imágenes.
- Si no se incluyen, los registros conservan `hasLocalEvidence` como información, sin rutas inválidas.
- Antes de publicar el paquete se valida el mismo manifiesto que validará la importación.

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

Produce un `BackupImportPlan` sin modificar persistencia. El plan expone versión, conteos,
presencia de bytes de imagen y número de UUID que reemplazarían registros locales.

## Restauración

1. crear respaldo de seguridad del estado actual;
2. importar a staging;
3. aplicar migraciones;
4. validar invariantes y conteos;
5. intercambiar estado de forma atómica;
6. conservar respaldo anterior hasta confirmación.

Ante error se restaura el estado original.

La copia de seguridad de la restauración permanece en temporal hasta la confirmación del
`save()`. Los checkpoints de prueba cubren fallo después de crear esa copia, después del
staging y justo antes de confirmar el reemplazo.

## Compatibilidad

- V2 importa formato v1 mediante adaptador probado.
- V1 no necesita importar formato v2.
- Cambiar `formatVersion` exige fixture y prueba de migración.
