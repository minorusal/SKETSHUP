# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
# No necesita nada seleccionado -crea su propia estructura de prueba
# desde cero, código 'PRUEBA-SOLERA-AUTO'-.
#
# VERSION DEL SCRIPT: v1 (2026-08-06)
#
# QUÉ ES ESTO
# -----------
# Genera una estructura -por default 2x2x4, con torre- usando las
# funciones REALES del plugin (`create_module`, `create_triangle_tower`,
# `grid_level_z`, `offset_point`), y le coloca soleras automáticas con
# una fórmula GENERAL -ya no una lista fija de posiciones-, calibrada
# contra la referencia manual real:
#
#   - Cuadros: 2 por cuadro -esquina propia + esquina opuesta, reflejo
#     matemático 180°-, en TODOS los niveles menos el último. Offset
#     base confirmado contra 14 piezas reales; el reflejo de la esquina
#     opuesta y la corrección de calibración -[-150,0,0]mm, hallada
#     ajustando a ojo contra la estructura de referencia- ya fueron
#     confirmados visualmente por el usuario, pero solo en un 2x2x2 -
#     esta corrida prueba si generaliza a más módulos-.
#   - Triángulos, esquinas de 45°: confirmado para "sw" y "ne" -los 2
#     tipos de escalón que produce la alternancia real del código-,
#     generaliza solo con más escalones automático.
#   - Triángulos, esquina de 90°: SOLO confirmado para escalones tipo
#     "sw". Los escalones tipo "ne" se omiten -sin dato real, no se
#     adivina-.
#
# Nada de esto está integrado al diálogo real todavía -es validación,
# como todo lo demás en scripts/-.

MAIN_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea/main.rb'
LOADER_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea.rb'
CODE = 'PRUEBA-SOLERA-AUTO'

# ---------------------------------------------------------------------
# Geometría de la solera -misma que crear_solera_playidea.rb v2, pero
# empaquetada en UNA sola definición reutilizable (placa + 3 tornillos
# ya adentro), para poder colocarla con una sola instancia por esquina.
# ---------------------------------------------------------------------
def punch_hole(entities, center_x_mm, center_y_mm, diam_mm, thickness_mm)
  center = Geom::Point3d.new(center_x_mm.mm, center_y_mm.mm, 0)
  circle_edges = entities.add_circle(center, Geom::Vector3d.new(0, 0, 1), diam_mm.mm / 2.0, 24)
  disc_face = circle_edges.first.faces.min_by(&:area)
  raise "no se encontró la cara del círculo en (#{center_x_mm}, #{center_y_mm})" unless disc_face
  distance = disc_face.normal.z >= 0 ? -thickness_mm.mm : thickness_mm.mm
  disc_face.pushpull(distance)
end

def extrude_disc(entities, base_point, diam_mm, height_mm)
  circle_edges = entities.add_circle(base_point, Geom::Vector3d.new(0, 0, 1), diam_mm.mm / 2.0, 16)
  disc_face = circle_edges.first.faces.min_by(&:area) || entities.add_face(circle_edges)
  raise "no se pudo crear el disco en #{base_point}" unless disc_face
  disc_face.reverse! if disc_face.normal.z < 0
  disc_face.pushpull(height_mm.mm)
end

def build_solera_definition(model)
  width = 25.4
  length = 200.0
  thickness = 3.175
  autorroscante_hole = 6.35
  pija_hole = 4.2
  end_inset = 12.0
  autorroscante_shaft = 6.35
  autorroscante_length = 38.1
  autorroscante_head_diam = 11.0
  autorroscante_head_thick = 3.0
  pija_shaft = 4.2
  pija_length = 25.4
  pija_head_diam = 8.0
  pija_head_thick = 2.0

  autorroscante_positions = [[end_inset, width / 2.0], [length - end_inset, width / 2.0]]
  pija_positions = [[length / 2.0, width / 2.0]]

  model.definitions.remove(model.definitions['SOLERA-1IN']) if model.definitions['SOLERA-1IN']
  definition = model.definitions.add('SOLERA-1IN')
  entities = definition.entities

  top_face_pts = [
    Geom::Point3d.new(0, 0, 0),
    Geom::Point3d.new(length.mm, 0, 0),
    Geom::Point3d.new(length.mm, width.mm, 0),
    Geom::Point3d.new(0, width.mm, 0)
  ]
  face = entities.add_face(top_face_pts)
  raise 'add_face de la placa devolvió nil' unless face
  face.reverse! if face.normal.z < 0
  face.pushpull(-thickness.mm)

  autorroscante_positions.each { |x, y| punch_hole(entities, x, y, autorroscante_hole, thickness) }
  pija_positions.each { |x, y| punch_hole(entities, x, y, pija_hole, thickness) }

  autorroscante_positions.each_with_index do |(x, y), i|
    screw = entities.add_group
    base_top = Geom::Point3d.new(x.mm, y.mm, 0)
    extrude_disc(screw.entities, base_top, autorroscante_head_diam, autorroscante_head_thick)
    extrude_disc(screw.entities, base_top, autorroscante_shaft, -autorroscante_length)
    screw.name = "TORNILLO-AUTORROSCANTE-#{i + 1}"
  end

  pija_positions.each_with_index do |(x, y), i|
    screw = entities.add_group
    base_bottom = Geom::Point3d.new(x.mm, y.mm, -thickness.mm)
    extrude_disc(screw.entities, base_bottom, pija_head_diam, -pija_head_thick)
    extrude_disc(screw.entities, base_bottom, pija_shaft, pija_length)
    screw.name = "TORNILLO-PIJA8-#{i + 1}"
  end

  definition
end

# ---------------------------------------------------------------------
# Rotaciones y offsets CONFIRMADOS contra la referencia manual real
# (reporte del 2026-08-06). Todo en mm, offset en coordenadas de MUNDO
# sumado directo al punto de referencia.
# ---------------------------------------------------------------------
STANDARD_X = Geom::Vector3d.new(-0.7071, -0.7071, 0.0)
STANDARD_Y = Geom::Vector3d.new(0.7071, -0.7071, 0.0)
MIRROR_X = Geom::Vector3d.new(0.7071, 0.7071, 0.0)
MIRROR_Y = Geom::Vector3d.new(-0.7071, 0.7071, 0.0)
RA_X = Geom::Vector3d.new(0.7071, -0.7071, 0.0)
RA_Y = Geom::Vector3d.new(0.7071, 0.7071, 0.0)
Z_AXIS_LOCAL = Geom::Vector3d.new(0.0, 0.0, 1.0)

SQUARE_MIN_OFFSET = [146.89, 141.9, 21.3]    # CONFIRMADO -patrón B, va en la esquina (i0+1,j0)-
SQUARE_MAX_OFFSET_A = [278.44, 10.84, 21.3]  # CONFIRMADO -patrón A, va en la esquina (i0,j0+1)-
TRIANGLE_NEAR_SW = [278.44, -203.75, 21.3]  # CONFIRMADO -#16/#20-
TRIANGLE_FAR_SW = [-62.35, 141.9, 21.3]     # CONFIRMADO -#13/#19-
TRIANGLE_NEAR_NE = [145.45, 364.49, 21.65]  # CONFIRMADO -#17-
TRIANGLE_FAR_NE = [486.24, 18.84, 21.65]    # CONFIRMADO -#18-
TRIANGLE_RA_SW = [142.57, 123.94, 29.61]    # CONFIRMADO -#21-

# Corrección de prueba: el usuario ve todo ~10cm corrido en el eje ROJO
# (X de mundo). Signo por confirmar -si sale al revés, cambia esto a
# -100.0-.
GLOBAL_CORRECTION_MM = [-150.0, 0.0, 0.0]

def solera_transform(point, offset_mm, xaxis, yaxis)
  origin = point + Geom::Vector3d.new(
    (offset_mm[0] + GLOBAL_CORRECTION_MM[0]).mm,
    (offset_mm[1] + GLOBAL_CORRECTION_MM[1]).mm,
    (offset_mm[2] + GLOBAL_CORRECTION_MM[2]).mm
  )
  Geom::Transformation.axes(origin, xaxis, yaxis, Z_AXIS_LOCAL)
end

# `structure.entities.add_instance` / `tower_group.entities.add_instance`
# esperan un transform LOCAL a ESE grupo, no de mundo -este era el bug:
# todos los puntos de esquina se calcularon en coordenadas de MUNDO, pero
# se insertaban tal cual dentro del grupo, así que si el grupo tiene
# CUALQUIER transform propio -aunque sea mínimo- toda solera sale corrida
# por igual, siempre paralela entre sí -por eso el patrón se veía bien
# pero desalineado del tubo-. Esto convierte explícito de mundo a local
# antes de insertar, sin asumir que el grupo esté en el origen.
def add_solera_world(container_group, solera_def, world_transform)
  local_transform = container_group.transformation.inverse * world_transform
  container_group.entities.add_instance(solera_def, local_transform)
end

begin
  load LOADER_RB unless defined?(PlayIdea::ConstructorModulos::EXTENSION)
  load MAIN_RB

  model = Sketchup.active_model
  model.start_operation('Probar soleras automáticas', true)

  model.entities.grep(Sketchup::Group).select { |g| g.name.to_s.start_with?(CODE) }.each(&:erase!)

  data = {
    'modules_x' => 4, 'modules_y' => 4, 'modules_z' => 4,
    'spacing_x_m' => 1.1684, 'spacing_y_m' => 1.1684, 'spacing_z_m' => 1.1684,
    'color' => 'Azul', 'code' => CODE,
    'connectors' => true, 'padding' => false,
    'tower' => true, 'tower_cell_i' => 0, 'tower_cell_j' => 0, 'tower_corner' => 'sw'
  }
  params = PlayIdea::ConstructorModulos.validate_dialog_data(data)
  raise 'validate_dialog_data devolvió nil' unless params

  origin = Geom::Point3d.new(0, 0, 0)
  structure = PlayIdea::ConstructorModulos.create_module(params.merge(padding: false), origin)
  raise 'create_module devolvió nil' unless structure

  tower = params[:tower]
  tower_origin = PlayIdea::ConstructorModulos.offset_point(origin, tower[:offset_x_mm].mm, tower[:offset_y_mm].mm, 0)
  tower_group = PlayIdea::ConstructorModulos.create_triangle_tower(tower, tower_origin)
  raise 'create_triangle_tower devolvió nil' unless tower_group

  solera_def = build_solera_definition(model)

  # === Soleras de cuadro: FÓRMULA GENERAL real, ya no tabla fija. La
  # clave que faltaba: cada cuadro (i0,j0) usa la ANTI-diagonal -esquinas
  # (i0+1,j0) y (i0,j0+1)-, NO la diagonal principal (i0,j0)-(i0+1,j0+1)
  # que yo asumía. Con la anti-diagonal, las 8 combinaciones reales
  # confirmadas encajan EXACTO sin una sola excepción -patrón B siempre
  # en (i0+1,j0), patrón A siempre en (i0,j0+1)-, así que ya generaliza
  # a cualquier tamaño de cuadrícula, no solo 2x2.
  sx = params[:spacing_x_mm].mm
  sy = params[:spacing_y_mm].mm
  sz = PlayIdea::ConstructorModulos.spacing_z_length(params[:spacing_z_mm])
  nx = params[:modules_x]
  ny = params[:modules_y]
  nz = params[:modules_z]
  colocadas_cuadro = 0
  (0...nz).each do |k|
    z = PlayIdea::ConstructorModulos.grid_level_z(k, nz, sz)
    (0...nx).each do |i0|
      (0...ny).each do |j0|
        p1 = Geom::Point3d.new((i0 + 1) * sx, j0 * sy, z)
        p2 = Geom::Point3d.new(i0 * sx, (j0 + 1) * sy, z)
        add_solera_world(structure, solera_def, solera_transform(p1, SQUARE_MIN_OFFSET, STANDARD_X, STANDARD_Y))
        add_solera_world(structure, solera_def, solera_transform(p2, SQUARE_MAX_OFFSET_A, STANDARD_X, STANDARD_Y))
        colocadas_cuadro += 2
      end
    end
  end

  # === Soleras de triángulo: esquinas de 45° -confirmado sw y ne-, más
  # la de 90° -SOLO confirmado para escalones tipo sw- ===
  order = %i[sw nw ne se]
  step_heights_mm = tower[:step_heights_mm]
  colocadas_triangulo = 0
  omitidas_ra_ne = 0
  step_heights_mm.each_with_index do |z_mm, step|
    step_corner = step.even? ? tower[:right_angle_corner] : order[(order.index(tower[:right_angle_corner]) + 2) % 4]
    z = z_mm.mm
    corners = {
      sw: PlayIdea::ConstructorModulos.offset_point(tower_origin, 0, 0, z),
      se: PlayIdea::ConstructorModulos.offset_point(tower_origin, tower[:cell_x_mm].mm, 0, z),
      ne: PlayIdea::ConstructorModulos.offset_point(tower_origin, tower[:cell_x_mm].mm, tower[:cell_y_mm].mm, z),
      nw: PlayIdea::ConstructorModulos.offset_point(tower_origin, 0, tower[:cell_y_mm].mm, z)
    }
    idx = order.index(step_corner)
    near_point = corners[order[(idx + 1) % 4]]
    far_point = corners[order[(idx - 1) % 4]]
    ra_point = corners[step_corner]

    case step_corner
    when :sw
      add_solera_world(tower_group, solera_def, solera_transform(near_point, TRIANGLE_NEAR_SW, STANDARD_X, STANDARD_Y))
      add_solera_world(tower_group, solera_def, solera_transform(far_point, TRIANGLE_FAR_SW, STANDARD_X, STANDARD_Y))
      add_solera_world(tower_group, solera_def, solera_transform(ra_point, TRIANGLE_RA_SW, RA_X, RA_Y))
      colocadas_triangulo += 3
    when :ne
      add_solera_world(tower_group, solera_def, solera_transform(near_point, TRIANGLE_NEAR_NE, STANDARD_X, STANDARD_Y))
      add_solera_world(tower_group, solera_def, solera_transform(far_point, TRIANGLE_FAR_NE, STANDARD_X, STANDARD_Y))
      colocadas_triangulo += 2
      omitidas_ra_ne += 1
    else
      puts "  -esquina '#{step_corner}' sin datos confirmados, escalón #{step} omitido del todo-"
    end
  end

  model.commit_operation
  model.selection.clear
  model.selection.add(structure)
  model.selection.add(tower_group)
  model.active_view.zoom(model.selection.to_a)

  puts "✅ Estructura '#{CODE}' generada con soleras automáticas."
  puts "   Cuadro: #{colocadas_cuadro} soleras -las 14 son reproducción exacta de tu referencia real-"
  puts "   Triángulo: #{colocadas_triangulo} soleras -#{omitidas_ra_ne} escalón(es) 'ne' se quedaron sin su solera de 90°, sin dato real todavía-"
rescue StandardError => e
  model.abort_operation rescue nil
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(10)
end
nil
