# Especificación de producto — Cartrack v2

**Estado:** Aprobada para planificación
**Fecha:** 2026-10-03
**Rama:** `codex/cartrack-v2`
**Constitución:** `.specify/memory/constitution.md`

## 1. Visión

Cartrack v2 es una aplicación iPhone local-first que transforma fotografías de tablero y facturas en registros confiables de uso y combustible. El usuario toma o selecciona las fotos, la aplicación ejecuta OCR local, precarga un formulario, explica cualquier incertidumbre y guarda únicamente después de una confirmación rápida.

La aplicación convierte esos registros en consumo real, costos, autonomía y una curva calibrada del indicador de combustible para uno o varios vehículos. V2 funciona sin nube; su modelo queda preparado para sincronizar exclusivamente datos estructurados en v2.1.

## 2. Problema

El flujo actual cubre captura, OCR, historial y analítica, pero la lectura de imágenes reales no es consistente en todos los casos, los contratos de confianza no están modelados por campo, el modelo no está preparado completamente para sincronización y la evidencia de lanzamiento está dispersa. V2 debe convertir ese conjunto en un producto verificable, recuperable y utilizable diariamente.

## 3. Usuarios y contexto

### Persona principal

Propietario de uno o varios vehículos que registra tableros y cargas de combustible desde su iPhone, generalmente después de conducir o repostar, y desea evitar transcribir números manualmente.

### Contextos relevantes

- Fotografías nocturnas con iluminación roja.
- Fotografías diurnas con reflejos o desenfoque moderado.
- Tableros donde odómetro y trip comparten display.
- Indicadores analógicos no lineales.
- Facturas con formatos y separadores variables.
- Operación sin internet.
- Cambio o pérdida de dispositivo.

## 4. Alcance

### Incluido en v2

- Varios vehículos.
- Carga de combustible parcial o completa.
- Registro de uso sin repostaje.
- Captura desde cámara o biblioteca.
- Control de calidad, clasificación, preprocesamiento y OCR local.
- Precarga y confirmación de campos.
- Confianza y procedencia por campo.
- Imágenes locales optimizadas, nunca sincronizadas.
- Historial, edición y eliminación segura.
- Consumo, costos, autonomía, proyecciones y gráficas.
- Respaldo/restauración local y migración v1→v2.
- Recordatorios, reportes, ubicación opcional y diagnóstico local.
- Español e inglés, VoiceOver y Dynamic Type.
- Modelo cloud-ready para v2.1.

### Fuera del alcance de v2

- Cuentas, autenticación o sincronización activa.
- Carga de imágenes a Supabase o cualquier servicio.
- Compartir vehículos entre usuarios.
- OBD, diagnóstico mecánico o telemetría vehicular.
- Android, web o macOS.
- Garantizar OCR en una fotografía físicamente ilegible.

## 5. Historias de usuario prioritarias

### US-01 — Registrar uso desde fotografías (P0)

Como conductor, quiero fotografiar odómetro y nivel de combustible para recibir un formulario precargado y guardar un registro sin transcribir datos legibles.

**Aceptación:** dada una pareja de imágenes legibles, cuando finaliza el análisis, entonces odómetro, trip y combustible disponibles aparecen precargados con unidad, confianza y fuente; el usuario confirma y el registro aparece en historial y analítica.

### US-02 — Registrar una carga (P0)

Como conductor, quiero fotografiar factura, tablero y nivel para registrar la carga y sus costos con mínima intervención.

**Aceptación:** los campos legibles de fecha, estación, monto, precio, volumen, odómetro y trip se precargan; las relaciones monto≈precio×volumen se validan antes de guardar.

### US-03 — Recuperarse de OCR incierto (P0)

Como usuario, quiero saber exactamente qué no se pudo leer y repetir solo la foto problemática, sin perder el resto del formulario.

**Aceptación:** un campo de baja confianza no se guarda con un valor inventado; la sesión conserva candidatos válidos y permite repetir o corregir ese campo.

### US-04 — Consultar autonomía real (P0)

Como conductor, quiero una autonomía basada en mi historial y en la curva real del medidor, con un intervalo que exprese incertidumbre.

**Aceptación:** con historial suficiente se muestran estimación central, rango conservador, nivel de confianza y datos utilizados; sin historial suficiente se explica que no puede estimarse.

### US-05 — Proteger y recuperar datos (P0)

Como usuario, quiero respaldar, validar y restaurar mis registros sin perder información ni mezclar duplicados.

**Aceptación:** la importación muestra un resumen, valida formato y hashes, y se aplica completamente o no se aplica.

### US-06 — Comprender consumo y costos (P1)

Como propietario, quiero comparar tanques, semanas y meses para detectar cambios de consumo y gasto.

### US-07 — Usar varios vehículos (P1)

Como propietario, quiero que capturas, reglas y métricas permanezcan separadas por vehículo.

### US-08 — Cambiar de dispositivo en v2.1 (P2 diferida)

Como usuario autenticado futuro, quiero recuperar datos estructurados en otro dispositivo, entendiendo que las imágenes permanecen solo en respaldos locales.

## 6. Requisitos funcionales

### Vehículos y configuración

- **FR-001:** crear, editar, archivar y eliminar vehículos con confirmación.
- **FR-002:** configurar unidad de odómetro, capacidad del tanque, escala y paso del medidor.
- **FR-003:** mantener todos los eventos y cálculos aislados por vehículo.

### Captura y sesión

- **FR-004:** iniciar una sesión de carga o de registro de uso.
- **FR-005:** aceptar cámara y biblioteca para cada tipo de evidencia.
- **FR-006:** conservar el borrador si la aplicación pasa a segundo plano o termina inesperadamente.
- **FR-007:** evaluar orientación, exposición, reflejo, recorte y desenfoque antes del OCR.
- **FR-008:** clasificar la imagen como factura, odómetro/trip, combustible u otra.
- **FR-009:** permitir reemplazar una imagen sin perder otros resultados de la sesión.

### OCR y precarga

- **FR-010:** ejecutar OCR local sin conexión y sin enviar píxeles fuera del dispositivo.
- **FR-011:** producir candidatos por campo con valor bruto, normalizado, fuente y confianza.
- **FR-012:** fusionar candidatos de varias imágenes sin ocultar conflictos.
- **FR-013:** precargar valores de alta y media confianza; dejar vacíos los de baja confianza.
- **FR-014:** marcar visualmente campos inciertos y explicar la recuperación disponible.
- **FR-015:** requerir confirmación explícita del formulario antes de guardar.
- **FR-016:** conservar corrección manual y valor OCR mínimo para auditoría.
- **FR-017:** reconocer odómetro y trip dentro de las tolerancias del fixture.
- **FR-018:** reconocer monto, precio, volumen, fecha y estación cuando sean legibles.
- **FR-019:** tratar el indicador analógico con un lector calibrable; si no es confiable, solicitar confirmación.

### Persistencia e imágenes

- **FR-020:** guardar datos canónicos y sus unidades de presentación separadamente.
- **FR-021:** optimizar la imagen confirmada a máximo 2000 px y JPEG 70–75%, verificando legibilidad antes de eliminar el original temporal.
- **FR-022:** conservar imágenes solo localmente, vinculadas por UUID y hash.
- **FR-023:** eliminar archivos e índices relacionados sin dejar huérfanos.
- **FR-024:** conservar `createdAt`, `updatedAt`, versión, revisión y `deletedAt` en entidades sincronizables.

### Reglas y analítica

- **FR-025:** impedir retroceso de odómetro salvo corrección explícita auditada.
- **FR-026:** detectar reinicio de trip sin confundirlo con distancia negativa.
- **FR-027:** cerrar ciclos únicamente con las reglas documentadas para tanque completo.
- **FR-028:** no calcular consumo definitivo desde una carga parcial aislada.
- **FR-029:** validar monto, precio y volumen dentro de tolerancia configurable.
- **FR-030:** calcular MPG, km/gal, km/L, L/100 km y costo por distancia.
- **FR-031:** calcular resúmenes diario, semanal, mensual y por tanque.
- **FR-032:** estimar autonomía con consumo histórico, capacidad útil y curva calibrada.
- **FR-033:** mostrar intervalo, confianza y suficiencia de muestra para proyecciones.
- **FR-034:** graficar combustible/distancia, curva del medidor, consumo, costos y proyección contra realidad.
- **FR-035:** detectar valores anómalos sin eliminarlos automáticamente.

### Historial, respaldo y soporte

- **FR-036:** buscar, filtrar, editar y eliminar eventos con recalculo inmediato.
- **FR-037:** exportar reportes CSV/PDF con origen real/estimado visible.
- **FR-038:** exportar respaldo versionado con imágenes opcionales, manifiesto y hashes.
- **FR-039:** validar una restauración antes de aplicarla transaccionalmente.
- **FR-040:** detectar duplicados por UUID y hash.
- **FR-041:** ofrecer diagnóstico local exportable sin datos sensibles por defecto.
- **FR-042:** soportar recordatorios locales configurables.

### Preparación v2.1

- **FR-043:** separar dominio y repositorios de SwiftData y del proveedor remoto.
- **FR-044:** definir operaciones idempotentes y resolución de conflictos por campo.
- **FR-045:** sincronizar en v2.1 solo datos estructurados mínimos; nunca imágenes.
- **FR-046:** usar un proyecto Supabase independiente; la base existente queda prohibida.

## 7. Requisitos no funcionales

- **NFR-001 Privacidad:** cero tráfico de imágenes y cero credenciales cloud en v2.
- **NFR-002 Disponibilidad:** todos los recorridos principales funcionan sin internet.
- **NFR-003 Integridad:** ningún fallo parcial confirma un guardado o importación.
- **NFR-004 Rendimiento:** precarga inicial objetivo ≤5 s en un iPhone soportado para un conjunto de hasta tres imágenes típicas; progreso visible si excede 1 s.
- **NFR-005 Almacenamiento local:** presupuesto esperado de imágenes ≤250 MB/año/usuario.
- **NFR-006 Almacenamiento cloud futuro:** presupuesto de datos estructurados ≤5 MB/año/usuario.
- **NFR-007 Accesibilidad:** recorridos críticos utilizables con VoiceOver y Dynamic Type XXL.
- **NFR-008 Localización:** español e inglés sin literales críticos fuera del catálogo.
- **NFR-009 Compatibilidad:** migración desde la versión actual sin pérdida de registros o imágenes.
- **NFR-010 Calidad:** cobertura de CartrackCore ≥90% y todos los gates obligatorios verdes.
- **NFR-011 Observabilidad:** errores reproducibles mediante diagnóstico local redactado.
- **NFR-012 Seguridad:** permisos mínimos, archivos protegidos y secretos ausentes del repositorio.
- **NFR-013 Mantenibilidad:** reglas de dominio probables sin UI, red o SwiftData real.
- **NFR-014 Eficiencia:** no persistir cachés, gráficas, observaciones completas de Vision ni métricas recalculables.
- **NFR-015 Reproducibilidad:** el commit candidato se prueba y publica sin cambios posteriores.

## 8. Reglas de confianza

- Alta: el valor pasa OCR, rango, continuidad y validaciones cruzadas; se precarga normalmente.
- Media: existe candidato plausible con una validación débil o una única fuente; se precarga resaltado.
- Baja: contradicción, OCR incompleto o calidad insuficiente; no se selecciona automáticamente.
- Crítica: el valor contradice una invariante; guardar queda bloqueado hasta resolverlo.

Los umbrales concretos pertenecen al contrato de captura y deben calibrarse con fixtures, no con un único archivo.

## 9. Casos límite obligatorios

- Odómetro menor que el anterior.
- Trip reiniciado.
- Factura sin uno de monto/precio/volumen.
- Separadores decimales o de miles ambiguos.
- Dos imágenes con valores distintos.
- Fotografía rotada, oscura, borrosa o parcial.
- Nivel analógico entre marcas.
- Carga parcial seguida por carga completa.
- Evento editado que cambia un tanque cerrado.
- Eliminación con archivo local ausente.
- Falta de espacio durante optimización o respaldo.
- Cierre de la app durante OCR o importación.
- Migración interrumpida.
- Restauración con UUID duplicados.
- Cambio de dispositivo sin fotografías cloud.

## 10. Criterios de éxito

- **SC-001:** 100% de los fixtures digitales prioritarios legibles producen odómetro/trip dentro de tolerancia o una recuperación segura explícita; nunca un valor incorrecto de alta confianza.
- **SC-002:** 100% de los fixtures de factura prioritarios extraen los campos declarados o identifican con precisión los ausentes.
- **SC-003:** 100% de los recorridos P0 pasan en simulador y en al menos un iPhone físico.
- **SC-004:** una sesión interrumpida puede continuar sin repetir fotografías válidas.
- **SC-005:** migración y restauración preservan conteos, UUID, relaciones, valores e imágenes locales.
- **SC-006:** ninguna imagen se transmite durante pruebas de red de v2.
- **SC-007:** crecimiento cloud estructurado medido ≤5 MB por usuario/año al volumen esperado.
- **SC-008:** crecimiento local de evidencia optimizada medido ≤250 MB por usuario/año al volumen esperado.
- **SC-009:** cobertura del núcleo ≥90%, cero fallos en gates públicos y privados, y cero crashes críticos conocidos.
- **SC-010:** cada requisito tiene estado y evidencia en `acceptance-matrix.md`.

## 11. Definición de terminado

Cartrack v2 está terminada solo cuando todos los requisitos P0 y P1 aparecen `VERIFIED`, la matriz de aceptación no contiene bloqueos de lanzamiento, la migración se prueba con una copia representativa, el gate privado de imágenes pasa y `release-checklist.md` queda firmado contra el mismo commit que se sube al remoto.
