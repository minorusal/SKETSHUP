# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# VERSION DEL SCRIPT: v1 (2026-08-05)
#
# QUÉ ES ESTO
# -----------
# Ya se verificó por NÚMEROS que las tablas de rotación del plugin
# -TRIANGLE_CONNECTOR_AXES, _AXES_CAPPED, _21_AXES, _10_AXES- coinciden
# EXACTO con tu torre hecha a mano en la esquina SE (diseños 1 y 2).
# Eso confirma que las tablas están bien, pero no prueba que el plugin
# REAL -corriendo create_triangle_tower de principio a fin- arme algo sin
# huecos ni tubos mal cortados -esa parte depende de otras cuentas
# -RECEIVER_RADIUS_MM, largo de tubo, etc.- que las tablas de rotación no
# cubren-.
#
# Este script llama DIRECTO al plugin -sin abrir el diálogo, sin necesitar
# clics- para generar una torre de 3 escalones con el ángulo recto en SE,
# igual que tu diseño 1/2, en un punto limpio del modelo. Así puedes
# compararla lado a lado contra tu torre hecha a mano.
#
# Requiere tener instalado constructor_modulos_playidea -y sus
# dependencias creador_tubos_playidea / conectores_playidea-.

# OJO: create_triangle_tower YA maneja su propio start_operation/
# commit_operation/abort_operation por dentro -no hay que envolverlo en
# otro aparte, o quedarían operaciones anidadas innecesarias-.
model = Sketchup.active_model

begin
  params = {
    cell_x_mm: 1168.4,
    cell_y_mm: 1168.4,
    right_angle_corner: :se,
    steps: 3,
    start_height_mm: 500.0, # nunca 0 -nivel 0 es del conector 61-; 500mm es intermedio, no coincide con ningún nivel real
    step_spacing_mm: 600.0,
    color: 'Azul',
    code: 'PRUEBA-TORRE-SE'
  }

  # Origen: esquina SO de la celda, en un punto del modelo lejos de todo lo
  # demás para que sea fácil de encontrar -ajusta estas coordenadas si ya
  # tienes algo ahí-.
  origen = Geom::Point3d.new(0, -60_000.mm, 0)

  torre = PlayIdea::ConstructorModulos.create_triangle_tower(params, origen)
  raise 'create_triangle_tower devolvió nil -revisa el mensaje de error que haya mostrado un UI.messagebox.' unless torre

  model.active_view.zoom([torre])
  model.selection.clear
  model.selection.add(torre)
  puts "✅ Torre de prueba (SE, 3 escalones) creada en X=0, Y=-60000mm, Z=0."

  if defined?(CopiarGrupoReferencia)
    CopiarGrupoReferencia.reportar(torre)
  else
    puts "ℹ️  Pega también copiar_grupo_referencia.rb si quieres el reporte detallado -CopiarGrupoReferencia.reportar(torre)-."
  end
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(8)
end
nil
