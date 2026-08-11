require 'sketchup.rb'
require 'extensions.rb'

module PlayIdea
  module ConstructorModulos
    EXTENSION = SketchupExtension.new(
      'Play Idea - Constructor de Módulos',
      'constructor_modulos_playidea/main'
    )
    EXTENSION.description = 'Genera estructuras modulares con tubos y conectores Play Idea.'
    EXTENSION.version = '0.30.1'
    EXTENSION.creator = 'Play Idea'
    Sketchup.register_extension(EXTENSION, true)
  end
end
