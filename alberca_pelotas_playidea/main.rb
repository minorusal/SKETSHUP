require 'sketchup.rb'
require 'json'

module PlayIdea
  module AlbercaPelotas
    extend self

    DICTIONARY = 'PlayIdeaAlbercaPelotas'

    # Diámetro típico de una pelota de plástico de alberca de pelotas
    # comercial (~6-8cm de diámetro); 70mm es un punto medio razonable como
    # valor por defecto -a diferencia de DEFAULT_CUBE_SIZE_MM en
    # alberca_esponjas_playidea, este NO viene de una medida real analizada,
    # es solo el precargado del diálogo- el usuario lo ajusta libremente.
    DEFAULT_BALL_DIAMETER_MM = 70.0

    # Mismo valor de referencia (Módulo Play Idea) que usan los demás
    # plugins de este proyecto, solo para precargar el diálogo.
    DEFAULT_SPACING_M = 1.1684

    # Qué tanto se puede mover cada pelota respecto al centro de su celda de
    # cuadrícula, como fracción de su propio diámetro -mismo mecanismo que
    # JITTER_FACTOR en alberca_esponjas_playidea-. Con 0.35 las pelotas
    # vecinas alcanzan a traslaparse/aplastarse entre sí, como una alberca
    # de pelotas real donde están amontonadas, no en filas perfectas.
    JITTER_FACTOR = 0.35

    # Techo de seguridad: más pelotas que esto puede volverse muy lento o
    # generar un archivo enorme.
    MAX_BALL_COUNT = 6000

    # Segmentos/anillos de la esfera -solo afecta a UNA definición de
    # componente por color, reusada por instancia en cada pelota, así que
    # se puede dar un acabado razonablemente redondo sin impacto real en el
    # tamaño del modelo-.
    SPHERE_SEGMENTS = 16

    # Catálogo FIJO de colores: los MISMOS 8 hex que usa
    # colorear_tubos_playidea -el usuario solo puede marcar cuáles de estos
    # usar, no capturar un color libre-, para que las pelotas combinen con
    # el resto de las piezas Play Idea ya coloreadas con esa paleta.
    COLOR_PALETTE = [
      { hex: 'FF0000', label: 'Rojo' },
      { hex: '84E311', label: 'Verde lima' },
      { hex: 'FFA400', label: 'Naranja' },
      { hex: '039CD4', label: 'Azul' },
      { hex: 'FFFF1E', label: 'Amarillo' },
      { hex: '11D9B4', label: 'Turquesa' },
      { hex: 'D911CB', label: 'Magenta' },
      { hex: '6E247D', label: 'Morado' }
    ].freeze

    def start
      unless defined?(UI::HtmlDialog)
        UI.messagebox('Esta herramienta necesita una versión de SketchUp compatible con HtmlDialog.')
        return
      end

      @dialog&.close
      @dialog = UI::HtmlDialog.new(
        dialog_title: 'Alberca de Pelotas Play Idea',
        preferences_key: 'PlayIdeaAlbercaPelotas',
        scrollable: true,
        resizable: true,
        width: 460,
        height: 680,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_file(File.join(__dir__, 'selector.html'))
      @dialog.add_action_callback('ready') do |_action_context|
        @dialog.execute_script(
          "loadDefaults(#{JSON.generate(
            default_spacing_m: DEFAULT_SPACING_M,
            default_ball_diameter_cm: DEFAULT_BALL_DIAMETER_MM / 10.0,
            palette: COLOR_PALETTE
          )})"
        )
      end
      @dialog.add_action_callback('createBallPit') do |_action_context, data|
        params = validate_dialog_data(data)
        next unless params
        @dialog.close
        Sketchup.active_model.select_tool(PlacementTool.new(params))
      end
      @dialog.show
    rescue StandardError => error
      UI.messagebox("No fue posible abrir la alberca de pelotas:\n#{error.message}")
      puts error.full_message
    end

    def validate_dialog_data(data)
      allowed_hexes = COLOR_PALETTE.map { |c| c[:hex] }
      colors = Array(data['colors']).map(&:to_s).select { |h| allowed_hexes.include?(h) }.uniq

      params = {
        width_mm: data['width_m'].to_f * 1000.0,
        length_mm: data['length_m'].to_f * 1000.0,
        height_mm: data['height_m'].to_f * 1000.0,
        ball_diameter_mm: data['ball_diameter_cm'].to_f * 10.0,
        colors: colors,
        code: data['code'].to_s.strip
      }
      valid = params[:width_mm].positive? && params[:length_mm].positive? &&
        params[:height_mm].positive? && params[:ball_diameter_mm].positive?
      unless valid
        UI.messagebox('Revisa el ancho, alto, largo y el diámetro de pelota -deben ser mayores que cero.')
        return nil
      end
      if colors.empty?
        UI.messagebox('Marca al menos un color de la lista.')
        return nil
      end

      counts = grid_counts(params)
      total = counts[:nx] * counts[:ny] * counts[:nz]
      if total > MAX_BALL_COUNT
        UI.messagebox(
          "Esa combinación generaría #{total} pelotas -demasiadas para un solo " \
          "modelo-. Usa una pelota más grande o reduce el volumen (máximo #{MAX_BALL_COUNT})."
        )
        return nil
      end

      params[:code] = default_code(params) if params[:code].empty?
      params
    end

    def default_code(params)
      w = (params[:width_mm] / 1000.0).round(2)
      l = (params[:length_mm] / 1000.0).round(2)
      h = (params[:height_mm] / 1000.0).round(2)
      "ALBERCA-PELOTAS-#{w}X#{l}X#{h}"
    end

    # Cuántas pelotas caben por eje -redondeado, mínimo 1- para que la
    # cuadrícula base (antes del jitter aleatorio) llene el volumen completo
    # de punta a punta.
    def grid_counts(params)
      {
        nx: [(params[:width_mm] / params[:ball_diameter_mm]).round, 1].max,
        ny: [(params[:length_mm] / params[:ball_diameter_mm]).round, 1].max,
        nz: [(params[:height_mm] / params[:ball_diameter_mm]).round, 1].max
      }
    end

    def offset_point(origin, x, y, z)
      Geom::Point3d.new(origin.x + x, origin.y + y, origin.z + z)
    end

    def unique_name(model, base)
      return base unless model.definitions[base]
      n = 2
      n += 1 while model.definitions["#{base}-#{n}"]
      "#{base}-#{n}"
    end

    def hex_to_color(hex)
      Sketchup::Color.new(hex[0..1].to_i(16), hex[2..3].to_i(16), hex[4..5].to_i(16))
    end

    def apply_material(model, definition, hex)
      material_name = "PlayIdea Pelota - ##{hex}"
      material = model.materials[material_name] || model.materials.add(material_name)
      material.color = hex_to_color(hex)
      definition.entities.grep(Sketchup::Face).each do |face|
        face.material = material
        face.back_material = material
      end
    end

    # Esfera sólida centrada en el origen local -igual que el cubo de
    # alberca_esponjas_playidea, sin hueco interior, no hace falta para una
    # pelota que nunca se ve por dentro-. UV-sphere estándar: anillos de
    # latitud entre polo y polo, con abanico de triángulos en cada polo -los
    # únicos puntos donde toda una fila de la cuadrícula colapsa al mismo
    # punto- y cuadriláteros en el resto.
    def add_sphere_geometry(entities, diameter_mm, segments = SPHERE_SEGMENTS)
      radius = (diameter_mm / 2.0).mm
      rings = [segments / 2, 3].max
      points = (0..rings).map do |i|
        lat = (Math::PI * i / rings) - (Math::PI / 2.0)
        z = radius * Math.sin(lat)
        ring_radius = radius * Math.cos(lat)
        segments.times.map do |j|
          lon = 2 * Math::PI * j / segments.to_f
          Geom::Point3d.new(ring_radius * Math.cos(lon), ring_radius * Math.sin(lon), z)
        end
      end

      (0...rings).each do |i|
        segments.times do |j|
          j2 = (j + 1) % segments
          a, b = points[i][j], points[i][j2]
          c, d = points[i + 1][j2], points[i + 1][j]
          if i.zero?
            entities.add_face(a, c, d) unless a == c || a == d || c == d
          elsif i == rings - 1
            entities.add_face(a, b, c) unless a == b || a == c || b == c
          else
            entities.add_face(a, b, c, d)
          end
        end
      end
    end

    def ball_definition_for(model, cache, hex, ball_diameter_mm)
      key = "#{hex}-#{ball_diameter_mm.round(2)}"
      cache[key] ||= begin
        definition = model.definitions.add(unique_name(model, "PELOTA-#{hex}"))
        add_sphere_geometry(definition.entities, ball_diameter_mm)
        apply_material(model, definition, hex)
        definition
      end
    end

    # `origin` es la esquina inferior (SO, Z=0) de la alberca -la que marca
    # el usuario con el clic-. Llena el volumen ancho×largo×alto con una
    # cuadrícula de pelotas del diámetro elegido, con jitter de posición
    # (ver JITTER_FACTOR) y un color al azar -entre los marcados en el
    # diálogo- por pelota. A diferencia de las esponjas, la pelota no
    # necesita rotación al azar -es una esfera, se ve igual desde cualquier
    # ángulo-.
    def create_ball_pit(params, origin)
      model = Sketchup.active_model
      model.start_operation("Crear alberca de pelotas #{params[:code]}", true)
      container = model.active_entities.add_group
      container.name = params[:code]
      entities = container.entities

      counts = grid_counts(params)
      nx, ny, nz = counts[:nx], counts[:ny], counts[:nz]
      step_x = params[:width_mm] / nx
      step_y = params[:length_mm] / ny
      step_z = params[:height_mm] / nz
      jitter = params[:ball_diameter_mm] * JITTER_FACTOR

      cache = {}
      count = 0

      nz.times do |k|
        ny.times do |j|
          nx.times do |i|
            hex = params[:colors].sample
            definition = ball_definition_for(model, cache, hex, params[:ball_diameter_mm])

            center_x = ((i + 0.5) * step_x) + rand(-jitter..jitter)
            center_y = ((j + 0.5) * step_y) + rand(-jitter..jitter)
            center_z = ((k + 0.5) * step_z) + rand(-jitter..jitter)
            point = offset_point(origin, center_x.mm, center_y.mm, center_z.mm)

            instance = entities.add_instance(definition, Geom::Transformation.translation(point))
            instance.name = 'PELOTA'
            count += 1
          end
        end
      end

      container.set_attribute(DICTIONARY, 'type', 'alberca_pelotas')
      container.set_attribute(DICTIONARY, 'width_mm', params[:width_mm])
      container.set_attribute(DICTIONARY, 'length_mm', params[:length_mm])
      container.set_attribute(DICTIONARY, 'height_mm', params[:height_mm])
      container.set_attribute(DICTIONARY, 'ball_diameter_mm', params[:ball_diameter_mm])
      container.set_attribute(DICTIONARY, 'ball_count', count)
      container.set_attribute('minorusal_auditor', 'code', params[:code])
      model.selection.clear
      model.selection.add(container)
      model.commit_operation
      container
    rescue StandardError
      model.abort_operation
      raise
    end

    class PlacementTool
      def initialize(params)
        @params = params
        @input = Sketchup::InputPoint.new
      end

      def activate
        Sketchup.set_status_text(
          'Haz clic para colocar la esquina inferior de la alberca de pelotas.',
          SB_PROMPT
        )
      end

      def onMouseMove(_flags, x, y, view)
        @input.pick(view, x, y)
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @input.pick(view, x, y)
        return unless @input.valid?
        AlbercaPelotas.create_ball_pit(@params, @input.position)
        Sketchup.active_model.select_tool(nil)
      rescue StandardError => error
        UI.messagebox(
          "No fue posible crear la alberca de pelotas:\n#{error.message}\n\n" \
          "Ubicación: #{error.backtrace&.first}"
        )
        puts error.full_message
        Sketchup.active_model.select_tool(nil)
      end

      def draw(view)
        @input.draw(view) if @input.valid?
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions').add_submenu('Play Idea - Alberca de Pelotas')
      menu.add_item('Crear alberca de pelotas') { start }
      file_loaded(__FILE__)
    end
  end
end
