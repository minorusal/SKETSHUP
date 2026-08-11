# Pruebas, diagnóstico y empaquetado

## Índice

- Orden de validación
- Diagnóstico fuera de SketchUp
- Compatibilidad Ruby
- Prueba dentro de SketchUp
- Empaquetado RBZ

## Orden de validación

1. Ejecutar `ruby -c` en cada Ruby modificado.
2. Buscar llamadas, constantes y contratos afectados con `rg`.
3. Probar fórmulas puras y rangos con un harness pequeño cuando haya cambios geométricos.
4. Inspeccionar el contenido final del RBZ si se empaqueta.
5. Declarar qué requiere comprobación visual en SketchUp real.

## Diagnóstico fuera de SketchUp

Usar mocks mínimos de `Geom::Point3d`, `Vector3d`, `Transformation`, `Numeric#mm` y `Numeric#degrees` para ejecutar fórmulas sin SketchUp. Hacer que `Numeric#mm` convierta a pulgadas (`self / 25.4`) para detectar coordenadas crudas.

Los mocks simples pueden validar rangos, conteos y transformaciones, pero no garantizan planaridad ni solidez. Triangular geometría torcida aunque un mock de `add_face` la acepte.

`scripts/inspect_geometry.rb` permite obtener bounds locales y mundiales, transformaciones y separaciones desde SketchUp. Pedir al usuario que lo ejecute con la pieza seleccionada cuando las capturas no basten. Comparar los datos reales contra el harness antes de confiar en la simulación.

## Compatibilidad Ruby

- Verificar la versión objetivo de Ruby de SketchUp y evitar APIs más modernas sin comprobarlas.
- Este proyecto ha usado Ruby 2.6 para pruebas locales; `Array#filter_map` no está disponible allí. Preferir construcciones compatibles como `select` + `map` cuando no haya certeza.
- `ruby -c` confirma sintaxis, no disponibilidad de métodos ni comportamiento de la API SketchUp.

## Prueba dentro de SketchUp

SketchUp no recarga automáticamente el Ruby de un plugin ya cargado. Después de reinstalar un RBZ, cerrar y abrir SketchUp por completo antes de concluir que un cambio no funcionó. Los scripts sueltos cargados con `load` sí se reejecutan.

## Empaquetado RBZ

Un RBZ es un ZIP renombrado. Crear el paquete desde la raíz del repositorio, incluyendo loader y carpeta del plugin sin carpeta contenedora:

```bash
zip -X nombre_vX.Y.Z.rbz.new nombre.rb nombre/main.rb nombre/selector.html
mv nombre_vX.Y.Z.rbz.new nombre_vX.Y.Z.rbz
unzip -l nombre_vX.Y.Z.rbz
```

Adaptar la lista a todos los archivos reales del plugin. Antes de empaquetar:

- Leer la versión del loader.
- Confirmar que el nombre del RBZ coincide con esa versión.
- Incluir subdirectorios requeridos, por ejemplo `constructor_modulos_playidea/tobogan/`.
- Verificar listado, tamaños y fechas del ZIP.
- No asumir que el RBZ más nuevo contiene el `main.rb` actual.
