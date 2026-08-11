require 'sketchup.rb'
require 'extensions.rb'

module PlayIdea
  module CreadorPlataformas
    EXTENSION = SketchupExtension.new(
      'Play Idea - Creador de Plataformas',
      'creador_plataformas_playidea/main'
    )
    EXTENSION.description = 'Crea la plataforma de 1.22 x 1.22 m -triplay, esponja de 1" y 1/2", forro de vinil- como pieza 3D lista para usarse en la estructura.'
    EXTENSION.version = '0.1.0'
    EXTENSION.creator = 'Play Idea'
    Sketchup.register_extension(EXTENSION, true)
  end
end
