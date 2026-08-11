# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# VERSION DEL SCRIPT: v3 -orden de operandos de subtract corregido- (2026-08-05)
#
# SEGUNDO INTENTO -el primero, con `Face#followme` para tallar el canal,
# salió mal: en las vueltas de 90° la geometría del barrido no queda
# sólida de forma limpia, así que la resta booleana fallaba y se comía el
# panel entero, dejando solo el canal flotando (confirmado con una
# captura real: sin panel, solo el tubo verde suelto)-.
#
# Esta versión arma el canal de otra forma, mucho más robusta: como una
# cadena de CAJAS rectangulares simples -una por tramo recto del zigzag,
# cada una alargada medio-ancho-del-canal más allá de sus dos puntas, así
# que las cajas vecinas se solapan solas exactamente en cada esquina, sin
# necesitar geometría especial de remate-. Las cajas son la forma más
# simple y confiable posible para SketchUp -cero riesgo de auto-
# intersección-. Se unen todas en un solo sólido con `union`, y ESE sólido
# sí se resta del panel con `subtract`.
#
# No modifica nada existente: crea todo dentro de un grupo nuevo, en el
# origen del modelo.

SCRIPT_VERSION = 'v3 -orden de operandos de subtract corregido- (2026-08-05)'
puts "▶️  Corriendo panel_laberinto_cuentas.rb #{SCRIPT_VERSION}"

model = Sketchup.active_model
model.start_operation('Panel Laberinto de Cuentas (prueba 2)', true)

begin
  entities = model.active_entities

  # ─────────────────────────────────────────────
  # Medidas del panel -ajustables-
  # ─────────────────────────────────────────────
  PANEL_ANCHO_MM = 500.0
  PANEL_ALTO_MM = 500.0
  PANEL_GROSOR_MM = 18.0   # grosor típico de MDF
  CANAL_ANCHO_MM = 14.0
  CANAL_PROFUNDIDAD_MM = 7.0
  CUENTA_DIAMETRO_MM = 30.0

  COLOR_PANEL = Sketchup::Color.new(0x9A, 0xD4, 0x2A)   # verde lima, como la foto
  COLORES_CUENTAS = [
    Sketchup::Color.new(0xE8, 0x2A, 0x2A), # rojo
    Sketchup::Color.new(0xF2, 0xC7, 0x1B), # amarillo
    Sketchup::Color.new(0x2E, 0xA6, 0x3D), # verde
    Sketchup::Color.new(0x1B, 0x22, 0x3A)  # azul marino / negro
  ]

  # Ruta del laberinto en XY (mm) -SOLO tramos horizontales/verticales,
  # a propósito: así cada tramo se puede armar como una caja simple sin
  # necesitar rotarla-. Zigzag genérico, no calcado de la foto de catálogo.
  RUTA_XY_MM = [
    [70, 430], [210, 430], [210, 300], [360, 300], [360, 430],
    [430, 430], [430, 200], [150, 200], [150, 70], [430, 70]
  ]

  # ─────────────────────────────────────────────
  # Helper: esfera sólida -mismo generador UV-sphere que
  # alberca_pelotas_playidea-.
  # ─────────────────────────────────────────────
  def add_sphere(entities, diameter_mm, segments = 16)
    radius = (diameter_mm / 2.0).mm
    rings = [segments / 2, 3].max
    points = (0..rings).map do |i|
      lat = (Math::PI * i / rings) - (Math::PI / 2.0)
      z = radius * Math.sin(lat)
      ring_radius = radius * Math.cos(lat)
      segments.times.map do |j|
        lon = 2 * Math::PI * j / segments.to_f
        Geom::Point3d.new(ring_radius * Math.cos(lon), ring_radius * Math.sin(lon), z)
      end
    end
    (0...rings).each do |i|
      segments.times do |j|
        j2 = (j + 1) % segments
        a, b = points[i][j], points[i][j2]
        c, d = points[i + 1][j2], points[i + 1][j]
        if i.zero?
          entities.add_face(a, c, d) unless a == c || a == d || c == d
        elsif i == rings - 1
          entities.add_face(a, b, c) unless a == b || a == c || b == c
        else
          entities.add_face(a, b, c, d)
        end
      end
    end
  end

  # ─────────────────────────────────────────────
  # Helper: una caja sólida axis-aligned, como grupo aparte -para poder
  # unirla/restarla luego-.
  # ─────────────────────────────────────────────
  def add_box(parent_entities, min_x, min_y, min_z, max_x, max_y, max_z)
    group = parent_entities.add_group
    ge = group.entities
    pts = [
      Geom::Point3d.new(min_x, min_y, min_z),
      Geom::Point3d.new(max_x, min_y, min_z),
      Geom::Point3d.new(max_x, max_y, min_z),
      Geom::Point3d.new(min_x, max_y, min_z)
    ]
    face = ge.add_face(pts)
    face.reverse! if face.normal.z < 0
    face.pushpull(max_z - min_z)
    group
  end

  # ─────────────────────────────────────────────
  # 1. Panel base -bloque sólido-
  # ─────────────────────────────────────────────
  panel_group = add_box(entities, 0, 0, 0, PANEL_ANCHO_MM.mm, PANEL_ALTO_MM.mm, PANEL_GROSOR_MM.mm)
  panel_group.name = 'Panel base'

  # ─────────────────────────────────────────────
  # 2. Canal del laberinto -una caja por tramo recto, alargada medio-ancho
  #    del canal más allá de sus dos puntas para que las cajas vecinas se
  #    solapen solas en cada esquina-, unidas en un solo sólido y restado
  #    del panel.
  # ─────────────────────────────────────────────
  ruta_puntos = RUTA_XY_MM.map { |x, y| [x.mm, y.mm] }
  medio_ancho = (CANAL_ANCHO_MM / 2.0).mm
  # El canal se hunde CANAL_PROFUNDIDAD_MM desde la cara superior, y se
  # extiende 2mm POR ENCIMA de esa cara -para atravesarla limpio, sin
  # dejar caras exactamente coplanares que puedan confundir la resta-.
  canal_z_min = (PANEL_GROSOR_MM - CANAL_PROFUNDIDAD_MM).mm
  canal_z_max = (PANEL_GROSOR_MM + 2.0).mm

  cajas_canal = ruta_puntos.each_cons(2).map do |(xa, ya), (xb, yb)|
    min_x = [xa, xb].min - medio_ancho
    max_x = [xa, xb].max + medio_ancho
    min_y = [ya, yb].min - medio_ancho
    max_y = [ya, yb].max + medio_ancho
    add_box(entities, min_x, min_y, canal_z_min, max_x, max_y, canal_z_max)
  end

  # Diagnóstico de las piezas de ANTES de la resta -el subtract borra
  # panel_group y canal_final, así que hay que anotar sus datos ahora-.
  panel_bounds_antes = panel_group.bounds
  panel_solido_antes = panel_group.manifold?

  canal_final = cajas_canal.shift
  cajas_canal.each { |caja| canal_final = canal_final.union(caja) }
  canal_final.name = 'Canal (temporal)'
  canal_bounds = canal_final.bounds
  canal_solido = canal_final.manifold?
  canal_caras = canal_final.entities.grep(Sketchup::Face).count

  # OJO: en esta instalación de SketchUp, `A.subtract(B)` da como resultado
  # "B menos A" -al revés de lo que dice la documentación oficial-. Lo
  # comprobamos con el reporte de la corrida anterior: pedimos
  # panel_group.subtract(canal_final) esperando "panel menos canal", y lo
  # que salió fue exactamente "canal menos panel" -un fragmento de
  # 374x374x2mm en Z 18-20mm, calcadito a la huella del canal en la franja
  # de 2mm que sobresale arriba del panel-. Por eso aquí invertimos el
  # orden de los operandos.
  panel_con_canal = canal_final.subtract(panel_group)
  raise 'La resta booleana devolvió vacío -revisa si el canal quedó fuera del panel.' unless panel_con_canal

  ancho_resultado = panel_con_canal.bounds.width.to_mm
  alto_resultado = panel_con_canal.bounds.height.to_mm
  if ancho_resultado < PANEL_ANCHO_MM * 0.9 || alto_resultado < PANEL_ALTO_MM * 0.9
    raise "La resta dio un resultado de #{ancho_resultado.round(1)}x#{alto_resultado.round(1)}mm, " \
      "mucho más chico que el panel (#{PANEL_ANCHO_MM}x#{PANEL_ALTO_MM}mm) -sigue invertida la resta, revisar orden de operandos-."
  end

  panel_con_canal.name = 'Panel Laberinto de Cuentas'

  material_panel = model.materials['Panel Laberinto - Verde'] || model.materials.add('Panel Laberinto - Verde')
  material_panel.color = COLOR_PANEL
  panel_con_canal.entities.grep(Sketchup::Face).each do |cara|
    cara.material = material_panel
    cara.back_material = material_panel
  end

  # ─────────────────────────────────────────────
  # 3. Cuentas de colores -esferas apoyadas en el piso del canal, en cada
  #    vértice de la ruta-.
  # ─────────────────────────────────────────────
  cuentas_group = entities.add_group
  cuentas_group.name = 'Cuentas'
  cue = cuentas_group.entities

  material_cache = {}
  color_definition_cache = {}
  cuenta_centro_z = (PANEL_GROSOR_MM - CANAL_PROFUNDIDAD_MM + (CUENTA_DIAMETRO_MM / 2.0)).mm

  RUTA_XY_MM.each_with_index do |xy, n|
    color = COLORES_CUENTAS[n % COLORES_CUENTAS.length]
    hex = color.to_a[0..2].map { |v| v.to_s(16).rjust(2, '0') }.join

    definition = color_definition_cache[hex] ||= begin
      d = model.definitions.add("CUENTA-#{hex}")
      add_sphere(d.entities, CUENTA_DIAMETRO_MM)
      mat = material_cache[hex] ||= (model.materials["Cuenta - ##{hex}"] || model.materials.add("Cuenta - ##{hex}"))
      mat.color = color
      d.entities.grep(Sketchup::Face).each { |f| f.material = mat; f.back_material = mat }
      d
    end

    centro = Geom::Point3d.new(xy[0].mm, xy[1].mm, cuenta_centro_z)
    cue.add_instance(definition, Geom::Transformation.translation(centro))
  end

  model.selection.clear
  model.selection.add(panel_con_canal)
  model.selection.add(cuentas_group)
  model.commit_operation

  # ─────────────────────────────────────────────
  # Reporte de diagnóstico -copia y pega TODO este bloque de vuelta-.
  # ─────────────────────────────────────────────
  panel_bounds_despues = panel_con_canal.bounds
  panel_caras_despues = panel_con_canal.entities.grep(Sketchup::Face).count
  panel_aristas_despues = panel_con_canal.entities.grep(Sketchup::Edge).count
  panel_solido_despues = panel_con_canal.manifold?
  cuentas_bounds = cuentas_group.bounds

  def fmt_bounds(b)
    "min(#{b.min.x.to_mm.round(1)}, #{b.min.y.to_mm.round(1)}, #{b.min.z.to_mm.round(1)})mm  " \
      "max(#{b.max.x.to_mm.round(1)}, #{b.max.y.to_mm.round(1)}, #{b.max.z.to_mm.round(1)})mm  " \
      "tamaño(#{b.width.to_mm.round(1)} x #{b.height.to_mm.round(1)} x #{b.depth.to_mm.round(1)})mm"
  end

  puts "✅ Listo (#{SCRIPT_VERSION}). Panel #{PANEL_ANCHO_MM}x#{PANEL_ALTO_MM}mm con canal de #{CANAL_ANCHO_MM}mm de ancho y #{RUTA_XY_MM.length} cuentas."
  puts "----- REPORTE DE GEOMETRÍA -----"
  puts "1) Panel ANTES de restar el canal:"
  puts "   sólido? #{panel_solido_antes} | #{fmt_bounds(panel_bounds_antes)}"
  puts "2) Canal (unión de #{RUTA_XY_MM.length - 1} cajas):"
  puts "   sólido? #{canal_solido} | caras: #{canal_caras} | #{fmt_bounds(canal_bounds)}"
  puts "3) Panel DESPUÉS de restar el canal -'#{panel_con_canal.name}'-:"
  puts "   sólido? #{panel_solido_despues} | caras: #{panel_caras_despues} | aristas: #{panel_aristas_despues}"
  puts "   #{fmt_bounds(panel_bounds_despues)}"
  puts "4) Cuentas -grupo '#{cuentas_group.name}', #{RUTA_XY_MM.length} instancias-:"
  puts "   #{fmt_bounds(cuentas_bounds)}"
  puts "5) Entidades sueltas en el nivel raíz del modelo: #{entities.count}"
  entities.each do |ent|
    next unless ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
    b = ent.bounds
    puts "   - #{ent.class.to_s.split('::').last} '#{ent.name}' | #{fmt_bounds(b)}"
  end
  puts "---------------------------------"
rescue StandardError => e
  model.abort_operation
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5)
end
nil
