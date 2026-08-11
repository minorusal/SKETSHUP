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
    REFERENCE_CASE = {
      id: 'Pi.03315',
      module_internal_mm: MODULE_INTERNAL_MM,
      status: 'reference_only',
      zones: [
        { id: 'jaula', label: 'Jaula rectangular de dos niveles', confidence: 0.92 },
        { id: 'centro', label: 'Trampolines y obstáculos centrales', confidence: 0.86 },
        { id: 'torre', label: 'Torre circular de red', confidence: 0.96, specialized: true },
        { id: 'puente', label: 'Puente elevado con armadura', confidence: 0.94, specialized: true },
        { id: 'tobogan', label: 'Tobogán verde abierto y ondulado', confidence: 0.98, specialized: true },
        { id: 'cancha', label: 'Cancha pequeña de futbol', confidence: 0.91 },
        { id: 'conexiones', label: 'Escaleras, plataformas y conexiones', confidence: 0.78 }
      ]
    }.freeze

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
          "loadReference(#{JSON.generate(REFERENCE_CASE.merge(
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

    unless file_loaded?(__FILE__)
      puts "▶️  constructor_imagen_playidea v#{EXTENSION.version} cargado."
      menu = UI.menu('Extensions').add_submenu(
        "Play Idea - Constructor desde Imágenes (v#{EXTENSION.version})"
      )
      menu.add_item('Cargar vistas de un juego') { start }
      file_loaded(__FILE__)
    end
  end
end
