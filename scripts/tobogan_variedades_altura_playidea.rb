# Script suelto (NO es un plugin instalable) para PROBAR el concepto de
# parametrizar el tobogán completo -scripts/tobogan_completo_playidea.rb-
# por ALTURA TOTAL, pensando en integrarlo algún día al constructor de
# módulos -el usuario quiere poder pedir "un tobogán de tantos metros" y
# que la inclinación, el número de vueltas y el número/posición de los
# brazos de soporte se ajusten solos-.
#
# Genera 5 variantes -3, 4, 5, 6 y 7 metros- una junto a otra, cada una
# con su propia inclinación resuelta por bisección para dar EXACTO el
# alto pedido -mismo método ya usado para fijar tobogan_completo_playidea
# en 4.000m, generalizado aquí a cualquier altura-.
#
# Los brazos de soporte de cada variante son automáticos -sin el ajuste
# fino manual (giro, holguras) que sí se le hizo a mano al tobogán de
# referencia en tobogan_completo_playidea_brazo3.rb/_brazo5.rb-: sirven
# para ver que el CONCEPTO de "más brazos en un tobogán más alto" ya
# funciona, no son la versión final. Cargar con:
#   load '/Users/minorusal/Documents/SKETCHUP/scripts/tobogan_variedades_altura_playidea.rb'

Object.send(:remove_const, :PlayIdeaToboganVariedadesAlturaScript) if defined?(PlayIdeaToboganVariedadesAlturaScript)

module PlayIdeaToboganVariedadesAlturaScript
  extend self

  SCRIPTS_DIR = '/Users/minorusal/Documents/SKETCHUP/scripts'.freeze
  DEPENDENCIES = %w[
    tobogan_recto_playidea.rb
    codo_90_playidea.rb
    salida_tobogan_playidea.rb
    soporte_solera_playidea.rb
  ].freeze
  STRUCTURE_DEPENDENCIES = [
    '/Users/minorusal/Documents/SKETCHUP/creador_tubos_playidea/main.rb',
    '/Users/minorusal/Documents/SKETCHUP/conectores_playidea/main.rb'
  ].freeze

  # A diferencia de tobogan_completo_playidea.rb -donde el numero de
  # codos esta fijo y solo la inclinacion se resuelve por biseccion-,
  # aqui TAMBIEN se busca el numero de codos de espiral por variante:
  # con muy pocos codos, un tobogan alto necesita una inclinacion muy
  # pronunciada -"kamikaze"-, asi que se agregan mas vueltas -mas
  # codos- hasta que la inclinacion baje a un rango razonable. Minimo
  # de codos = el ya validado a mano -6 de espiral, 8 total-.
  MIN_STEADY_ELBOW_COUNT = 6
  MAX_STEADY_ELBOW_COUNT = 20 # limite de busqueda, no deberia alcanzarse en el rango 3-7m
  # "menos kamikaze", pedido por el usuario -si un tobogan queda muy
  # alto, no debe subirse la inclinacion, mejor agregarle vueltas-. Muy
  # cerca del valor ya validado a mano en el tobogan de referencia
  # -20.08° para 4m-, para que ninguna variante se incline mucho mas
  # que eso.
  MAX_REASONABLE_PITCH_DEG = 22.0
  TRANSITION_SWEEP_RAD = Math::PI / 2.0

  CENTRAL_TUBE_OUTSIDE_MM = 38.1
  CENTRAL_TUBE_WALL_MM = 1.50
  CENTRAL_TUBE_INSIDE_MM = CENTRAL_TUBE_OUTSIDE_MM - (2.0 * CENTRAL_TUBE_WALL_MM)
  CENTRAL_TUBE_COLOR = 'Negro'.freeze
  CON61_BELOW_EXIT_MM = 300.0
  CONNECTOR_SOCKET_CLEARANCE_MM = 25.0

  # Separación horizontal entre el arranque de cada variante -generosa,
  # para que quepan sin encimarse aunque la espiral se abra distinto en
  # cada una-.
  VARIANT_SPACING_MM = 7000.0
  TARGET_HEIGHTS_MM = [3000.0, 4000.0, 5000.0, 6000.0, 7000.0].freeze

  def start
    DEPENDENCIES.each { |file| load File.join(SCRIPTS_DIR, file) }
    STRUCTURE_DEPENDENCIES.each { |file| load file }
    Sketchup.active_model.select_tool(PlacementTool.new({}))
  rescue StandardError => error
    UI.messagebox("No fue posible iniciar las variedades de altura:\n#{error.message}")
    puts error.full_message
  end

  def dir_at(phi, pitch)
    Geom::Vector3d.new(
      Math.cos(pitch) * Math.cos(phi),
      Math.cos(pitch) * Math.sin(phi),
      -Math.sin(pitch)
    )
  end

  # --- Bisección de inclinación por altura -------------------------------
  # Réplica en Float puro -sin SketchUp, para poder bisectar rápido, ver
  # skill sketchup-plugins "simular las fórmulas del plugin en Ruby puro"-
  # de la caída vertical total a través de los ELBOW_COUNT codos. La caída
  # NO depende del rumbo -phi/delta_phi-, solo de la inclinación en cada
  # codo -dir_at(...).z = -sin(pitch)-, así que no hace falta simular la
  # espiral completa en planta para resolver la altura, solo el eje Z.
  def total_drop_mm_for_pitch(pitch_deg, elbow_count, bend_radius_mm, ceja_mm)
    pitch = pitch_deg * Math::PI / 180.0
    dx_local = bend_radius_mm * Math.sin(TRANSITION_SWEEP_RAD)
    dy_local = bend_radius_mm * (1.0 - Math.cos(TRANSITION_SWEEP_RAD))
    z = 0.0
    elbow_count.times do |i|
      is_entry = i.zero?
      is_exit = (i == elbow_count - 1)
      entry_pitch = is_entry ? 0.0 : pitch
      exit_pitch = is_exit ? 0.0 : pitch
      dz = -Math.sin(entry_pitch)
      edz = -Math.sin(exit_pitch)
      z += (dz * dx_local) + (edz * dy_local) # bend_offset.z, sumado DIRECTO -ver nota abajo-
      z += edz * ceja_mm
    end
    -z
  end

  # altura total -de la base del CON-61 a la superficie EXTERIOR de
  # arriba del tramo recto- = caida_por_codos + 2*radio_exterior_ducto
  # (una vez para "exterior de arriba" al inicio, otra para "base" al
  # final, donde se resta el radio para llegar al fondo del tubo antes
  # de bajar CON61_BELOW_EXIT_MM) + CON61_BELOW_EXIT_MM. Verificado:
  # da EXACTO 4.000m en pitch=20.08° con elbow_count=8, el valor ya
  # validado a mano en tobogan_completo_playidea.rb.
  def height_mm_for_pitch(pitch_deg, elbow_count, bend_radius_mm, ceja_mm, duct_outside_r_mm)
    total_drop_mm_for_pitch(pitch_deg, elbow_count, bend_radius_mm, ceja_mm) + (2.0 * duct_outside_r_mm) + CON61_BELOW_EXIT_MM
  end

  # Bisección simple -la altura crece con la inclinación, monotónica-.
  # Devuelve nil si ni con pitch=44° -limite fisico del codo, <45°- se
  # alcanza la altura pedida con este numero de codos -hace falta mas
  # vueltas, ver elbow_count_and_pitch_for_height-.
  def pitch_deg_for_height(target_height_mm, elbow_count, bend_radius_mm, ceja_mm, duct_outside_r_mm)
    low = 1.0
    high = 44.0
    return nil if height_mm_for_pitch(high, elbow_count, bend_radius_mm, ceja_mm, duct_outside_r_mm) < target_height_mm

    30.times do
      mid = (low + high) / 2.0
      h = height_mm_for_pitch(mid, elbow_count, bend_radius_mm, ceja_mm, duct_outside_r_mm)
      if h < target_height_mm
        low = mid
      else
        high = mid
      end
    end
    (low + high) / 2.0
  end

  # Busca el MENOR numero de codos de espiral -MIN_STEADY_ELBOW_COUNT
  # hacia arriba- tal que la inclinacion resuelta para la altura pedida
  # ya no pase de MAX_REASONABLE_PITCH_DEG -"menos kamikaze"-. Un
  # tobogan mas alto con el mismo numero de codos necesitaria una
  # inclinacion cada vez mas pronunciada; agregar vueltas la reparte.
  # REVERTIDO -pedido del usuario, regresión real-: se había cambiado a
  # buscar el elbow_count con MEJOR alineamiento salida↔entrada en TODO
  # el rango -ver skill tobogan-completo-playidea-, pero eso podía elegir
  # un elbow_count mucho más alto -más vueltas, pitch mucho más angosto-
  # solo por unos grados de alineamiento que casi nunca importaban -
  # verificado numéricamente: para 5m elegía elbow_count=20 -pitch=9.3°,
  # ~5 vueltas- en vez de elbow_count=10 -pitch=20°, ~2.7 vueltas-, con
  # el desalineamiento apenas mejorando -~28° en ambos casos-. Ductos tan
  # apretados quedan "pegados" entre sí. De vuelta al PRIMER elbow_count
  # con pitch razonable, sin buscar alineamiento -comportamiento
  # original, validado-.
  def elbow_count_and_pitch_for_height(target_height_mm, bend_radius_mm, ceja_mm, duct_outside_r_mm)
    steady = MIN_STEADY_ELBOW_COUNT
    while steady <= MAX_STEADY_ELBOW_COUNT
      elbow_count = steady + 2
      pitch_deg = pitch_deg_for_height(target_height_mm, elbow_count, bend_radius_mm, ceja_mm, duct_outside_r_mm)
      return [elbow_count, pitch_deg] if pitch_deg && pitch_deg <= MAX_REASONABLE_PITCH_DEG

      steady += 1
    end
    # No se encontro combinacion razonable dentro del limite de busqueda
    # -no deberia pasar en 3-7m-: usar el maximo numero de codos con el
    # pitch mas alto que alcance, mejor que tronar.
    elbow_count = MAX_STEADY_ELBOW_COUNT + 2
    pitch_deg = pitch_deg_for_height(target_height_mm, elbow_count, bend_radius_mm, ceja_mm, duct_outside_r_mm) || 44.0
    [elbow_count, pitch_deg]
  end

  def point_at_segment_fraction(seg, fraction)
    if seg[:type] == :straight
      t_mm = seg[:length].to_mm * fraction
      [seg[:start].offset(seg[:direction], t_mm.mm), seg[:direction]]
    else
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

  # Busca, por FUERZA BRUTA -sin crear geometria, pura aritmetica de
  # vectores-, la combinacion de AZIMUT -giro del brazo sobre el eje Z
  # del poste- y DROP -que tan abajo arranca el brazo- que deja la
  # PUNTA del tubito de 10cm -con conector y todo, ver SOLERA_LEG_*- lo
  # mas cerca posible de base_point -la base real de la solera-.
  # Pedido del usuario: girar el brazo, no solo mover el drop, para que
  # el tubito SI toque la solera. Barrido amplio de azimut primero
  # -por si la direccion radial pura estuviera lejos-, luego fino
  # alrededor del mejor angulo encontrado.
  def align_arm_to_solera_base(direction_before_rotation, radial_length_mm, centroid_x_mm, centroid_y_mm, ground_z, target_point, local_z, base_point)
    best_unit = nil
    best_drop_mm = nil
    best_gap_mm = Float::INFINITY

    evaluate = lambda do |deg|
      angle = deg * Math::PI / 180.0
      rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, angle)
      unit = direction_before_rotation.transform(rotation).normalize
      along_arm = local_z.dot(unit)
      branch_raw = Geom::Vector3d.new(
        local_z.x - (unit.x * along_arm), local_z.y - (unit.y * along_arm), local_z.z - (unit.z * along_arm)
      )
      next if branch_raw.length < 0.01

      branch_dir = branch_raw.normalize
      (50..800).step(10) do |drop_mm|
        candidate_z = target_point.z - drop_mm.mm
        next if candidate_z <= ground_z

        candidate_post_axis = Geom::Point3d.new(centroid_x_mm.mm, centroid_y_mm.mm, candidate_z)
        candidate_mid_point = candidate_post_axis.offset(unit, radial_length_mm.mm)
        candidate_tip = candidate_mid_point.offset(branch_dir, (SOLERA_LEG_RAISE_MM + SOLERA_LEG_LENGTH_MM).mm)
        gap_mm = candidate_tip.distance(base_point).to_mm
        if gap_mm < best_gap_mm
          best_gap_mm = gap_mm
          best_unit = unit
          best_drop_mm = drop_mm.to_f
        end
      end
    end

    (-45..45).step(3) { |deg| evaluate.call(deg) }
    center_deg = best_unit ? (Math.atan2(
      direction_before_rotation.cross(best_unit).dot(Z_AXIS), direction_before_rotation.dot(best_unit)
    ) * 180.0 / Math::PI) : 0.0
    (center_deg - 3.0).step(center_deg + 3.0, 0.2) { |deg| evaluate.call(deg) }

    [best_unit, best_drop_mm]
  end

  # Mismo radio exterior del ducto que usa soporte_solera_playidea.rb
  # -TUBE_OUTER_RADIUS_MM-, para saber donde queda la SUPERFICIE -la
  # base- de la solera, no solo su centro.
  SOLERA_OUTER_RADIUS_MM = 408.0
  SOLERA_LEG_LENGTH_MM = 100.0 # 10cm, pedido por el usuario
  SOLERA_LEG_RAISE_MM = 25.0

  # Replica EXACTA del marco local -Gram-Schmidt- que usa
  # soporte_solera_playidea.rb para orientar la solera -direction =
  # target_tangent, up_hint = Z_AXIS.reverse-. `local_z` es el eje a lo
  # largo del cual la solera "cae" hacia abajo -en la MISMA inclinacion
  # del ducto en ese punto, no vertical puro-. Necesario para que el
  # tubito que sube a tocarla salga con esa misma inclinacion, tal
  # como pidio el usuario.
  def solera_local_z(target_tangent)
    local_x = target_tangent.normalize
    reference = local_x.parallel?(Z_AXIS.reverse) ? Y_AXIS : Z_AXIS.reverse
    local_y = local_x.cross(reference).normalize
    local_x.cross(local_y).normalize
  end

  # --- Un brazo de soporte, automático -----------------------------------
  # Regla geometrica del usuario, sin excepcion: el brazo apunta RADIAL
  # -del eje del poste central derecho hacia el punto del codo, sin
  # ninguna rotacion artificial para esquivar nada- y su LARGO EXACTO
  # -ni mas ni menos que la distancia real hasta quedar justo debajo
  # del ducto- es lo que evita que atraviese el ducto, otro codo o
  # otra vuelta de la espiral. Nada de busqueda de rotacion por
  # clearance -eso violaba la regla de "orientacion radial siempre"-.
  def build_support_arm(ctx, instances, loop_i)
    elbow_segment = ctx[:duct_segments][1 + (2 * loop_i)]
    return unless elbow_segment && elbow_segment[:type] == :elbow

    target_point, target_tangent = point_at_segment_fraction(elbow_segment, 0.5)
    original_axis_point = Geom::Point3d.new(ctx[:centroid_x_mm].mm, ctx[:centroid_y_mm].mm, target_point.z)
    direction_before_rotation = target_point - original_axis_point
    radial_length_mm = direction_before_rotation.length.to_mm
    return if radial_length_mm < 1.0 # codo casi encima del poste, no hay brazo que trazar

    # Base -superficie, no centro- de la solera, en SU misma inclinacion
    # -local_z, calculado igual que soporte_solera_playidea.rb-. El
    # tubito de 10cm debe llegar ahi, saliendo con esa inclinacion.
    local_z = solera_local_z(target_tangent)
    base_point = target_point.offset(local_z.reverse, SOLERA_OUTER_RADIUS_MM.mm)

    # Pedido del usuario: GIRAR el brazo -no solo mover el drop- para
    # que la punta del tubito de 10cm si toque la base real de la
    # solera. Busqueda conjunta de azimut + drop, ver
    # align_arm_to_solera_base.
    unit_direction, best_drop_mm = align_arm_to_solera_base(
      direction_before_rotation, radial_length_mm, ctx[:centroid_x_mm], ctx[:centroid_y_mm], ctx[:ground_z], target_point, local_z, base_point
    )
    return if unit_direction.nil? || best_drop_mm.nil?

    along_arm = local_z.dot(unit_direction)
    branch_raw = Geom::Vector3d.new(
      local_z.x - (unit_direction.x * along_arm),
      local_z.y - (unit_direction.y * along_arm),
      local_z.z - (unit_direction.z * along_arm)
    )
    return if branch_raw.length < 0.01 # local_z YA es unitario, un residuo cercano a 0 -no a 1- es lo degenerado

    mid_branch_direction = branch_raw.normalize

    arm_z = target_point.z - best_drop_mm.mm
    post_axis = Geom::Point3d.new(ctx[:centroid_x_mm].mm, ctx[:centroid_y_mm].mm, arm_z)
    mid_point = post_axis.offset(unit_direction, radial_length_mm.mm)

    con10 = PlayIdea::Conectores.create_connector('10', 'Galvanizado', ctx[:con10_metadata], post_axis)
    con10_target_x = Z_AXIS
    con10_target_z = unit_direction.reverse
    con10_target_y = con10_target_z.cross(con10_target_x)
    con10.transformation = Geom::Transformation.axes(post_axis, con10_target_x, con10_target_y, con10_target_z)
    instances << con10

    con10_mid = PlayIdea::Conectores.create_connector('10', 'Galvanizado', ctx[:con10_metadata], mid_point)
    con10_mid_target_x = unit_direction
    con10_mid_target_z = mid_branch_direction.reverse
    con10_mid_target_y = con10_mid_target_z.cross(con10_mid_target_x)
    con10_mid.transformation = Geom::Transformation.axes(mid_point, con10_mid_target_x, con10_mid_target_y, con10_mid_target_z)
    instances << con10_mid

    # Tubito de 10cm, MISMA inclinacion que la solera -mid_branch_
    # direction, la proyeccion de local_z sobre el plano perpendicular
    # al brazo-, sin doblez.
    mid_leg_start = mid_point.offset(mid_branch_direction, SOLERA_LEG_RAISE_MM.mm)
    mid_leg = PlayIdea::CreadorTubos.build_tube(
      ctx[:tube_params_base].merge(length_mm: SOLERA_LEG_LENGTH_MM, code: 'TUBO-ESTRUCTURAL-PATA-BRAZO-AUTO'),
      mid_leg_start, mid_branch_direction
    )
    instances << mid_leg

    # La solera -su propia geometria ya envuelve el radio exterior
    # real del ducto- va DIRECTO al punto conocido del codo -centro-,
    # nunca con nearest_duct_point -ver skill tobogan-completo-
    # playidea, "enganchaba" codos distintos en espirales apretadas-.
    solera = PlayIdeaSoporteSoleraScript.build_piece({}, target_point, target_tangent, Z_AXIS.reverse, 76.2)
    instances << solera

    tube_1_growth_mm = 70.0 # +5cm + 2cm mas, pedido por el usuario
    tube_1_start = post_axis.offset(unit_direction, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
    tube_1_length_mm = radial_length_mm - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM) + tube_1_growth_mm
    return if tube_1_length_mm <= 0.0

    tube_1 = PlayIdea::CreadorTubos.build_tube(
      ctx[:tube_params_base].merge(length_mm: tube_1_length_mm, code: 'TUBO-ESTRUCTURAL-BRAZO-AUTO'),
      tube_1_start, unit_direction
    )
    instances << tube_1

    brace_distance_mm = [radial_length_mm * 0.6, 400.0].min
    brace_arm_point = post_axis.offset(unit_direction, brace_distance_mm.mm)
    brace_post_point = Geom::Point3d.new(post_axis.x, post_axis.y, post_axis.z - brace_distance_mm.mm)
    return if brace_post_point.z <= ctx[:ground_z]

    con12_post = PlayIdea::Conectores.create_connector('12', 'Galvanizado', ctx[:con10_metadata], brace_post_point)
    con12_post_target_x = Z_AXIS.reverse
    con12_post_target_z = unit_direction.reverse
    con12_post_target_y = con12_post_target_z.cross(con12_post_target_x)
    con12_post.transformation = Geom::Transformation.axes(brace_post_point, con12_post_target_x, con12_post_target_y, con12_post_target_z)
    instances << con12_post

    con12_arm = PlayIdea::Conectores.create_connector('12', 'Galvanizado', ctx[:con10_metadata], brace_arm_point)
    con12_arm_target_x = unit_direction
    con12_arm_target_z = Z_AXIS
    con12_arm_target_y = con12_arm_target_z.cross(con12_arm_target_x)
    con12_arm.transformation = Geom::Transformation.axes(brace_arm_point, con12_arm_target_x, con12_arm_target_y, con12_arm_target_z)
    instances << con12_arm

    con12_receiver_radius_mm = PlayIdea::Conectores::OUTSIDE_MM / 2.0
    contact_post = brace_post_point.offset(con12_post_target_z.reverse, con12_receiver_radius_mm.mm)
    contact_arm = brace_arm_point.offset(con12_arm_target_z.reverse, con12_receiver_radius_mm.mm)
    brace_vector = contact_arm - contact_post
    return if brace_vector.length.to_mm <= (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM)

    brace_direction = brace_vector.normalize
    brace_start = contact_post.offset(brace_direction, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
    brace_length_mm = brace_vector.length.to_mm - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM)
    brace_tube = PlayIdea::CreadorTubos.build_tube(
      ctx[:tube_params_base].merge(length_mm: brace_length_mm, code: 'TUBO-ESTRUCTURAL-DIAGONAL-AUTO'),
      brace_start, brace_direction
    )
    instances << brace_tube
  rescue StandardError => error
    # Un brazo individual que no se pudo trazar -ej. geometria degenerada
    # en un caso limite- no debe tronar la variante completa; se salta y
    # se reporta en consola para revisar despues.
    puts "  (brazo loop_i=#{loop_i} omitido: #{error.message})"
  end

  # Cuantos brazos y en que codos, segun cuantos codos de espiral tiene
  # ESTA variante -mas codos -mas alto/mas vueltas- reparte mas brazos-.
  # Los indices posibles de codo van de 0 a elbow_count-1 -incluyendo
  # las 2 transiciones-. Concepto de demo, no una regla final.
  def arm_plan_for_height(elbow_count)
    steady = elbow_count - 2
    count = [[2 + ((steady - 6) / 2.0).round, 2].max, elbow_count - 2].min
    return [0] if count <= 1

    max_index = elbow_count - 2 # se deja el ultimo -transicion de salida- sin brazo, muy cerca del piso
    (0...count).map { |k| (k * max_index / (count - 1).to_f).round }.uniq
  end

  # --- Una variante completa ---------------------------------------------
  def build_tobogan_variant(target_height_mm, start_point, heading = X_AXIS)
    model = Sketchup.active_model
    instances = []

    transition_radius_mm = PlayIdeaCodo90Script::BEND_RADIUS_MM
    transition_ceja_mm = PlayIdeaCodo90Script::CEJA_LENGTH_MM
    duct_outside_r_mm = PlayIdeaCodo90Script::BODY_OUTSIDE_R_MM

    elbow_count, pitch_deg = elbow_count_and_pitch_for_height(target_height_mm, transition_radius_mm, transition_ceja_mm, duct_outside_r_mm)
    pitch = pitch_deg * Math::PI / 180.0
    tan2_pitch = Math.tan(pitch)**2
    delta_phi = Math.acos(-tan2_pitch)

    point = start_point
    heading_phi = Math.atan2(heading.y, heading.x)
    phi = heading_phi
    start_z = point.z

    spiral_points = []
    duct_segments = []

    lead_in_direction = dir_at(phi, 0.0)
    duct_segments << { type: :straight, start: point, direction: lead_in_direction,
                        length: PlayIdeaToboganRectoScript::TOTAL_LENGTH_MM.mm }
    lead_in = PlayIdeaToboganRectoScript.build_piece({}, point, lead_in_direction)
    instances << lead_in
    point = point.offset(lead_in_direction, PlayIdeaToboganRectoScript::TOTAL_LENGTH_MM.mm)

    dx_local = transition_radius_mm.mm * Math.sin(TRANSITION_SWEEP_RAD)
    dy_local = transition_radius_mm.mm * (1.0 - Math.cos(TRANSITION_SWEEP_RAD))

    elbow_count.times do |i|
      is_entry_transition = i.zero?
      is_exit_transition = (i == elbow_count - 1)
      is_transition = is_entry_transition || is_exit_transition

      entry_pitch = is_entry_transition ? 0.0 : pitch
      exit_pitch = is_exit_transition ? 0.0 : pitch
      step = is_transition ? TRANSITION_SWEEP_RAD : delta_phi

      entry_phi = phi
      exit_phi = entry_phi + step

      direction = dir_at(entry_phi, entry_pitch)
      exit_direction = dir_at(exit_phi, exit_pitch)

      spiral_points << point unless is_transition

      up_hint = exit_direction.cross(direction)
      instance = PlayIdeaCodo90Script.build_piece({}, point, direction, up_hint)
      instances << instance

      duct_segments << { type: :elbow, entry: point, direction: direction, exit_direction: exit_direction,
                          radius: transition_radius_mm.mm, sweep: TRANSITION_SWEEP_RAD }

      bend_offset = Geom::Vector3d.new(
        (direction.x * dx_local) + (exit_direction.x * dy_local),
        (direction.y * dx_local) + (exit_direction.y * dy_local),
        (direction.z * dx_local) + (exit_direction.z * dy_local)
      )
      point = point.offset(bend_offset)
      duct_segments << { type: :straight, start: point, direction: exit_direction, length: transition_ceja_mm.mm }
      point = point.offset(exit_direction, transition_ceja_mm.mm)

      phi = exit_phi
    end

    final_direction = dir_at(phi, 0.0)
    salida = PlayIdeaSalidaToboganScript.build_piece({}, point, final_direction, Z_AXIS.reverse)
    instances << salida
    salida_round_length_mm = PlayIdeaSalidaToboganScript::CEJA_LENGTH_MM + PlayIdeaSalidaToboganScript::STRAIGHT_ROUND_LENGTH_MM
    duct_segments << { type: :straight, start: point, direction: final_direction, length: salida_round_length_mm.mm }

    spiral_xs_mm = spiral_points.map(&:x).map(&:to_mm)
    spiral_ys_mm = spiral_points.map(&:y).map(&:to_mm)
    centroid_x_mm = (spiral_xs_mm.min + spiral_xs_mm.max) / 2.0
    centroid_y_mm = (spiral_ys_mm.min + spiral_ys_mm.max) / 2.0

    exit_bottom_z = point.z - PlayIdeaSalidaToboganScript::BODY_OUTSIDE_R_MM.mm
    ground_z = exit_bottom_z - CON61_BELOW_EXIT_MM.mm

    con61_metadata = { receiver_material: 'Galvanizado', hardware_size: '3/8"', investment_cost_mxn: 0, costing: { rows: [] } }
    con61_point = Geom::Point3d.new(centroid_x_mm.mm, centroid_y_mm.mm, ground_z)
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
    con10_metadata = { receiver_material: 'Galvanizado', hardware_size: '3/8"', investment_cost_mxn: 0, costing: { rows: [] } }

    post_total_length_mm = (start_z - ground_z).to_mm
    post = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: post_total_length_mm, code: 'TUBO-ESTRUCTURAL-POSTE'),
      con61_point, Z_AXIS
    )
    instances << post

    ctx = {
      centroid_x_mm: centroid_x_mm, centroid_y_mm: centroid_y_mm, ground_z: ground_z,
      duct_segments: duct_segments, con10_metadata: con10_metadata, tube_params_base: tube_params_base
    }
    arm_indices = arm_plan_for_height(elbow_count)
    arm_indices.each do |loop_i|
      build_support_arm(ctx, instances, loop_i)
    end

    resulting_height_mm = post_total_length_mm.to_mm + (2.0 * PlayIdeaSalidaToboganScript::BODY_OUTSIDE_R_MM) + CON61_BELOW_EXIT_MM
    total_loops = (phi - heading_phi) / (2.0 * Math::PI)

    model.start_operation('Agrupar variante de tobogán', true)
    group = model.active_entities.add_group(instances)
    group.name = "Tobogán #{(target_height_mm / 1000.0).round(1)}m (pitch=#{pitch_deg.round(2)}°, " \
                 "#{elbow_count} codos, ~#{total_loops.round(2)} vueltas, #{arm_indices.length} brazos)"
    model.commit_operation

    puts "Variante #{(target_height_mm / 1000.0).round(1)}m: pitch=#{pitch_deg.round(2)}°, " \
         "codos=#{elbow_count}, vueltas=#{total_loops.round(2)}, brazos=#{arm_indices.length}, " \
         "altura_real=#{(resulting_height_mm / 1000.0).round(3)}m"
    group
  end

  def build_all_variants(start_point, heading = X_AXIS)
    TARGET_HEIGHTS_MM.each_with_index do |height_mm, index|
      variant_start = start_point.offset(Geom::Vector3d.new(1, 0, 0), (index * VARIANT_SPACING_MM).mm)
      begin
        build_tobogan_variant(height_mm, variant_start, heading)
      rescue StandardError => error
        # Que una variante truene NO debe detener a las demas -antes
        # una excepcion aqui abortaba el each_with_index completo, y
        # solo se veia la primera variante, a medias, con nada mas-.
        puts "Variante #{(height_mm / 1000.0).round(1)}m fallo: #{error.message}"
        puts error.full_message
      end
    end
  end

  class PlacementTool
    def initialize(params)
      @params = params
      @input_point = Sketchup::InputPoint.new
    end

    def activate
      Sketchup.set_status_text('Haz clic para colocar las 5 variantes de altura -3,4,5,6,7m, una junto a otra-.', SB_PROMPT)
    end

    def onMouseMove(_flags, x, y, view)
      @input_point.pick(view, x, y)
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      @input_point.pick(view, x, y)
      PlayIdeaToboganVariedadesAlturaScript.build_all_variants(@input_point.position, X_AXIS)
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

PlayIdeaToboganVariedadesAlturaScript.start
