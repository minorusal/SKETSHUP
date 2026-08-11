# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# VERSION DEL SCRIPT: v2 -estructura completa, no solo la torre- (2026-08-06)
#
# QUÉ ES ESTO
# -----------
# Prueba la lógica de "escalera de planta baja a la ÚLTIMA planta"
# -auto_tower_step_heights- contra 3 niveles reales NO uniformes -altura
# de módulo distinta cada uno: 1.70m, 1.60m, 1.50m-, en vez de la altura
# fija de catálogo (1168.4mm) usada en las pruebas anteriores.
#
# v1 solo construía la torre sola -create_module no soportaba alturas de
# módulo variables-. v2 agrega ese soporte a create_module -en esta copia
# experimental, main.rb real no se toca-: `spacing_z_mm` ahora puede ser
# un Array -una altura por módulo- además del Float uniforme de siempre,
# y `grid_level_z`/`write_module_attributes` ya lo manejan. Con eso
# construye la CUADRÍCULA COMPLETA con las 3 alturas, más la torre.
#
# Usa scripts/main_niveles_experimental.rb -módulo aislado
# PlayIdea::ConstructorModulosNiveles-, NO el plugin real.

EXPERIMENTAL_RB = '/Users/minorusal/Documents/SKETCHUP/scripts/main_niveles_experimental.rb'
LOADER_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea.rb'
CODIGO_PRUEBA = 'PRUEBA-ALTURAS-VARIABLES'

begin
  load LOADER_RB unless defined?(PlayIdea::ConstructorModulos::EXTENSION)
  load EXPERIMENTAL_RB
  puts "🔄 main_niveles_experimental recargado desde el archivo fuente."

  model = Sketchup.active_model
  model.active_entities.grep(Sketchup::Group)
    .select { |g| g.name.to_s.start_with?(CODIGO_PRUEBA) }
    .each(&:erase!)

  # 3 módulos, cada uno de una altura distinta -mm-: 1700, 1600, 1500.
  structure_params = {
    modules_x: 2,
    modules_y: 2,
    modules_z: 3,
    spacing_x_mm: 1168.4,
    spacing_y_mm: 1168.4,
    spacing_z_mm: [1700.0, 1600.0, 1500.0],
    color: 'Azul',
    code: CODIGO_PRUEBA,
    connectors: true,
    padding: false
  }

  tower_data = { 'tower_cell_i' => 0, 'tower_cell_j' => 0, 'tower_corner' => 'sw' }
  tower_params = PlayIdea::ConstructorModulosNiveles.tower_params_from_dialog(tower_data, structure_params)
  raise 'tower_params_from_dialog devolvió nil' unless tower_params

  puts ''
  puts "Alturas de módulo (mm): #{structure_params[:spacing_z_mm]}"
  puts "Niveles reales de la cuadrícula (mm): #{tower_params[:real_grid_levels_mm].map { |v| v.round(2) }}"
  puts "Escalones de la torre (#{tower_params[:step_heights_mm].length} en total):"
  tower_params[:step_heights_mm].each_with_index do |z, step|
    coincide = tower_params[:real_grid_levels_mm].any? { |lvl| (z - lvl).abs < PlayIdea::ConstructorModulosNiveles::GRID_LEVEL_COINCIDENCE_TOLERANCE_MM }
    marca = coincide ? '  <- coincide con nivel real, sin CON-21+patas' : ''
    puts "  Escalón #{step}: Z=#{z.round(2)}mm#{marca}"
  end
  puts "Debe detenerse en el nivel real 2 -base del último módulo, #{tower_params[:real_grid_levels_mm][-2].round(2)}mm-, sin subir hasta el nivel 3 -tope del último módulo, #{tower_params[:real_grid_levels_mm][-1].round(2)}mm-."

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
  puts "✅ Estructura + torre reconstruidas -código '#{CODIGO_PRUEBA}'-, con 3 módulos de altura distinta (1.70m/1.60m/1.50m)."
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(8)
end
nil
