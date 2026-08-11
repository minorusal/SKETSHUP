# Pega este script completo en Ventana > Consola de Ruby de SketchUp,
# con el/los grupo(s) YA CONSTRUIDO(S) -estructura, torre, o ambos si son
# grupos separados- seleccionado(s).
#
# VERSION DEL SCRIPT: v8 -usa el catálogo hex estándar (STANDARD_COLOR_
# PALETTE en main.rb), no los nombres aproximados de CreadorTubos-
# (2026-08-06)
#
# QUÉ ES ESTO
# -----------
# Agrega el recubrimiento de espuma -segmentado en tramos de máximo 2.4m,
# con cinchos de plástico cada 15cm del mismo color que su tramo- a
# estructura(s) que YA EXISTEN, sea cual sea su tamaño, procesando TODOS
# los grupos seleccionados -por si la torre es un grupo separado junto a
# la estructura- y cualquier sub-grupo dentro de cada uno. Usa
# `pad_existing_tubes` en main.rb, que busca RECURSIVAMENTE cualquier
# tubo estructural ya existente y le pega recubrimiento a SU PROPIA
# geometría real -no recalculada desde modules_x/y/z-. Si ya había
# recubrimiento de una corrida anterior, lo borra primero para no
# duplicar.
#
# COLOR: usa PlayIdea::ConstructorModulos::STANDARD_COLOR_PALETTE -los 8
# hex reales del catálogo, los mismos que colorear_tubos_playidea y
# alberca_pelotas_playidea, confirmado por el usuario como el estándar-,
# NO los nombres aproximados de PlayIdea::CreadorTubos.apply_material.
# 2 modos, elige uno con MODO_COLOR más abajo:
#   :aleatorio            -> cada pieza, un color al azar del catálogo.
#   :vertical_horizontal  -> postes Z (verticales) de un color, filas/
#                             columnas/diagonales/patas (horizontales) de
#                             otro -edítalos en LABEL_VERTICAL/
#                             LABEL_HORIZONTAL más abajo, por nombre-.
#
# Usa `load` sobre el `main.rb` real -mismo patrón que probar_
# integrado.rb, que NO se toca-.

MAIN_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea/main.rb'
LOADER_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea.rb'

MODO_COLOR = :aleatorio # o :vertical_horizontal
LABEL_VERTICAL = 'Azul'
LABEL_HORIZONTAL = 'Naranja'

def borrar_recubrimiento_recursivo(entities)
  entities.grep(Sketchup::ComponentInstance)
    .select { |i| i.definition.name.to_s.start_with?('REC-') || i.definition.name.to_s.start_with?('CINCHO-') }
    .each(&:erase!)
  entities.grep(Sketchup::Group).each { |g| borrar_recubrimiento_recursivo(g.entities) }
end

def contar_recubrimiento_recursivo(entities, conteo = Hash.new(0))
  entities.grep(Sketchup::ComponentInstance)
    .select { |i| i.definition.name.to_s.start_with?('REC-') }
    .each do |p|
      largo = p.definition.get_attribute('playidea_modulo', 'length_mm')&.round(1)
      color = p.definition.get_attribute('playidea_modulo', 'color') || '(desconocido)'
      conteo[[largo, color]] += 1
    end
  entities.grep(Sketchup::Group).each { |g| contar_recubrimiento_recursivo(g.entities, conteo) }
  conteo
end

def contar_cinchos_recursivo(entities, conteo = Hash.new(0))
  entities.grep(Sketchup::ComponentInstance)
    .select { |i| i.definition.name.to_s.start_with?('CINCHO-') }
    .each { |p| conteo[p.definition.get_attribute('playidea_modulo', 'color') || '(desconocido)'] += 1 }
  entities.grep(Sketchup::Group).each { |g| contar_cinchos_recursivo(g.entities, conteo) }
  conteo
end

puts "📌 recubrir_estructura_seleccionada.rb v8 -catálogo hex estándar, modo color: #{MODO_COLOR}, #{__FILE__}-"

begin
  load LOADER_RB unless defined?(PlayIdea::ConstructorModulos::EXTENSION)
  load MAIN_RB
  puts "🔄 constructor_modulos_playidea recargado desde el archivo fuente."

  model = Sketchup.active_model
  grupos = model.selection.grep(Sketchup::Group)
  raise 'Selecciona el/los grupo(s) a recubrir antes de pegar esto -si la torre es un grupo separado, selecciona AMBOS-.' if grupos.empty?
  puts "Grupos seleccionados (#{grupos.length}): #{grupos.map(&:name).join(', ')}"

  paleta = PlayIdea::ConstructorModulos::STANDARD_COLOR_PALETTE
  hex_por_label = paleta.to_h { |c| [c[:label], c[:hex]] }
  puts "Catálogo estándar (#{paleta.length} colores): #{paleta.map { |c| "#{c[:label]}=##{c[:hex]}" }.join(', ')}"

  color_selector =
    case MODO_COLOR
    when :aleatorio
      ->(_direction) { paleta.sample[:hex] }
    when :vertical_horizontal
      hex_vertical = hex_por_label.fetch(LABEL_VERTICAL)
      hex_horizontal = hex_por_label.fetch(LABEL_HORIZONTAL)
      ->(direction) { direction.parallel?(Z_AXIS) ? hex_vertical : hex_horizontal }
    else
      raise "MODO_COLOR desconocido: #{MODO_COLOR.inspect} -usa :aleatorio o :vertical_horizontal-."
    end

  model.start_operation('Recubrir estructura(s) seleccionada(s)', true)
  grupos.each do |grupo|
    previas = contar_recubrimiento_recursivo(grupo.entities)
    if previas.any?
      puts "  '#{grupo.name}': #{previas.values.sum} piezas previas -se borran antes de recrear-."
      borrar_recubrimiento_recursivo(grupo.entities)
    end
    total_length_mm = PlayIdea::ConstructorModulos.pad_existing_tubes(grupo.entities, model, color_selector)
    conteo = contar_recubrimiento_recursivo(grupo.entities)
    cinchos = contar_cinchos_recursivo(grupo.entities)
    puts ''
    puts "'#{grupo.name}': #{conteo.values.sum} piezas de recubrimiento (largo total lógico: #{total_length_mm.round(1)}mm), #{cinchos.values.sum} cinchos"
    conteo.sort.each { |(largo, color), n| puts "  #{largo}mm ##{color} x #{n}" }
    cinchos.sort.each { |color, n| puts "  cincho ##{color} x #{n}" }
  end
  model.commit_operation

  model.selection.clear
  grupos.each { |g| model.selection.add(g) }
  puts ''
  puts "✅ Recubrimiento agregado a #{grupos.length} grupo(s) -incluyendo sus sub-grupos-, modo color: #{MODO_COLOR}."
rescue StandardError => e
  model.abort_operation rescue nil
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(8)
end
nil
