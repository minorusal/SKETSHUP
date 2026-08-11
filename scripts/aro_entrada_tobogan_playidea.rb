# Script suelto (NO es un plugin instalable) para probar rápido un ARO
# de entrada para el tobogán -collar/pestaña donde el tramo recto entra
# a la estructura- sin reiniciar SketchUp: edita este archivo y en la
# Consola de Ruby -Window > Ruby Console- corre
#   load '/Users/minorusal/Documents/SKETCHUP/scripts/aro_entrada_tobogan_playidea.rb'
# -o arrastra el archivo a la ventana de SketchUp-. Cada `load` vuelve a
# ejecutar el archivo completo y abre la herramienta de inmediato.
#
# Primer intento -pedido del usuario, descripción verbal, ajustar según
# feedback-: "un aro que es más ancho que el recto, para que el recto
# entre justo en ese aro, y el aro tiene una pestaña para que se vea de
# lado ese aro como un ángulo de 90°".
#
# Geometría: mismo patrón ya usado en tobogan_recto_playidea.rb -circle_
# points + add_wall/add_ring por anillos-, pero como una pieza SUELTA
# -no parte del tramo recto-: un cuerpo cilíndrico corto -COLLAR_LENGTH_MM-
# cuyo diámetro INTERNO recibe el diámetro EXTERIOR del tramo recto -el
# recto entra dentro de este aro-, que en un extremo da un escalón hacia
# afuera -la "pestaña"- a un radio mayor -FLANGE_OUTER_R_MM-, capeado en
# ese extremo. Ese escalón, visto en corte a lo largo del eje, es el
# ángulo de 90° que describió el usuario -el perfil pasa de un cilindro
# angosto a uno más ancho de golpe, en vez de un cono-.

Object.send(:remove_const, :PlayIdeaAroEntradaToboganScript) if defined?(PlayIdeaAroEntradaToboganScript)

module PlayIdeaAroEntradaToboganScript
  extend self

  DICTIONARY = 'playidea_tobogan'.freeze
  SEGMENTS = 48

  # Mismos numeros que BODY_OUTSIDE_R_MM en tobogan_recto_playidea.rb
  # -diametro interno 800mm + pared 8mm- para que el recto entre justo,
  # sin depender de que ese script ya este cargado.
  RECTO_BODY_OUTSIDE_R_MM = (800.0 / 2.0) + 8.0 # 408mm

  WALL_THICKNESS_MM = 8.0
  # Holgura para que el recto entre sin apretar -mismo criterio que
  # CEJA_CLEARANCE_MM en tobogan_recto_playidea.rb, ahi tambien en 0
  # por ahora-.
  CLEARANCE_MM = 0.0

  COLLAR_INNER_R_MM = RECTO_BODY_OUTSIDE_R_MM + CLEARANCE_MM
  COLLAR_OUTER_R_MM = COLLAR_INNER_R_MM + WALL_THICKNESS_MM
  COLLAR_LENGTH_MM = 100.0 # el cuerpo del aro -antes de la pestaña-

  FLANGE_WIDTH_MM = 60.0 # cuanto sobresale la pestaña mas alla del cuerpo del aro
  FLANGE_OUTER_R_MM = COLLAR_OUTER_R_MM + FLANGE_WIDTH_MM
  FLANGE_THICKNESS_MM = 10.0 # grosor de la pestaña misma

  COLOR = Sketchup::Color.new(180, 180, 190)
  CODE = 'TOBOGAN-ARO-ENTRADA'.freeze

  def start
    Sketchup.active_model.select_tool(PlacementTool.new({}))
  rescue StandardError => error
    UI.messagebox("No fue posible iniciar el aro de entrada:\n#{error.message}")
    puts error.full_message
  end

  def circle_points(radius, z_value)
    SEGMENTS.times.map do |index|
      angle = (2.0 * Math::PI * index) / SEGMENTS
      Geom::Point3d.new(radius * Math.cos(angle), radius * Math.sin(angle), z_value)
    end
  end

  def add_wall(entities, radius, z0, z1)
    bottom = circle_points(radius, z0)
    top = circle_points(radius, z1)
    SEGMENTS.times do |index|
      following = (index + 1) % SEGMENTS
      entities.add_face(bottom[index], bottom[following], top[following], top[index])
    end
  end

  def add_ring(entities, inner_r, outer_r, z_value)
    inner = circle_points(inner_r, z_value)
    outer = circle_points(outer_r, z_value)
    SEGMENTS.times do |index|
      following = (index + 1) % SEGMENTS
      entities.add_face(outer[index], outer[following], inner[following], inner[index])
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

  def build_piece(_params, start_point, direction)
    model = Sketchup.active_model
    model.start_operation('Crear aro de entrada de tobogán', true)

    definition = model.definitions.add(unique_name(model, CODE))
    entities = definition.entities

    z0 = 0.mm
    z1 = COLLAR_LENGTH_MM.mm # aqui empieza la pestaña
    z2 = z1 + FLANGE_THICKNESS_MM.mm # remate de la pestaña

    inner_r = COLLAR_INNER_R_MM.mm
    outer_r = COLLAR_OUTER_R_MM.mm
    flange_r = FLANGE_OUTER_R_MM.mm

    add_wall(entities, inner_r, z0, z2)              # pared interior, corrida completa -cuerpo + pestaña-
    add_wall(entities, outer_r, z0, z1)               # pared exterior del CUERPO del aro
    add_wall(entities, flange_r, z1, z2)              # pared exterior de la PESTAÑA -mas ancha-
    add_ring(entities, inner_r, outer_r, z0)          # extremo liso, ABIERTO -por aqui entra el recto-
    add_ring(entities, outer_r, flange_r, z1)         # el ESCALON -el angulo de 90° visto de lado-
    add_ring(entities, inner_r, flange_r, z2)         # remate de la pestaña, cerrado

    soften_circular_edges(entities)

    material = aro_material(model)
    entities.grep(Sketchup::Face).each do |f|
      f.material = material
      f.back_material = material
    end

    definition.set_attribute(DICTIONARY, 'type', 'tobogan_aro_entrada')
    definition.set_attribute(DICTIONARY, 'collar_inner_r_mm', COLLAR_INNER_R_MM)
    definition.set_attribute(DICTIONARY, 'collar_length_mm', COLLAR_LENGTH_MM)
    definition.set_attribute(DICTIONARY, 'flange_outer_r_mm', FLANGE_OUTER_R_MM)

    z_axis = direction.normalize
    helper = z_axis.parallel?(Z_AXIS) ? X_AXIS : Z_AXIS
    x_axis = helper.cross(z_axis).normalize
    y_axis = z_axis.cross(x_axis).normalize
    transform = Geom::Transformation.axes(start_point, x_axis, y_axis, z_axis)
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

  def aro_material(model)
    name = 'PlayIdea Aro Entrada'
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

  # Un clic: coloca el extremo LISO -por donde entra el recto- en el
  # punto marcado, el aro se extiende hacia +X_AXIS -la pestaña queda
  # del lado lejano-.
  class PlacementTool
    def initialize(params)
      @params = params
      @input_point = Sketchup::InputPoint.new
    end

    def activate
      Sketchup.set_status_text('Haz clic para colocar el extremo LISO del aro -se extiende hacia +X, la pestaña queda del lado lejano-.', SB_PROMPT)
    end

    def onMouseMove(_flags, x, y, view)
      @input_point.pick(view, x, y)
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      @input_point.pick(view, x, y)
      PlayIdeaAroEntradaToboganScript.build_piece(@params, @input_point.position, X_AXIS)
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

PlayIdeaAroEntradaToboganScript.start
