# Pega este script completo en Ventana > Consola de Ruby de SketchUp,
# con la estructura (MOD-2X2X2, con sus atributos playidea_modulo) Y la
# torre seleccionadas -misma selección de siempre-.
#
# VERSION DEL SCRIPT: v1 (2026-08-06)
#
# QUÉ ES ESTO
# -----------
# NO mueve ni duplica nada. En vez de comparar cada solera contra "la
# pieza más cercana" -que resultó no ser un ancla confiable, cada
# conector trae su propia rotación local según su posición en la
# cuadrícula-, esto calcula la posición TEÓRICA de cada esquina de cama
# -en coordenadas de MUNDO, alineadas a los ejes- usando la MISMA función
# `grid_level_z` que ya usa el plugin real -cargado con `load` desde
# main.rb, cero fórmula reinventada a mano-, leyendo modules_x/y/z y
# spacing_x/y/z_mm directo de los atributos que la propia estructura ya
# trae guardados. Así el offset de cada solera sale limpio porque el
# punto de comparación no tiene ninguna rotación rara.
#
# Por ahora solo compara contra las esquinas de la CUADRÍCULA -los
# cuadros-. Los triángulos de la torre se analizan aparte después.

MAIN_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea/main.rb'
LOADER_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea.rb'

def recorrer_soleras(entities, transform_acumulado, resultados)
  entities.each do |e|
    next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    transform_mundo = transform_acumulado * e.transformation
    nombre = e.is_a?(Sketchup::Group) ? e.name.to_s : e.definition.name.to_s
    nombre = e.name.to_s if nombre.empty?
    resultados << { nombre: nombre, transform: transform_mundo } if nombre.start_with?('SOLERA')
    hijos = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
    recorrer_soleras(hijos, transform_mundo, resultados)
  end
end

def mm(length)
  length.respond_to?(:to_mm) ? length.to_mm.round(2) : length.round(2)
end

begin
  load LOADER_RB unless defined?(PlayIdea::ConstructorModulos::EXTENSION)
  load MAIN_RB

  model = Sketchup.active_model
  sel = model.selection
  raise 'Selecciona la estructura -con atributos playidea_modulo- y la torre.' if sel.empty?

  estructura = sel.find do |g|
    (g.is_a?(Sketchup::Group) || g.is_a?(Sketchup::ComponentInstance)) &&
      g.attribute_dictionary('playidea_modulo') &&
      g.attribute_dictionary('playidea_modulo')['modules_x']
  end
  raise 'No encontré en la selección ningún grupo con atributos playidea_modulo (modules_x, spacing_x_mm, etc.). Selecciona la estructura -no solo la torre-.' unless estructura

  dict = estructura.attribute_dictionary('playidea_modulo')
  nx = dict['modules_x'].to_i
  ny = dict['modules_y'].to_i
  nz = dict['modules_z'].to_i
  sx = dict['spacing_x_mm'].to_f.mm
  sy = dict['spacing_y_mm'].to_f.mm
  sz = dict['spacing_z_mm'].to_f.mm
  base_t = estructura.transformation

  puts "Estructura '#{estructura.name}': modules=#{nx}x#{ny}x#{nz}, spacing=#{dict['spacing_x_mm']}/#{dict['spacing_y_mm']}/#{dict['spacing_z_mm']}mm"

  # Esquinas TEÓRICAS de la cuadrícula, en coordenadas de MUNDO -alineadas
  # a los ejes X/Y/Z globales, sin ninguna rotación de conector de por
  # medio-.
  esquinas = []
  (0..nx).each do |i|
    (0..ny).each do |j|
      (0..nz).each do |k|
        z = PlayIdea::ConstructorModulos.grid_level_z(k, nz, sz)
        punto_local = Geom::Point3d.new(i * sx, j * sy, z)
        esquinas << { i: i, j: j, k: k, punto: base_t * punto_local }
      end
    end
  end
  puts "#{esquinas.length} esquinas teóricas de cuadrícula calculadas -i:0..#{nx}, j:0..#{ny}, k:0..#{nz}-."
  puts ''

  soleras = []
  sel.each do |top|
    next unless top.is_a?(Sketchup::Group) || top.is_a?(Sketchup::ComponentInstance)
    base = top.transformation
    nombre = top.is_a?(Sketchup::Group) ? top.name.to_s : top.definition.name.to_s
    nombre = top.name.to_s if nombre.empty?
    soleras << { nombre: nombre, transform: base } if nombre.start_with?('SOLERA')
    hijos = top.is_a?(Sketchup::Group) ? top.entities : top.definition.entities
    recorrer_soleras(hijos, base, soleras)
  end

  puts "#{soleras.length} soleras encontradas en la selección."
  puts ''

  soleras.each_with_index do |s, idx|
    origen = s[:transform].origin
    cercana = esquinas.min_by { |e| e[:punto].distance(origen) }
    dist = cercana[:punto].distance(origen)
    offset = origen - cercana[:punto]
    xa = s[:transform].xaxis
    ya = s[:transform].yaxis
    puts "Solera ##{idx + 1}: esquina más cercana (i=#{cercana[:i]}, j=#{cercana[:j]}, k=#{cercana[:k]}) a #{mm(dist)}mm"
    puts "  offset MUNDO desde esa esquina = [#{mm(offset.x)}, #{mm(offset.y)}, #{mm(offset.z)}] mm"
    puts "  xaxis=[#{xa.x.round(4)}, #{xa.y.round(4)}, #{xa.z.round(4)}]  yaxis=[#{ya.x.round(4)}, #{ya.y.round(4)}, #{ya.z.round(4)}]"
    puts ''
  end

  puts '✅ Análisis contra esquinas de cuadrícula teóricas -nada se movió ni se duplicó-.'
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(10)
end
nil
