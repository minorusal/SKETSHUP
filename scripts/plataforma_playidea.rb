# Script suelto (NO es un plugin instalable) para probar rápido la
# geometría de la plataforma sin reiniciar SketchUp: edita este archivo
# y en la Consola de Ruby -Window > Ruby Console- corre
#   load 'Documents/SKETCHUP/script_plataforma_playidea.rb'
# -o arrastra el archivo a la ventana de SketchUp-. Cada `load` vuelve a
# ejecutar el archivo completo y abre el diálogo de inmediato.

Object.send(:remove_const, :PlayIdeaPlataformaScript) if defined?(PlayIdeaPlataformaScript)

module PlayIdeaPlataformaScript
  extend self

  DICTIONARY = 'playidea_plataforma'.freeze

  WIDTH_MM = 1220.0
  DEPTH_MM = 1220.0
  TRIPLAY_MM = 15.0
  FOAM_1IN_MM = 25.4
  FOAM_HALF_MM = 12.7
  TOTAL_HEIGHT_MM = TRIPLAY_MM + FOAM_1IN_MM + FOAM_HALF_MM

  # La plataforma debe entrar entre los postes de la estructura -tubo +
  # protector de esponja que lo cubre-, así que las 4 puntas van
  # cortadas -chaflán a 45°- en vez de en escuadra. El protector de
  # esponja es lo más ancho en cada poste -va sobredimensionado para
  # cubrir también el conector, no solo el tubo, ver constructor_
  # modulos_playidea/main.rb PADDING_OUTSIDE_MM = 85.0mm-, así que ese
  # es el diámetro que hay que despejar en cada esquina.
  POST_ENVELOPE_RADIUS_MM = 85.0 / 2.0
  # Si la punta de la plataforma coincide justo con el centro del poste,
  # el chaflán -medido desde la esquina, sobre cada lado- necesita ser
  # de POST_ENVELOPE_RADIUS_MM * sqrt(2) para que el corte quede
  # tangente al cilindro del poste. PROVISIONAL: falta confirmar
  # visualmente contra un módulo real armado -ajusta este único número y
  # vuelve a cargar el script para iterar rápido-.
  CORNER_CHAMFER_MM = (POST_ENVELOPE_RADIUS_MM * Math.sqrt(2)).ceil

  CODE = 'PLATAFORMA-122X122'.freeze

  VINIL_COLORS = {
    'Morado' => Sketchup::Color.new(90, 40, 120),
    'Fiusha' => Sketchup::Color.new(215, 30, 120),
    'Verde turquesa' => Sketchup::Color.new(20, 150, 140),
    'Verde limón' => Sketchup::Color.new(140, 195, 40),
    'Azul claro' => Sketchup::Color.new(60, 160, 220),
    'Azul rey' => Sketchup::Color.new(20, 60, 160),
    'Rojo' => Sketchup::Color.new(200, 30, 40),
    'Amarillo' => Sketchup::Color.new(240, 200, 30),
    'Beige' => Sketchup::Color.new(215, 195, 160),
    'Negro' => Sketchup::Color.new(30, 30, 30),
    'Café' => Sketchup::Color.new(90, 55, 30),
    'Gris' => Sketchup::Color.new(130, 130, 130),
    'Mandarina' => Sketchup::Color.new(235, 120, 30)
  }.freeze

  WOOD_COLOR = Sketchup::Color.new(200, 170, 120).freeze
  FOAM_COLOR = Sketchup::Color.new(230, 225, 210).freeze

  def start
    prompts = ['Color de vinil (solo visual, no afecta el costo)']
    defaults = [VINIL_COLORS.keys.first]
    lists = [VINIL_COLORS.keys.join('|')]
    values = UI.inputbox(prompts, defaults, lists, 'Crear plataforma Play Idea (1.22 x 1.22 m)')
    return unless values

    color_name = values[0]
    params = { color: color_name, code: CODE }
    Sketchup.active_model.select_tool(PlacementTool.new(params))
  rescue StandardError => error
    UI.messagebox("No fue posible iniciar el creador de plataformas:\n#{error.message}")
    puts error.full_message
  end

  def build_plataforma(params, center_point)
    model = Sketchup.active_model
    model.start_operation('Crear plataforma Play Idea', true)

    definition = model.definitions.add(unique_definition_name(model))
    entities = definition.entities

    z = 0.0
    add_layer(entities, z, TRIPLAY_MM, WOOD_COLOR)
    z += TRIPLAY_MM
    add_layer(entities, z, FOAM_1IN_MM, FOAM_COLOR)
    z += FOAM_1IN_MM
    add_layer(entities, z, FOAM_HALF_MM, FOAM_COLOR)

    wrap_with_vinil(entities, VINIL_COLORS.fetch(params[:color], VINIL_COLORS.values.first))
    write_attributes(definition, params)

    transform = Geom::Transformation.new(center_point)
    instance = model.active_entities.add_instance(definition, transform)
    instance.name = params[:code]
    write_attributes(instance, params)

    model.selection.clear
    model.selection.add(instance)
    model.commit_operation
    instance
  rescue StandardError
    model.abort_operation
    raise
  end

  def unique_definition_name(model)
    base = 'Plataforma 1.22x1.22'
    name = base
    index = 2
    while model.definitions[name]
      name = "#{base} (#{index})"
      index += 1
    end
    name
  end

  # Rectángulo con las 4 puntas cortadas -chaflán CORNER_CHAMFER_MM
  # medido desde cada esquina, sobre cada lado-, en vez de un rectángulo
  # en escuadra. 8 puntos en vez de 4.
  def footprint_points(z0_mm)
    half_w = (WIDTH_MM / 2.0).mm
    half_d = (DEPTH_MM / 2.0).mm
    c = CORNER_CHAMFER_MM.mm
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

  def add_layer(entities, z0_mm, height_mm, color)
    pts = footprint_points(z0_mm)
    face = entities.add_face(pts)
    face.reverse! if face.normal.z < 0
    face.pushpull(height_mm.mm)

    material_name = "PlayIdea Plataforma - #{color_key(color)}"
    material = Sketchup.active_model.materials[material_name] || Sketchup.active_model.materials.add(material_name)
    material.color = color
    entities.grep(Sketchup::Face).each do |f|
      next if f.material
      f.material = material
      f.back_material = material
    end
  end

  def wrap_with_vinil(entities, color)
    material_name = "PlayIdea Plataforma - Vinil #{color_key(color)}"
    material = Sketchup.active_model.materials[material_name] || Sketchup.active_model.materials.add(material_name)
    material.color = color
    top_z = TOTAL_HEIGHT_MM.mm
    entities.grep(Sketchup::Face).each do |face|
      normal = face.normal
      lateral = normal.z.abs < 0.001
      top = normal.z > 0.999 && face.vertices.first.position.z >= (top_z - 0.01.mm)
      next unless lateral || top
      face.material = material
      face.back_material = material
    end
  end

  def color_key(color)
    "#{color.red}-#{color.green}-#{color.blue}"
  end

  def write_attributes(entity, params)
    {
      'code' => params[:code],
      'width_mm' => WIDTH_MM,
      'depth_mm' => DEPTH_MM,
      'triplay_mm' => TRIPLAY_MM,
      'foam_1in_mm' => FOAM_1IN_MM,
      'foam_half_mm' => FOAM_HALF_MM,
      'total_height_mm' => TOTAL_HEIGHT_MM,
      'vinil_color' => params[:color],
      'type' => 'plataforma'
    }.each { |key, value| entity.set_attribute(DICTIONARY, key, value) }

    entity.set_attribute('minorusal_auditor', 'code', params[:code])
  end

  class PlacementTool
    def initialize(params)
      @params = params
      @input_point = Sketchup::InputPoint.new
    end

    def activate
      Sketchup.set_status_text('Haz clic para colocar el centro de la plataforma (queda plana, apoyada en el punto).', SB_PROMPT)
    end

    def onMouseMove(_flags, x, y, view)
      @input_point.pick(view, x, y)
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      @input_point.pick(view, x, y)
      PlayIdeaPlataformaScript.build_plataforma(@params, @input_point.position)
      Sketchup.active_model.select_tool(nil)
    end

    def draw(view)
      @input_point.draw(view) if @input_point.valid?
      return unless @input_point.valid?
      center = @input_point.position
      outline = PlayIdeaPlataformaScript.footprint_points(0.0).map do |pt|
        center.offset(X_AXIS, pt.x).offset(Y_AXIS, pt.y)
      end
      view.line_width = 2
      view.drawing_color = 'blue'
      view.draw(GL_LINE_LOOP, outline)
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

PlayIdeaPlataformaScript.start
