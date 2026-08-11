# Geometría de SketchUp

## Índice

- Unidades
- Transformaciones y ejes
- Caras y sólidos
- Definiciones e instancias
- Colisiones y medición
- Rendimiento

## Unidades

SketchUp almacena longitudes internamente en pulgadas. Tratar las variables con sufijo `_mm` como números en milímetros y convertirlas al cruzar la frontera de la API:

```ruby
Geom::Point3d.new(x_mm.mm, y_mm.mm, z_mm.mm)
entities.add_circle(center, normal, radius_mm.mm, segments)
```

No mezclar un `Float` en mm con coordenadas internas. Un `z_mm` crudo se interpreta como pulgadas y produce geometría aproximadamente 25.4 veces mayor.

## Transformaciones y ejes

Para orientar una pieza a lo largo de `direction`:

```ruby
local_x = direction.normalize
reference = local_x.parallel?(up_hint) ? Y_AXIS : up_hint
local_y = local_x.cross(reference).normalize
local_z = local_x.cross(local_y).normalize
transform = Geom::Transformation.axes(origin, local_x, local_y, local_z)
```

Normalizar todos los ejes. Un vector usado como eje conserva su magnitud y puede estirar el componente. Comparar piezas anidadas en coordenadas de mundo, acumulando transformaciones de ancestros; no comparar directamente bounds locales de padres distintos.

## Caras y sólidos

- Para tubos huecos confiables, construir paredes exterior/interior por segmentos y cerrar con anillos explícitos. No depender de que dos círculos concéntricos produzcan automáticamente el hueco esperado.
- Un cuadrángulo de pared con dos pares verticales puede ser coplanar; una cinta helicoidal generalmente no lo es.
- Triangular cada tramo de superficies con giro, torsión o bordes que rotan entre muestras.
- Revisar orientación de caras y aplicar material a frente y reverso cuando el render lo requiera.
- Verificar que tapas, domos y losas anulares no cierren perforaciones centrales.

## Definiciones e instancias

- Cachear definiciones para geometría repetida y colocar instancias transformadas.
- Incluir en la clave de caché todas las dimensiones que cambian la geometría.
- Nombrar tanto definición como instancia de acuerdo con los contratos del cotizador y auditor.
- Al reemplazar una transformación, preservar la intención completa de traslación, orientación y escala.

## Colisiones y medición

- No decidir tangencia o colisión solo por una captura en perspectiva.
- Para ductos curvos, medir contra el recorrido completo, no solo contra el punto medio o azimut.
- Muestrear rectos y codos y calcular distancia punto-segmento/segmento-segmento incluyendo radios y margen de seguridad.
- Validar cajas, distancias, tangencias, huecos, extremos y altura final mediante números.
- Si un diseño con piezas de radio/ángulo fijo no puede satisfacer una alineación exacta, explicar la limitación; no ocultarla con una búsqueda discreta que cambie la altura real.

## Rendimiento

SketchUp se degrada con miles de grupos o caras duplicadas. Para discos, puntadas, tornillos y piezas repetidas, preferir una definición y múltiples instancias. Mantener suficientes segmentos para la forma visual sin multiplicarlos innecesariamente.
