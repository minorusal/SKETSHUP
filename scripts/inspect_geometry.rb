# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# Uso:
#   1. Inserta o selecciona la pieza a inspeccionar (un conector, un tubo,
#      un módulo completo armado a mano como referencia "correcta", etc.).
#      Preferir seleccionar SOLO lo relevante (ej. un conector + su tubo)
#      en vez del módulo completo: la nueva tabla de distancias en mundo
#      compara TODOS los pares posibles, así que con una selección grande
#      el resultado crece muy rápido y se vuelve difícil de leer.
#   2. Selecciónala en el modelo (clic simple sobre el grupo/componente raíz).
#   3. Pega este script en la consola y presiona Enter.
#   4. El resultado NO se imprime en la consola -queda demasiado grande
#      para copiar a mano-; se guarda directo en un archivo .txt nuevo
#      (con fecha y hora en el nombre, nunca sobreescribe uno anterior)
#      dentro de la carpeta de los plugins, en OUTPUT_DIR. La consola solo
#      muestra la ruta del archivo creado.
#
# Baja RECURSIVAMENTE (por defecto hasta 4 niveles): si seleccionas un
# módulo completo, también muestra qué hay DENTRO de cada conector.
#
# IMPORTANTE: cada pieza ahora se reporta en DOS sistemas de coordenadas:
#   - "local" = relativo a su padre inmediato (como antes).
#   - "MUNDO" = coordenadas absolutas del modelo, ya acumulando todas las
#     transformaciones de los padres. Esto permite comparar directamente,
#     por ejemplo, un tubo que cuelga del módulo contra un manguito que
#     está anidado 3 niveles adentro de un conector, sin tener que
#     multiplicar matrices a mano (fuente de errores en rondas anteriores).
#
# Al final imprime además una TABLA PLANA con las coordenadas de mundo de
# TODAS las piezas inspeccionadas, en un solo lugar, para comparar cualquier
# par de piezas sin importar en qué rama del árbol estén, y una tabla de
# DISTANCIAS EN MUNDO entre TODOS los pares de esa tabla plana -a diferencia
# de las "Distancias LOCALES" (que solo comparan hermanos directos bajo el
# mismo padre), esta sí compara piezas en ramas distintas del árbol -por
# ejemplo, el receptor "Principal" anidado 2 niveles adentro de un conector
# contra el poste Z que cuelga directo de la raíz, sin tener que restar
# coordenadas a mano-.
#
# No modifica el modelo: solo lee bounds y transformaciones.

require 'fileutils'
require 'stringio'

# Carpeta de los plugins (contiene auditor_juegos, conectores_playidea,
# constructor_modulos_playidea, creador_tubos_playidea, scripts, etc.).
OUTPUT_DIR = '/Users/minorusal/Documents/SKETCHUP/inspect_output'.freeze

MAX_DEPTH = 4
FLAT_INDEX = []

def mm3(point_or_vector)
  point_or_vector.to_a.map { |v| v.to_mm.round(3) }
end

# Transforma los 8 vértices del bounding box (que ya viene en coords del
# padre inmediato) al sistema de coordenadas de mundo, usando el transform
# acumulado de TODOS los ancestros (sin incluir el de esta misma entidad,
# porque bounds ya lo incorpora).
def world_bounds(bounds, ancestors_transform)
  box = Geom::BoundingBox.new
  8.times { |i| box.add(bounds.corner(i).transform(ancestors_transform)) }
  box
end

def describe_entity(entity, indent, path, ancestors_transform)
  name = entity.name.to_s.empty? ? "(sin nombre)" : entity.name
  kind = entity.is_a?(Sketchup::Group) ? "Grupo" : "Componente"
  bounds = entity.bounds
  t = entity.transformation
  wbounds = world_bounds(bounds, ancestors_transform)
  world_origin = t.origin.transform(ancestors_transform)

  puts "#{indent}- #{name}  [#{kind}]  ruta: #{path}"
  puts "#{indent}    bounds min=#{mm3(bounds.min)}  max=#{mm3(bounds.max)}  (mm, LOCAL al padre inmediato)"
  puts "#{indent}    bounds MUNDO min=#{mm3(wbounds.min)}  max=#{mm3(wbounds.max)}  (mm, ABSOLUTAS del modelo)"
  puts "#{indent}    bounds size = #{[bounds.width.to_mm.round(3), bounds.height.to_mm.round(3), bounds.depth.to_mm.round(3)]} mm (X,Y,Z)"
  puts "#{indent}    transform origin LOCAL=#{mm3(t.origin)}  origin MUNDO=#{mm3(world_origin)}"
  puts "#{indent}    transform xaxis=#{t.xaxis.to_a.map { |v| v.round(4) }}  yaxis=#{t.yaxis.to_a.map { |v| v.round(4) }}  zaxis=#{t.zaxis.to_a.map { |v| v.round(4) }}"

  FLAT_INDEX << { path: path, name: name, kind: kind, wbounds: wbounds, world_origin: world_origin }
  wbounds
end

def child_entities(entity)
  container = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
  container.grep(Sketchup::Group) + container.grep(Sketchup::ComponentInstance)
end

def bbox_gap(b1, b2)
  # Distancia (mm) entre dos bounding boxes eje por eje, en el MISMO
  # sistema de coordenadas (deben ser ambos locales o ambos de mundo).
  # Positivo = hueco real en ese eje. Negativo = se encimen en ese eje.
  gx = [b1.min.x, b2.min.x].max - [b1.max.x, b2.max.x].min
  gy = [b1.min.y, b2.min.y].max - [b1.max.y, b2.max.y].min
  gz = [b1.min.z, b2.min.z].max - [b1.max.z, b2.max.z].min
  [gx.to_mm.round(3), gy.to_mm.round(3), gz.to_mm.round(3)]
end

def entity_label(e)
  e.name.to_s.empty? ? "(sin nombre)" : e.name
end

def inspect_recursive(entity, indent, depth, path, ancestors_transform)
  wbounds = describe_entity(entity, indent, path, ancestors_transform)
  return if depth >= MAX_DEPTH

  children = child_entities(entity)
  return if children.empty?

  my_world_transform = ancestors_transform * entity.transformation

  puts "#{indent}  Sub-piezas directas (#{children.length}):\n\n"
  child_wbounds = children.map do |c|
    child_path = "#{path} > #{entity_label(c)}"
    [c, inspect_recursive(c, indent + "    ", depth + 1, child_path, my_world_transform)]
  end

  if children.length > 1
    puts "#{indent}  Distancias LOCALES entre hijos de '#{entity_label(entity)}' (mm por eje; negativo = se encimen):\n\n"
    children.combination(2).each do |a, b|
      gap = bbox_gap(a.bounds, b.bounds)
      puts "#{indent}    #{entity_label(a)}  <->  #{entity_label(b)}  :  gap XYZ = #{gap}"
    end
    puts
  end

  wbounds
end

captured_output = StringIO.new
real_stdout = $stdout
$stdout = captured_output

begin

selection = Sketchup.active_model.selection
if selection.empty?
  puts "Selecciona primero la pieza (grupo o componente) a inspeccionar."
else
  selection.each do |root|
    unless root.is_a?(Sketchup::Group) || root.is_a?(Sketchup::ComponentInstance)
      puts "Selecciona un grupo o componente, no geometría suelta."
      next
    end
    puts "=" * 70
    puts "RAÍZ: #{entity_label(root)}  (profundidad máxima: #{MAX_DEPTH})"
    puts "=" * 70
    # Identity transform: el root se toma como referencia de "mundo" tal
    # cual está en el modelo (asume que el root está directamente en
    # model.active_entities, no anidado dentro de otro grupo).
    identity = Geom::Transformation.new
    inspect_recursive(root, "", 0, entity_label(root), identity)
    puts
  end

  puts "=" * 70
  puts "TABLA PLANA — coordenadas de MUNDO de todas las piezas (#{FLAT_INDEX.length})"
  puts "=" * 70
  FLAT_INDEX.each do |e|
    min = e[:wbounds].min.to_a.map { |v| v.to_mm.round(2) }
    max = e[:wbounds].max.to_a.map { |v| v.to_mm.round(2) }
    puts "#{e[:path]}"
    puts "    world bounds min=#{min}  max=#{max}"
  end

  if FLAT_INDEX.length > 1
    puts
    puts "=" * 70
    puts "DISTANCIAS EN MUNDO entre TODOS los pares (mm por eje; negativo = se " \
      "encimen/traslapan en ese eje; compara CUALQUIER rama del árbol, no solo hermanos)"
    puts "=" * 70
    FLAT_INDEX.combination(2).each do |a, b|
      gap = bbox_gap(a[:wbounds], b[:wbounds])
      puts "#{a[:path]}"
      puts "  <-> #{b[:path]}"
      puts "  gap XYZ = #{gap}"
    end
  end
end

ensure
  $stdout = real_stdout
end

FileUtils.mkdir_p(OUTPUT_DIR)
output_path = File.join(OUTPUT_DIR, "inspect_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt")
File.write(output_path, captured_output.string)
puts "Listo. Resultado guardado en: #{output_path}"
nil
