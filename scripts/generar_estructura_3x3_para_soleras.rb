# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
# No necesita nada seleccionado -crea su propia estructura desde cero,
# código 'PRUEBA-SOLERA-3X3'-.
#
# VERSION DEL SCRIPT: v1 (2026-08-06)
#
# QUÉ ES ESTO
# -----------
# Genera una estructura 3x3x1 -un solo nivel, para que no tengas que
# repetir la colocación en varias alturas- SIN torre y SIN soleras, para
# que coloques tú a mano las soleras de cuadro con tu propio criterio -2
# por cuadro, esquinas opuestas, la que tú elijas-. A diferencia del
# 2x2x2 anterior, una cuadrícula 3x3 ya tiene esquinas VERDADERAMENTE
# interiores -con cuadro en los 4 lados- en más de un punto -(1,1),(1,2),
# (2,1),(2,2)-, no solo una como antes, así que debería alcanzar para
# sacar la regla real de qué patrón le toca a cada tipo de esquina.
#
# Usa el mismo componente SOLERA-1IN -placa+3 tornillos- que ya
# validamos, así que puedes copiar/pegar/rotar esa misma pieza -no hace
# falta crear una nueva por esquina-.

MAIN_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea/main.rb'
LOADER_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea.rb'
CODE = 'PRUEBA-SOLERA-3X3'

begin
  load LOADER_RB unless defined?(PlayIdea::ConstructorModulos::EXTENSION)
  load MAIN_RB

  model = Sketchup.active_model
  model.start_operation('Generar estructura 3x3 para soleras', true)

  model.entities.grep(Sketchup::Group).select { |g| g.name.to_s.start_with?(CODE) }.each(&:erase!)

  data = {
    'modules_x' => 3, 'modules_y' => 3, 'modules_z' => 1,
    'spacing_x_m' => 1.1684, 'spacing_y_m' => 1.1684, 'spacing_z_m' => 1.1684,
    'color' => 'Azul', 'code' => CODE,
    'connectors' => true, 'padding' => false
  }
  params = PlayIdea::ConstructorModulos.validate_dialog_data(data)
  raise 'validate_dialog_data devolvió nil' unless params

  origin = Geom::Point3d.new(0, 0, 0)
  structure = PlayIdea::ConstructorModulos.create_module(params.merge(padding: false), origin)
  raise 'create_module devolvió nil' unless structure

  model.commit_operation
  model.selection.clear
  model.selection.add(structure)
  model.active_view.zoom(structure)

  puts "✅ Estructura '#{CODE}' generada -3x3x1, sin torre, sin soleras-."
  puts '   Corre scripts/crear_solera_playidea.rb para tener una pieza SOLERA-1IN-TEST'
  puts '   que copiar/pegar a mano en cada esquina que tú seleccciones -2 por cuadro,'
  puts '   opuestas, tu criterio-, y luego scripts/inspeccionar_soleras.rb +'
  puts '   scripts/analizar_soleras.rb -con esta estructura seleccionada- para medir.'
rescue StandardError => e
  model.abort_operation rescue nil
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(10)
end
nil
