require 'sketchup.rb'
require 'extensions.rb'

module PlayIdea
  module ColorearTubos
    EXTENSION = SketchupExtension.new(
      'Play Idea - Colorear Tubos de Esponja',
      'colorear_tubos_playidea/main'
    )
    EXTENSION.description = 'Detecta todos los tubos de esponja (~85mm de diámetro) en el modelo y los ' \
      'colorea con los colores que elijas -máximo 8-, sin que dos tubos que se tocan en un mismo nodo ' \
      'compartan color.'
    EXTENSION.version = '0.1.1'
    EXTENSION.creator = 'Play Idea'
    Sketchup.register_extension(EXTENSION, true)
  end
end
