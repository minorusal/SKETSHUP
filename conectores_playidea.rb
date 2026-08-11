require 'sketchup.rb'
require 'extensions.rb'

module PlayIdea
  module Conectores
    EXTENSION = SketchupExtension.new(
      'Play Idea - Biblioteca de Conectores',
      'conectores_playidea/main'
    )
    EXTENSION.description = 'Inserta conectores estructurales Play Idea por número.'
    EXTENSION.version = '0.8.0'
    EXTENSION.creator = 'Play Idea'
    Sketchup.register_extension(EXTENSION, true)
  end
end
