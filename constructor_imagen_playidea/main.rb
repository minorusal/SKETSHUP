require 'sketchup.rb'
require 'json'
require 'fileutils'
require 'net/http'

module PlayIdea
  module ConstructorImagen
    extend self

    MODULE_INTERNAL_MM = 1168.4
    API_HOST = '127.0.0.1'.freeze
    API_PORT = 8765
    ANALYSIS_CASE = {
      id: 'estructura_actual',
      module_internal_mm: MODULE_INTERNAL_MM,
      status: 'structure_and_connectors_only'
    }.freeze

    # El dataset usa las constantes dimensionales anteriores, por lo que debe
    # cargarse solamente después de definir el contrato base del plugin.
    require_relative 'synthetic_dataset'

    def start
      unless defined?(UI::HtmlDialog)
        UI.messagebox('Este plugin necesita una versión de SketchUp compatible con HtmlDialog.')
        return
      end

      @dialog&.close
      @dialog = UI::HtmlDialog.new(
        dialog_title: "Constructor desde Imágenes v#{EXTENSION.version}",
        preferences_key: 'PlayIdeaConstructorImagen',
        scrollable: true,
        resizable: true,
        width: 900,
        height: 760,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_file(File.join(__dir__, 'selector.html'))
      @dialog.add_action_callback('ready') do |_context|
        api = start_local_api
        @dialog.execute_script(
          "loadReference(#{JSON.generate(ANALYSIS_CASE.merge(
            api_url: "http://#{API_HOST}:#{API_PORT}",
            api_started: api[:ok],
            api_message: api[:message]
          ))})"
        )
      end
      @dialog.add_action_callback('prepareAnalysis') do |_context, payload|
        image_count = payload['images'].is_a?(Array) ? payload['images'].length : 0
        puts "▶️  Constructor desde Imágenes: #{image_count} vistas preparadas para #{payload['case_id']}."
        @dialog.execute_script(
          "analysisPrepared(#{JSON.generate(
            ok: true,
            image_count: image_count,
            message: 'Las vistas y sus metadatos llegaron correctamente al plugin.'
          )})"
        )
      end
      @dialog.add_action_callback('createSkeleton') do |_context, payload|
        unless constructor_available?
          UI.messagebox(
            "No está disponible el Constructor de Módulos Play Idea.\n\n" \
            'Actívalo en el Administrador de extensiones y reinicia SketchUp.'
          )
          next
        end
        plan = validate_metric_plan(payload)
        next unless plan
        @dialog.close
        Sketchup.active_model.select_tool(SkeletonPlacementTool.new(plan))
      end
      @dialog.show
    rescue StandardError => error
      UI.messagebox("No fue posible abrir el constructor desde imágenes:\n#{error.message}")
      puts error.full_message
    end

    def runtime_python
      File.join(
        Dir.home,
        'Library', 'Application Support', 'PlayIdea',
        'constructor_imagen_runtime', 'bin', 'python3'
      )
    end

    def start_local_api
      return { ok: true, message: 'Servicio local ya estaba activo.' } if api_running?

      python = runtime_python
      return { ok: false, message: 'Falta instalar el runtime local de OpenCV.' } unless File.executable?(python)

      api_dir = File.join(__dir__, 'api')
      log_dir = File.join(Dir.home, 'Library', 'Logs', 'PlayIdea')
      FileUtils.mkdir_p(log_dir)
      log_path = File.join(log_dir, 'constructor_imagen_api.log')
      command = [
        python, '-m', 'uvicorn', 'server:app',
        '--app-dir', api_dir,
        '--host', API_HOST,
        '--port', API_PORT.to_s
      ]
      @api_pid = Process.spawn(*command, out: [log_path, 'a'], err: [:child, :out])
      Process.detach(@api_pid)
      { ok: true, message: 'Servicio local iniciándose.' }
    rescue StandardError => error
      { ok: false, message: "No fue posible iniciar la API local: #{error.message}" }
    end

    def api_running?
      Net::HTTP.start(API_HOST, API_PORT, open_timeout: 0.35, read_timeout: 0.5) do |http|
        response = http.get('/health')
        response.is_a?(Net::HTTPSuccess)
      end
    rescue StandardError
      false
    end

    def validate_metric_plan(payload)
      zones = payload['zones'] if payload.is_a?(Hash)
      unless zones.is_a?(Array) && zones.length.between?(1, 20)
        UI.messagebox('La planta métrica no contiene zonas válidas.')
        return nil
      end
      cleaned = zones.map do |zone|
        kind = zone['kind'].to_s
        values = %w[x y width depth levels].map { |key| zone[key].to_i }
        unless %w[modular special accessory].include?(kind) && values[0].between?(0, 30) && values[1].between?(0, 30) && values[2..4].all? { |value| value.between?(1, 20) }
          UI.messagebox("Zona inválida: #{zone['label']}")
          return nil
        end
        {
          id: zone['id'].to_s,
          label: zone['label'].to_s,
          kind: kind,
          x: values[0], y: values[1], width: values[2], depth: values[3], levels: values[4]
        }
      end
      { module_internal_mm: payload['module_internal_mm'].to_f, zones: cleaned }
    end

    def constructor_available?
      return true if defined?(PlayIdea::ConstructorModulos) &&
        PlayIdea::ConstructorModulos.respond_to?(:create_module)

      require 'constructor_modulos_playidea'
      if defined?(PlayIdea::ConstructorModulos::EXTENSION) &&
          (!defined?(PlayIdea::ConstructorModulos) ||
           !PlayIdea::ConstructorModulos.respond_to?(:create_module))
        require 'constructor_modulos_playidea/main'
      end
      defined?(PlayIdea::ConstructorModulos) &&
        PlayIdea::ConstructorModulos.respond_to?(:create_module)
    rescue LoadError, NameError => error
      puts "No se pudo cargar el constructor modular: #{error.message}"
      false
    end

    def create_placeholder(zone, origin, module_mm)
      model = Sketchup.active_model
      group = model.active_entities.add_group
      group.name = "PRELIMINAR-#{zone[:id].upcase}"
      x0 = origin.x + zone[:x] * module_mm.mm
      y0 = origin.y + zone[:y] * module_mm.mm
      z0_mm = zone[:id] == 'puente' ? module_mm * 2.0 : 0.0
      z0 = origin.z + z0_mm.mm
      width = zone[:width] * module_mm.mm
      depth = zone[:depth] * module_mm.mm
      height_mm = zone[:kind] == 'accessory' ? 100.0 : zone[:levels] * module_mm
      points = [
        Geom::Point3d.new(x0, y0, z0), Geom::Point3d.new(x0 + width, y0, z0),
        Geom::Point3d.new(x0 + width, y0 + depth, z0), Geom::Point3d.new(x0, y0 + depth, z0)
      ]
      face = group.entities.add_face(points)
      face.pushpull(height_mm.mm)
      material_name = "PlayIdea Preliminar #{zone[:kind]}"
      material = model.materials[material_name] || model.materials.add(material_name)
      material.color = zone[:kind] == 'special' ? Sketchup::Color.new(229, 107, 24) : Sketchup::Color.new(96, 168, 50)
      group.material = material
      group.set_attribute('playidea_imagen', 'provisional', true)
      group.set_attribute('playidea_imagen', 'zone_id', zone[:id])
      group
    end

    class SkeletonPlacementTool
      def initialize(plan)
        @plan = plan
        @input = Sketchup::InputPoint.new
      end

      def activate
        Sketchup.set_status_text('Haz clic para colocar el origen de la planta preliminar.', SB_PROMPT)
      end

      def onMouseMove(_flags, x, y, view)
        @input.pick(view, x, y)
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @input.pick(view, x, y)
        return unless @input.valid?
        module_mm = @plan[:module_internal_mm]
        @plan[:zones].each do |zone|
          zone_origin = Geom::Point3d.new(
            @input.position.x + zone[:x] * module_mm.mm,
            @input.position.y + zone[:y] * module_mm.mm,
            @input.position.z
          )
          if zone[:kind] == 'modular'
            params = {
              modules_x: zone[:width], modules_y: zone[:depth], modules_z: zone[:levels],
              spacing_x_mm: module_mm, spacing_y_mm: module_mm, spacing_z_mm: module_mm,
              color: 'Azul', code: "PRE-#{zone[:id].upcase}",
              connectors: true, padding: false
            }
            PlayIdea::ConstructorModulos.create_module(params, zone_origin)
          end
        end
        Sketchup.active_model.select_tool(nil)
        UI.messagebox('Estructura con tubos y conectores creada. Revisa ancho, fondo y niveles antes de continuar con accesorios.')
      rescue StandardError => error
        UI.messagebox("No fue posible crear el esqueleto:\n#{error.message}")
        puts error.full_message
        Sketchup.active_model.select_tool(nil)
      end

      def draw(view)
        @input.draw(view) if @input.valid?
      end
    end

    unless file_loaded?(__FILE__)
      puts "▶️  constructor_imagen_playidea v#{EXTENSION.version} cargado."
      menu = UI.menu('Extensions').add_submenu(
        "Play Idea - Constructor desde Imágenes (v#{EXTENSION.version})"
      )
      menu.add_item('Cargar vistas de un juego') { start }
      menu.add_item('Generar dataset sintético de postes') { generate_synthetic_dataset }
      file_loaded(__FILE__)
    end
  end
end
