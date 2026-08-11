# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# Uso:
#   1. Selecciona el/los grupo(s) donde puedan estar los cubos de
#      esponja -puede ser un contenedor con más cosas adentro, no hace
#      falta seleccionar solo los cubos-.
#   2. Pega este script en la consola y presiona Enter.
#   3. Baja RECURSIVAMENTE por grupos/componentes hasta encontrar cada
#      geometría "hoja" -la que ya tiene caras propias, como un cubo
#      individual, a diferencia de un contenedor que solo agrupa otros
#      grupos-, y SOLO colorea las que sean geométricamente un cubo de
#      ~150mm de arista -la medida confirmada analizando
#      inspect_20260729_122045.txt-. Cualquier otra cosa dentro de la
#      selección -tubos, conectores, cajas no cúbicas, cubos de otro
#      tamaño- se deja intacta.
#
# Cómo se detecta un cubo de ~150mm sin importar su rotación: para cada
# eje del mundo, el tamaño de la caja delimitadora en ese eje es
# `arista * (suma de los valores absolutos de las 3 componentes de
# xaxis/yaxis/zaxis en ese eje)` -fórmula verificada con exactitud
# numérica contra los datos reales del .txt-. Si las 3 estimaciones de
# arista que salen de esa fórmula concuerdan entre sí Y caen cerca de
# REFERENCE_CUBE_EDGE_MM, se pinta; si no, se ignora.
#
# Si una geometría "hoja" resulta ser un COMPONENTE cuya definición se
# usa en más de un lugar del modelo, este script la vuelve única primero
# (`make_unique`) antes de colorearla, para que el color solo afecte a
# ESA instancia -no a las demás copias del mismo componente-. Los grupos
# ya son siempre únicos en SketchUp, así que no necesitan este paso.
#
# No modifica posición, rotación ni geometría -solo asigna material/color
# a las caras de cada cubo detectado-.

REFERENCE_CUBE_EDGE_MM = 150.0
EDGE_TOLERANCE_MM = 15.0
CONSISTENCY_TOLERANCE = 0.08

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

# Devuelve la arista estimada (mm) si `entity` es geométricamente un
# cubo de ~REFERENCE_CUBE_EDGE_MM, o `nil` si no -ver comentario de
# cabecera para la fórmula-.
def cube_like_edge_mm(entity)
  t = entity.transformation
  bounds = entity.bounds
  size = [bounds.width.to_mm, bounds.height.to_mm, bounds.depth.to_mm]
  axes = [t.xaxis.to_a, t.yaxis.to_a, t.zaxis.to_a]
  l1 = [0, 1, 2].map { |col| axes.sum { |axis| axis[col].abs } }
  return nil if l1.any? { |v| v < 0.05 }
  estimates = size.zip(l1).map { |s, l| s / l }
  avg = estimates.sum / estimates.length
  return nil if avg <= 0
  return nil unless estimates.all? { |e| ((e - avg).abs / avg) <= CONSISTENCY_TOLERANCE }
  return nil if (avg - REFERENCE_CUBE_EDGE_MM).abs > EDGE_TOLERANCE_MM
  avg
end

def paint_leaf(entity, materials, painted)
  entity.make_unique if entity.is_a?(Sketchup::ComponentInstance)
  hex = COLORS_HEX.sample
  material = materials[hex] ||= begin
    name = "Color ##{hex}"
    m = Sketchup.active_model.materials[name] || Sketchup.active_model.materials.add(name)
    m.color = hex_to_color(hex)
    m
  end
  direct_faces(entity).each do |face|
    face.material = material
    face.back_material = material
  end
  painted[hex] += 1
end

def paint_recursive(entity, materials, painted, skipped)
  faces = direct_faces(entity)
  children = child_entities(entity)
  if !faces.empty? || children.empty?
    if cube_like_edge_mm(entity)
      paint_leaf(entity, materials, painted)
    else
      skipped[0] += 1
    end
  else
    children.each { |child| paint_recursive(child, materials, painted, skipped) }
  end
end

selection = Sketchup.active_model.selection
if selection.empty?
  puts 'Selecciona primero el grupo (o los cubos) a colorear.'
else
  model = Sketchup.active_model
  materials = {}
  painted = Hash.new(0)
  skipped = [0]
  model.start_operation('Colorear cubos de esponja', true)
  begin
    selection.each do |entity|
      next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      paint_recursive(entity, materials, painted, skipped)
    end
    model.commit_operation
  rescue StandardError
    model.abort_operation
    raise
  end
  total = painted.values.sum
  puts "Listo. #{total} cubo(s) de ~#{REFERENCE_CUBE_EDGE_MM.to_i}mm coloreado(s):"
  painted.each { |hex, n| puts "  ##{hex}: #{n}" }
  puts "Geometrías ignoradas (no son cubos de ~#{REFERENCE_CUBE_EDGE_MM.to_i}mm): #{skipped[0]}"
end
nil
