# Script suelto (NO es un plugin instalable) para PROBAR el tobogán
# parametrico -ver tobogan_variedades_altura_playidea_LISTO.rb, ya
# validado- UNIDO a una estructura modular real, construida con el
# plugin constructor_modulos_playidea -llamando su API directamente,
# sin pasar por su dialogo HTML-.
#
# Pedido del usuario: el tramo RECTO del tobogán -su entrada- debe
# quedar centrado en uno de los "cuadros" que forma la cuadrícula de
# módulos -la celda entre 4 postes-, a unos 20cm por encima del tubo
# horizontal de esa celda -como una plataforma de entrada al tobogán-.
# La ALTURA del tobogán -y por lo tanto su inclinación/vueltas/número
# de brazos, todo ya automático- se hace coincidir con la altura TOTAL
# pedida para la estructura, para que el tobogán baje del nivel de
# arriba hasta el piso junto a la base de la estructura.
#
# Cargar con:
#   load '/Users/minorusal/Documents/SKETCHUP/scripts/tobogan_con_estructura_playidea.rb'

Object.send(:remove_const, :PlayIdeaToboganConEstructuraScript) if defined?(PlayIdeaToboganConEstructuraScript)

module PlayIdeaToboganConEstructuraScript
  extend self

  SCRIPTS_DIR = '/Users/minorusal/Documents/SKETCHUP/scripts'.freeze
  DEPENDENCIES = %w[
    tobogan_recto_playidea.rb
    aro_entrada_tobogan_playidea.rb
    codo_90_playidea.rb
    salida_tobogan_playidea.rb
    soporte_solera_playidea.rb
    tornilleria_playidea.rb
  ].freeze
  STRUCTURE_DEPENDENCIES = [
    '/Users/minorusal/Documents/SKETCHUP/creador_tubos_playidea/main.rb',
    '/Users/minorusal/Documents/SKETCHUP/conectores_playidea/main.rb'
  ].freeze
  # El plugin de módulos -loader primero, para que registre su extensión
  # y quede definido PlayIdea::ConstructorModulos::EXTENSION, igual que
  # el patrón ya usado en scripts/probar_medio_modulo.rb- y luego su
  # main.rb con la lógica real.
  MODULES_LOADER = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea.rb'.freeze
  MODULES_MAIN = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea/main.rb'.freeze

  # Mismos valores ya validados en tobogan_variedades_altura_playidea_LISTO.rb
  MIN_STEADY_ELBOW_COUNT = 6
  MAX_STEADY_ELBOW_COUNT = 20
  MAX_REASONABLE_PITCH_DEG = 22.0
  TRANSITION_SWEEP_RAD = Math::PI / 2.0

  CENTRAL_TUBE_OUTSIDE_MM = 38.1
  CENTRAL_TUBE_WALL_MM = 1.50
  CENTRAL_TUBE_INSIDE_MM = CENTRAL_TUBE_OUTSIDE_MM - (2.0 * CENTRAL_TUBE_WALL_MM)
  CENTRAL_TUBE_COLOR = 'Negro'.freeze
  CON61_BELOW_EXIT_MM = 300.0
  CONNECTOR_SOCKET_CLEARANCE_MM = 25.0
  # Pedido del usuario: el tubo del soporte que carga el tramo recto -desde
  # el riel real de la estructura hasta el recto- debe medir SIEMPRE esto,
  # sin importar la altura pedida. Ver build_structure_with_tobogan.
  RECTO_SUPPORT_LEG_MM = 200.0
  # Pedido del usuario: entre más alto el tobogán, más ligas poste↔
  # estructura -antes siempre 2, fijo-. Cada cuánto -en mm de poste- se
  # agrega una liga extra. Ver build_structure_with_tobogan.
  LINK_SPACING_MM = 1800.0


  def start
    DEPENDENCIES.each { |file| load File.join(SCRIPTS_DIR, file) }
    STRUCTURE_DEPENDENCIES.each { |file| load file }
    load MODULES_LOADER unless defined?(PlayIdea::ConstructorModulos::EXTENSION)
    load MODULES_MAIN
    Sketchup.active_model.select_tool(PlacementTool.new({}))
  rescue StandardError => error
    UI.messagebox("No fue posible iniciar el tobogán con estructura:\n#{error.message}")
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
      z += (dz * dx_local) + (edz * dy_local)
      z += edz * ceja_mm
    end
    -z
  end

  def height_mm_for_pitch(pitch_deg, elbow_count, bend_radius_mm, ceja_mm, duct_outside_r_mm)
    total_drop_mm_for_pitch(pitch_deg, elbow_count, bend_radius_mm, ceja_mm) + (2.0 * duct_outside_r_mm) + CON61_BELOW_EXIT_MM
  end

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

  SOLERA_OUTER_RADIUS_MM = 408.0
  SOLERA_LEG_LENGTH_MM = 100.0
  SOLERA_LEG_RAISE_MM = 25.0

  def solera_local_z(target_tangent)
    local_x = target_tangent.normalize
    reference = local_x.parallel?(Z_AXIS.reverse) ? Y_AXIS : Z_AXIS.reverse
    local_y = local_x.cross(reference).normalize
    local_x.cross(local_y).normalize
  end

  # Pedido del usuario: los mismos tornillos que aseguran las uniones de
  # pestaña también aseguran la solera en CADA EXTREMO de esta -los 2
  # extremos del ARCO -soporte_solera_playidea.rb va de 180° a 360°-,
  # NO los 2 lados de su ancho-. Esos 2 extremos caen exactos sobre el
  # eje local_y de la solera -mismo Gram-Schmidt que usa su propio
  # build_piece con up_hint=Z_AXIS.reverse-, a los lados del ducto. El
  # tornillo cruza desde el barreno del ducto hacia afuera, atravesando
  # la pared del ducto + el grueso de la solera -no 2 paredes de ducto,
  # como en las uniones de pestaña-.
  # Corrección pedida por el usuario: puestos justo en la punta del
  # arco -phi=180°/360° exactos- quedaban en la mera orilla, sin
  # material real de la solera alrededor para agarrar -se podía safar-.
  # Se meten SOLERA_BOLT_ARC_INSET_MM -5cm- hacia el CENTRO del arco
  # -hacia phi=270°, el punto más bajo-, no en línea recta sino sobre el
  # mismo arco -mismo radio-, para quedar dentro del cuerpo de la
  # solera.
  SOLERA_BOLT_ARC_INSET_MM = 50.0

  # Método -no constante- porque PlayIdeaCodo90Script/PlayIdeaSoporte-
  # SoleraScript recién existen después de que DEPENDENCIES se carga en
  # `start`, y una constante a nivel de módulo se evaluaría antes de eso.
  def solera_bolt_wall_mm
    PlayIdeaCodo90Script::WALL_THICKNESS_MM + PlayIdeaSoporteSoleraScript::SUPPORT_THICKNESS_MM
  end

  def build_solera_bolts(instances, anchor_point, direction, up_hint)
    local_x = direction.normalize
    reference = local_x.parallel?(up_hint) ? Y_AXIS : up_hint
    local_y = local_x.cross(reference).normalize
    local_z = local_x.cross(local_y).normalize
    duct_inside_r_mm = PlayIdeaCodo90Script::BODY_INSIDE_R_MM

    arc_radius_mm = PlayIdeaSoporteSoleraScript::TUBE_OUTER_RADIUS_MM
    inset_rad = SOLERA_BOLT_ARC_INSET_MM / arc_radius_mm
    start_rad = (PlayIdeaSoporteSoleraScript::ARC_START_DEG * Math::PI / 180.0) + inset_rad
    end_rad = (PlayIdeaSoporteSoleraScript::ARC_END_DEG * Math::PI / 180.0) - inset_rad

    [start_rad, end_rad].each do |phi|
      radial_dir = Geom::Vector3d.new(
        (local_y.x * Math.cos(phi)) + (local_z.x * Math.sin(phi)),
        (local_y.y * Math.cos(phi)) + (local_z.y * Math.sin(phi)),
        (local_y.z * Math.cos(phi)) + (local_z.z * Math.sin(phi))
      ).normalize
      bore_point = anchor_point.offset(radial_dir, duct_inside_r_mm.mm)
      bolt = PlayIdeaTornilleriaScript.build_bolt_set({}, bore_point, radial_dir, solera_bolt_wall_mm)
      instances << bolt
    end
  rescue StandardError => error
    puts "  (tornillos de solera omitidos: #{error.message})"
  end

  def build_support_arm(ctx, instances, loop_i)
    elbow_segment = ctx[:duct_segments][1 + (2 * loop_i)]
    return unless elbow_segment && elbow_segment[:type] == :elbow

    target_point, target_tangent = point_at_segment_fraction(elbow_segment, 0.5)
    original_axis_point = Geom::Point3d.new(ctx[:centroid_x_mm].mm, ctx[:centroid_y_mm].mm, target_point.z)
    direction_before_rotation = target_point - original_axis_point
    radial_length_mm = direction_before_rotation.length.to_mm
    return if radial_length_mm < 1.0

    local_z = solera_local_z(target_tangent)
    base_point = target_point.offset(local_z.reverse, SOLERA_OUTER_RADIUS_MM.mm)

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
    return if branch_raw.length < 0.01

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

    mid_leg_start = mid_point.offset(mid_branch_direction, SOLERA_LEG_RAISE_MM.mm)
    mid_leg = PlayIdea::CreadorTubos.build_tube(
      ctx[:tube_params_base].merge(length_mm: SOLERA_LEG_LENGTH_MM, code: "TUB-ESTRUCTURAL-PATA-BRAZO-AUTO-#{format('%.1f', SOLERA_LEG_LENGTH_MM)}"),
      mid_leg_start, mid_branch_direction
    )
    instances << mid_leg

    solera = PlayIdeaSoporteSoleraScript.build_piece({}, target_point, target_tangent, Z_AXIS.reverse, 76.2)
    instances << solera
    build_solera_bolts(instances, target_point, target_tangent, Z_AXIS.reverse)

    tube_1_growth_mm = 70.0
    tube_1_start = post_axis.offset(unit_direction, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
    tube_1_length_mm = radial_length_mm - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM) + tube_1_growth_mm
    return if tube_1_length_mm <= 0.0

    tube_1 = PlayIdea::CreadorTubos.build_tube(
      ctx[:tube_params_base].merge(length_mm: tube_1_length_mm, code: "TUB-ESTRUCTURAL-BRAZO-AUTO-#{format('%.1f', tube_1_length_mm)}"),
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
      ctx[:tube_params_base].merge(length_mm: brace_length_mm, code: "TUB-ESTRUCTURAL-DIAGONAL-AUTO-#{format('%.1f', brace_length_mm)}"),
      brace_start, brace_direction
    )
    instances << brace_tube
  rescue StandardError => error
    puts "  (brazo loop_i=#{loop_i} omitido: #{error.message})"
  end

  # Pedido del usuario: replicar el soporte de tierra que tenia el
  # PRIMER brazo -hacia la salida- del tobogan de referencia -
  # tobogan_completo_playidea_hasta_brazo4_LISTO.rb-: en vez -o ademas-
  # de colgar de un conector de en medio, la punta del brazo sigue un
  # tramo mas y llega a un SEGUNDO CON-10 -"T acostada", paso principal
  # vertical, ramal recibe el tubo desde atras-, con un tubo vertical
  # bajando hasta un SEGUNDO CON-61 -al MISMO ground_z que el poste
  # central-. Mismo patron geometrico que build_support_arm hasta
  # con10_mid -radial, giro/drop buscados igual-, solo se le agrega
  # esta pata extra a partir de ahi.
  EXIT_ARM_TIP_EXTRA_MM = 150.0 # cuanto mas alla del conector de en medio llega la punta, ajustable
  TIP_POST_EXTRA_MM = 40.0 # igual que el tobogan de referencia -le faltaban ~6cm para tocar el conector-

  def build_exit_ground_support(ctx, instances, loop_i)
    elbow_segment = ctx[:duct_segments][1 + (2 * loop_i)]
    return unless elbow_segment && elbow_segment[:type] == :elbow

    target_point, target_tangent = point_at_segment_fraction(elbow_segment, 0.5)
    original_axis_point = Geom::Point3d.new(ctx[:centroid_x_mm].mm, ctx[:centroid_y_mm].mm, target_point.z)
    direction_before_rotation = target_point - original_axis_point
    radial_length_mm = direction_before_rotation.length.to_mm
    return if radial_length_mm < 1.0

    local_z = solera_local_z(target_tangent)
    base_point = target_point.offset(local_z.reverse, SOLERA_OUTER_RADIUS_MM.mm)
    # Mismo giro/drop que ya encontro build_support_arm para este mismo
    # loop_i -busqueda deterministica, da el mismo resultado-, asi el
    # conector de en medio de ESTA pata cae exacto donde ya vive el que
    # se construyo antes para la solera.
    unit_direction, best_drop_mm = align_arm_to_solera_base(
      direction_before_rotation, radial_length_mm, ctx[:centroid_x_mm], ctx[:centroid_y_mm], ctx[:ground_z], target_point, local_z, base_point
    )
    return if unit_direction.nil? || best_drop_mm.nil?

    arm_z = target_point.z - best_drop_mm.mm
    post_axis = Geom::Point3d.new(ctx[:centroid_x_mm].mm, ctx[:centroid_y_mm].mm, arm_z)
    mid_point = post_axis.offset(unit_direction, radial_length_mm.mm)

    arm_end_point = mid_point.offset(unit_direction, EXIT_ARM_TIP_EXTRA_MM.mm)

    tube_extra_start = mid_point.offset(unit_direction, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
    tube_extra_length_mm = EXIT_ARM_TIP_EXTRA_MM - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM)
    if tube_extra_length_mm > 0.0
      tube_extra = PlayIdea::CreadorTubos.build_tube(
        ctx[:tube_params_base].merge(length_mm: tube_extra_length_mm, code: "TUB-ESTRUCTURAL-BRAZO-SALIDA-EXT-#{format('%.1f', tube_extra_length_mm)}"),
        tube_extra_start, unit_direction
      )
      instances << tube_extra
    end

    # CON-10 en la punta, "T acostada": paso principal -de fabrica
    # horizontal- pasa a vertical, libre para seguir hacia abajo; el
    # ramal -de fabrica hacia -Z- abre hacia atras, hacia el poste, para
    # recibir el tubo que llega de ese lado.
    con10_up = PlayIdea::Conectores.create_connector('10', 'Galvanizado', ctx[:con10_metadata], arm_end_point)
    con10_up_target_x = Z_AXIS
    con10_up_target_z = unit_direction
    con10_up_target_y = con10_up_target_z.cross(con10_up_target_x)
    con10_up.transformation = Geom::Transformation.axes(arm_end_point, con10_up_target_x, con10_up_target_y, con10_up_target_z)
    instances << con10_up

    # Pata vertical bajando desde el segundo CON-10 hasta un segundo
    # CON-61, al MISMO ground_z que el del poste central.
    tip_con61_point = Geom::Point3d.new(arm_end_point.x, arm_end_point.y, ctx[:ground_z])
    tip_con61 = PlayIdea::Conectores.create_connector('61', 'Galvanizado', ctx[:con10_metadata], tip_con61_point)
    instances << tip_con61

    tip_post_length_mm = (arm_end_point.z - ctx[:ground_z]).to_mm + TIP_POST_EXTRA_MM
    tip_post = PlayIdea::CreadorTubos.build_tube(
      ctx[:tube_params_base].merge(length_mm: tip_post_length_mm, code: "TUB-ESTRUCTURAL-PATA-BRAZO-SALIDA-#{format('%.1f', tip_post_length_mm)}"),
      tip_con61_point, Z_AXIS
    )
    instances << tip_post
  rescue StandardError => error
    puts "  (soporte de tierra en la salida omitido: #{error.message})"
  end

  # Pedido del usuario: igual que el tobogan de referencia -
  # tobogan_completo_playidea_hasta_brazo4_LISTO.rb-, siempre debe
  # haber un brazo cerca de la SALIDA -el ultimo codo, la transicion de
  # salida, justo antes de la pieza de salida-, ademas de los repartidos
  # a lo largo de la espiral. Ese brazo de referencia usaba el punto de
  # ENTRADA de ese codo -no su centro-, pero build_support_arm ya
  # funciona bien con el centro -mismo patron para todos los brazos,
  # mas simple-, asi que aqui solo se agrega su indice -elbow_count-1-
  # a la lista, sin duplicar logica.
  def arm_plan_for_height(elbow_count)
    steady = elbow_count - 2
    # Pedido del usuario: con solo 2 brazos repartidos -los 2 extremos
    # del rango, sin nada real en medio-, faltaba soporte a la mitad de
    # la espiral. Base subida de 2 a 3 para que SIEMPRE haya un brazo
    # genuino en medio, no solo en las puntas.
    count = [[3 + ((steady - 6) / 2.0).round, 3].max, elbow_count - 2].min
    indices = if count <= 1
                [0]
              else
                max_index = elbow_count - 2
                (0...count).map { |k| (k * max_index / (count - 1).to_f).round }
              end
    (indices + [elbow_count - 1]).uniq
  end

  # --- El tobogán, una sola vez -------------------------------------------
  def build_tobogan(target_height_mm, start_point, heading = X_AXIS)
    model = Sketchup.active_model
    instances = []

    transition_radius_mm = PlayIdeaCodo90Script::BEND_RADIUS_MM
    transition_ceja_mm = PlayIdeaCodo90Script::CEJA_LENGTH_MM
    duct_outside_r_mm = PlayIdeaCodo90Script::BODY_OUTSIDE_R_MM
    # Pedido del usuario: cada unión de pestaña de los ductos se
    # asegura con 4 tornillos -tornilleria_playidea.rb-. El tornillo
    # cruza radialmente desde el barreno -radio interno- hacia afuera,
    # atravesando las 2 paredes traslapadas -la de la pieza que entra +
    # la de la ceja que la recibe-, ambas del mismo grosor.
    duct_inside_r_mm = PlayIdeaCodo90Script::BODY_INSIDE_R_MM
    flange_bolt_wall_mm = 2.0 * PlayIdeaCodo90Script::WALL_THICKNESS_MM

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

    # Pedido del usuario: el aro-collar -aro_entrada_tobogan_playidea.rb-
    # va en la entrada, en la misma zona que crecio el recto -los 10cm
    # extra-, pero AL REVES de como se probo primero: la pestaña -angulo
    # de 90° visto de lado- debe quedar justo en la entrada -entry_
    # point, del lado de la estructura, visible-, y el extremo liso -
    # abierto, por donde entra el recto- del lado de la espiral. Por eso
    # se construye arrancando MAS ADELANTE -su propio largo total- y con
    # la direccion invertida, asi su remate -la pestaña- cae exacto en
    # entry_point.
    aro_total_mm = PlayIdeaAroEntradaToboganScript::COLLAR_LENGTH_MM + PlayIdeaAroEntradaToboganScript::FLANGE_THICKNESS_MM
    aro_start = point.offset(lead_in_direction, aro_total_mm.mm)
    aro_entrada = PlayIdeaAroEntradaToboganScript.build_piece({}, aro_start, lead_in_direction.reverse)
    instances << aro_entrada

    # Pedido del usuario: también en tache el aro de la entrada -lo
    # atornilla al recto que envuelve-. El aro no tiene ceja propia como
    # los codos -es un cuerpo liso que envuelve al recto-, así que el
    # tache se centra a la mitad de ese cuerpo -no de la pestaña, que es
    # solo el remate-, cruzando la pared del recto + la pared del aro
    # -mismo grosor total que las demás uniones-.
    aro_bolt_center = point.offset(lead_in_direction, ((PlayIdeaAroEntradaToboganScript::COLLAR_LENGTH_MM / 2.0) + PlayIdeaAroEntradaToboganScript::FLANGE_THICKNESS_MM).mm)
    PlayIdeaTornilleriaScript.build_flange_bolts(instances, aro_bolt_center, lead_in_direction, duct_inside_r_mm, flange_bolt_wall_mm)

    point = point.offset(lead_in_direction, PlayIdeaToboganRectoScript::TOTAL_LENGTH_MM.mm)
    # Unión de pestaña: extremo con ceja del recto <-> entrada lisa del
    # primer codo. Corrección pedida por el usuario: `point` es la
    # misma orilla/boca de la ceja -no agarra nada ahí-, así que el
    # tornillo se centra a la mitad del largo de la ceja -hacia ATRÁS,
    # dentro de la ceja del recto que acaba de terminar-.
    recto_bolt_center = point.offset(lead_in_direction.reverse, (PlayIdeaToboganRectoScript::CEJA_LENGTH_MM / 2.0).mm)
    PlayIdeaTornilleriaScript.build_flange_bolts(instances, recto_bolt_center, lead_in_direction, duct_inside_r_mm, flange_bolt_wall_mm)

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
      # Unión de pestaña: extremo con ceja de ESTE codo <-> entrada lisa
      # de la SIGUIENTE pieza -el próximo codo, o la salida si es el
      # último-. Igual que en el recto: se centra a la mitad del largo
      # de la ceja, no en su boca/orilla.
      elbow_bolt_center = point.offset(exit_direction.reverse, (transition_ceja_mm / 2.0).mm)
      PlayIdeaTornilleriaScript.build_flange_bolts(instances, elbow_bolt_center, exit_direction, duct_inside_r_mm, flange_bolt_wall_mm)

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
      tube_params_base.merge(length_mm: post_total_length_mm, code: "TUB-ESTRUCTURAL-POSTE-#{format('%.1f', post_total_length_mm)}"),
      con61_point, Z_AXIS
    )
    instances << post

    ctx = {
      centroid_x_mm: centroid_x_mm, centroid_y_mm: centroid_y_mm, ground_z: ground_z,
      duct_segments: duct_segments, con10_metadata: con10_metadata, tube_params_base: tube_params_base
    }
    arm_indices = arm_plan_for_height(elbow_count)
    arm_indices.each { |loop_i| build_support_arm(ctx, instances, loop_i) }
    build_exit_ground_support(ctx, instances, elbow_count - 1)

    resulting_height_mm = post_total_length_mm.to_mm + (2.0 * PlayIdeaSalidaToboganScript::BODY_OUTSIDE_R_MM) + CON61_BELOW_EXIT_MM
    total_loops = (phi - heading_phi) / (2.0 * Math::PI)

    model.start_operation('Agrupar tobogán', true)
    group = model.active_entities.add_group(instances)
    group.name = "Tobogán #{(target_height_mm / 1000.0).round(1)}m (pitch=#{pitch_deg.round(2)}°, " \
                 "#{elbow_count} codos, ~#{total_loops.round(2)} vueltas, #{arm_indices.length} brazos)"
    model.commit_operation

    puts "Tobogán: pitch=#{pitch_deg.round(2)}°, codos=#{elbow_count}, vueltas=#{total_loops.round(2)}, " \
         "brazos=#{arm_indices.length}, altura_real=#{(resulting_height_mm / 1000.0).round(3)}m"
    { group: group, centroid_x_mm: centroid_x_mm, centroid_y_mm: centroid_y_mm, ground_z: ground_z, start_z: start_z, duct_segments: duct_segments }
  end

  # --- Estructura de módulos + tobogán unido ------------------------------
  # Construye la cuadrícula con la MISMA API que usa la herramienta
  # automática del constructor de módulos -params_from_automatic_data +
  # create_module-, sin pasar por su diálogo HTML. Luego, correcciones
  # pedidas por el usuario tras la primera prueba:
  # -1- el recto arranca en la ORILLA real de la cuadrícula -última
  #     columna de tubos horizontales, eje +X-, no en medio de una
  #     celda -eso dejaba al tobogán metido dentro de la estructura-,
  #     y sale hacia AFUERA -heading +X, alejándose de la estructura-.
  # -2- el CON-61 del poste central del tobogán queda a la MISMA altura
  #     que los CON-61 de la estructura -origin.z, el suelo real-: como
  #     build_tobogan ya resuelve la inclinación para que la altura
  #     total dé EXACTO target_height_mm, basta con arrancar la entrada
  #     justo esa distancia arriba de origin.z.
  def build_structure_with_tobogan(origin, ancho_m, largo_m, alto_m)
    data = {
      'ancho_m' => ancho_m, 'largo_m' => largo_m, 'alto_m' => alto_m,
      'color' => 'Azul', 'code' => '', 'padding' => false, 'solera' => true,
      'platform' => false, 'net' => false
    }
    params = PlayIdea::ConstructorModulos.params_from_automatic_data(data)
    raise 'No se pudo calcular la estructura -revisa ancho/largo/alto-' unless params

    PlayIdea::ConstructorModulos.create_module(params, origin)

    nx = params[:modules_x]
    ny = params[:modules_y]
    nz = params[:modules_z]
    sx_mm = params[:spacing_x_mm]
    sy_mm = params[:spacing_y_mm]
    sz_mm = params[:spacing_z_mm]

    # Pedido del usuario -correccion-: el tobogan NO debe quedar metido
    # dentro de la estructura. La orilla del recto va en la ORILLA real
    # de la cuadricula -la ultima columna de tubos horizontales, eje
    # +X-, no en medio de una celda, y el brazo sale hacia AFUERA -
    # heading +X, alejandose de la estructura-. j0 -la fila, a lo largo
    # de esa orilla- se centra en la celda de en medio para que quede
    # parejo, evitando la esquina de la torre si la hay ahi.
    j0 = [ny / 2, ny - 1].min
    if params[:tower] && ny > 1
      tower_offset_y_mm = params[:tower][:offset_y_mm]
      candidate_y_mm = PlayIdea::ConstructorModulos.axis_cumulative_mm(j0, sy_mm).to_mm
      j0 = j0.zero? ? 1 : j0 - 1 if (candidate_y_mm - tower_offset_y_mm).abs < 1.0
    end

    k = [nz - 1, 0].max # ultimo piso real -ver investigacion, place_platforms va de 0 a nz-1-

    # OJO unidades -ver skill sketchup-plugins-: axis_column_width_mm
    # regresa Float CRUDO en mm -no Length-, mientras axis_cumulative_mm
    # y grid_level_z regresan Length -ya en unidades internas-. Sumar un
    # Float crudo directo a un Length lo malinterpreta como pulgadas -
    # bug real ya visto antes-, por eso el .mm explicito en cell_depth.
    cell_depth_mm = PlayIdea::ConstructorModulos.axis_column_width_mm(j0, sy_mm)
    center_y = PlayIdea::ConstructorModulos.axis_cumulative_mm(j0, sy_mm) + (cell_depth_mm / 2.0).mm
    # nx -no nx-1- en axis_cumulative_mm da el acumulado COMPLETO del
    # eje X: la orilla real despues de la ULTIMA columna de tubos.
    edge_x = PlayIdea::ConstructorModulos.axis_cumulative_mm(nx, sx_mm)

    # Pedido del usuario: el tubo del soporte que carga el recto debe
    # medir SIEMPRE ~20cm -antes salía lo que la geometría diera, según
    # alto_m-. Por eso el recto YA NO se ancla directo a alto_m: se
    # ancla a `structure_top_z` -el riel real del último nivel usable,
    # de donde sale ese tubo-, con el tubo fijo a RECTO_SUPPORT_LEG_MM.
    # `target_height_mm` se recalcula despejando la MISMA fórmula
    # `entry_z = origin.z + (target_height_mm - duct_outside_r_mm)` ya
    # validada -antes con alto_m como dato, ahora con entry_z ya fijo-,
    # para que `ground_z` -el CON-61 del tobogán- se siga alineando
    # exacto con origin.z, igual que antes.
    duct_outside_r_mm = PlayIdeaCodo90Script::BODY_OUTSIDE_R_MM
    heading = X_AXIS
    sz_length = PlayIdea::ConstructorModulos.spacing_z_length(sz_mm)
    structure_top_z = origin.z + PlayIdea::ConstructorModulos.grid_level_z(k, nz, sz_length)
    entry_z = structure_top_z + (RECTO_SUPPORT_LEG_MM + duct_outside_r_mm).mm
    target_height_mm = (entry_z - origin.z).to_mm + duct_outside_r_mm
    # Pedido del usuario: el recto se acorto 200mm -1300->1100mm-, asi
    # que el tobogan se acerca esos mismos 200mm a la estructura -hacia
    # adentro, contrario al heading- para no dejar un hueco de mas.
    # El recto crecio 10cm -1000->1100mm-: como crece desde su punto de
    # ARRANQUE -entry_point-, sin compensar esto empuja TODO el resto
    # del tobogan -la espiral completa- 10cm mas hacia afuera. Pedido
    # del usuario: que crezca el recto, pero sin correr el tobogan.
    # Arreglo: entry_point se recorre esos mismos 10cm HACIA ADENTRO,
    # asi el extremo LEJANO del recto -donde arranca la espiral- se
    # queda exactamente donde ya estaba.
    move_closer_mm = 150.0 # 50mm + 10cm mas, para compensar el crecimiento del recto
    entry_point = Geom::Point3d.new(origin.x + edge_x, origin.y + center_y, entry_z)
    entry_point = entry_point.offset(heading.reverse, move_closer_mm.mm)

    tobogan = build_tobogan(target_height_mm, entry_point, heading)

    # Pedido del usuario: unir el poste central del tobogan a la
    # estructura en 2 puntos -abajo y arriba-, con conector y tubo de
    # estructura -mismo patron "T acostada" que ya usan los brazos del
    # tobogan con su propio poste-. Corregido -la liga de arriba
    # atravesaba el ducto recto-: en vez del nodo (nx, j0) -que no
    # comparte la Y exacta del poste, dejando la liga en diagonal,
    # cruzando el recto-, se conecta al tubo horizontal de la orilla
    # justo en la Y del poste -"exactamente el frente del poste"-, asi
    # la liga viaja derecho en X, sin cruzar el recto.
    structure_post_x = origin.x + edge_x
    structure_post_y = tobogan[:centroid_y_mm].mm

    link_con10_metadata = { receiver_material: 'Galvanizado', hardware_size: '3/8"', investment_cost_mxn: 0, costing: { rows: [] } }
    link_tube_params_base = {
      outside_mm: CENTRAL_TUBE_OUTSIDE_MM, wall_mm: CENTRAL_TUBE_WALL_MM, inside_mm: CENTRAL_TUBE_INSIDE_MM,
      schedule: 'ESTRUCTURAL', color: CENTRAL_TUBE_COLOR, length_mode: 'manual', standard_name: '',
      connector_compatible: true, connector_clearance_mm: PlayIdea::CreadorTubos::CONNECTOR_INSIDE_MM - CENTRAL_TUBE_OUTSIDE_MM
    }

    # Pedido del usuario -corrección-: la liga de arriba rozaba un ducto
    # de 90° -el offset fijo de antes caía justo dentro del primer codo-.
    # Ahora se usan los puntos MEDIOS reales de los codos -duct_segments-
    # con el azimut más ALEJADO posible del azimut hacia la estructura.
    # También: entre más alto el tobogán, más ligas -antes siempre 2-.
    link_instances = []
    bottom_link_drop_mm = 150.0 # 30cm - 15cm mas abajo, pedido por el usuario
    bottom_z = origin.z + bottom_link_drop_mm.mm

    post_span_mm = (entry_point.z - bottom_z).to_mm
    extra_link_count = [1 + (post_span_mm / LINK_SPACING_MM).round, 1].max
    extra_targets_z = (0...extra_link_count).map do |i|
      fraction = (i + 1).to_f / (extra_link_count + 1)
      entry_point.z - ((entry_point.z - bottom_z) * fraction)
    end
    extra_zs = link_zs_avoiding_ducts(
      tobogan[:duct_segments], tobogan[:centroid_x_mm], tobogan[:centroid_y_mm],
      structure_post_x, structure_post_y, extra_targets_z, duct_outside_r_mm, bottom_z, entry_point.z
    )

    link_zs = ([bottom_z] + extra_zs).uniq
    link_zs.each_with_index do |link_z, index|
      tobogan_point = Geom::Point3d.new(tobogan[:centroid_x_mm].mm, tobogan[:centroid_y_mm].mm, link_z)
      structure_point = Geom::Point3d.new(structure_post_x, structure_post_y, link_z)
      code_suffix = if index.zero?
                      'ABAJO'
                    elsif index == link_zs.length - 1
                      'ARRIBA'
                    else
                      "MEDIO-#{index}"
                    end
      build_post_link(link_instances, tobogan_point, structure_point, link_con10_metadata, link_tube_params_base, code_suffix)
    end

    # Pedido del usuario: un soporte extra, no en un codo de 90° del
    # tobogan sino parado sobre la ESTRUCTURA de modulos, para cargar
    # el tramo RECTO -la entrada- justo donde pasa por encima de ella.
    # Mismo patron de tubito+solera que ya usan los brazos del tobogan,
    # pero arrancando desde un riel real de la estructura -el de la
    # orilla, mismo X que structure_post_x- en vez de desde el poste
    # del tobogan. El punto se elige en la MISMA X del riel -edge_x-,
    # que cae dentro del tramo del recto -entry_point ya arranca 50mm
    # adentro de esa orilla-, y en la Y real del recto -entry_point.y-.
    recto_point = Geom::Point3d.new(structure_post_x, entry_point.y, entry_point.z)
    build_recto_support(link_instances, structure_post_x, entry_point.y, structure_top_z, recto_point, heading, link_con10_metadata, link_tube_params_base)

    unless link_instances.empty?
      model = Sketchup.active_model
      model.start_operation('Unir tobogán a la estructura', true)
      link_group = model.active_entities.add_group(link_instances)
      link_group.name = 'Liga tobogán-estructura'
      model.commit_operation
    end

    tobogan[:group]
  end

  # Soporte del tramo RECTO parado sobre un riel real de la estructura
  # -no sobre el poste del tobogan-: conector "T de cabeza" -paso
  # principal horizontal, a lo largo del riel -Y_AXIS-, ramal vertical
  # hacia arriba, mismo convenio que con10_mid en build_support_arm-,
  # tubo vertical, y solera abrazando el recto en su base real -un
  # radio de ducto por debajo de su linea central-.
  def build_recto_support(instances, base_x, base_y, structure_top_z, recto_point, recto_tangent, con10_metadata, tube_params_base)
    base_point = Geom::Point3d.new(base_x, base_y, structure_top_z)
    duct_outside_r_mm = PlayIdeaCodo90Script::BODY_OUTSIDE_R_MM
    base_target = recto_point.offset(Z_AXIS.reverse, duct_outside_r_mm.mm)
    vector = base_target - base_point
    return if vector.length.to_mm < 1.0

    unit = vector.normalize

    con_base = PlayIdea::Conectores.create_connector('10', 'Galvanizado', con10_metadata, base_point)
    con_base_target_x = Y_AXIS # paso principal, a lo largo del riel de la estructura
    con_base_target_z = Z_AXIS.reverse # ramal -local -Z- pasa a apuntar hacia arriba
    con_base_target_y = con_base_target_z.cross(con_base_target_x)
    con_base.transformation = Geom::Transformation.axes(base_point, con_base_target_x, con_base_target_y, con_base_target_z)
    instances << con_base

    leg_raise_mm = 25.0
    leg_start = base_point.offset(unit, leg_raise_mm.mm)
    leg_length_mm = vector.length.to_mm - leg_raise_mm
    return if leg_length_mm <= 0.0

    leg = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: leg_length_mm, code: "TUB-ESTRUCTURAL-SOPORTE-RECTO-#{format('%.1f', leg_length_mm)}"),
      leg_start, unit
    )
    instances << leg

    solera = PlayIdeaSoporteSoleraScript.build_piece({}, recto_point, recto_tangent, Z_AXIS.reverse, 76.2)
    instances << solera
    build_solera_bolts(instances, recto_point, recto_tangent, Z_AXIS.reverse)
  rescue StandardError => error
    puts "  (soporte del recto omitido: #{error.message})"
  end

  # Une 2 postes verticales -point_a, point_b, cualquier altura- con un
  # CON-10 "acostado" en cada extremo -paso principal vertical, ramal
  # horizontal apuntando al otro poste- y un tubo de estructura entre
  # ambos, mismo patron ya usado en build_support_arm para el poste del
  # tobogan.
  # Distancia MÍNIMA de `point` al segmento de recta `seg_a`-`seg_b` -no a
  # la recta infinita-, en mm.
  def point_to_segment_distance_mm(point, seg_a, seg_b)
    ab = seg_b - seg_a
    len2 = (ab.x * ab.x) + (ab.y * ab.y) + (ab.z * ab.z)
    return point.distance(seg_a).to_mm if len2 < 1e-9

    ap = point - seg_a
    t = ((ap.x * ab.x) + (ap.y * ab.y) + (ap.z * ab.z)) / len2
    t = [[t, 0.0].max, 1.0].min
    closest = Geom::Point3d.new(seg_a.x + (ab.x * t), seg_a.y + (ab.y * t), seg_a.z + (ab.z * t))
    point.distance(closest).to_mm
  end

  # Espacio libre -mm- entre el segmento de la liga -tobogan_point a
  # structure_point- y el ducto REAL más cercano: muestrea CADA tramo de
  # duct_segments -recto O codo, no solo el punto medio de los codos- en
  # varios puntos, mide la distancia de cada uno al segmento de la liga,
  # y resta el radio exterior del ducto. Negativo/cero = choca.
  def link_clearance_mm(duct_segments, tobogan_point, structure_point, duct_outside_r_mm, samples_per_segment: 12)
    min_distance_mm = Float::INFINITY
    duct_segments.each do |seg|
      (0..samples_per_segment).each do |i|
        point, = point_at_segment_fraction(seg, i.to_f / samples_per_segment)
        distance_mm = point_to_segment_distance_mm(point, tobogan_point, structure_point)
        min_distance_mm = distance_mm if distance_mm < min_distance_mm
      end
    end
    min_distance_mm - duct_outside_r_mm
  end

  LINK_CLEARANCE_SAFETY_MM = 60.0
  LINK_SCAN_STEP_MM = 50.0

  # Para cada Z objetivo en `target_zs`, recorre TODO el rango bottom_z..
  # top_z -cada LINK_SCAN_STEP_MM- midiendo el espacio libre real de la
  # liga horizontal a esa Z, y elige la Z SEGURA más cercana a la
  # buscada. Si ninguna es segura, se conforma con la de más espacio libre.
  def link_zs_avoiding_ducts(duct_segments, centroid_x_mm, centroid_y_mm, structure_x, structure_y, target_zs, duct_outside_r_mm, bottom_z, top_z)
    evaluated = []
    z = bottom_z
    while z <= top_z
      tobogan_point = Geom::Point3d.new(centroid_x_mm.mm, centroid_y_mm.mm, z)
      structure_point = Geom::Point3d.new(structure_x, structure_y, z)
      clearance_mm = link_clearance_mm(duct_segments, tobogan_point, structure_point, duct_outside_r_mm)
      evaluated << { z: z, clearance_mm: clearance_mm }
      z += LINK_SCAN_STEP_MM.mm
    end
    return [] if evaluated.empty?

    safe = evaluated.select { |c| c[:clearance_mm] >= LINK_CLEARANCE_SAFETY_MM }
    if safe.empty?
      best_clearance = evaluated.map { |c| c[:clearance_mm] }.max
      safe = evaluated.select { |c| c[:clearance_mm] >= best_clearance - 1.0 }
    end
    target_zs.map { |target_z| safe.min_by { |c| (c[:z] - target_z).to_mm.abs }[:z] }
  end

  def build_post_link(instances, point_a, point_b, con10_metadata, tube_params_base, code_suffix)
    vector = point_b - point_a
    return if vector.length.to_mm < 1.0

    unit = vector.normalize

    con_a = PlayIdea::Conectores.create_connector('10', 'Galvanizado', con10_metadata, point_a)
    con_a_target_x = Z_AXIS
    con_a_target_z = unit.reverse
    con_a_target_y = con_a_target_z.cross(con_a_target_x)
    con_a.transformation = Geom::Transformation.axes(point_a, con_a_target_x, con_a_target_y, con_a_target_z)
    instances << con_a

    con_b = PlayIdea::Conectores.create_connector('10', 'Galvanizado', con10_metadata, point_b)
    con_b_target_x = Z_AXIS
    con_b_target_z = unit
    con_b_target_y = con_b_target_z.cross(con_b_target_x)
    con_b.transformation = Geom::Transformation.axes(point_b, con_b_target_x, con_b_target_y, con_b_target_z)
    instances << con_b

    tube_start = point_a.offset(unit, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
    tube_length_mm = vector.length.to_mm - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM)
    return if tube_length_mm <= 0.0

    tube = PlayIdea::CreadorTubos.build_tube(
      tube_params_base.merge(length_mm: tube_length_mm, code: "TUB-ESTRUCTURAL-LIGA-#{code_suffix}-#{format('%.1f', tube_length_mm)}"),
      tube_start, unit
    )
    instances << tube
  end

  class PlacementTool
    def initialize(params)
      @params = params
      @input_point = Sketchup::InputPoint.new
    end

    def activate
      Sketchup.set_status_text('Haz clic para colocar la estructura + tobogán unido.', SB_PROMPT)
    end

    def onMouseMove(_flags, x, y, view)
      @input_point.pick(view, x, y)
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      @input_point.pick(view, x, y)
      prompts = ['Ancho (m)', 'Largo (m)', 'Alto TOTAL (m)']
      defaults = [3.5, 3.5, 4.0]
      results = UI.inputbox(prompts, defaults, 'Estructura + tobogán')
      unless results
        Sketchup.active_model.select_tool(nil)
        return
      end

      ancho_m, largo_m, alto_m = results.map(&:to_f)
      PlayIdeaToboganConEstructuraScript.build_structure_with_tobogan(@input_point.position, ancho_m, largo_m, alto_m)
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

PlayIdeaToboganConEstructuraScript.start
