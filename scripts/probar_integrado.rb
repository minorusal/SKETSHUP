# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# VERSION DEL SCRIPT: v1 (2026-08-06)
#
# QUÉ ES ESTO
# -----------
# Reconstruye estructura + torre -el flujo integrado real, el mismo que
# usa el checkbox "Agregar torre" del diálogo- en un solo paso, RECARGANDO
# el código del plugin en caliente cada vez -sin reinstalar el .rbz, sin
# cerrar/abrir SketchUp-. Edita constructor_modulos_playidea/main.rb,
# vuelve a pegar ESTE script completo, y en segundos ves el resultado.
#
# CÓMO FUNCIONA
# -------------
# `load` -a diferencia de `require`- SÍ vuelve a ejecutar el archivo
# aunque ya esté cargado, redefiniendo los métodos del módulo en el
# mismo lugar -mismo truco que usa auto_etiquetado_playidea para
# autoeditarse-. Como apunta directo al archivo FUENTE -no al instalado
# en el Plugins de SketchUp-, cualquier cambio que yo haga ahí se ve
# reflejado de inmediato, sin empacar .rbz ni tocar Extension Manager.
#
# Requiere: conectores_playidea y creador_tubos_playidea instalados
# -esos SÍ están al día, no hace falta recargarlos-.

MAIN_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea/main.rb'
LOADER_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea.rb'
CODIGO_PRUEBA = 'PRUEBA-INTEGRADA'

begin
  # main.rb usa la constante EXTENSION -para el mensaje de versión y el
  # nombre del submenú-, que normalmente define el archivo cargador. Si
  # no hay ninguna versión instalada en esta sesión de SketchUp -.rbz no
  # instalado, o SketchUp recién abierto sin instalarlo todavía-, esa
  # constante no existe y `load MAIN_RB` truena. Se carga el cargador
  # primero, pero SOLO si hace falta -para no volver a registrar la
  # extensión de más en cada corrida-.
  load LOADER_RB unless defined?(PlayIdea::ConstructorModulos::EXTENSION)
  load MAIN_RB
  puts "🔄 constructor_modulos_playidea recargado desde el archivo fuente."

  model = Sketchup.active_model

  # Borra el resultado de la prueba anterior -si existe- para no ir
  # acumulando estructuras encimadas cada vez que se corre esto.
  model.active_entities.grep(Sketchup::Group)
    .select { |g| g.name.to_s.start_with?(CODIGO_PRUEBA) }
    .each(&:erase!)

  # Estructura chica -2x2x3 módulos- con conectores. modules_z sube a 3
  # -antes 1- para probar que la torre escala con el número de módulos de
  # alto -más escalones, alternando esquina, separación 50-60cm-, en vez
  # de quedarse fija en 2 escalones como el caso de 1 módulo ya validado.
  structure_params = {
    modules_x: 2,
    modules_y: 2,
    modules_z: 3,
    spacing_x_mm: 1168.4,
    spacing_y_mm: 1168.4,
    spacing_z_mm: 1168.4,
    color: 'Azul',
    code: CODIGO_PRUEBA,
    connectors: true,
    padding: false
  }

  # Mismos datos que mandaría el diálogo con el checkbox "Agregar torre"
  # marcado -columna (0,0), ángulo recto en SO-. Antes decía SE, pero la
  # referencia real que confirmó el usuario -reporte_grupo_20260806_
  # 110850.txt- tiene el CON-21 pegado a la esquina física (45,45), que
  # el código etiqueta como :sw -ver triangle_cell_corners-. Con 'se' se
  # estaba comparando el triángulo en la esquina opuesta de la celda:
  # no es un error de geometría, es comparar dos esquinas distintas.
  tower_data = { 'tower_cell_i' => 0, 'tower_cell_j' => 0, 'tower_corner' => 'sw' }
  tower_params = PlayIdea::ConstructorModulos.tower_params_from_dialog(tower_data, structure_params)
  raise 'tower_params_from_dialog devolvió nil -revisa modules_z/spacing_z, necesita al menos 50cm libres.' unless tower_params

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
  puts "✅ Estructura + torre reconstruidas desde cero -código '#{CODIGO_PRUEBA}'-."
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(8)
end
nil
