require 'sketchup.rb'
require 'json'

module PlayIdea
  module CreadorTubos
    extend self

    DICTIONARY = 'playidea_tubo'.freeze
    SEGMENTS = 32
    CONNECTOR_INSIDE_MM = 41.94
    STANDARD_LENGTHS = {
      'Módulo Play Idea — 1.1684 m' => 1.1684
    }.freeze

    # Espesores en mm para diámetros exteriores comunes.
    # El catálogo puede ampliarse con las medidas reales del proveedor.
    WALL_TABLE = {
      38.1 => { 'ESTRUCTURAL' => 1.50 },
      33.4 => { '10' => 2.77, '40' => 3.38, '80' => 4.55 },
      42.2 => { '10' => 2.77, '40' => 3.56, '80' => 4.85 },
      48.3 => { '10' => 2.77, '40' => 3.68, '80' => 5.08 },
      60.3 => { '10' => 2.77, '40' => 3.91, '80' => 5.54 },
      73.0 => { '10' => 3.05, '40' => 5.16, '80' => 7.01 },
      88.9 => { '10' => 3.05, '40' => 5.49, '80' => 7.62 },
      114.3 => { '10' => 3.05, '40' => 6.02, '80' => 8.56 }
    }.freeze

    def start
      return start_legacy unless defined?(UI::HtmlDialog)

      @dialog&.close
      @dialog = UI::HtmlDialog.new(
        dialog_title: 'Crear tubo Play Idea',
        preferences_key: 'PlayIdeaCreadorTubos',
        scrollable: true,
        resizable: true,
        width: 720,
        height: 650,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_file(File.join(__dir__, 'selector.html'))
      @dialog.add_action_callback('ready') do |_action_context|
        profiles = WALL_TABLE.flat_map do |diameter, schedules|
          schedules.map do |schedule, wall|
            {
              outside_mm: diameter,
              schedule: schedule,
              wall_mm: wall,
              compatible: diameter < CONNECTOR_INSIDE_MM,
              clearance_mm: CONNECTOR_INSIDE_MM - diameter
            }
          end
        end
        standards = STANDARD_LENGTHS.map do |label, meters|
          { label: label, meters: meters }
        end
        @dialog.execute_script(
          "loadTubeCatalog(#{JSON.generate(
            profiles: profiles,
            standards: standards,
            connector_inside_mm: CONNECTOR_INSIDE_MM
          )})"
        )
      end
      @dialog.add_action_callback('createTube') do |_action_context, data|
        params = params_from_dialog(data)
        next unless params
        @dialog.close
        Sketchup.active_model.select_tool(PlacementTool.new(params))
      end
      @dialog.show
    rescue StandardError => error
      UI.messagebox("No fue posible abrir el creador de tubos:\n#{error.message}")
      puts error.full_message
    end

    def params_from_dialog(data)
      length_mm = data['length_m'].to_f * 1000.0
      outside_mm = data['outside_mm'].to_f
      schedule = data['schedule'].to_s
      wall_mm = lookup_wall(outside_mm, schedule)
      unless wall_mm && valid_dimensions?(length_mm, outside_mm, wall_mm)
        UI.messagebox('La longitud o el perfil seleccionado no son válidos.')
        return nil
      end
      {
        length_mm: length_mm,
        outside_mm: outside_mm,
        schedule: schedule,
        wall_mm: wall_mm,
        inside_mm: outside_mm - (2.0 * wall_mm),
        code: data['code'].to_s.strip,
        color: data['color'].to_s,
        length_mode: data['length_mode'].to_s,
        standard_name: data['standard_name'].to_s,
        connector_compatible: outside_mm < CONNECTOR_INSIDE_MM,
        connector_clearance_mm: CONNECTOR_INSIDE_MM - outside_mm
      }
    end

    def start_legacy
      prompts = [
        'Largo del tubo (mm)',
        'Diámetro exterior (mm)',
        'Cédula',
        'Código de pieza',
        'Color'
      ]
      defaults = [1168.4, 38.1, 'ESTRUCTURAL', 'TUB-038-1168', 'Azul']
      lists = ['', diameter_options, 'ESTRUCTURAL|10|40|80', '', 'Azul|Rojo|Amarillo|Verde|Naranja|Gris|Negro']
      values = UI.inputbox(prompts, defaults, lists, 'Crear tubo Play Idea')
      return unless values

      length_mm, outside_mm, schedule, code, color = values
      length_mm = length_mm.to_f
      outside_mm = outside_mm.to_f
      schedule = schedule.to_s
      wall_mm = lookup_wall(outside_mm, schedule)

      unless wall_mm
        UI.messagebox(
          "La combinación Ø#{outside_mm} mm y cédula #{schedule} no está registrada.\n\n" \
          'Debe agregarse al catálogo antes de crear el tubo.'
        )
        return
      end

      unless valid_dimensions?(length_mm, outside_mm, wall_mm)
        UI.messagebox(
          "Las dimensiones no son válidas.\n\n" \
          "Verifica que el largo y el diámetro sean mayores que cero y que el espesor sea menor que la mitad del diámetro."
        )
        return
      end

      params = {
        length_mm: length_mm,
        outside_mm: outside_mm,
        schedule: schedule,
        wall_mm: wall_mm,
        inside_mm: outside_mm - (2.0 * wall_mm),
        code: code.to_s.strip,
        color: color.to_s,
        length_mode: 'legacy',
        standard_name: '',
        connector_compatible: outside_mm < CONNECTOR_INSIDE_MM,
        connector_clearance_mm: CONNECTOR_INSIDE_MM - outside_mm
      }
      Sketchup.active_model.select_tool(PlacementTool.new(params))
    rescue StandardError => error
      UI.messagebox("No fue posible iniciar el creador de tubos:\n#{error.message}")
      puts error.full_message
    end

    def diameter_options
      WALL_TABLE.keys.map { |diameter| format('%.1f', diameter) }.join('|')
    end

    def lookup_wall(outside_mm, schedule)
      diameter = WALL_TABLE.keys.min_by { |candidate| (candidate - outside_mm).abs }
      return nil unless diameter && (diameter - outside_mm).abs < 0.06
      WALL_TABLE[diameter][schedule]
    end

    def valid_dimensions?(length_mm, outside_mm, wall_mm)
      length_mm.positive? && outside_mm.positive? && wall_mm.positive? && (2.0 * wall_mm) < outside_mm
    end

    def build_tube(params, start_point, direction)
      model = Sketchup.active_model
      model.start_operation('Crear tubo Play Idea', true)

      definition_name = unique_definition_name(model, params)
      definition = model.definitions.add(definition_name)
      add_hollow_geometry(definition.entities, params)
      apply_material(model, definition, params[:color])
      write_attributes(definition, params)

      z_axis = direction.normalize
      helper = z_axis.parallel?(Z_AXIS) ? X_AXIS : Z_AXIS
      x_axis = helper.cross(z_axis).normalize
      y_axis = z_axis.cross(x_axis).normalize
      transform = Geom::Transformation.axes(start_point, x_axis, y_axis, z_axis)
      instance = model.active_entities.add_instance(definition, transform)
      instance.name = params[:code].empty? ? definition_name : params[:code]
      write_attributes(instance, params)

      model.selection.clear
      model.selection.add(instance)
      model.commit_operation
      instance
    rescue StandardError
      model.abort_operation
      raise
    end

    def unique_definition_name(model, params)
      base = params[:code].empty? ?
        "Tubo Ø#{format_number(params[:outside_mm])} L#{format_number(params[:length_mm])} C#{params[:schedule]}" :
        params[:code]
      name = base
      index = 2
      while model.definitions[name]
        name = "#{base} (#{index})"
        index += 1
      end
      name
    end

    def add_hollow_geometry(entities, params)
      outer = params[:outside_mm].mm / 2.0
      inner = params[:inside_mm].mm / 2.0
      length = params[:length_mm].mm
      outer_bottom = circle_points(outer, 0)
      outer_top = circle_points(outer, length)
      inner_bottom = circle_points(inner, 0)
      inner_top = circle_points(inner, length)

      SEGMENTS.times do |index|
        following = (index + 1) % SEGMENTS
        entities.add_face(
          outer_bottom[index], outer_bottom[following],
          outer_top[following], outer_top[index]
        )
        inner_face = entities.add_face(
          inner_bottom[index], inner_top[index],
          inner_top[following], inner_bottom[following]
        )
        inner_face.reverse! if inner_face
        entities.add_face(
          outer_bottom[following], outer_bottom[index],
          inner_bottom[index], inner_bottom[following]
        )
        entities.add_face(
          outer_top[index], outer_top[following],
          inner_top[following], inner_top[index]
        )
      end
      soften_circular_edges(entities)
    end

    def circle_points(radius, z_value)
      SEGMENTS.times.map do |index|
        angle = (2.0 * Math::PI * index) / SEGMENTS
        Geom::Point3d.new(radius * Math.cos(angle), radius * Math.sin(angle), z_value)
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

    def apply_material(model, definition, color_name)
      material_name = "PlayIdea Tubo - #{color_name}"
      material = model.materials[material_name] || model.materials.add(material_name)
      material.color = color_value(color_name)
      definition.entities.grep(Sketchup::Face).each do |face|
        face.material = material
        face.back_material = material
      end
    end

    def color_value(name)
      {
        'Azul' => Sketchup::Color.new(25, 85, 210),
        'Rojo' => Sketchup::Color.new(220, 40, 40),
        'Amarillo' => Sketchup::Color.new(245, 205, 25),
        'Verde' => Sketchup::Color.new(35, 170, 80),
        'Naranja' => Sketchup::Color.new(245, 125, 20),
        'Gris' => Sketchup::Color.new(135, 145, 150),
        'Negro' => Sketchup::Color.new(35, 35, 35)
      }[name] || Sketchup::Color.new(135, 145, 150)
    end

    def write_attributes(entity, params)
      {
        'code' => params[:code],
        'length_mm' => params[:length_mm],
        'outside_diameter_mm' => params[:outside_mm],
        'inside_diameter_mm' => params[:inside_mm],
        'wall_thickness_mm' => params[:wall_mm],
        'schedule' => params[:schedule],
        'color' => params[:color],
        'length_mode' => params[:length_mode],
        'standard_name' => params[:standard_name],
        'connector_compatible' => params[:connector_compatible],
        'connector_clearance_mm' => params[:connector_clearance_mm],
        'type' => 'tubo'
      }.each { |key, value| entity.set_attribute(DICTIONARY, key, value) }

      # Compatibilidad con el auditor de juegos.
      entity.set_attribute('minorusal_auditor', 'code', params[:code])
    end

    def format_number(value)
      format('%.1f', value).sub(/\.0\z/, '')
    end

    class PlacementTool
      def initialize(params)
        @params = params
        @input_point = Sketchup::InputPoint.new
        @start_point = nil
        @direction_point = nil
      end

      def activate
        Sketchup.set_status_text('Haz clic para indicar el inicio del tubo.', SB_PROMPT)
      end

      def onMouseMove(_flags, x, y, view)
        @input_point.pick(view, x, y)
        if @start_point
          @direction_point = @input_point.position
          view.invalidate
        end
      end

      def onLButtonDown(_flags, x, y, view)
        @input_point.pick(view, x, y)
        if @start_point.nil?
          @start_point = @input_point.position
          Sketchup.set_status_text('Indica con el segundo clic la dirección del tubo. El largo será el capturado.', SB_PROMPT)
        else
          direction = @input_point.position - @start_point
          return if direction.length < 0.001
          CreadorTubos.build_tube(@params, @start_point, direction)
          Sketchup.active_model.select_tool(nil)
        end
        view.invalidate
      end

      def draw(view)
        @input_point.draw(view) if @input_point.valid?
        return unless @start_point && @direction_point
        direction = @direction_point - @start_point
        return if direction.length < 0.001
        endpoint = @start_point.offset(direction.normalize, @params[:length_mm].mm)
        view.line_width = 4
        view.drawing_color = 'blue'
        view.draw(GL_LINES, @start_point, endpoint)
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end

      def getExtents
        bounds = Geom::BoundingBox.new
        bounds.add(@start_point) if @start_point
        if @start_point && @direction_point
          direction = @direction_point - @start_point
          bounds.add(@start_point.offset(direction.normalize, @params[:length_mm].mm)) if direction.length > 0.001
        end
        bounds
      end
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions').add_submenu('Play Idea - Creador de Tubos')
      menu.add_item('Crear tubo paramétrico') { start }
      file_loaded(__FILE__)
    end
  end
end
