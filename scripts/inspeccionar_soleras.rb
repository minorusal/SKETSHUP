# Pega este script completo en Ventana > Consola de Ruby de SketchUp,
# con la estructura completa Y la torre -con las soleras ya puestas a
# mano- seleccionadas (ambas a la vez, tal cual estén en el modelo).
#
# VERSION DEL SCRIPT: v2 -compara solo contra CONECTORES, no tubos, porque
# el ancla física real de una esquina es el conector- (2026-08-06)
#
# QUÉ ES ESTO
# -----------
# A diferencia de copiar_grupo_referencia.rb -que DUPLICA cada elemento
# top-level seleccionado con un offset propio, pensado para comparar dos
# copias lado a lado-, este NO mueve ni duplica NADA. Solo recorre
# recursivamente lo seleccionado, encuentra cada instancia de
# SOLERA-1IN-TEST, calcula su transform en coordenadas de MUNDO
# -acumulando la cadena de transforms padre-a-hijo, no el transform local
# al padre inmediato que da copiar_grupo_referencia- y reporta el
# tubo/conector estructural (TUB-/CON-) más cercano con el vector de
# offset real hacia él. Con eso se puede derivar la regla de colocación
# -en qué esquina, a qué distancia, con qué rotación respecto al tubo-
# sin adivinar.

def recorrer(entities, transform_acumulado, resultados)
  entities.each do |e|
    next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    transform_mundo = transform_acumulado * e.transformation
    nombre = e.is_a?(Sketchup::Group) ? e.name.to_s : e.definition.name.to_s
    nombre = e.name.to_s if nombre.empty?
    resultados << { entidad: e, nombre: nombre, transform: transform_mundo }
    hijos = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
    recorrer(hijos, transform_mundo, resultados)
  end
end

def mm(length)
  length.respond_to?(:to_mm) ? length.to_mm.round(2) : length.round(2)
end

begin
  model = Sketchup.active_model
  sel = model.selection
  raise 'Selecciona la estructura y la torre -con las soleras ya puestas- antes de correr esto.' if sel.empty?

  resultados = []
  sel.each do |top|
    next unless top.is_a?(Sketchup::Group) || top.is_a?(Sketchup::ComponentInstance)
    base_t = top.transformation
    nombre = top.is_a?(Sketchup::Group) ? top.name.to_s : top.definition.name.to_s
    nombre = top.name.to_s if nombre.empty?
    resultados << { entidad: top, nombre: nombre, transform: base_t }
    hijos = top.is_a?(Sketchup::Group) ? top.entities : top.definition.entities
    recorrer(hijos, base_t, resultados)
  end

  soleras = resultados.select { |r| r[:nombre].to_s.start_with?('SOLERA') }
  # Solo CONECTORES -no tubos-: el ancla física real de una esquina es el
  # conector (CON-MOD-XX), un tubo cercano puede ganarle en distancia sin
  # ser el punto de referencia real.
  referencias = resultados.select { |r| r[:nombre].to_s.start_with?('CON-') }

  puts "Encontradas #{soleras.length} soleras y #{referencias.length} conectores en la selección."
  puts ''

  soleras.each_with_index do |s, i|
    origen = s[:transform].origin
    xa = s[:transform].xaxis
    ya = s[:transform].yaxis
    za = s[:transform].zaxis
    puts "Solera ##{i + 1} -#{s[:entidad].name}-:"
    puts "  origen MUNDO = [#{mm(origen.x)}, #{mm(origen.y)}, #{mm(origen.z)}] mm"
    puts "  xaxis=[#{xa.x.round(4)}, #{xa.y.round(4)}, #{xa.z.round(4)}]  " \
      "yaxis=[#{ya.x.round(4)}, #{ya.y.round(4)}, #{ya.z.round(4)}]  " \
      "zaxis=[#{za.x.round(4)}, #{za.y.round(4)}, #{za.z.round(4)}]"

    cercano = referencias.min_by { |r| r[:transform].origin.distance(origen) }
    if cercano
      dist = cercano[:transform].origin.distance(origen)
      offset = origen - cercano[:transform].origin
      puts "  pieza más cercana: #{cercano[:nombre]} a #{mm(dist)}mm, " \
        "offset MUNDO=[#{mm(offset.x)}, #{mm(offset.y)}, #{mm(offset.z)}] mm"

      # Offset y rotación de la solera vistos DESDE el sistema de
      # coordenadas LOCAL de la pieza de referencia -no en mundo-. Esto es
      # lo que debería repetirse limpio entre esquinas equivalentes,
      # porque ya no depende de hacia dónde apunta esa pieza en el mundo.
      relativo = cercano[:transform].inverse * s[:transform]
      ro = relativo.origin
      rxa = relativo.xaxis
      rya = relativo.yaxis
      puts "  offset LOCAL a esa pieza=[#{mm(ro.x)}, #{mm(ro.y)}, #{mm(ro.z)}] mm, " \
        "rotación LOCAL xaxis=[#{rxa.x.round(4)}, #{rxa.y.round(4)}, #{rxa.z.round(4)}] " \
        "yaxis=[#{rya.x.round(4)}, #{rya.y.round(4)}, #{rya.z.round(4)}]"
    else
      puts '  -no se encontró ningún TUB-/CON- en la selección para comparar-'
    end
    puts ''
  end

  puts "✅ #{soleras.length} soleras inspeccionadas -nada se movió ni se duplicó-."
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(8)
end
nil
