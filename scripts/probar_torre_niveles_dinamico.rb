# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# VERSION DEL SCRIPT: v1 (2026-08-06)
#
# QUÉ ES ESTO
# -----------
# Prueba que el cálculo de escalones -cuántos, y su separación- es
# DINÁMICO: depende de la altura REAL del módulo (`spacing_z_mm`) que se
# le pase, no de un número fijo. Construye 4 estructuras en fila, cada
# una con una altura de módulo distinta -incluida la real del catálogo,
# 1168.4mm-, cada una con su propia torre, y muestra en consola cuántos
# escalones salieron y en qué alturas -para confirmar a simple vista que
# cambian según la altura de cada estructura, y que los escalones que
# coinciden con un nivel real -donde ya hay CON-61 y tubo recto- se
# saltan el CON-21+patas-.
#
# Usa scripts/main_niveles_experimental.rb -módulo aislado
# PlayIdea::ConstructorModulosNiveles-, NO el plugin real
# -constructor_modulos_playidea/main.rb, que no se toca-.

EXPERIMENTAL_RB = '/Users/minorusal/Documents/SKETCHUP/scripts/main_niveles_experimental.rb'
LOADER_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea.rb'
CODIGO_PRUEBA = 'PRUEBA-NIVELES-DINAMICO'
SEPARACION_ENTRE_ESTRUCTURAS_MM = 5000.0

begin
  load LOADER_RB unless defined?(PlayIdea::ConstructorModulos::EXTENSION)
  load EXPERIMENTAL_RB
  puts "🔄 main_niveles_experimental recargado desde el archivo fuente."

  model = Sketchup.active_model
  model.active_entities.grep(Sketchup::Group)
    .select { |g| g.name.to_s.start_with?(CODIGO_PRUEBA) }
    .each(&:erase!)

  # 4 alturas de módulo distintas -mm-: la real del catálogo (1168.4), una
  # más chica, una más grande, y la del ejemplo que dio el usuario (2000mm
  # -"si el módulo mide 1 [...] antes de llegar a los 2m"-).
  casos = [
    { spacing_z_mm: 1168.4, modules_z: 2, etiqueta: 'catálogo 1168.4mm' },
    { spacing_z_mm: 700.0, modules_z: 2, etiqueta: 'chico 700mm' },
    { spacing_z_mm: 2000.0, modules_z: 1, etiqueta: 'grande 2000mm (ejemplo del usuario)' },
    { spacing_z_mm: 861.55, modules_z: 2, etiqueta: '861.55mm (coincidencia exacta a propósito)' }
  ]

  grupos_para_zoom = []

  casos.each_with_index do |caso, indice|
    codigo = "#{CODIGO_PRUEBA}-#{indice}"
    structure_params = {
      modules_x: 2,
      modules_y: 2,
      modules_z: caso[:modules_z],
      spacing_x_mm: 1168.4,
      spacing_y_mm: 1168.4,
      spacing_z_mm: caso[:spacing_z_mm],
      color: 'Azul',
      code: codigo,
      connectors: true,
      padding: false
    }

    tower_data = { 'tower_cell_i' => 0, 'tower_cell_j' => 0, 'tower_corner' => 'sw' }
    tower_params = PlayIdea::ConstructorModulosNiveles.tower_params_from_dialog(tower_data, structure_params)
    raise "tower_params_from_dialog devolvió nil para el caso #{indice} -#{caso[:etiqueta]}-" unless tower_params

    puts ''
    puts "=== Caso #{indice}: módulo #{caso[:etiqueta]}, modules_z=#{caso[:modules_z]} ==="
    puts "Niveles reales de la cuadrícula (mm): #{tower_params[:real_grid_levels_mm].map { |v| v.round(1) }}"
    puts "Escalones de la torre (#{tower_params[:step_heights_mm].length} en total):"
    tower_params[:step_heights_mm].each_with_index do |z, step|
      coincide = tower_params[:real_grid_levels_mm].any? { |lvl| (z - lvl).abs < PlayIdea::ConstructorModulosNiveles::GRID_LEVEL_COINCIDENCE_TOLERANCE_MM }
      marca = coincide ? '  <- coincide con nivel real, sin CON-21+patas' : ''
      puts "  Escalón #{step}: Z=#{z.round(1)}mm#{marca}"
    end

    origen_x_mm = indice * SEPARACION_ENTRE_ESTRUCTURAS_MM
    origen = Geom::Point3d.new(origen_x_mm.mm, 0, 0)
    estructura = PlayIdea::ConstructorModulosNiveles.create_module(structure_params, origen)
    raise "create_module devolvió nil para el caso #{indice}" unless estructura

    tower_origin = PlayIdea::ConstructorModulosNiveles.offset_point(
      origen, tower_params[:offset_x_mm].mm, tower_params[:offset_y_mm].mm, 0
    )
    torre = PlayIdea::ConstructorModulosNiveles.create_triangle_tower(tower_params, tower_origin)
    raise "create_triangle_tower devolvió nil para el caso #{indice}" unless torre

    grupos_para_zoom << estructura << torre
  end

  model.active_view.zoom(grupos_para_zoom)
  model.selection.clear
  grupos_para_zoom.each { |g| model.selection.add(g) }
  puts ''
  puts "✅ #{casos.length} estructuras con alturas de módulo distintas, cada una con su torre -código '#{CODIGO_PRUEBA}-N'-."
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(8)
end
nil
