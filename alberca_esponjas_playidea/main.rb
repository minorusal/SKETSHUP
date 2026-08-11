require 'sketchup.rb'
require 'json'

module PlayIdea
  module AlbercaEsponjas
    extend self

    DICTIONARY = 'PlayIdeaAlbercaEsponjas'

    # Confirmado analizando un ejemplo real armado a mano por el usuario
    # (inspect_20260729_122045.txt, 12 cubos dentro de un contenedor de
    # ~740x733x235mm): TODOS los cubos miden exactamente lo mismo -150mm
    # de arista-, verificado con la fórmula de bounding box de un cubo
    # rotado (bbox_en_un_eje = arista * suma de valores absolutos de esa
    # fila de la matriz de rotación) contra los datos reales del .txt, con
    # coincidencia exacta a 3+ decimales en varios cubos distintos (ej.
    # 150*(0.866+0.5)=204.9mm, igual al bounds real). Las rotaciones del
    # ejemplo no siguen un patrón fijo de ángulos -parecen aleatorias en
    # eje y ángulo, no incrementos de 30/45°-, así que aquí cada cubo se
    # genera con eje y ángulo de rotación totalmente al azar.
    DEFAULT_CUBE_SIZE_MM = 150.0

    # Mismo valor de referencia (Módulo Play Idea) que usan los demás
    # plugins de este proyecto, solo para precargar el diálogo.
    DEFAULT_SPACING_M = 1.1684

    # Qué tanto se puede mover cada cubo respecto al centro de su celda
    # de cuadrícula, como fracción de su propio tamaño -para que no se
    # vea alineado en filas perfectas, como una alberca real revuelta-.
    # Con 0.35 los cubos vecinos alcanzan a traslaparse, igual que en el
    # ejemplo real (huecos negativos de hasta -260mm en su tabla de
    # distancias).
    JITTER_FACTOR = 0.35

    # Techo de seguridad: más cubos que esto puede volverse muy lento o
    # generar un archivo enorme; con este número el diálogo pide reducir
    # el volumen o agrandar el cubo en vez de intentarlo.
    MAX_CUBE_COUNT = 4000

    # Sin Gris ni Negro -no son colores de espuma-.
    COLOR_PALETTE = %w[Azul Rojo Amarillo Verde Naranja].freeze

    def start
      unless defined?(UI::HtmlDialog)
        UI.messagebox('Esta herramienta necesita una versión de SketchUp compatible con HtmlDialog.')
        return
      end

      @dialog&.close
      @dialog = UI::HtmlDialog.new(
        dialog_title: 'Alberca de Esponjas Play Idea',
        preferences_key: 'PlayIdeaAlbercaEsponjas',
        scrollable: true,
        resizable: true,
        width: 480,
        height: 640,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_file(File.join(__dir__, 'selector.html'))
      @dialog.add_action_callback('ready') do |_action_context|
        @dialog.execute_script(
          "loadDefaults(#{JSON.generate(
            default_spacing_m: DEFAULT_SPACING_M,
            default_cube_size_cm: DEFAULT_CUBE_SIZE_MM / 10.0
          )})"
        )
      end
      @dialog.add_action_callback('createFoamPit') do |_action_context, data|
        params = validate_dialog_data(data)
        next unless params
        @dialog.close
        Sketchup.active_model.select_tool(PlacementTool.new(params))
      end
      @dialog.show
    rescue StandardError => error
      UI.messagebox("No fue posible abrir la alberca de esponjas:\n#{error.message}")
      puts error.full_message
    end

    def validate_dialog_data(data)
      params = {
        width_mm: data['width_m'].to_f * 1000.0,
        length_mm: data['length_m'].to_f * 1000.0,
        height_mm: data['height_m'].to_f * 1000.0,
        cube_size_mm: data['cube_size_cm'].to_f * 10.0,
        color_mode: data['color_mode'].to_s,
        color: data['color'].to_s,
        code: data['code'].to_s.strip
      }
      valid = params[:width_mm].positive? && params[:length_mm].positive? &&
        params[:height_mm].positive? && params[:cube_size_mm].positive? &&
        %w[mixed single].include?(params[:color_mode])
      unless valid
        UI.messagebox('Revisa el ancho, alto, largo y tamaño de cubo -deben ser mayores que cero.')
        return nil
      end

      counts = grid_counts(params)
      total = counts[:nx] * counts[:ny] * counts[:nz]
      if total > MAX_CUBE_COUNT
        UI.messagebox(
          "Esa combinación generaría #{total} cubos -demasiados para un solo " \
          "modelo-. Usa un cubo más grande o reduce el volumen (máximo #{MAX_CUBE_COUNT})."
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
      "ALBERCA-#{w}X#{l}X#{h}"
    end

    # Cuántos cubos caben por eje -redondeado, mínimo 1- para que la
    # cuadrícula base (antes del jitter aleatorio) llene el volumen
    # completo de punta a punta.
    def grid_counts(params)
      {
        nx: [(params[:width_mm] / params[:cube_size_mm]).round, 1].max,
        ny: [(params[:length_mm] / params[:cube_size_mm]).round, 1].max,
        nz: [(params[:height_mm] / params[:cube_size_mm]).round, 1].max
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

    def apply_material(model, definition, color_name)
      material_name = "PlayIdea Esponja - #{color_name}"
      material = model.materials[material_name] || model.materials.add(material_name)
      material.color = color_value(color_name)
      definition.entities.grep(Sketchup::Face).each do |face|
        face.material = material
        face.back_material = material
      end
    end

    # Cubo sólido centrado en el origen local, arista `size_mm`. Sin
    # hueco -a diferencia de los tubos estructurales, una esponja no
    # necesita interior hueco-.
    def add_cube_geometry(entities, size_mm)
      h = (size_mm / 2.0).mm
      corners = {}
      [-1, 1].each do |sx|
        [-1, 1].each do |sy|
          [-1, 1].each do |sz|
            corners[[sx, sy, sz]] = Geom::Point3d.new(sx * h, sy * h, sz * h)
          end
        end
      end
      faces = [
        [[-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1]], # abajo
        [[-1, -1, 1], [-1, 1, 1], [1, 1, 1], [1, -1, 1]],     # arriba
        [[-1, -1, -1], [-1, -1, 1], [1, -1, 1], [1, -1, -1]], # frente
        [[-1, 1, -1], [1, 1, -1], [1, 1, 1], [-1, 1, 1]],     # atrás
        [[-1, -1, -1], [-1, 1, -1], [-1, 1, 1], [-1, -1, 1]], # izquierda
        [[1, -1, -1], [1, -1, 1], [1, 1, 1], [1, 1, -1]]      # derecha
      ]
      faces.each { |pts| entities.add_face(pts.map { |key| corners[key] }) }
    end

    def cube_definition_for(model, cache, color_name, cube_size_mm)
      key = "#{color_name}-#{cube_size_mm.round(2)}"
      cache[key] ||= begin
        definition = model.definitions.add(unique_name(model, "CUBO-ESPONJA-#{color_name}"))
        add_cube_geometry(definition.entities, cube_size_mm)
        apply_material(model, definition, color_name)
        definition
      end
    end

    # Eje y ángulo totalmente al azar -ver DEFAULT_CUBE_SIZE_MM para la
    # justificación-, compuesto como traslación × rotación-en-el-origen
    # para que la rotación sea respecto al propio centro del cubo, no
    # respecto al origen del modelo.
    def random_rotation_transform(point)
      axis = Geom::Vector3d.new(rand(-1.0..1.0), rand(-1.0..1.0), rand(-1.0..1.0))
      axis = Z_AXIS if axis.length < 0.0001
      angle = rand(0.0..(2 * Math::PI))
      Geom::Transformation.translation(point) *
        Geom::Transformation.rotation(ORIGIN, axis, angle)
    end

    # `origin` es la esquina inferior (SO, Z=0) de la alberca -la que
    # marca el usuario con el clic-. Llena el volumen ancho×largo×alto
    # con una cuadrícula de cubos del tamaño elegido y le aplica jitter
    # de posición + rotación aleatoria a cada uno -ver JITTER_FACTOR-.
    def create_foam_pit(params, origin)
      model = Sketchup.active_model
      model.start_operation("Crear alberca de esponjas #{params[:code]}", true)
      container = model.active_entities.add_group
      container.name = params[:code]
      entities = container.entities

      counts = grid_counts(params)
      nx, ny, nz = counts[:nx], counts[:ny], counts[:nz]
      step_x = params[:width_mm] / nx
      step_y = params[:length_mm] / ny
      step_z = params[:height_mm] / nz
      jitter = params[:cube_size_mm] * JITTER_FACTOR

      cache = {}
      count = 0

      nz.times do |k|
        ny.times do |j|
          nx.times do |i|
            color = params[:color_mode] == 'mixed' ? COLOR_PALETTE.sample : params[:color]
            definition = cube_definition_for(model, cache, color, params[:cube_size_mm])

            center_x = ((i + 0.5) * step_x) + rand(-jitter..jitter)
            center_y = ((j + 0.5) * step_y) + rand(-jitter..jitter)
            center_z = ((k + 0.5) * step_z) + rand(-jitter..jitter)
            point = offset_point(origin, center_x.mm, center_y.mm, center_z.mm)

            transform = random_rotation_transform(point)
            instance = entities.add_instance(definition, transform)
            instance.name = 'CUBO-ESPONJA'
            count += 1
          end
        end
      end

      container.set_attribute(DICTIONARY, 'type', 'alberca_esponjas')
      container.set_attribute(DICTIONARY, 'width_mm', params[:width_mm])
      container.set_attribute(DICTIONARY, 'length_mm', params[:length_mm])
      container.set_attribute(DICTIONARY, 'height_mm', params[:height_mm])
      container.set_attribute(DICTIONARY, 'cube_size_mm', params[:cube_size_mm])
      container.set_attribute(DICTIONARY, 'cube_count', count)
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
          'Haz clic para colocar la esquina inferior de la alberca de esponjas.',
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
        AlbercaEsponjas.create_foam_pit(@params, @input.position)
        Sketchup.active_model.select_tool(nil)
      rescue StandardError => error
        UI.messagebox(
          "No fue posible crear la alberca de esponjas:\n#{error.message}\n\n" \
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
      menu = UI.menu('Extensions').add_submenu('Play Idea - Alberca de Esponjas')
      menu.add_item('Crear alberca de esponjas') { start }
      file_loaded(__FILE__)
    end
  end
end
