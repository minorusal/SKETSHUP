# Script suelto (NO es un plugin instalable) para probar rápido el tramo
# recto de tobogán de fibra de vidrio sin reiniciar SketchUp: edita este
# archivo y en la Consola de Ruby -Window > Ruby Console- corre
#   load '/Users/minorusal/Documents/SKETCHUP/scripts/tobogan_recto_playidea.rb'
# -o arrastra el archivo a la ventana de SketchUp-. Cada `load` vuelve a
# ejecutar el archivo completo y abre la herramienta de inmediato.
#
# Pieza: ducto hueco de diámetro INTERNO 80cm y pared de 8mm. Un extremo
# es liso (se inserta DENTRO de la campana de la pieza anterior); el
# otro extremo tiene una "ceja" -campana- de 10cm donde el diámetro se
# agranda un escalón, para recibir el extremo liso de la SIGUIENTE
# pieza de 80cm/8mm.
#
# Geometría: mismo patrón ya probado en creador_tubos_playidea -circle_
# points + add_face por cada gajo, cara interior invertida-, extendido
# con 2 radios -cuerpo y ceja- y los anillos de transición del escalón,
# en vez de una revolución con followme.

Object.send(:remove_const, :PlayIdeaToboganRectoScript) if defined?(PlayIdeaToboganRectoScript)

module PlayIdeaToboganRectoScript
  extend self

  DICTIONARY = 'playidea_tobogan'.freeze
  SEGMENTS = 48

  INSIDE_DIAMETER_MM = 800.0
  WALL_THICKNESS_MM = 8.0
  TOTAL_LENGTH_MM = 1100.0 # 1.1m - 10cm + 10cm mas, pedido por el usuario -antes 1300mm-
  CEJA_LENGTH_MM = 100.0
  BODY_LENGTH_MM = TOTAL_LENGTH_MM - CEJA_LENGTH_MM

  BODY_INSIDE_R_MM = INSIDE_DIAMETER_MM / 2.0
  BODY_OUTSIDE_R_MM = BODY_INSIDE_R_MM + WALL_THICKNESS_MM
  # La ceja recibe el EXTERIOR de otra pieza igual -mismo diámetro
  # interno/grosor-, así que su diámetro interno = diámetro EXTERNO del
  # cuerpo. PROVISIONAL: sin holgura de ensamble todavía -ajusta
  # CEJA_CLEARANCE_MM si en la pieza real hace falta juego para que
  # entre sin apretar-.
  CEJA_CLEARANCE_MM = 0.0
  CEJA_INSIDE_R_MM = BODY_OUTSIDE_R_MM + CEJA_CLEARANCE_MM
  CEJA_OUTSIDE_R_MM = CEJA_INSIDE_R_MM + WALL_THICKNESS_MM

  COLOR = Sketchup::Color.new(225, 225, 232)

  CODE = "TOBOGAN-RECTO-#{(TOTAL_LENGTH_MM / 10.0).round}".freeze

  def start
    Sketchup.active_model.select_tool(PlacementTool.new({}))
  rescue StandardError => error
    UI.messagebox("No fue posible iniciar el creador de tobogán recto:\n#{error.message}")
    puts error.full_message
  end

  def circle_points(radius, z_value)
    SEGMENTS.times.map do |index|
      angle = (2.0 * Math::PI * index) / SEGMENTS
      Geom::Point3d.new(radius * Math.cos(angle), radius * Math.sin(angle), z_value)
    end
  end

  # Pared cilíndrica lisa entre z0 y z1, a un solo radio -cuerpo O ceja,
  # nunca las 2 a la vez-. Cara exterior con normal hacia afuera, cara
  # interior invertida -misma convención que add_hollow_geometry en
  # creador_tubos_playidea-.
  def add_wall(entities, radius, z0, z1)
    bottom = circle_points(radius, z0)
    top = circle_points(radius, z1)
    SEGMENTS.times do |index|
      following = (index + 1) % SEGMENTS
      entities.add_face(bottom[index], bottom[following], top[following], top[index])
    end
  end

  # Anillo plano -"dona"- a una Z fija, entre 2 radios: los 2 extremos
  # abiertos del ducto -liso y campana-, y los 2 escalones de la
  # transición del cuerpo a la ceja -el de afuera y el de adentro, este
  # último es el TOPE real contra el que llega la siguiente pieza-.
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
    model.start_operation('Crear tramo recto de tobogán', true)

    definition = model.definitions.add(unique_name(model, CODE))
    entities = definition.entities

    z0 = 0.mm
    z_step = BODY_LENGTH_MM.mm
    z1 = TOTAL_LENGTH_MM.mm
    body_inside = BODY_INSIDE_R_MM.mm
    body_outside = BODY_OUTSIDE_R_MM.mm
    ceja_inside = CEJA_INSIDE_R_MM.mm
    ceja_outside = CEJA_OUTSIDE_R_MM.mm

    add_wall(entities, body_inside, z0, z_step)
    add_wall(entities, body_outside, z0, z_step)
    add_ring(entities, body_inside, body_outside, z0) # extremo liso, abierto
    add_ring(entities, body_outside, ceja_outside, z_step) # hombro exterior del escalón
    add_ring(entities, body_inside, ceja_inside, z_step)   # hombro interior -tope de la siguiente pieza-
    add_wall(entities, ceja_inside, z_step, z1)
    add_wall(entities, ceja_outside, z_step, z1)
    add_ring(entities, ceja_inside, ceja_outside, z1) # remate de la campana, abierto

    soften_circular_edges(entities)

    material = tobogan_material(model)
    entities.grep(Sketchup::Face).each do |f|
      f.material = material
      f.back_material = material
    end

    definition.set_attribute(DICTIONARY, 'type', 'tobogan_recto')
    definition.set_attribute(DICTIONARY, 'inside_diameter_mm', INSIDE_DIAMETER_MM)
    definition.set_attribute(DICTIONARY, 'wall_thickness_mm', WALL_THICKNESS_MM)
    definition.set_attribute(DICTIONARY, 'total_length_mm', TOTAL_LENGTH_MM)
    definition.set_attribute(DICTIONARY, 'ceja_length_mm', CEJA_LENGTH_MM)

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

  # Un clic: coloca el extremo LISO en el punto marcado, el ducto se
  # extiende hacia +X_AXIS -dirección fija-. Gira la instancia después
  # con las herramientas normales de SketchUp si hace falta otra
  # orientación.
  class PlacementTool
    def initialize(params)
      @params = params
      @input_point = Sketchup::InputPoint.new
    end

    def activate
      Sketchup.set_status_text('Haz clic para colocar el extremo LISO del tramo -se extiende hacia +X-.', SB_PROMPT)
    end

    def onMouseMove(_flags, x, y, view)
      @input_point.pick(view, x, y)
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      @input_point.pick(view, x, y)
      PlayIdeaToboganRectoScript.build_piece(@params, @input_point.position, X_AXIS)
      Sketchup.active_model.select_tool(nil)
    end

    def draw(view)
      @input_point.draw(view) if @input_point.valid?
      return unless @input_point.valid?
      endpoint = @input_point.position.offset(X_AXIS, PlayIdeaToboganRectoScript::TOTAL_LENGTH_MM.mm)
      view.line_width = 4
      view.drawing_color = 'blue'
      view.draw(GL_LINES, @input_point.position, endpoint)
    end

    def onCancel(_reason, _view)
      Sketchup.active_model.select_tool(nil)
    end

    def getExtents
      bounds = Geom::BoundingBox.new
      if @input_point.valid?
        bounds.add(@input_point.position)
        bounds.add(@input_point.position.offset(X_AXIS, PlayIdeaToboganRectoScript::TOTAL_LENGTH_MM.mm))
      end
      bounds
    end
  end
end

PlayIdeaToboganRectoScript.start
