require 'sketchup.rb'
require 'extensions.rb'

module PlayIdea
  module AlbercaEsponjas
    EXTENSION = SketchupExtension.new(
      'Play Idea - Alberca de Esponjas',
      'alberca_esponjas_playidea/main'
    )
    EXTENSION.description = 'Llena un volumen con cubos de esponja en posición y rotación aleatorias, simulando una alberca de esponjas.'
    EXTENSION.version = '0.1.1'
    EXTENSION.creator = 'Play Idea'
    Sketchup.register_extension(EXTENSION, true)
  end
end
