# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# Uso:
#   1. Pega este script y presiona Enter. NO hace falta seleccionar
#      nada antes -revisa el modelo completo-.
#   2. Selecciona (en el modelo) TODAS las piezas que sean
#      geométricamente un tubo/cilindro de ~85mm de diámetro -misma
#      detección que colorear_tubos_esponja.rb, no colorea nada, solo
#      selecciona-.
#   3. Además de seleccionar, calcula para cada tubo sus dos extremos
#      reales en el mundo y arma el mismo grafo de "qué tubos se tocan
#      en qué nodo" que usa colorear_tubos_esponja.rb para repartir
#      colores -pero aquí NO colorea nada, solo lo reporta-. Guarda
#      todo (posición, largo, diámetro, cuántos tubos comparten cada
#      nodo) en un archivo, para poder revisar la estructura ANTES de
#      colorear -o para diagnosticar si algo se ve raro después-.
#
# Ver colorear_tubos_esponja.rb para la explicación completa de la
# fórmula de detección de tubo y del grafo de nodos compartidos.

DIAMETER_REFERENCE_MM = 85.0
DIAMETER_TOLERANCE_MM = 10.0
MIN_ASPECT_RATIO = 2.0
RESIDUAL_RELATIVE_TOLERANCE = 0.02
JOINT_BUCKET_MM = 20.0

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

# Agrupa TODOS los extremos por cercanía real en 3D -distancia
# euclidiana, no redondeo por eje independiente, que puede perder
# conexiones reales cuando dos puntos caen justo en bordes de celdas
# distintas de la rejilla-. Mismo método que colorear_tubos_esponja.rb.
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

def build_joints(found)
  cluster_endpoints(found).map do |cluster|
    { tubes: cluster.map { |p| p[:tube] }.uniq, point: cluster.first[:point] }
  end
end

require 'fileutils'
OUTPUT_DIR = '/Users/minorusal/Documents/SKETCHUP/inspect_output'.freeze

model = Sketchup.active_model
found = []
identity = Geom::Transformation.new
top_level = model.entities.grep(Sketchup::Group) + model.entities.grep(Sketchup::ComponentInstance)
top_level.each { |entity| collect_foam_tubes(entity, identity, found) }

model.selection.clear
model.selection.add(found.map { |item| item[:entity] })

if found.empty?
  puts "No se encontró ningún tubo de esponja (~#{DIAMETER_REFERENCE_MM.to_i}mm de diámetro) en el modelo."
else
  joints = build_joints(found)
  neighbor_counts = Array.new(found.length, 0)
  joints.each do |joint|
    members = joint[:tubes]
    next if members.length < 2
    members.each { |i| neighbor_counts[i] += (members.length - 1) }
  end

  lines = []
  lines << "Tubos de esponja encontrados (seleccionados en el modelo): #{found.length}"
  lines << "Nodos distintos (extremos compartidos por 2+ tubos): #{joints.count { |j| j[:tubes].length >= 2 }}"
  lines << "Máximo de tubos que se tocan en un solo nodo: #{joints.map { |j| j[:tubes].length }.max}"
  lines << ('=' * 70)
  lines << 'DETALLE POR TUBO'
  lines << ('=' * 70)
  found.each_with_index do |item, i|
    c = item[:world_center]
    a = item[:endpoint_a]
    b = item[:endpoint_b]
    lines << "##{i + 1}  entityID=#{item[:entity].entityID}  largo=#{item[:length_mm].round(1)}mm  " \
      "diámetro=#{item[:diameter_mm].round(1)}mm"
    lines << "     centro=(#{c.x.to_mm.round(1)}, #{c.y.to_mm.round(1)}, #{c.z.to_mm.round(1)})mm"
    lines << "     extremo A=(#{a.x.to_mm.round(1)}, #{a.y.to_mm.round(1)}, #{a.z.to_mm.round(1)})mm  " \
      "extremo B=(#{b.x.to_mm.round(1)}, #{b.y.to_mm.round(1)}, #{b.z.to_mm.round(1)})mm"
    lines << "     tubos que comparten alguno de sus dos nodos: #{neighbor_counts[i]}"
  end

  lines << ('=' * 70)
  lines << 'NODOS CON 2 O MÁS TUBOS (qué tubos se tocan ahí)'
  lines << ('=' * 70)
  joints.each do |joint|
    members = joint[:tubes]
    next if members.length < 2
    p = joint[:point]
    ids = members.map { |i| found[i][:entity].entityID }
    lines << "nodo ~(#{p.x.to_mm.round(1)}, #{p.y.to_mm.round(1)}, #{p.z.to_mm.round(1)})mm  -  " \
      "#{members.length} tubo(s): entityID #{ids.join(', ')}"
  end

  FileUtils.mkdir_p(OUTPUT_DIR)
  output_path = File.join(OUTPUT_DIR, "seleccionar_tubos_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt")
  File.write(output_path, lines.join("\n"))

  puts "Seleccionados #{found.length} tubo(s) de esponja (~#{DIAMETER_REFERENCE_MM.to_i}mm de diámetro)."
  puts "Nodos con 2+ tubos: #{joints.count { |j| j[:tubes].length >= 2 }}  " \
    "-  máximo de tubos en un nodo: #{joints.map { |j| j[:tubes].length }.max}"
  puts "Detalle completo (posición, largo, extremos, nodos compartidos) guardado en: #{output_path}"
end
nil
