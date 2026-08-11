# Script suelto (NO es un plugin instalable) para probar rápido el codo
# de 90° de tobogán de fibra de vidrio sin reiniciar SketchUp: edita
# este archivo y en la Consola de Ruby -Window > Ruby Console- corre
#   load '/Users/minorusal/Documents/SKETCHUP/scripts/codo_90_playidea.rb'
# -o arrastra el archivo a la ventana de SketchUp-. Cada `load` vuelve a
# ejecutar el archivo completo y abre la herramienta de inmediato.
#
# Pieza: mismo ducto hueco (diámetro interno 80cm, pared 8mm) que
# tobogan_recto_playidea.rb, pero curvado 90°, con la misma ceja de
# 10cm en el extremo de salida. RADIO DE CURVATURA -PROVISIONAL,
# confirmar con una pieza real-: igual al diámetro interno (80cm),
# "de ahí debe poder calcularse" según el usuario -sin una medida de
# referencia más precisa todavía-.
#
# Geometría: mismo patrón de circle_points + add_face por gajo que el
# recto -sin followme-, extendido a un barrido angular: en vez de 2
# anillos (arriba/abajo) unidos rectos, son N anillos a lo largo del
# arco de 90°, cada uno rotado según su ángulo, unidos consecutivos.

Object.send(:remove_const, :PlayIdeaCodo90Script) if defined?(PlayIdeaCodo90Script)

module PlayIdeaCodo90Script
  extend self

  DICTIONARY = 'playidea_tobogan'.freeze
  SEGMENTS = 48       # resolución de la circunferencia del tubo
  ANGLE_STEPS = 24    # resolución del barrido de 0 a 90°

  INSIDE_DIAMETER_MM = 800.0
  WALL_THICKNESS_MM = 8.0
  CEJA_LENGTH_MM = 100.0
  SWEEP_ANGLE_DEG = 90.0
  SWEEP_ANGLE_RAD = SWEEP_ANGLE_DEG * Math::PI / 180.0

  BODY_INSIDE_R_MM = INSIDE_DIAMETER_MM / 2.0
  BODY_OUTSIDE_R_MM = BODY_INSIDE_R_MM + WALL_THICKNESS_MM
  CEJA_CLEARANCE_MM = 0.0
  CEJA_INSIDE_R_MM = BODY_OUTSIDE_R_MM + CEJA_CLEARANCE_MM
  CEJA_OUTSIDE_R_MM = CEJA_INSIDE_R_MM + WALL_THICKNESS_MM

  # Radio de curvatura del CENTRO del ducto -no del tubo-. Antes igual
  # al diámetro interno (800mm); el usuario lo fue ajustando -600mm,
  # luego 500mm, ahora 550mm-, SIN tocar el diámetro del tubo -por eso
  # ya no se deriva de INSIDE_DIAMETER_MM, es su propia constante
  # independiente-.
  BEND_RADIUS_MM = 550.0

  COLOR = Sketchup::Color.new(225, 225, 232)
  CODE = 'TOBOGAN-CODO-90'.freeze

  def start
    Sketchup.active_model.select_tool(PlacementTool.new({}))
  rescue StandardError => error
    UI.messagebox("No fue posible iniciar el creador de codo de 90°:\n#{error.message}")
    puts error.full_message
  end

  # Un punto sobre el anillo del ducto a un ángulo `theta` del barrido
  # (0=entrada lisa, PI/2=salida hacia la ceja) y `phi` alrededor de la
  # circunferencia del tubo, a un radio de tubo `radius`. El centro de
  # curva local es (0, BEND_RADIUS_MM, 0) -así el ducto arranca en el
  # ORIGEN viajando hacia +X, igual que tobogan_recto_playidea.rb-.
  def ring_point(theta, radius, phi)
    center_x = BEND_RADIUS_MM.mm * Math.sin(theta)
    center_y = BEND_RADIUS_MM.mm - (BEND_RADIUS_MM.mm * Math.cos(theta))
    radial_x = Math.sin(theta)
    radial_y = -Math.cos(theta)
    r = radius * Math.cos(phi)
    x = center_x + (r * radial_x)
    y = center_y + (r * radial_y)
    z = radius * Math.sin(phi)
    Geom::Point3d.new(x, y, z)
  end

  def ring_points(theta, radius)
    SEGMENTS.times.map { |seg| ring_point(theta, radius, (2.0 * Math::PI * seg) / SEGMENTS) }
  end

  # Punto/dirección de viaje en la SALIDA del barrido (theta=PI/2), para
  # anclar ahí la ceja recta -mismo patrón que un tramo recto normal,
  # solo que arrancando en este punto/dirección en vez del origen/+X-.
  def exit_frame
    theta = SWEEP_ANGLE_RAD
    origin = Geom::Point3d.new(
      BEND_RADIUS_MM.mm * Math.sin(theta),
      BEND_RADIUS_MM.mm - (BEND_RADIUS_MM.mm * Math.cos(theta)),
      0
    )
    forward = Geom::Vector3d.new(Math.cos(theta), Math.sin(theta), 0) # tangente en la salida
    radial = Geom::Vector3d.new(Math.sin(theta), -Math.cos(theta), 0) # "arriba" en la sección transversal, eje U
    [origin, forward, radial]
  end

  def straight_ring_points(origin, forward, radial, up, offset_mm, radius)
    SEGMENTS.times.map do |seg|
      phi = (2.0 * Math::PI * seg) / SEGMENTS
      base = origin + Geom::Vector3d.new(forward.x * offset_mm, forward.y * offset_mm, forward.z * offset_mm)
      u = radius * Math.cos(phi)
      v = radius * Math.sin(phi)
      base + Geom::Vector3d.new(radial.x * u + up.x * v, radial.y * u + up.y * v, radial.z * u + up.z * v)
    end
  end

  # Triangulado -2 triángulos en vez de 1 cuadrilátero-, para que
  # add_face nunca truene por -Points are not planar- si los 4 puntos no
  # caen exactos en un plano. Un triángulo siempre es plano.
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

  def soften_circular_edges(entities)
    entities.grep(Sketchup::Edge).each do |edge|
      edge.soft = true
      edge.smooth = true
    end
  end

  def build_piece(_params, start_point, direction, up_hint = Z_AXIS)
    model = Sketchup.active_model
    model.start_operation('Crear codo de 90° de tobogán', true)

    definition = model.definitions.add(unique_name(model, CODE))
    entities = definition.entities

    # --- Tramo curvo: de theta=0 (liso) a theta=PI/2 (hacia la ceja) ---
    inner_rings = (0..ANGLE_STEPS).map { |i| ring_points(SWEEP_ANGLE_RAD * (i.to_f / ANGLE_STEPS), BODY_INSIDE_R_MM.mm) }
    outer_rings = (0..ANGLE_STEPS).map { |i| ring_points(SWEEP_ANGLE_RAD * (i.to_f / ANGLE_STEPS), BODY_OUTSIDE_R_MM.mm) }
    ANGLE_STEPS.times do |i|
      add_wall_between_rings(entities, inner_rings[i], inner_rings[i + 1])
      add_wall_between_rings(entities, outer_rings[i], outer_rings[i + 1])
    end
    add_ring_face(entities, inner_rings.first, outer_rings.first) # extremo liso, abierto

    # --- Ceja recta en la salida del codo ---
    exit_origin, forward, radial = exit_frame
    up = Z_AXIS
    ceja_z0_inner = straight_ring_points(exit_origin, forward, radial, up, 0, CEJA_INSIDE_R_MM.mm)
    ceja_z0_outer = straight_ring_points(exit_origin, forward, radial, up, 0, CEJA_OUTSIDE_R_MM.mm)
    ceja_z1_inner = straight_ring_points(exit_origin, forward, radial, up, CEJA_LENGTH_MM.mm, CEJA_INSIDE_R_MM.mm)
    ceja_z1_outer = straight_ring_points(exit_origin, forward, radial, up, CEJA_LENGTH_MM.mm, CEJA_OUTSIDE_R_MM.mm)

    add_ring_face(entities, inner_rings.last, ceja_z0_inner) # hombro interior -tope de la siguiente pieza-
    add_ring_face(entities, outer_rings.last, ceja_z0_outer) # hombro exterior
    add_wall_between_rings(entities, ceja_z0_inner, ceja_z1_inner)
    add_wall_between_rings(entities, ceja_z0_outer, ceja_z1_outer)
    add_ring_face(entities, ceja_z1_inner, ceja_z1_outer) # remate de la campana, abierto

    soften_circular_edges(entities)

    material = tobogan_material(model)
    entities.grep(Sketchup::Face).each do |f|
      f.material = material
      f.back_material = material
    end

    definition.set_attribute(DICTIONARY, 'type', 'tobogan_codo_90')
    definition.set_attribute(DICTIONARY, 'inside_diameter_mm', INSIDE_DIAMETER_MM)
    definition.set_attribute(DICTIONARY, 'wall_thickness_mm', WALL_THICKNESS_MM)
    definition.set_attribute(DICTIONARY, 'bend_radius_mm', BEND_RADIUS_MM)
    definition.set_attribute(DICTIONARY, 'ceja_length_mm', CEJA_LENGTH_MM)

    # La geometría viaja en LOCAL +X -no +Z como el tramo recto-, así
    # que aquí `direction` se mapea al eje local X, no Z. `local_y` sale
    # perpendicular a local_x -vía cruz con una referencia-, y
    # `local_z = local_x × local_y` cierra el conjunto siempre bien
    # orientado -mano derecha garantizada por construcción-, para que el
    # codo no salga espejeado -a diferencia de un tubo recto simétrico,
    # aquí SÍ importa: un codo espejeado curva para el lado contrario-.
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

  # Un clic: coloca el extremo LISO en el punto marcado. El ducto arranca
  # hacia +X_AXIS y curva 90° en el plano X-Y -queda "acostado"-; gira la
  # instancia después con las herramientas normales de SketchUp si hace
  # falta otra orientación.
  class PlacementTool
    def initialize(params)
      @params = params
      @input_point = Sketchup::InputPoint.new
    end

    def activate
      Sketchup.set_status_text('Haz clic para colocar el extremo LISO del codo -arranca hacia +X, curva en el plano X-Y-.', SB_PROMPT)
    end

    def onMouseMove(_flags, x, y, view)
      @input_point.pick(view, x, y)
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      @input_point.pick(view, x, y)
      PlayIdeaCodo90Script.build_piece(@params, @input_point.position, X_AXIS)
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

PlayIdeaCodo90Script.start
