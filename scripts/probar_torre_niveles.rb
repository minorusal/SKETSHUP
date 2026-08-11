# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# VERSION DEL SCRIPT: v1 (2026-08-06)
#
# QUÉ ES ESTO
# -----------
# Prueba EXPERIMENTAL: si un escalón de la torre cae en la misma altura
# que un nivel real de la cuadrícula -donde ya hay CON-61 y tubo recto de
# esquina a esquina-, ese escalón debe saltarse el CON-21 + 2 patas -se
# duplicaría con lo que ya existe ahí- y poner SOLO la diagonal con sus
# 2 CON-12.
#
# NO usa constructor_modulos_playidea/main.rb -el plugin real, ya
# validado y funcionando, que no se toca para esto- sino una COPIA
# aislada en scripts/main_niveles_experimental.rb, con su propio módulo
# -PlayIdea::ConstructorModulosNiveles, no PlayIdea::ConstructorModulos-,
# así que no pisa nada del plugin real aunque esté instalado o cargado
# en la misma sesión de SketchUp.
#
# CÓMO USARLO
# -----------
# Edita scripts/main_niveles_experimental.rb, vuelve a pegar ESTE script
# completo, y en segundos ves el resultado -mismo truco de `load` que
# probar_integrado.rb-.

EXPERIMENTAL_RB = '/Users/minorusal/Documents/SKETCHUP/scripts/main_niveles_experimental.rb'
LOADER_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea.rb'
CODIGO_PRUEBA = 'PRUEBA-NIVELES'

begin
  # main_niveles_experimental.rb reutiliza conectores_playidea/creador_
  # tubos_playidea -esos sí están al día-, pero necesita que PlayIdea
  # exista como módulo antes de abrirlo -lo garantiza el loader real, sin
  # pisar nada porque el módulo de la torre experimental tiene otro
  # nombre-.
  load LOADER_RB unless defined?(PlayIdea::ConstructorModulos::EXTENSION)
  load EXPERIMENTAL_RB
  puts "🔄 main_niveles_experimental recargado desde el archivo fuente."

  model = Sketchup.active_model

  model.active_entities.grep(Sketchup::Group)
    .select { |g| g.name.to_s.start_with?(CODIGO_PRUEBA) }
    .each(&:erase!)

  # Estructura 2x2x2 -2 módulos de alto- con spacing_z_mm=861.55mm -NO es
  # el spacing real de 1168.4mm del catálogo, es un valor calculado para
  # esta prueba-: con arranque en 500mm y separación auto-ajustada a
  # 500mm -único resultado válido para nz*500=1000mm de recorrido total-,
  # el escalón 1 cae en Z=1000mm, y el nivel real 1 -BASE_GRID_HEIGHT_MM
  # + 1×spacing_z_mm = 138.45+861.55- también cae en Z=1000mm: coinciden
  # SOLOS, sin forzar nada. Con el spacing_z_mm real -1168.4mm- el nivel
  # real 1 cae en 1306.85mm, lejos de cualquier escalón -por eso la
  # prueba anterior con spacing real nunca coincidía sola-.
  structure_params = {
    modules_x: 2,
    modules_y: 2,
    modules_z: 2,
    spacing_x_mm: 1168.4,
    spacing_y_mm: 1168.4,
    spacing_z_mm: 861.55,
    color: 'Azul',
    code: CODIGO_PRUEBA,
    connectors: true,
    padding: false
  }

  tower_data = { 'tower_cell_i' => 0, 'tower_cell_j' => 0, 'tower_corner' => 'sw' }
  tower_params = PlayIdea::ConstructorModulosNiveles.tower_params_from_dialog(tower_data, structure_params)
  raise 'tower_params_from_dialog devolvió nil' unless tower_params

  puts "Escalones: #{tower_params[:steps]}, separación: #{tower_params[:step_spacing_mm].round(1)}mm"
  puts "Niveles reales de la cuadrícula (mm): #{tower_params[:real_grid_levels_mm].map { |v| v.round(1) }}"
  (0...tower_params[:steps]).each do |step|
    z = tower_params[:start_height_mm] + step * tower_params[:step_spacing_mm]
    puts "  Escalón #{step}: Z=#{z.round(1)}mm"
  end

  origen = Geom::Point3d.new(0, 0, 0)
  estructura = PlayIdea::ConstructorModulosNiveles.create_module(structure_params, origen)
  raise 'create_module devolvió nil' unless estructura

  tower_origin = PlayIdea::ConstructorModulosNiveles.offset_point(
    origen, tower_params[:offset_x_mm].mm, tower_params[:offset_y_mm].mm, 0
  )
  torre = PlayIdea::ConstructorModulosNiveles.create_triangle_tower(tower_params, tower_origin)
  raise 'create_triangle_tower devolvió nil' unless torre

  model.active_view.zoom([estructura, torre])
  model.selection.clear
  model.selection.add(estructura)
  model.selection.add(torre)
  puts "✅ Estructura + torre reconstruidas -código '#{CODIGO_PRUEBA}'-. Revisa el escalón 1: debe tener SOLO la diagonal, sin CON-21 ni patas."
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(8)
end
nil
