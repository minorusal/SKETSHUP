require 'sketchup.rb'
require 'extensions.rb'

module Minorusal
  module AuditorJuegos
    EXTENSION = SketchupExtension.new(
      'Auditor de Juegos Modulares',
      'auditor_juegos/main'
    )
    EXTENSION.description = 'Analiza modelos de juegos infantiles y detecta problemas de organización, documentación y fabricación.'
    EXTENSION.version = '0.2.0'
    EXTENSION.creator = 'Minorusal'
    Sketchup.register_extension(EXTENSION, true)
  end
end
