# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# VERSION DEL SCRIPT: v2 -agrega los 4 tornillos, no solo los agujeros-
# (2026-08-06)
#
# QUÉ ES ESTO
# -----------
# Crea, como pieza SUELTA -todavía sin integrar a ninguna estructura-, la
# "placa de solera" de 1 pulgada CON sus 4 tornillos puestos: 2
# autorroscantes arriba de la placa (la fijan a la estructura) y 2 pijas
# de madera #8 apuntando hacia arriba por debajo (sujetan lo que va
# encima). La idea es que el usuario la tome desde aquí y la coloque A
# MANO en las esquinas de una cama real, para que después -con
# copiar_grupo_referencia.rb sobre esa colocación real- se pueda analizar
# dónde queda exactamente y automatizar su colocación en el script de
# creación de estructura.
#
# DATOS CONFIRMADOS por el usuario (no tocar sin que él lo pida):
#   - Ancho de la solera: 1 pulgada (25.4mm). Largo: 20cm (200mm).
#   - 2 autorroscantes #14 x 1 1/2" punta de broca (self-drilling), uno en
#     cada extremo, apuntando hacia abajo -fijan la solera a la estructura-.
#   - 1 pija de madera del número 8 al centro, apuntando hacia arriba
#     -sujeta lo que va encima-.
#
# DATOS QUE FALTAN Y AQUÍ SE USAN COMO ESTIMADO -avísame la medida real y
# los corrijo, no hay que adivinar más de lo necesario para tener algo que
# puedas colocar y probar-:
#   - Largo de la solera, su espesor, y diámetro/posición de los 4
#     agujeros (igual que en la v1).
#   - Largo de la pija #8 -no me lo diste, tampoco los diámetros de vástago
#     y cabeza de ninguno de los dos tornillos-.

model = Sketchup.active_model
model.start_operation('Crear solera de prueba', true)

begin
  SOLERA_WIDTH_MM = 25.4        # 1" - CONFIRMADO
  SOLERA_LENGTH_MM = 200.0      # 20cm - CONFIRMADO
  SOLERA_THICKNESS_MM = 3.175   # 1/8" - ESTIMADO
  AUTORROSCANTE_HOLE_DIAM_MM = 6.35 # ESTIMADO
  PIJA8_HOLE_DIAM_MM = 4.2      # ESTIMADO
  END_INSET_MM = 12.0           # ESTIMADO -qué tan cerca del extremo va cada autorroscante-

  AUTORROSCANTE_SHAFT_DIAM_MM = 6.35    # ESTIMADO -diámetro nominal aprox. de un #14-
  AUTORROSCANTE_LENGTH_MM = 38.1        # 1 1/2" - CONFIRMADO
  AUTORROSCANTE_HEAD_DIAM_MM = 11.0     # ESTIMADO
  AUTORROSCANTE_HEAD_THICKNESS_MM = 3.0 # ESTIMADO

  PIJA8_SHAFT_DIAM_MM = 4.2      # ESTIMADO -diámetro nominal aprox. de un #8-
  PIJA8_LENGTH_MM = 25.4         # 1" - ESTIMADO, no me diste el largo real
  PIJA8_HEAD_DIAM_MM = 8.0       # ESTIMADO
  PIJA8_HEAD_THICKNESS_MM = 2.0  # ESTIMADO

  # Posiciones LOCALES (mm) sobre la placa -mismo origen que usa la
  # instancia, que se coloca con transformación identidad-, reutilizadas
  # tanto para los agujeros como para los tornillos.
  AUTORROSCANTE_POSITIONS_MM = [
    [END_INSET_MM, SOLERA_WIDTH_MM / 2.0],
    [SOLERA_LENGTH_MM - END_INSET_MM, SOLERA_WIDTH_MM / 2.0]
  ]
  PIJA_POSITIONS_MM = [
    [SOLERA_LENGTH_MM / 2.0, SOLERA_WIDTH_MM / 2.0]
  ]

  model.definitions.remove(model.definitions['SOLERA-1IN-TEST']) if model.definitions['SOLERA-1IN-TEST']
  definition = model.definitions.add('SOLERA-1IN-TEST')
  entities = definition.entities

  # Cara superior en Z=0, la placa se extruye HACIA ABAJO (-Z) el espesor.
  top_face_pts = [
    Geom::Point3d.new(0, 0, 0),
    Geom::Point3d.new(SOLERA_LENGTH_MM.mm, 0, 0),
    Geom::Point3d.new(SOLERA_LENGTH_MM.mm, SOLERA_WIDTH_MM.mm, 0),
    Geom::Point3d.new(0, SOLERA_WIDTH_MM.mm, 0)
  ]
  face = entities.add_face(top_face_pts)
  raise 'add_face de la placa devolvió nil' unless face
  face.reverse! if face.normal.z < 0
  face.pushpull(-SOLERA_THICKNESS_MM.mm)

  def punch_hole(entities, center_x_mm, center_y_mm, diam_mm, thickness_mm)
    center = Geom::Point3d.new(center_x_mm.mm, center_y_mm.mm, 0)
    circle_edges = entities.add_circle(center, Geom::Vector3d.new(0, 0, 1), diam_mm.mm / 2.0, 24)
    # `add_circle` YA crea automáticamente la carita del círculo -al quedar
    # coplanar y contenida en la cara superior de la placa-, por eso un
    # `add_face` explícito aquí devolvía nil (la cara ya existía). Hay que
    # tomar esa carita -la más chica de las dos que comparten el borde del
    # círculo- y empujarla hacia adentro del material para perforar.
    disc_face = circle_edges.first.faces.min_by(&:area)
    raise "no se encontró la cara del círculo en (#{center_x_mm}, #{center_y_mm})" unless disc_face
    distance = disc_face.normal.z >= 0 ? -thickness_mm.mm : thickness_mm.mm
    disc_face.pushpull(distance)
  end

  # Dibuja un disco -en un `entities` recién creado, no coplanar con nada
  # todavía- y lo extruye. `add_circle` aquí NO auto-crea la cara -no hay
  # ninguna cara existente con la que fusionarse-, así que sí hay que
  # llamar `add_face` explícito.
  def extrude_disc(entities, base_point, diam_mm, height_mm)
    circle_edges = entities.add_circle(base_point, Geom::Vector3d.new(0, 0, 1), diam_mm.mm / 2.0, 16)
    disc_face = circle_edges.first.faces.min_by(&:area) || entities.add_face(circle_edges)
    raise "no se pudo crear el disco en #{base_point}" unless disc_face
    disc_face.reverse! if disc_face.normal.z < 0
    disc_face.pushpull(height_mm.mm)
  end

  # Autorroscantes -fijan la solera a la estructura- cerca de cada extremo.
  AUTORROSCANTE_POSITIONS_MM.each do |x, y|
    punch_hole(entities, x, y, AUTORROSCANTE_HOLE_DIAM_MM, SOLERA_THICKNESS_MM)
  end

  # Pija de madera #8 al centro -sujeta lo que va encima, apuntando hacia arriba-.
  PIJA_POSITIONS_MM.each do |x, y|
    punch_hole(entities, x, y, PIJA8_HOLE_DIAM_MM, SOLERA_THICKNESS_MM)
  end

  # OJO: `IDENTITY` no existe como constante en la API de Ruby de SketchUp
  # -ese era el bug de la v1: la definición se creaba pero nunca se
  # insertaba en el modelo porque esta línea reventaba con NameError-.
  instance = model.active_entities.add_instance(definition, Geom::Transformation.new)
  raise 'add_instance devolvió nil' unless instance
  instance.name = 'SOLERA-1IN-TEST'

  placed = [instance]

  # Tornillos autorroscantes -cabeza ARRIBA de la placa, vástago atraviesa
  # el agujero y sigue bajando hacia donde estaría la estructura-.
  AUTORROSCANTE_POSITIONS_MM.each_with_index do |(x, y), i|
    screw = model.active_entities.add_group
    base_top = Geom::Point3d.new(x.mm, y.mm, 0)
    extrude_disc(screw.entities, base_top, AUTORROSCANTE_HEAD_DIAM_MM, AUTORROSCANTE_HEAD_THICKNESS_MM)
    extrude_disc(screw.entities, base_top, AUTORROSCANTE_SHAFT_DIAM_MM, -AUTORROSCANTE_LENGTH_MM)
    screw.name = "TORNILLO-AUTORROSCANTE-#{i + 1}"
    placed << screw
  end

  # Pija de madera #8 al centro -cabeza DEBAJO de la placa, vástago
  # atraviesa el agujero y apunta hacia arriba, sobresaliendo por encima-.
  PIJA_POSITIONS_MM.each_with_index do |(x, y), i|
    screw = model.active_entities.add_group
    base_bottom = Geom::Point3d.new(x.mm, y.mm, -SOLERA_THICKNESS_MM.mm)
    extrude_disc(screw.entities, base_bottom, PIJA8_HEAD_DIAM_MM, -PIJA8_HEAD_THICKNESS_MM)
    extrude_disc(screw.entities, base_bottom, PIJA8_SHAFT_DIAM_MM, PIJA8_LENGTH_MM)
    screw.name = "TORNILLO-PIJA8-#{i + 1}"
    placed << screw
  end

  model.commit_operation
  model.selection.clear
  placed.each { |p| model.selection.add(p) }
  model.active_view.zoom(placed)

  puts '✅ Solera de prueba creada con sus 4 tornillos -medidas en mm, ESTIMADO salvo lo marcado-:'
  puts "   Ancho: #{SOLERA_WIDTH_MM}mm (1\") -CONFIRMADO"
  puts "   Largo: #{SOLERA_LENGTH_MM}mm -ESTIMADO"
  puts "   Espesor: #{SOLERA_THICKNESS_MM}mm -ESTIMADO"
  puts "   Autorroscante: Ø vástago #{AUTORROSCANTE_SHAFT_DIAM_MM}mm x #{AUTORROSCANTE_LENGTH_MM}mm (1 1/2\") -largo CONFIRMADO, diámetros ESTIMADO-"
  puts "   Pija #8: Ø vástago #{PIJA8_SHAFT_DIAM_MM}mm x #{PIJA8_LENGTH_MM}mm -TODO ESTIMADO, no me diste el largo-"
rescue StandardError => e
  model.abort_operation rescue nil
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(8)
end
nil
