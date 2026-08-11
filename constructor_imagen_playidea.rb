require 'sketchup.rb'
require 'extensions.rb'

module PlayIdea
  module ConstructorImagen
    EXTENSION = SketchupExtension.new(
      'Play Idea - Constructor desde Imágenes',
      'constructor_imagen_playidea/main'
    )
    EXTENSION.description = 'Analiza varias vistas de un juego y prepara una planta modular editable.'
    EXTENSION.version = '0.1.0'
    EXTENSION.creator = 'Play Idea'
    Sketchup.register_extension(EXTENSION, true)
  end
end
