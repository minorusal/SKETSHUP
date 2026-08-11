# Pega este script completo en Ventana > Consola de Ruby de SketchUp,
# con la estructura (y la torre, si es un grupo aparte) seleccionadas.
#
# VERSION DEL SCRIPT: v1 (2026-08-06)
#
# QUÉ ES ESTO
# -----------
# NO mueve ni duplica nada. Solo lee y reporta los atributos
# 'playidea_modulo' -módulos, separación, offset y esquina de la torre,
# etc.- que constructor_modulos_playidea ya guarda en cada grupo al
# crearlo. Con esos parámetros exactos se puede calcular la posición
# TEÓRICA de cada esquina de cama sin depender de comparar contra la
# pieza más cercana -que resultó no ser un ancla confiable, cada
# conector trae su propia rotación local según su posición en la
# cuadrícula-.

begin
  model = Sketchup.active_model
  sel = model.selection
  raise 'Selecciona la estructura -y la torre, si es un grupo aparte- antes de correr esto.' if sel.empty?

  sel.each do |g|
    next unless g.is_a?(Sketchup::Group) || g.is_a?(Sketchup::ComponentInstance)
    puts "== #{g.name} =="
    dict = g.attribute_dictionary('playidea_modulo')
    if dict
      dict.each_pair { |k, v| puts "  #{k} = #{v.inspect}" }
    else
      puts '  -sin atributos playidea_modulo-'
    end
    t = g.transformation
    puts "  transform origen MUNDO = [#{t.origin.x.to_mm.round(2)}, #{t.origin.y.to_mm.round(2)}, #{t.origin.z.to_mm.round(2)}] mm"
    puts "  xaxis=[#{t.xaxis.x.round(4)}, #{t.xaxis.y.round(4)}, #{t.xaxis.z.round(4)}]  yaxis=[#{t.yaxis.x.round(4)}, #{t.yaxis.y.round(4)}, #{t.yaxis.z.round(4)}]"
    puts ''
  end
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(8)
end
nil
