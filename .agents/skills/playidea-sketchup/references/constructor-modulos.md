# Constructor de módulos: contrato central

## Autoridad y alcance

Leer siempre el loader, `main.rb`, los HTML y el README actuales antes de editar. Esta referencia preserva las reglas confirmadas, pero el código vigente es la fuente de verdad. La versión del loader al redactar esta referencia es `0.30.1`; verificarla de nuevo, no asumirla.

El Constructor orquesta geometría ya validada. Depende de `creador_tubos_playidea/main` y `conectores_playidea/main`; no debe copiar esas implementaciones ni empaquetarlas en su RBZ. No modificar esos plugins desde una tarea del Constructor sin autorización explícita.

`constructor_imagen_playidea` y futuros generadores deben tratar al Constructor como motor central: transformar su análisis en parámetros del Constructor y llamar una fachada de construcción compartida. No duplicar el orden de ensamblaje ni mantener una segunda versión de sus reglas.

## Carga segura

- El loader `constructor_modulos_playidea.rb` define `EXTENSION` y registra la extensión; `main.rb` usa esa constante al crear menú y mensajes.
- Una integración instalada no debe hacer `require 'constructor_modulos_playidea/main'` durante su propio arranque. Primero cargar el loader con `require 'constructor_modulos_playidea'` y comprobar disponibilidad cuando el usuario solicite generar geometría. La carga directa temprana de `main.rb` puede producir constantes duplicadas o `EXTENSION` ausente.
- Verificar `dependencies_available?` y las funciones públicas requeridas antes de construir.
- SketchUp no recarga Ruby al reinstalar un RBZ en la misma sesión: cerrar y abrir SketchUp por completo.

## Convenciones dimensionales

- Módulo interno estándar: `DEFAULT_SPACING_M = 1.1684`, es decir, `1168.4 mm` entre nodos. Es la referencia de escala para reconstrucción desde imágenes.
- X, Y y Z pueden tener separaciones escalares o arreglos por tramo. Usar `axis_column_width_mm`, `axis_cumulative_mm`, `axis_total_mm`, `spacing_z_length` y `grid_level_z`; no multiplicar índices por una constante si existen medios módulos o alturas distintas.
- Medio módulo X/Y agrega un tramo final de la mitad del módulo normal y aumenta el conteo de ese eje. No existe medio módulo Z.
- La unidad interna de SketchUp es pulgada. Mantener cálculos en mm y convertir con `.mm` solo al cruzar a `Geom`/SketchUp.
- La parrilla inferior usa `BOTTOM_GRID_HEIGHT_MM`; el último nivel tiene el ajuste de `RECEIVER_RADIUS_MM`. Tubos y conectores deben obtener Z mediante el mismo `grid_level_z` para no separarse.

## Estructura y conectores

- `create_module(params, origin)` crea la cuadrícula estructural y sus atributos. Debe usar las funciones públicas de tubos y conectores existentes.
- Los tubos horizontales no van simplemente de nodo a nodo. Cada extremo usa la boca real del receptor: `x_mouth_offset_mm` y `y_mouth_offset_mm`. El papel Azul/Verde y el nivel pueden cambiar el largo y origen de cada tubo.
- No reemplazar transformaciones medidas por una fórmula “más limpia” sin verificación numérica. Tras mover un conector multibrazo, comprobar cada brazo contra su tubo correspondiente en coordenadas de mundo.
- Mantener códigos, nombres de instancia y diccionarios de atributos. El auditor, recubrimiento y cotizador dependen de ellos.
- Cachear definiciones por todas las dimensiones relevantes. Evitar repetir caras cuando bastan instancias.

## Parámetros de ensamblaje

El contrato validado admite, como mínimo:

- `modules_x`, `modules_y`, `modules_z`
- `spacing_x_mm`, `spacing_y_mm`, `spacing_z_mm`
- `color`, `code`, `connectors`
- `padding` y selección de colores/costos del recubrimiento
- `solera`, `platform`, `net`
- `tower` con sus parámetros derivados
- `entrada` como `{ edge:, index: }` cuando hay malla
- `tobogan`, `tobogan_edge`, `tobogan_index`, altura y colores

No fabricar un hash parcial a ciegas. Reutilizar la validación/normalización del Constructor o introducir una API pública que produzca exactamente el mismo contrato para UI manual, automática y análisis de imágenes.

## Orden obligatorio de construcción

El flujo canónico está en `ModulePlacementTool` y debe preservarse en una fachada reutilizable:

1. Crear estructura mediante `create_module(params.merge(padding: false), origin)`.
2. Crear la torre triangular, si existe, y conservar su grupo y origen.
3. Si se pidió recubrimiento, aplicar `pad_existing_tubes` después de que estructura y torre existan; sumar longitudes y escribir el resumen. El recubrimiento reconoce tubos por su contrato `TUB-`.
4. Crear y colocar soleras cuadradas; añadir las triangulares de la torre.
5. Colocar plataformas rectangulares; añadir plataformas triangulares de torre.
6. Colocar mallas y respetar la abertura de entrada.
7. Adjuntar el tobogán con `Tobogan::Builder.attach`.
8. Si hay recubrimiento, recubrir también los tubos estructurales y ligas del tobogán, no sus piezas de fibra de vidrio.

Cada etapa debe usar `start_operation`/`commit_operation` con `abort_operation` al fallar, escribir conteos/atributos y devolver referencias útiles. No dejar geometría parcial silenciosa.

## Reglas por subsistema

### Recubrimiento

- Se coloca sobre tubos y conectores, con diámetro interior basado en el conector, no solamente en el tubo estructural.
- Se aplica después de estructura y torre para cubrir ambas. Colores usan la paleta estándar de ocho hex, no el sistema histórico aproximado del creador de tubos.
- Foam y cinchos tienen tags separados. Conservar el cálculo de tramos, cinchos, costos y resumen.

### Soleras y plataformas

- Las soleras usan posiciones y orientaciones medidas; no inventar diagonales u offsets. Las cuadradas siguen la antidiagonal confirmada.
- La plataforma rectangular manufacturada es de 1220 × 1220 mm y solo se coloca en celdas completas compatibles con el módulo estándar. No forzarla dentro de medios módulos.
- Las plataformas triangulares pertenecen a la torre y siguen su geometría propia.

### Mallas y entrada

- Las mallas se cortan al tamaño real de cada cara, por lo que sí soportan módulos completos, medios módulos y alturas variables.
- Actualmente cubren caras verticales en ambas orientaciones y el techo. `entrada` omite un único paño del nivel 0 en la orilla/celda elegida.
- Conservar textura transparente y marco; no reemplazar la red por un bloque opaco.

### Torre triangular

- Usar `tower_params_from_dialog`, `auto_tower_step_fit`, `auto_tower_step_heights` y las tablas de ejes/offsets actuales.
- Las orientaciones e inserciones provienen de mediciones reales. No derivarlas nuevamente solo por signos de vectores.
- Generar tubos, CON-12, CON-21, CON-10, soleras y plataformas según los métodos del Constructor; evitar duplicar conectores donde un escalón coincide con un nivel real.

### Tobogán

- Está integrado dentro del Constructor y su `Builder` es la única autoridad para componer codos, rectos, salida, aro, solera, tornillería, poste, brazos y ligas.
- No sustituirlo por una rampa o bloque provisional cuando se solicite geometría final. Leer además `tobogan.md`.

## Integración desde imágenes

El análisis visual debe producir un plan editable y auditable antes de generar. La escala se ancla con 1168.4 mm, pero una imagen no determina por sí sola todas las profundidades, alturas, oclusiones ni selecciones de celdas. Marcar cada valor como detectado, derivado, confirmado por usuario o provisional.

Flujo esperado:

1. Fusionar vistas y resolver una topología métrica de zonas/celdas/niveles.
2. Convertir zonas rectangulares en tramos X/Y/Z del contrato del Constructor.
3. Resolver torre, entrada, tobogán y conexiones como selecciones explícitas de celda/orilla.
4. Mostrar el plan editable y validar colisiones/adyacencias.
5. Pasar el contrato completo a una fachada compartida del Constructor.
6. Usar bloques de marcador solo para subsistemas todavía no implementados y etiquetarlos claramente como provisionales; nunca presentarlos como juego terminado.

### Aprendizaje del detector

- No confundir coincidencias ORB generales con correspondencias de postes. Las primeras solo califican pares de vistas; las segundas necesitan identidad compartida (`P1`, `P2`, etc.).
- Guardar localmente cada corrección confirmada como ejemplo: imágenes originales, dimensiones de análisis, punta/base de cada poste, vistas ancla y correspondencias.
- Mantener coordenadas en el sistema de la imagen de análisis e incluir sus dimensiones para poder normalizarlas durante entrenamiento.
- Nunca entrenar con sugerencias automáticas sin confirmar. El dataset debe contener únicamente postes aceptados, agregados o corregidos por el usuario.
- Permitir guardar ejemplos sin cuatro correspondencias: sirven para entrenar detección de postes. Clasificarlos como `post_detection`; reservar `multiview_geometry` para ejemplos con al menos cuatro parejas.
- Empezar aprendiendo una sola clase: poste estructural vertical. Agregar tubos horizontales, conectores y accesorios como clases separadas después de validar esta primera clase.
- Preferir generar ejemplos sintéticos desde modelos SketchUp conocidos, proyectando sus tubos con la cámara, para ampliar el dataset sin etiquetado manual repetitivo.

## Verificación mínima

- `ruby -c` en loaders y archivos Ruby modificados.
- Prueba con mocks para unidades, transformaciones y contrato de parámetros.
- Verificar coordenadas de mundo con `scripts/inspect_geometry.rb` cuando haya un problema de embone.
- Revisar una estructura mínima, medios módulos, alturas variables, torre, entrada, mallas y tobogán.
- Confirmar nombres/atributos y que las operaciones puedan deshacerse limpiamente.
- Empaquetar únicamente loader y carpeta del plugin correspondiente; inspeccionar el RBZ.
