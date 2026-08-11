require 'sketchup.rb'
require 'extensions.rb'

module PlayIdea
  module Cotizador
    EXTENSION = SketchupExtension.new(
      'Play Idea - Cotizador',
      'cotizador_playidea/main'
    )
    EXTENSION.description = 'Cuenta las cantidades de piezas -conectores, tubos, ' \
      'soleras, recubrimiento, tornillería- de una estructura Play Idea ya ' \
      'construida y seleccionada, como base para cotizar.'
    EXTENSION.version = '0.23.0'
    EXTENSION.creator = 'Play Idea'
    Sketchup.register_extension(EXTENSION, true)
  end
end
