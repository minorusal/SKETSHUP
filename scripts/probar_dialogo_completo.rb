# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# VERSION DEL SCRIPT: v1 (2026-08-06)
#
# QUÉ ES ESTO
# -----------
# Simula EXACTO el flujo real del diálogo -validate_dialog_data +
# ModulePlacementTool#onLButtonDown, incluyendo torre y recubrimiento
# con cinchos- pero sin abrir ningún diálogo ni HtmlDialog, para
# encontrar errores de lógica ANTES de instalar el .rbz y reiniciar
# SketchUp -ciclo caro-. Usa `load` sobre el `main.rb` real -mismo
# patrón que probar_integrado.rb, que NO se toca-.

MAIN_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea/main.rb'
LOADER_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea.rb'
CODIGO_PRUEBA = 'PRUEBA-DIALOGO-COMPLETO'

begin
  load LOADER_RB unless defined?(PlayIdea::ConstructorModulos::EXTENSION)
  load MAIN_RB
  puts "🔄 constructor_modulos_playidea recargado desde el archivo fuente."

  model = Sketchup.active_model
  model.active_entities.grep(Sketchup::Group)
    .select { |g| g.name.to_s.start_with?(CODIGO_PRUEBA) }
    .each(&:erase!)

  # Mismos datos que mandaría selector.html con: 2x2x3, conectores,
  # torre en (0,0) esquina SO, recubrimiento en modo vertical/horizontal.
  data = {
    'modules_x' => 2, 'modules_y' => 2, 'modules_z' => 3,
    'spacing_x_m' => 1.1684, 'spacing_y_m' => 1.1684, 'spacing_z_m' => 1.1684,
    'color' => 'Azul', 'code' => CODIGO_PRUEBA,
    'connectors' => true,
    'padding' => true,
    'padding_color_mode' => 'vertical_horizontal',
    'padding_color_vertical' => 'Azul',
    'padding_color_horizontal' => 'Naranja',
    'tower' => true,
    'tower_cell_i' => 0, 'tower_cell_j' => 0, 'tower_corner' => 'sw'
  }

  params = PlayIdea::ConstructorModulos.validate_dialog_data(data)
  raise 'validate_dialog_data devolvió nil' unless params
  puts "Params válidos. padding_color_mode=#{params[:padding_color_mode]}, tower=#{!!params[:tower]}"

  # Costos de prueba -normalmente los captura capture_padding_costs, un
  # diálogo nativo que no se puede simular headless-.
  params[:padding_costs] = {
    'raw_tube' => 100.0, 'perforation_labor' => 10.0, 'electricity' => 5.0,
    'splice_labor' => 10.0, 'wrap_material' => 20.0, 'adhesive' => 10.0,
    'apply_labor' => 10.0, 'weld_labor' => 10.0
  }

  # A partir de aquí, EXACTO lo mismo que ModulePlacementTool#onLButtonDown.
  origen = Geom::Point3d.new(0, 0, 0)
  structure = PlayIdea::ConstructorModulos.create_module(params.merge(padding: false), origen)
  raise 'create_module devolvió nil' unless structure

  tower_group = nil
  if params[:tower]
    tower = params[:tower]
    tower_origin = PlayIdea::ConstructorModulos.offset_point(
      origen, tower[:offset_x_mm].mm, tower[:offset_y_mm].mm, 0
    )
    tower_group = PlayIdea::ConstructorModulos.create_triangle_tower(tower, tower_origin)
    raise 'create_triangle_tower devolvió nil' unless tower_group
  end

  if params[:padding]
    color_selector = PlayIdea::ConstructorModulos.padding_color_selector(params)
    model.start_operation('Recubrir con espuma', true)
    total_length_mm = PlayIdea::ConstructorModulos.pad_existing_tubes(structure.entities, model, color_selector)
    total_length_mm += PlayIdea::ConstructorModulos.pad_existing_tubes(tower_group.entities, model, color_selector) if tower_group
    PlayIdea::ConstructorModulos.write_padding_summary(structure, params, total_length_mm)
    model.commit_operation
  end

  # Verificación: cuenta piezas de recubrimiento/cinchos en AMBOS grupos.
  def contar(entities, prefijo)
    n = entities.grep(Sketchup::ComponentInstance).count { |i| i.definition.name.to_s.start_with?(prefijo) }
    entities.grep(Sketchup::Group).each { |g| n += contar(g.entities, prefijo) }
    n
  end
  puts ''
  puts "Estructura: #{contar(structure.entities, 'REC-')} recubrimiento, #{contar(structure.entities, 'CINCHO-')} cinchos"
  puts "Torre: #{contar(tower_group.entities, 'REC-')} recubrimiento, #{contar(tower_group.entities, 'CINCHO-')} cinchos" if tower_group
  puts "Atributo padding_investment_cost_mxn en estructura: #{structure.get_attribute('playidea_modulo', 'padding_investment_cost_mxn')}"

  model.active_view.zoom([structure, tower_group].compact)
  model.selection.clear
  model.selection.add(structure)
  model.selection.add(tower_group) if tower_group
  puts "✅ Flujo completo del diálogo simulado sin errores -código '#{CODIGO_PRUEBA}'-."
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(10)
end
nil
