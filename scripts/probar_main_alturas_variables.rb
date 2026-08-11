# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# VERSION DEL SCRIPT: v1 (2026-08-06)
#
# QUÉ ES ESTO
# -----------
# Prueba el `main.rb` REAL del plugin -no la copia experimental- ya con
# el soporte de alturas de módulo variables portado. Construye una
# estructura 2x2x3 con módulos de 1.70m/1.60m/1.50m -mismo caso ya
# validado en la copia experimental- y su torre, usando `load` para
# recargar `main.rb` en caliente -mismo patrón que probar_integrado.rb,
# que NO se toca-.

MAIN_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea/main.rb'
LOADER_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea.rb'
CODIGO_PRUEBA = 'PRUEBA-MAIN-ALTURAS-VARIABLES'

begin
  load LOADER_RB unless defined?(PlayIdea::ConstructorModulos::EXTENSION)
  load MAIN_RB
  puts "🔄 constructor_modulos_playidea recargado desde el archivo fuente."

  model = Sketchup.active_model
  model.active_entities.grep(Sketchup::Group)
    .select { |g| g.name.to_s.start_with?(CODIGO_PRUEBA) }
    .each(&:erase!)

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
  tower_params = PlayIdea::ConstructorModulos.tower_params_from_dialog(tower_data, structure_params)
  raise 'tower_params_from_dialog devolvió nil' unless tower_params

  puts ''
  puts "Alturas de módulo (mm): #{structure_params[:spacing_z_mm]}"
  puts "Niveles reales de la cuadrícula (mm): #{tower_params[:real_grid_levels_mm].map { |v| v.round(2) }}"
  puts "Escalones de la torre (#{tower_params[:step_heights_mm].length} en total):"
  tower_params[:step_heights_mm].each_with_index do |z, step|
    coincide = tower_params[:real_grid_levels_mm].any? { |lvl| (z - lvl).abs < PlayIdea::ConstructorModulos::GRID_LEVEL_COINCIDENCE_TOLERANCE_MM }
    marca = coincide ? '  <- coincide con nivel real, sin CON-21+patas' : ''
    puts "  Escalón #{step}: Z=#{z.round(2)}mm#{marca}"
  end

  origen = Geom::Point3d.new(0, 0, 0)
  estructura = PlayIdea::ConstructorModulos.create_module(structure_params, origen)
  raise 'create_module devolvió nil' unless estructura

  tower_origin = PlayIdea::ConstructorModulos.offset_point(
    origen, tower_params[:offset_x_mm].mm, tower_params[:offset_y_mm].mm, 0
  )
  torre = PlayIdea::ConstructorModulos.create_triangle_tower(tower_params, tower_origin)
  raise 'create_triangle_tower devolvió nil' unless torre

  model.active_view.zoom([estructura, torre])
  model.selection.clear
  model.selection.add(estructura)
  model.selection.add(torre)
  puts "✅ main.rb real: estructura + torre con alturas de módulo variables -código '#{CODIGO_PRUEBA}'-."
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(8)
end
nil
