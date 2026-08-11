# Pega este script en Ventana > Consola de Ruby de SketchUp, DESPUÉS de
# haber corrido probar_medio_modulo.rb (no borra nada, solo lee).
#
# VERSION DEL SCRIPT: v1 (2026-08-07)
#
# QUÉ ES ESTO
# -----------
# El usuario reporta que la estructura "normal" -3x2x2, sin fracciones-
# también salió mal, no solo la de cuarto. Para no adivinar dónde está
# el problema, este script lee los tubos X YA COLOCADOS -su largo exacto
# viene codificado en el nombre de la definición, 'TUB-MOD-X-####.#'-
# y los agrupa, en vez de depender de medir a mano en el viewport.
#
# Valor esperado si todo está bien -RECEIVER_RADIUS_MM=24.15mm,
# confirmado en comentarios de main.rb-:
#   columna normal (1168.4mm):  1168.4 - 2*24.15 = 1120.1mm
#   columna media  (584.2mm):    584.2 - 2*24.15 =  535.9mm
#   columna cuarto (292.1mm):    292.1 - 2*24.15 =  243.8mm

CODIGOS = {
  'PRUEBA-MOD-NORMAL' => 'Normal (3x2x2, sin fracciones)',
  'PRUEBA-MOD-MEDIO' => 'Medio (2 normales + 1 media en X)',
  'PRUEBA-MOD-CUARTO' => 'Cuarto (1 normal + 1 cuarto en X)'
}.freeze

def largos_tubo_x(entities, encontrados = Hash.new(0))
  entities.grep(Sketchup::ComponentInstance).each do |instance|
    name = instance.definition.name.to_s
    next unless name.start_with?('TUB-MOD-X-')
    largo = name.sub('TUB-MOD-X-', '').to_f
    encontrados[largo] += 1
  end
  entities.grep(Sketchup::Group).each { |g| largos_tubo_x(g.entities, encontrados) }
  encontrados
end

model = Sketchup.active_model
CODIGOS.each do |codigo, etiqueta|
  grupo = model.active_entities.grep(Sketchup::Group).find { |g| g.name.to_s.start_with?(codigo) }
  puts ''
  if grupo.nil?
    puts "⚠️  #{etiqueta}: no se encontró el grupo '#{codigo}' -¿corriste probar_medio_modulo.rb primero?-"
    next
  end
  largos = largos_tubo_x(grupo.entities)
  puts "#{etiqueta}:"
  largos.sort.each do |largo, cantidad|
    puts "  #{cantidad} tubos X de #{largo}mm"
  end
end
nil
