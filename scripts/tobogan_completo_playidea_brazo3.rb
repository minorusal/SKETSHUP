# Script suelto (NO es un plugin instalable) para ensamblar de un solo
# clic un tobogán COMPLETO -desde la plataforma hasta la salida- con
# las piezas ya construidas por separado: edita este archivo y en la
# Consola de Ruby -Window > Ruby Console- corre
#   load '/Users/minorusal/Documents/SKETCHUP/scripts/tobogan_completo_playidea.rb'
# -o arrastra el archivo a la ventana de SketchUp-. Cada `load` vuelve a
# cargar las piezas dependientes -codo de 90°, salida- y abre la
# herramienta de inmediato.
#
# REPLANTEADO otra vez: el intento anterior -giro de 90° entre codos-
# salió como una "escalera" con tramos COMPLETAMENTE VERTICALES -de
# horizontal a apuntando derecho hacia abajo-, que el usuario señaló
# como peligroso -una caída vertical real, no un tobogán-. Corrección:
# "debió ser vertical" se refiere al EJE de la espiral -un poste
# vertical imaginario alrededor del cual gira-, no a que las piezas
# mismas apunten hacia abajo.
#
# Solución -verificada primero con una simulación en Ruby puro fuera de
# SketchUp, ver conversación-: en vez de un giro arbitrario entre
# codos, cada codo se orienta para que su INCLINACIÓN -el ángulo hacia
# abajo respecto a la horizontal- sea SIEMPRE LA MISMA -PITCH_RAD, un
# valor moderado, nunca 90°- y solo el RUMBO -hacia dónde apunta en
# planta- vaya girando un incremento fijo -DELTA_PHI_RAD- en cada codo.
# Es la misma idea que un tubo de caracol real: inclinación constante,
# vueltas alrededor de un eje. La demostración matemática -un codo de
# 90° SIEMPRE separa su entrada y su salida por exactamente 90°, pero
# ESE par de direcciones puede elegirse con la MISMA inclinación y
# solo el rumbo distinto, mientras la inclinación no pase de 45°- está
# en la conversación.
#
# PITCH_RAD se calcula para que ELBOW_COUNT codos den EXACTO
# TARGET_HEIGHT_MM de caída -a diferencia de los intentos anteriores,
# aquí si cae justo en el objetivo, no hay que aproximar-.

Object.send(:remove_const, :PlayIdeaToboganCompletoScriptBrazo3) if defined?(PlayIdeaToboganCompletoScriptBrazo3)

module PlayIdeaToboganCompletoScriptBrazo3
  extend self

  # OJO: NO usar File.dirname(__FILE__) -dentro del `load` de la
  # Consola de Ruby, __FILE__ no resuelve a la ruta real del archivo,
  # da un valor relativo que rompe los `load` de las piezas
  # dependientes-. Ruta fija, igual que la de la cabecera de este
  # archivo.
  SCRIPTS_DIR = '/Users/minorusal/Documents/SKETCHUP/scripts'.freeze
  DEPENDENCIES = %w[
    tobogan_recto_playidea.rb
    codo_90_playidea.rb
    salida_tobogan_playidea.rb
    soporte_solera_playidea.rb
  ].freeze
  # Plugins existentes -no scripts sueltos, viven en su propia carpeta
  # cada uno- reutilizados para la estructura central: el creador de
  # tubos genéricos -PlayIdea::CreadorTubos- y los conectores
  # -PlayIdea::Conectores, para el CON-61 de la base-. Cargarlos con
  # `load` repetido es seguro -ambos usan `unless file_loaded?(...)`
  # para su registro de menú, no reabren ningún diálogo solos-.
  STRUCTURE_DEPENDENCIES = [
    '/Users/minorusal/Documents/SKETCHUP/creador_tubos_playidea/main.rb',
    '/Users/minorusal/Documents/SKETCHUP/conectores_playidea/main.rb'
  ].freeze

  # REPLANTEADO otra vez -última corrección del usuario-: se suelta lo
  # de "salida EXACTAMENTE del lado contrario" -eso era lo que obligaba
  # a 25.3°, ver conversación-, pero se mantiene "salida horizontal"
  # -con su propio codo de transición al final, tal como ya se hacía en
  # la entrada, solo que ahora también abajo-. Sin la meta de cerrar la
  # vuelta en un rumbo exacto, la inclinación de la espiral vuelve a
  # ser una elección libre -PITCH_DEG- en vez de algo forzado por el
  # cierre de vuelta: se deja en el mismo valor ya aprobado antes
  # -~16°, "menos kamikaze"-. El rumbo final -hacia dónde queda la
  # salida- ya no se controla, cae donde caiga tras STEADY_ELBOW_COUNT
  # codos.
  # 20.08° -resuelto por bisección- da EXACTO 4.000m de altura total
  # -de la base del CON-61 a la superficie exterior de arriba del tramo
  # recto horizontal-, que es la medida que el usuario pidió ajustar.
  # delta_phi se sigue derivando de PITCH_RAD con la misma fórmula
  # exacta -tan²(pitch) = -cos(delta_phi)-, así que los codos de espiral
  # siguen embonando entre sí garantizado, sin importar el valor exacto
  # de la inclinación.
  PITCH_DEG = 20.08
  PITCH_RAD = PITCH_DEG * Math::PI / 180.0
  # STEADY_ELBOW_COUNT=6 -antes 9- para que la salida conecte justo
  # después del codo 8 contando desde arriba -1 transición de entrada +
  # 6 de espiral + 1 transición de salida = 8 codos, pedido explícito
  # del usuario-.
  STEADY_ELBOW_COUNT = 6
  ELBOW_COUNT = STEADY_ELBOW_COUNT + 2 # + transición de entrada y de salida
  TRANSITION_SWEEP_RAD = Math::PI / 2.0 # puros codos de 90°, también los de transición

  # Tubo de estructura -poste central + brazos a cada soporte de
  # solera-: perfil 'ESTRUCTURAL' del catálogo de CreadorTubos -38.1mm
  # exterior, 1.5mm pared-, el único que cabe DENTRO del receptor del
  # CON-61 -receptor de 41.94mm interno, ver conversación-.
  CENTRAL_TUBE_OUTSIDE_MM = 38.1
  CENTRAL_TUBE_WALL_MM = 1.50
  CENTRAL_TUBE_INSIDE_MM = CENTRAL_TUBE_OUTSIDE_MM - (2.0 * CENTRAL_TUBE_WALL_MM)
  CENTRAL_TUBE_COLOR = 'Negro'.freeze
  ARM_MIN_MM = 300.0 # 30cm, dato del usuario -largo esperado del brazo soldado a cada soporte-
  ARM_MAX_MM = 400.0 # 40cm
  CON61_BELOW_EXIT_MM = 300.0 # 30cm, dato del usuario -el CON-61 queda más abajo que la salida-
  # Cuánto se recorta un tubo estructural antes del CENTRO de un CON-10
  # -o similar- en cada extremo, para no atravesar el cuerpo/paso
  # principal del conector -el conector mismo ocupa ese último tramo-.
  # 50mm dejaba ~2cm de hueco visible de más -según el usuario-, bajado
  # a 30mm, luego 1cm más metido -20mm-, luego el usuario reportó 5mm de
  # sobra en cada extremo del brazo -subido a 25mm-.
  CONNECTOR_SOCKET_CLEARANCE_MM = 25.0
  # La pata vertical de la punta del brazo -hasta el CON-10 de arriba-
  # usa una cavidad más profunda que el brazo; con el mismo recorte
  # -20mm- le faltaban ~6cm para tocarlo -confirmado por el usuario-.
  # Neto: en vez de -20mm, +40mm -equivale a los +60mm pedidos sobre lo
  # que ya había-.
  TIP_POST_EXTRA_MM = 40.0

  def start
    DEPENDENCIES.each { |file| load File.join(SCRIPTS_DIR, file) }
    STRUCTURE_DEPENDENCIES.each { |file| load file }
    Sketchup.active_model.select_tool(PlacementTool.new({}))
  rescue StandardError => error
    UI.messagebox("No fue posible iniciar el ensamble del tobogán:\n#{error.message}")
    puts error.full_message
  end

  # Dirección de viaje en el rumbo `phi` -ángulo en planta, alrededor
  # del eje vertical- con inclinación fija `pitch` hacia abajo. Vector
  # unitario por construcción -cos²+sen²=1-.
  def dir_at(phi, pitch)
    Geom::Vector3d.new(
      Math.cos(pitch) * Math.cos(phi),
      Math.cos(pitch) * Math.sin(phi),
      -Math.sin(pitch)
    )
  end

  # Busca, a lo largo de TODOS los tramos del ducto -duct_segments-, el
  # punto más cercano en PLANTA -solo X,Y, sin importar la altura- a
  # `target_x_mm, target_y_mm`. Devuelve [punto, tangente_unitaria] del
  # mejor punto encontrado -tangente = dirección local del tubo ahí,
  # útil para orientar una solera-. Muestrea cada tramo curvo en
  # SAMPLES_PER_ELBOW puntos -suficiente para un radio de curvatura de
  # unos cientos de mm, no hace falta más precisión para acomodar una
  # abrazadera a mano-.
  SAMPLES_PER_ELBOW = 60

  def nearest_duct_point(duct_segments, target_x_mm, target_y_mm)
    best = nil
    duct_segments.each do |seg|
      if seg[:type] == :straight
        (0..10).each do |k|
          t_mm = seg[:length].to_mm * (k / 10.0)
          candidate_point = seg[:start].offset(seg[:direction], t_mm.mm)
          candidate_tangent = seg[:direction]
          best = closer(best, candidate_point, candidate_tangent, target_x_mm, target_y_mm)
        end
      else # :elbow
        SAMPLES_PER_ELBOW.times do |k|
          theta = seg[:sweep] * k / (SAMPLES_PER_ELBOW - 1).to_f
          dx_local = seg[:radius] * Math.sin(theta)
          dy_local = seg[:radius] * (1.0 - Math.cos(theta))
          candidate_point = seg[:entry].offset(Geom::Vector3d.new(
            (seg[:direction].x * dx_local) + (seg[:exit_direction].x * dy_local),
            (seg[:direction].y * dx_local) + (seg[:exit_direction].y * dy_local),
            (seg[:direction].z * dx_local) + (seg[:exit_direction].z * dy_local)
          ))
          candidate_tangent = Geom::Vector3d.new(
            (Math.cos(theta) * seg[:direction].x) + (Math.sin(theta) * seg[:exit_direction].x),
            (Math.cos(theta) * seg[:direction].y) + (Math.sin(theta) * seg[:exit_direction].y),
            (Math.cos(theta) * seg[:direction].z) + (Math.sin(theta) * seg[:exit_direction].z)
          )
          best = closer(best, candidate_point, candidate_tangent, target_x_mm, target_y_mm)
        end
      end
    end
    [best[:point], best[:tangent]]
  end

  def closer(best, candidate_point, candidate_tangent, target_x_mm, target_y_mm)
    dx = candidate_point.x.to_mm - target_x_mm
    dy = candidate_point.y.to_mm - target_y_mm
    dist2 = (dx * dx) + (dy * dy)
    return best if best && best[:dist2] <= dist2

    { point: candidate_point, tangent: candidate_tangent, dist2: dist2 }
  end

  # Punto/tangente a una FRACCIÓN dada -0.0=entrada, 0.5=centro,
  # 1.0=salida- de un tramo -de duct_segments-, curvo o recto. Mismas
  # fórmulas que nearest_duct_point, pero para un punto CONOCIDO -por
  # índice- en vez de buscar el más cercano a algo.
  def point_at_segment_fraction(seg, fraction)
    if seg[:type] == :straight
      t_mm = seg[:length].to_mm * fraction
      [seg[:start].offset(seg[:direction], t_mm.mm), seg[:direction]]
    else # :elbow
      theta = seg[:sweep] * fraction
      dx_local = seg[:radius] * Math.sin(theta)
      dy_local = seg[:radius] * (1.0 - Math.cos(theta))
      point = seg[:entry].offset(Geom::Vector3d.new(
        (seg[:direction].x * dx_local) + (seg[:exit_direction].x * dy_local),
        (seg[:direction].y * dx_local) + (seg[:exit_direction].y * dy_local),
        (seg[:direction].z * dx_local) + (seg[:exit_direction].z * dy_local)
      ))
      tangent = Geom::Vector3d.new(
        (Math.cos(theta) * seg[:direction].x) + (Math.sin(theta) * seg[:exit_direction].x),
        (Math.cos(theta) * seg[:direction].y) + (Math.sin(theta) * seg[:exit_direction].y),
        (Math.cos(theta) * seg[:direction].z) + (Math.sin(theta) * seg[:exit_direction].z)
      )
      [point, tangent]
    end
  end

  # Construye la cadena completa arrancando en `start_point`, con el
  # primer codo entrando en el rumbo `heading` -un vector horizontal,
  # sin componente Z, solo define el rumbo inicial en planta-.
  def build_assembly(start_point, heading = X_AXIS)
    model = Sketchup.active_model
    instances = []

    transition_radius_mm = PlayIdeaCodo90Script::BEND_RADIUS_MM
    transition_ceja_mm = PlayIdeaCodo90Script::CEJA_LENGTH_MM

    # Con la inclinación YA FIJA -PITCH_RAD, elección directa- el avance
    # de rumbo por codo de la espiral sale directo de la fórmula del
    # codo de 90°: cos(90°) = cos²(pitch)·cos(delta_phi) + sen²(pitch),
    # y cos(90°)=0, entonces tan²(pitch) = -cos(delta_phi).
    pitch = PITCH_RAD
    tan2_pitch = Math.tan(pitch)**2
    delta_phi = Math.acos(-tan2_pitch)

    point = start_point
    heading_phi = Math.atan2(heading.y, heading.x)
    phi = heading_phi
    start_z = point.z

    # --- Soportes de solera: uno en cada UNIÓN entre piezas -donde la
    # ceja de una pieza recibe el extremo liso de la siguiente-, que es
    # donde concentra carga la pieza de arriba. Se coloca ANTES de cada
    # pieza, con la misma dirección/inclinación con la que esa pieza
    # arranca -así la solera queda perpendicular al eje del tubo justo
    # ahí-. No se pone soporte en la salida -llega prácticamente al
    # piso, no necesita colgar de nada-. ---
    support_points = []
    # Solo los codos de ESPIRAL -ni el tramo recto de arranque, ni las
    # 2 transiciones-, que son los que de verdad trazan el "loop" de la
    # espiral. Se usa aparte para ubicar el poste central -incluir el
    # arranque/las transiciones jalaba el eje hacia el lado de la
    # entrada, sacándolo del centro real de la espiral-.
    spiral_points = []
    # Registro de CADA tramo del ducto -curvo o recto- con lo mínimo
    # para reconstruir cualquier punto/tangente sobre él después -para
    # buscar "el punto del ducto más cercano en planta a tal X,Y", como
    # el que pidió el usuario para la solera de en medio-.
    duct_segments = []

    # --- Tramo recto de arranque, HORIZONTAL -pitch=0-. ---
    lead_in_direction = dir_at(phi, 0.0)
    support_points << [point, lead_in_direction]
    duct_segments << { type: :straight, start: point, direction: lead_in_direction,
                        length: PlayIdeaToboganRectoScript::TOTAL_LENGTH_MM.mm }
    lead_in = PlayIdeaToboganRectoScript.build_piece({}, point, lead_in_direction)
    instances << lead_in
    point = point.offset(lead_in_direction, PlayIdeaToboganRectoScript::TOTAL_LENGTH_MM.mm)

    # Todos los codos son de 90°, así que dx/dy/ceja son los mismos
    # para transición o espiral -mismo radio, mismo barrido-.
    dx_local = transition_radius_mm.mm * Math.sin(TRANSITION_SWEEP_RAD)
    dy_local = transition_radius_mm.mm * (1.0 - Math.cos(TRANSITION_SWEEP_RAD))

    ELBOW_COUNT.times do |i|
      # Codo 0 -transición de ENTRADA-: entra horizontal -pitch=0-,
      # sale ya a la inclinación de la espiral. Codo ELBOW_COUNT-1
      # -transición de SALIDA-: entra a la inclinación de la espiral,
      # sale horizontal -pitch=0- otra vez. Ambas transiciones avanzan
      # el rumbo exactamente 90°, sin importar la inclinación -mismo
      # caso especial de antes-. Los codos de en medio -la espiral-
      # entran y salen a la MISMA inclinación, con el avance de rumbo
      # delta_phi ya calculado. El rumbo final YA NO se fuerza a nada
      # en particular -cae donde caiga tras STEADY_ELBOW_COUNT codos-.
      is_entry_transition = i.zero?
      is_exit_transition = (i == ELBOW_COUNT - 1)
      is_transition = is_entry_transition || is_exit_transition

      entry_pitch = is_entry_transition ? 0.0 : pitch
      exit_pitch = is_exit_transition ? 0.0 : pitch
      step = is_transition ? TRANSITION_SWEEP_RAD : delta_phi

      entry_phi = phi
      exit_phi = entry_phi + step

      direction = dir_at(entry_phi, entry_pitch)
      exit_direction = dir_at(exit_phi, exit_pitch)

      support_points << [point, direction]
      spiral_points << point unless is_transition

      # up_hint tal que el codo -local_y = direction × up_hint,
      # normalizado- termine su barrido apuntando exactamente hacia
      # exit_direction: up_hint = exit_direction × direction resuelve
      # eso -ver derivación con el triple producto vectorial en la
      # conversación-.
      up_hint = exit_direction.cross(direction)

      instance = PlayIdeaCodo90Script.build_piece({}, point, direction, up_hint)
      instances << instance

      # OJO: el barrido FÍSICO del codo -su propia curva interna, theta
      # de 0 a esto- SIEMPRE es TRANSITION_SWEEP_RAD -90°, todos son
      # codo_90-, sin importar `step` -que es el avance de MI rumbo phi,
      # otra cosa totalmente distinta: 90° en las transiciones pero
      # delta_phi -~102°- en los codos de espiral-. Confundir los dos
      # aquí habría hecho que la búsqueda de punto más cercano recorriera
      # la curva mal en los codos de espiral.
      duct_segments << { type: :elbow, entry: point, direction: direction, exit_direction: exit_direction,
                          radius: transition_radius_mm.mm, sweep: TRANSITION_SWEEP_RAD }

      bend_offset = Geom::Vector3d.new(
        (direction.x * dx_local) + (exit_direction.x * dy_local),
        (direction.y * dx_local) + (exit_direction.y * dy_local),
        (direction.z * dx_local) + (exit_direction.z * dy_local)
      )
      point = point.offset(bend_offset)
      duct_segments << { type: :straight, start: point, direction: exit_direction, length: transition_ceja_mm.mm }
      point = point.offset(exit_direction, transition_ceja_mm.mm) # la ceja del codo sigue derecho

      phi = exit_phi
    end

    # --- Pieza de salida, HORIZONTAL -el último codo ya regresó a
    # pitch=0-, canal abierto hacia arriba. ---
    final_direction = dir_at(phi, 0.0)
    salida = PlayIdeaSalidaToboganScript.build_piece({}, point, final_direction, Z_AXIS.reverse)
    instances << salida

    # La parte LISA -redonda, cerrada- de la salida, como candidato para
    # nearest_duct_point -sin esto, la búsqueda nunca conocía la salida
    # y se quedaba justo en la ceja del último codo, que es donde el
    # usuario reportó que quedaba mal la solera de en medio-.
    salida_round_length_mm = PlayIdeaSalidaToboganScript::CEJA_LENGTH_MM + PlayIdeaSalidaToboganScript::STRAIGHT_ROUND_LENGTH_MM
    duct_segments << { type: :straight, start: point, direction: final_direction, length: salida_round_length_mm.mm }

    # Los soportes de solera en cada unión -uno por cada codo, además
    # del de 3" del brazo de hasta abajo- se quitaron por pedido del
    # usuario -por ahora solo queda el del brazo-.

    # --- Estructura central -poste vertical + CON-61 en la base-. El
    # poste va en el centro de la CAJA que envuelve los codos de
    # ESPIRAL -spiral_points, NO support_points: el tramo recto de
    # arranque y las 2 transiciones no forman parte del loop, incluirlos
    # jalaba el eje hacia el lado de la entrada, sacándolo del centro
    # real-, de la altura del piso -donde termina la espiral, mismo
    # nivel que la salida- hasta la altura de la entrada. Brazos a cada
    # soporte: PENDIENTE, quitados por ahora.
    spiral_xs_mm = spiral_points.map(&:x).map(&:to_mm)
    spiral_ys_mm = spiral_points.map(&:y).map(&:to_mm)
    centroid_x_mm = (spiral_xs_mm.min + spiral_xs_mm.max) / 2.0
    centroid_y_mm = (spiral_ys_mm.min + spiral_ys_mm.max) / 2.0
    # El CON-61 -y con él, la base del poste- queda CON61_BELOW_EXIT_MM
    # más abajo que el nivel de la salida -dato del usuario, 30cm-. OJO:
    # `point.z` aquí es el EJE/centro del tubo de la salida, no su
    # superficie de abajo -el tubo tiene BODY_OUTSIDE_R_MM -40.8cm- de
    # radio real-; hay que bajar el radio completo primero y DESPUÉS
    # los 30cm, si no, el 61 queda solo unos cm abajo del eje en vez de
    # 30cm abajo del tubo de verdad.
    exit_bottom_z = point.z - PlayIdeaSalidaToboganScript::BODY_OUTSIDE_R_MM.mm
    ground_z = exit_bottom_z - CON61_BELOW_EXIT_MM.mm

    con61_point = Geom::Point3d.new(centroid_x_mm.mm, centroid_y_mm.mm, ground_z)
    # metadata necesita :costing => { rows: [...] } -write_attributes lo
    # lee directo, sin chequeo de nil- aunque aquí no haya costos reales
    # que registrar todavía, solo geometría.
    con61_metadata = {
      receiver_material: 'Galvanizado',
      hardware_size: '3/8"',
      investment_cost_mxn: 0,
      costing: { rows: [] }
    }
    con61 = PlayIdea::Conectores.create_connector('61', 'Galvanizado', con61_metadata, con61_point)
    instances << con61

    tube_params_base = {
      outside_mm: CENTRAL_TUBE_OUTSIDE_MM,
      wall_mm: CENTRAL_TUBE_WALL_MM,
      inside_mm: CENTRAL_TUBE_INSIDE_MM,
      schedule: 'ESTRUCTURAL',
      color: CENTRAL_TUBE_COLOR,
      length_mode: 'manual',
      standard_name: '',
      connector_compatible: true,
      connector_clearance_mm: PlayIdea::CreadorTubos::CONNECTOR_INSIDE_MM - CENTRAL_TUBE_OUTSIDE_MM
    }

    # --- Primer brazo, hacia la salida -el soporte de solera más
    # cercano a la salida, la última transición de la espiral-,
    # conectado al poste con un CON-10 -"T sencilla a 90°": paso
    # horizontal de 63.5mm por default, más un ramal de 50.8mm hacia
    # -Z-. Se usa GIRADO -el paso queda VERTICAL, siguiendo el poste; el
    # ramal queda HORIZONTAL, apuntando hacia el soporte-, en vez de su
    # orientación de fábrica -paso horizontal, ramal hacia abajo-. ---
    arm_support_point, = support_points.last
    # Ajuste manual pedido por el usuario -ya no apunta exacto al
    # soporte-: 65cm más abajo que la altura del soporte -45cm, luego
    # 10cm más, luego 10cm más-, y el rumbo horizontal girado 90° a la
    # izquierda -sentido contrario a las manecillas del reloj visto
    # desde arriba, mismo sentido positivo que gira `phi` en dir_at- de
    # hacia dónde apuntaba antes. El largo del brazo se conserva -mismo
    # que antes, solo cambia dirección-.
    arm_drop_mm = 680.0 # 650mm + 3cm más abajo, pedido por el usuario
    arm_z = arm_support_point.z - arm_drop_mm.mm
    post_axis_at_arm = Geom::Point3d.new(centroid_x_mm.mm, centroid_y_mm.mm, arm_z)
    original_arm_direction = arm_support_point - Geom::Point3d.new(centroid_x_mm.mm, centroid_y_mm.mm, arm_support_point.z)

    # Largo del brazo -calculado AQUÍ, antes de rotar, porque rotar no
    # cambia la magnitud del vector, y hace falta el radio -arm_mid_mm-
    # para la 2a rotación de abajo-. +10cm sobre el original, luego
    # DUPLICADO, pedido del usuario en su momento.
    arm_extra_mm = 100.0
    arm_length_mm = (original_arm_direction.length.to_mm + arm_extra_mm) * 2.0
    arm_mid_mm = arm_length_mm / 2.0

    # 2 giros alrededor del poste, ambos a la izquierda -sentido
    # contrario a las manecillas del reloj visto desde arriba-: los 90°
    # fijos del pedido original, más un ajuste fino de ~15cm de arco
    # -medido en el radio del punto medio del brazo, arm_mid_mm- pedido
    # después para sacar la solera de en medio de la ceja.
    arm_rotation_deg = 90.0
    arm_fine_shift_mm = 150.0
    arm_fine_rotation_rad = arm_fine_shift_mm / arm_mid_mm
    arm_rotation_rad = arm_rotation_deg.degrees + arm_fine_rotation_rad
    arm_rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, arm_rotation_rad)
    arm_direction = original_arm_direction.transform(arm_rotation)

    con10_metadata = {
      receiver_material: 'Galvanizado',
      hardware_size: '3/8"',
      investment_cost_mxn: 0,
      costing: { rows: [] }
    }
    con10 = PlayIdea::Conectores.create_connector('10', 'Galvanizado', con10_metadata, post_axis_at_arm)
    # Reorienta el CON-10 EN SITIO -mismo punto, solo rotación-: local
    # +X -su paso horizontal de fábrica- pasa a apuntar hacia Z_AXIS
    # -vertical, seguido del poste-; local +Z -opuesto al ramal, que de
    # fábrica apunta a -Z- pasa a apuntar contrario a arm_direction, así
    # el ramal -local -Z- sí apunta hacia el soporte.
    # OJO: arm_direction NO es unitario -es Point3d-Point3d, su
    # magnitud es la distancia real-; usarlo sin normalizar en
    # Transformation.axes metería ese largo como ESCALA en el CON-10 y
    # lo estiraría. Todos los ejes destino tienen que ser unitarios.
    con10_target_x = Z_AXIS
    con10_target_z = arm_direction.reverse.normalize
    con10_target_y = con10_target_z.cross(con10_target_x)
    con10.transformation = Geom::Transformation.axes(post_axis_at_arm, con10_target_x, con10_target_y, con10_target_z)
    instances << con10

    # --- Segundo brazo, hacia el CENTRO del 5º codo contando de ABAJO
    # hacia ARRIBA -de los 8 codos totales, sin contar el tramo recto
    # de arranque-: 1º desde abajo = transición de salida (i=7), 2º =
    # espiral 6 (i=6), 3º = espiral 5 (i=5), 4º = espiral 4 (i=4), 5º =
    # espiral 3 (i=3, el que se agarra aquí) -ver conteo completo en la
    # conversación-. duct_segments[1+2*i] es el tramo curvo de ese codo
    # -índice determinístico, ver cómo se llenó duct_segments arriba-.
    # Mismo patrón que el primer CON-10: paso principal vertical
    # -siguiendo el poste-, ramal horizontal hacia el punto destino.
    arm2_loop_i = 3
    arm2_elbow_segment = duct_segments[1 + (2 * arm2_loop_i)]
    raise "duct_segments[#{1 + (2 * arm2_loop_i)}] no es el codo esperado" unless arm2_elbow_segment[:type] == :elbow

    arm2_target_point, = point_at_segment_fraction(arm2_elbow_segment, 0.5)
    # Ajuste manual pedido por el usuario -igual que el primer brazo, la
    # DIRECCION se calcula a la altura ORIGINAL del punto destino -para
    # que se quede horizontal, sin componente Z-, y DESPUES se baja el
    # punto del poste -arm2_z-, no el punto destino.
    arm2_drop_mm = 300.0 # 150mm + 15cm mas bajado, pedido por el usuario
    arm2_original_axis_point = Geom::Point3d.new(centroid_x_mm.mm, centroid_y_mm.mm, arm2_target_point.z)
    arm2_direction_before_rotation = arm2_target_point - arm2_original_axis_point
    arm2_extra_mm = 500.0 # +50cm de largo, pedido por el usuario
    arm2_length_mm = arm2_direction_before_rotation.length.to_mm + arm2_extra_mm
    arm2_mid_mm = arm2_length_mm / 2.0
    # Radio FIJO para los angulos de giro -congelado con el valor
    # historico de arm2_extra_mm, 500mm-, para que acortar/alargar el
    # brazo despues -arm2_extra_mm- ya NO cambie los angulos de giro ya
    # calibrados -arm2_rotation_rad, arm2_leg_anchor_rotation_rad-. Solo
    # arm2_mid_mm -para POSICIONES: con10_2_mid, tramos de tubo- sigue
    # el largo real y en vivo del brazo.
    arm2_rotation_radius_mm = (arm2_direction_before_rotation.length.to_mm + 500.0) / 2.0
    arm2_z = arm2_target_point.z - arm2_drop_mm.mm
    raise 'el 2do brazo debe quedar arriba del primero -revisar arm2_loop_i/arm2_drop_mm-' unless arm2_z > arm_z

    post_axis_at_arm2 = Geom::Point3d.new(centroid_x_mm.mm, centroid_y_mm.mm, arm2_z)

    # Giro alrededor del poste -mismo patron que el primer brazo-, hacia
    # donde caminan las manecillas del reloj vistas desde arriba -
    # sentido NEGATIVO en este script-: 20cm de arco, luego 30cm mas,
    # luego 10cm mas, medidos en el radio del punto medio del brazo
    # -arm2_mid_mm-, pedido por el usuario.
    arm2_shift_mm = 850.0 # 200mm + 300mm + 100mm + 100mm + 150mm, pedido por el usuario
    arm2_rotation_rad = -(arm2_shift_mm / arm2_rotation_radius_mm)
    arm2_rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, arm2_rotation_rad)
    arm2_direction = arm2_direction_before_rotation.transform(arm2_rotation)

    con10_2 = PlayIdea::Conectores.create_connector('10', 'Galvanizado', con10_metadata, post_axis_at_arm2)
    con10_2_target_x = Z_AXIS
    con10_2_target_z = arm2_direction.reverse.normalize
    con10_2_target_y = con10_2_target_z.cross(con10_2_target_x)
    con10_2.transformation = Geom::Transformation.axes(
      post_axis_at_arm2, con10_2_target_x, con10_2_target_y, con10_2_target_z
    )
    instances << con10_2

    arm2_unit_direction = arm2_direction.normalize

    # CON-10 "de cabeza" -mismo patron que con10_mid del primer brazo-:
    # el PASO PRINCIPAL -no el ramal- queda alineado con el brazo -el
    # brazo pasa "a traves" de el-, y el ramal -de fabrica hacia -Z-
    # queda apuntando hacia ARRIBA. Va en el punto MEDIO del brazo, asi
    # que este tambien se parte en 2 tramos.
    arm2_mid_point = post_axis_at_arm2.offset(arm2_unit_direction, arm2_mid_mm.mm)

    # Giro pedido por el usuario -SOLO este conector y su tubito, nada
    # mas-: sobre el eje del propio brazo -arm2_unit_direction-, hacia
    # la izquierda visto parado en el poste mirando hacia la punta del
    # brazo -eso da signo NEGATIVO, ver nota de signo mas abajo-. 3cm de
    # arco medidos en el radio del tubo estructural -CENTRAL_TUBE_
    # OUTSIDE_MM/2-, no en el radio del brazo -es un giro chiquito
    # sobre un tubo delgado, no un giro grande alrededor del poste-.
    arm2_twist_shift_mm = 6.6
    arm2_twist_radius_mm = CENTRAL_TUBE_OUTSIDE_MM / 2.0
    arm2_twist_rotation_rad = -(arm2_twist_shift_mm / arm2_twist_radius_mm)
    arm2_twist_rotation = Geom::Transformation.rotation(ORIGIN, arm2_unit_direction, arm2_twist_rotation_rad)
    # Direccion real del ramal -antes recta hacia +Z, ahora girada
    # alrededor del brazo-, usada tanto para el conector como para el
    # tubito que sale de el.
    arm2_mid_branch_direction = Z_AXIS.transform(arm2_twist_rotation).normalize

    con10_2_mid = PlayIdea::Conectores.create_connector('10', 'Galvanizado', con10_metadata, arm2_mid_point)
    con10_2_mid_target_x = arm2_unit_direction # paso principal, alineado con el brazo
    con10_2_mid_target_z = arm2_mid_branch_direction.reverse # local -Z -el ramal- apunta hacia arm2_mid_branch_direction
    con10_2_mid_target_y = con10_2_mid_target_z.cross(con10_2_mid_target_x)
    con10_2_mid.transformation = Geom::Transformation.axes(
      arm2_mid_point, con10_2_mid_target_x, con10_2_mid_target_y, con10_2_mid_target_z
    )
    instances << con10_2_mid

    # Ancla FIJA -congelada en 600mm-: la pata y la solera NO siguen la
    # posicion en vivo del brazo, para que girar el brazo despues
    # -arm2_shift_mm- no las mueva.
    arm2_leg_anchor_shift_mm = 600.0
    arm2_leg_anchor_rotation_rad = -(arm2_leg_anchor_shift_mm / arm2_rotation_radius_mm)
    arm2_leg_anchor_rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, arm2_leg_anchor_rotation_rad)
    arm2_leg_anchor_direction = arm2_direction_before_rotation.transform(arm2_leg_anchor_rotation).normalize
    arm2_leg_anchor_point = post_axis_at_arm2.offset(arm2_leg_anchor_direction, arm2_rotation_radius_mm.mm)

    arm2_mid_leg_length_mm = 190.0 # +10cm, luego +1cm mas, pedido por el usuario
    arm2_mid_leg_raise_mm = 25.0 # +2cm, luego +5mm mas, pedido por el usuario
    arm2_mid_leg_start = arm2_mid_point.offset(arm2_mid_branch_direction, arm2_mid_leg_raise_mm.mm)
    arm2_mid_leg = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: arm2_mid_leg_length_mm, code: 'TUBO-ESTRUCTURAL-PATA-BRAZO-2-MEDIO'),
      arm2_mid_leg_start, arm2_mid_branch_direction
    )
    instances << arm2_mid_leg

    arm2_duct_near_x_mm = arm2_leg_anchor_point.x.to_mm
    arm2_duct_near_y_mm = arm2_leg_anchor_point.y.to_mm
    arm2_duct_point, arm2_duct_tangent = nearest_duct_point(duct_segments, arm2_duct_near_x_mm, arm2_duct_near_y_mm)
    arm2_mid_leg_top_point = Geom::Point3d.new(arm2_leg_anchor_point.x, arm2_leg_anchor_point.y, arm2_duct_point.z)
    arm2_solera_shift_mm = 10.0
    arm2_solera_lateral = Z_AXIS.cross(arm2_duct_tangent).normalize
    arm2_mid_leg_top_point = arm2_mid_leg_top_point.offset(arm2_solera_lateral, arm2_solera_shift_mm.mm)
    # Ajuste manual pedido por el usuario -1mm hacia su derecha, hacia
    # el exterior del tobogan-: RADIAL, alejandose del eje del poste
    # central -mismo convenio que mid_solera_away_from_post del primer
    # brazo-, medido desde la posicion YA con el corrido lateral.
    arm2_solera_radial_mm = 1.0
    arm2_solera_away_from_post = Geom::Vector3d.new(
      arm2_mid_leg_top_point.x.to_mm - centroid_x_mm, arm2_mid_leg_top_point.y.to_mm - centroid_y_mm, 0
    ).normalize
    arm2_mid_leg_top_point = arm2_mid_leg_top_point.offset(arm2_solera_away_from_post, arm2_solera_radial_mm.mm)
    arm2_solera_3in = PlayIdeaSoporteSoleraScript.build_piece(
      {}, arm2_mid_leg_top_point, arm2_duct_tangent, Z_AXIS.reverse, 76.2
    )
    instances << arm2_solera_3in

    # Correccion pedida por el usuario: arrancar EXACTO en post_axis_at_
    # arm2 -el centro del conector- hacia invadir el palito VERTICAL de
    # la T acostada -el paso principal, que sigue al poste-. Debe parar
    # justo en el limite del palito HORIZONTAL -el ramal, por donde
    # entra el brazo-, o sea con la misma holgura de siempre.
    # Ajuste pedido por el usuario -mismo brazo, su OTRO extremo-: en el
    # extremo del conector 10 de en medio -el que tiene el tubito
    # perpendicular- se estaba pasando de largo, atravesando el
    # conector. Holgura extra SOLO en ese extremo -no en el del poste-.
    arm2_tube_1_end_extra_clearance_mm = 25.0
    arm2_tube_1_growth_mm = 80.0 # +8cm hacia la punta, pedido por el usuario
    arm2_tube_1_start = post_axis_at_arm2.offset(arm2_unit_direction, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
    arm2_tube_1_length_mm = arm2_mid_mm - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM) - arm2_tube_1_end_extra_clearance_mm + arm2_tube_1_growth_mm
    arm2_tube_1 = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: arm2_tube_1_length_mm, code: 'TUBO-ESTRUCTURAL-BRAZO-2-1'),
      arm2_tube_1_start, arm2_direction
    )
    instances << arm2_tube_1

    # Pedido del usuario: el brazo de arriba debe ser SOLO este tramo
    # -arm2_tube_1, el que sale del poste central-. Se quito el segundo
    # tramo -arm2_tube_2, el que seguia del conector de en medio hacia
    # la punta-, ya no existe.

    # --- Soporte diagonal -pedido del usuario-: un tubo que une el
    # poste central con el tubo brazo, usando 2 conectores 12 -"T
    # inclinada a 45 grados"-. El CON-12 trae un paso recto -se monta
    # A TRAVES del poste o del brazo, como una abrazadera- mas un
    # ramal a 45 grados de ese paso -para el tubo diagonal-. Para que
    # el tubo diagonal entre derecho en los 2 ramales -ambos a 45
    # grados de su propio paso recto- el triangulo tiene que ser
    # ISOCELES: la distancia horizontal del poste al punto del brazo
    # debe ser IGUAL a la caida vertical de ese punto hasta el punto
    # del poste.
    arm2_brace_distance_mm = 400.0 # cuanto se aleja del poste sobre el brazo -ajustable-
    arm2_brace_arm_point = post_axis_at_arm2.offset(arm2_unit_direction, arm2_brace_distance_mm.mm)
    arm2_brace_post_point = Geom::Point3d.new(
      post_axis_at_arm2.x, post_axis_at_arm2.y, post_axis_at_arm2.z - arm2_brace_distance_mm.mm
    )

    con12_post = PlayIdea::Conectores.create_connector('12', 'Galvanizado', con10_metadata, arm2_brace_post_point)
    con12_post_target_x = Z_AXIS.reverse # paso recto, a lo largo del poste
    con12_post_target_z = arm2_unit_direction.reverse # con esto el ramal -45 grados- apunta hacia arriba Y hacia el brazo
    con12_post_target_y = con12_post_target_z.cross(con12_post_target_x)
    con12_post.transformation = Geom::Transformation.axes(
      arm2_brace_post_point, con12_post_target_x, con12_post_target_y, con12_post_target_z
    )
    instances << con12_post

    con12_arm = PlayIdea::Conectores.create_connector('12', 'Galvanizado', con10_metadata, arm2_brace_arm_point)
    con12_arm_target_x = arm2_unit_direction # paso recto, a lo largo del brazo
    con12_arm_target_z = Z_AXIS # con esto el ramal -45 grados- apunta hacia abajo Y hacia el poste
    con12_arm_target_y = con12_arm_target_z.cross(con12_arm_target_x)
    con12_arm.transformation = Geom::Transformation.axes(
      arm2_brace_arm_point, con12_arm_target_x, con12_arm_target_y, con12_arm_target_z
    )
    instances << con12_arm

    # El ramal del CON-12 NO arranca en el punto de colocacion del
    # conector -eso es el CENTRO de su paso recto-, arranca en la
    # SUPERFICIE de ese paso recto -desplazado por su propio radio,
    # PlayIdea::Conectores::OUTSIDE_MM/2-, hacia el lado de target_z.
    # Sin este desplazamiento el tubo diagonal arranca "flotando"
    # dentro del cuerpo del conector, no en su ramal real -por eso no
    # embonaba-.
    con12_receiver_radius_mm = PlayIdea::Conectores::OUTSIDE_MM / 2.0
    arm2_brace_contact_post = arm2_brace_post_point.offset(con12_post_target_z.reverse, con12_receiver_radius_mm.mm)
    arm2_brace_contact_arm = arm2_brace_arm_point.offset(con12_arm_target_z.reverse, con12_receiver_radius_mm.mm)

    arm2_brace_vector = arm2_brace_contact_arm - arm2_brace_contact_post
    arm2_brace_direction = arm2_brace_vector.normalize
    arm2_brace_full_length_mm = arm2_brace_vector.length.to_mm
    arm2_brace_start = arm2_brace_contact_post.offset(arm2_brace_direction, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
    arm2_brace_length_mm = arm2_brace_full_length_mm - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM)
    arm2_brace_tube = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: arm2_brace_length_mm, code: 'TUBO-ESTRUCTURAL-DIAGONAL-BRAZO-2'),
      arm2_brace_start, arm2_brace_direction
    )
    instances << arm2_brace_tube

    # --- Tercer brazo, hacia el CENTRO del 1er codo contando de ARRIBA
    # hacia ABAJO -mismo patron completo que el segundo brazo: poste,
    # CON-10 "acostado", tubo, CON-10 "de cabeza" -con giro/twist
    # disponibles en 0 por default-, pata + solera con ancla fija
    # -desacoplada del giro del brazo-, soporte diagonal con 2 CON-12-.
    # arm3_loop_i=0 porque duct_segments[1+2*i] es el codo, y el
    # conteo desde ARRIBA es i+1 -i=0 es el primer codo despues del
    # tramo recto, el mas alto de todos, pedido por el usuario-.
    arm3_loop_i = 0
    arm3_elbow_segment = duct_segments[1 + (2 * arm3_loop_i)]
    raise "duct_segments[#{1 + (2 * arm3_loop_i)}] no es el codo esperado" unless arm3_elbow_segment[:type] == :elbow

    arm3_target_point, arm3_target_tangent = point_at_segment_fraction(arm3_elbow_segment, 0.5)
    arm3_drop_mm = 530.0 # 300mm + 15cm + 8cm mas bajado, pedido por el usuario
    arm3_original_axis_point = Geom::Point3d.new(centroid_x_mm.mm, centroid_y_mm.mm, arm3_target_point.z)
    arm3_direction_before_rotation = arm3_target_point - arm3_original_axis_point
    arm3_extra_mm = 500.0 # mismo valor inicial que tenia el 2do brazo, ajustable
    arm3_length_mm = arm3_direction_before_rotation.length.to_mm + arm3_extra_mm
    arm3_mid_mm = arm3_length_mm / 2.0
    # Radio FIJO para los angulos de giro -ver arm2_rotation_radius_mm,
    # mismo motivo: que acortar/alargar el brazo no cambie los angulos-.
    arm3_rotation_radius_mm = (arm3_direction_before_rotation.length.to_mm + 500.0) / 2.0
    arm3_z = arm3_target_point.z - arm3_drop_mm.mm
    raise 'el 3er brazo debe quedar arriba del segundo -revisar arm3_loop_i/arm3_drop_mm-' unless arm3_z > arm2_z

    post_axis_at_arm3 = Geom::Point3d.new(centroid_x_mm.mm, centroid_y_mm.mm, arm3_z)

    # 10cm de arco hacia las manecillas del reloj, pedido por el usuario.
    arm3_shift_mm = 100.0
    arm3_rotation_rad = -(arm3_shift_mm / arm3_rotation_radius_mm)
    arm3_rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, arm3_rotation_rad)
    arm3_direction = arm3_direction_before_rotation.transform(arm3_rotation)

    con10_3 = PlayIdea::Conectores.create_connector('10', 'Galvanizado', con10_metadata, post_axis_at_arm3)
    con10_3_target_x = Z_AXIS
    con10_3_target_z = arm3_direction.reverse.normalize
    con10_3_target_y = con10_3_target_z.cross(con10_3_target_x)
    con10_3.transformation = Geom::Transformation.axes(
      post_axis_at_arm3, con10_3_target_x, con10_3_target_y, con10_3_target_z
    )
    instances << con10_3

    arm3_unit_direction = arm3_direction.normalize
    arm3_mid_point = post_axis_at_arm3.offset(arm3_unit_direction, arm3_mid_mm.mm)

    # Giro del conector de en medio y su tubito sobre el eje del propio
    # brazo -ver arm2_twist_shift_mm-, en 0 por default.
    arm3_twist_shift_mm = 0.0
    arm3_twist_radius_mm = CENTRAL_TUBE_OUTSIDE_MM / 2.0
    arm3_twist_rotation_rad = -(arm3_twist_shift_mm / arm3_twist_radius_mm)
    arm3_twist_rotation = Geom::Transformation.rotation(ORIGIN, arm3_unit_direction, arm3_twist_rotation_rad)
    arm3_mid_branch_direction = Z_AXIS.transform(arm3_twist_rotation).normalize

    con10_3_mid = PlayIdea::Conectores.create_connector('10', 'Galvanizado', con10_metadata, arm3_mid_point)
    con10_3_mid_target_x = arm3_unit_direction
    con10_3_mid_target_z = arm3_mid_branch_direction.reverse
    con10_3_mid_target_y = con10_3_mid_target_z.cross(con10_3_mid_target_x)
    con10_3_mid.transformation = Geom::Transformation.axes(
      arm3_mid_point, con10_3_mid_target_x, con10_3_mid_target_y, con10_3_mid_target_z
    )
    instances << con10_3_mid

    arm3_mid_leg_length_mm = 190.0 # igual que el brazo 2 -80mm base + 11cm-, el radio del brazo es casi identico
    arm3_mid_leg_raise_mm = 25.0
    arm3_mid_leg_start = arm3_mid_point.offset(arm3_mid_branch_direction, arm3_mid_leg_raise_mm.mm)
    arm3_mid_leg = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: arm3_mid_leg_length_mm, code: 'TUBO-ESTRUCTURAL-PATA-BRAZO-3-MEDIO'),
      arm3_mid_leg_start, arm3_mid_branch_direction
    )
    instances << arm3_mid_leg

    # La solera va DIRECTO al punto del codo objetivo -arm3_target_point/
    # arm3_target_tangent, ya calculados arriba con point_at_segment_fraction
    # sobre el MISMO segmento -arm3_elbow_segment-, sin busqueda-. NO usar
    # nearest_duct_point aqui: como la espiral esta muy apretada -ver skill
    # tobogan-completo-playidea-, esa busqueda puede enganchar un codo
    # distinto al que en verdad se quiere abrazar.
    arm3_mid_leg_top_point = arm3_target_point
    arm3_duct_tangent = arm3_target_tangent
    arm3_solera_3in = PlayIdeaSoporteSoleraScript.build_piece(
      {}, arm3_mid_leg_top_point, arm3_duct_tangent, Z_AXIS.reverse, 76.2
    )
    instances << arm3_solera_3in

    # Mismos ajustes que el brazo 2 -end_extra_clearance/growth-: sin
    # ellos el tubo se queda corto y no llega al conector de en medio.
    arm3_tube_1_end_extra_clearance_mm = 25.0
    arm3_tube_1_growth_mm = 80.0
    arm3_tube_1_start = post_axis_at_arm3.offset(arm3_unit_direction, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
    arm3_tube_1_length_mm = arm3_mid_mm - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM) - arm3_tube_1_end_extra_clearance_mm + arm3_tube_1_growth_mm
    arm3_tube_1 = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: arm3_tube_1_length_mm, code: 'TUBO-ESTRUCTURAL-BRAZO-3-1'),
      arm3_tube_1_start, arm3_direction
    )
    instances << arm3_tube_1

    # Soporte diagonal -mismo patron que el del 2do brazo, ver
    # con12_receiver_radius_mm arriba-: 2 CON-12 uniendo el poste y el
    # brazo, tubo diagonal arrancando en la superficie real de cada
    # conector -no en su centro-.
    arm3_brace_distance_mm = 400.0
    arm3_brace_arm_point = post_axis_at_arm3.offset(arm3_unit_direction, arm3_brace_distance_mm.mm)
    arm3_brace_post_point = Geom::Point3d.new(
      post_axis_at_arm3.x, post_axis_at_arm3.y, post_axis_at_arm3.z - arm3_brace_distance_mm.mm
    )

    con12_post_3 = PlayIdea::Conectores.create_connector('12', 'Galvanizado', con10_metadata, arm3_brace_post_point)
    con12_post_3_target_x = Z_AXIS.reverse
    con12_post_3_target_z = arm3_unit_direction.reverse
    con12_post_3_target_y = con12_post_3_target_z.cross(con12_post_3_target_x)
    con12_post_3.transformation = Geom::Transformation.axes(
      arm3_brace_post_point, con12_post_3_target_x, con12_post_3_target_y, con12_post_3_target_z
    )
    instances << con12_post_3

    con12_arm_3 = PlayIdea::Conectores.create_connector('12', 'Galvanizado', con10_metadata, arm3_brace_arm_point)
    con12_arm_3_target_x = arm3_unit_direction
    con12_arm_3_target_z = Z_AXIS
    con12_arm_3_target_y = con12_arm_3_target_z.cross(con12_arm_3_target_x)
    con12_arm_3.transformation = Geom::Transformation.axes(
      arm3_brace_arm_point, con12_arm_3_target_x, con12_arm_3_target_y, con12_arm_3_target_z
    )
    instances << con12_arm_3

    arm3_brace_contact_post = arm3_brace_post_point.offset(con12_post_3_target_z.reverse, con12_receiver_radius_mm.mm)
    arm3_brace_contact_arm = arm3_brace_arm_point.offset(con12_arm_3_target_z.reverse, con12_receiver_radius_mm.mm)

    arm3_brace_vector = arm3_brace_contact_arm - arm3_brace_contact_post
    arm3_brace_direction = arm3_brace_vector.normalize
    arm3_brace_full_length_mm = arm3_brace_vector.length.to_mm
    arm3_brace_start = arm3_brace_contact_post.offset(arm3_brace_direction, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
    arm3_brace_length_mm = arm3_brace_full_length_mm - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM)
    arm3_brace_tube = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: arm3_brace_length_mm, code: 'TUBO-ESTRUCTURAL-DIAGONAL-BRAZO-3'),
      arm3_brace_start, arm3_brace_direction
    )
    instances << arm3_brace_tube

    # --- Cuarto brazo, hacia el CENTRO del 7º codo contando A PARTIR del
    # codo pegado al recto -es decir, contando el pegado al recto como el
    # 1º-: 7º = i=6, uno antes del 8º -el usuario corrigio, el objetivo
    # original (i=7) no era el codo correcto-. Va en ALTURA entre el
    # brazo mas bajo -hacia la salida- y el brazo de en medio -arm2-.
    # Mismo patron limpio que el brazo 3 -ya sin el bug de
    # nearest_duct_point: solera directo al punto conocido del codo, no
    # busqueda global-.
    arm4_loop_i = 6
    arm4_elbow_segment = duct_segments[1 + (2 * arm4_loop_i)]
    raise "duct_segments[#{1 + (2 * arm4_loop_i)}] no es el codo esperado" unless arm4_elbow_segment[:type] == :elbow

    arm4_target_point, arm4_target_tangent = point_at_segment_fraction(arm4_elbow_segment, 0.5)
    arm4_drop_mm = 430.0 # 300mm + 15cm bajado, luego 2cm subido, pedido por el usuario
    arm4_original_axis_point = Geom::Point3d.new(centroid_x_mm.mm, centroid_y_mm.mm, arm4_target_point.z)
    arm4_direction_before_rotation = arm4_target_point - arm4_original_axis_point
    arm4_extra_mm = 500.0
    arm4_length_mm = arm4_direction_before_rotation.length.to_mm + arm4_extra_mm
    arm4_mid_mm = arm4_length_mm / 2.0
    arm4_rotation_radius_mm = (arm4_direction_before_rotation.length.to_mm + 500.0) / 2.0
    arm4_z = arm4_target_point.z - arm4_drop_mm.mm
    raise 'el 4to brazo debe quedar entre el mas bajo y el de en medio -revisar arm4_loop_i/arm4_drop_mm-' unless arm4_z > arm_z && arm4_z < arm2_z

    post_axis_at_arm4 = Geom::Point3d.new(centroid_x_mm.mm, centroid_y_mm.mm, arm4_z)

    arm4_shift_mm = 270.0 # 300mm - 2cm - 1cm hacia la izquierda -contrario a las manecillas-, pedido por el usuario
    arm4_rotation_rad = -(arm4_shift_mm / arm4_rotation_radius_mm)
    arm4_rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, arm4_rotation_rad)
    arm4_direction = arm4_direction_before_rotation.transform(arm4_rotation)

    con10_4 = PlayIdea::Conectores.create_connector('10', 'Galvanizado', con10_metadata, post_axis_at_arm4)
    con10_4_target_x = Z_AXIS
    con10_4_target_z = arm4_direction.reverse.normalize
    con10_4_target_y = con10_4_target_z.cross(con10_4_target_x)
    con10_4.transformation = Geom::Transformation.axes(
      post_axis_at_arm4, con10_4_target_x, con10_4_target_y, con10_4_target_z
    )
    instances << con10_4

    arm4_unit_direction = arm4_direction.normalize
    arm4_mid_point = post_axis_at_arm4.offset(arm4_unit_direction, arm4_mid_mm.mm)

    # Pedido del usuario: el conector de en medio tambien debe INCLINARSE
    # hacia la solera -no solo alargar/anguiar el tubito para compensar,
    # eso ya se probo y no basta-. Un CON-10 "de cabeza" solo puede
    # apuntar su ramal DENTRO del plano perpendicular a su paso
    # principal -el brazo-, nunca hacia adelante/atras sobre el brazo
    # mismo -es una T, no una rotula-. Se calcula la direccion ideal
    # -derecho hacia arm4_target_point, el punto real de la solera- y
    # se PROYECTA sobre ese plano perpendicular -lo mas cerca que un
    # CON-10 puede fisicamente apuntar hacia alla-, en vez del giro
    # arbitrario que se usaba antes -arm4_twist_shift_mm-.
    arm4_to_solera = arm4_target_point - arm4_mid_point
    arm4_to_solera_along_arm = arm4_to_solera.dot(arm4_unit_direction)
    arm4_branch_raw = Geom::Vector3d.new(
      arm4_to_solera.x - (arm4_unit_direction.x * arm4_to_solera_along_arm),
      arm4_to_solera.y - (arm4_unit_direction.y * arm4_to_solera_along_arm),
      arm4_to_solera.z - (arm4_unit_direction.z * arm4_to_solera_along_arm)
    )
    arm4_mid_branch_direction = arm4_branch_raw.normalize

    con10_4_mid = PlayIdea::Conectores.create_connector('10', 'Galvanizado', con10_metadata, arm4_mid_point)
    con10_4_mid_target_x = arm4_unit_direction
    con10_4_mid_target_z = arm4_mid_branch_direction.reverse
    con10_4_mid_target_y = con10_4_mid_target_z.cross(con10_4_mid_target_x)
    con10_4_mid.transformation = Geom::Transformation.axes(
      arm4_mid_point, con10_4_mid_target_x, con10_4_mid_target_y, con10_4_mid_target_z
    )
    instances << con10_4_mid

    # Pedido del usuario: el tubito debe TOCAR de verdad la solera -no
    # quedar cortito o largo por su cuenta-, con un angulo razonable
    # -no muy pronunciado- para que realmente la soporte. Se calcula la
    # direccion/largo DIRECTO desde su base -en el conector- hasta el
    # punto fijo de la solera -arm4_target_point-, en vez de un largo y
    # una direccion fijos como antes.
    # Correccion pedida por el usuario: el tubito debe salir en la MISMA
    # direccion que el conector -arm4_mid_branch_direction-, sin ningun
    # doblez -antes apuntaba directo a la solera, con un angulo distinto
    # al del conector, como si se torciera justo al salir-. Largo FIJO
    # de 8cm -pedido por el usuario-, no estirado hasta la solera.
    arm4_mid_leg_raise_mm = 25.0
    arm4_mid_leg_base = arm4_mid_point.offset(arm4_mid_branch_direction, arm4_mid_leg_raise_mm.mm)
    arm4_mid_leg_direction = arm4_mid_branch_direction
    arm4_mid_leg_length_mm = 80.0
    arm4_mid_leg = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: arm4_mid_leg_length_mm, code: 'TUBO-ESTRUCTURAL-PATA-BRAZO-4-MEDIO'),
      arm4_mid_leg_base, arm4_mid_leg_direction
    )
    instances << arm4_mid_leg

    arm4_mid_leg_top_point = arm4_target_point
    arm4_duct_tangent = arm4_target_tangent
    arm4_solera_3in = PlayIdeaSoporteSoleraScript.build_piece(
      {}, arm4_mid_leg_top_point, arm4_duct_tangent, Z_AXIS.reverse, 76.2
    )
    instances << arm4_solera_3in

    arm4_tube_1_end_extra_clearance_mm = 25.0
    arm4_tube_1_growth_mm = 80.0
    arm4_tube_1_start = post_axis_at_arm4.offset(arm4_unit_direction, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
    arm4_tube_1_length_mm = arm4_mid_mm - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM) - arm4_tube_1_end_extra_clearance_mm + arm4_tube_1_growth_mm
    arm4_tube_1 = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: arm4_tube_1_length_mm, code: 'TUBO-ESTRUCTURAL-BRAZO-4-1'),
      arm4_tube_1_start, arm4_direction
    )
    instances << arm4_tube_1

    arm4_brace_distance_mm = 400.0
    arm4_brace_arm_point = post_axis_at_arm4.offset(arm4_unit_direction, arm4_brace_distance_mm.mm)
    arm4_brace_post_point = Geom::Point3d.new(
      post_axis_at_arm4.x, post_axis_at_arm4.y, post_axis_at_arm4.z - arm4_brace_distance_mm.mm
    )

    con12_post_4 = PlayIdea::Conectores.create_connector('12', 'Galvanizado', con10_metadata, arm4_brace_post_point)
    con12_post_4_target_x = Z_AXIS.reverse
    con12_post_4_target_z = arm4_unit_direction.reverse
    con12_post_4_target_y = con12_post_4_target_z.cross(con12_post_4_target_x)
    con12_post_4.transformation = Geom::Transformation.axes(
      arm4_brace_post_point, con12_post_4_target_x, con12_post_4_target_y, con12_post_4_target_z
    )
    instances << con12_post_4

    con12_arm_4 = PlayIdea::Conectores.create_connector('12', 'Galvanizado', con10_metadata, arm4_brace_arm_point)
    con12_arm_4_target_x = arm4_unit_direction
    con12_arm_4_target_z = Z_AXIS
    con12_arm_4_target_y = con12_arm_4_target_z.cross(con12_arm_4_target_x)
    con12_arm_4.transformation = Geom::Transformation.axes(
      arm4_brace_arm_point, con12_arm_4_target_x, con12_arm_4_target_y, con12_arm_4_target_z
    )
    instances << con12_arm_4

    arm4_brace_contact_post = arm4_brace_post_point.offset(con12_post_4_target_z.reverse, con12_receiver_radius_mm.mm)
    arm4_brace_contact_arm = arm4_brace_arm_point.offset(con12_arm_4_target_z.reverse, con12_receiver_radius_mm.mm)

    arm4_brace_vector = arm4_brace_contact_arm - arm4_brace_contact_post
    arm4_brace_direction = arm4_brace_vector.normalize
    arm4_brace_full_length_mm = arm4_brace_vector.length.to_mm
    arm4_brace_start = arm4_brace_contact_post.offset(arm4_brace_direction, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
    arm4_brace_length_mm = arm4_brace_full_length_mm - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM)
    arm4_brace_tube = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: arm4_brace_length_mm, code: 'TUBO-ESTRUCTURAL-DIAGONAL-BRAZO-4'),
      arm4_brace_start, arm4_brace_direction
    )
    instances << arm4_brace_tube

    # Poste partido en 5 tramos -entre CON-61/CON-10 #1, CON-10 #1/
    # CON-10 #4, CON-10 #4/CON-10 #2, CON-10 #2/CON-10 #3, y CON-10 #3/
    # arriba-, mas los 4 brazos horizontales.
    post_lower_length_mm = (arm_z - ground_z).to_mm
    post_lower = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: post_lower_length_mm, code: 'TUBO-ESTRUCTURAL-POSTE-INFERIOR'),
      con61_point, Z_AXIS
    )
    instances << post_lower

    post_mid_a_length_mm = (arm4_z - arm_z).to_mm
    post_mid_a = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: post_mid_a_length_mm, code: 'TUBO-ESTRUCTURAL-POSTE-MEDIO-A'),
      post_axis_at_arm, Z_AXIS
    )
    instances << post_mid_a

    post_mid_length_mm = (arm2_z - arm4_z).to_mm
    post_mid = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: post_mid_length_mm, code: 'TUBO-ESTRUCTURAL-POSTE-MEDIO'),
      post_axis_at_arm4, Z_AXIS
    )
    instances << post_mid

    post_mid_2_length_mm = (arm3_z - arm2_z).to_mm
    post_mid_2 = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: post_mid_2_length_mm, code: 'TUBO-ESTRUCTURAL-POSTE-MEDIO-2'),
      post_axis_at_arm2, Z_AXIS
    )
    instances << post_mid_2

    post_upper_length_mm = (start_z - arm3_z).to_mm
    post_upper = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: post_upper_length_mm, code: 'TUBO-ESTRUCTURAL-POSTE-SUPERIOR'),
      post_axis_at_arm3, Z_AXIS
    )
    instances << post_upper

    # arm_length_mm/arm_mid_mm YA se calcularon arriba -antes de rotar-.
    # La dirección -arm_direction- ya rotada no cambia el largo; el CON-
    # 10 de la punta usa arm_length_mm para su posición, así que se
    # mueve solo si ese número cambia -sigue quedando en la punta del
    # brazo-. El TUBO se queda CONNECTOR_SOCKET_CLEARANCE_MM antes del
    # centro de CADA conector -el conector, no el tubo, es quien ocupa
    # esos últimos tramos con su propio cuerpo/ramal-; si el tubo llega
    # hasta el centro exacto, se mete de más y atraviesa el paso
    # principal -el "palito vertical"- del conector. Recorta por AMBOS
    # extremos: el de arranque -el primer CON-10, junto al poste- y el
    # de la punta -el segundo CON-10, ver más abajo-. Partido en 2
    # tramos -antes y después del CON-10 "de cabeza" a la mitad del
    # brazo, ver más abajo-, cada uno con su propio recorte de
    # CONNECTOR_SOCKET_CLEARANCE_MM en los 2 extremos que dan a un
    # conector.
    arm_unit_direction = arm_direction.normalize
    arm_mid_point = post_axis_at_arm.offset(arm_unit_direction, arm_mid_mm.mm)

    arm_tube_start = post_axis_at_arm.offset(arm_unit_direction, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
    arm_tube_1_length_mm = arm_mid_mm - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM)
    arm_tube_1 = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: arm_tube_1_length_mm, code: 'TUBO-ESTRUCTURAL-BRAZO-SALIDA-1'),
      arm_tube_start, arm_direction
    )
    instances << arm_tube_1

    arm_tube_2_start = arm_mid_point.offset(arm_unit_direction, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
    arm_tube_2_length_mm = (arm_length_mm - arm_mid_mm) - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM)
    arm_tube_2 = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: arm_tube_2_length_mm, code: 'TUBO-ESTRUCTURAL-BRAZO-SALIDA-2'),
      arm_tube_2_start, arm_direction
    )
    instances << arm_tube_2

    # --- CON-10 "de cabeza" -al revés de la de la punta-: el PASO
    # PRINCIPAL -no el ramal- es el que embona con el brazo -queda
    # alineado con arm_direction, el brazo pasa "a través" de él-, y el
    # ramal -de fábrica hacia -Z- se queda apuntando hacia ARRIBA. ---
    con10_mid = PlayIdea::Conectores.create_connector('10', 'Galvanizado', con10_metadata, arm_mid_point)
    con10_mid_target_x = arm_unit_direction # paso principal, alineado con el brazo
    con10_mid_target_z = Z_AXIS.reverse # local -Z -el ramal- pasa a apuntar hacia arriba
    con10_mid_target_y = con10_mid_target_z.cross(con10_mid_target_x)
    con10_mid.transformation = Geom::Transformation.axes(
      arm_mid_point, con10_mid_target_x, con10_mid_target_y, con10_mid_target_z
    )
    instances << con10_mid

    # --- Pata vertical desde el ramal del CON-10 de en medio, subiendo
    # hasta el punto REAL del ducto más cercano en planta -X,Y- a la
    # posición del brazo -sin importar a qué altura caiga ese punto-,
    # más una solera de 3" ahí, abrazando el tubo real con su propia
    # tangente local -no la dirección del soporte original-.
    duct_near_x_mm = arm_mid_point.x.to_mm
    duct_near_y_mm = arm_mid_point.y.to_mm
    duct_point, duct_tangent = nearest_duct_point(duct_segments, duct_near_x_mm, duct_near_y_mm)
    mid_leg_top_point = Geom::Point3d.new(arm_mid_point.x, arm_mid_point.y, duct_point.z)
    # Ajuste manual pedido por el usuario -la solera se veía corrida a
    # la izquierda-: recorrida 10cm LATERAL -perpendicular al tubo, no
    # a lo largo de él-. La prueba con duct_tangent -a lo largo del
    # tubo- la movió "hacia el frente de la salida", no lateral -de ahí
    # se confirmó el eje equivocado-. Lateral = perpendicular a la
    # tangente Y a la vertical, un vector horizontal que cruza el tubo.
    mid_solera_shift_mm = 60.0
    mid_solera_lateral = Z_AXIS.cross(duct_tangent).normalize # orden invertido -salió al lado contrario-
    mid_leg_top_point = mid_leg_top_point.offset(mid_solera_lateral, mid_solera_shift_mm.mm)

    # Otro ajuste manual: 5cm en sentido CONTRARIO al poste central -
    # radialmente hacia afuera, alejándose del eje del poste-, medido
    # desde la posición ACTUAL de la solera -ya con el corrido lateral
    # aplicado-, no desde la posición original del brazo.
    mid_solera_radial_mm = 35.0
    mid_solera_away_from_post = Geom::Vector3d.new(
      mid_leg_top_point.x.to_mm - centroid_x_mm, mid_leg_top_point.y.to_mm - centroid_y_mm, 0
    ).normalize
    mid_leg_top_point = mid_leg_top_point.offset(mid_solera_away_from_post, mid_solera_radial_mm.mm)

    # Otro ajuste más: 1cm hacia el CON-61 de la PUNTA del brazo -NO el
    # del poste central, el otro-. Ese conector se calcula formalmente
    # más abajo -arm_end_point/tip_con61_point-, pero su X,Y no depende
    # de nada que cambie después, así que se repite aquí el mismo
    # cálculo -post_axis_at_arm + arm_length_mm en arm_unit_direction-
    # sin necesidad de reordenar el resto del código.
    tip_con61_xy_target = post_axis_at_arm.offset(arm_unit_direction, arm_length_mm.mm)
    mid_solera_toward_tip61 = Geom::Vector3d.new(
      tip_con61_xy_target.x.to_mm - mid_leg_top_point.x.to_mm,
      tip_con61_xy_target.y.to_mm - mid_leg_top_point.y.to_mm,
      0
    ).normalize
    mid_solera_toward_tip61_mm = 10.0
    mid_leg_top_point = mid_leg_top_point.offset(mid_solera_toward_tip61, mid_solera_toward_tip61_mm.mm)

    # Largo FIJO pedido por el usuario -70mm, luego 60mm, luego +1mm-.
    # La solera NO se toca -ya estaba bien colocada-, solo se acorta el
    # tubo. Después, subido 1.5cm sobre Z y luego 1cm más -2.5cm en
    # total- sobre Z -mismo largo, arranca más arriba-.
    mid_leg_length_mm = 63.0
    mid_leg_raise_mm = 25.0
    mid_leg_start = arm_mid_point.offset(Z_AXIS, mid_leg_raise_mm.mm)
    mid_leg = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: mid_leg_length_mm, code: 'TUBO-ESTRUCTURAL-PATA-BRAZO-MEDIO'),
      mid_leg_start, Z_AXIS
    )
    instances << mid_leg

    solera_3in = PlayIdeaSoporteSoleraScript.build_piece(
      {}, mid_leg_top_point, duct_tangent, Z_AXIS.reverse, 76.2
    )
    instances << solera_3in

    # --- CON-10 en la PUNTA del brazo -ahora más largo-, "T acostada":
    # el RAMAL -no el paso principal- es el que embona con el brazo
    # -abre hacia atrás, de vuelta hacia el poste, para recibir la
    # punta del tubo que llega de ese lado-, y el paso principal -de
    # fábrica horizontal- pasa a quedar VERTICAL, libre para seguir
    # hacia arriba después. ---
    arm_end_point = post_axis_at_arm.offset(arm_unit_direction, arm_length_mm.mm)
    con10_up = PlayIdea::Conectores.create_connector('10', 'Galvanizado', con10_metadata, arm_end_point)
    con10_up_target_x = Z_AXIS # paso principal -de fábrica horizontal-, ahora vertical
    con10_up_target_z = arm_unit_direction # local -Z -el ramal- abre hacia atrás, hacia el poste
    con10_up_target_y = con10_up_target_z.cross(con10_up_target_x)
    con10_up.transformation = Geom::Transformation.axes(
      arm_end_point, con10_up_target_x, con10_up_target_y, con10_up_target_z
    )
    instances << con10_up

    # --- Pata vertical en la punta del brazo -entra en el paso
    # principal -vertical, "el palo de la T acostada"- del segundo
    # CON-10-, bajando hasta un CON-61 al MISMO nivel que el CON-61 del
    # poste central -mismo ground_z-. Misma X,Y que la punta del brazo,
    # el tubo se queda vertical todo el trayecto. ---
    tip_con61_point = Geom::Point3d.new(arm_end_point.x, arm_end_point.y, ground_z)
    tip_con61 = PlayIdea::Conectores.create_connector('61', 'Galvanizado', con61_metadata, tip_con61_point)
    instances << tip_con61

    # Le faltaban ~6cm para tocar el CON-10 de arriba -confirmado por el
    # usuario viéndolo en SketchUp-, así que aquí NO se resta el
    # CONNECTOR_SOCKET_CLEARANCE_MM genérico -es una cavidad distinta a
    # la del brazo, más profunda-; se alarga TIP_POST_EXTRA_MM extra en
    # vez de recortar.
    tip_post_length_mm = (arm_end_point.z - ground_z).to_mm + TIP_POST_EXTRA_MM
    tip_post = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: tip_post_length_mm, code: 'TUBO-ESTRUCTURAL-PATA-BRAZO'),
      tip_con61_point, Z_AXIS
    )
    instances << tip_post

    # Altura real acumulada -de la caída de la espiral, sin contar el
    # tramo recto de arranque, que ahora es horizontal y no aporta-.
    # OJO: Point3d#z devuelve un Length -no un Float plano-, hay que
    # convertir con #to_mm explícito antes de hacer aritmética de
    # unidades "a mano".
    resulting_height_mm = (start_z - point.z).to_mm
    total_loops = (phi - heading_phi) / (2.0 * Math::PI) # informativo, ya no se fuerza a nada

    model.start_operation('Agrupar tobogán completo', true)
    group = model.active_entities.add_group(instances)
    group.name = "Tobogán completo (~#{(resulting_height_mm / 1000.0).round(1)}m, " \
                 "~#{total_loops.round(2)} vueltas)"
    model.commit_operation

    puts "Tobogán completo: tramo recto de arranque + #{ELBOW_COUNT} codos de 90° " \
         "-#{STEADY_ELBOW_COUNT} de espiral a inclinación constante " \
         "#{(pitch * 180.0 / Math::PI).round(2)}° más 2 de transición horizontal-, " \
         "entrada y salida horizontales -el rumbo final de la salida ya NO se fuerza a nada-, " \
         "~#{total_loops.round(2)} vueltas, altura ≈#{(resulting_height_mm / 1000.0).round(3)}m, " \
         "poste central + CON-61 en la base, 1er brazo -hacia la salida- de #{(arm_length_mm / 10.0).round(1)}cm " \
         "vía CON-10 -faltan los demás soportes-."

    group
  end

  # Un clic: coloca el arranque -parte de arriba, extremo LISO del
  # primer codo- en el punto marcado. El primer codo entra hacia
  # +X_AXIS -dirección fija, gira el grupo después con las herramientas
  # normales de SketchUp si hace falta otra orientación u otro punto de
  # anclaje en la plataforma-.
  class PlacementTool
    def initialize(params)
      @params = params
      @input_point = Sketchup::InputPoint.new
    end

    def activate
      Sketchup.set_status_text('Haz clic para colocar el arranque -arriba- del tobogán completo.', SB_PROMPT)
    end

    def onMouseMove(_flags, x, y, view)
      @input_point.pick(view, x, y)
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      @input_point.pick(view, x, y)
      # OJO: sin wrap propio de start_operation/commit_operation aquí -
      # cada pieza dependiente ya abre y cierra su PROPIA operación
      # -sin declararse "nested"-, así que envolver esta llamada en
      # otra operación externa chocaría con eso. build_assembly deja
      # una operación separada por cada pieza más una final para el
      # agrupado -varios pasos de deshacer en vez de uno solo, pero sin
      # tocar los 2 scripts dependientes-.
      PlayIdeaToboganCompletoScriptBrazo3.build_assembly(@input_point.position, X_AXIS)
      Sketchup.active_model.select_tool(nil)
    end

    def draw(view)
      @input_point.draw(view) if @input_point.valid?
    end

    def onCancel(_reason, _view)
      Sketchup.active_model.select_tool(nil)
    end

    def getExtents
      bounds = Geom::BoundingBox.new
      bounds.add(@input_point.position) if @input_point.valid?
      bounds
    end
  end
end

PlayIdeaToboganCompletoScriptBrazo3.start
