require 'sketchup.rb'
require 'extensions.rb'

module PlayIdea
  module AutoEtiquetado
    EXTENSION = SketchupExtension.new(
      'Play Idea - Auto Etiquetado',
      'auto_etiquetado_playidea/main'
    )
    EXTENSION.description = 'Auto-etiqueta la estructura por geometría/textura (tags + carpetas) y genera ' \
      'el reporte de inventario y costos -mismo motor que script_auto_etiquetado.rb, empacado como plugin.'
    EXTENSION.version = '1.2.0'
    EXTENSION.creator = 'Play Idea'
    Sketchup.register_extension(EXTENSION, true)
  end
end
