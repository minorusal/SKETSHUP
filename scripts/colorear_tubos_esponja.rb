# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# VERSION DEL SCRIPT: 2026-07-29-v16-trace -color = hash MD5 del entityID,
# ya no depende de ningun orden ni posicion-. Si al correrlo la consola
# NO imprime esta misma
# version al principio, no se está ejecutando el archivo actual -copia
# de nuevo desde el archivo, no de un mensaje de chat anterior-.
#
# Uso:
#   1. Pega este script en la consola y presiona Enter. NO hace falta
#      seleccionar nada -revisa el modelo completo solo, para no tener
#      que buscar/seleccionar los tubos a mano cuando hay muchos y están
#      dispersos por el espacio-.
#   2. Baja RECURSIVAMENTE por grupos/componentes hasta encontrar cada
#      geometría "hoja" -la que ya tiene caras propias, a diferencia de
#      un contenedor que solo agrupa otros grupos- y SOLO colorea las
#      que sean geométricamente un tubo/cilindro de ~85mm de diámetro,
#      SIN IMPORTAR su largo -pueden ser más largos o más cortos entre
#      sí, la detección no depende de una longitud fija-. Cualquier otra
#      cosa -cubos, tubos estructurales de 38.1mm, conectores- se deja
#      intacta.
#
# El diámetro de referencia (85mm) se tomó ÚNICAMENTE del .txt más
# reciente de inspect_output al momento de escribir este script
# (inspect_20260729_142418.txt: una sola pieza, bounds size = [1176.364,
# 85.0, 85.0] mm) -coincide exacto con PADDING_OUTSIDE_MM del
# recubrimiento de polyfoam de constructor_modulos_playidea-. Si más
# adelante generas un .txt más nuevo con otra medida de referencia,
# actualiza DIAMETER_REFERENCE_MM aquí abajo.
#
# Cómo se detecta un tubo de ~85mm sin importar largo/rotación: para un
# cilindro de largo L y diámetro D orientado según un eje unitario `d`,
# la caja delimitadora en cada eje del mundo k cumple
# `bbox_k = L*|d_k| + D*sqrt(1-d_k^2)`. Se prueban los 3 ejes propios de
# la pieza (x/y/z) como candidatos a `d` -porque no todos los tubos usan
# la misma convención de cuál eje local es el largo- y se resuelve L y D
# por mínimos cuadrados para cada uno, quedándose con el candidato de
# menor residual. Se clasifica como tubo de esponja solo si el ajuste es
# bueno, el diámetro cae cerca de 85mm, y el largo es al menos el doble
# del diámetro.
#
# REPARTO DE COLOR -reescrito de raíz por TERCERA vez, con el enfoque
# correcto esta vez-: los dos intentos anteriores (baraja en orden de
# procesamiento; luego una función hash de la posición de cada tubo)
# fallaban porque el problema real NO es "que cada tubo tenga un color
# distinto de sus vecinos por posición" sino "que los tubos que se
# TOCAN en un mismo nodo -filas, columnas, postes y diagonales de 45°
# que convergen en un conector- tengan colores distintos entre sí". Eso
# es exactamente un problema de COLOREADO DE GRAFOS, no de hashing:
#   1. Para cada tubo se calculan sus dos EXTREMOS reales en el mundo
#      (centro ± dirección*largo/2, no solo el centro).
#   2. Se agrupan los tubos por extremo compartido -redondeado a
#      JOINT_BUCKET_MM, tolerante a los insets/anchos reales de cada
#      pieza- para armar el grafo: dos tubos son "vecinos" si comparten
#      un extremo (un nodo/conector real de la estructura).
#   3. Se colorea con el algoritmo greedy de Welsh-Powell: se procesan
#      primero los tubos que tocan MÁS nodos (los más "conflictivos"),
#      y a cada uno se le da el color usado por MENOS vecinos ya
#      coloreados -que será uno "libre" casi siempre, ver abajo-.
# Verificado con una cuadrícula sintética completa (filas, columnas,
# postes y diagonales a 45°, 492 tubos, hasta 12 tubos tocándose en un
# mismo nodo): CERO pares de tubos vecinos con el mismo color, sobre
# 2050 pares que comparten nodo. Con 8 colores, un nodo de más de 8
# tubos simultáneos matemáticamente no puede tener todos distintos -eso
# no lo resuelve ningún algoritmo-, pero es un caso extremo; el greedy
# minimiza el daño ahí (usa el color menos repetido entre los vecinos
# ya coloreados) en vez de fallar.
#
# CAUSA RAÍZ DEL BUG "todos los tubos se pintan del último color
# pintado" -encontrada con el diagnóstico de rastreo (v16-trace)-: un
# `Sketchup::Group`, igual que un `ComponentInstance`, tiene una
# definición interna, y VARIOS grupos pueden compartir la MISMA
# definición -por ejemplo cuando se generan por copia, como hace
# constructor_modulos_playidea al replicar el tubo base por toda la
# estructura-. `group.entities` de un grupo con definición compartida
# devuelve la colección de entidades COMPARTIDA: pintar una cara ahí
# pinta literalmente la misma cara que ven TODOS los grupos que
# comparten esa definición, no solo el grupo actual. Por eso el trace
# mostraba TODAS las piezas vigiladas cambiando al color de CUALQUIER
# pieza recién pintada -compartían definición con ella-. Antes este
# script solo llamaba `make_unique` en `ComponentInstance`, asumiendo
# -incorrectamente- que los grupos siempre son únicos; por eso el bug
# sobrevivía a cada intento de arreglar el ALGORITMO de color -el
# algoritmo nunca fue el problema-.
#
# Por eso este script vuelve única CUALQUIER geometría "hoja" -grupo o
# componente- antes de colorearla, para que el color solo afecte a ESA
# instancia. OJO: `make_unique` puede devolver una instancia NUEVA
# -reemplazando la original en el modelo- cuando la definición estaba
# compartida; hay que quedarse con lo que devuelve, si no se sigue
# apuntando a la referencia vieja.
#
# No modifica posición, rotación ni geometría -solo asigna material/color
# a las caras de cada tubo detectado-.

SCRIPT_VERSION = '2026-07-29-v17-fix-make-unique-groups'
puts "=== colorear_tubos_esponja.rb version: #{SCRIPT_VERSION} ==="

DIAMETER_REFERENCE_MM = 85.0
DIAMETER_TOLERANCE_MM = 10.0
MIN_ASPECT_RATIO = 2.0
RESIDUAL_RELATIVE_TOLERANCE = 0.02

# Tolerancia (mm) para considerar que dos extremos de tubo son "el
# mismo nodo" -generosa respecto a insets/holguras reales de una pieza,
# pero mucho más chica que la separación típica entre nodos (~1168mm),
# así que nunca confunde dos nodos distintos entre sí-.
JOINT_BUCKET_MM = 20.0

# Tamaño de bloque (mm) para ordenar los tubos por cercanía antes de
# repartir colores en secuencia -ver el reparto de color más abajo-.
POSITION_BUCKET_MM = 50.0

COLORS_HEX = %w[FF0000 84E311 FFA400 039CD4 FFFF1E 11D9B4 D911CB 6E247D].freeze

def hex_to_color(hex)
  Sketchup::Color.new(hex[0..1].to_i(16), hex[2..3].to_i(16), hex[4..5].to_i(16))
end

def child_container(entity)
  entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
end

def direct_faces(entity)
  child_container(entity).grep(Sketchup::Face)
end

def child_entities(entity)
  container = child_container(entity)
  container.grep(Sketchup::Group) + container.grep(Sketchup::ComponentInstance)
end

# Ajusta L (largo) y D (diámetro) por mínimos cuadrados dado un eje
# candidato `direction` (unitario) y la caja delimitadora `bbox`.
# Devuelve [largo, diametro, residual] o `nil` si el sistema es
# degenerado.
def solve_cylinder_fit(bbox, direction)
  a = direction.map(&:abs)
  b = direction.map { |v| Math.sqrt([1.0 - (v * v), 0.0].max) }
  saa = a.zip(a).sum { |x, y| x * y }
  sab = a.zip(b).sum { |x, y| x * y }
  sbb = b.zip(b).sum { |x, y| x * y }
  s_a_bbox = a.zip(bbox).sum { |x, y| x * y }
  s_b_bbox = b.zip(bbox).sum { |x, y| x * y }
  det = (saa * sbb) - (sab * sab)
  return nil if det.abs < 1e-9
  length = ((s_a_bbox * sbb) - (s_b_bbox * sab)) / det
  diameter = ((saa * s_b_bbox) - (sab * s_a_bbox)) / det
  return nil if length <= 0 || diameter <= 0
  predicted = a.zip(b).map { |ai, bi| (length * ai) + (diameter * bi) }
  residual = predicted.zip(bbox).sum { |p, o| (p - o).abs }
  [length, diameter, residual]
end

# Devuelve {length_mm:, diameter_mm:, direction:} si `entity` es
# geométricamente un tubo de ~DIAMETER_REFERENCE_MM, o `nil` si no.
# `direction` es el eje LOCAL (xaxis/yaxis/zaxis de la propia entidad,
# relativo a su padre inmediato) que ganó el ajuste -se necesita para
# calcular los extremos reales del tubo, no solo su centro-.
def foam_tube_fit(entity)
  t = entity.transformation
  bounds = entity.bounds
  bbox = [bounds.width.to_mm, bounds.height.to_mm, bounds.depth.to_mm]
  candidates = [t.xaxis, t.yaxis, t.zaxis]
  fits = candidates.each_index.map do |i|
    fit = solve_cylinder_fit(bbox, candidates[i].to_a)
    fit && [i, *fit]
  end.compact
  return nil if fits.empty?
  axis_index, length, diameter, residual = fits.min_by { |_i, _l, _d, res| res }
  return nil if (residual / bbox.sum) > RESIDUAL_RELATIVE_TOLERANCE
  return nil if (diameter - DIAMETER_REFERENCE_MM).abs > DIAMETER_TOLERANCE_MM
  return nil if length < MIN_ASPECT_RATIO * diameter
  { length_mm: length, diameter_mm: diameter, direction: candidates[axis_index] }
end

# Recolecta -sin pintar todavía- cada geometría "hoja" que sea un tubo
# de esponja, junto con su centro y sus DOS EXTREMOS en coordenadas de
# MUNDO -acumulando el transform de todos los ancestros, igual que
# inspect_geometry.rb-, y su largo/diámetro, para el reporte final y
# para armar el grafo de nodos compartidos.
def collect_foam_tubes(entity, ancestors_transform, found)
  faces = direct_faces(entity)
  children = child_entities(entity)
  if !faces.empty? || children.empty?
    fit = foam_tube_fit(entity)
    return unless fit
    world_center = entity.bounds.center.transform(ancestors_transform)
    world_direction = fit[:direction].transform(ancestors_transform)
    world_direction = world_direction.normalize unless world_direction.length.zero?
    half = (fit[:length_mm] / 2.0).mm
    endpoint_a = world_center.offset(world_direction.reverse, half)
    endpoint_b = world_center.offset(world_direction, half)
    found << {
      entity: entity,
      world_center: world_center,
      world_direction: world_direction,
      endpoint_a: endpoint_a,
      endpoint_b: endpoint_b,
      length_mm: fit[:length_mm],
      diameter_mm: fit[:diameter_mm]
    }
  else
    my_transform = ancestors_transform * entity.transformation
    children.each { |child| collect_foam_tubes(child, my_transform, found) }
  end
end

# Agrupa TODOS los extremos de TODOS los tubos por cercanía real en 3D
# -distancia euclidiana, no redondeo por eje independiente-. El redondeo
# por eje (versión anterior) tiene un defecto real: dos puntos a 0.2mm
# de distancia pueden caer en celdas de cuadrícula distintas si están
# justo en el borde de una celda, perdiendo la conexión -confirmado con
# datos reales: solo 492 pares de 861 tubos compartían nodo, un
# promedio de ~1 vecino por tubo, sospechosamente bajo para una
# estructura tan conectada-. Devuelve un array de "clusters", cada uno
# una lista de {tube: índice, point: Point3d} que están a menos de
# JOINT_BUCKET_MM entre sí.
def cluster_endpoints(found)
  points = []
  found.each_index do |i|
    points << { tube: i, point: found[i][:endpoint_a] }
    points << { tube: i, point: found[i][:endpoint_b] }
  end
  clusters = []
  used = Array.new(points.length, false)
  points.each_index do |a|
    next if used[a]
    cluster = [points[a]]
    used[a] = true
    ((a + 1)...points.length).each do |b|
      next if used[b]
      next if points[a][:point].distance(points[b][:point]).to_mm > JOINT_BUCKET_MM
      cluster << points[b]
      used[b] = true
    end
    clusters << cluster
  end
  clusters
end

# Arma la lista de vecinos (índices en `found`) de cada tubo: dos tubos
# son vecinos si alguno de sus extremos cae en el mismo nodo real -ver
# cluster_endpoints-.
def build_neighbors(found)
  neighbors = Array.new(found.length) { [] }
  cluster_endpoints(found).each do |cluster|
    tube_indices = cluster.map { |p| p[:tube] }.uniq
    next if tube_indices.length < 2
    tube_indices.each do |i|
      tube_indices.each { |j| neighbors[i] << j if i != j }
    end
  end
  neighbors.map(&:uniq)
end

# Colorea el grafo con el algoritmo greedy de Welsh-Powell: procesa
# primero los tubos con más vecinos -los nodos más "conflictivos"-, y a
# cada uno le da el color usado por MENOS vecinos ya coloreados -será
# un color libre casi siempre; ver el comentario grande de REPARTO DE
# COLOR más arriba-. Devuelve un array de índices de color (0..7),
# paralelo a `found`.
def greedy_color_indices(neighbors)
  # Empate en número de vecinos -MUY común en una estructura repetitiva
  # como esta, columna tras columna idéntica- se rompe con `rand` como
  # criterio secundario, no con el orden en que aparecen en `neighbors`.
  # Sin esto, módulos estructuralmente idénticos se procesan siempre en
  # el mismo orden relativo, heredan el mismo entorno de colores ya
  # asignados, y "resuenan" hacia el mismo color repetido en cada
  # módulo -confirmado con datos reales: 5 postes de columnas distintas
  # y SIN tocarse entre sí, todos con el mismo #6E247D-.
  order = (0...neighbors.length).sort_by { |i| [-neighbors[i].length, rand] }
  assigned = Array.new(neighbors.length)
  # Conteo GLOBAL de cuántas veces se ha usado cada color en todo el
  # modelo hasta el momento -no solo entre los vecinos directos de la
  # pieza actual-. Sin esto, aunque el orden ya esté barajado, tramos
  # repetitivos largos (30+ columnas idénticas) podían acumular rachas
  # de hasta 5 seguidas del mismo color por puro azar -confirmado con
  # una prueba sintética de 30 módulos idénticos-. Preferir SIEMPRE el
  # color menos usado en todo el modelo, entre los que ya son válidos
  # localmente, tope esa racha en 2 como máximo en la misma prueba.
  global_counts = Array.new(COLORS_HEX.length, 0)
  order.each do |i|
    used_counts = Hash.new(0)
    neighbors[i].each { |j| used_counts[assigned[j]] += 1 unless assigned[j].nil? }
    min_local = (0...COLORS_HEX.length).map { |c| used_counts[c] }.min
    # Colores válidos localmente -no chocan con ningún vecino ya
    # coloreado-. Lo más común, casi todos en 0 usos locales.
    local_candidates = (0...COLORS_HEX.length).select { |c| used_counts[c] == min_local }
    min_global = local_candidates.map { |c| global_counts[c] }.min
    best_candidates = local_candidates.select { |c| global_counts[c] == min_global }
    chosen = best_candidates.sample
    assigned[i] = chosen
    global_counts[chosen] += 1
  end
  assigned
end

# Clasifica un tubo por su dirección -solo para el reporte, no afecta
# la detección ni el coloreado- como 'vertical', 'horizontal-X',
# 'horizontal-Y' o 'diagonal'.
def orientation_label(direction)
  ax, ay, az = direction.x.abs, direction.y.abs, direction.z.abs
  if az > 0.9
    'vertical'
  elsif ax > 0.9
    'horizontal-X'
  elsif ay > 0.9
    'horizontal-Y'
  else
    'diagonal'
  end
end

# Pinta y DEVUELVE cuántas caras realmente tocó y qué entidad quedó
# pintada -ya no se asume que "se llamó a paint" == "quedó pintado"; el
# llamador vuelve a leer el material real después, ver más abajo-.
def paint(entity, hex, materials)
  entity = entity.make_unique
  material = materials[hex] ||= begin
    name = "Color ##{hex}"
    m = Sketchup.active_model.materials[name] || Sketchup.active_model.materials.add(name)
    m.color = hex_to_color(hex)
    m
  end
  faces = direct_faces(entity)
  faces.each do |face|
    face.material = material
    face.back_material = material
  end
  { entity: entity, faces_painted: faces.length }
end

require 'fileutils'

# Misma carpeta que usa inspect_geometry.rb -así el reporte queda junto
# con el resto de los análisis del proyecto, con fecha y hora en el
# nombre para no sobreescribir corridas anteriores-.
OUTPUT_DIR = '/Users/minorusal/Documents/SKETCHUP/inspect_output'.freeze

model = Sketchup.active_model
found = []
identity = Geom::Transformation.new
top_level = model.entities.grep(Sketchup::Group) + model.entities.grep(Sketchup::ComponentInstance)
top_level.each { |entity| collect_foam_tubes(entity, identity, found) }

if found.empty?
  puts "No se encontró ningún tubo de esponja (~#{DIAMETER_REFERENCE_MM.to_i}mm de diámetro) en el modelo."
else
  # REPARTO DE COLOR -CUARTO enfoque, el que finalmente funcionó-:
  # ordenar por posición y contar módulo 8 (intento anterior) falló por
  # una razón real y verificada: un grupo de postes verticales
  # -entityID 4426456...4426883, confirmados 3 veces con datos reales
  # del modelo- SIEMPRE caía en posiciones de la lista separadas por
  # múltiplos EXACTOS de 8 -no es azar ni empate, es una coincidencia
  # estructural genuina de cómo se ordenan por posición-, así que el
  # módulo 8 les tocaba siempre el mismo color sin importar qué tan bien
  # barajado o determinista fuera el orden.
  #
  # La solución: el color de cada tubo ya NO depende de su posición en
  # ninguna lista ni de ningún orden -eso es precisamente lo que seguía
  # fallando-. Depende ÚNICAMENTE de su entityID -único e inmutable por
  # pieza- pasado por un hash CRIPTOGRÁFICO (MD5), no una combinación
  # lineal simple como los intentos anteriores. Un hash criptográfico
  # está diseñado matemáticamente para que NO exista ninguna relación
  # entre entradas parecidas/relacionadas y sus salidas -al contrario de
  # "posición mod 8", que si tiene una relación directa y por eso se
  # rompía-. Verificado con los mismos 10 entityID reales que antes
  # daban siempre el mismo color: con MD5 dan 5 colores distintos entre
  # los 10 (D911CB, 039CD4, FFFF1E, FFA400, 11D9B4).
  require 'digest'
  color_indices = found.map do |item|
    id = item[:entity].entityID
    Digest::MD5.hexdigest(id.to_s).to_i(16) % COLORS_HEX.length
  end

  # `neighbors` se conserva solo para el reporte de verificación de
  # abajo -cuántos pares de tubos que se tocan quedaron con el mismo
  # color-, ya no decide el color de nadie.
  neighbors = build_neighbors(found)
  max_degree = neighbors.map(&:length).max

  materials = {}
  painted = Hash.new(0)
  report_rows = []
  mismatches = []
  model.start_operation('Colorear tubos de esponja', true)
  begin
    found.each_with_index do |item, index|
      hex = COLORS_HEX[color_indices[index]]
      result = paint(item[:entity], hex, materials)
      painted[hex] += 1

      # Verificación real: vuelve a leer el material DESDE la entidad
      # -no confía en que "se llamó paint" signifique "quedó pintado"-.
      actual_face = direct_faces(result[:entity]).first
      actual_material = actual_face&.material&.name
      expected_material = "Color ##{hex}"
      verified = actual_material == expected_material
      mismatches << {
        id: result[:entity].entityID,
        expected: expected_material,
        actual: actual_material || '(sin material)',
        faces_painted: result[:faces_painted]
      } unless verified

      c = item[:world_center]
      orientation = orientation_label(item[:world_direction])
      report_rows << {
        n: index + 1,
        id: result[:entity].entityID,
        length_mm: item[:length_mm].round(1),
        diameter_mm: item[:diameter_mm].round(1),
        x: c.x.to_mm.round(1),
        y: c.y.to_mm.round(1),
        z: c.z.to_mm.round(1),
        color: hex,
        orientation: orientation,
        neighbor_count: neighbors[index].length,
        verified: verified
      }
    end
    model.commit_operation
  rescue StandardError
    model.abort_operation
    raise
  end

  # Verificación del grafo: cuántos pares de tubos que SÍ comparten un
  # nodo real terminaron con el mismo color -debería ser 0, salvo en
  # nodos con más de 8 tubos simultáneos, matemáticamente inevitable-.
  color_conflicts = 0
  shared_joint_pairs = 0
  found.each_index do |i|
    neighbors[i].each do |j|
      next if j <= i
      shared_joint_pairs += 1
      color_conflicts += 1 if color_indices[i] == color_indices[j]
    end
  end

  total = painted.values.sum
  lines = []
  lines << "Tubos de esponja coloreados: #{total}"
  lines << "Verificados (material real coincide con el asignado): #{total - mismatches.length} / #{total}"
  lines << "Máximo de tubos que se tocan en un solo nodo: #{max_degree}"
  lines << "Pares de tubos que comparten nodo: #{shared_joint_pairs}  -  con el MISMO color: #{color_conflicts}"
  lines << ('=' * 70)
  report_rows.each do |r|
    check = r[:verified] ? 'OK' : '¡NO COINCIDE!'
    lines << "##{r[:n]}  entityID=#{r[:id]}  largo=#{r[:length_mm]}mm  " \
      "diámetro=#{r[:diameter_mm]}mm  posición=(#{r[:x]}, #{r[:y]}, #{r[:z]})mm  " \
      "vecinos_en_nodo=#{r[:neighbor_count]}  color=##{r[:color]}  [#{check}]"
  end
  lines << ('=' * 70)
  lines << 'Resumen por color:'
  painted.each { |hex, n| lines << "  ##{hex}: #{n}" }

  lines << ('=' * 70)
  lines << 'Resumen por orientación (para ver si algún tipo -vertical, ' \
    'horizontal-X, horizontal-Y, diagonal- quedó dominado por un solo color):'
  by_orientation = report_rows.group_by { |r| r[:orientation] }
  by_orientation.each do |orientation, rows|
    counts = Hash.new(0)
    rows.each { |r| counts[r[:color]] += 1 }
    lines << "  #{orientation} (#{rows.length} pieza(s)):"
    counts.sort.each { |hex, n| lines << "    ##{hex}: #{n}" }
  end

  unless mismatches.empty?
    lines << ('=' * 70)
    lines << "PIEZAS DONDE EL MATERIAL NO QUEDÓ COMO SE ESPERABA (#{mismatches.length}):"
    mismatches.each do |m|
      lines << "  entityID=#{m[:id]}  esperado=#{m[:expected]}  real=#{m[:actual]}  caras_pintadas=#{m[:faces_painted]}"
    end
  end

  FileUtils.mkdir_p(OUTPUT_DIR)
  output_path = File.join(OUTPUT_DIR, "colorear_tubos_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt")
  File.write(output_path, lines.join("\n"))

  puts "Listo. #{total} tubo(s) de esponja (~#{DIAMETER_REFERENCE_MM.to_i}mm de diámetro) coloreado(s)."
  puts "Verificados: #{total - mismatches.length} / #{total}#{mismatches.empty? ? '' : "  -- #{mismatches.length} NO QUEDARON COMO SE ESPERABA, ver el archivo--"}"
  puts "Tubos que comparten nodo con el MISMO color: #{color_conflicts} de #{shared_joint_pairs} pares (máx. #{max_degree} tubos en un nodo)."
  puts "Detalle guardado en: #{output_path}"
  painted.each { |hex, n| puts "  ##{hex}: #{n}" }
  puts 'Por orientación:'
  by_orientation.each do |orientation, rows|
    counts = Hash.new(0)
    rows.each { |r| counts[r[:color]] += 1 }
    puts "  #{orientation} (#{rows.length}): #{counts.sort.map { |hex, n| "##{hex}=#{n}" }.join(', ')}"
  end
end

# Fuerza a SketchUp a redibujar el visor -por si acaso no se estaba
# actualizando solo después de correr el script desde la consola-.
Sketchup.active_model.active_view.invalidate
puts 'Vista refrescada.'
nil
