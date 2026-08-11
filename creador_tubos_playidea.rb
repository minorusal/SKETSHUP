require 'sketchup.rb'
require 'extensions.rb'

module PlayIdea
  module CreadorTubos
    EXTENSION = SketchupExtension.new(
      'Play Idea - Creador de Tubos',
      'creador_tubos_playidea/main'
    )
    EXTENSION.description = 'Crea tubos huecos paramétricos por largo, diámetro exterior y cédula.'
    EXTENSION.version = '0.2.0'
    EXTENSION.creator = 'Play Idea'
    Sketchup.register_extension(EXTENSION, true)
  end
end
