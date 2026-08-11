# Play Idea - Constructor de Módulos

Versión 0.5.0.

Plugin independiente que construye una cuadrícula tridimensional a partir de
una cantidad de módulos de ancho, largo y alto.

## Dependencias

- Play Idea - Creador de Tubos 0.2.0 o posterior.
- Play Idea - Biblioteca de Conectores 0.8.0 o posterior.

El constructor usa las funciones públicas y los metadatos de esos plugins, pero
no modifica sus archivos.

## Primera versión

- Ventana HTML con módulos X, Y y Z.
- Medidas independientes para ancho, largo y alto.
- Valor inicial de 1.1684 m en los tres ejes.
- Tubos estructurales Ø38.1 × 1.5 mm.
- Conector 21 en las esquinas de tres direcciones.
- Conector 40 en nodos con cuatro o más direcciones.
- Tubos compartidos entre módulos contiguos.
- Grupo general con metadatos y cantidades.

## Versión 0.2.0

- Todo poste que toca el suelo comienza con un conector 61.
- Se elimina la parrilla horizontal del nivel cero.
- Las parrillas horizontales comienzan sobre la primera planta.
- Esquinas del perímetro: conector 21.
- Bordes con tres direcciones horizontales: conector 35 orientado hacia dentro.
- Centros con cuatro direcciones horizontales: conector 40.
- No se usa un conector 40 en el perímetro cuando dejaría ramales laterales
  sin tubo.

## Versión 0.3.0

- Recupera la parrilla horizontal del nivel cero.
- Cada apoyo inferior lleva primero un conector 61.
- El poste vertical entra en el 61.
- Sobre el mismo poste se coloca, a 50.8 mm, el conector 21, 35 o 40 que
  corresponde a su posición en la parrilla.
- Los conectores 61 y los conectores de la parrilla se cuentan por separado.

## Versión 0.4.0

- Normaliza el origen desplazado del conector 21 usando su nodo geométrico
  real `(radio, 0, radio)`.
- Coloca todas las parrillas sobre un mismo plano matemático.
- La primera parrilla queda a 138.45 mm del piso para no invadir el receptor
  61 con el cuerpo inferior del conector 21.
- Sustituye los tramos verticales desfasados por un poste continuo en cada
  columna.
- Recalcula cantidades y longitud total de tubo según los postes continuos.

## Versión 0.5.0

- Incorpora internamente el conector 26 sin modificar la biblioteca de
  conectores.
- El 26 tiene un manguito central pasante y dos receptores horizontales
  opuestos a 180 grados.
- Una unión con dos direcciones horizontales opuestas usa 26.
- Una esquina con dos direcciones horizontales a 90 grados conserva el 21.
- El 26 incluye tres tuercas, tres opresores, desglose de materiales y costo.

## Supuesto pendiente de calibración

La medida capturada se interpreta inicialmente como distancia entre nodos y
también como largo físico del tubo. Debe medirse cuánto penetra el tubo dentro
del receptor para calcular posteriormente los largos de corte exactos.
