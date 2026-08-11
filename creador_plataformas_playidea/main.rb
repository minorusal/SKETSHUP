require 'sketchup.rb'

module PlayIdea
  module CreadorPlataformas
    extend self

    DICTIONARY = 'playidea_plataforma'.freeze

    # Única medida soportada por ahora -confirmado con el usuario: "hay
    # otras medidas de plataforma pero solo comencemos por perfeccionar
    # con 1.22 x 1.22"-. Coincide exactamente con la lámina de triplay
    # (1.22 x 2.44, rinde 2 piezas) y con la receta PLATAFORMA-122X122
    # ya dada de alta en la API de cotizaciones.
    WIDTH_MM = 1220.0
    DEPTH_MM = 1220.0
    TRIPLAY_MM = 15.0
    FOAM_1IN_MM = 25.4
    FOAM_HALF_MM = 12.7
    TOTAL_HEIGHT_MM = TRIPLAY_MM + FOAM_1IN_MM + FOAM_HALF_MM

    # Código de producto terminado en play-idea-explorer -ver POST /api/
    # cotizaciones/calcular-. El nombre de cada instancia se deja fijo en
    # este valor -en vez de editable- para que el futuro conteo en
    # cotizador_playidea pueda detectarlo por patrón, igual que ya hace
    # con SOLERA-1IN/CINCHO-*/REC-*.
    CODE = 'PLATAFORMA-122X122'.freeze

    # Mismos colores reales de Duroplex 18oz que existen en el catálogo
    # de la API -cualquiera de estos tiene el mismo precio por metro
    # lineal, es solo para elegir el acabado visual-.
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
      base = "Plataforma 1.22x1.22"
      name = base
      index = 2
      while model.definitions[name]
        name = "#{base} (#{index})"
        index += 1
      end
      name
    end

    # Una capa = un rectángulo extruido hacia +Z desde z0_mm. Centrado en
    # el origen en X/Y para que el punto de clic quede al centro de la
    # plataforma. Solo colorea las caras que todavía no tienen material
    # -así una capa nunca repinta la de abajo-.
    def add_layer(entities, z0_mm, height_mm, color)
      half_w = (WIDTH_MM / 2.0).mm
      half_d = (DEPTH_MM / 2.0).mm
      z0 = z0_mm.mm
      pts = [
        Geom::Point3d.new(-half_w, -half_d, z0),
        Geom::Point3d.new(half_w, -half_d, z0),
        Geom::Point3d.new(half_w, half_d, z0),
        Geom::Point3d.new(-half_w, half_d, z0)
      ]
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

    # El vinil envuelve toda la superficie expuesta -las 4 caras
    # laterales y la cara superior-, dejando la cara inferior con su
    # color de triplay -queda expuesta, como en la pieza real-. Esto
    # sobreescribe a propósito el color de capa asignado en add_layer.
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

      # Compatibilidad con el auditor de juegos.
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
        CreadorPlataformas.build_plataforma(@params, @input_point.position)
        Sketchup.active_model.select_tool(nil)
      end

      def draw(view)
        @input_point.draw(view) if @input_point.valid?
        return unless @input_point.valid?
        half_w = (CreadorPlataformas::WIDTH_MM / 2.0).mm
        half_d = (CreadorPlataformas::DEPTH_MM / 2.0).mm
        center = @input_point.position
        corners = [
          center.offset(X_AXIS, half_w).offset(Y_AXIS, half_d),
          center.offset(X_AXIS, -half_w).offset(Y_AXIS, half_d),
          center.offset(X_AXIS, -half_w).offset(Y_AXIS, -half_d),
          center.offset(X_AXIS, half_w).offset(Y_AXIS, -half_d)
        ]
        view.line_width = 2
        view.drawing_color = 'blue'
        view.draw(GL_LINE_LOOP, corners)
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

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions').add_submenu('Play Idea - Creador de Plataformas')
      menu.add_item('Crear plataforma (1.22 x 1.22 m)') { start }
      file_loaded(__FILE__)
    end
  end
end
