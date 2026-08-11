# Script suelto (NO es un plugin instalable) para probar rápido el
# juego de tornillería que asegura cada unión de pestaña -ceja- entre
# ductos, y también los soportes de solera en cada extremo. Edita este
# archivo y en la Consola de Ruby -Window > Ruby Console- corre
#   load '/Users/minorusal/Documents/SKETCHUP/scripts/tornilleria_playidea.rb'
# -o arrastra el archivo a la ventana de SketchUp-. Cada `load` vuelve a
# ejecutar el archivo completo y abre la herramienta de inmediato.
#
# Pedido del usuario: cada unión de pestaña de los ductos se asegura con
# 4 tornillos "coche" -cabeza redonda, sin filos- galvanizados 5/16"×1½":
# la cabeza queda ADENTRO del ducto -bombudita, no lastima al deslizarse-,
# el vástago cruza las 2 paredes que se traslapan en la ceja, y por
# fuera se aprieta con rondana plana + tuerca -hexagonal por default,
# bellota como variante-. Mismos tornillos aseguran los soportes de
# solera en cada extremo.
#
# Geometría SIMPLIFICADA para esta primera versión -pedir ajuste si
# hace falta más detalle-: la tuerca se modela como un cilindro corto
# -no hexagonal todavía-, la cabeza de coche y la tapa de la tuerca
# bellota se aproximan con un domo -perfil de cuarto de círculo, en
# vez de una esfera exacta-, reusando el mismo patrón circle_points +
# add_wall/add_ring ya usado en las demás piezas del proyecto.
#
# Costos -factura real, para que quede trazable como BOM-:
#   Tornillo coche galv. 5/16"x1 1/2": $1.5958 sin IVA / $1.85 con IVA
#     Proveedora de Tornillos S.A. de C.V., RFC PTO8707098J9,
#     factura FFM-11729, 2018-03-06, UUID 3852316A-FA41-4700-AC14-F0A82F66DCB5
#   Rondana plana galv. 5/16"x7/8": $0.8621 sin IVA / $1.00 con IVA
#   Tuerca hexagonal ligera galv. 5/16"-18 NC: $0.5025 sin IVA / $0.58 con IVA
#   Tuerca bellota niquelada 5/16"-18 NC: $1.7875 sin IVA / $2.07 con IVA
#     Tornillos y Birlos de México, RFC TBM901216PE2, factura TB5668,
#     2024-11-29, UUID 4FF42A36-C115-44E1-8FF2-92FDE413EFE5

Object.send(:remove_const, :PlayIdeaTornilleriaScript) if defined?(PlayIdeaTornilleriaScript)

module PlayIdeaTornilleriaScript
  extend self

  DICTIONARY = 'playidea_tornilleria'.freeze
  SEGMENTS = 24

  # --- Tornillo coche 5/16" x 1 1/2" --------------------------------------
  BOLT_DIAMETER_MM = 7.94   # 5/16"
  BOLT_SHAFT_R_MM = BOLT_DIAMETER_MM / 2.0
  BOLT_LENGTH_MM = 38.1     # 1 1/2", bajo la cabeza
  HEAD_DIAMETER_MM = 19.5
  HEAD_R_MM = HEAD_DIAMETER_MM / 2.0
  HEAD_HEIGHT_MM = 6.5      # cuanto se mete "bombudita" hacia adentro del ducto

  # --- Rondana plana 5/16" x 7/8" -----------------------------------------
  WASHER_OUTER_DIAMETER_MM = 22.225 # 7/8"
  WASHER_OUTER_R_MM = WASHER_OUTER_DIAMETER_MM / 2.0
  WASHER_INNER_R_MM = (BOLT_DIAMETER_MM / 2.0) + 0.4 # holgura para que pase el tornillo
  WASHER_THICKNESS_MM = 1.6

  # --- Tuerca 5/16"-18 NC -- aproximada como cilindro, ver nota arriba ----
  NUT_R_MM = 7.4
  NUT_HEIGHT_MM = 7.9
  NUT_CAP_HEIGHT_MM = 4.5 # solo para la variante "bellota"
  NUT_BORE_R_MM = WASHER_INNER_R_MM

  BOLT_COLOR = Sketchup::Color.new(120, 120, 125)
  NUT_COLOR = Sketchup::Color.new(105, 105, 110)

  CODE = 'TORNILLERIA-5-16-1.5'.freeze

  def start
    Sketchup.active_model.select_tool(PlacementTool.new({}))
  rescue StandardError => error
    UI.messagebox("No fue posible iniciar la tornillería:\n#{error.message}")
    puts error.full_message
  end

  def circle_points(radius, z_value)
    SEGMENTS.times.map do |index|
      angle = (2.0 * Math::PI * index) / SEGMENTS
      Geom::Point3d.new(radius * Math.cos(angle), radius * Math.sin(angle), z_value)
    end
  end

  # Pared cilíndrica -o tronco de cono si r0 != r1- entre z0 y z1.
  def add_wall(entities, r0, r1, z0, z1)
    bottom = circle_points(r0, z0)
    top = circle_points(r1, z1)
    SEGMENTS.times do |index|
      following = (index + 1) % SEGMENTS
      entities.add_face(bottom[index], bottom[following], top[following], top[index])
    end
  end

  def add_ring(entities, inner_r, outer_r, z_value)
    outer = circle_points(outer_r, z_value)
    if inner_r <= 0.mm
      # radio interior 0 -remate cerrado, ej. la punta del vástago-:
      # un anillo con radio interior 0 colapsa todos los puntos
      # "internos" en el mismo punto -"Duplicate points in array" en
      # add_face-, así que se cierra con un abanico de triángulos en
      # vez de la tira de cuadrángulos normal.
      center = Geom::Point3d.new(0, 0, z_value)
      SEGMENTS.times do |index|
        following = (index + 1) % SEGMENTS
        entities.add_face(center, outer[index], outer[following])
      end
      return
    end

    inner = circle_points(inner_r, z_value)
    SEGMENTS.times do |index|
      following = (index + 1) % SEGMENTS
      entities.add_face(outer[index], outer[following], inner[following], inner[index])
    end
  end

  # Domo -perfil de 1/4 de círculo, radio 0 en z0 hasta base_r en
  # z0+height- para la cabeza de coche y la tapa de la tuerca bellota.
  def add_dome(entities, base_r, height, z0, steps: 6)
    profile = (0..steps).map do |i|
      t = i.to_f / steps
      angle = t * (Math::PI / 2.0)
      [base_r * Math.sin(angle), z0 + (height * (1.0 - Math.cos(angle)))]
    end
    apex = Geom::Point3d.new(0, 0, z0)
    top = circle_points(profile[1][0], profile[1][1])
    SEGMENTS.times do |index|
      following = (index + 1) % SEGMENTS
      entities.add_face(apex, top[index], top[following])
    end
    (1...steps).each do |i|
      r0, z0i = profile[i]
      r1, z1i = profile[i + 1]
      add_wall(entities, r0, r1, z0i, z1i)
    end
  end

  def soften_circular_edges(entities)
    entities.grep(Sketchup::Edge).each do |edge|
      vector = edge.end.position - edge.start.position
      next if vector.parallel?(Z_AXIS)

      edge.soft = true
      edge.smooth = true
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

  def material_for(model, name, color)
    material = model.materials[name] || model.materials.add(name)
    material.color = color
    material
  end

  def set_costing(definition, rows)
    definition.set_attribute(DICTIONARY, 'type', 'tornilleria_set')
    definition.set_attribute(DICTIONARY, 'costing_rows', rows.to_json)
  end

  # Una unión de pestaña necesita 4 juegos, y un tobogán completo tiene
  # muchas uniones -uno por cada codo, más el de salida-, así que
  # construir una definición NUEVA por cada tornillo sería carísimo -
  # cientos de caras cada uno-. Para un mismo wall_thickness_mm -en la
  # práctica siempre el mismo, mismas piezas- la forma es IDÉNTICA, así
  # que se construye la geometría UNA sola vez y de ahí en adelante solo
  # se colocan instancias nuevas del mismo componente.
  def bolt_definition(model, wall_thickness_mm)
    @definitions_cache ||= {}
    key = wall_thickness_mm.round(3)
    cached = @definitions_cache[key]
    return cached if cached && model.definitions[cached.name] == cached

    model.start_operation('Crear pieza de tornillería', true)
    definition = build_bolt_definition(model, wall_thickness_mm)
    model.commit_operation
    @definitions_cache[key] = definition
    definition
  rescue StandardError
    model.abort_operation
    raise
  end

  # Pedido del usuario -corrección-: NO es tuerca hexagonal O tapa
  # -bellota-, van LAS DOS: primero la rondana, luego la tuerca
  # hexagonal, y con el tornillo que sobra -el resto del largo nominal,
  # después de cruzar la pared + rondana + tuerca- se pone la tapa
  # encima, cerrando la punta. El largo de la tapa se ADAPTA a lo que
  # sobre de tornillo -varía según wall_thickness_mm-, no es un tamaño
  # fijo: si sobra menos que NUT_CAP_HEIGHT_MM, la tapa es puro domo sin
  # cuerpo recto.
  def build_bolt_definition(model, wall_thickness_mm)
    definition = model.definitions.add(unique_name(model, CODE))
    entities = definition.entities

    head_tip_z = 0.mm
    head_base_z = HEAD_HEIGHT_MM.mm
    shaft_end_z = head_base_z + BOLT_LENGTH_MM.mm
    washer_start_z = head_base_z + wall_thickness_mm.mm
    washer_end_z = washer_start_z + WASHER_THICKNESS_MM.mm
    hex_start_z = washer_end_z
    hex_end_z = hex_start_z + NUT_HEIGHT_MM.mm

    cap_start_z = hex_end_z
    cap_available_mm = [(shaft_end_z - cap_start_z).to_mm, 1.0].max
    cap_dome_mm = [NUT_CAP_HEIGHT_MM, cap_available_mm].min
    cap_skirt_mm = cap_available_mm - cap_dome_mm
    cap_skirt_end_z = cap_start_z + cap_skirt_mm.mm
    cap_tip_z = cap_skirt_end_z + cap_dome_mm.mm

    # Cabeza de coche -domo redondeado, apunta hacia adentro del ducto-
    add_dome(entities, HEAD_R_MM.mm, HEAD_HEIGHT_MM.mm, head_tip_z, steps: 6)
    # Cara de apoyo de la cabeza -plana, contra la pared del ducto-: sin
    # esto quedaba un hueco abierto entre el borde del domo -HEAD_R_MM,
    # más ancho- y el vástago -BOLT_SHAFT_R_MM, más angosto- en la misma Z.
    add_ring(entities, BOLT_SHAFT_R_MM.mm, HEAD_R_MM.mm, head_base_z)
    # Vástago -cilindro liso, hasta donde arranca la tuerca hexagonal;
    # de ahí en adelante lo cubren la tuerca y la tapa-
    add_wall(entities, BOLT_SHAFT_R_MM.mm, BOLT_SHAFT_R_MM.mm, head_base_z, hex_start_z)

    # Rondana
    add_wall(entities, WASHER_INNER_R_MM.mm, WASHER_INNER_R_MM.mm, washer_start_z, washer_end_z)
    add_wall(entities, WASHER_OUTER_R_MM.mm, WASHER_OUTER_R_MM.mm, washer_start_z, washer_end_z)
    add_ring(entities, WASHER_INNER_R_MM.mm, WASHER_OUTER_R_MM.mm, washer_start_z)
    add_ring(entities, WASHER_INNER_R_MM.mm, WASHER_OUTER_R_MM.mm, washer_end_z)

    # Tuerca hexagonal -aproximada como cilindro, ver nota de la
    # geometría simplificada arriba-, pasada de lado a lado
    add_wall(entities, NUT_R_MM.mm, NUT_R_MM.mm, hex_start_z, hex_end_z)
    add_wall(entities, NUT_BORE_R_MM.mm, NUT_BORE_R_MM.mm, hex_start_z, hex_end_z)
    add_ring(entities, NUT_BORE_R_MM.mm, NUT_R_MM.mm, hex_start_z)
    add_ring(entities, NUT_BORE_R_MM.mm, NUT_R_MM.mm, hex_end_z)

    # Tapa/capucha -tuerca bellota-, sobre lo que sobra de tornillo
    # después de la tuerca hexagonal, cerrando la punta.
    add_wall(entities, NUT_R_MM.mm, NUT_R_MM.mm, cap_start_z, cap_skirt_end_z)
    add_wall(entities, NUT_BORE_R_MM.mm, NUT_BORE_R_MM.mm, cap_start_z, cap_skirt_end_z) # barreno ciego
    add_ring(entities, NUT_BORE_R_MM.mm, NUT_R_MM.mm, cap_start_z)
    add_dome(entities, NUT_R_MM.mm, cap_dome_mm.mm, cap_skirt_end_z, steps: 5)

    soften_circular_edges(entities)

    bolt_material = material_for(model, 'PlayIdea Tornillo Galvanizado', BOLT_COLOR)
    nut_material = material_for(model, 'PlayIdea Tuerca/Rondana Galvanizada', NUT_COLOR)
    entities.grep(Sketchup::Face).each do |face|
      inside_nut_zone = face.vertices.all? { |v| v.position.z >= washer_start_z - 0.1.mm }
      material = inside_nut_zone ? nut_material : bolt_material
      face.material = material
      face.back_material = material
    end

    # Factura consolidada -corrección del usuario, reemplaza la factura
    # vieja del tornillo (FFM-11729, proveedor distinto)-: los 4
    # renglones vienen de la MISMA factura TB5668, mismo proveedor.
    rows = [
      { item: 'Tornillo cabeza de coche galvanizado 5/16"-18 NC', unit_cost_mxn: 1.4575, unit_cost_iva_mxn: 1.69,
        provider: 'Tornillos y Birlos de México', rfc: 'TBM901216PE2', invoice: 'TB5668', date: '2024-11-29',
        uuid: '4FF42A36-C115-44E1-8FF2-92FDE413EFE5' },
      { item: 'Rondana plana galvanizada 5/16"x7/8"', unit_cost_mxn: 0.862069, unit_cost_iva_mxn: 1.00,
        provider: 'Tornillos y Birlos de México', rfc: 'TBM901216PE2', invoice: 'TB5668', date: '2024-11-29',
        uuid: '4FF42A36-C115-44E1-8FF2-92FDE413EFE5' },
      { item: 'Tuerca hexagonal ligera galvanizada 5/16"-18 NC', unit_cost_mxn: 0.5025, unit_cost_iva_mxn: 0.58,
        provider: 'Tornillos y Birlos de México', rfc: 'TBM901216PE2', invoice: 'TB5668', date: '2024-11-29',
        uuid: '4FF42A36-C115-44E1-8FF2-92FDE413EFE5' },
      { item: 'Tuerca bellota niquelada 5/16"-18 NC -tapa-', unit_cost_mxn: 1.7875, unit_cost_iva_mxn: 2.07,
        provider: 'Tornillos y Birlos de México', rfc: 'TBM901216PE2', invoice: 'TB5668', date: '2024-11-29',
        uuid: '4FF42A36-C115-44E1-8FF2-92FDE413EFE5' }
    ]
    set_costing(definition, rows)
    definition
  end

  # bore_surface_point: punto sobre la superficie INTERIOR del ducto -
  # el barreno, radio = radio interno del ducto- donde el tornillo
  # cruza hacia afuera. outward_direction: vector radial, del eje del
  # ducto hacia afuera. wall_thickness_mm: grosor TOTAL de material que
  # atraviesa el tornillo -pared de la pieza que entra + pared de la
  # ceja que la recibe-.
  def build_bolt_set(_params, bore_surface_point, outward_direction, wall_thickness_mm)
    model = Sketchup.active_model
    definition = bolt_definition(model, wall_thickness_mm)

    model.start_operation('Colocar tornillo', true)
    z_axis = outward_direction.normalize
    helper = z_axis.parallel?(Z_AXIS) ? X_AXIS : Z_AXIS
    x_axis = helper.cross(z_axis).normalize
    y_axis = z_axis.cross(x_axis).normalize
    tip_point = bore_surface_point.offset(z_axis.reverse, HEAD_HEIGHT_MM.mm)
    transform = Geom::Transformation.axes(tip_point, x_axis, y_axis, z_axis)
    instance = model.active_entities.add_instance(definition, transform)
    # CODE, no un nombre genérico -bug real: con 'TORNILLO' a secas el
    # cotizador -que lee `entity.name` antes que el nombre de la
    # definición- no podía reconocer estas instancias por patrón-.
    instance.name = CODE

    model.commit_operation
    instance
  rescue StandardError
    model.abort_operation
    raise
  end

  # Coloca `count` juegos de tornillo repartidos parejos alrededor de
  # una unión de pestaña. joint_center: punto sobre el EJE del ducto,
  # en la Z de la unión -normalmente a la mitad del largo de la ceja-.
  # axis_direction: hacia donde corre el ducto ahí. inner_r_mm: radio
  # INTERNO del ducto -por donde entra la cabeza-. wall_thickness_mm:
  # grosor total que cruza el tornillo -las 2 paredes traslapadas-.
  # Pedido del usuario: los 4 tornillos no van en cruz -alineados con
  # up_hint, formando un "+"-, van en tache -formando una "X"-. Por eso
  # el reparto arranca desfasado 45° en vez de 0°.
  BOLT_PHASE_DEG = 45.0

  def build_flange_bolts(instances, joint_center, axis_direction, inner_r_mm, wall_thickness_mm, up_hint: Z_AXIS, count: 4)
    axis = axis_direction.normalize
    reference = axis.parallel?(up_hint) ? X_AXIS : up_hint
    radial_a = axis.cross(reference).normalize
    radial_b = axis.cross(radial_a).normalize
    phase = BOLT_PHASE_DEG * Math::PI / 180.0

    count.times do |i|
      angle = phase + ((2.0 * Math::PI * i) / count)
      radial_dir = Geom::Vector3d.new(
        (radial_a.x * Math.cos(angle)) + (radial_b.x * Math.sin(angle)),
        (radial_a.y * Math.cos(angle)) + (radial_b.y * Math.sin(angle)),
        (radial_a.z * Math.cos(angle)) + (radial_b.z * Math.sin(angle))
      ).normalize
      bore_point = joint_center.offset(radial_dir, inner_r_mm.mm)
      bolt = build_bolt_set({}, bore_point, radial_dir, wall_thickness_mm)
      instances << bolt
    end
  end

  # Un clic: prueba rapida, 4 tornillos repartidos alrededor de un punto
  # -simulando una union de pestaña de un ducto de 400mm de radio
  # interno y 16mm de pared total, mismos numeros que tobogan_recto/
  # codo_90-, eje del ducto hacia +X_AXIS.
  class PlacementTool
    def initialize(params)
      @params = params
      @input_point = Sketchup::InputPoint.new
    end

    def activate
      Sketchup.set_status_text('Haz clic para probar 4 tornillos de una unión de pestaña -radio 400mm, pared 16mm-.', SB_PROMPT)
    end

    def onMouseMove(_flags, x, y, view)
      @input_point.pick(view, x, y)
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      @input_point.pick(view, x, y)
      instances = []
      PlayIdeaTornilleriaScript.build_flange_bolts(instances, @input_point.position, X_AXIS, 400.0, 16.0)
      model = Sketchup.active_model
      model.start_operation('Agrupar prueba de tornillería', true)
      group = model.active_entities.add_group(instances)
      group.name = 'Prueba tornillería -4 tornillos-'
      model.commit_operation
      model.selection.clear
      model.selection.add(group)
      view.zoom([group])
      view.invalidate
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

PlayIdeaTornilleriaScript.start
