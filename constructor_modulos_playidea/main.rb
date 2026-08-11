require 'sketchup.rb'
require 'json'
require 'zlib'
require 'creador_tubos_playidea/main'
require 'conectores_playidea/main'
# Piezas del tobogán -empacadas aquí, no como plugin aparte, ver la
# skill tobogan-completo-playidea para el porqué-. codo_90/salida
# reciben a recto/aro en su ceja; builder.rb necesita a las 6 ya
# cargadas -orden sin dependencias entre sí, solo builder depende de
# las demás-.
require_relative 'tobogan/codo_90'
require_relative 'tobogan/recto'
require_relative 'tobogan/salida'
require_relative 'tobogan/solera'
require_relative 'tobogan/aro_entrada'
require_relative 'tobogan/tornilleria'
require_relative 'tobogan/builder'

module PlayIdea
  module ConstructorModulos
    extend self

    DICTIONARY = 'playidea_modulo'.freeze
    DEFAULT_SPACING_M = 1.1684
    RECEIVER_RADIUS_MM = PlayIdea::Conectores::OUTSIDE_MM / 2.0
    # El 21 tiene 63.5 mm hacia abajo desde su origen y su eje horizontal se
    # encuentra un radio arriba. Esta cota evita que invada el receptor 61.
    BASE_GRID_HEIGHT_MM = 50.8 + 63.5 + RECEIVER_RADIUS_MM
    # Altura de la parrilla horizontal del NIVEL 0 (la que se apoya en el
    # receptor 61). A la altura normal (BASE_GRID_HEIGHT_MM) solo "Principal"
    # -asimétrico- alcanza a tocar el 61; a esta altura más baja es "Verde"
    # -centrada tras el fix de conectores_playidea- quien lo toca en cambio.
    # 50.8 = tope del receptor 61. 25.4 = mitad del largo de "Verde" (50.8mm).
    BOTTOM_GRID_HEIGHT_MM = 50.8 + 25.4
    # Cada extremo de un tubo horizontal necesita un desplazamiento propio
    # -no uno uniforme por eje- porque depende de qué papel (Azul o Verde)
    # sirve ese eje en el nodo de ese extremo -ver x_mouth_offset_mm/
    # y_mouth_offset_mm y middle_transform-:
    #
    #   - Azul (asimétrico, SIEMPRE sirve el eje en su propio extremo de
    #     fila/columna -nunca puede ser el eje interior/continuo justo en
    #     el extremo que se consulta-): la boca del receptor empieza un
    #     radio (24.15mm) ADELANTE del nodo, en la dirección del tubo. El
    #     tubo debe acortarse ese tanto para arrancar ya dentro del
    #     receptor. Aplica siempre a X; aplica a Y salvo en la única
    #     excepción de abajo.
    #   - Verde (centrado, solo puede darse en Y y solo en una esquina
    #     real -2 direcciones- de nivel k>=1, ver corner_transform): quedó
    #     CENTRADO sobre el nodo tras su fix en conectores_playidea (cubre
    #     de nodo-25.4 a nodo+25.4). El tubo debe ALARGARSE 25.4mm para
    #     atravesar todo el receptor y llegar a su pared trasera.
    #
    # Cada tubo se construye a su propia medida combinando el offset de SU
    # extremo de inicio con el de SU extremo final -pueden diferir, p.ej.
    # una esquina real de nivel 0 en un extremo y de nivel 1 en el otro no
    # aplica aquí porque ambos extremos comparten nivel k, pero esquina
    # real vs nodo intermedio sí puede diferir entre extremos-.
    VERDE_HALF_LENGTH_MM = 50.8 / 2.0
    STRUCTURAL_OUTSIDE_MM = 38.1
    STRUCTURAL_WALL_MM = 1.5
    STRUCTURAL_SCHEDULE = 'ESTRUCTURAL'.freeze

    # Recubrimiento de espuma (polyfoam) que forra toda la estructura -tubos
    # Y conectores, de ahí que el hueco interior sea el diámetro del
    # conector (48.3mm) y no el del tubo estructural (38.1mm)-. Cada tramo
    # (fila X, columna Y, poste Z) se recubre de PUNTA A PUNTA sin
    # detenerse en los nodos -a diferencia de los tubos estructurales, el
    # recubrimiento no necesita insertarse dentro de ningún receptor-.
    PADDING_OUTSIDE_MM = 85.0
    PADDING_INSIDE_MM = PlayIdea::Conectores::OUTSIDE_MM
    # El tubo crudo mide 2m; para llegar a la medida comercial de 2.4m se
    # pega un tramo de 40cm cortado de OTRO tubo crudo. El costo de
    # material por tubo terminado se aproxima como 1.2x el precio de un
    # tubo crudo -1 completo + una fracción de 0.4/2.0 de otro-, sin
    # modelar el aprovechamiento del sobrante de 1.6m del tubo donante.
    PADDING_STOCK_LENGTH_MM = 2000.0
    PADDING_FINISHED_LENGTH_MM = 2400.0
    PADDING_SPLICE_LENGTH_MM = 400.0
    PADDING_RAW_MATERIAL_FACTOR = 1 + (PADDING_SPLICE_LENGTH_MM / PADDING_STOCK_LENGTH_MM)
    PADDING_DEFAULT_COSTS = {
      'raw_tube' => 250.0,
      'perforation_labor' => 15.0,
      'electricity' => 3.0,
      'splice_labor' => 10.0,
      'wrap_material' => 40.0,
      'adhesive' => 20.0,
      'apply_labor' => 12.0,
      'weld_labor' => 8.0
    }.freeze

    # Catálogo ESTÁNDAR de colores -los mismos 8 hex que colorear_tubos_
    # playidea y alberca_pelotas_playidea usan, NO los nombres aproximados
    # de PlayIdea::CreadorTubos.apply_material (ese es un sistema de color
    # distinto y más viejo, con RGB a ojo). El recubrimiento y los cinchos
    # usan ESTE catálogo -confirmado por el usuario: "esos colores son
    # estándar de los que se usan"-, aplicado directo por hex -ver
    # `apply_hex_material`-, no por PlayIdea::CreadorTubos.
    STANDARD_COLOR_PALETTE = [
      { hex: 'FF0000', label: 'Rojo' },
      { hex: '84E311', label: 'Verde lima' },
      { hex: 'FFA400', label: 'Naranja' },
      { hex: '039CD4', label: 'Azul' },
      { hex: 'FFFF1E', label: 'Amarillo' },
      { hex: '11D9B4', label: 'Turquesa' },
      { hex: 'D911CB', label: 'Magenta' },
      { hex: '6E247D', label: 'Morado' }
    ].freeze

    # Cinchos de plástico que fijan el recubrimiento a la estructura -ficha
    # real: 7.6 x 370mm (ancho x largo). El largo (370mm) solo importa para
    # confirmar que alcanza a cerrar alrededor del recubrimiento -su
    # circunferencia es π×85≈267mm, sobra de sobra-, no afecta la
    # geometría del anillo. El GROSOR no viene en la ficha -solo ancho y
    # largo-, así que CABLE_TIE_THICKNESS_MM es un estimado -típico de un
    # cincho de nylon de este tamaño-, no medido.
    CABLE_TIE_WIDTH_MM = 7.6
    CABLE_TIE_THICKNESS_MM = 1.3
    CABLE_TIE_SPACING_MM = 150.0

    # Tags -Sketchup::Layer en la API- para poder ocultar/mostrar el
    # protector de esponja y los cinchos por separado desde el panel de
    # Tags, sin tocar los tubos estructurales -esos se quedan sin tag,
    # nadie pidió poder ocultarlos-.
    FOAM_TAG_NAME = 'Play Idea - Protector foam'.freeze
    CABLE_TIE_TAG_NAME = 'Play Idea - Cinchos'.freeze

    # Placa de solera de 1 pulgada -fija con 2 autorroscantes #14 x 1 1/2"
    # self-drilling apuntando hacia abajo hacia la estructura, más 1 pija
    # de madera #8 al centro apuntando hacia arriba, para sujetar una
    # plataforma que se agrega después-. Ancho, largo y tornillos vienen
    # dados por el usuario; espesor y diámetros de perforación son
    # ESTIMADOS -no hay pieza física de la solera para medirlos-. El
    # offset/rotación de colocación en cada esquina viene de medir 8
    # piezas reales puestas a mano en una referencia real (2026-08-06):
    # cada cuadro usa la ANTI-diagonal -esquinas (i0+1,j0) y (i0,j0+1),
    # NO (i0,j0)-(i0+1,j0+1)-, cero excepciones en los 8 casos medidos.
    # La esquina de 90° de la torre solo se confirmó para escalones tipo
    # "sw" -ver `place_triangle_soleras`-.
    SOLERA_WIDTH_MM = 25.4
    SOLERA_LENGTH_MM = 200.0
    SOLERA_THICKNESS_MM = 3.175
    SOLERA_AUTORROSCANTE_HOLE_MM = 6.35
    SOLERA_PIJA_HOLE_MM = 4.2
    SOLERA_END_INSET_MM = 12.0
    SOLERA_AUTORROSCANTE_SHAFT_MM = 6.35
    SOLERA_AUTORROSCANTE_LENGTH_MM = 38.1
    SOLERA_AUTORROSCANTE_HEAD_MM = 11.0
    SOLERA_AUTORROSCANTE_HEAD_THICK_MM = 3.0
    SOLERA_PIJA_SHAFT_MM = 4.2
    SOLERA_PIJA_LENGTH_MM = 25.4
    SOLERA_PIJA_HEAD_MM = 8.0
    SOLERA_PIJA_HEAD_THICK_MM = 2.0

    # Rotación fija a 45° respecto a la cuadrícula -confirmada igual en
    # las esquinas de cuadro Y en las de 45° de la torre-.
    SOLERA_STANDARD_XAXIS = Geom::Vector3d.new(-0.7071, -0.7071, 0.0).freeze
    SOLERA_STANDARD_YAXIS = Geom::Vector3d.new(0.7071, -0.7071, 0.0).freeze
    # Rotación de la esquina de 90° de la torre -distinta a la de
    # arriba-, confirmada solo para escalones tipo "sw".
    SOLERA_RA_XAXIS = Geom::Vector3d.new(0.7071, -0.7071, 0.0).freeze
    SOLERA_RA_YAXIS = Geom::Vector3d.new(0.7071, 0.7071, 0.0).freeze

    # Offsets en mm, coordenadas de MUNDO, sumados directo al punto de
    # referencia -esquina de cuadrícula o esquina de celda de la torre-.
    SOLERA_SQUARE_OFFSET_1 = [-3.11, 141.9, 21.3].freeze   # esquina (i0+1,j0)
    SOLERA_SQUARE_OFFSET_2 = [128.44, 10.84, 21.3].freeze  # esquina (i0,j0+1)
    SOLERA_TRIANGLE_NEAR_SW = [128.44, -203.75, 21.3].freeze
    SOLERA_TRIANGLE_FAR_SW = [-212.35, 141.9, 21.3].freeze
    SOLERA_TRIANGLE_NEAR_NE = [-4.55, 364.49, 21.65].freeze
    SOLERA_TRIANGLE_FAR_NE = [336.24, 18.84, 21.65].freeze
    SOLERA_TRIANGLE_RA_SW = [-7.43, 123.94, 29.61].freeze

    # Plataforma de piso -triplay 15mm + esponja de 1" y 1/2" + forro de
    # vinil-, geometría probada primero como script suelto en
    # /Users/minorusal/Documents/SKETCHUP/scripts/plataforma_playidea.rb
    # antes de integrarla aquí. Solo existe en 1.22 x 1.22m por ahora, así
    # que únicamente se coloca en cuadros de módulo COMPLETO -nunca en
    # columnas/filas de medio módulo, más angostas de lo que necesita-, y
    # solo si el módulo de la estructura es -aprox- el estándar
    # (DEFAULT_SPACING_M), que es la medida para la que se calculó el
    # corte de las puntas -ver PLATFORM_CORNER_CHAMFER_MM-.
    PLATFORM_WIDTH_MM = 1220.0
    PLATFORM_DEPTH_MM = 1220.0
    PLATFORM_TRIPLAY_MM = 15.0
    PLATFORM_FOAM_1IN_MM = 25.4
    PLATFORM_FOAM_HALF_MM = 12.7
    PLATFORM_TOTAL_HEIGHT_MM = PLATFORM_TRIPLAY_MM + PLATFORM_FOAM_1IN_MM + PLATFORM_FOAM_HALF_MM
    PLATFORM_CODE = 'PLATAFORMA-122X122'.freeze

    # Las 4 puntas van cortadas -chaflán a 45°, medido desde la esquina
    # sobre cada lado- para que la plataforma quepa entre los postes de
    # la estructura sin chocar con el protector de esponja que los cubre
    # -85mm de diámetro, PADDING_OUTSIDE_MM, el más ancho en cada
    # esquina-. PROVISIONAL: pendiente de confirmar contra una estructura
    # real armada -ajusta este único número si sobra o falta espacio-.
    PLATFORM_CORNER_CHAMFER_MM = (PADDING_OUTSIDE_MM / 2.0 * Math.sqrt(2)).ceil

    # Tolerancia -en mm- para considerar un cuadro/estructura "de módulo
    # estándar" al comparar contra DEFAULT_SPACING_M*1000, por redondeo
    # metro->mm del diálogo.
    PLATFORM_MODULE_TOLERANCE_MM = 1.0

    # La plataforma se apoya ENCIMA del protector de esponja del poste,
    # no al centro del tubo de la parrilla -mismo Z que usan las
    # soleras-. PROVISIONAL: pendiente de confirmar contra una estructura
    # real armada.
    PLATFORM_Z_LIFT_MM = PADDING_OUTSIDE_MM / 2.0

    PLATFORM_WOOD_COLOR = Sketchup::Color.new(200, 170, 120).freeze
    PLATFORM_FOAM_COLOR = Sketchup::Color.new(230, 225, 210).freeze
    # El color de vinil de cada plataforma sale al azar de STANDARD_
    # COLOR_PALETTE -los mismos 8 colores reales que usan los
    # protectores de esponja-, uno independiente por plataforma -mismo
    # criterio que padding_color_selector en modo "aleatorio"-, ver
    # place_platforms/place_triangle_platforms.

    # Red de nylon de seguridad -paños con marco de redondo pulido en el
    # perímetro, amarrados a la estructura con cinchos-. Se coloca ANTES
    # del recubrimiento de esponja -confirmado con el usuario-, sobre
    # cualquier cara vertical de la cuadrícula -perpendicular a X o a Y-,
    # del tamaño real de esa cara (ancho de módulo x alto de nivel). La
    # geometría real -miles de hilos anudados- es imposible de modelar a
    # escala, así que se representa como una textura PNG generada aquí
    # mismo -hilo opaco, abertura transparente- sobre un solo panel
    # plano, igual que el script de prueba en
    # /Users/minorusal/Documents/SKETCHUP/scripts/red_nylon_playidea.rb.
    NET_ABERTURA_MM = 25.4 # 1 pulgada
    NET_CALIBRE_MM = 1.7   # grosor del hilo -calibre 18, redondo-
    NET_ROD_DIAMETER_MM = 4.8 # redondo pulido 3/16", el marco del perímetro

    NET_TILE_PX = 128
    NET_LINE_WIDTH_PX = (NET_TILE_PX * (NET_CALIBRE_MM / NET_ABERTURA_MM)).round.clamp(2, NET_TILE_PX / 4)
    NET_KNOT_RADIUS_PX = NET_LINE_WIDTH_PX * 1.4
    NET_CORD_COLOR = [15, 15, 15, 255].freeze
    NET_GAP_COLOR = [0, 0, 0, 0].freeze
    NET_ROD_COLOR = Sketchup::Color.new(180, 180, 185).freeze

    # Por ahora se coloca en TODA la cuadrícula -todas las caras
    # verticales posibles, en ambas orientaciones, en todos los niveles-
    # y el usuario la quita a mano donde no haga falta -confirmado con
    # el usuario, no hay lógica de "sólo perímetro" todavía-.

    # Torre de pisos triangulares: un tubo diagonal a 45° por escalón,
    # cruzando una sola celda de esquina a esquina, con un CON-12 en cada
    # extremo. TODOS los escalones usan la MISMA diagonal -sin alternar-;
    # una versión anterior alternaba (zigzag) por 4 ejemplos previos en
    # otras estructuras, pero se retiró tras analizar 5 ejemplos nuevos
    # (4 direcciones corregidas a mano por el usuario + el original del
    # plugin) sobre esta misma estructura (MOD-3X4X2): en los 4 corregidos,
    # los 3 escalones de cada torre -incluidos los que sí coinciden con un
    # nodo de la cuadrícula base- usan exactamente la misma diagonal, sin
    # excepción. Los escalones siguen espaciados 600mm entre sí, sin
    # importar el tamaño del módulo.
    #
    # DIRECCIÓN -4 opciones, una por esquina de la celda-: en vez de elegir
    # "cuál diagonal", el usuario elige qué ESQUINA de la celda (SO/SE/NE/
    # NO) sería el ángulo recto de un triángulo completo ahí -aunque este
    # plugin solo construye la hipotenusa (el tubo diagonal), no las 2
    # patas ni el conector de esquina, ver NOTA DE ALCANCE-. Esa esquina
    # determina sola las otras dos (sus vecinas, unidas por la diagonal que
    # SÍ se construye), verificado con exactitud contra los 4 ejemplos
    # corregidos: dado un orden fijo de esquinas alrededor de la celda
    # `ORDERED_CORNERS = [sw, nw, ne, se]`, si la esquina elegida es `c`,
    # la diagonal conecta `siguiente(c)` con `anterior(c)` en ese mismo
    # orden -confirmado exacto en los 4 casos (NO⇒SO-NE con inicio en NE,
    # SE⇒SO-NE con inicio en SO, NE⇒SE-NO con inicio en SE, SO⇒SE-NO con
    # inicio en NO-).
    TRIANGLE_STEP_SPACING_MM = 600.0
    # Altura mínima de arranque de la torre -el primer escalón no puede
    # coincidir con el nivel 0 -conector 61-, así que arranca en una
    # altura intermedia fija en vez de en 0. 500mm queda cómodo por
    # encima de BOTTOM_GRID_HEIGHT_MM y dentro del rango ideal de
    # separación entre escalones (ver TRIANGLE_STEP_SPACING_MM).
    TOWER_FIRST_STEP_HEIGHT_MM = 500.0
    # Qué tan cerca -en mm- tiene que estar la altura de un escalón de un
    # nivel real de la cuadrícula para tratarlo como "coincide" -y
    # saltarse el CON-21+patas de ese escalón-. Valor estimado, no medido
    # con datos reales todavía -no hay ninguna referencia real de un
    # escalón coincidiendo con un nivel-.
    GRID_LEVEL_COINCIDENCE_TOLERANCE_MM = 5.0
    # Cuánto se aleja el CON-12 diagonal de su propia esquina real -a lo
    # largo de la diagonal, hacia el otro extremo-, NO toda la celda ni
    # los demás conectores. Medido directo en una torre + cuadrícula real
    # que el usuario confirmó correcta -reporte_grupo_20260806_110850.txt,
    # 2 escalones, parseado con script en vez de a mano-: las 4 instancias
    # de CON-12 -2 por escalón, en los 2 escalones- dieron 104.2, 104.9,
    # 104.8 y 106.6mm, promedio 105.1mm. (Un intento anterior de 186mm,
    # basado en comparar contra una corrección a mano que resultó no ser
    # la buena, quedaba muy lejos de esta referencia confirmada -no se
    # usa-.)
    TRIANGLE_DIAGONAL_INSET_MM = 105.0
    # Cuánto se aleja el CON-21 -ángulo recto- de su propia esquina real,
    # hacia la esquina OPUESTA de la celda -la que no toca ni la
    # diagonal ni ninguna pata-. Viene de una sola medición real (con
    # comparar_grupos.rb, misma corrección que dio el número de arriba)
    # -34.65mm-, no de 4 como el CON-12; ojo si hace falta ajustarlo con
    # más muestras REALES -no calculadas-.
    TRIANGLE_RIGHT_ANGLE_INSET_MM = 34.65
    # Orden fijo de las 4 esquinas alrededor de la celda -ver DIRECCIÓN
    # arriba-; el vecino SIGUIENTE de una esquina en este orden es donde
    # arranca la diagonal (`near`), el ANTERIOR es donde termina (`far`).
    TRIANGLE_CORNER_ORDER = %i[sw nw ne se].freeze

    # Cuánto se mete el tubo -diagonal o pata- dentro de cada conector,
    # medido a lo largo del eje LOCAL de ese conector. `diagonal_connector_
    # mouth`/`right_angle_connector_mouth`/`leg_connector_mouth` usaban
    # RECEIVER_RADIUS_MM completo -24.15mm- en cada boca, pero midiendo el
    # largo REAL de los tubos en 4 torres hechas a mano -comparando la
    # distancia cruda entre conectores contra el largo real del tubo,
    # proyectado sobre sus propios ejes- ese inset resultó ser de ~11.3mm
    # por boca -la mitad de RECEIVER_RADIUS_MM-, consistente en el escalón
    # limpio de los 4 diseños y en los escalones tapados de 2 de los 4
    # -las otras 2 mediciones del escalón tapado inferior salieron muy
    # distintas entre sí, ~30mm, más parecido a ruido de construcción a
    # mano que a una regla real-. Con el inset completo (48.3mm totales
    # por tubo) el tubo calculado quedaba más corto que el hueco real entre
    # conectores, así que sobraba tubo y atravesaba la geometría del
    # conector en vez de detenerse en su boca.
    TRIANGLE_MOUTH_INSET_MM = RECEIVER_RADIUS_MM / 2.0

    # Orientación EXACTA del CON-12 -ejes local_x/local_y/local_z, para
    # `Geom::Transformation.axes`- por (ángulo recto elegido, papel
    # near/far), tomada DIRECTAMENTE de los 4 ejemplos corregidos por el
    # usuario -ya NO de una fórmula-. Se intentó primero una fórmula
    # basada solo en el signo de la dirección de la diagonal
    # (`diagonal_direction.x/y positivo o negativo`, la versión anterior
    # de `diagonal_connector_transform`) pero verificada numéricamente
    # contra los 4 archivos solo coincidía en 3 de los 8 casos reales -la
    # orientación correcta depende de CUÁL esquina y de su papel (near vs
    # far), no solo del signo de la dirección-. Como este plugin solo
    # construye exactamente estas 4 direcciones × 2 conectores cada una
    # -8 casos, ni uno más-, una tabla con los 8 valores reales es exacta
    # y no necesita ninguna fórmula.
    #
    # TRIÁNGULO COMPLETO en TODOS los escalones -diagonal + 2 patas, con un
    # CON-21 en el ángulo recto y un CON-10 en cada esquina vecina-. Esto NO
    # es integración con la cuadrícula base -verificado en los 4 ejemplos:
    # las alturas de esos escalones NO coinciden con ningún nivel real de
    # conectores de la estructura (CON-40/CON-35 de la cuadrícula base
    # existente)-, es simplemente que la torre "tapa" cada escalón con el
    # triángulo completo, flotando igual que la diagonal.
    #
    # Esto es una tabla de los 8 valores reales (4 ángulos rectos × pata
    # cercana/lejana) tomados de los 4 ejemplos, no una fórmula.
    TRIANGLE_CONNECTOR_21_AXES = {
      nw: [Y_AXIS.reverse, Z_AXIS.reverse, X_AXIS],
      se: [Y_AXIS.reverse, Z_AXIS.reverse, X_AXIS],
      ne: [X_AXIS, Z_AXIS.reverse, Y_AXIS],
      sw: [X_AXIS.reverse, Z_AXIS.reverse, Y_AXIS.reverse]
    }.freeze

    TRIANGLE_CONNECTOR_10_AXES = {
      nw: { near: [Z_AXIS, Y_AXIS.reverse, X_AXIS.reverse], far: [Z_AXIS, X_AXIS, Y_AXIS] },
      se: { near: [Z_AXIS, Y_AXIS.reverse, X_AXIS.reverse], far: [Z_AXIS, X_AXIS, Y_AXIS] },
      ne: { near: [Z_AXIS, X_AXIS, Y_AXIS.reverse], far: [Z_AXIS, Y_AXIS, X_AXIS.reverse] },
      sw: { near: [Z_AXIS, X_AXIS.reverse, Y_AXIS], far: [Z_AXIS, Y_AXIS.reverse, X_AXIS] }
    }.freeze

    # Orientación real del CON-12 -diagonal-, en TODOS los escalones -ver
    # TRIANGLE_CONNECTOR_21_AXES para el CON-21 del mismo escalón-.
    TRIANGLE_CONNECTOR_AXES_CAPPED = {
      nw: { near: [X_AXIS.reverse, Z_AXIS.reverse, Y_AXIS.reverse], far: [Y_AXIS, Z_AXIS, X_AXIS] },
      se: { near: [X_AXIS.reverse, Z_AXIS.reverse, Y_AXIS.reverse], far: [Y_AXIS, Z_AXIS, X_AXIS] },
      ne: { near: [Y_AXIS.reverse, Z_AXIS.reverse, X_AXIS], far: [X_AXIS.reverse, Z_AXIS, Y_AXIS] },
      sw: { near: [Y_AXIS, Z_AXIS.reverse, X_AXIS.reverse], far: [X_AXIS, Z_AXIS, Y_AXIS.reverse] }
    }.freeze
    # El punto real donde el tubo diagonal toca cada CON-12 -analizado
    # contra los 4 escalones "limpios" (los que no comparten nodo con un
    # conector de cuadrícula ya existente, ver NOTA DE ALCANCE) de los 2
    # ejemplos reales- NO es la punta del ramal mitrado de 76.2mm de
    # build_12; es el mismo RECEIVER_RADIUS_MM (24.15mm) usado en TODO el
    # resto del proyecto para tubos rectos, medido a lo largo del eje
    # local Z del propio CON-12 -el ramal de 76.2mm es el manguito que
    # RECIBE al tubo por dentro, oculto, igual que los manguitos centrados
    # de los conectores 21/35/40-. Verificado con error de ~2.1mm (0.14%
    # de una diagonal de ~1470mm) en los 4 escalones limpios de los 2
    # ejemplos -el error previo de una versión anterior (constante fija de
    # 70mm a lo largo de la diagonal pura) era de ~77mm, por eso los tubos
    # salían flotando fuera del conector-. Ver `diagonal_connector_mouth`.
    #
    # NOTA DE ALCANCE: esto solo construye el tubo diagonal y sus dos
    # CON-12 -la parte confirmada y verificada con exactitud numérica
    # contra datos reales-. NO modifica ningún conector de la cuadrícula
    # base en las esquinas donde cae la diagonal -el usuario confirmó que
    # a veces el conector que ya está ahí embona tal cual y a veces hay
    # que cambiarlo a mano, según el caso; de hecho, el escalón intermedio
    # de ambos ejemplos reales -el único que SÍ coincide con un nodo de la
    # cuadrícula base- se desvía ~36mm de esta fórmula limpia, justo
    # porque el usuario tuvo que ajustarlo a mano por esa razón-. Ese
    # ajuste, si hace falta, se sigue haciendo a mano en SketchUp después.

    def start
      unless defined?(UI::HtmlDialog)
        UI.messagebox('Este constructor necesita una versión de SketchUp compatible con HtmlDialog.')
        return
      end
      unless dependencies_available?
        UI.messagebox(
          "No se encontraron los plugins de tubos y conectores.\n\n" \
          'Instálalos y reinicia SketchUp antes de crear módulos.'
        )
        return
      end

      @dialog&.close
      @dialog = UI::HtmlDialog.new(
        dialog_title: 'Constructor de Módulos Play Idea',
        preferences_key: 'PlayIdeaConstructorModulos',
        scrollable: true,
        resizable: true,
        width: 820,
        height: 720,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_file(File.join(__dir__, 'selector.html'))
      @dialog.add_action_callback('ready') do |_action_context|
        @dialog.execute_script(
          "loadDefaults(#{JSON.generate(
            default_spacing_m: DEFAULT_SPACING_M,
            base_grid_height_mm: BASE_GRID_HEIGHT_MM,
            bottom_grid_height_mm: BOTTOM_GRID_HEIGHT_MM,
            receiver_radius_mm: RECEIVER_RADIUS_MM,
            tower_first_step_height_mm: TOWER_FIRST_STEP_HEIGHT_MM,
            standard_color_palette: STANDARD_COLOR_PALETTE
          )})"
        )
      end
      @dialog.add_action_callback('createModule') do |_action_context, data|
        params = validate_dialog_data(data)
        next unless params
        if params[:padding]
          padding_costs = capture_padding_costs
          next unless padding_costs
          params[:padding_costs] = padding_costs
        end
        @dialog.close
        Sketchup.active_model.select_tool(ModulePlacementTool.new(params))
      end
      @dialog.show
    rescue StandardError => error
      UI.messagebox("No fue posible abrir el constructor:\n#{error.message}")
      puts error.full_message
    end

    def dependencies_available?
      defined?(PlayIdea::CreadorTubos) &&
        defined?(PlayIdea::Conectores) &&
        PlayIdea::CreadorTubos.respond_to?(:add_hollow_geometry) &&
        PlayIdea::Conectores.respond_to?(:build_connector_geometry)
    end

    def validate_dialog_data(data)
      # spacing_z_m puede venir como número único -altura uniforme, de
      # siempre- o como Array -checkbox "alturas de módulo distintas" en
      # el diálogo, una altura por módulo (mm), ver grid_level_z/
      # spacing_z_length-.
      spacing_z_mm = if data['spacing_z_m'].is_a?(Array)
                       data['spacing_z_m'].map { |v| v.to_f * 1000.0 }
                     else
                       data['spacing_z_m'].to_f * 1000.0
                     end
      params = {
        modules_x: data['modules_x'].to_i,
        modules_y: data['modules_y'].to_i,
        modules_z: data['modules_z'].to_i,
        spacing_x_mm: data['spacing_x_m'].to_f * 1000.0,
        spacing_y_mm: data['spacing_y_m'].to_f * 1000.0,
        spacing_z_mm: spacing_z_mm,
        color: data['color'].to_s,
        code: data['code'].to_s.strip,
        connectors: data['connectors'] == true,
        padding: data['padding'] == true,
        padding_color_mode: data['padding_color_mode'].to_s,
        padding_color_vertical: data['padding_color_vertical'].to_s,
        padding_color_horizontal: data['padding_color_horizontal'].to_s,
        solera: data['solera'] == true,
        platform: data['platform'] == true,
        net: data['net'] == true
      }
      valid_counts = [:modules_x, :modules_y, :modules_z].all? do |key|
        params[key].between?(1, 20)
      end
      valid_spacing = [:spacing_x_mm, :spacing_y_mm].all? { |key| params[key].positive? } &&
        (params[:spacing_z_mm].is_a?(Array) ? params[:spacing_z_mm].length == params[:modules_z] && params[:spacing_z_mm].all?(&:positive?) : params[:spacing_z_mm].positive?)
      unless valid_counts && valid_spacing
        UI.messagebox('Las cantidades deben estar entre 1 y 20 y las medidas deben ser mayores que cero.')
        return nil
      end
      params[:code] = module_code(params) if params[:code].empty?
      # Medio módulo -checkboxes "Agregar medio módulo a lo ancho (X)"/"...
      # a lo largo (Y)" en el diálogo-: cada uno agrega una fila/columna
      # ENTERA adicional, a la mitad del ancho estándar, al final de SU
      # eje -independientes entre sí, se pueden activar los dos a la vez-.
      # SÍ se puede combinar con torre -la torre simplemente no puede
      # pararse sobre esas columnas/filas angostas, ver tower_params_from_
      # dialog, que las rechaza-. "modules_x/y" tal como los escribe el
      # usuario siguen siendo la cantidad de columnas/filas de tamaño
      # NORMAL; el medio módulo se agrega aparte, no cuenta dentro de esa
      # cifra.
      if data['half_module_x'] == true
        params[:spacing_x_mm], params[:modules_x] = apply_half_module(params[:spacing_x_mm], params[:modules_x])
      end
      if data['half_module_y'] == true
        params[:spacing_y_mm], params[:modules_y] = apply_half_module(params[:spacing_y_mm], params[:modules_y])
      end
      if data['tower'] == true
        tower = tower_params_from_dialog(data, params)
        if tower.nil?
          UI.messagebox(
            'Elige una columna de la cuadrícula haciendo clic en la vista ' \
            'previa para colocar la torre -o revisa que la estructura sea ' \
            'lo bastante alta (al menos 50cm) para que quepa un escalón.'
          )
          return nil
        end
        params[:tower] = tower
      end
      if data['tobogan'] == true
        edge = data['tobogan_edge'].to_s.to_sym
        index = data['tobogan_index']
        valid_edge = %i[x_near x_far y_near y_far].include?(edge)
        max_index = (edge == :x_near || edge == :x_far) ? params[:modules_y] : params[:modules_x]
        valid_index = index.is_a?(Numeric) && index.to_i.between?(0, max_index - 1)
        unless valid_edge && valid_index
          UI.messagebox(
            'Elige por dónde arranca el tobogán haciendo clic en una celda ' \
            'de la orilla de la vista previa.'
          )
          return nil
        end
        params[:tobogan] = true
        params[:tobogan_edge] = edge
        params[:tobogan_index] = index.to_i
        params[:tobogan_height_mm] = real_total_height_mm(params)
        params[:tobogan_color_mode] = data['tobogan_color_mode'].to_s
        params[:tobogan_color] = data['tobogan_color'].to_s
        params[:tobogan_color_a] = data['tobogan_color_a'].to_s
        params[:tobogan_color_b] = data['tobogan_color_b'].to_s
      end
      # "Entrada" de la estructura -checkbox propio, solo visible/relevante
      # si hay malla-: SIEMPRE en el nivel 0 -planta baja-, mismo par
      # edge/index que el tobogán -celda de orilla elegida en la vista
      # previa-, pero es un concepto independiente -la estructura puede
      # tener entrada sin tobogán-. place_nets usa esto para omitir el
      # ÚNICO paño vertical de ese lado/celda en el nivel 0.
      if params[:net] && data['entrada'] == true
        edge = data['entrada_edge'].to_s.to_sym
        index = data['entrada_index']
        valid_edge = %i[x_near x_far y_near y_far].include?(edge)
        max_index = (edge == :x_near || edge == :x_far) ? params[:modules_y] : params[:modules_x]
        valid_index = index.is_a?(Numeric) && index.to_i.between?(0, max_index - 1)
        unless valid_edge && valid_index
          UI.messagebox(
            'Elige por dónde va la entrada de la estructura haciendo clic ' \
            'en una celda de la orilla de la vista previa.'
          )
          return nil
        end
        params[:entrada] = { edge: edge, index: index.to_i }
      end
      params
    end

    def module_code(params)
      "MOD-#{params[:modules_x]}X#{params[:modules_y]}X#{params[:modules_z]}"
    end

    # Convierte `spacing_mm` -Float uniforme, de siempre- en un Array de
    # `modules` columnas/filas normales más UNA columna/fila extra a la
    # mitad de ancho -"medio módulo"-, y regresa el nuevo Array junto con
    # la cantidad de columnas/filas actualizada -modules+1-. Mismo cálculo
    # usado tanto desde el diálogo manual -checkboxes "Agregar medio
    # módulo..."- como desde el constructor automático.
    def apply_half_module(spacing_mm, modules)
      [Array.new(modules, spacing_mm) + [spacing_mm / 2.0], modules + 1]
    end

    # Ajuste automático de un eje horizontal (X o Y) a una medida real
    # pedida en mm: `units` = cuántos módulos de `module_mm` caben en
    # `target_mm`. El umbral para agregar medio módulo tiene que ser 0.5
    # -no menos- para que "acercarse más" y "nunca pasarse de lo pedido"
    # sean compatibles: agregar medio módulo solo achica la diferencia
    # SIN pasarse cuando el residuo es de al menos medio módulo -si fuera
    # menos, whole+0.5 ya sería MÁS grande que lo pedido-. Si el residuo
    # es menor a medio módulo, se queda en el entero hacia abajo. NUNCA
    # redondea hacia arriba a un módulo completo extra.
    # Regresa [cantidad de módulos normales, usar medio módulo?].
    def fit_modules_and_half(target_mm, module_mm)
      units = target_mm / module_mm
      whole = units.floor
      remainder = units - whole
      half = remainder >= 0.5
      whole = 1 if whole.zero? && !half
      [whole, half]
    end

    # Ajuste automático del alto (Z): cuántos módulos de altura `module_mm`
    # caben en `target_mm` de alto de CUADRÍCULA -sin contar la torre, que
    # se agrega ENCIMA de esta altura, no está incluida en `target_mm`-.
    # Redondea hacia abajo, nunca hacia arriba, mismo criterio que X/Y.
    # No existe "medio módulo" en Z -concepto no aplica a alturas-.
    def fit_modules_z(target_mm, module_mm)
      modules = ((target_mm - BASE_GRID_HEIGHT_MM) / module_mm).floor
      modules < 1 ? 1 : modules
    end

    # Distancia constante entre el tope del tramo vertical SUPERIOR -entre
    # el penúltimo y el último nivel- y el borde de arriba del cincho MÁS
    # ALTO que lo abraza. Ese tramo SIEMPRE mide exactamente 1 módulo
    # estándar (DEFAULT_SPACING_M) de largo cuando hay 2+ niveles -el
    # RECEIVER_RADIUS_MM de holgura se cancela entre su z_start y su
    # z_end en create_grid_tubes, ver derivación completa en la
    # conversación-, así que esta distancia no depende de nz ni de la
    # altura de la planta baja -solo del cincho más cercano al tope,
    # que cae en el último múltiplo de CABLE_TIE_SPACING_MM antes del
    # final del tramo-.
    TOP_SEGMENT_TO_LAST_CINCHO_TOP_MM = (
      (DEFAULT_SPACING_M * 1000.0) -
      (((DEFAULT_SPACING_M * 1000.0) / CABLE_TIE_SPACING_MM).floor * CABLE_TIE_SPACING_MM + CABLE_TIE_WIDTH_MM)
    )

    # Alternativa a fit_modules_z: en vez de "altura de cuadrícula" a
    # secas, `target_mm` es la altura TOTAL pedida por el usuario -de la
    # BASE del CON-61 (Z=0) a la superficie exterior de arriba del
    # CINCHO MÁS ALTO que envuelve el protector del tramo superior-, una
    # medida más útil para instalación que la cuadrícula cruda.
    #
    # Reparte esa altura en `nz` niveles: todos a `module_mm` -estándar-
    # EXCEPTO la planta baja -nivel 0-, que se queda con el sobrante
    # ENCIMA de un módulo estándar -"un poco más alta", nunca más baja,
    # pedido explícito del usuario-. Devuelve [nz, spacing_z_mm] listo
    # para params[:modules_z]/params[:spacing_z_mm] -este último ya
    # como Array, un valor por nivel-.
    #
    # OJO -caso no cubierto-: si el resultado da nz==1 -estructura muy
    # baja, un solo nivel-, el tramo superior "SIEMPRE mide 1 módulo
    # estándar" ya NO aplica -con nz==1 el único tramo empieza en el 61
    # mismo, no a la altura de un nivel intermedio-, así que la altura
    # final quedaría un poco corrida para ese caso extremo. No pasa en
    # una estructura de altura normal -varios metros-, que es el uso
    # real esperado.
    def fit_modules_z_and_spacing(target_mm, module_mm)
      needed_accumulated_mm = target_mm + TOP_SEGMENT_TO_LAST_CINCHO_TOP_MM - BASE_GRID_HEIGHT_MM - RECEIVER_RADIUS_MM
      nz = (needed_accumulated_mm / module_mm).floor
      nz = 1 if nz < 1
      ground_floor_mm = needed_accumulated_mm - ((nz - 1) * module_mm)
      spacing = Array.new(nz, module_mm)
      spacing[0] = ground_floor_mm
      [nz, spacing]
    end

    # Celda (i,j) + esquina al azar para la torre del constructor
    # automático -para que no salga siempre en la misma esquina-, evitando
    # las columnas/filas de medio módulo -mismo criterio de rechazo que
    # tower_params_from_dialog, pero aquí se descarta ANTES de elegir, no
    # después-.
    #
    # SOLO elige entre las esquinas REALES de la cuadrícula completa
    # -(0,0)/(0,max)/(max,0)/(max,max)-, NUNCA una columna interior o de
    # borde intermedio: create_triangle_tower/TRIANGLE_CONNECTOR_AXES_
    # CAPPED deja explícito en su "NOTA DE ALCANCE" que el tubo diagonal
    # de la torre NUNCA reemplaza el conector que ya esté en esos dos
    # nodos -"a veces el conector que ya está ahí embona tal cual y a
    # veces hay que cambiarlo a mano"-, y todo lo medido/calibrado fue
    # contra una esquina real (CON-61/CON-21), nunca contra un nodo de
    # borde (CON-35) o interior (CON-40). Escoger una columna interior al
    # azar producía justo eso: CON-12/CON-26 mal acomodados, reportado
    # por el usuario tras probar el modo automático.
    # `nil` si no queda ninguna esquina válida -estructura demasiado
    # angosta, ver el aviso en params_from_automatic_data-.
    #
    # La dirección del ángulo recto SOLO se elige entre :sw y :ne -no las
    # 4 de TRIANGLE_CORNER_ORDER-: create_triangle_tower ALTERNA cada
    # escalón entre la esquina dada y su opuesta diagonal
    # -TRIANGLE_CORNER_ORDER[(idx+2)%4]-, así que sw alterna con ne y nw
    # alterna con se. Repasando TODAS las pruebas con datos reales de
    # este proyecto, siempre se usó 'sw' como dirección elegida -nunca
    # 'nw'-, así que el par sw↔ne quedó validado -ambas esquinas se
    # ejercitan al alternar- pero nw↔se JAMÁS se probó contra una torre
    # real. Elegir entre las 4 -incluyendo nw/se- producía CON-12/CON-26
    # mal acomodados, reportado por el usuario tras probar el automático.
    VALIDATED_TOWER_RIGHT_ANGLE_CORNERS = %i[sw ne].freeze
    def random_tower_cell(params)
      valid_is = (0...params[:modules_x]).to_a
      valid_is.delete(params[:modules_x] - 1) if params[:spacing_x_mm].is_a?(Array)
      valid_js = (0...params[:modules_y]).to_a
      valid_js.delete(params[:modules_y] - 1) if params[:spacing_y_mm].is_a?(Array)
      return nil if valid_is.empty? || valid_js.empty?

      corner_is = (valid_is & [0, params[:modules_x] - 1]).uniq
      corner_js = (valid_js & [0, params[:modules_y] - 1]).uniq
      return nil if corner_is.empty? || corner_js.empty?

      [corner_is.sample, corner_js.sample, VALIDATED_TOWER_RIGHT_ANGLE_CORNERS.sample]
    end

    # Arma el mismo `params` que produce validate_dialog_data -mismas
    # llaves, compatible con ModulePlacementTool sin cambiarla-, pero a
    # partir de una medida real pedida -ancho/largo/alto en metros- en vez
    # de cantidades de módulo explícitas: calcula modules_x/y -con medio
    # módulo automático si ayuda a acercarse más, ver fit_modules_and_
    # half- y modules_z -fit_modules_z-, y arma una torre en una columna Y
    # esquina AL AZAR -ver random_tower_cell-, evitando automáticamente
    # que caiga sobre una columna/fila de medio módulo.
    def params_from_automatic_data(data)
      ancho_mm = data['ancho_m'].to_f * 1000.0
      largo_mm = data['largo_m'].to_f * 1000.0
      alto_mm = data['alto_m'].to_f * 1000.0
      unless ancho_mm.positive? && largo_mm.positive? && alto_mm.positive?
        UI.messagebox('Ancho, largo y alto deben ser mayores que cero.')
        return nil
      end

      module_mm = DEFAULT_SPACING_M * 1000.0
      modules_x, half_x = fit_modules_and_half(ancho_mm, module_mm)
      modules_y, half_y = fit_modules_and_half(largo_mm, module_mm)
      # `alto_m` ahora es la altura TOTAL real -de la base del CON-61 al
      # cincho más alto-, no la altura de cuadrícula cruda -ver
      # fit_modules_z_and_spacing-. La planta baja -spacing_z_mm[0]-
      # sale más alta que el resto para absorber el sobrante exacto.
      modules_z, spacing_z_array = fit_modules_z_and_spacing(alto_mm, module_mm)

      params = {
        modules_x: modules_x,
        modules_y: modules_y,
        modules_z: modules_z,
        spacing_x_mm: module_mm,
        spacing_y_mm: module_mm,
        spacing_z_mm: spacing_z_array,
        color: data['color'].to_s,
        code: data['code'].to_s.strip,
        connectors: true,
        # Recubrimiento -si se pidió- siempre en modo 'aleatorio' -mezcla
        # los colores del catálogo, ver padding_color_selector-: no expone
        # el modo vertical/horizontal aquí, para mantener el diálogo
        # automático mínimo -eso sigue disponible en el manual-.
        padding: data['padding'] == true,
        padding_color_mode: 'aleatorio',
        padding_color_vertical: '',
        padding_color_horizontal: '',
        solera: data['solera'] == true,
        platform: data['platform'] == true,
        net: data['net'] == true,
        # Pedido del usuario: el tobogán se agrega DESPUÉS de armar la
        # cuadrícula -ver Tobogan::Builder.attach, llamado desde
        # ModulePlacementTool tras create_module-, pero necesita la
        # altura TOTAL pedida -alto_m, en mm- que params_from_automatic_
        # data ya NO conserva -se convierte a modules_z/spacing_z_array
        # arriba-, así que se guarda aparte aquí.
        tobogan: data['tobogan'] == true,
        tobogan_height_mm: alto_mm,
        # Pedido del usuario: colores de los ductos del tobogán -fibra de
        # vidrio-, independientes del color de los tubos de la
        # estructura. Ver Tobogan::Builder.tobogan_color_picker.
        tobogan_color_mode: data['tobogan_color_mode'].to_s,
        tobogan_color: data['tobogan_color'].to_s,
        tobogan_color_a: data['tobogan_color_a'].to_s,
        tobogan_color_b: data['tobogan_color_b'].to_s
      }
      params[:spacing_x_mm], params[:modules_x] = apply_half_module(params[:spacing_x_mm], params[:modules_x]) if half_x
      params[:spacing_y_mm], params[:modules_y] = apply_half_module(params[:spacing_y_mm], params[:modules_y]) if half_y
      params[:code] = module_code(params) if params[:code].empty?

      cell = random_tower_cell(params)
      if cell
        i, j, corner = cell
        tower = tower_params_from_dialog(
          { 'tower_cell_i' => i, 'tower_cell_j' => j, 'tower_corner' => corner.to_s }, params
        )
        params[:tower] = tower if tower
      end
      unless params[:tower]
        UI.messagebox(
          'La estructura quedó demasiado angosta para agregar la torre ' \
          '-no quedó ninguna columna disponible fuera de las de medio ' \
          'módulo-, así que se creará sin torre.'
        )
      end
      params
    end

    def start_automatico
      unless defined?(UI::HtmlDialog)
        UI.messagebox('Este constructor necesita una versión de SketchUp compatible con HtmlDialog.')
        return
      end
      unless dependencies_available?
        UI.messagebox(
          "No se encontraron los plugins de tubos y conectores.\n\n" \
          'Instálalos y reinicia SketchUp antes de crear módulos.'
        )
        return
      end

      @automatic_dialog&.close
      @automatic_dialog = UI::HtmlDialog.new(
        dialog_title: 'Construcción de Juegos Play Idea (automática)',
        preferences_key: 'PlayIdeaConstructorAutomatico',
        scrollable: true,
        resizable: true,
        width: 420,
        height: 480,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @automatic_dialog.set_file(File.join(__dir__, 'automatico.html'))
      @automatic_dialog.add_action_callback('ready') do |_action_context|
        @automatic_dialog.execute_script(
          "loadDefaults(#{JSON.generate(
            default_spacing_m: DEFAULT_SPACING_M,
            base_grid_height_mm: BASE_GRID_HEIGHT_MM,
            receiver_radius_mm: RECEIVER_RADIUS_MM,
            top_segment_to_last_cincho_top_mm: TOP_SEGMENT_TO_LAST_CINCHO_TOP_MM,
            standard_color_palette: STANDARD_COLOR_PALETTE
          )})"
        )
      end
      @automatic_dialog.add_action_callback('createAutomatic') do |_action_context, data|
        params = params_from_automatic_data(data)
        next unless params
        if params[:padding]
          padding_costs = capture_padding_costs
          next unless padding_costs
          params[:padding_costs] = padding_costs
        end
        @automatic_dialog.close
        Sketchup.active_model.select_tool(ModulePlacementTool.new(params))
      end
      @automatic_dialog.show
    rescue StandardError => error
      UI.messagebox("No fue posible abrir el constructor automático:\n#{error.message}")
      puts error.full_message
    end

    # Cuántos escalones caben, con separación entre 50 y 60cm, en
    # `total_height_mm` de punta a punta. Entre las opciones válidas
    # prefiere la separación más cercana a 600mm -menos escalones-; si
    # ninguna cantidad de escalones cae exactamente dentro del rango,
    # devuelve la que menos se aleje. `nil` si no cabe ni un escalón.
    def auto_tower_step_fit(total_height_mm)
      return nil if total_height_mm < 500.0
      best = nil
      (1..40).each do |gaps|
        spacing = total_height_mm / gaps
        next if spacing > 900.0
        error = if spacing < 500.0
                  500.0 - spacing
                elsif spacing > 600.0
                  spacing - 600.0
                else
                  0.0
                end
        next unless best.nil? || error < best[:error] || (error == best[:error] && gaps < best[:gaps])
        best = { gaps: gaps, spacing: spacing, error: error }
      end
      return nil if best.nil?
      { steps: best[:gaps] + 1, spacing_mm: best[:spacing] }
    end

    # Lista de alturas -mm- de TODOS los escalones de la torre. Es una
    # ESCALERA de planta baja a la ÚLTIMA planta -confirmado por el
    # usuario, analogía de una casa de 2 pisos-: sube TRAMO POR TRAMO por
    # cada nivel real INTERMEDIO -k=1 a nz-1-, pero se DETIENE en la base
    # del último módulo -nivel k=nz-1-, sin seguir subiendo DENTRO del
    # último módulo -no hay más pisos arriba de eso, no sería coherente
    # seguir poniendo escalones-. Con nz=1 -un solo módulo, sin "siguiente
    # piso" al que subir- no aplica esta lógica de escalera: se queda con
    # el patrón fijo ya validado -2 escalones a TOWER_FIRST_STEP_HEIGHT_MM
    # de separación, ver reporte_grupo_20260806_110850.txt-, independiente
    # de la altura del módulo. Cada tramo -de un nivel real al siguiente-
    # se auto-ajusta aparte con `auto_tower_step_fit`, así que el escalón
    # final de cada tramo cae EXACTO en el nivel real, sin importar qué
    # tan alto sea el módulo -uno alto necesita más escalones intermedios
    # por tramo, uno bajito los necesita menos, calculado solo, no
    # forzado-.
    def auto_tower_step_heights(bottom_z_mm, real_grid_levels_mm, nz)
      return [bottom_z_mm, bottom_z_mm + TOWER_FIRST_STEP_HEIGHT_MM] if nz <= 1
      objetivos = real_grid_levels_mm[1..(nz - 1)] || []
      alturas = [bottom_z_mm]
      actual = bottom_z_mm
      objetivos.each do |objetivo|
        fit = auto_tower_step_fit(objetivo - actual)
        if fit.nil?
          alturas << objetivo
        else
          (1...fit[:steps]).each { |i| alturas << actual + i * fit[:spacing_mm] }
        end
        actual = objetivo
      end
      alturas
    end

    # Campos `tower_*` del mismo diálogo (checkbox "Agregar torre de pisos
    # triangulares" en selector.html), reutilizando color y código de la
    # estructura -no hay un segundo diálogo para la torre en este flujo
    # integrado-. La celda de la torre YA NO se escribe a mano: el usuario
    # elige una columna (i,j) real de la cuadrícula haciendo clic en la
    # vista previa, así que usa la MISMA medida de celda que la
    # estructura (`spacing_x_mm`/`spacing_y_mm`). Escalones auto-
    # calculados vía `auto_tower_step_heights` -tramo por tramo entre
    # niveles reales, ver el comentario grande junto a esa función-.
    # Devuelve `nil` si algo no es válido.
    def tower_params_from_dialog(data, structure_params)
      return nil if data['tower_cell_i'].nil? || data['tower_cell_j'].nil?
      i = data['tower_cell_i'].to_i
      j = data['tower_cell_j'].to_i
      return nil unless i.between?(0, structure_params[:modules_x] - 1)
      return nil unless j.between?(0, structure_params[:modules_y] - 1)
      # La torre no se puede parar sobre la columna/fila de medio módulo
      # -angosta a propósito, no aguanta una torre-: si ese eje tiene medio
      # módulo -spacing_x_mm/spacing_y_mm llega como Array-, su última
      # columna/fila es la mitad de ancho y queda fuera de las celdas
      # elegibles para torre.
      return nil if structure_params[:spacing_x_mm].is_a?(Array) && i == structure_params[:modules_x] - 1
      return nil if structure_params[:spacing_y_mm].is_a?(Array) && j == structure_params[:modules_y] - 1
      right_angle_corner = data['tower_corner'].to_s.to_sym
      return nil unless TRIANGLE_CORNER_ORDER.include?(right_angle_corner)

      nz = structure_params[:modules_z]
      # El primer escalón nunca arranca EXACTO en el nivel 0 -ahí ya está
      # el conector 61 recibiendo el poste vertical, no cabe un tubo
      # diagonal ahí-, así que arranca en TOWER_FIRST_STEP_HEIGHT_MM
      # -500mm, siempre por encima de BOTTOM_GRID_HEIGHT_MM-, punto fijo,
      # no depende de la altura de módulo elegida.
      return nil if nz < 1
      bottom_z_mm = TOWER_FIRST_STEP_HEIGHT_MM

      # Niveles reales de la cuadrícula -en mm-, para que create_triangle_
      # tower pueda saltarse el CON-21+patas en cualquier escalón cuya
      # altura caiga en uno de estos niveles -ahí ya hay conectores/tubos
      # reales de la cuadrícula, no hace falta duplicar, solo la
      # diagonal- Y para que auto_tower_step_heights sepa dónde tienen que
      # caer los escalones finales de cada tramo. `spacing_z_mm` puede ser
      # un Float uniforme o un Array -altura variable por módulo-, ver
      # `grid_level_z`/`spacing_z_length`.
      sz = spacing_z_length(structure_params[:spacing_z_mm])
      real_grid_levels_mm = (0..nz).map { |k| grid_level_z(k, nz, sz).to_mm }
      step_heights_mm = auto_tower_step_heights(bottom_z_mm, real_grid_levels_mm, nz)

      # REVERTIDO: la celda de la torre SÍ usa las 4 esquinas reales de la
      # cuadrícula, sin inset -ver el comentario grande junto a
      # TRIANGLE_DIAGONAL_INSET_MM más abajo-. Midiendo 4 estructuras
      # reales hechas a mano (torre + cuadrícula juntas) resultó que
      # CON-21 y CON-10 SÍ van pegados/cerca de la columna real -a propio
      # propósito, no es un choque-; solo el CON-12 diagonal necesita
      # alejarse, y no de toda la celda: solo él, de su propia esquina.
      # Ver `diagonal_connector_transform` y create_triangle_tower.
      # `axis_column_width_mm`/`axis_cumulative_mm` -en vez de multiplicar
      # directo por spacing_x_mm/spacing_y_mm- porque esos ahora pueden ser
      # Array -medio módulo activo en ese eje-; ya se rechazó arriba que la
      # celda elegida SEA la columna/fila angosta, así que aquí `i`/`j`
      # siempre caen en una columna/fila de ancho normal.
      {
        cell_x_mm: axis_column_width_mm(i, structure_params[:spacing_x_mm]),
        cell_y_mm: axis_column_width_mm(j, structure_params[:spacing_y_mm]),
        right_angle_corner: right_angle_corner,
        step_heights_mm: step_heights_mm,
        real_grid_levels_mm: real_grid_levels_mm,
        color: structure_params[:color],
        code: "#{structure_params[:code]}-TORRE",
        offset_x_mm: axis_cumulative_mm(i, structure_params[:spacing_x_mm]).to_mm,
        offset_y_mm: axis_cumulative_mm(j, structure_params[:spacing_y_mm]).to_mm
      }
    end

    # Mismo patrón que capture_costs en conectores_playidea: valores por
    # defecto editables, guardados con Sketchup.write_default para que la
    # siguiente vez ya aparezcan los últimos capturados. Cada renglón
    # corresponde a un paso real del proceso: tubo crudo, perforado (mano
    # de obra + luz), empalme a 2.4m, forro de plástico, pegamento con
    # solvente, mano de obra de aplicarlo, y soldado de la costura.
    def capture_padding_costs
      prompts = [
        'Precio de un tubo crudo de polyfoam 2m (MXN)',
        'Mano de obra de perforado por tubo terminado (MXN)',
        'Electricidad de perforado por tubo terminado (MXN)',
        'Mano de obra de empalme/pegado a 2.4m (MXN)',
        'Material de forro (plástico) por tubo terminado (MXN)',
        'Pegamento con solvente por tubo terminado (MXN)',
        'Mano de obra de aplicar el pegamento (MXN)',
        'Mano de obra de soldar la costura (MXN)'
      ]
      keys = %w[raw_tube perforation_labor electricity splice_labor wrap_material adhesive apply_labor weld_labor]
      defaults = keys.map do |key|
        stored = Sketchup.read_default('PlayIdeaRecubrimientoCostos', key, nil)
        stored.nil? || stored.to_f <= 0 ? PADDING_DEFAULT_COSTS[key] : stored.to_f
      end
      values = UI.inputbox(prompts, defaults, 'Costos del recubrimiento de espuma')
      return nil unless values
      keys.each_with_index do |key, index|
        Sketchup.write_default('PlayIdeaRecubrimientoCostos', key, values[index].to_f)
      end
      keys.zip(values.map(&:to_f)).to_h
    end

    def create_module(params, origin)
      model = Sketchup.active_model
      model.start_operation("Crear módulo #{params[:code]}", true)
      container = model.active_entities.add_group
      container.name = params[:code]

      create_grid_tubes(container.entities, params, origin, model)

      connector_counts = Hash.new(0)
      if params[:connectors]
        connector_definitions = create_connector_definitions(model)
        create_grid_connectors(
          container.entities, connector_definitions, connector_counts,
          params, origin
        )
      end

      padding_length_mm = params[:padding] ? create_grid_padding(container.entities, params, origin, model) : 0.0

      write_module_attributes(container, params, connector_counts, padding_length_mm)
      model.selection.clear
      model.selection.add(container)
      model.commit_operation
      container
    rescue StandardError
      model.abort_operation
      raise
    end

    def create_tube_definition(model, length_mm, color, axis_name)
      params = {
        length_mm: length_mm,
        outside_mm: STRUCTURAL_OUTSIDE_MM,
        schedule: STRUCTURAL_SCHEDULE,
        wall_mm: STRUCTURAL_WALL_MM,
        inside_mm: STRUCTURAL_OUTSIDE_MM - (2.0 * STRUCTURAL_WALL_MM),
        code: "TUB-MOD-#{axis_name}-#{format('%.1f', length_mm)}",
        color: color,
        length_mode: 'modular',
        standard_name: (length_mm - DEFAULT_SPACING_M * 1000.0).abs < 0.05 ?
          'Módulo Play Idea — 1.1684 m' : '',
        connector_compatible: true,
        connector_clearance_mm: PlayIdea::Conectores::INSIDE_MM - STRUCTURAL_OUTSIDE_MM
      }
      definition = model.definitions.add(unique_name(model, params[:code]))
      PlayIdea::CreadorTubos.add_hollow_geometry(definition.entities, params)
      PlayIdea::CreadorTubos.apply_material(model, definition, color)
      PlayIdea::CreadorTubos.write_attributes(definition, params)
      definition
    end

    # Altura Z de una parrilla horizontal completa (tubos y conectores),
    # compartida entre create_grid_tubes y create_grid_connectors para que
    # ambos siempre se muevan juntos. Nivel 0: ver BOTTOM_GRID_HEIGHT_MM.
    # Último nivel (k==nz): el poste termina justo ahí (no continúa a otro
    # conector arriba), así que toda la parrilla sube un radio para que el
    # receptor vertical de cada conector alcance la punta real del poste
    # en vez de quedarse corto.
    # `sz` puede ser un solo Length -separación uniforme, como siempre- O un
    # Array de Length -una altura por módulo, para estructuras de varios
    # pisos con altura distinta cada uno-. Con Array, la altura acumulada
    # hasta el nivel k es la suma de las primeras k alturas (`sz[0...k]`),
    # no `k*sz`.
    def grid_level_z(k, nz, sz)
      return BOTTOM_GRID_HEIGHT_MM.mm if k.zero?
      altura_acumulada = sz.is_a?(Array) ? sz[0...k].inject(0.mm, :+) : k * sz
      z = BASE_GRID_HEIGHT_MM.mm + altura_acumulada
      z += RECEIVER_RADIUS_MM.mm if k == nz
      z
    end

    # Convierte `spacing_z_mm` -Float uniforme o Array de Floats, una altura
    # de módulo por elemento- a Length -o Array de Length-, para usarse
    # directo en `grid_level_z`.
    def spacing_z_length(spacing_z_mm)
      spacing_z_mm.is_a?(Array) ? spacing_z_mm.map(&:mm) : spacing_z_mm.mm
    end

    # Mismo patrón que spacing_z_mm/grid_level_z pero para X/Y: `spacing_mm`
    # acepta un Float uniforme -de siempre, todas las columnas/filas del
    # mismo ancho- o un Array de Floats, un ancho de columna/fila por
    # elemento -para "medios módulos"/"cuartos de módulo": una fila entera
    # a lo largo o a lo ancho con un ancho distinto (ej. la mitad o un
    # cuarto del ancho estándar), mezclada con columnas/filas normales-.
    # `axis_column_width_mm(index, spacing_mm)` da el ancho (Float mm) de
    # la columna/fila `index`; `axis_cumulative_mm(index, spacing_mm)` da
    # el offset acumulado (Length) desde el origen hasta esa columna/fila.
    def axis_column_width_mm(index, spacing_mm)
      spacing_mm.is_a?(Array) ? spacing_mm[index] : spacing_mm
    end

    def axis_cumulative_mm(index, spacing_mm)
      if spacing_mm.is_a?(Array)
        spacing_mm[0...index].sum.mm
      else
        (index * spacing_mm).mm
      end
    end

    # Altura TOTAL real de una estructura ya resuelta -mismo significado
    # que "alto_m" en el diálogo automático: de la base del CON-61 a la
    # superficie de arriba del cincho MÁS ALTO-, calculada a partir de
    # `params[:modules_z]`/`params[:spacing_z_mm]` en vez de pedirle ese
    # dato al usuario -el diálogo MANUAL no tiene un campo "alto total",
    # solo cantidad de módulos/medida de cada uno-. Es la inversa exacta
    # de `fit_modules_z_and_spacing` -sin pérdida por redondeo: el "sobrante"
    # de la planta baja absorbe el residuo completo, ver la derivación en
    # esa función-, así que para una estructura creada con el diálogo
    # AUTOMÁTICO esto reproduce el `alto_m` original tal cual.
    def real_total_height_mm(params)
      sz_length = spacing_z_length(params[:spacing_z_mm])
      grid_level_z(params[:modules_z], params[:modules_z], sz_length).to_mm - TOP_SEGMENT_TO_LAST_CINCHO_TOP_MM
    end

    # Ancho total del eje -suma de todas las columnas/filas-, para tramos
    # que atraviesan la cuadrícula completa de punta a punta (ej. el
    # tubo Y continuo en niveles k>=1, ver create_grid_tubes).
    def axis_total_mm(count, spacing_mm)
      spacing_mm.is_a?(Array) ? spacing_mm.sum : count * spacing_mm
    end

    # Desplazamiento (acortamiento) de un tubo X en un extremo nodo-a-nodo
    # (i, i+1). X siempre lo sirve Azul -asimétrico, nunca centrado, en
    # NINGÚN nivel, ni siquiera arriba de todo- así que los tubos X van
    # SIEMPRE segmentados un tramo por módulo, con el mismo radio en ambos
    # extremos, sin excepción de nivel.
    def x_mouth_offset_mm(_i, _j, _nx, _ny)
      RECEIVER_RADIUS_MM
    end

    # Desplazamiento (acortamiento, o alargamiento si es negativo) de un
    # tubo Y en un extremo REAL de columna (j=0 o j=ny). Solo en el NIVEL 0
    # el eje Y lo sirve una pieza asimétrica -Principal, vía
    # bottom_corner_transform, porque "Verde" está volteada tocando el 61-,
    # así que ahí Y se acorta igual que X. En CUALQUIER OTRO nivel (k>=1,
    # sea el intermedio real o el de arriba) una esquina real (2
    # direcciones) siempre queda servida por una pieza CENTRADA -"Verde"
    # arriba, vía corner_transform; el par opuesto reorientado a Z en un
    # nivel intermedio real deja la pieza centrada libre para Y, vía
    # swapped_z_body_transform-, así que el tubo debe alargarse para
    # atravesarla del todo. Un nodo de 3 direcciones (i interior, columna
    # con paso propio en X) nunca alarga en Y -confirmado en la ronda 13-,
    # sin importar el nivel: en su propio extremo Y siempre es el eje
    # sencillo ahí. Confirmado con datos reales de modules_z=2: en nivel 0
    # el tubo Y mide 1120.1mm por tramo (acorta 24.15 en ambos extremos);
    # en el nivel intermedio real Y en niveles k>=1 mide 2387.6mm de punta
    # a punta (alarga 25.4 en ambos extremos, sean esquinas reales).
    def y_mouth_offset_mm(i, j, nx, ny, k)
      horizontal = horizontal_directions(i, j, nx, ny)
      return -VERDE_HALF_LENGTH_MM if horizontal.length == 2 && !k.zero?
      RECEIVER_RADIUS_MM
    end

    # Reutiliza (o crea) la definición de tubo para un largo exacto, para
    # no duplicar geometría cuando varias combinaciones de extremos dan el
    # mismo largo -lo más común, ej. todos los tramos esquina-a-esquina-.
    def cached_tube_definition(model, cache, length_mm, color, axis_name)
      # La llave incluye axis_name -no solo el largo-: sin esto, un tramo X
      # y un tramo Y/Z del mismo largo -coincide seguido, ej. 1120.1mm es
      # tanto un tramo X completo como el tramo Y del nivel 0- terminaban
      # compartiendo la MISMA definición ya creada para el otro eje, con
      # su nombre -"TUB-MOD-X-..." en vez de "TUB-MOD-Y-..."-, afectando
      # cualquier cosa que cuente piezas por el prefijo del nombre -ej.
      # cotizador_playidea-. La geometría en sí no se veía afectada -la
      # pieza reusada se rota igual según la dirección real de colocación-,
      # solo el nombre quedaba engañoso.
      key = [length_mm.round(4), axis_name]
      cache[key] ||= create_tube_definition(model, length_mm, color, axis_name)
    end

    # Los tubos X siempre van segmentados, un tramo por módulo, en TODOS los
    # niveles (ver x_mouth_offset_mm). Los tubos Y van segmentados solo en
    # el nivel 0; en cualquier nivel k>=1 -intermedio real o el de arriba-
    # cada columna Y es un tubo continuo de punta a punta, porque ahí Y
    # siempre topa contra una pieza centrada en sus extremos reales (ver
    # y_mouth_offset_mm) que necesita ser atravesada por dentro, no solo
    # tocada en el borde.
    def create_grid_tubes(entities, params, origin, model)
      nx = params[:modules_x]
      ny = params[:modules_y]
      nz = params[:modules_z]
      sx_mm = params[:spacing_x_mm]
      sy_mm = params[:spacing_y_mm]
      sz = spacing_z_length(params[:spacing_z_mm])
      cache = {}

      (0..nz).each do |k|
        z = grid_level_z(k, nz, sz)
        (0..ny).each do |j|
          nx.times do |i|
            start_offset = x_mouth_offset_mm(i, j, nx, ny)
            end_offset = x_mouth_offset_mm(i + 1, j, nx, ny)
            length_mm = axis_column_width_mm(i, sx_mm) - start_offset - end_offset
            definition = cached_tube_definition(model, cache, length_mm, params[:color], 'X')
            point = offset_point(origin, axis_cumulative_mm(i, sx_mm) + start_offset.mm, axis_cumulative_mm(j, sy_mm), z)
            add_oriented_instance(entities, definition, point, X_AXIS)
          end
        end
      end

      (0..nz).each do |k|
        z = grid_level_z(k, nz, sz)
        if k.zero?
          (0..nx).each do |i|
            ny.times do |j|
              start_offset = y_mouth_offset_mm(i, j, nx, ny, k)
              end_offset = y_mouth_offset_mm(i, j + 1, nx, ny, k)
              length_mm = axis_column_width_mm(j, sy_mm) - start_offset - end_offset
              definition = cached_tube_definition(model, cache, length_mm, params[:color], 'Y')
              point = offset_point(origin, axis_cumulative_mm(i, sx_mm), axis_cumulative_mm(j, sy_mm) + start_offset.mm, z)
              add_oriented_instance(entities, definition, point, Y_AXIS)
            end
          end
        else
          (0..nx).each do |i|
            start_offset = y_mouth_offset_mm(i, 0, nx, ny, k)
            end_offset = y_mouth_offset_mm(i, ny, nx, ny, k)
            length_mm = axis_total_mm(ny, sy_mm) - start_offset - end_offset
            definition = cached_tube_definition(model, cache, length_mm, params[:color], 'Y')
            point = offset_point(origin, axis_cumulative_mm(i, sx_mm), start_offset.mm, z)
            add_oriented_instance(entities, definition, point, Y_AXIS)
          end
        end
      end

      # El poste Z solo es continuo DENTRO de un mismo nivel -nace en el 61
      # (k==0) y termina en el último nivel (k==nz) sin cortes-, pero se
      # PARTE en dos en cada nivel intermedio real (0<k<nz, solo existe con
      # modules_z>=2): el conector de ahí recibe cada mitad por separado con
      # su par de ramales reorientado a Z (ver swapped_z_body_transform),
      # así que el tubo no debe cruzarlo de largo. Confirmado con datos
      # reales: con modules_z=2 el poste aparece partido en dos piezas de
      # 1288.12mm cada una, con un hueco de ~40mm donde se aloja el
      # conector intermedio -aquí se usa el mismo radio de siempre
      # (24.15mm) para ese hueco, dentro del margen de imprecisión de un
      # ajuste hecho a mano en SketchUp-.
      (0...nz).each do |k|
        z_start = k.zero? ? 0.mm : grid_level_z(k, nz, sz) + RECEIVER_RADIUS_MM.mm
        z_end = k == nz - 1 ? grid_level_z(nz, nz, sz) : grid_level_z(k + 1, nz, sz) - RECEIVER_RADIUS_MM.mm
        length_mm = (z_end - z_start).to_mm
        z_definition = cached_tube_definition(model, cache, length_mm, params[:color], 'Z')
        (0..ny).each do |j|
          (0..nx).each do |i|
            point = offset_point(origin, axis_cumulative_mm(i, sx_mm), axis_cumulative_mm(j, sy_mm), z_start)
            add_oriented_instance(entities, z_definition, point, Z_AXIS)
          end
        end
      end
    end

    # Reutiliza (o crea) la definición del tubo de recubrimiento para un
    # largo exacto -mismo patrón que cached_tube_definition-.
    def cached_padding_definition(model, cache, length_mm, color)
      # La llave incluye el color -no solo el largo-: con un solo color
      # fijo nunca importó, pero con colores variables por pieza -ver
      # pad_existing_tubes-, dos piezas del mismo largo pueden necesitar
      # colores distintos, y antes la segunda se quedaba pegada al color
      # de la primera que cayera en esa llave.
      key = [length_mm.round(4), color]
      cache[key] ||= create_padding_definition(model, length_mm, color)
    end

    # Mismo patrón que `paint`/`hex_to_color` en colorear_tubos_playidea:
    # una sola definición de material por hex -nombre "Color #HEX", cacheada
    # en el propio `model.materials`, no en un Hash local- para que
    # coincida exacto con lo que ese plugin ya crea si coloreó otras
    # piezas del mismo hex.
    def apply_hex_material(model, definition, hex)
      name = "Color ##{hex}"
      material = model.materials[name] || model.materials.add(name)
      material.color = Sketchup::Color.new(hex[0..1].to_i(16), hex[2..3].to_i(16), hex[4..5].to_i(16))
      definition.entities.grep(Sketchup::Face).each do |face|
        face.material = material
        face.back_material = material
      end
    end

    # `color` es un hex de STANDARD_COLOR_PALETTE -no un nombre de
    # PlayIdea::CreadorTubos-, aplicado vía `apply_hex_material`.
    def create_padding_definition(model, length_mm, color)
      geometry_params = {
        length_mm: length_mm,
        outside_mm: PADDING_OUTSIDE_MM,
        inside_mm: PADDING_INSIDE_MM
      }
      definition = model.definitions.add(
        unique_name(model, "REC-#{format('%.1f', length_mm)}")
      )
      PlayIdea::CreadorTubos.add_hollow_geometry(definition.entities, geometry_params)
      apply_hex_material(model, definition, color)
      definition.set_attribute(DICTIONARY, 'type', 'recubrimiento')
      definition.set_attribute(DICTIONARY, 'length_mm', length_mm)
      definition.set_attribute(DICTIONARY, 'outside_diameter_mm', PADDING_OUTSIDE_MM)
      definition.set_attribute(DICTIONARY, 'inside_diameter_mm', PADDING_INSIDE_MM)
      definition.set_attribute(DICTIONARY, 'color', color)
      definition
    end

    # Geometría del cincho: un anillo delgado -mismo `add_hollow_geometry`
    # que cualquier tubo hueco del proyecto, solo corto (CABLE_TIE_WIDTH_MM)
    # y pegado a la superficie exterior de la espuma (diámetro interior =
    # PADDING_OUTSIDE_MM, exterior = +2×CABLE_TIE_THICKNESS_MM)-. Una sola
    # definición, cacheada -todos los cinchos son iguales, a diferencia del
    # recubrimiento que varía en largo-.
    # El cincho es del MISMO color que el recubrimiento que está fijando
    # -no un color fijo-, así que la llave del caché incluye el color,
    # igual que `cached_padding_definition`.
    def cached_cable_tie_definition(model, cache, color)
      key = [:cable_tie, color]
      cache[key] ||= begin
        geometry_params = {
          length_mm: CABLE_TIE_WIDTH_MM,
          outside_mm: PADDING_OUTSIDE_MM + 2 * CABLE_TIE_THICKNESS_MM,
          inside_mm: PADDING_OUTSIDE_MM
        }
        definition = model.definitions.add(unique_name(model, 'CINCHO-7.6X370'))
        PlayIdea::CreadorTubos.add_hollow_geometry(definition.entities, geometry_params)
        apply_hex_material(model, definition, color)
        definition.set_attribute(DICTIONARY, 'type', 'cincho')
        definition.set_attribute(DICTIONARY, 'width_mm', CABLE_TIE_WIDTH_MM)
        definition.set_attribute(DICTIONARY, 'color', color)
        definition
      end
    end

    # Un cincho cada CABLE_TIE_SPACING_MM (15cm) a lo largo de TODO el
    # recorrido real del tubo -`length_mm`, el largo del tubo estructural
    # original, no de cada tramo de 2.4m del recubrimiento-, para que la
    # separación se vea uniforme sin importar dónde caigan los cortes del
    # recubrimiento. Empieza en el primer múltiplo de 15cm -no en la punta
    # exacta del tubo- y no pasa del largo real.
    def add_cable_ties(entities, model, origin, direction, length_mm, color, cache)
      tag = get_or_create_tag(model, CABLE_TIE_TAG_NAME)
      offset_mm = CABLE_TIE_SPACING_MM
      while offset_mm < length_mm
        definition = cached_cable_tie_definition(model, cache, color)
        point = origin.offset(direction, offset_mm.mm)
        add_oriented_instance(entities, definition, point, direction, tag)
        offset_mm += CABLE_TIE_SPACING_MM
      end
    end

    # El tubo de espuma comercial mide PADDING_FINISHED_LENGTH_MM (2.4m) -no
    # existe más largo que eso-, así que ningún tramo de recubrimiento puede
    # ser una sola pieza más larga que eso: hay que partirlo en tantos
    # tramos de 2.4m como quepan, más un "cacho" final con el sobrante -si
    # el sobrante no es prácticamente cero- para cubrir exacto el resto sin
    # pasarse ni dejar hueco. Devuelve un Array de largos (mm), nunca vacío
    # salvo que `total_mm` sea 0 o negativo.
    def padding_segment_lengths_mm(total_mm)
      return [] if total_mm <= 0.01
      full_segments = (total_mm / PADDING_FINISHED_LENGTH_MM).floor
      remainder_mm = total_mm - full_segments * PADDING_FINISHED_LENGTH_MM
      lengths = Array.new(full_segments, PADDING_FINISHED_LENGTH_MM)
      lengths << remainder_mm if remainder_mm > 0.01
      lengths
    end

    # Recorre RECURSIVAMENTE `entities` -y cualquier sub-grupo dentro,
    # como el de una torre triangular- buscando instancias de tubos
    # estructurales ya existentes -definición con nombre 'TUB-...', mismo
    # prefijo que usa `create_tube_definition` tanto para la cuadrícula
    # base como para la torre-, y les pega recubrimiento de espuma
    # SEGMENTADO en tramos de máximo 2.4m -misma `padding_segment_lengths_
    # mm`- a lo largo de la geometría REAL de cada tubo -su propio origen
    # y dirección (`transformation.zaxis`, el eje que `add_oriented_
    # instance` usa como dirección de avance)-, no recalculada desde
    # `modules_x/y/z`. Así cubre CUALQUIER tubo -cuadrícula, torre, o
    # cualquier generador futuro- sin necesitar lógica especial por tipo
    # ni saber de antemano qué sub-grupos existen. El recubrimiento de
    # cada tubo se agrega a la MISMA colección de entities donde vive ese
    # tubo -necesario para que quede en el marco de coordenadas correcto
    # de su propio grupo/sub-grupo-. Devuelve el largo total cubierto
    # (mm, sin partir en tramos).
    # `color` acepta un nombre de color fijo -String, de siempre- O un
    # objeto que responda a `call(direction)` -un Vector3d unitario, el
    # eje de avance real de ese tubo- y devuelva el nombre de color a
    # usar para ESE tubo en particular -para poder colorear distinto por
    # dirección (vertical/horizontal) o al azar por pieza, sin tener que
    # llamar esta función una vez por cada caso-.
    def pad_existing_tubes(entities, model, color, cache = {})
      foam_tag = get_or_create_tag(model, FOAM_TAG_NAME)
      total_length_mm = 0.0
      entities.grep(Sketchup::ComponentInstance).each do |instance|
        name = instance.definition.name.to_s
        next unless name.start_with?('TUB-')
        length_str = name.scan(/\d+\.\d+/).last
        next unless length_str
        length_mm = length_str.to_f
        transform = instance.transformation
        direction = transform.zaxis
        segment_color = color.respond_to?(:call) ? color.call(direction) : color
        offset_mm = 0.0
        padding_segment_lengths_mm(length_mm).each do |seg_len_mm|
          definition = cached_padding_definition(model, cache, seg_len_mm, segment_color)
          point = transform.origin.offset(direction, offset_mm.mm)
          add_oriented_instance(entities, definition, point, direction, foam_tag)
          offset_mm += seg_len_mm
        end
        add_cable_ties(entities, model, transform.origin, direction, length_mm, segment_color, cache)
        total_length_mm += length_mm
      end
      entities.grep(Sketchup::Group).each do |sub_group|
        total_length_mm += pad_existing_tubes(sub_group.entities, model, color, cache)
      end
      total_length_mm
    end

    # El recubrimiento cubre cada fila X, columna Y y poste Z de PUNTA A
    # PUNTA -sin insetarse en los nodos como los tubos estructurales, ver
    # la constante PADDING_OUTSIDE_MM/PADDING_INSIDE_MM-, pero YA NO como
    # una sola pieza continua: se parte en tramos de máximo 2.4m
    # (`padding_segment_lengths_mm`), unidos uno tras otro a lo largo del
    # mismo eje, con un tramo más corto al final si el sobrante no llena un
    # tramo completo. No necesita conocer nada de la lógica de conectores
    # por tipo/nivel: solo el ancho total de la cuadrícula en cada eje.
    # Regresa el largo total construido (mm, sin partir), usado por
    # write_module_attributes para el costeo -el costeo YA asumía tramos de
    # 2.4m, ver PADDING_FINISHED_LENGTH_MM/sticks_needed; ahora la
    # geometría por fin coincide con esa cuenta-.
    def create_grid_padding(entities, params, origin, model)
      nx = params[:modules_x]
      ny = params[:modules_y]
      nz = params[:modules_z]
      sx_mm = params[:spacing_x_mm]
      sy_mm = params[:spacing_y_mm]
      sz = spacing_z_length(params[:spacing_z_mm])
      color = params[:color]
      cache = {}
      total_length_mm = 0.0

      (0..nz).each do |k|
        z = grid_level_z(k, nz, sz)
        (0..ny).each do |j|
          length_mm = nx * sx_mm
          offset_mm = 0.0
          padding_segment_lengths_mm(length_mm).each do |seg_len_mm|
            definition = cached_padding_definition(model, cache, seg_len_mm, color)
            point = offset_point(origin, offset_mm.mm, j * sy_mm.mm, z)
            add_oriented_instance(entities, definition, point, X_AXIS)
            offset_mm += seg_len_mm
          end
          total_length_mm += length_mm
        end
      end
      (0..nz).each do |k|
        z = grid_level_z(k, nz, sz)
        (0..nx).each do |i|
          length_mm = ny * sy_mm
          offset_mm = 0.0
          padding_segment_lengths_mm(length_mm).each do |seg_len_mm|
            definition = cached_padding_definition(model, cache, seg_len_mm, color)
            point = offset_point(origin, i * sx_mm.mm, offset_mm.mm, z)
            add_oriented_instance(entities, definition, point, Y_AXIS)
            offset_mm += seg_len_mm
          end
          total_length_mm += length_mm
        end
      end
      z_length_mm = grid_level_z(nz, nz, sz).to_mm
      (0..ny).each do |j|
        (0..nx).each do |i|
          offset_mm = 0.0
          padding_segment_lengths_mm(z_length_mm).each do |seg_len_mm|
            definition = cached_padding_definition(model, cache, seg_len_mm, color)
            point = offset_point(origin, i * sx_mm.mm, j * sy_mm.mm, offset_mm.mm)
            add_oriented_instance(entities, definition, point, Z_AXIS)
            offset_mm += seg_len_mm
          end
          total_length_mm += z_length_mm
        end
      end
      total_length_mm
    end

    def create_connector_definitions(model)
      %w[21 26 35 40 61].each_with_object({}) do |code, result|
        definition = model.definitions.add(
          unique_name(model, "CON-MOD-#{code}")
        )
        material = PlayIdea::Conectores.connector_material(model, 'Galvanizado')
        hardware = PlayIdea::Conectores.hardware_material(model)
        if code == '26'
          build_connector_26(definition.entities, material, hardware)
          metadata = connector_26_metadata
          write_connector_26_attributes(definition, metadata)
        elsif code == '35'
          build_connector_35_verde(definition.entities, material, hardware)
          metadata = connector_metadata(code)
          PlayIdea::Conectores.write_attributes(
            definition, code, 'Galvanizado', metadata
          )
        else
          PlayIdea::Conectores.build_connector_geometry(
            definition.entities, code, material, hardware
          )
          metadata = connector_metadata(code)
          PlayIdea::Conectores.write_attributes(
            definition, code, 'Galvanizado', metadata
          )
        end
        result[code] = [definition, metadata]
      end
    end

    # Variante del 35 exclusiva del constructor -no toca conectores_playidea,
    # mismo patrón que build_connector_26-: los mismos 3 ramales del 35
    # original (par opuesto en X + ramal sencillo en Y), pero con la pieza
    # central reemplazada por una centrada de 50.8mm -del mismo largo que
    # "Verde" del 21- en vez del manguito asimétrico de 63.5mm. Se usa en
    # nodos donde el poste Z no termina ahí -pasa continuo (nivel 0) o se
    # parte en dos (nivel intermedio real, ver swapped_z_body_transform)-,
    # así que necesita una pieza SIMÉTRICA para cubrir ambos lados del
    # nodo en Z, igual que Verde ya resuelve esto en el 21. Verificado
    # contra el largo real del tubo Y continuo del usuario en nivel
    # intermedio (2387.6mm con nx=1,ny=2 → alargue de 25.4mm por extremo,
    # exactamente la mitad de 50.8mm, no de 63.5mm).
    def build_connector_35_verde(entities, material, hardware)
      positive = PlayIdea::Conectores.add_branch_sleeve(
        entities, X_AXIS, 50.8, material, hardware
      )
      positive.name = 'Salida lateral +X 2 pulgadas'
      lateral = PlayIdea::Conectores.add_branch_sleeve(
        entities, Y_AXIS, 50.8, material, hardware
      )
      lateral.name = 'Salida lateral +Y 2 pulgadas'
      negative = PlayIdea::Conectores.add_branch_sleeve(
        entities, X_AXIS.reverse, 50.8, material, hardware
      )
      negative.name = 'Salida lateral -X 2 pulgadas'
      central = PlayIdea::Conectores.add_centered_sleeve(
        entities, Z_AXIS, 50.8, material, hardware
      )
      central.name = 'Salida verde 2 pulgadas'
    end

    # Conector 26 exclusivo del constructor: poste central pasante y dos
    # receptores horizontales enfrentados a 180 grados.
    def build_connector_26(entities, material, hardware)
      central = PlayIdea::Conectores.add_centered_sleeve(
        entities, Z_AXIS, 63.5, material, hardware
      )
      central.name = 'Paso central del conector 26'
      positive = PlayIdea::Conectores.add_branch_sleeve(
        entities, X_AXIS, 50.8, material, hardware
      )
      positive.name = 'Salida lateral +X del conector 26'
      negative = PlayIdea::Conectores.add_branch_sleeve(
        entities, X_AXIS.reverse, 50.8, material, hardware
      )
      negative.name = 'Salida lateral -X del conector 26'
    end

    def connector_26_metadata
      costs = PlayIdea::Conectores::DEFAULT_COSTS.each_with_object({}) do |(key, default), result|
        stored = Sketchup.read_default('PlayIdeaConectoresCostos', key, nil)
        result[key] = stored.nil? || stored.to_f <= 0 ? default : stored.to_f
      end
      cuts = [63.5, 50.8, 50.8]
      rows = cuts.each_with_index.map do |length, index|
        PlayIdea::Conectores.cost_row(
          "Tubo receptor #{index + 1} — #{length} mm",
          length / 6000.0, 'barra de 6 m', costs['bar_6m']
        )
      end
      rows.concat([
        PlayIdea::Conectores.cost_row('Tuercas', 3, 'pieza', costs['nut']),
        PlayIdea::Conectores.cost_row('Opresores Allen', 3, 'pieza', costs['screw']),
        PlayIdea::Conectores.cost_row('Cortes de tubo', 3, 'corte', costs['cut']),
        PlayIdea::Conectores.cost_row('Uniones soldadas', 5, 'operación', costs['weld']),
        PlayIdea::Conectores.cost_row('Consumibles de soldadura', 1, 'conector', costs['welding_supplies']),
        PlayIdea::Conectores.cost_row('Electricidad', 1, 'conector', costs['electricity']),
        PlayIdea::Conectores.cost_row('Acabado / pintura', 1, 'conector', costs['finish']),
        PlayIdea::Conectores.cost_row('Otros insumos', 1, 'conector', costs['other'])
      ])
      {
        receiver_material: 'Acero al carbón',
        hardware_size: 'M8',
        costing: { rows: rows, total: rows.inject(0.0) { |sum, row| sum + row[:subtotal] } },
        investment_cost_mxn: rows.inject(0.0) { |sum, row| sum + row[:subtotal] }
      }
    end

    def write_connector_26_attributes(entity, metadata)
      data = {
        'code' => 'CON-26',
        'connector_type' => '26',
        'description' => 'Paso central con dos salidas opuestas',
        'receiver_nominal_size' => '1 1/2 pulgadas',
        'receiver_schedule' => '30',
        'receiver_outside_mm' => PlayIdea::Conectores::OUTSIDE_MM,
        'receiver_inside_mm' => PlayIdea::Conectores::INSIDE_MM,
        'receiver_wall_mm' => PlayIdea::Conectores::WALL_MM,
        'color' => 'Galvanizado',
        'investment_cost_mxn' => metadata[:investment_cost_mxn],
        'currency' => 'MXN',
        'receiver_material' => metadata[:receiver_material],
        'tube_cuts_mm' => '63.5, 50.8, 50.8',
        'total_tube_length_mm' => 165.1,
        'nut_specification' => metadata[:hardware_size],
        'nut_quantity' => 3,
        'set_screw_specification' => metadata[:hardware_size],
        'set_screw_quantity' => 3,
        'has_base_plate' => false,
        'cost_breakdown_json' => JSON.generate(metadata[:costing][:rows])
      }
      data.each do |key, value|
        entity.set_attribute(PlayIdea::Conectores::DICTIONARY, key, value)
      end
      entity.set_attribute('minorusal_auditor', 'code', 'CON-26')
      entity.set_attribute(
        'minorusal_auditor',
        'investment_cost_mxn',
        metadata[:investment_cost_mxn]
      )
    end

    def connector_metadata(code)
      costs = PlayIdea::Conectores::DEFAULT_COSTS.each_with_object({}) do |(key, default), result|
        stored = Sketchup.read_default('PlayIdeaConectoresCostos', key, nil)
        result[key] = stored.nil? || stored.to_f <= 0 ? default : stored.to_f
      end
      costing = PlayIdea::Conectores.build_cost_breakdown(code, costs)
      {
        receiver_material: 'Acero al carbón',
        hardware_size: 'M8',
        costing: costing,
        investment_cost_mxn: costing[:total]
      }
    end

    def create_grid_connectors(entities, definitions, counts, params, origin)
      nx = params[:modules_x]
      ny = params[:modules_y]
      nz = params[:modules_z]
      sx_mm = params[:spacing_x_mm]
      sy_mm = params[:spacing_y_mm]
      sz = spacing_z_length(params[:spacing_z_mm])

      (0..nz).each do |k|
        (0..ny).each do |j|
          (0..nx).each do |i|
            horizontal = horizontal_directions(i, j, nx, ny)
            if k.zero?
              add_connector_instance(
                entities, definitions, counts, '61',
                offset_point(origin, axis_cumulative_mm(i, sx_mm), axis_cumulative_mm(j, sy_mm), 0),
                Geom::Transformation.translation(
                  offset_point(origin, axis_cumulative_mm(i, sx_mm), axis_cumulative_mm(j, sy_mm), 0)
                )
              )
            end

            code = connector_code_for_horizontal(horizontal)
            # El poste Z solo es continuo dentro de un mismo nivel; se PARTE
            # en cada nivel intermedio real (0<k<nz) -ver create_grid_tubes-,
            # así que ahí CUALQUIER nodo (esquina real o intermedio) necesita
            # el cuerpo del 35 para recibir cada mitad del poste, no solo los
            # nodos que ya tenían 3 direcciones horizontales. En el nivel más
            # alto (k==nz) no hay nada que continúe arriba, así que un nodo
            # intermedio de 3 direcciones no necesita el 35 -reusa el 21, ver
            # middle_transform-. Un nodo interior verdadero de 4 direcciones
            # (código '40') en ese mismo nivel más alto SÍ necesita el cuerpo
            # del 35 -no el del 21, que solo tiene 2 salidas horizontales,
            # insuficientes para las 4 reales de un nodo interior-: su par
            # opuesto sirve el eje X (siempre segmentado, ver
            # x_mouth_offset_mm, necesita dos bocas separadas) y su pieza
            # centrada sirve Y (continuo en cualquier nivel k>=1, necesita
            # una sola boca que se atraviese), ver interior_top_transform.
            # NO se toca el nodo interior en niveles k<nz -sigue pendiente,
            # sin datos reales todavía que confirmen su diseño correcto-.
            if k == nz
              code = '21' if code == '35'
              code = '35' if code == '40'
            elsif !k.zero?
              code = '35' if code == '21'
            end
            definition, metadata = definitions.fetch(code)
            z = grid_level_z(k, nz, sz)
            point = offset_point(origin, axis_cumulative_mm(i, sx_mm), axis_cumulative_mm(j, sy_mm), z)
            transform = connector_transform(code, point, horizontal, k, nz)
            instance = entities.add_instance(definition, transform)
            instance.name = "CON-#{code}"
            if code == '26'
              write_connector_26_attributes(instance, metadata)
            else
              PlayIdea::Conectores.write_attributes(
                instance, code, 'Galvanizado', metadata
              )
            end
            counts[code] += 1
          end
        end
      end
    end

    def horizontal_directions(i, j, nx, ny)
      directions = []
      directions << X_AXIS if i < nx
      directions << X_AXIS.reverse if i > 0
      directions << Y_AXIS if j < ny
      directions << Y_AXIS.reverse if j > 0
      directions
    end

    # Código estructural (por CANTIDAD de direcciones), sin conocer todavía
    # el nivel k. El nivel decide luego, en create_grid_connectors, si un
    # nodo de 2 direcciones (esquina real) o de 3 (nodo intermedio de fila/
    # columna) necesita este código tal cual o se remapea a otro -ver el
    # override ahí mismo y los comentarios de connector_transform-.
    def connector_code_for_horizontal(horizontal)
      if horizontal.length == 2
        return '26' if horizontal[0].parallel?(horizontal[1])
        return '21'
      end
      return '35' if horizontal.length == 3
      '40'
    end

    def add_connector_instance(entities, definitions, counts, code, point, transform)
      definition, metadata = definitions.fetch(code)
      instance = entities.add_instance(definition, transform)
      instance.name = "CON-#{code}"
      if code == '26'
        write_connector_26_attributes(instance, metadata)
      else
        PlayIdea::Conectores.write_attributes(
          instance, code, 'Galvanizado', metadata
        )
      end
      counts[code] += 1
      instance
    end

    # Único punto de despacho para TODOS los niveles -antes eran dos
    # funciones separadas (una para k==0, otra para k>=1), pero esa
    # división estaba mal desde el principio: lo que realmente distingue
    # el comportamiento no es "k==0 vs el resto" sino "k==nz (arriba de
    # todo, nada continúa) vs k<nz (algo sigue de largo, sea el poste
    # entero en k==0 o partido en dos en un nivel intermedio real)".
    #   - code=='21', 2 direcciones (esquina real):
    #       k==nz  -> corner_transform (normal, Principal asimétrico hacia
    #                 abajo está bien porque nada sigue arriba).
    #       k==0   -> bottom_corner_transform (Verde se voltea a tocar el
    #                 61 porque el poste sigue de largo, completo, arriba).
    #       0<k<nz -> NO debería llegar aquí -create_grid_connectors ya
    #                 remapea esquinas reales a '35' en niveles
    #                 intermedios reales, ver ahí el porqué-.
    #   - code=='21', 3 direcciones (nodo intermedio de fila/columna):
    #       solo llega aquí cuando k==nz (ver el mismo remapeo) ->
    #       middle_transform.
    #   - code=='35' (siempre 0<k<nz o k==0 con 3 direcciones, nunca
    #     k==nz, por el mismo remapeo):
    #       k==0   -> edge_transform_35 (el poste pasa CONTINUO por este
    #                 nivel, solo necesita una funda simétrica -"Verde"
    #                 sustituyendo el manguito central original, ver
    #                 build_connector_35_verde-, sin tocar la orientación
    #                 horizontal normal del cuerpo).
    #       0<k<nz -> swapped_z_body_transform (aquí el poste SÍ se parte
    #                 en dos -ver create_grid_tubes-, así que el PAR
    #                 OPUESTO de ramales del cuerpo -normalmente
    #                 horizontal- se reorienta para servir Z, recibiendo
    #                 cada mitad del poste por separado).
    def connector_transform(code, point, horizontal, k, nz)
      case code
      when '21'
        if horizontal.length == 2
          k.zero? ? bottom_corner_transform(point, horizontal) : corner_transform(point, horizontal + [Z_AXIS.reverse])
        else
          middle_transform(point, horizontal)
        end
      when '26'
        straight_transform_26(point, horizontal)
      when '35'
        if horizontal.length == 4
          interior_top_transform(point, horizontal)
        else
          k.zero? ? edge_transform_35(point, horizontal) : swapped_z_body_transform(point, horizontal)
        end
      when '40'
        k.zero? ? Geom::Transformation.translation(point) : interior_middle_transform(point)
      else
        Geom::Transformation.translation(point)
      end
    end

    # Nodo intermedio de una fila/columna (3 direcciones horizontales):
    # exactamente una es "sencilla" (sin pareja opuesta en la lista) y las
    # otras dos son un eje completo (ambas direcciones presentes). Reusa el
    # MISMO cuerpo del 21 sin modificarlo -Azul a la sencilla, Verde
    # -centrada- al eje completo, sirviendo de paso continuo-, sin importar
    # si ese eje es X o Y en el mundo -a diferencia de corner_transform, que
    # ata Azul a X y Verde a Y fijo, aquí el amarre es por rol, no por eje-.
    def middle_transform(point, horizontal)
      single = horizontal.find do |direction|
        horizontal.none? { |other| other.samedirection?(direction.reverse) }
      end
      continuous = horizontal.find { |direction| !direction.samedirection?(single) }
      world_axes = Geom::Transformation.axes(point, single.reverse, continuous, Z_AXIS)
      local_anchor_correction = Geom::Transformation.translation(
        Geom::Vector3d.new(-RECEIVER_RADIUS_MM.mm, 0, -RECEIVER_RADIUS_MM.mm)
      )
      world_axes * local_anchor_correction
    end

    # El 26 base está alineado sobre X. Se gira 90 grados cuando la línea
    # intermedia corre sobre el eje Y.
    #
    # `Transformation.rotation(point, eje, angulo)` NO coloca el origen local
    # del conector en `point` -solo garantiza que `point` quede fijo al girar-;
    # como origen local (0,0,0) de esta definición representa el nodo, hay que
    # girar alrededor de ORIGIN (ahí sí queda fijo en 0,0,0) y LUEGO trasladar
    # a `point`. Usar rotation(point,...) solo, como transform de colocación,
    # deja el conector en un lugar completamente distinto al nodo real -ver
    # misma corrección en edge_transform_35, donde se confirmó numéricamente-.
    def straight_transform_26(point, horizontal)
      along_y = horizontal.first.parallel?(Y_AXIS)
      angle = along_y ? 90.degrees : 0.degrees
      Geom::Transformation.translation(point) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, angle)
    end

    # El conector 21 base apunta a -X, +Y y -Z. Esta transformación alinea
    # sus tres receptores con las tres direcciones reales de cada esquina.
    def corner_transform(point, directions)
      x_target = directions.find { |vector| vector.parallel?(X_AXIS) }
      y_target = directions.find { |vector| vector.parallel?(Y_AXIS) }
      z_target = directions.find { |vector| vector.parallel?(Z_AXIS) }
      world_axes = Geom::Transformation.axes(
        point, x_target.reverse, y_target, z_target.reverse
      )
      # En el 21 aprobado, el nodo común está en (radio, 0, radio), no en el
      # origen de la definición. Se compensa para que las bocas horizontales
      # y el poste vertical coincidan con el nodo matemático de la cuadrícula.
      local_anchor_correction = Geom::Transformation.translation(
        Geom::Vector3d.new(
          -RECEIVER_RADIUS_MM.mm,
          0,
          -RECEIVER_RADIUS_MM.mm
        )
      )
      world_axes * local_anchor_correction
    end

    # Variante del 21 para el nivel 0 (BOTTOM_GRID_HEIGHT_MM): "Verde" -ya
    # centrada por conectores_playidea- pasa a apuntar hacia abajo para tocar
    # el receptor 61, mientras "Principal" pasa a servir la dirección Y y
    # "Azul" conserva la X. Es el mismo patrón que corner_transform pero
    # intercambiando los papeles de Y y Z.
    def bottom_corner_transform(point, directions)
      x_target = directions.find { |vector| vector.parallel?(X_AXIS) }
      y_target = directions.find { |vector| vector.parallel?(Y_AXIS) }
      world_axes = Geom::Transformation.axes(
        point, x_target.reverse, Z_AXIS, y_target.reverse
      )
      # El nodo común de la definición sigue en (radio, 0, radio) -el centro
      # de "Verde" tras su fix de centrado coincide con ese mismo punto-, así
      # que el ancla es idéntica a la de corner_transform.
      local_anchor_correction = Geom::Transformation.translation(
        Geom::Vector3d.new(-RECEIVER_RADIUS_MM.mm, 0, -RECEIVER_RADIUS_MM.mm)
      )
      world_axes * local_anchor_correction
    end

    # El 35 base tiene ramales +X, -X y +Y; le falta -Y. Se gira para que
    # esa dirección ausente coincida con el exterior del perímetro.
    def edge_transform_35(point, horizontal)
      all = [X_AXIS, X_AXIS.reverse, Y_AXIS, Y_AXIS.reverse]
      missing = all.find do |candidate|
        horizontal.none? { |direction| direction.samedirection?(candidate) }
      end
      angle =
        if missing.samedirection?(Y_AXIS.reverse)
          0.degrees
        elsif missing.samedirection?(X_AXIS)
          90.degrees
        elsif missing.samedirection?(Y_AXIS)
          180.degrees
        else
          -90.degrees
        end
      # Ver nota en straight_transform_26: rotation(point,...) sola NO coloca
      # el origen local en `point`, solo lo deja fijo si ya estuviera ahí.
      # Verificado con datos reales: con este bug, el conector de (0,1168.4)
      # con angle=-90° terminaba en (-1168.4,1168.4,0) -un módulo entero de
      # distancia-, coincidiendo exactamente con la fórmula
      # point - rotate(angle, point). Se gira primero alrededor de ORIGIN y
      # se traslada después a `point`.
      Geom::Transformation.translation(point) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, angle)
    end

    # Nivel intermedio REAL (0<k<nz, solo existe con modules_z>=2): aquí el
    # poste Z se PARTE en dos tramos en vez de pasar continuo (ver
    # create_grid_tubes) -confirmado con datos reales del usuario: el
    # bounding box del conector crece en Z, no en el eje horizontal que
    # tendría el 35 normal-. El cuerpo del 35 (par opuesto de ramales +
    # ramal sencillo + pieza centrada, ver build_connector_35_verde) se
    # reorienta para que el PAR OPUESTO -normalmente horizontal- sirva Z en
    # su lugar, recibiendo cada mitad del poste por separado; las dos
    # direcciones horizontales reales de este nodo -sean 2 de una esquina
    # real o 1 sencilla + 1 continua de un nodo intermedio de fila/
    # columna- las cubren el ramal sencillo y la pieza centrada, sin
    # importar cuál sea cuál -ambas alcanzan igual de bien una dirección
    # sencilla; la centrada de más simplemente sobra un poco, sin problema-.
    # Verificado con datos reales: para una esquina con horizontal=
    # [X_AXIS.reverse, Y_AXIS], esta fórmula predice xaxis=[0,0,1],
    # yaxis=[-1,0,0], zaxis=[0,1,0] -coincide exactamente con lo medido-.
    def swapped_z_body_transform(point, horizontal)
      single = horizontal.find do |direction|
        horizontal.none? { |other| other.samedirection?(direction.reverse) }
      end
      other = horizontal.find { |direction| !direction.samedirection?(single) && !direction.parallel?(single) }
      Geom::Transformation.axes(point, Z_AXIS, single, other)
    end

    # Nodo interior verdadero (4 direcciones horizontales: los dos ejes
    # completos, X e Y) en el nivel MÁS ALTO (k==nz) — el único caso donde
    # esto se remapea a '35' en vez de quedarse en '40', ver el override en
    # create_grid_connectors. El 21 no sirve aquí -solo tiene 2 salidas
    # horizontales, hacen falta 4-, así que se reusa el mismo cuerpo del 35
    # (par opuesto + ramal sencillo + pieza centrada, build_connector_35_verde)
    # con una tercera asignación de roles: el par opuesto sirve el eje X
    # -SIEMPRE segmentado en cualquier nivel, ver x_mouth_offset_mm, necesita
    # dos bocas separadas para los dos tramos que llegan-; la pieza centrada
    # sirve Y -continuo en cualquier nivel k>=1, ver y_mouth_offset_mm,
    # necesita una sola boca que se atraviese de lado a lado-; el ramal
    # sencillo sirve Z hacia abajo -asimétrico, como Principal en una
    # esquina real de este mismo nivel, porque nada continúa arriba-.
    # Verificado con datos reales: para horizontal=[X_AXIS,X_AXIS.reverse,
    # Y_AXIS,Y_AXIS.reverse] predice xaxis=[1,0,0], yaxis=[0,0,-1],
    # zaxis=[0,1,0] -coincide con lo medido, la posición coincide dentro de
    # 1mm de diferencia-.
    def interior_top_transform(point, horizontal)
      x_target = horizontal.find { |direction| direction.parallel?(X_AXIS) }
      y_target = horizontal.find { |direction| direction.parallel?(Y_AXIS) }
      Geom::Transformation.axes(point, x_target, Z_AXIS.reverse, y_target)
    end

    # Nodo interior verdadero (4 direcciones) en un nivel intermedio REAL
    # (0<k<nz) — el poste Z se parte ahí (ver create_grid_tubes), igual que
    # en swapped_z_body_transform, pero aquí NO hace falta ninguna pieza
    # nueva ni reasignar roles por búsqueda: el 40 original -sin tocar- ya
    # tiene, de fábrica, exactamente las tres piezas necesarias con la
    # forma correcta -su manguito central YA es continuo/simétrico
    # (`add_sleeve` centrado en Z_AXIS, igual patrón que `add_centered_sleeve`)
    # y sus 4 ramales YA son dos pares independientes (±X, ±Y)-, solo hace
    # falta permutar a qué eje del mundo apunta cada uno: el manguito
    # central -continuo- sirve Y (continuo en cualquier nivel k>=1, ver
    # y_mouth_offset_mm); el par ±Y -dos ramales SEPARADOS- se reorienta a
    # Z, recibiendo cada mitad del poste partido; el par ±X se queda en X
    # -siempre segmentado, cada ramal ya sirve un tramo distinto sin
    # cambios-. No hay ambigüedad de "cuál eje es cuál" que resolver por
    # búsqueda -a diferencia de swapped_z_body_transform/interior_top_
    # transform-: en un nodo de 4 direcciones X e Y SIEMPRE están completos
    # los dos, así que el mapeo es fijo. Verificado con datos reales: el
    # signo exacto de Y (aquí invertido) no importa -la pieza central es
    # simétrica, cualquier signo da el mismo resultado físico-, coincide
    # con lo medido de todos modos.
    def interior_middle_transform(point)
      Geom::Transformation.axes(point, X_AXIS, Z_AXIS, Y_AXIS.reverse)
    end

    def add_oriented_instance(entities, definition, point, direction, tag = nil)
      helper = direction.parallel?(Z_AXIS) ? X_AXIS : Z_AXIS
      x_axis = helper.cross(direction).normalize
      y_axis = direction.cross(x_axis).normalize
      transform = Geom::Transformation.axes(
        point, x_axis, y_axis, direction
      )
      instance = entities.add_instance(definition, transform)
      instance.layer = tag if tag
      definition.attribute_dictionaries&.each do |dictionary|
        dictionary.each_pair do |key, value|
          instance.set_attribute(dictionary.name, key, value)
        end
      end
      instance
    end

    # Busca un tag -Sketchup::Layer- por nombre o lo crea si no existe,
    # para no duplicarlo cada vez que se genera una estructura nueva.
    def get_or_create_tag(model, name)
      model.layers[name] || model.layers.add(name)
    end

    def offset_point(origin, x, y, z)
      Geom::Point3d.new(origin.x + x, origin.y + y, origin.z + z)
    end

    def write_module_attributes(group, params, connector_counts, padding_length_mm = 0.0)
      # Ver create_grid_tubes: X siempre va segmentado (un tramo por módulo,
      # en todos los niveles); Y va segmentado solo en el nivel 0 y continuo
      # -un tramo por columna- en cualquier nivel k>=1; el poste Z se parte
      # en un tramo por nivel (nz tramos por columna, ya no uno continuo).
      nx = params[:modules_x]
      ny = params[:modules_y]
      nz = params[:modules_z]
      tube_counts = {
        x: nx * (ny + 1) * (nz + 1),
        y: (nx + 1) * (ny + nz),
        z: (nx + 1) * (ny + 1) * nz
      }
      total_tubes = tube_counts.values.inject(0, :+)
      # El largo total no depende de en cuántos tramos se corte cada fila/
      # columna/poste -mismo material, solo cambia cuántas piezas son-.
      # spacing_x_mm/spacing_y_mm/spacing_z_mm pueden ser Array -ancho/
      # altura variable por módulo, ej. medios/cuartos de módulo en X o
      # Y-, ahí el total de ese eje es la suma, no nx/ny/nz*valor -mismo
      # patrón que axis_total_mm, usado aquí en vez de porque axis_total_
      # mm regresa Length, y aquí se necesita el Float mm crudo-.
      ancho_x_total_mm = params[:spacing_x_mm].is_a?(Array) ? params[:spacing_x_mm].sum : nx * params[:spacing_x_mm]
      ancho_y_total_mm = params[:spacing_y_mm].is_a?(Array) ? params[:spacing_y_mm].sum : ny * params[:spacing_y_mm]
      altura_z_total_mm = params[:spacing_z_mm].is_a?(Array) ? params[:spacing_z_mm].sum : nz * params[:spacing_z_mm]
      total_length_mm =
        (ny + 1) * (nz + 1) * ancho_x_total_mm +
        (nx + 1) * (nz + 1) * ancho_y_total_mm +
        (nx + 1) * (ny + 1) * (
          BASE_GRID_HEIGHT_MM +
          altura_z_total_mm
        )
      data = {
        'code' => params[:code],
        'modules_x' => params[:modules_x],
        'modules_y' => params[:modules_y],
        'modules_z' => params[:modules_z],
        'spacing_x_mm' => params[:spacing_x_mm],
        'spacing_y_mm' => params[:spacing_y_mm],
        'spacing_z_mm' => params[:spacing_z_mm],
        'tube_count_x' => tube_counts[:x],
        'tube_count_y' => tube_counts[:y],
        'tube_count_z' => tube_counts[:z],
        'tube_count_total' => total_tubes,
        'tube_total_length_mm' => total_length_mm,
        'connector_counts_json' => JSON.generate(connector_counts),
        'base_grid_height_mm' => BASE_GRID_HEIGHT_MM,
        'geometry_basis' => 'ejes normalizados; poste vertical continuo; penetración pendiente de calibración',
        'type' => 'modulo'
      }
      data.merge!(padding_attributes(params, padding_length_mm)) if params[:padding]
      data.each { |key, value| group.set_attribute(DICTIONARY, key, value) }
      group.set_attribute('minorusal_auditor', 'code', params[:code])
      group.set_attribute(
        'minorusal_auditor', 'investment_cost_mxn', data['padding_investment_cost_mxn']
      ) if params[:padding]
    end

    # Costo por tubo terminado de 2.4m: 1.2x el tubo crudo -ver
    # PADDING_RAW_MATERIAL_FACTOR- más cada paso de mano de obra/insumos
    # capturado en capture_padding_costs. El número de tubos necesarios se
    # redondea hacia arriba -no se puede comprar/fabricar una fracción de
    # tubo terminado-.
    def padding_attributes(params, padding_length_mm)
      costs = params[:padding_costs]
      sticks_needed = (padding_length_mm / PADDING_FINISHED_LENGTH_MM).ceil
      cost_per_stick =
        (costs['raw_tube'] * PADDING_RAW_MATERIAL_FACTOR) +
        costs['perforation_labor'] + costs['electricity'] +
        costs['splice_labor'] + costs['wrap_material'] +
        costs['adhesive'] + costs['apply_labor'] + costs['weld_labor']
      {
        'padding_outside_mm' => PADDING_OUTSIDE_MM,
        'padding_inside_mm' => PADDING_INSIDE_MM,
        'padding_total_length_mm' => padding_length_mm.round(1),
        'padding_finished_sticks_needed' => sticks_needed,
        'padding_cost_per_stick_mxn' => cost_per_stick.round(2),
        'padding_investment_cost_mxn' => (sticks_needed * cost_per_stick).round(2),
        'padding_cost_breakdown_json' => JSON.generate(costs)
      }
    end

    # Igual que las líneas de recubrimiento dentro de `write_module_
    # attributes`, pero llamable aparte -para el flujo real del diálogo,
    # donde el recubrimiento ahora se agrega DESPUÉS de construir la
    # estructura y la torre -vía `pad_existing_tubes`-, no durante
    # `create_module`, para poder cubrir la torre también-.
    def write_padding_summary(group, params, padding_length_mm)
      data = padding_attributes(params, padding_length_mm)
      data.each { |key, value| group.set_attribute(DICTIONARY, key, value) }
      group.set_attribute('minorusal_auditor', 'investment_cost_mxn', data['padding_investment_cost_mxn'])
    end

    # Arma el selector de color para `pad_existing_tubes` a partir de los
    # campos `padding_color_mode`/`padding_color_vertical`/
    # `padding_color_horizontal` del diálogo -ver selector.html-, usando
    # STANDARD_COLOR_PALETTE -catálogo real, no PlayIdea::CreadorTubos-.
    def padding_color_selector(params)
      hex_por_label = STANDARD_COLOR_PALETTE.to_h { |c| [c[:label], c[:hex]] }
      if params[:padding_color_mode] == 'vertical_horizontal'
        hex_vertical = hex_por_label[params[:padding_color_vertical]] || STANDARD_COLOR_PALETTE.first[:hex]
        hex_horizontal = hex_por_label[params[:padding_color_horizontal]] || STANDARD_COLOR_PALETTE.first[:hex]
        ->(direction) { direction.parallel?(Z_AXIS) ? hex_vertical : hex_horizontal }
      else
        ->(_direction) { STANDARD_COLOR_PALETTE.sample[:hex] }
      end
    end

    def unique_name(model, base)
      name = base
      index = 2
      while model.definitions[name]
        name = "#{base} (#{index})"
        index += 1
      end
      name
    end

    # Perfora un agujero pasante en la cara superior -en Z=0- de una
    # placa: al dibujar un círculo coplanar y contenido en una cara ya
    # existente, SketchUp crea automáticamente la carita del círculo -un
    # `add_face` explícito ahí devuelve nil, la cara ya existe-, así que
    # solo hay que tomarla -la más chica de las 2 que comparten el borde
    # del círculo- y empujarla hacia adentro del material.
    def solera_punch_hole(entities, center_x_mm, center_y_mm, diam_mm, thickness_mm)
      center = Geom::Point3d.new(center_x_mm.mm, center_y_mm.mm, 0)
      circle_edges = entities.add_circle(center, Z_AXIS, diam_mm.mm / 2.0, 24)
      disc_face = circle_edges.first.faces.min_by(&:area)
      distance = disc_face.normal.z >= 0 ? -thickness_mm.mm : thickness_mm.mm
      disc_face.pushpull(distance)
    end

    # Dibuja un disco -en un `entities` recién creado, no coplanar con
    # nada todavía- y lo extruye. Aquí SÍ hay que crear la cara a mano,
    # porque no hay ninguna cara existente con la que fusionarse.
    def solera_extrude_disc(entities, base_point, diam_mm, height_mm)
      circle_edges = entities.add_circle(base_point, Z_AXIS, diam_mm.mm / 2.0, 16)
      disc_face = circle_edges.first.faces.min_by(&:area) || entities.add_face(circle_edges)
      disc_face.reverse! if disc_face.normal.z < 0
      disc_face.pushpull(height_mm.mm)
    end

    # Placa de solera -con sus 2 autorroscantes (cabeza arriba, apuntan
    # hacia abajo) y su pija #8 al centro (cabeza abajo, apunta hacia
    # arriba) ya incluidos como grupos anidados- lista para instanciar
    # en cada esquina. Una sola definición, cacheada por color en
    # `create_module`/`create_triangle_tower` -todas las soleras de una
    # misma estructura comparten geometría, solo cambia dónde se coloca
    # la instancia-.
    def create_solera_definition(model, color)
      definition = model.definitions.add(unique_name(model, 'SOLERA-1IN'))
      entities = definition.entities

      top_face_pts = [
        Geom::Point3d.new(0, 0, 0),
        Geom::Point3d.new(SOLERA_LENGTH_MM.mm, 0, 0),
        Geom::Point3d.new(SOLERA_LENGTH_MM.mm, SOLERA_WIDTH_MM.mm, 0),
        Geom::Point3d.new(0, SOLERA_WIDTH_MM.mm, 0)
      ]
      face = entities.add_face(top_face_pts)
      face.reverse! if face.normal.z < 0
      face.pushpull(-SOLERA_THICKNESS_MM.mm)

      autorroscante_positions = [
        [SOLERA_END_INSET_MM, SOLERA_WIDTH_MM / 2.0],
        [SOLERA_LENGTH_MM - SOLERA_END_INSET_MM, SOLERA_WIDTH_MM / 2.0]
      ]
      pija_positions = [[SOLERA_LENGTH_MM / 2.0, SOLERA_WIDTH_MM / 2.0]]

      autorroscante_positions.each { |x, y| solera_punch_hole(entities, x, y, SOLERA_AUTORROSCANTE_HOLE_MM, SOLERA_THICKNESS_MM) }
      pija_positions.each { |x, y| solera_punch_hole(entities, x, y, SOLERA_PIJA_HOLE_MM, SOLERA_THICKNESS_MM) }

      PlayIdea::CreadorTubos.apply_material(model, definition, color)

      autorroscante_positions.each_with_index do |(x, y), i|
        screw = entities.add_group
        base_top = Geom::Point3d.new(x.mm, y.mm, 0)
        solera_extrude_disc(screw.entities, base_top, SOLERA_AUTORROSCANTE_HEAD_MM, SOLERA_AUTORROSCANTE_HEAD_THICK_MM)
        solera_extrude_disc(screw.entities, base_top, SOLERA_AUTORROSCANTE_SHAFT_MM, -SOLERA_AUTORROSCANTE_LENGTH_MM)
        screw.name = "TORNILLO-AUTORROSCANTE-#{i + 1}"
      end

      pija_positions.each_with_index do |(x, y), i|
        screw = entities.add_group
        base_bottom = Geom::Point3d.new(x.mm, y.mm, -SOLERA_THICKNESS_MM.mm)
        solera_extrude_disc(screw.entities, base_bottom, SOLERA_PIJA_HEAD_MM, -SOLERA_PIJA_HEAD_THICK_MM)
        solera_extrude_disc(screw.entities, base_bottom, SOLERA_PIJA_SHAFT_MM, SOLERA_PIJA_LENGTH_MM)
        screw.name = "TORNILLO-PIJA8-#{i + 1}"
      end

      definition.set_attribute(DICTIONARY, 'type', 'solera')
      definition.set_attribute(DICTIONARY, 'width_mm', SOLERA_WIDTH_MM)
      definition.set_attribute(DICTIONARY, 'length_mm', SOLERA_LENGTH_MM)
      definition.set_attribute(DICTIONARY, 'thickness_mm', SOLERA_THICKNESS_MM)
      definition.set_attribute(DICTIONARY, 'color', color)
      definition
    end

    def solera_world_transform(point, offset_mm, xaxis, yaxis)
      origin = point + Geom::Vector3d.new(offset_mm[0].mm, offset_mm[1].mm, offset_mm[2].mm)
      Geom::Transformation.axes(origin, xaxis, yaxis, Z_AXIS)
    end

    # Soleras de esquina de cuadro, en TODA la cuadrícula de `params`, en
    # todos los niveles menos el último -su función es fijar una
    # plataforma que se agrega después, y no hace falta en el nivel de
    # arriba, donde no hay nada más encima-. Cada cuadro (i0,j0) coloca
    # 2 -esquinas (i0+1,j0) y (i0,j0+1), la ANTI-diagonal, ver la nota
    # junto a las constantes SOLERA_*-.
    # `axis_cumulative_mm` -en vez de `(i0+1)*sx`/`j0*sy` directo- porque
    # spacing_x_mm/spacing_y_mm ahora pueden ser Array -medio módulo
    # activo en ese eje, ver create_grid_tubes-. El offset/rotación
    # calibrado de cada solera (SOLERA_SQUARE_OFFSET_1/2) es una medida
    # FIJA relativa a SU PROPIA esquina real -no depende del ancho de la
    # celda-, así que sigue aplicando igual aunque la celda sea angosta;
    # lo único que cambia es DÓNDE cae esa esquina. Confirmado con datos
    # reales SOLO para celdas cuadradas -ancho normal en ambos ejes-; para
    # una celda angosta -medio módulo- es la misma fórmula extrapolada,
    # sin verificar aún contra una pieza real puesta a mano ahí.
    def place_square_soleras(entities, params, origin, solera_def)
      sx_mm = params[:spacing_x_mm]
      sy_mm = params[:spacing_y_mm]
      sz = spacing_z_length(params[:spacing_z_mm])
      nx = params[:modules_x]
      ny = params[:modules_y]
      nz = params[:modules_z]
      count = 0
      (0...nz).each do |k|
        z = grid_level_z(k, nz, sz)
        (0...nx).each do |i0|
          (0...ny).each do |j0|
            p1 = offset_point(origin, axis_cumulative_mm(i0 + 1, sx_mm), axis_cumulative_mm(j0, sy_mm), z)
            p2 = offset_point(origin, axis_cumulative_mm(i0, sx_mm), axis_cumulative_mm(j0 + 1, sy_mm), z)
            entities.add_instance(solera_def, solera_world_transform(p1, SOLERA_SQUARE_OFFSET_1, SOLERA_STANDARD_XAXIS, SOLERA_STANDARD_YAXIS))
            entities.add_instance(solera_def, solera_world_transform(p2, SOLERA_SQUARE_OFFSET_2, SOLERA_STANDARD_XAXIS, SOLERA_STANDARD_YAXIS))
            count += 2
          end
        end
      end
      count
    end

    # Soleras de la torre triangular: 1 en cada esquina de 45° -donde va
    # la pata, CON-10- por escalón, más 1 en la esquina de 90° -SOLO
    # para escalones tipo "sw", la única con dato real medido; los
    # escalones "ne" se quedan sin su solera de 90° hasta tener una
    # pieza real de esa esquina para medir, no se adivina-.
    def place_triangle_soleras(entities, tower_params, tower_origin, solera_def)
      order = TRIANGLE_CORNER_ORDER
      step_heights_mm = tower_params[:step_heights_mm] ||
        Array.new(tower_params[:steps]) { |step| tower_params[:start_height_mm] + step * tower_params[:step_spacing_mm] }
      count = 0
      step_heights_mm.each_with_index do |z_mm, step|
        step_corner = step.even? ? tower_params[:right_angle_corner] :
          order[(order.index(tower_params[:right_angle_corner]) + 2) % 4]
        z = z_mm.mm
        corners = triangle_cell_corners(tower_origin, tower_params, z)
        near, far = diagonal_near_far_corners(step_corner, corners)
        ra_point = corners[step_corner]

        case step_corner
        when :sw
          entities.add_instance(solera_def, solera_world_transform(near, SOLERA_TRIANGLE_NEAR_SW, SOLERA_STANDARD_XAXIS, SOLERA_STANDARD_YAXIS))
          entities.add_instance(solera_def, solera_world_transform(far, SOLERA_TRIANGLE_FAR_SW, SOLERA_STANDARD_XAXIS, SOLERA_STANDARD_YAXIS))
          entities.add_instance(solera_def, solera_world_transform(ra_point, SOLERA_TRIANGLE_RA_SW, SOLERA_RA_XAXIS, SOLERA_RA_YAXIS))
          count += 3
        when :ne
          entities.add_instance(solera_def, solera_world_transform(near, SOLERA_TRIANGLE_NEAR_NE, SOLERA_STANDARD_XAXIS, SOLERA_STANDARD_YAXIS))
          entities.add_instance(solera_def, solera_world_transform(far, SOLERA_TRIANGLE_FAR_NE, SOLERA_STANDARD_XAXIS, SOLERA_STANDARD_YAXIS))
          count += 2
        end
      end
      count
    end

    # Rectángulo con las 4 puntas cortadas -PLATFORM_CORNER_CHAMFER_MM
    # medido desde cada esquina, sobre cada lado, IGUAL sin importar el
    # tamaño de la plataforma: es la misma esquina de poste/protector la
    # que hay que despejar en cualquier tamaño-. 8 puntos en vez de 4.
    # Coordenadas LOCALES -centradas en (0,0)-, para la geometría de
    # create_platform_definition, no coordenadas de mundo.
    def platform_footprint_points(width_mm, depth_mm, z0_mm)
      half_w = (width_mm / 2.0).mm
      half_d = (depth_mm / 2.0).mm
      c = PLATFORM_CORNER_CHAMFER_MM.mm
      z0 = z0_mm.mm
      [
        Geom::Point3d.new(-half_w + c, -half_d, z0),
        Geom::Point3d.new(half_w - c, -half_d, z0),
        Geom::Point3d.new(half_w, -half_d + c, z0),
        Geom::Point3d.new(half_w, half_d - c, z0),
        Geom::Point3d.new(half_w - c, half_d, z0),
        Geom::Point3d.new(-half_w + c, half_d, z0),
        Geom::Point3d.new(-half_w, half_d - c, z0),
        Geom::Point3d.new(-half_w, -half_d + c, z0)
      ]
    end

    # Una capa = el contorno de platform_footprint_points extruido hacia
    # +Z desde z0_mm. Solo colorea las caras que todavía no tienen
    # material -así una capa nunca repinta la de abajo-.
    def platform_add_layer(model, entities, width_mm, depth_mm, z0_mm, height_mm, color)
      face = entities.add_face(platform_footprint_points(width_mm, depth_mm, z0_mm))
      face.reverse! if face.normal.z < 0
      face.pushpull(height_mm.mm)

      material_name = "PlayIdea Plataforma - #{color.red}-#{color.green}-#{color.blue}"
      material = model.materials[material_name] || model.materials.add(material_name)
      material.color = color
      entities.grep(Sketchup::Face).each do |f|
        next if f.material
        f.material = material
        f.back_material = material
      end
    end

    # El vinil envuelve toda la superficie expuesta -las caras laterales
    # y la cara superior-, dejando la cara inferior con su color de
    # triplay -queda expuesta, como en la pieza real-. Sobreescribe a
    # propósito el color de capa asignado en platform_add_layer. `hex`
    # -de STANDARD_COLOR_PALETTE- usa el mismo material "Color #HEX"
    # cacheado en `model.materials` que ya usa apply_hex_material para
    # los protectores, para que coincida exacto si algún protector de la
    # misma estructura cayó en el mismo color.
    def platform_wrap_with_vinil(model, entities, hex)
      material_name = "Color ##{hex}"
      material = model.materials[material_name] || model.materials.add(material_name)
      material.color = Sketchup::Color.new(hex[0..1].to_i(16), hex[2..3].to_i(16), hex[4..5].to_i(16))
      top_z = PLATFORM_TOTAL_HEIGHT_MM.mm
      entities.grep(Sketchup::Face).each do |face|
        normal = face.normal
        lateral = normal.z.abs < 0.001
        top = normal.z > 0.999 && face.vertices.first.position.z >= (top_z - 0.01.mm)
        next unless lateral || top
        face.material = material
        face.back_material = material
      end
    end

    # Código legible por tamaño -en cm, redondeado-, ej. "PLATAFORMA-
    # 122X122" para la completa, "PLATAFORMA-61X122"/"PLATAFORMA-122X61"
    # para la mitad -donde cruza un medio módulo con uno completo-,
    # "PLATAFORMA-61X61" para el cuarto -donde cruzan dos medios módulos-.
    def platform_code_for(width_mm, depth_mm)
      "PLATAFORMA-#{(width_mm / 10.0).round}X#{(depth_mm / 10.0).round}"
    end

    # Definición compartida por tamaño -una geometría por combinación de
    # width_mm/depth_mm, reusada por cada instancia de ese tamaño vía
    # entities.add_instance, mismo patrón que create_solera_definition-.
    # El nombre de la DEFINICIÓN -no de cada instancia- codifica el
    # tamaño, para que un futuro conteo en cotizador_playidea la detecte
    # por patrón igual que ya hace con SOLERA-1IN -las instancias nunca
    # traen nombre propio, heredan el de su definición-.
    def create_platform_definition(model, width_mm, depth_mm, vinil_hex)
      definition = model.definitions.add(unique_name(model, platform_code_for(width_mm, depth_mm)))
      entities = definition.entities

      z = 0.0
      platform_add_layer(model, entities, width_mm, depth_mm, z, PLATFORM_TRIPLAY_MM, PLATFORM_WOOD_COLOR)
      z += PLATFORM_TRIPLAY_MM
      platform_add_layer(model, entities, width_mm, depth_mm, z, PLATFORM_FOAM_1IN_MM, PLATFORM_FOAM_COLOR)
      z += PLATFORM_FOAM_1IN_MM
      platform_add_layer(model, entities, width_mm, depth_mm, z, PLATFORM_FOAM_HALF_MM, PLATFORM_FOAM_COLOR)

      platform_wrap_with_vinil(model, entities, vinil_hex)

      definition.set_attribute(DICTIONARY, 'type', 'plataforma')
      definition.set_attribute(DICTIONARY, 'width_mm', width_mm)
      definition.set_attribute(DICTIONARY, 'depth_mm', depth_mm)
      definition.set_attribute(DICTIONARY, 'total_height_mm', PLATFORM_TOTAL_HEIGHT_MM)
      definition
    end

    # Tamaño de plataforma -en mm- para un cuadro de `width_mm` real de
    # ancho -PLATFORM_WIDTH_MM si es un módulo completo, la mitad
    # (PLATFORM_WIDTH_MM/2) si es medio módulo-. `full_module_mm` es el
    # ancho real de un módulo completo EN ESTA estructura -para comparar
    # contra medidas reales de celda, no contra el tamaño de plataforma-.
    # `nil` si la celda no es ni completa ni medio módulo -tamaño de
    # módulo no estándar, sin plataforma que le quede, ver place_
    # platforms-.
    def platform_dimension_for_cell(cell_mm, full_module_mm, full_platform_mm)
      if (cell_mm - full_module_mm).abs <= PLATFORM_MODULE_TOLERANCE_MM
        full_platform_mm
      elsif (cell_mm - full_module_mm / 2.0).abs <= PLATFORM_MODULE_TOLERANCE_MM
        full_platform_mm / 2.0
      end
    end

    # Coloca una plataforma al centro de cada cuadro de módulo -completo
    # o medio módulo, en cualquier combinación de los dos ejes- en todos
    # los niveles menos el último -la plataforma es el piso; el nivel de
    # arriba no tiene nada encima, así que no necesita piso propio,
    # mismo criterio que place_square_soleras-. Si el módulo de la
    # estructura no es -aprox- el estándar (DEFAULT_SPACING_M), no
    # coloca ninguna -el corte de puntas está calculado solo para ese
    # tamaño-. Cachea una definición por tamaño real usado -normalmente
    # 1 a 4 tamaños: completo, medio en X, medio en Y, cuarto-.
    def place_platforms(entities, params, origin, model)
      sx_mm = params[:spacing_x_mm]
      sy_mm = params[:spacing_y_mm]
      sz = spacing_z_length(params[:spacing_z_mm])
      nx = params[:modules_x]
      ny = params[:modules_y]
      nz = params[:modules_z]
      tower = params[:tower]
      full_x_mm = sx_mm.is_a?(Array) ? sx_mm.max : sx_mm
      full_y_mm = sy_mm.is_a?(Array) ? sy_mm.max : sy_mm
      standard_mm = DEFAULT_SPACING_M * 1000.0
      return 0 if (full_x_mm - standard_mm).abs > PLATFORM_MODULE_TOLERANCE_MM
      return 0 if (full_y_mm - standard_mm).abs > PLATFORM_MODULE_TOLERANCE_MM

      cache = {}
      count = 0
      (0...nz).each do |k|
        z = grid_level_z(k, nz, sz) + PLATFORM_Z_LIFT_MM.mm
        (0...nx).each do |i0|
          (0...ny).each do |j0|
            cell_width_mm = axis_column_width_mm(i0, sx_mm)
            cell_depth_mm = axis_column_width_mm(j0, sy_mm)
            plat_width_mm = platform_dimension_for_cell(cell_width_mm, full_x_mm, PLATFORM_WIDTH_MM)
            plat_depth_mm = platform_dimension_for_cell(cell_depth_mm, full_y_mm, PLATFORM_DEPTH_MM)
            next if plat_width_mm.nil? || plat_depth_mm.nil?
            cell_x_mm = axis_cumulative_mm(i0, sx_mm).to_mm
            cell_y_mm = axis_cumulative_mm(j0, sy_mm).to_mm
            # La columna donde se paró la torre triangular no lleva
            # plataforma -la torre ocupa ese cuadro con su propio tubo
            # diagonal/escalones, una plataforma ahí chocaría con eso-,
            # EXCEPTO en el nivel 0 -la base-: el primer escalón siempre
            # arranca en TOWER_FIRST_STEP_HEIGHT_MM (500mm), por encima
            # del nivel 0 de la cuadrícula, así que la plataforma de la
            # base no choca con nada de la torre -confirmado con el
            # usuario: "la única plataforma que sí debe ir en la torre
            # debe estar en la base nadamás"-. `tower` solo trae el
            # offset acumulado de su esquina -no i/j crudos, ver tower_
            # params_from_dialog-, así que se compara contra el offset
            # de cada cuadro en vez de contra un índice.
            if tower && k.positive?
              next if (cell_x_mm - tower[:offset_x_mm]).abs < PLATFORM_MODULE_TOLERANCE_MM &&
                      (cell_y_mm - tower[:offset_y_mm]).abs < PLATFORM_MODULE_TOLERANCE_MM
            end
            # Color al azar de STANDARD_COLOR_PALETTE, uno independiente
            # por plataforma -mismo criterio que padding_color_selector
            # en modo "aleatorio"-. Se sortea ANTES de la llave de caché
            # para que sea de verdad al azar por pieza; si dos
            # plataformas del mismo tamaño caen en el mismo color
            # comparten definición, si no, cada combinación tamaño+color
            # nueva crea la suya.
            hex = STANDARD_COLOR_PALETTE.sample[:hex]
            key = [plat_width_mm, plat_depth_mm, hex]
            platform_def = cache[key] ||= create_platform_definition(model, plat_width_mm, plat_depth_mm, hex)
            center_x = axis_cumulative_mm(i0, sx_mm) + (cell_width_mm / 2.0).mm
            center_y = axis_cumulative_mm(j0, sy_mm) + (cell_depth_mm / 2.0).mm
            center = offset_point(origin, center_x, center_y, z)
            entities.add_instance(platform_def, Geom::Transformation.new(center))
            count += 1
          end
        end
      end
      count
    end

    # Cateto de la plataforma triangular -misma medida que el lado de la
    # plataforma cuadrada-. Ángulo recto entre los 2 catetos; la
    # hipotenusa sale sola de la geometría (no es una medida fija que se
    # calibre aparte).
    PLATFORM_TRIANGLE_LEG_MM = PLATFORM_WIDTH_MM

    # Triángulo rectángulo con las 3 puntas cortadas -mismo
    # PLATFORM_CORNER_CHAMFER_MM que la plataforma cuadrada, medido
    # sobre cada arista que toca esa punta-, para despejar el protector
    # de esponja de los 3 postes de la celda -el de la escuadra y los 2
    # extremos de catetos-. Coordenadas LOCALES: el ángulo recto queda
    # en el origen, un cateto sobre +X, el otro sobre +Y -así,
    # instanciada con Geom::Transformation.axes(ra_point, hacia "near",
    # hacia "far", Z_AXIS), cada cateto apunta solo al poste que le
    # corresponde-.
    def platform_triangle_footprint_points(leg_mm, z0_mm)
      leg = leg_mm.mm
      c = PLATFORM_CORNER_CHAMFER_MM.mm
      diag = c / Math.sqrt(2)
      z0 = z0_mm.mm
      [
        Geom::Point3d.new(c, 0, z0),
        Geom::Point3d.new(leg - c, 0, z0),
        Geom::Point3d.new(leg - diag, diag, z0),
        Geom::Point3d.new(diag, leg - diag, z0),
        Geom::Point3d.new(0, leg - c, z0),
        Geom::Point3d.new(0, c, z0)
      ]
    end

    def platform_triangle_add_layer(model, entities, leg_mm, z0_mm, height_mm, color)
      face = entities.add_face(platform_triangle_footprint_points(leg_mm, z0_mm))
      face.reverse! if face.normal.z < 0
      face.pushpull(height_mm.mm)

      material_name = "PlayIdea Plataforma - #{color.red}-#{color.green}-#{color.blue}"
      material = model.materials[material_name] || model.materials.add(material_name)
      material.color = color
      entities.grep(Sketchup::Face).each do |f|
        next if f.material
        f.material = material
        f.back_material = material
      end
    end

    # Definición compartida de la plataforma triangular -una sola
    # geometría, reusada por cada escalón de la torre-. Mismo criterio
    # de capas/vinil que create_platform_definition, solo cambia el
    # contorno.
    def create_triangle_platform_definition(model, leg_mm, vinil_hex)
      definition = model.definitions.add(unique_name(model, "PLATAFORMA-TRIANGULO-#{(leg_mm / 10.0).round}"))
      entities = definition.entities

      z = 0.0
      platform_triangle_add_layer(model, entities, leg_mm, z, PLATFORM_TRIPLAY_MM, PLATFORM_WOOD_COLOR)
      z += PLATFORM_TRIPLAY_MM
      platform_triangle_add_layer(model, entities, leg_mm, z, PLATFORM_FOAM_1IN_MM, PLATFORM_FOAM_COLOR)
      z += PLATFORM_FOAM_1IN_MM
      platform_triangle_add_layer(model, entities, leg_mm, z, PLATFORM_FOAM_HALF_MM, PLATFORM_FOAM_COLOR)

      platform_wrap_with_vinil(model, entities, vinil_hex)

      definition.set_attribute(DICTIONARY, 'type', 'plataforma_triangulo')
      definition.set_attribute(DICTIONARY, 'leg_mm', leg_mm)
      definition.set_attribute(DICTIONARY, 'total_height_mm', PLATFORM_TOTAL_HEIGHT_MM)
      definition
    end

    # Una plataforma triangular por escalón de la torre -mismo criterio
    # de "solo módulo estándar" que place_platforms, aquí contra
    # cell_x_mm/cell_y_mm de la torre en vez de spacing_x/y_mm de la
    # cuadrícula-. A diferencia de place_triangle_soleras -que usa
    # offsets calibrados distintos por tipo de esquina, y por eso solo
    # cubre "sw" completo y dejaba "ne" sin la pieza de 90°-, aquí se
    # arma la geometría directo desde los 3 puntos reales de la celda
    # -near/far/ra_point-, sin ningún offset a mano, así que cubre
    # cualquier step_corner válido -sw/ne, ver VALIDATED_TOWER_RIGHT_
    # ANGLE_CORNERS- por igual.
    def place_triangle_platforms(entities, tower_params, tower_origin, model)
      standard_mm = DEFAULT_SPACING_M * 1000.0
      return 0 if (tower_params[:cell_x_mm] - standard_mm).abs > PLATFORM_MODULE_TOLERANCE_MM
      return 0 if (tower_params[:cell_y_mm] - standard_mm).abs > PLATFORM_MODULE_TOLERANCE_MM

      cache = {}
      step_heights_mm = tower_params[:step_heights_mm] ||
        Array.new(tower_params[:steps]) { |step| tower_params[:start_height_mm] + step * tower_params[:step_spacing_mm] }
      order = TRIANGLE_CORNER_ORDER
      count = 0
      step_heights_mm.each_with_index do |z_mm, step|
        step_corner = step.even? ? tower_params[:right_angle_corner] :
          order[(order.index(tower_params[:right_angle_corner]) + 2) % 4]
        z = z_mm.mm + PLATFORM_Z_LIFT_MM.mm
        corners = triangle_cell_corners(tower_origin, tower_params, z)
        near, far = diagonal_near_far_corners(step_corner, corners)
        ra_point = corners[step_corner]

        # Color al azar por escalón, mismo criterio que place_platforms.
        hex = STANDARD_COLOR_PALETTE.sample[:hex]
        triangle_def = cache[hex] ||= create_triangle_platform_definition(model, PLATFORM_TRIANGLE_LEG_MM, hex)

        xaxis = (near - ra_point).normalize
        yaxis = (far - ra_point).normalize
        transform = Geom::Transformation.axes(ra_point, xaxis, yaxis, Z_AXIS)
        entities.add_instance(triangle_def, transform)
        count += 1
      end
      count
    end

    # --- Red de nylon de seguridad ---------------------------------

    def net_png_chunk(type, data)
      chunk = type.dup.force_encoding(Encoding::ASCII_8BIT) + data
      [data.bytesize].pack('N') + chunk + [Zlib.crc32(chunk)].pack('N')
    end

    def net_write_png(path, width, height, pixels)
      raw = String.new(encoding: Encoding::ASCII_8BIT)
      height.times do |y|
        raw << 0.chr
        width.times do |x|
          raw << pixels[y][x].pack('C4')
        end
      end
      compressed = Zlib::Deflate.deflate(raw, 9)

      png = String.new(encoding: Encoding::ASCII_8BIT)
      png << [137, 80, 78, 71, 13, 10, 26, 10].pack('C8')
      png << net_png_chunk('IHDR', [width, height, 8, 6, 0, 0, 0].pack('N2C5'))
      png << net_png_chunk('IDAT', compressed)
      png << net_png_chunk('IEND', String.new(encoding: Encoding::ASCII_8BIT))
      File.open(path, 'wb') { |f| f.write(png) }
    end

    # Cuadrícula RECTA -horizontal/vertical, no en rombo- con nudo
    # redondo en cada cruce, hilo opaco sobre fondo transparente. Mismo
    # patrón validado en scripts/red_nylon_playidea.rb.
    def net_write_texture(path)
      half_line = NET_LINE_WIDTH_PX / 2.0
      pixels = Array.new(NET_TILE_PX) { Array.new(NET_TILE_PX) }
      NET_TILE_PX.times do |y|
        NET_TILE_PX.times do |x|
          dx = [x % NET_TILE_PX, NET_TILE_PX - (x % NET_TILE_PX)].min
          dy = [y % NET_TILE_PX, NET_TILE_PX - (y % NET_TILE_PX)].min
          on_line = dx <= half_line || dy <= half_line
          on_knot = Math.sqrt((dx**2) + (dy**2)) <= NET_KNOT_RADIUS_PX
          pixels[y][x] = (on_line || on_knot) ? NET_CORD_COLOR : NET_GAP_COLOR
        end
      end
      net_write_png(path, NET_TILE_PX, NET_TILE_PX, pixels)
    end

    # Se regenera cada vez -mismo criterio que el script suelto-, para
    # que un ajuste al patrón/tamaño nunca se quede viendo una versión
    # vieja cacheada por nombre de archivo o de material.
    def net_texture_material(model)
      name = 'PlayIdea Red Nylon Negra'
      path = File.join(Sketchup.temp_dir, 'playidea_red_nylon_tile.png')
      net_write_texture(path)

      material = model.materials[name] || model.materials.add(name)
      material.texture = path
      material.texture.size = NET_ABERTURA_MM.mm
      material.alpha = 1.0
      material
    end

    def net_rod_material(model)
      name = 'PlayIdea Redondo Pulido'
      material = model.materials[name] || model.materials.add(name)
      material.color = NET_ROD_COLOR
      material
    end

    # Un tramo recto de redondo pulido entre 2 puntos -mismo patrón que
    # solera_extrude_disc, generalizado a una dirección arbitraria en
    # vez de solo +Z-. Solo colorea caras nuevas, para no repintar los
    # otros 3 lados del marco ya construidos en el mismo `entities`.
    def net_add_rod(entities, p1, p2, diameter_mm, material)
      direction = p2 - p1
      return if direction.length < 0.001.mm
      circle_edges = entities.add_circle(p1, direction, diameter_mm.mm / 2.0, 12)
      face = circle_edges.first.faces.min_by(&:area) || entities.add_face(circle_edges)
      face.reverse! if face.normal.dot(direction) < 0
      face.pushpull(direction.length)
      entities.grep(Sketchup::Face).each do |f|
        next if f.material
        f.material = material
        f.back_material = material
      end
    end

    def net_code_for(width_mm, height_mm)
      "RED-#{(width_mm / 10.0).round}X#{(height_mm / 10.0).round}"
    end

    # Definición compartida por tamaño -paño de malla + marco de
    # redondo pulido en los 4 lados-. Geometría LOCAL en el plano XZ
    # -ancho en X, alto en Z-, para que place_nets solo tenga que
    # orientar el eje X local hacia donde corresponda en el mundo.
    def create_net_definition(model, width_mm, height_mm)
      definition = model.definitions.add(unique_name(model, net_code_for(width_mm, height_mm)))
      entities = definition.entities

      w = width_mm.mm
      h = height_mm.mm
      pts = [
        Geom::Point3d.new(0, 0, 0),
        Geom::Point3d.new(w, 0, 0),
        Geom::Point3d.new(w, 0, h),
        Geom::Point3d.new(0, 0, h)
      ]
      face = entities.add_face(pts)
      face.reverse! if face.normal.y > 0
      texture = net_texture_material(model)
      face.material = texture
      face.back_material = texture

      rod = net_rod_material(model)
      net_add_rod(entities, pts[0], pts[1], NET_ROD_DIAMETER_MM, rod)
      net_add_rod(entities, pts[3], pts[2], NET_ROD_DIAMETER_MM, rod)
      net_add_rod(entities, pts[0], pts[3], NET_ROD_DIAMETER_MM, rod)
      net_add_rod(entities, pts[1], pts[2], NET_ROD_DIAMETER_MM, rod)

      definition.set_attribute(DICTIONARY, 'type', 'red_nylon')
      definition.set_attribute(DICTIONARY, 'width_mm', width_mm)
      definition.set_attribute(DICTIONARY, 'height_mm', height_mm)
      definition
    end

    # Coloca un paño de malla en CADA cara vertical de la cuadrícula,
    # en las 2 orientaciones -perpendicular a X y perpendicular a Y-, en
    # todos los niveles -a diferencia de la plataforma, aquí SÍ incluye
    # el último nivel: es una malla de seguridad, no un piso-. Solo
    # cuadros de módulo COMPLETO -mismo criterio que place_platforms-.
    # "Por ahora en toda la cuadrícula, se quita a mano donde no haga
    # falta" -confirmado con el usuario, no hay lógica de perímetro-.
    # `entrada` -opcional, params[:entrada]- es `{edge:, index:}`, MISMO
    # significado que params[:tobogan_edge]/params[:tobogan_index] -edge en
    # x_near/x_far/y_near/y_far, index es la fila -edges X- o columna
    # -edges Y- de la celda de orilla elegida-. Identifica el ÚNICO paño
    # vertical del NIVEL 0 -planta baja, siempre- que se debe omitir para
    # dejar libre el paso de entrada a la estructura.
    def net_panel_is_entrada?(entrada, k, orientation, boundary_index, cell_index)
      return false unless entrada && k.zero?

      case entrada[:edge]
      when :x_near
        orientation == :perp_x && boundary_index.zero? && cell_index == entrada[:index]
      when :x_far
        orientation == :perp_x && boundary_index == entrada[:x_boundary] && cell_index == entrada[:index]
      when :y_near
        orientation == :perp_y && boundary_index.zero? && cell_index == entrada[:index]
      when :y_far
        orientation == :perp_y && boundary_index == entrada[:y_boundary] && cell_index == entrada[:index]
      else
        false
      end
    end

    def place_nets(entities, params, origin, model)
      sx_mm = params[:spacing_x_mm]
      sy_mm = params[:spacing_y_mm]
      sz = spacing_z_length(params[:spacing_z_mm])
      szmm = params[:spacing_z_mm]
      nx = params[:modules_x]
      ny = params[:modules_y]
      nz = params[:modules_z]
      entrada = params[:entrada]
      entrada = entrada.merge(x_boundary: nx, y_boundary: ny) if entrada

      # A diferencia de la plataforma -tabla manufacturada de tamaño
      # fijo, 1.22x1.22-, la malla se corta a la medida exacta de CADA
      # cuadro -grande, chico, medio módulo, cualquiera-, así que no hay
      # ninguna restricción de tamaño de módulo aquí: create_net_
      # definition arma la textura+marco al tamaño que le pidan.
      cache = {}
      count = 0
      (0...nz).each do |k|
        z0 = grid_level_z(k, nz, sz)
        height_mm = szmm.is_a?(Array) ? szmm[k] : szmm
        next if height_mm.nil?

        # Perpendiculares a X -franja Y-Z-, una línea i por cada frontera
        # de columna (0..nx).
        (0..nx).each do |i|
          x_mm = axis_cumulative_mm(i, sx_mm)
          (0...ny).each do |j0|
            next if net_panel_is_entrada?(entrada, k, :perp_x, i, j0)
            depth_mm = axis_column_width_mm(j0, sy_mm)
            key = [depth_mm, height_mm]
            net_def = cache[key] ||= create_net_definition(model, depth_mm, height_mm)
            base = offset_point(origin, x_mm, axis_cumulative_mm(j0, sy_mm), z0)
            transform = Geom::Transformation.axes(base, Y_AXIS, X_AXIS, Z_AXIS)
            entities.add_instance(net_def, transform)
            count += 1
          end
        end

        # Perpendiculares a Y -franja X-Z-, una línea j por cada frontera
        # de fila (0..ny). Local X ya coincide con mundo X -sin rotar-.
        (0..ny).each do |j|
          y_mm = axis_cumulative_mm(j, sy_mm)
          (0...nx).each do |i0|
            next if net_panel_is_entrada?(entrada, k, :perp_y, j, i0)
            width_mm = axis_column_width_mm(i0, sx_mm)
            key = [width_mm, height_mm]
            net_def = cache[key] ||= create_net_definition(model, width_mm, height_mm)
            base = offset_point(origin, axis_cumulative_mm(i0, sx_mm), y_mm, z0)
            entities.add_instance(net_def, Geom::Transformation.new(base))
            count += 1
          end
        end
      end

      # Techo: paños horizontales sobre CADA cuadro del nivel de arriba
      # -nz, el único que las plataformas nunca cubren-, cualquier
      # tamaño de cuadro también. Local X -ancho de create_net_
      # definition- va hacia mundo X, local Z -alto- va hacia mundo Y,
      # así el paño queda acostado con su normal hacia +Z.
      z_top = grid_level_z(nz, nz, sz)
      (0...nx).each do |i0|
        width_mm = axis_column_width_mm(i0, sx_mm)
        (0...ny).each do |j0|
          depth_mm = axis_column_width_mm(j0, sy_mm)
          key = [width_mm, depth_mm]
          net_def = cache[key] ||= create_net_definition(model, width_mm, depth_mm)
          base = offset_point(origin, axis_cumulative_mm(i0, sx_mm), axis_cumulative_mm(j0, sy_mm), z_top)
          transform = Geom::Transformation.axes(base, X_AXIS, Z_AXIS, Y_AXIS)
          entities.add_instance(net_def, transform)
          count += 1
        end
      end
      count
    end

    # Coloca la estructura y, si `params[:tower]` viene lleno -checkbox
    # "Agregar torre de pisos triangulares" marcado en el mismo diálogo de
    # crear estructura-, encadena UN SEGUNDO clic para la esquina de la
    # torre, todo dentro de la MISMA herramienta/operación de colocación
    # -sin ventanas ni confirmaciones de por medio-, para poder crear
    # estructura + torre juntas en un solo flujo.
    class ModulePlacementTool
      def initialize(params)
        @params = params
        @input = Sketchup::InputPoint.new
      end

      def activate
        Sketchup.set_status_text(
          'Haz clic para colocar la esquina inferior del módulo.',
          SB_PROMPT
        )
      end

      def onMouseMove(_flags, x, y, view)
        @input.pick(view, x, y)
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @input.pick(view, x, y)
        return unless @input.valid?
        # El recubrimiento -si se pidió- NO se hace aquí dentro de
        # create_module -ese es el camino viejo, solo cuadrícula, nunca ve
        # la torre-: se pasa padding:false y se aplica DESPUÉS con
        # `pad_existing_tubes`, una vez que estructura Y torre existen,
        # para que la torre también quede cubierta.
        structure = ConstructorModulos.create_module(@params.merge(padding: false), @input.position)
        tower_group = nil
        if @params[:tower]
          tower = @params[:tower]
          tower_origin = ConstructorModulos.offset_point(
            @input.position, tower[:offset_x_mm].mm, tower[:offset_y_mm].mm, 0
          )
          tower_group = ConstructorModulos.create_triangle_tower(tower, tower_origin)
        end
        if @params[:padding]
          color_selector = ConstructorModulos.padding_color_selector(@params)
          model = Sketchup.active_model
          model.start_operation('Recubrir con espuma', true)
          total_length_mm = ConstructorModulos.pad_existing_tubes(structure.entities, model, color_selector)
          total_length_mm += ConstructorModulos.pad_existing_tubes(tower_group.entities, model, color_selector) if tower_group
          ConstructorModulos.write_padding_summary(structure, @params, total_length_mm)
          model.commit_operation
        end
        if @params[:solera]
          model = Sketchup.active_model
          model.start_operation('Agregar soleras', true)
          solera_def = ConstructorModulos.create_solera_definition(model, @params[:color])
          solera_count = ConstructorModulos.place_square_soleras(structure.entities, @params, @input.position, solera_def)
          solera_count += ConstructorModulos.place_triangle_soleras(tower_group.entities, @params[:tower], tower_origin, solera_def) if tower_group
          structure.set_attribute(ConstructorModulos::DICTIONARY, 'solera_count', solera_count)
          model.commit_operation
        end
        if @params[:platform]
          model = Sketchup.active_model
          model.start_operation('Agregar plataformas', true)
          platform_count = ConstructorModulos.place_platforms(structure.entities, @params, @input.position, model)
          structure.set_attribute(ConstructorModulos::DICTIONARY, 'platform_count', platform_count)
          if tower_group
            triangle_count = ConstructorModulos.place_triangle_platforms(tower_group.entities, @params[:tower], tower_origin, model)
            tower_group.set_attribute(ConstructorModulos::DICTIONARY, 'platform_count', triangle_count)
          end
          model.commit_operation
        end
        if @params[:net]
          model = Sketchup.active_model
          model.start_operation('Agregar malla de seguridad', true)
          net_count = ConstructorModulos.place_nets(structure.entities, @params, @input.position, model)
          structure.set_attribute(ConstructorModulos::DICTIONARY, 'net_count', net_count)
          model.commit_operation
        end
        if @params[:tobogan]
          tobogan_result = Tobogan::Builder.attach(@params, @input.position)
          # Pedido del usuario: la estructura DEL TOBOGÁN -poste, brazos,
          # ligas a la cuadrícula- también se recubre con espuma/cinchos,
          # de los MISMOS colores ya elegidos para el resto -mismo
          # `color_selector`, misma `pad_existing_tubes` que ya usan la
          # cuadrícula y la torre-. Las piezas de fibra de vidrio del
          # tobogán mismo -codos, recto, salida, aro- NO llevan
          # recubrimiento -son otro material, y sus nombres de definición
          # no empiezan con 'TUB-', así que pad_existing_tubes ya las
          # ignora solas-.
          if @params[:padding] && tobogan_result
            model = Sketchup.active_model
            model.start_operation('Recubrir tobogán con espuma', true)
            tobogan_color_selector = ConstructorModulos.padding_color_selector(@params)
            ConstructorModulos.pad_existing_tubes(tobogan_result[:tobogan_group].entities, model, tobogan_color_selector)
            if tobogan_result[:link_group]
              ConstructorModulos.pad_existing_tubes(tobogan_result[:link_group].entities, model, tobogan_color_selector)
            end
            model.commit_operation
          end
        end
        Sketchup.active_model.select_tool(nil)
      rescue StandardError => error
        UI.messagebox(
          "No fue posible crear la estructura:\n#{error.message}\n\n" \
          "Ubicación: #{error.backtrace&.first}"
        )
        puts error.full_message
        Sketchup.active_model.select_tool(nil)
      end

      def draw(view)
        @input.draw(view) if @input.valid?
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end
    end

    class TriangleTowerPlacementTool
      def initialize(params)
        @params = params
        @input = Sketchup::InputPoint.new
      end

      def activate
        Sketchup.set_status_text(
          'Haz clic para colocar la esquina suroeste de la celda de la torre.',
          SB_PROMPT
        )
      end

      def onMouseMove(_flags, x, y, view)
        @input.pick(view, x, y)
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @input.pick(view, x, y)
        return unless @input.valid?
        ConstructorModulos.create_triangle_tower(@params, @input.position)
        Sketchup.active_model.select_tool(nil)
        if UI.messagebox('¿Agregar otra torre de pisos triangulares?', MB_YESNO) == IDYES
          ConstructorModulos.start_triangle_tower(
            color: @params[:color],
            cell_x_m: @params[:cell_x_mm] / 1000.0,
            cell_y_m: @params[:cell_y_mm] / 1000.0
          )
        end
      rescue StandardError => error
        UI.messagebox(
          "No fue posible crear la torre triangular:\n#{error.message}\n\n" \
          "Ubicación: #{error.backtrace&.first}"
        )
        puts error.full_message
        Sketchup.active_model.select_tool(nil)
      end

      def draw(view)
        @input.draw(view) if @input.valid?
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end
    end

    # `prefill` -opcional- llega cuando esta torre se abre encadenada
    # justo después de crear una estructura (ModulePlacementTool) o de
    # colocar otra torre (TriangleTowerPlacementTool), para no obligar al
    # usuario a volver a escribir el color/medida de celda que ya usó.
    def start_triangle_tower(prefill = {})
      unless defined?(UI::HtmlDialog)
        UI.messagebox('Esta herramienta necesita una versión de SketchUp compatible con HtmlDialog.')
        return
      end
      unless dependencies_available?
        UI.messagebox(
          "No se encontraron los plugins de tubos y conectores.\n\n" \
          'Instálalos y reinicia SketchUp antes de crear una torre.'
        )
        return
      end

      @triangle_dialog&.close
      @triangle_dialog = UI::HtmlDialog.new(
        dialog_title: 'Torre de Pisos Triangulares Play Idea',
        preferences_key: 'PlayIdeaTorreTriangular',
        scrollable: true,
        resizable: true,
        width: 560,
        height: 620,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @triangle_dialog.set_file(File.join(__dir__, 'torre_triangular.html'))
      @triangle_dialog.add_action_callback('ready') do |_action_context|
        @triangle_dialog.execute_script(
          "loadDefaults(#{JSON.generate(
            default_spacing_m: prefill[:cell_x_m] || DEFAULT_SPACING_M,
            default_spacing_y_m: prefill[:cell_y_m] || prefill[:cell_x_m] || DEFAULT_SPACING_M,
            step_spacing_mm: TRIANGLE_STEP_SPACING_MM,
            color: prefill[:color]
          )})"
        )
      end
      @triangle_dialog.add_action_callback('createTriangleTower') do |_action_context, data|
        params = validate_triangle_dialog_data(data)
        next unless params
        @triangle_dialog.close
        Sketchup.active_model.select_tool(TriangleTowerPlacementTool.new(params))
      end
      @triangle_dialog.show
    rescue StandardError => error
      UI.messagebox("No fue posible abrir la torre triangular:\n#{error.message}")
      puts error.full_message
    end

    def validate_triangle_dialog_data(data)
      params = {
        cell_x_mm: data['cell_x_m'].to_f * 1000.0,
        cell_y_mm: data['cell_y_m'].to_f * 1000.0,
        right_angle_corner: data['corner'].to_s.to_sym,
        steps: data['steps'].to_i,
        start_height_mm: data['start_height_m'].to_f * 1000.0,
        step_spacing_mm: data['step_spacing_mm'].to_f,
        color: data['color'].to_s,
        code: data['code'].to_s.strip
      }
      valid = params[:cell_x_mm].positive? && params[:cell_y_mm].positive? &&
        params[:steps].between?(1, 50) && params[:step_spacing_mm].positive? &&
        TRIANGLE_CORNER_ORDER.include?(params[:right_angle_corner])
      unless valid
        UI.messagebox('Revisa las medidas de celda, la cantidad de escalones (1-50) y la esquina elegida.')
        return nil
      end
      # El primer escalón no puede arrancar en el nivel 0 -ahí ya está el
      # conector 61 recibiendo el poste vertical, no cabe un tubo diagonal
      # a 45° en ese nivel, en ninguna orientación-.
      if params[:start_height_mm] < BOTTOM_GRID_HEIGHT_MM
        UI.messagebox(
          "La altura inicial debe ser de al menos #{(BOTTOM_GRID_HEIGHT_MM / 1000.0).round(3)}m -en el " \
          'nivel 0 ya está el conector 61 del poste vertical, no cabe un escalón triangular ahí.'
        )
        return nil
      end
      params[:code] = "TORRE-#{params[:steps]}" if params[:code].empty?
      params
    end

    # Coloca un CON-12 en `point` con la orientación exacta de
    # TRIANGLE_CONNECTOR_AXES_CAPPED -ver ese comentario- para
    # (`right_angle_corner`, `role`).
    def diagonal_connector_transform(point, right_angle_corner, role)
      local_x, local_y, local_z = TRIANGLE_CONNECTOR_AXES_CAPPED[right_angle_corner][role]
      Geom::Transformation.axes(point, local_x, local_y, local_z)
    end

    # El punto real donde debe llegar el tubo diagonal: por el codo de 45°
    # del receptor mitrado de build_12, es un desplazamiento COMPUESTO en 2
    # ejes locales del propio CON-12 -no un solo eje-. Medido directo en
    # los 4 CON-12 con tapa de reporte_grupo_20260806_110850.txt -2
    # escalones × 2 conectores-, comparando cada boca calculada contra el
    # extremo real del tubo diagonal: X local dio -11.99, -10.16, -9.93 y
    # +0.68mm -mediana -10.05-; Z local dio -26.28, -27.18, -32.67 y
    # -19.76mm -mediana -26.73-. Bastante ruido entre las 4 muestras -son
    # de una estructura hecha a mano, no todas van a calzar igual de bien-,
    # así que si se sigue viendo desfasado hace falta una referencia más
    # limpia -solo estos 2 tubos diagonales, sin el resto de la
    # estructura alrededor- para afinar más. `transform` es el resultado
    # de `diagonal_connector_transform` para ese mismo conector.
    # Ajustado con la indicación del usuario -"hacia la parte contraria de
    # donde forma el ángulo de 45"-. Primer intento: -10.05 a -12.0mm en X
    # local -insuficiente-. Segundo intento: subir la magnitud a -22.0mm
    # -CONFIRMADO AL REVÉS por el usuario, eso movió el punto HACIA el
    # ángulo de 45, no en contra-. Corregido: hacer X local MENOS negativo
    # -no más- para alejarse del ángulo. Desde -12.0mm, +10mm en esa
    # dirección: -2.0mm.
    DIAGONAL_MOUTH_LOCAL_X_MM = -2.0
    DIAGONAL_MOUTH_LOCAL_Z_MM = -28.5
    def diagonal_connector_mouth(transform)
      Geom::Point3d.new(DIAGONAL_MOUTH_LOCAL_X_MM.mm, 0, DIAGONAL_MOUTH_LOCAL_Z_MM.mm).transform(transform)
    end

    # CON-21 en el ángulo recto: orientación de TRIANGLE_CONNECTOR_21_AXES,
    # colocado exactamente en la esquina (mismo punto que usa `near`/`far`
    # para el CON-12, sin inset -ver triangle_cell_corners-).
    def right_angle_connector_transform(point, right_angle_corner)
      local_x, local_y, local_z = TRIANGLE_CONNECTOR_21_AXES[right_angle_corner]
      Geom::Transformation.axes(point, local_x, local_y, local_z)
    end

    # CON-10 en cada esquina vecina del ángulo recto: orientación de
    # TRIANGLE_CONNECTOR_10_AXES, colocado en la MISMA esquina que usa el
    # CON-12 de esa pata (`near`/`far`).
    def leg_connector_transform(point, right_angle_corner, leg_role)
      local_x, local_y, local_z = TRIANGLE_CONNECTOR_10_AXES[right_angle_corner][leg_role]
      Geom::Transformation.axes(point, local_x, local_y, local_z)
    end

    # Dado el ángulo recto elegido (una de TRIANGLE_CORNER_ORDER), devuelve
    # las esquinas [near, far] de la diagonal que SÍ construye este plugin
    # -ver el comentario DIRECCIÓN junto a TRIANGLE_CORNER_ORDER-: `near` es
    # la esquina siguiente a la elegida en ese orden fijo, `far` la
    # anterior. Verificado exacto contra los 4 ejemplos corregidos por el
    # usuario (NO→near=NE,far=SO; SE→near=SO,far=NE; NE→near=SE,far=NO;
    # SO→near=NO,far=SE).
    def diagonal_near_far_corners(right_angle_corner, corners)
      order = TRIANGLE_CORNER_ORDER
      idx = order.index(right_angle_corner)
      near_key = order[(idx + 1) % order.length]
      far_key = order[(idx - 1) % order.length]
      [corners[near_key], corners[far_key]]
    end

    # Las 4 esquinas de la celda de la torre, con `origin` -el punto que
    # marca el usuario- siempre como la esquina SO. `z` ya viene en
    # unidades reales de SketchUp (con `.mm` aplicado).
    def triangle_cell_corners(origin, params, z)
      {
        sw: offset_point(origin, 0, 0, z),
        se: offset_point(origin, params[:cell_x_mm].mm, 0, z),
        ne: offset_point(origin, params[:cell_x_mm].mm, params[:cell_y_mm].mm, z),
        nw: offset_point(origin, 0, params[:cell_y_mm].mm, z)
      }
    end

    # `origin` es la esquina SO de la celda -la que el usuario marca con el
    # clic-. Los escalones se apilan hacia arriba desde `start_height_mm`,
    # cada `step_spacing_mm` -600mm por defecto, confirmado con datos
    # reales-, TODOS con la MISMA diagonal -sin alternar entre escalones,
    # ver el comentario grande junto a TRIANGLE_STEP_SPACING_MM-. El primer
    # y último escalón llevan además las 2 patas + CON-21 + 2×CON-10 -ver
    # TRIANGLE_CONNECTOR_21_AXES-; no toca ningún conector de la cuadrícula
    # base -verificado que esos escalones no coinciden con niveles reales
    # de la estructura, ver el mismo comentario-.
    def create_triangle_tower(params, origin)
      model = Sketchup.active_model
      model.start_operation("Crear torre triangular #{params[:code]}", true)
      container = model.active_entities.add_group
      container.name = params[:code]
      entities = container.entities

      material = PlayIdea::Conectores.connector_material(model, 'Galvanizado')
      hardware = PlayIdea::Conectores.hardware_material(model)
      con12_definition = model.definitions.add(unique_name(model, 'CON-MOD-12'))
      PlayIdea::Conectores.build_connector_geometry(con12_definition.entities, '12', material, hardware)
      metadata12 = connector_metadata('12')
      PlayIdea::Conectores.write_attributes(con12_definition, '12', 'Galvanizado', metadata12)

      con21_definition = model.definitions.add(unique_name(model, 'CON-MOD-21'))
      PlayIdea::Conectores.build_connector_geometry(con21_definition.entities, '21', material, hardware)
      metadata21 = connector_metadata('21')
      PlayIdea::Conectores.write_attributes(con21_definition, '21', 'Galvanizado', metadata21)

      con10_definition = model.definitions.add(unique_name(model, 'CON-MOD-10'))
      PlayIdea::Conectores.build_connector_geometry(con10_definition.entities, '10', material, hardware)
      metadata10 = connector_metadata('10')
      PlayIdea::Conectores.write_attributes(con10_definition, '10', 'Galvanizado', metadata10)

      tube_cache = {}

      # `params[:step_heights_mm]` -lista de alturas, una por escalón,
      # tramo por tramo entre niveles reales, ver `auto_tower_step_heights`-
      # si viene de `tower_params_from_dialog`; si no viene -flujo del
      # diálogo manual de torre suelta, sin estructura de referencia, con
      # `steps`+`start_height_mm`+`step_spacing_mm` fijos en su lugar-, se
      # genera la lista equivalente con separación uniforme, igual que
      # antes.
      step_heights_mm = params[:step_heights_mm] ||
        Array.new(params[:steps]) { |step| params[:start_height_mm] + step * params[:step_spacing_mm] }

      step_heights_mm.each_with_index do |z_mm, step|
        # TODOS los escalones llevan el triángulo completo -diagonal +
        # CON-21 + 2 patas-, no solo el primero y el último. Antes solo
        # esos 2 lo llevaban -diseño original, confirmado contra la
        # referencia aislada de 4 torres, que solo tenía 2 o 3 escalones
        # y nunca escalaba con nz-; con torres de más escalones -nz>1- el
        # usuario confirmó que cada escalón necesita su propio ángulo
        # recto, no solo los extremos.
        # Los escalones ALTERNAN esquina: el escalón 0 usa la esquina dada
        # -params[:right_angle_corner]-, el escalón 1 usa la esquina
        # CONTRARIA -diagonalmente opuesta en la celda-, el 2 vuelve a la
        # dada, etc. Confirmado con datos reales -reporte_grupo_20260806_
        # 110850.txt-: el CON-21 del escalón 1 estaba pegado a una
        # esquina, y el del escalón 2 pegado a la esquina diagonalmente
        # opuesta, no a la misma. Antes este código usaba SIEMPRE la
        # misma esquina en todos los escalones -confirmado erróneo-.
        step_corner = if step.even?
                        params[:right_angle_corner]
                      else
                        idx = TRIANGLE_CORNER_ORDER.index(params[:right_angle_corner])
                        TRIANGLE_CORNER_ORDER[(idx + 2) % 4]
                      end
        z = z_mm.mm
        corners = triangle_cell_corners(origin, params, z)
        near, far = diagonal_near_far_corners(step_corner, corners)
        ra_point = corners[step_corner]

        # Solo el CON-12 se aleja de la esquina real -a lo largo de su
        # PROPIO borde de celda, hacia la esquina del ÁNGULO RECTO, NO a
        # lo largo de la diagonal hacia la esquina opuesta-. Confirmado
        # con datos reales -reporte_grupo_20260806_110850.txt, parseado
        # con script-: en las 4 instancias medidas, el desplazamiento real
        # fue puro ±X o puro ±Y -nunca diagonal a 45°-, siempre apuntando
        # hacia la esquina del ángulo recto de ese escalón. También
        # confirmado contra DISENOS_REFERENCIA -diseño 1, escalón capped-.
        # El código anterior movía cada CON-12 hacia el OTRO extremo de la
        # diagonal -confirmado erróneo, por eso el tubo no embonaba bien-.
        # `near`/`far` SIN alejar se siguen usando tal cual para el CON-21
        # y los CON-10 -esos si van pegados a la columna real, confirmado
        # con datos-, así que no se tocan aquí.
        near_diag = near.offset((ra_point - near).normalize, TRIANGLE_DIAGONAL_INSET_MM.mm)
        far_diag = far.offset((ra_point - far).normalize, TRIANGLE_DIAGONAL_INSET_MM.mm)

        transform_near = diagonal_connector_transform(near_diag, step_corner, :near)
        transform_far = diagonal_connector_transform(far_diag, step_corner, :far)
        mouth_near = diagonal_connector_mouth(transform_near)
        mouth_far = diagonal_connector_mouth(transform_far)
        tube_vector = mouth_far - mouth_near
        tube_length_mm = tube_vector.length.to_mm

        if tube_length_mm <= 0
          model.abort_operation
          UI.messagebox('La celda es demasiado pequeña para que el tubo diagonal quepa entre los dos conectores.')
          return nil
        end
        tube_direction = tube_vector.normalize
        tube_definition = tube_cache[tube_length_mm.round(4)] ||=
          create_tube_definition(model, tube_length_mm, params[:color], 'DIAG')
        add_oriented_instance(entities, tube_definition, mouth_near, tube_direction)

        [transform_near, transform_far].each do |transform|
          instance = entities.add_instance(con12_definition, transform)
          instance.name = 'CON-12'
          PlayIdea::Conectores.write_attributes(instance, '12', 'Galvanizado', metadata12)
        end

        # Si la altura de este escalón COINCIDE con un nivel real de la
        # cuadrícula -tolerancia GRID_LEVEL_COINCIDENCE_TOLERANCE_MM-, ese
        # nivel YA tiene sus propios conectores/tubos ahí -CON-61 y el
        # tubo recto de esquina a esquina-, así que este escalón NO pone
        # el CON-21 + 2 patas -se duplicaría con lo que ya existe-, solo
        # la diagonal de arriba. `real_grid_levels_mm` viene de
        # `tower_params_from_dialog`; si no viene -flujo del diálogo
        # manual de torre suelta, sin estructura de referencia-, se trata
        # como si nunca coincidiera. Con `nz=1` esto casi nunca aplica -la
        # torre se queda en su patrón fijo de 2 escalones, sin relación
        # con los niveles reales-; se vuelve relevante con módulos de
        # altura elegida a propósito para que un escalón caiga exacto en
        # un nivel real.
        grid_levels = params[:real_grid_levels_mm] || []
        next if grid_levels.any? { |lvl| (z.to_mm - lvl).abs < GRID_LEVEL_COINCIDENCE_TOLERANCE_MM }

        # El CON-21 también se aleja de su esquina real, hacia la esquina
        # OPUESTA de la celda -la que no toca ni la diagonal ni ninguna
        # pata-, ver TRIANGLE_RIGHT_ANGLE_INSET_MM.
        opposite_key = TRIANGLE_CORNER_ORDER[(TRIANGLE_CORNER_ORDER.index(step_corner) + 2) % 4]
        ra_point_inset = ra_point.offset((corners[opposite_key] - ra_point).normalize, TRIANGLE_RIGHT_ANGLE_INSET_MM.mm)

        transform_ra = right_angle_connector_transform(ra_point_inset, step_corner)
        ra_instance = entities.add_instance(con21_definition, transform_ra)
        ra_instance.name = 'CON-21'
        PlayIdea::Conectores.write_attributes(ra_instance, '21', 'Galvanizado', metadata21)

        { near: near, far: far }.each do |leg_role, leg_point|
          transform_leg = leg_connector_transform(leg_point, step_corner, leg_role)
          # El tubo de la pata NO va del CON-21 -ya movido 34.65mm- al
          # CON-10: es un tubo de borde de celda ESTÁNDAR, esquina cruda a
          # esquina cruda -ra_point a leg_point-, con la misma inserción
          # RECEIVER_RADIUS_MM -24.15mm- que cualquier tubo recto de la
          # cuadrícula, no TRIANGLE_MOUTH_INSET_MM -12.075mm-. Confirmado
          # con datos reales -reporte_grupo_20260806_110850.txt-: el
          # nombre del tubo real es 1120.1mm = separación de celda menos
          # 2×24.15mm, exactamente la fórmula de un tubo de borde normal,
          # y ambos extremos caen a ~1-3mm de esa fórmula. El CON-21 sigue
          # en su posición -ya confirmada correcta-, pero el tubo no sale
          # de ahí, sale del borde real de la celda.
          mouth_ra = ra_point.offset((leg_point - ra_point).normalize, RECEIVER_RADIUS_MM.mm)
          mouth_leg = leg_point.offset((ra_point - leg_point).normalize, RECEIVER_RADIUS_MM.mm)
          leg_vector = mouth_ra - mouth_leg
          leg_length_mm = leg_vector.length.to_mm
          next if leg_length_mm <= 0
          leg_direction = leg_vector.normalize
          leg_tube_definition = tube_cache[[:leg, leg_length_mm.round(4)]] ||=
            create_tube_definition(model, leg_length_mm, params[:color], 'PATA')
          add_oriented_instance(entities, leg_tube_definition, mouth_leg, leg_direction)

          leg_instance = entities.add_instance(con10_definition, transform_leg)
          leg_instance.name = 'CON-10'
          PlayIdea::Conectores.write_attributes(leg_instance, '10', 'Galvanizado', metadata10)
        end
      end

      container.set_attribute(DICTIONARY, 'type', 'torre_triangular')
      container.set_attribute(DICTIONARY, 'steps', step_heights_mm.length)
      container.set_attribute(DICTIONARY, 'step_heights_mm', step_heights_mm.join(','))
      container.set_attribute(DICTIONARY, 'right_angle_corner', params[:right_angle_corner].to_s)
      container.set_attribute('minorusal_auditor', 'code', params[:code])
      model.selection.clear
      model.selection.add(container)
      model.commit_operation
      container
    rescue StandardError
      model.abort_operation
      raise
    end

    unless file_loaded?(__FILE__)
      # Aviso claro en consola -y versión visible directo en el nombre del
      # submenú, sin tener que abrir el Extension Manager- para poder
      # confirmar a simple vista, sin adivinar, que SketchUp está
      # corriendo la versión recién instalada y no una copia vieja en
      # memoria -recuerda: reinstalar el .rbz con SketchUp abierto NO
      # recarga el código, hace falta cerrar y volver a abrir-.
      puts "▶️  constructor_modulos_playidea v#{EXTENSION.version} cargado."
      menu = UI.menu('Extensions').add_submenu(
        "Play Idea - Constructor de Módulos (v#{EXTENSION.version})"
      )
      menu.add_item('Construcción de juegos (manual)') { start }
      menu.add_item('Construcción de juegos (automática)') { start_automatico }
      menu.add_item('Agregar torre de pisos triangulares') { start_triangle_tower }
      file_loaded(__FILE__)
    end
  end
end
