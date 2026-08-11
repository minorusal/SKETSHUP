# Script suelto (NO es un plugin instalable) para probar rápido un
# SOPORTE de solera curva -abraza la circunferencia del tobogán por
# abajo- sin reiniciar SketchUp: edita este archivo y en la Consola de
# Ruby -Window > Ruby Console- corre
#   load '/Users/minorusal/Documents/SKETCHUP/scripts/soporte_solera_playidea.rb'
# -o arrastra el archivo a la ventana de SketchUp-. Cada `load` vuelve a
# ejecutar el archivo completo y abre la herramienta de inmediato.
#
# Pieza: una tira de solera -barra plana de acero, SUPPORT_WIDTH_MM de
# ancho -2"- por SUPPORT_THICKNESS_MM de grueso- doblada en arco para
# abrazar la circunferencia EXTERIOR del ducto del tobogán -mismo radio
# que BODY_OUTSIDE_R_MM de las piezas de ducto, 408mm con diámetro
# interno 800mm + pared 8mm-. Por default abraza la mitad de ABAJO
# -ARC_START_DEG a ARC_END_DEG, 180° a 360°, mismo convenio de "abajo"
# que usa la pieza de salida-, pensado para después atornillarse a un
# poste/pata de soporte -esa estructura todavía no se construye aquí,
# solo la abrazadera-.
#
# Geometría: mismo patrón de anillo + add_face por gajo que las demás
# piezas de ducto -sin followme-, pero como TIRA ABIERTA -no da la
# vuelta completa, solo el arco pedido- y en 2 radios muy cercanos -el
# grueso de la solera, no el grueso de pared de un tubo-.

Object.send(:remove_const, :PlayIdeaSoporteSoleraScript) if defined?(PlayIdeaSoporteSoleraScript)

module PlayIdeaSoporteSoleraScript
  extend self

  DICTIONARY = 'playidea_tobogan'.freeze
  SEGMENTS = 24 # resolución del arco

  SUPPORT_WIDTH_MM = 50.8   # 2"
  SUPPORT_THICKNESS_MM = 6.0
  # Debe coincidir con BODY_OUTSIDE_R_MM de las piezas de ducto -mismo
  # diámetro interno 800mm + pared 8mm-, para que la solera quede
  # exacta contra la superficie exterior del tubo, sin holgura.
  TUBE_OUTER_RADIUS_MM = 408.0
  ARC_START_DEG = 180.0
  ARC_END_DEG = 360.0

  COLOR = Sketchup::Color.new(90, 90, 95)
  CODE = 'TOBOGAN-SOPORTE-SOLERA'.freeze

  def start
    Sketchup.active_model.select_tool(PlacementTool.new({}))
  rescue StandardError => error
    UI.messagebox("No fue posible iniciar el creador de soporte de solera:\n#{error.message}")
    puts error.full_message
  end

  # Anillo -arco ABIERTO, no da la vuelta completa- a un radio y un
  # valor de X -ancho de la solera- dados. SEGMENTS+1 puntos, tira
  # abierta, igual que las tiras abiertas de la pieza de salida.
  def arc_ring_points(radius, x_value)
    start_rad = ARC_START_DEG * Math::PI / 180.0
    end_rad = ARC_END_DEG * Math::PI / 180.0
    (0..SEGMENTS).map do |k|
      phi = start_rad + ((end_rad - start_rad) * k / SEGMENTS)
      Geom::Point3d.new(x_value, radius * Math.cos(phi), radius * Math.sin(phi))
    end
  end

  # Tira ABIERTA -sin wraparound- entre 2 anillos/arcos consecutivos,
  # triangulada -2 triángulos por gajo, nunca "Points are not planar"-.
  def add_open_wall_between_rings(entities, ring_a, ring_b)
    (ring_a.length - 1).times do |index|
      entities.add_face(ring_a[index], ring_a[index + 1], ring_b[index + 1])
      entities.add_face(ring_a[index], ring_b[index + 1], ring_b[index])
    end
  end

  # Cara plana -anillo abierto- entre 2 arcos al MISMO valor de X, a
  # 2 radios distintos -tapa los 2 bordes de ancho de la solera-.
  def add_open_ring_face(entities, inner_ring, outer_ring)
    (inner_ring.length - 1).times do |index|
      entities.add_face(outer_ring[index], outer_ring[index + 1], inner_ring[index + 1])
      entities.add_face(outer_ring[index], inner_ring[index + 1], inner_ring[index])
    end
  end

  # Tapa un extremo del arco -donde empieza/termina, phi fijo- con el
  # grosor de la solera entre los 2 anillos de ancho.
  def add_arc_end_cap(entities, inner_a, outer_a, inner_b, outer_b)
    entities.add_face(inner_a, outer_a, outer_b)
    entities.add_face(inner_a, outer_b, inner_b)
  end

  def soften_edges(entities)
    entities.grep(Sketchup::Edge).each do |edge|
      edge.soft = true
      edge.smooth = true
    end
  end

  # `width_mm` opcional -default SUPPORT_WIDTH_MM, 2"- para poder pedir
  # otros anchos de solera -por ejemplo 3"= 76.2mm- sin duplicar el
  # script entero.
  def build_piece(_params, start_point, direction, up_hint = Z_AXIS, width_mm = SUPPORT_WIDTH_MM)
    model = Sketchup.active_model
    model.start_operation('Crear soporte de solera', true)

    definition = model.definitions.add(unique_name(model, CODE))
    entities = definition.entities

    x0 = -(width_mm.mm) / 2.0
    x1 = (width_mm.mm) / 2.0
    inner_r = TUBE_OUTER_RADIUS_MM.mm
    outer_r = inner_r + SUPPORT_THICKNESS_MM.mm

    inner_front = arc_ring_points(inner_r, x0)
    inner_back = arc_ring_points(inner_r, x1)
    outer_front = arc_ring_points(outer_r, x0)
    outer_back = arc_ring_points(outer_r, x1)

    add_open_wall_between_rings(entities, outer_front, outer_back) # cara exterior
    add_open_wall_between_rings(entities, inner_back, inner_front) # cara interior -orden invertido, normal hacia el tubo-
    add_open_ring_face(entities, inner_front, outer_front) # borde de ancho, lado x0
    add_open_ring_face(entities, inner_back, outer_back)   # borde de ancho, lado x1
    add_arc_end_cap(entities, inner_front.first, outer_front.first, inner_back.first, outer_back.first) # extremo del arco, phi=ARC_START_DEG
    add_arc_end_cap(entities, inner_front.last, outer_front.last, inner_back.last, outer_back.last)     # extremo del arco, phi=ARC_END_DEG

    soften_edges(entities)

    material = soporte_material(model)
    entities.grep(Sketchup::Face).each do |f|
      f.material = material
      f.back_material = material
    end

    definition.set_attribute(DICTIONARY, 'type', 'tobogan_soporte_solera')
    definition.set_attribute(DICTIONARY, 'width_mm', width_mm)
    definition.set_attribute(DICTIONARY, 'thickness_mm', SUPPORT_THICKNESS_MM)
    definition.set_attribute(DICTIONARY, 'tube_outer_radius_mm', TUBE_OUTER_RADIUS_MM)

    # Mismo convenio que el codo/la salida: `direction` se mapea al eje
    # local X -no Z-, `up_hint` controla la rotación alrededor de ese
    # eje -importa porque el arco de la solera SÍ tiene una orientación
    # -de qué lado queda "abajo"-, a diferencia de un tubo redondo
    # simétrico-.
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

  def soporte_material(model)
    name = 'PlayIdea Soporte Solera'
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

  # Un clic: coloca el CENTRO de la solera -a la mitad de su ancho- en
  # el punto marcado, con el eje del tubo hacia +X_AXIS y "abajo" hacia
  # -Z -mismo convenio que la pieza de salida-.
  class PlacementTool
    def initialize(params)
      @params = params
      @input_point = Sketchup::InputPoint.new
    end

    def activate
      Sketchup.set_status_text('Haz clic para colocar el soporte de solera -eje del tubo hacia +X-.', SB_PROMPT)
    end

    def onMouseMove(_flags, x, y, view)
      @input_point.pick(view, x, y)
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      @input_point.pick(view, x, y)
      PlayIdeaSoporteSoleraScript.build_piece(@params, @input_point.position, X_AXIS, Z_AXIS.reverse)
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

PlayIdeaSoporteSoleraScript.start
