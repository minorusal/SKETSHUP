# Script suelto (NO es un plugin instalable) para probar rápido la
# pieza de SALIDA del tobogán sin reiniciar SketchUp: edita este archivo
# y en la Consola de Ruby -Window > Ruby Console- corre
#   load '/Users/minorusal/Documents/SKETCHUP/scripts/salida_tobogan_playidea.rb'
# -o arrastra el archivo a la ventana de SketchUp-. Cada `load` vuelve a
# ejecutar el archivo completo y abre la herramienta de inmediato.
#
# Pieza -REPLANTEADA otra vez según correcciones del usuario-: RECTA
# -la curva de 90° la pone el codo por separado, antes de esta pieza,
# no va aquí-. Entrada LISA -no ceja propia: la pieza anterior -el
# codo- ya trae su propia ceja, y 2 cejas no encajan entre sí, así que
# esta debe entrar lisa para meterse DENTRO de esa ceja-; tubo cerrado
# y redondo, se tapa la mitad de arriba con un casquete plano y sigue
# derecho como medio tubo abierto 30cm -antes 40, dato corregido por el
# usuario-, terminando en un reborde DOBLADO -analogía final del
# usuario: como una hoja de papel a la que se le hacen 2 dobleces
# marcados de 90° sobre la misma orilla, quedando "como un cuadro que
# le falta una cara"-, en vez del tubito redondo de antes.
#
# Perfil del reborde -3 segmentos, esquinas vivas, NO redondeado-: desde
# el punto de la orilla, 1) hacia AFUERA -radial, alejándose del eje del
# tubo- un ancho LIP_FOLD_WIDTH_MM, 2) doblez de 90°, hacia el LADO
# -paralelo a la orilla local- el mismo ancho, 3) doblez de 90° otra
# vez, de vuelta hacia el tubo -paralelo al primer segmento pero
# desfasado-. Ese perfil se barre a lo largo del camino de la orilla
# abierta -collares orientados según la tangente local del camino-.

Object.send(:remove_const, :PlayIdeaSalidaToboganScript) if defined?(PlayIdeaSalidaToboganScript)

module PlayIdeaSalidaToboganScript
  extend self

  DICTIONARY = 'playidea_tobogan'.freeze
  SEGMENTS = 48
  HALF_SEGMENTS = SEGMENTS / 2

  INSIDE_DIAMETER_MM = 800.0
  WALL_THICKNESS_MM = 8.0
  CEJA_LENGTH_MM = 100.0
  # Tubo completo -redondo, cerrado- entre la ceja y donde empieza a
  # abrirse el medio tubo, dato del usuario ("unos 10cm").
  STRAIGHT_ROUND_LENGTH_MM = 100.0
  # Tramo de medio tubo, dato del usuario -corregido de 40 a 30cm-.
  HALF_TUBE_LENGTH_MM = 300.0
  # Ancho de cada uno de los 2 dobleces del reborde, PROVISIONAL -sin
  # confirmar contra una pieza real, un solo número fácil de ajustar-.
  LIP_FOLD_WIDTH_MM = 15.0

  BODY_INSIDE_R_MM = INSIDE_DIAMETER_MM / 2.0
  BODY_OUTSIDE_R_MM = BODY_INSIDE_R_MM + WALL_THICKNESS_MM

  COLOR = Sketchup::Color.new(225, 225, 232)
  CODE = 'TOBOGAN-SALIDA'.freeze

  def start
    Sketchup.active_model.select_tool(PlacementTool.new({}))
  rescue StandardError => error
    UI.messagebox("No fue posible iniciar el creador de salida de tobogán:\n#{error.message}")
    puts error.full_message
  end

  # Anillo COMPLETO en el eje local X -mismo patrón que tobogan_recto_
  # playidea.rb-.
  def full_ring_points(radius, x_value)
    SEGMENTS.times.map do |seg|
      phi = (2.0 * Math::PI * seg) / SEGMENTS
      Geom::Point3d.new(x_value, radius * Math.cos(phi), radius * Math.sin(phi))
    end
  end

  # Mitad de ABAJO -phi 180° a 360°, sin(phi)<=0-, la que se conserva
  # como canal abierto. HALF_SEGMENTS+1 puntos, tira abierta.
  def bottom_half_ring_points(radius, x_value)
    (0..HALF_SEGMENTS).map do |k|
      phi = Math::PI + (Math::PI * k / HALF_SEGMENTS)
      Geom::Point3d.new(x_value, radius * Math.cos(phi), radius * Math.sin(phi))
    end
  end

  # Mitad de ARRIBA -phi 0° a 180°-, la que se tapa con el casquete.
  def top_half_ring_points(radius, x_value)
    (0..HALF_SEGMENTS).map do |k|
      phi = Math::PI * k / HALF_SEGMENTS
      Geom::Point3d.new(x_value, radius * Math.cos(phi), radius * Math.sin(phi))
    end
  end

  def add_wall_between_rings(entities, ring_a, ring_b)
    SEGMENTS.times do |index|
      following = (index + 1) % SEGMENTS
      entities.add_face(ring_a[index], ring_a[following], ring_b[following])
      entities.add_face(ring_a[index], ring_b[following], ring_b[index])
    end
  end

  def add_ring_face(entities, inner_ring, outer_ring)
    SEGMENTS.times do |index|
      following = (index + 1) % SEGMENTS
      entities.add_face(outer_ring[index], outer_ring[following], inner_ring[following])
      entities.add_face(outer_ring[index], inner_ring[following], inner_ring[index])
    end
  end

  def add_open_wall_between_rings(entities, ring_a, ring_b)
    (ring_a.length - 1).times do |index|
      entities.add_face(ring_a[index], ring_a[index + 1], ring_b[index + 1])
      entities.add_face(ring_a[index], ring_b[index + 1], ring_b[index])
    end
  end

  def add_open_ring_face(entities, inner_ring, outer_ring)
    (inner_ring.length - 1).times do |index|
      entities.add_face(outer_ring[index], outer_ring[index + 1], inner_ring[index + 1])
      entities.add_face(outer_ring[index], inner_ring[index + 1], inner_ring[index])
    end
  end

  def add_edge_cap(entities, inner_a, outer_a, inner_b, outer_b)
    entities.add_face(inner_a, outer_a, outer_b)
    entities.add_face(inner_a, outer_b, inner_b)
  end

  # Perfil doblado -4 puntos, 3 segmentos, esquinas vivas- de la sección
  # del reborde en un punto de la orilla. `outward` es la dirección
  # radial -del eje local X del tubo hacia afuera-, bien definida en
  # cualquier punto de esta orilla porque TODA cae sobre el círculo de
  # radio BODY_OUTSIDE_R_MM alrededor del eje X -orillas rectas y arco
  # final por igual-, así que no hace falta ninguna referencia externa.
  # `side` sale de outward × tangent, perpendicular a ambas -paralela a
  # la orilla local-. Con eso: p0 en la orilla misma, p1 = p0 + outward
  # -doblez 1, hacia afuera-, p2 = p1 + side -doblez 2, hacia el lado-,
  # p3 = p2 - outward -doblez 3, de vuelta hacia el tubo-. El resultado
  # traza 3 lados de un cuadrado -"le falta una cara", la que uniría p3
  # de vuelta con p0-.
  def lip_collar(point, tangent, fold_width)
    outward = Geom::Vector3d.new(0, point.y, point.z)
    outward = Geom::Vector3d.new(0, 1, 0) if outward.length < 0.001.mm
    outward = outward.normalize
    side = outward.cross(tangent).normalize
    p0 = point
    p1 = p0 + Geom::Vector3d.new(outward.x * fold_width, outward.y * fold_width, outward.z * fold_width)
    p2 = p1 + Geom::Vector3d.new(side.x * fold_width, side.y * fold_width, side.z * fold_width)
    p3 = p2 - Geom::Vector3d.new(outward.x * fold_width, outward.y * fold_width, outward.z * fold_width)
    [p0, p1, p2, p3]
  end

  # Reborde doblado corriendo por TODA la orilla abierta de la boca
  # -las 2 orillas rectas del medio tubo más el semicírculo del final-,
  # dado el camino como lista de puntos consecutivos: en cada punto se
  # calcula el perfil de 4 puntos -lip_collar- y se conectan los
  # perfiles consecutivos con una tira ABIERTA -add_open_wall_between_
  # rings ya triangula y no cierra en círculo, que es justo lo que hace
  # falta para un perfil que "le falta una cara"-. La tangente en cada
  # punto sale de sus vecinos -en los 2 extremos, del único vecino que
  # hay-.
  def add_rolled_lip(entities, path_points, fold_width)
    collars = path_points.each_with_index.map do |point, i|
      # OJO: `path_points[i - 1]` con i=0 da el ÚLTIMO punto en Ruby
      # -índice negativo-, no nil; por eso el chequeo explícito de
      # `i.zero?`/último índice en vez de `path_points[i-1] || point`.
      prev_pt = i.zero? ? point : path_points[i - 1]
      next_pt = i == path_points.length - 1 ? point : path_points[i + 1]
      tangent = next_pt - prev_pt
      tangent = Geom::Vector3d.new(1, 0, 0) if tangent.length < 0.001.mm
      lip_collar(point, tangent.normalize, fold_width)
    end
    (collars.length - 1).times do |i|
      add_open_wall_between_rings(entities, collars[i], collars[i + 1])
    end
    # Tapa los 2 extremos del reborde -donde arranca/termina el camino-.
    cap_lip_profile(entities, collars.first)
    cap_lip_profile(entities, collars.last)
  end

  # Tapa un perfil de 4 puntos -p0,p1,p2,p3- con 2 triángulos.
  def cap_lip_profile(entities, profile)
    entities.add_face(profile[0], profile[1], profile[2])
    entities.add_face(profile[0], profile[2], profile[3])
  end

  def soften_circular_edges(entities)
    entities.grep(Sketchup::Edge).each do |edge|
      edge.soft = true
      edge.smooth = true
    end
  end

  def build_piece(_params, start_point, direction, up_hint = Z_AXIS)
    model = Sketchup.active_model
    model.start_operation('Crear salida de tobogán', true)

    definition = model.definitions.add(unique_name(model, CODE))
    entities = definition.entities

    x0 = 0.0.mm
    x_step = CEJA_LENGTH_MM.mm
    x_round_end = x_step + STRAIGHT_ROUND_LENGTH_MM.mm
    x_cut = x_round_end + HALF_TUBE_LENGTH_MM.mm

    # --- Entrada LISA -sin ceja propia-: el codo que antecede a esta
    # pieza YA termina en su propia ceja -como todas las piezas de
    # ducto-, así que esta debe entrar LISA para meterse DENTRO de esa
    # ceja -2 cejas no pueden encajar entre sí, hacía falta una lisa-.
    # Tubo redondo completo -diámetro de cuerpo, no de ceja- desde x0
    # hasta x_round_end -incluye lo que antes era ceja+escalón-.
    body_inner_start = full_ring_points(BODY_INSIDE_R_MM.mm, x0)
    body_outer_start = full_ring_points(BODY_OUTSIDE_R_MM.mm, x0)
    add_ring_face(entities, body_inner_start, body_outer_start) # extremo liso, abierto

    # --- Tubo completo y redondo, 10cm, antes de que empiece a abrirse ---
    body_inner_end = full_ring_points(BODY_INSIDE_R_MM.mm, x_round_end)
    body_outer_end = full_ring_points(BODY_OUTSIDE_R_MM.mm, x_round_end)
    add_wall_between_rings(entities, body_inner_start, body_inner_end)
    add_wall_between_rings(entities, body_outer_start, body_outer_end)

    # --- Ahí se tapa la mitad de ARRIBA -casquete plano- ---
    top_inner_cap = top_half_ring_points(BODY_INSIDE_R_MM.mm, x_round_end)
    top_outer_cap = top_half_ring_points(BODY_OUTSIDE_R_MM.mm, x_round_end)
    add_open_ring_face(entities, top_inner_cap, top_outer_cap)

    # --- Medio tubo recto, 30cm, hasta el corte final ---
    half_inner_start = bottom_half_ring_points(BODY_INSIDE_R_MM.mm, x_round_end)
    half_outer_start = bottom_half_ring_points(BODY_OUTSIDE_R_MM.mm, x_round_end)
    half_inner_end = bottom_half_ring_points(BODY_INSIDE_R_MM.mm, x_cut)
    half_outer_end = bottom_half_ring_points(BODY_OUTSIDE_R_MM.mm, x_cut)
    add_open_wall_between_rings(entities, half_inner_start, half_inner_end)
    add_open_wall_between_rings(entities, half_outer_start, half_outer_end)

    # Grosor de pared en las 2 orillas rectas del corte longitudinal.
    add_edge_cap(entities, half_inner_start.first, half_outer_start.first, half_inner_end.first, half_outer_end.first)
    add_edge_cap(entities, half_inner_start.last, half_outer_start.last, half_inner_end.last, half_outer_end.last)

    # Suaviza las aristas circulares construidas HASTA AQUÍ -ceja, tubo
    # redondo, medio tubo- ANTES de agregar el reborde: sus dobleces
    # deben quedar con esquina VIVA -marcada, sin suavizar-, que es
    # justo lo que se busca con la analogía del papel doblado 2 veces.
    soften_circular_edges(entities)

    # --- Reborde doblado en TODA la orilla abierta -las 2 rectas más
    # el semicírculo del final-, en vez de un corte a filo vivo. Se
    # apoya en la superficie EXTERIOR -half_outer_*- como referencia. ---
    lip_path = [half_outer_start.first] + half_outer_end + [half_outer_start.last]
    add_rolled_lip(entities, lip_path, LIP_FOLD_WIDTH_MM.mm)

    material = tobogan_material(model)
    entities.grep(Sketchup::Face).each do |f|
      f.material = material
      f.back_material = material
    end

    definition.set_attribute(DICTIONARY, 'type', 'tobogan_salida')
    definition.set_attribute(DICTIONARY, 'inside_diameter_mm', INSIDE_DIAMETER_MM)
    definition.set_attribute(DICTIONARY, 'wall_thickness_mm', WALL_THICKNESS_MM)
    definition.set_attribute(DICTIONARY, 'half_tube_length_mm', HALF_TUBE_LENGTH_MM)
    definition.set_attribute(DICTIONARY, 'ceja_length_mm', CEJA_LENGTH_MM)
    definition.set_attribute(DICTIONARY, 'lip_fold_width_mm', LIP_FOLD_WIDTH_MM)

    # La geometría viaja en LOCAL +X -no +Z-, igual que el codo -ver su
    # comentario para el detalle-: `direction` se mapea al eje local X,
    # `up_hint` controla la rotación alrededor de ese eje -importa
    # porque la pieza es asimétrica -mitad de arriba tapada, mitad de
    # abajo abierta-, así que "hacia dónde queda el canal abierto" sí
    # depende de esto, a diferencia de un tubo redondo simétrico-.
    local_x = direction.normalize
    reference = local_x.parallel?(up_hint) ? Y_AXIS : up_hint
    local_y = local_x.cross(reference).normalize
    local_z = local_x.cross(local_y).normalize
    transform = Geom::Transformation.axes(start_point, local_x, local_y, local_z)
    instance = model.active_entities.add_instance(definition, transform)
    instance.name = CODE

    model.selection.clear
    model.selection.add(instance)
    model.commit_operation
    instance
  rescue StandardError
    model.abort_operation
    raise
  end

  def tobogan_material(model)
    name = 'PlayIdea Tobogán Fibra de Vidrio'
    material = model.materials[name] || model.materials.add(name)
    material.color = COLOR
    material
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

  # Un clic: coloca el extremo de la CEJA -entrada- en el punto marcado,
  # se extiende hacia +X_AXIS -recta, sin curva-.
  class PlacementTool
    def initialize(params)
      @params = params
      @input_point = Sketchup::InputPoint.new
    end

    def activate
      Sketchup.set_status_text('Haz clic para colocar el extremo de la CEJA -entrada- de la salida.', SB_PROMPT)
    end

    def onMouseMove(_flags, x, y, view)
      @input_point.pick(view, x, y)
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      @input_point.pick(view, x, y)
      PlayIdeaSalidaToboganScript.build_piece(@params, @input_point.position, X_AXIS)
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

PlayIdeaSalidaToboganScript.start
