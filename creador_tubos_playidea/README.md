# Play Idea - Creador de Tubos

Extensión de SketchUp para crear tubos huecos paramétricos.

Versión 0.2.0.

## Uso

1. Ejecutar **Extensiones > Play Idea - Creador de Tubos > Crear tubo paramétrico**.
2. Capturar largo, diámetro exterior, cédula, código y color.
3. Hacer clic en el punto inicial.
4. Hacer un segundo clic para indicar la dirección.

El segundo punto sólo define la dirección; el largo final es el capturado en el
formulario.

## Cálculo

La cédula selecciona automáticamente el espesor correspondiente al diámetro
exterior dentro del catálogo incluido. El usuario no captura el espesor por
separado. El diámetro interior se calcula como:

`diámetro interior = diámetro exterior - (2 × espesor)`

Si una combinación no existe, el tubo no se genera hasta que la medida sea
agregada al catálogo.

## Medidas estándar y libres

La ventana HTML permite elegir una medida estándar o capturar una longitud
libre en metros. La primera medida estándar registrada es 1.1684 m. Una medida
libre puede ser, por ejemplo, 0.15 m.

El perfil estructural Play Idea predeterminado es Ø38.1 × 1.5 mm. Su diámetro
exterior es menor que los 41.94 mm interiores de los receptores, por lo que
puede entrar en ellos con 3.84 mm de holgura diametral. La compatibilidad se
muestra antes de crear el tubo y también se guarda como metadato.
