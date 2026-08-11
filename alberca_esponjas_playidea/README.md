# Play Idea - Alberca de Esponjas

Extensión de SketchUp para llenar un volumen con cubos de esponja en
posición y rotación aleatorias, simulando una alberca de esponjas.

Versión 0.1.0.

## Uso

1. Ejecutar **Extensiones > Play Idea - Alberca de Esponjas > Crear alberca de esponjas**.
2. Capturar ancho, alto y largo del volumen a llenar, el tamaño de cubo,
   el color (mezcla aleatoria de la paleta Play Idea o un solo color) y
   el código.
3. Hacer clic en el punto donde va la esquina inferior de la alberca.

## Cómo se llena el volumen

El tamaño de cubo elegido (arista) define una cuadrícula base que cubre
todo el volumen de punta a punta. Cada cubo se desplaza al azar hasta un
35% de su propio tamaño respecto al centro de su celda, y se rota al
azar en cualquier eje y ángulo -no solo en incrementos de 30°/45°-, así
que los cubos vecinos se traslapan entre sí en vez de quedar alineados
en filas perfectas.

Esta medida (cubo de 150mm de arista) y el estilo de traslape se
confirmaron analizando un ejemplo real armado a mano por el usuario con
`scripts/inspect_geometry.rb`: los 12 cubos de ese ejemplo resultaron
tener EXACTAMENTE la misma arista (150mm), verificado con la fórmula de
bounding box de un cubo rotado, aunque sus cajas delimitadoras se veían
muy distintas por estar rotados cada uno de forma distinta.

## Límite de seguridad

Si la combinación de volumen y tamaño de cubo generaría más de 4000
cubos, el plugin pide agrandar el cubo o reducir el volumen en vez de
intentarlo -para no crear un archivo excesivamente pesado o lento-.
