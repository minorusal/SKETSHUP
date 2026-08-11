require 'sketchup.rb'
require 'extensions.rb'

module PlayIdea
  module AlbercaPelotas
    EXTENSION = SketchupExtension.new(
      'Play Idea - Alberca de Pelotas',
      'alberca_pelotas_playidea/main'
    )
    EXTENSION.description = 'Llena un volumen con pelotas de plástico de colores, ' \
      'usando el mismo catálogo de 8 colores del plugin de pintado de tubos de esponja.'
    EXTENSION.version = '0.1.0'
    EXTENSION.creator = 'Play Idea'
    Sketchup.register_extension(EXTENSION, true)
  end
end
