# Investigación y decisiones — Cartrack v2

## 1. Inventario actual

El repositorio ya dispone de:

- SwiftUI y SwiftData.
- Modelos `Vehicle`, `FuelFillEvent`, `SnapshotEvent`, `MonthlyManualAdjustment` e `ImageAsset`.
- Vision OCR y parser de facturas/tablero.
- Almacenamiento local protegido de imágenes.
- Historial, dashboard, mapa, reportes, respaldo, recordatorios y reset.
- Pruebas de núcleo, integración, UI y fixtures privados.
- ADR-001 a ADR-007.

Los documentos históricos son útiles, pero mezclan requisitos, estado y decisiones. El paquete `specs/001-cartrack-v2` se convierte en la fuente normativa para v2.

## 2. Brechas confirmadas

- Un fixture prioritario real no produce odómetro ni trip.
- La confianza no es una entidad explícita por campo.
- No existe sesión de captura persistente/reanudable formal.
- Los modelos no comparten todos los metadatos necesarios para v2.1.
- El dominio aún conoce SwiftData directamente.
- El respaldo actual reemplaza datos y contiene imágenes embebidas, pero no tiene manifiesto/hash/transacción de staging formal.
- No hay migración v1→v2 definida ni probada.
- La accesibilidad/localización no tiene gate completo.
- La trazabilidad requisito→prueba→evidencia no estaba centralizada.

## 3. Decisiones de producto aprobadas

1. V2 es una mejora integral, no solo una corrección OCR.
2. Sigue siendo local-first y offline.
3. V2.1 añadirá nube; v2 solo deja contratos listos.
4. OCR debe precargar idealmente sin intervención, pero siempre existe confirmación previa al guardado.
5. Una imagen ilegible activa recuperación; nunca se inventa el dato.
6. Las fotografías no se sincronizan.
7. Después de confirmar, se conserva una copia local optimizada y se elimina el original temporal tras verificarla.
8. La base Supabase existente (~20 MB) no se toca.
9. El proyecto futuro de Supabase será independiente.
10. Toda v2 se desarrolla en una rama y cada tarea es un commit.

## 4. Presupuesto de almacenamiento

Se midieron 28 fixtures actuales:

- promedio original: 2,575,398 bytes;
- mínimo: 878,039 bytes;
- máximo: 4,680,647 bytes.

Una prueba de reducción a máximo 2000 px y JPEG 70% produjo:

- promedio: 391,270 bytes;
- mínimo: 212,397 bytes;
- máximo: 588,710 bytes.

Con 11 imágenes semanales:

- original: ~1.47 GB/año local;
- optimizado: ~224 MB/año local.

La meta normativa es ≤250 MB/año por usuario para evidencia local.

Sin imágenes cloud, cinco eventos semanales requieren aproximadamente 0.8–2.1 MB/año de filas estructuradas. Se adopta un presupuesto conservador de 5 MB/año por usuario incluyendo índices y metadatos.

## 5. Alternativas descartadas

### Subir originales a Supabase

Descartada por privacidad, costo, egress y porque los valores estructurados satisfacen sincronización. También convierte la red en requisito de recuperación de evidencia.

### Subir miniaturas

Descartada para v2.1 inicial. Agrega complejidad y cuota sin valor esencial. Puede reconsiderarse mediante una enmienda explícita.

### Guardar todos los tokens y bounding boxes de Vision

Descartada. Son datos voluminosos, dependientes de implementación y recalculables. Solo se conserva texto mínimo y evidencia por campo; el diagnóstico completo es local y temporal.

### Guardado totalmente automático

Descartado. Una lectura incorrecta contamina odómetro, tanques y proyecciones posteriores. La confirmación rápida es obligatoria.

### Nube dentro de v2

Descartada para reducir riesgo. El valor principal de v2 es captura confiable, integridad y analítica; v2.1 implementará Auth/RLS/sync sobre contratos probados.

## 6. Supabase v2.1

La cuenta gratuita disponible no cambia v2. La implementación futura debe:

- crear un proyecto independiente;
- usar Auth y RLS por propietario;
- guardar solo DTO estructurado;
- no usar Storage para imágenes;
- medir tamaño real por evento antes del despliegue;
- impedir por configuración que un build apunte a la base existente;
- documentar que una restauración cloud no incluye fotografías.

## 7. Preguntas resueltas

- ¿Original o copia optimizada local? Copia optimizada tras confirmación.
- ¿OCR cloud? No.
- ¿Confirmación? Sí, siempre.
- ¿Sync de fotos? No.
- ¿Proyecto Supabase compartido? No.
- ¿Una o varias ramas? Una rama v2.
- ¿Qué significa terminado? Solo requisitos `VERIFIED` y todos los gates finales verdes.
