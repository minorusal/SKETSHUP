# Tobogán e integración con la estructura

## Índice

- Dos niveles de implementación
- Ensamble y orientación
- Soportes, ligas y colisiones
- Altura y salida
- Recubrimiento, color y materiales
- Entrada de la estructura

## Dos niveles de implementación

Los prototipos viven en `scripts/tobogan*_playidea.rb` y archivos auxiliares. La implementación instalable vive en `constructor_modulos_playidea/tobogan/`, principalmente `builder.rb`, `codo_90.rb`, `recto.rb`, `salida.rb`, `solera.rb`, `aro_entrada.rb` y `tornilleria.rb`.

No asumir que un script y el plugin están sincronizados. Compararlos explícitamente. Cuando el usuario declare una variante experimental como correcta, conservarla y experimentar en una copia nueva; no sobrescribir la referencia validada.

## Ensamble y orientación

- Construir el recorrido a partir de segmentos reales y conservar esos segmentos en el resultado para cálculos posteriores.
- Usar Gram-Schmidt y ejes normalizados al orientar codos, rectos, salida, soleras y brazos.
- Orientar conectores reasignando una transformación completa; la función que los crea puede limitarse a trasladarlos.
- Revisar todos los brazos y uniones después de cambiar una transformación, no solamente el elemento que motivó el ajuste.
- Tornillería y demás piezas cotizables deben usar `instance.name = CODE`.

## Soportes, ligas y colisiones

- Apuntar soportes al ducto real usando puntos sobre los segmentos, no a centros aproximados de la espiral.
- Evaluar codos y tramos rectos completos. Un chequeo basado solo en azimut o punto medio deja pasar colisiones cerca de los extremos.
- Elegir alturas de ligas mediante distancia geométrica al ducto, incluyendo radio exterior y margen de seguridad.
- Agregar más ligas cuando aumente la altura, distribuyéndolas en el rango útil y buscando una altura libre próxima a cada objetivo.
- El soporte del recto debe conservar una pata cercana a 200 mm cuando esa constante siga vigente en el código; derivar la altura del tobogán desde la estructura y la geometría, no desde un dato incompatible.

## Altura y salida

La altura al suelo es una restricción física. No ajustar el número de codos o el giro hasta obtener múltiplos de 360° si eso altera la altura por metros. Con codos de radio y ángulo fijos puede no existir una solución exacta de alineación salida↔entrada. Explicar la limitación o introducir una pieza de ajuste solo con autorización.

## Recubrimiento, color y materiales

- Recubrir poste, brazos y ligas estructurales mediante el flujo genérico de tubos `TUB-`.
- Incluir una longitud decimal real en el nombre si `pad_existing_tubes` la extrae mediante regex.
- No recubrir como foam las piezas de fibra de vidrio del ducto.
- Los modos de color del tobogán pueden ser mono, bicolor o aleatorio. Seleccionar color por pieza mediante un proc/selector estable.
- Usar materiales propios para fibra de vidrio, separados de foam y vinil aunque el hex coincida.

## Entrada de la estructura

La entrada sin malla es independiente del tobogán. El selector manual identifica una celda de orilla en nivel cero y `place_nets` omite exactamente ese paño. Mantener estados independientes para torre, tobogán y entrada; al activar uno, convertirlo en el objetivo del siguiente clic. No ofrecer esta selección en un diálogo sin canvas.
