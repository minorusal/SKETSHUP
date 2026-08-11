require 'sketchup.rb'
require 'json'

module PlayIdea
  module ConstructorImagen
    extend self

    MODULE_INTERNAL_MM = 1168.4
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
        @dialog.execute_script("loadReference(#{JSON.generate(REFERENCE_CASE)})")
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
