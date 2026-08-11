# Play Idea - Biblioteca de Conectores

Versión 0.8.0.

## Uso

1. Abrir **Extensiones > Play Idea - Conectores > Insertar conector**.
2. Elegir el número y el color.
3. Hacer clic en el modelo para colocarlo.
4. Usar las herramientas normales de SketchUp para moverlo o rotarlo.

Al insertarlo se captura el material, la medida del herraje y los costos
unitarios de cada insumo y operación. Para consultar posteriormente la
información, seleccionar el componente y ejecutar **Ver ficha del conector
seleccionado**.

## Biblioteca inicial

- 10: T sencilla a 90 grados.
- 12: T inclinada a 45 grados.
- 19: conector lateral de dos receptores.
- 21: T lateral de tres direcciones.
- 35: cruz con tres salidas laterales.
- 40: paso central continuo con cuatro salidas horizontales a 90 grados.
- 61: receptor con placa base.
- COPLE: unión recta de cuatro pulgadas con dos opresores.

Los cuerpos se generan con dimensiones de referencia para receptor nominal de
1 1/2 pulgadas cédula 30: 48.3 mm exteriores, 3.18 mm de pared y 41.94 mm
interiores. Las tuercas, opresores, placa y soldaduras deben calibrarse contra
las piezas reales antes de usar los modelos para fabricación.

## Metadatos

- Código y tipo de conector.
- Costo unitario de inversión en MXN.
- Material y acabado.
- Cortes y longitud total de tubo receptor.
- Cédula, diámetros y espesor calculado.
- Cantidad y medida de tuercas.
- Cantidad y medida de opresores Allen.
- Presencia y dimensiones de placa base.
- Lista de materiales serializada para futuras exportaciones.
- Precio proporcional del tubo a partir de una barra completa de 6 m.
- Mano de obra de corte y soldadura.
- Consumibles de soldadura, electricidad, acabado y otros insumos.
- Desglose completo con cantidad, costo unitario y subtotal.

La versión 0.3.0 también corrige los ramales para que comiencen en la superficie
del cuerpo principal y representa los opresores retraídos, sin bloquear el paso
interior antes de insertar el tubo.

La versión 0.3.1 incorpora costos aproximados predeterminados en MXN. Todos los
valores pueden editarse y SketchUp recuerda los últimos importes utilizados.

La versión 0.3.2 corrige el conector 12: el paso recto y el receptor diagonal de
45 grados quedan coplanares para construir bastidores y refuerzos triangulares.

La versión 0.3.3 desplaza el receptor diagonal considerando el radio de ambos
tubos, evitando que su pared invada el paso libre del receptor horizontal.

La versión 0.3.4 sustituye la separación tangencial por un corte oblicuo real de
45 grados. La cara plana resultante se apoya bajo el receptor horizontal para
representar la unión soldada sin bloquear su paso interior.

La versión 0.3.5 inició la corrección del conector 19.

La versión 0.3.6 coloca el extremo del receptor horizontal exactamente sobre el
eje del vertical. Ambos quedan unidos a 90 grados con media sección de traslape,
mientras la otra mitad del paso vertical permanece libre.

La versión 0.3.7 ajustó la orientación preliminar del conector 19.

La versión 0.3.8 reproduce la geometría confirmada sin encimar los tubos.

La versión 0.3.9 fija como especificación definitiva del conector 19 el tercer
diagrama aprobado: contacto superficial de media sección, base vertical en D/2
y ningún volumen compartido.

La versión 0.4.0 corrige el conector 21 según el diagrama aprobado: principal de
2.5 pulgadas hacia abajo, salida azul de 2 pulgadas hacia la izquierda y salida
verde de 2 pulgadas hacia el fondo. Los tres ejes se unen en un nodo y forman
90 grados entre sí.

La versión 0.4.1 corrige la construcción física del conector 21 según el modelo
manual: los ejes ya no coinciden en el centro. Las dos salidas horizontales se
tocan externamente formando la esquina y el principal vertical se coloca debajo,
sin obstruir ni encimar los pasos interiores.

La versión 0.4.2 estabiliza la creación del conector 61 eliminando la operación
de perforación coplanar que podía fallar en algunas versiones de SketchUp. La
placa se crea como un sólido simple.

La versión 0.4.3 corrige el conector 61 con una placa circular Ø90 × 6 mm. El
receptor queda centrado y comienza directamente sobre la cara superior de la
placa, sin separación.

La versión 0.5.0 incorpora el conector 40: un manguito central vertical abierto
por arriba y por abajo, para que el tubo estructural lo atraviese completamente,
y cuatro receptores horizontales soldados alrededor a intervalos de 90 grados.
Los cuatro ramales terminan en la pared exterior y no obstruyen el paso central.

La versión 0.5.1 coloca la tuerca y el opresor del manguito central del conector
40 en su zona superior libre, evitando que queden ocultos entre los cuatro
ramales horizontales.

La versión 0.6.0 reemplaza el selector básico por un catálogo visual. Al cambiar
el código se muestra inmediatamente un esquema del conector, su nombre y la
disposición de sus receptores antes de insertarlo. SketchUp antiguos que no
incluyan HtmlDialog conservan automáticamente el selector clásico.

La versión 0.6.1 corrige la comunicación entre SketchUp y la ventana del
catálogo para que el listado de códigos se cargue correctamente al abrirla.

La versión 0.7.0 sustituye las vistas isométricas del catálogo por diagramas
técnicos planos vistos desde arriba. Las entradas abiertas, las tuercas y los
receptores verticales se distinguen mediante símbolos sencillos.

La versión 0.8.0 elimina los dibujos aproximados. Cada imagen del catálogo se
exporta directamente desde la misma definición 3D que el plugin utiliza para
crear el conector. En SketchUp 2023 o posterior se fuerza una cámara superior
ortográfica; las versiones anteriores usan la miniatura nativa del componente.
