require 'sketchup.rb'
require 'extensions.rb'

module PlayIdea
  module PanelLaberinto
    EXTENSION = SketchupExtension.new(
      'Play Idea - Panel Laberinto de Cuentas',
      'panel_laberinto_playidea/main'
    )
    EXTENSION.description = 'Genera paneles interactivos de laberinto de cuentas -MDF con canal tallado y ' \
      'cuentas de colores-, con una ruta de laberinto aleatoria distinta en cada corrida.'
    EXTENSION.version = '0.2.0'
    EXTENSION.creator = 'Play Idea'
    Sketchup.register_extension(EXTENSION, true)
  end
end
