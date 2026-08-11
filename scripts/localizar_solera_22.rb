# Pega este script completo en Ventana > Consola de Ruby de SketchUp,
# con la misma selección de siempre (estructura + torre). Busca la
# solera cuyo origen de mundo es [1185.23, 1166.64, 1330.04] mm -la #22
# del análisis- y la SELECCIONA + hace zoom, para verla directo en el
# modelo en vez de en números. No mueve ni duplica nada.

OBJETIVO_MM = [1185.23, 1166.64, 1330.04]
TOLERANCIA_MM = 1.0

def buscar_soleras(entities, transform_acumulado, resultados)
  entities.each do |e|
    next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    transform_mundo = transform_acumulado * e.transformation
    nombre = e.is_a?(Sketchup::Group) ? e.name.to_s : e.definition.name.to_s
    nombre = e.name.to_s if nombre.empty?
    resultados << { entidad: e, transform: transform_mundo } if nombre.start_with?('SOLERA')
    hijos = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
    buscar_soleras(hijos, transform_mundo, resultados)
  end
end

begin
  model = Sketchup.active_model
  sel = model.selection
  raise 'Selecciona la estructura y la torre antes de correr esto.' if sel.empty?

  resultados = []
  sel.each do |top|
    next unless top.is_a?(Sketchup::Group) || top.is_a?(Sketchup::ComponentInstance)
    resultados << { entidad: top, transform: top.transformation } if top.name.to_s.start_with?('SOLERA')
    hijos = top.is_a?(Sketchup::Group) ? top.entities : top.definition.entities
    buscar_soleras(hijos, top.transformation, resultados)
  end

  objetivo = Geom::Point3d.new(OBJETIVO_MM[0].mm, OBJETIVO_MM[1].mm, OBJETIVO_MM[2].mm)
  encontrada = resultados.min_by { |r| r[:transform].origin.distance(objetivo) }
  raise 'No encontré ninguna solera en la selección.' unless encontrada

  dist = encontrada[:transform].origin.distance(objetivo)
  raise "La más cercana está a #{dist.to_mm.round(1)}mm del objetivo -parece que no es la misma-." if dist.to_mm > TOLERANCIA_MM

  model.selection.clear
  model.selection.add(encontrada[:entidad])
  model.active_view.zoom(model.selection.to_a)
  puts "✅ Solera #22 seleccionada y con zoom -es el objeto '#{encontrada[:entidad].name}' que ahora se ve resaltado-."
rescue StandardError => e
  puts "❌ Error: #{e.message}"
end
nil
