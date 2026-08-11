# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# Uso:
#   1. Selecciona los tubos a diagnosticar -puede ser toda la selección
#      que dejó seleccionar_tubos_esponja.rb-.
#   2. Pega este script y presiona Enter.
#   3. Imprime, por cada uno: entityID, posición del CENTRO en
#      coordenadas de MUNDO (mm), y el material de su primera cara.
#      Al final, agrupa por color y muestra el rango de posiciones de
#      cada grupo, para ver si los colores se están repartiendo por
#      posición real o no.
#
# A diferencia de la versión anterior, esta SÍ imprime la posición -la
# anterior solo daba entityID y color, que no alcanza para saber si las
# piezas del mismo color están físicamente juntas o dispersas-.

selection = Sketchup.active_model.selection
if selection.empty?
  puts 'Selecciona primero los tubos a diagnosticar.'
else
  identity = Geom::Transformation.new
  rows = []
  selection.each do |entity|
    next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    center = entity.bounds.center.transform(identity)
    face = if entity.is_a?(Sketchup::Group)
             entity.entities.grep(Sketchup::Face).first
           else
             entity.definition.entities.grep(Sketchup::Face).first
           end
    material = face&.material&.name || '(sin material)'
    rows << {
      id: entity.entityID,
      x: center.x.to_mm.round(1),
      y: center.y.to_mm.round(1),
      z: center.z.to_mm.round(1),
      material: material
    }
  end

  puts "--- #{rows.length} pieza(s), ordenadas por posición (Z,Y,X) ---"
  rows.sort_by! { |r| [r[:z], r[:y], r[:x]] }
  rows.each do |r|
    puts "id=#{r[:id]}  pos=(#{r[:x]}, #{r[:y]}, #{r[:z]})  #{r[:material]}"
  end

  puts "\n--- Resumen por color ---"
  rows.group_by { |r| r[:material] }.each do |material, group|
    xs = group.map { |r| r[:x] }
    ys = group.map { |r| r[:y] }
    zs = group.map { |r| r[:z] }
    puts "#{material}: #{group.length} pieza(s)  X=[#{xs.min}..#{xs.max}]  Y=[#{ys.min}..#{ys.max}]  Z=[#{zs.min}..#{zs.max}]"
  end
end
nil
