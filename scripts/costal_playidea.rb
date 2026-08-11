# Script suelto (NO es un plugin instalable) para probar rápido la
# geometría del costal -rodillo relleno- sin reiniciar SketchUp: edita
# este archivo y en la Consola de Ruby -Window > Ruby Console- corre
#   load 'Documents/SKETCHUP/scripts/costal_playidea.rb'
# -o arrastra el archivo a la ventana de SketchUp-. Cada `load` vuelve a
# ejecutar el archivo completo, pregunta colores y coloca UN costal liso
# y UN costal caramelo lado a lado -para comparar los 2 acabados en el
# mismo clic-. PRIMER INTENTO -varias medidas están marcadas como
# PROVISIONAL más abajo, no hay foto/plano de referencia todavía para
# la costura/pegado, solo la descripción del usuario-.

Object.send(:remove_const, :PlayIdeaCostalScript) if defined?(PlayIdeaCostalScript)

module PlayIdeaCostalScript
  extend self

  DICTIONARY = 'playidea_costal'.freeze

  MM_PER_IN = 25.4

  # --- Medidas dadas por el usuario ---------------------------------------
  # "el rodillo mide 12 de diámetro" -dato directo, no derivado-.
  CYLINDER_DIAMETER_MM = 12.0 * MM_PER_IN # 304.8
  CYLINDER_RADIUS_MM = CYLINDER_DIAMETER_MM / 2.0

  # La lona real mide 44" x 36". SUPUESTO -a falta de plano-: el lado de
  # 36" es el LARGO del cilindro -coincide EXACTO con 36 discos de foam
  # de 1", ver FOAM_DISC_COUNT abajo, demasiado limpio para ser
  # casualidad- y el de 44" envuelve la circunferencia con margen de
  # costura -12" de diámetro da ~37.7" de circunferencia teórica
  # (π×12), los ~6.3" de sobra son costura/traslape del cilindro-. Si al
  # verlo en SketchUp el usuario dice que es al revés, se invierte fácil
  # -son 2 constantes-.
  LONA_WIDTH_IN = 44.0
  LONA_LENGTH_IN = 36.0
  CYLINDER_LENGTH_MM = LONA_LENGTH_IN * MM_PER_IN # 914.4

  # --- Medidas PROVISIONALES -no las dio el usuario, ajustar y volver a
  # cargar el script si se ven mal en SketchUp, mismo patrón que
  # CORNER_CHAMFER_MM en plataforma_playidea.rb- ------------------------
  CYLINDER_WALL_MM = 3.0 # grosor visual de la lona ya enrollada y cosida
  BASE_THICKNESS_MM = 3.0 # base cosida -lado permanente, disco liso a ras-
  CINTA_WIDTH_MM = 15.0 # cinta cosida al perímetro de la tapa -bastilla-
  CINTA_HEIGHT_MM = 2.0

  # Tapa desmontable -lado pegado con Plastigón-. SEGUNDA corrección del
  # usuario: "imagínate un bote de plástico con su tapa sin rosca, la
  # tapa es una taparrosca sin rosca... entra a la punta de la botella
  # sin roscar solo con presión" -un disco plano con esquina viva, la
  # primera corrección, TAMPOCO era correcto: una taparrosca real tiene
  # pared con grosor de verdad -no una lámina de una sola cara- y un
  # domo poco profundo y REDONDEADO arriba, no un disco plano-. Perfil
  # final: faldón de pared doble -grosor real de plástico- que se
  # resbala POR FUERA de la punta del tubo a presión, rematado arriba
  # por un domo poco profundo -mismo truco de perfil de cuarto de
  # círculo que `add_dome` en tornilleria_playidea.rb, ya probado ahí
  # para cabezas de tornillo/tapa bellota-, que se detiene justo en el
  # borde del hueco del poste -ver build_tapa_dome- en vez de cerrar en
  # una punta. Todas PROVISIONALES, sin medida real, ajustar y volver a
  # cargar.
  TAPA_THICKNESS_MM = 3.0 # grosor del plástico -faldón y domo-
  TAPA_CLEARANCE_MM = 1.5 # holgura del faldón contra el tubo, para que entre sin apretar
  TAPA_SKIRT_HEIGHT_MM = 25.0 # cuánto se mete el faldón sobre el cuerpo del tubo
  TAPA_OUTER_R_MM = CYLINDER_RADIUS_MM + TAPA_CLEARANCE_MM
  TAPA_DOME_RISE_MM = 20.0 # qué tanto se levanta el domo, perfil suave -no puntiagudo-

  # Perforación vertical al centro -pedido del usuario, corregido: NO es
  # el tubo estructural metálico, es un PVC de 2 1/2" el que atraviesa el
  # rodillo de lado a lado para montarlo en un poste. SUPUESTO -el
  # usuario dio la medida NOMINAL, "2 1/2 pulgadas", que es la forma
  # normal de pedir tubería PVC en ferretería-: se usa el diámetro
  # EXTERIOR real de PVC cédula 40 para esa nominal -2.875", 73.03mm-,
  # que es MAYOR que la medida nominal -convención estándar de tubería
  # de plomería, muy distinta de un tubo metálico donde "2 1/2" sería
  # literal-. Si el PVC real que usan mide otra cosa -cédula distinta,
  # o de verdad es 2.5" exactos-, avisar y se ajusta esta constante.
  PVC_POST_NOMINAL_IN = 2.5
  PVC_POST_OUTSIDE_MM = 73.03 # PVC cédula 40, diámetro exterior real de la nominal 2 1/2"
  POST_HOLE_CLEARANCE_MM = 2.0
  POST_HOLE_RADIUS_MM = (PVC_POST_OUTSIDE_MM / 2.0) + POST_HOLE_CLEARANCE_MM

  # PVC visible -pedido del usuario: "te faltó poner el tubo PVC"-: el
  # hueco central ya existía, pero faltaba dibujar el tubo de verdad
  # atravesando el costal, para verlo en su lugar. Asoma un tramo de
  # cada lado -PROVISIONAL, solo para que se note que atraviesa; en una
  # instalación real el mismo PVC seguiría más allá, hacia los postes de
  # la estructura-. Radio real del PVC -sin la holgura del hueco, que es
  # solo el espacio libre alrededor-, color gris claro típico de PVC.
  PVC_VISIBLE_OVERHANG_MM = 150.0
  PVC_RADIUS_MM = PVC_POST_OUTSIDE_MM / 2.0
  PVC_COLOR = Sketchup::Color.new(214, 214, 208).freeze

  # Discos de relleno: "el polyfoam es de 1 [pulgada]" -mismo material ya
  # dado de alta en la API de play-idea-explorer, "Polyfon" -buscar
  # ?q=polyfon-, entrada más reciente id 82 "Rollo De Polyfon De Pulg",
  # $6,200/rollo (2026-06-03)-, el MISMO polyfon que ya se usa para el
  # recubrimiento de tubos -ver constructor_modulos_playidea PADDING-,
  # aquí cortado en discos en vez de enrollado como manguera-. 36 discos
  # de 1" llenan EXACTO el largo de 36" del cilindro -confirma la
  # lectura de LONA_LENGTH_IN de arriba-.
  FOAM_DISC_THICKNESS_MM = 1.0 * MM_PER_IN # 25.4
  FOAM_DISC_COUNT = (CYLINDER_LENGTH_MM / FOAM_DISC_THICKNESS_MM).round # 36
  FOAM_DISC_CLEARANCE_MM = 2.0 # hueco visual contra la pared interior
  FOAM_DISC_RADIUS_MM = CYLINDER_RADIUS_MM - CYLINDER_WALL_MM - FOAM_DISC_CLEARANCE_MM
  FOAM_COLOR = Sketchup::Color.new(230, 225, 210).freeze

  # --- Variante "caramelo" -cintas diagonales tipo dulce de bastón------
  # Dato DIRECTO del usuario -corregido después de un primer "6 pulgadas"
  # que fue error suyo-: "las cintas son de 10 [pulgadas]", alternadas
  # 50/50 con el vinil visible -10" de cinta, 10" de cilindro, repite-,
  # medido a lo largo del eje. 1 vuelta completa a lo largo del cilindro
  # da ~45° de diagonal -972mm de circunferencia vs 914mm de largo, casi
  # 1:1-. A diferencia de cuando eran 6", 10" NO divide el largo del
  # tubo -914.4mm- en un número entero de períodos -914.4/508=1.8-, así
  # que el patrón se recorta -no cierra "parejo"- en vez de repetirse un
  # número exacto de veces; build_stripe_ribbons ya recorta cada franja
  # al rango real del tubo, así que esto no rompe nada, solo no es tan
  # "redondo" como con 6".
  CANDY_STRIPE_WIDTH_MM = 10.0 * MM_PER_IN # 254.0
  CANDY_PERIOD_MM = CANDY_STRIPE_WIDTH_MM * 2.0 # cinta + cilindro visible
  CANDY_TURNS = 1.0
  # Antes 1.0mm -"parece que esta al mismo nivel que el vinil"-: muy poco
  # separada de la pared de abajo, se veía como si compitiera por la
  # misma superficie en vez de estar encima. PROVISIONAL, ajustar a ojo.
  CANDY_STRIPE_RAISE_MM = 4.0

  # Costuras -pedido del usuario: "estaría bien más detalle de las
  # costuras... no tan recto todo"-. Cada línea de costura -recta o en
  # anillo- se dibuja como una fila de "cuentas" cortas con huecos entre
  # ellas -imitando puntadas de máquina de coser, no una línea continua
  # lisa-, ligeramente levantadas de la superficie. PROVISIONAL, sin
  # medida real, ajustar a ojo.
  STITCH_BEAD_LENGTH_MM = 6.0
  STITCH_GAP_MM = 4.0
  STITCH_BEAD_WIDTH_MM = 1.5
  STITCH_BEAD_RAISE_MM = 1.0
  STITCH_COLOR = Sketchup::Color.new(238, 233, 222).freeze # hilo -blanco hueso-

  VARIANT_SPACING_MM = CYLINDER_DIAMETER_MM + 300.0

  CODE_LISO = 'COSTAL-12X36-LISO'.freeze
  CODE_CARAMELO = 'COSTAL-12X36-CARAMELO'.freeze

  # Mismo catálogo de 8 colores que recubrimiento/tobogán -ver
  # constructor_modulos_playidea::STANDARD_COLOR_PALETTE-, repetido aquí
  # porque este es un script suelto sin ese require.
  STANDARD_COLOR_PALETTE = [
    { hex: 'FF0000', label: 'Rojo' },
    { hex: '84E311', label: 'Verde lima' },
    { hex: 'FFA400', label: 'Naranja' },
    { hex: '039CD4', label: 'Azul' },
    { hex: 'FFFF1E', label: 'Amarillo' },
    { hex: '11D9B4', label: 'Turquesa' },
    { hex: 'D911CB', label: 'Magenta' },
    { hex: '6E247D', label: 'Morado' }
  ].freeze

  def start
    labels = STANDARD_COLOR_PALETTE.map { |c| c[:label] }
    prompts = ['Color de la lona', 'Color de las cintas (caramelo)']
    defaults = [labels[3], labels[0]]
    lists = [labels.join('|'), labels.join('|')]
    values = UI.inputbox(prompts, defaults, lists, 'Crear costal Play Idea (rodillo Ø12" x 36") -liso + caramelo-')
    return unless values

    params = {
      lona_hex: STANDARD_COLOR_PALETTE.find { |c| c[:label] == values[0] }[:hex],
      stripe_hex: STANDARD_COLOR_PALETTE.find { |c| c[:label] == values[1] }[:hex]
    }
    Sketchup.active_model.select_tool(PlacementTool.new(params))
  rescue StandardError => error
    UI.messagebox("No fue posible iniciar el creador de costales:\n#{error.message}")
    puts error.full_message
  end

  # Coloca el liso en `base_point` y el caramelo justo al lado -mismo
  # patrón que VARIANT_SPACING_MM en tobogan_variedades_altura_playidea,
  # para comparar acabados en un solo clic-.
  def build_pair(params, base_point)
    model = Sketchup.active_model
    model.start_operation('Crear costales Play Idea (liso + caramelo)', true)
    liso = build_costal(model, base_point, params.merge(variant: 'liso'))
    caramelo_point = base_point.offset(X_AXIS, VARIANT_SPACING_MM.mm)
    caramelo = build_costal(model, caramelo_point, params.merge(variant: 'caramelo'))
    model.selection.clear
    model.selection.add(liso)
    model.selection.add(caramelo)
    model.commit_operation
    [liso, caramelo]
  rescue StandardError
    model.abort_operation
    raise
  end

  def build_costal(model, base_point, params)
    variant = params[:variant]
    code = variant == 'caramelo' ? CODE_CARAMELO : CODE_LISO

    definition = model.definitions.add(unique_definition_name(model, variant))
    entities = definition.entities

    build_tube_shell(entities, model, params[:lona_hex])
    build_stripe_ribbons(entities, model, params[:stripe_hex]) if variant == 'caramelo'
    # Base: cosida, lado permanente -disco liso a ras, se abre HACIA
    # ABAJO desde z=0-.
    build_cap(entities, model, 0.0, -BASE_THICKNESS_MM, params[:lona_hex])
    # Tapa: pegada con plastigón, lado desmontable para rellenar de foam
    # -"taparrosca sin rosca, entra a presión": faldón de pared doble +
    # domo redondeado arriba-. La cinta de tela queda como banda
    # decorativa justo donde el faldón se encuentra con el domo -ya no
    # hay un "disco plano" al que coserla, ver build_tapa_lid-.
    tapa_top_z = CYLINDER_LENGTH_MM + TAPA_SKIRT_HEIGHT_MM
    build_tapa_lid(entities, model, params[:lona_hex])
    build_cinta_ring(entities, model, tapa_top_z, params[:stripe_hex])
    build_foam_stack(entities, model)
    build_pvc_post(entities, model)

    # Costuras -pedido del usuario, "más detalle de las costuras, no tan
    # recto todo"-: unión base-cuerpo -anillo en z=0-, costura larga
    # donde se enrolló y cosió la lona -línea recta a lo largo del
    # cuerpo, a un ángulo fijo-, hilo de la cinta de la tapa -anillo en
    # el borde interior Y en el borde exterior de la cinta-, y bastilla
    # de las cintas caramelo -en sus 2 orillas, ver build_stripe_
    # stitches-. NO hay costura en la unión cuerpo-tapa: ese lado va
    # pegado con Plastigón, no cosido.
    build_stitch_ring(entities, model, 0.0, CYLINDER_RADIUS_MM)
    build_stitch_line_straight(entities, model, 0.0, CYLINDER_RADIUS_MM, 0.0, CYLINDER_LENGTH_MM)
    build_stitch_ring(entities, model, tapa_top_z, TAPA_OUTER_R_MM)
    build_stitch_ring(entities, model, tapa_top_z, TAPA_OUTER_R_MM + CINTA_WIDTH_MM)
    build_stripe_stitches(entities, model) if variant == 'caramelo'

    write_attributes(definition, params, code, variant)

    transform = Geom::Transformation.new(base_point)
    instance = model.active_entities.add_instance(definition, transform)
    instance.name = code
    write_attributes(instance, params, code, variant)
    instance
  end

  def unique_definition_name(model, variant)
    base = "Costal 12x36 #{variant == 'caramelo' ? 'Caramelo' : 'Liso'}"
    name = base
    index = 2
    while model.definitions[name]
      name = "#{base} (#{index})"
      index += 1
    end
    name
  end

  # --- Geometría -------------------------------------------------------
  # Mismo patrón YA probado y confirmado visualmente en tobogan_recto_
  # playidea.rb -circle_points/add_wall/add_ring, gajos explícitos en vez
  # de confiar en que SketchUp detecte solo el hueco de 2 círculos
  # concéntricos coplanares-. Ese truco de "2 círculos = anillo con
  # hueco automático" NO se usa en ninguna pieza ya validada de este
  # proyecto -se descartó a propósito ahí-, así que aquí tampoco: paredes
  # huecas siempre por 2 add_wall -exterior e interior- + add_ring en
  # cada extremo abierto.
  SEGMENTS = 48

  def circle_points(radius, z_value)
    SEGMENTS.times.map do |index|
      angle = (2.0 * Math::PI * index) / SEGMENTS
      Geom::Point3d.new(radius * Math.cos(angle), radius * Math.sin(angle), z_value)
    end
  end

  def add_wall(entities, radius, z0, z1)
    bottom = circle_points(radius, z0)
    top = circle_points(radius, z1)
    SEGMENTS.times do |index|
      following = (index + 1) % SEGMENTS
      entities.add_face(bottom[index], bottom[following], top[following], top[index])
    end
  end

  def add_ring(entities, inner_r, outer_r, z_value)
    if inner_r <= 0.mm
      center = Geom::Point3d.new(0, 0, z_value)
      outer = circle_points(outer_r, z_value)
      SEGMENTS.times { |index| entities.add_face(center, outer[index], outer[(index + 1) % SEGMENTS]) }
      return
    end
    inner = circle_points(inner_r, z_value)
    outer = circle_points(outer_r, z_value)
    SEGMENTS.times do |index|
      following = (index + 1) % SEGMENTS
      entities.add_face(outer[index], outer[following], inner[following], inner[index])
    end
  end

  # Pared cónica -radio DISTINTO en cada extremo, a diferencia de
  # add_wall-, para perfiles curvos aproximados por tramos rectos -ej.
  # el domo de la tapa-. Mismo truco de perfil que `add_dome` en
  # tornilleria_playidea.rb -ya probado ahí para cabezas de tornillo-,
  # pero SIEMPRE triangulado -2 triángulos, no 1 cuadrángulo- por la
  # misma razón que build_stripe_ribbons: con radios distintos en cada
  # extremo el cuadrángulo ya no es exactamente plano, y mejor no
  # arriesgarse a que SketchUp lo rechace.
  def add_cone_wall(entities, r0, r1, z0, z1)
    bottom = circle_points(r0, z0)
    top = circle_points(r1, z1)
    SEGMENTS.times do |index|
      following = (index + 1) % SEGMENTS
      [
        [bottom[index], bottom[following], top[following]],
        [bottom[index], top[following], top[index]]
      ].each { |points| entities.add_face(*points) }
    end
  end

  # Tubo hueco -pared exterior + pared interior, extremos abiertos- para
  # que el relleno de foam quede visible por dentro y las tapas se noten
  # como piezas aparte, no como un cilindro macizo.
  def build_tube_shell(entities, model, lona_hex)
    z0 = 0.mm
    z1 = CYLINDER_LENGTH_MM.mm
    outer = CYLINDER_RADIUS_MM.mm
    inner = (CYLINDER_RADIUS_MM - CYLINDER_WALL_MM).mm
    add_wall(entities, outer, z0, z1)
    add_wall(entities, inner, z0, z1)
    add_ring(entities, inner, outer, z0) # extremo base, lo cierra el cap
    add_ring(entities, inner, outer, z1) # extremo tapa, lo cierra el cap
    material = costal_material(model, 'Lona', lona_hex)
    paint_new_faces(entities, material)
  end

  # "Rondana gruesa" -disco con espesor real Y un hueco pasante al
  # centro-, mismo patrón que build_tube_shell -2 paredes + 2 anillos-
  # pero de un tramo corto. La reutilizan la base, el disco de arriba de
  # la tapa, y cada disco de foam -todos necesitan dejar pasar el poste
  # de estructura por el centro, ver POST_HOLE_RADIUS_MM-.
  def build_annulus_slab(entities, z0_mm, thickness_mm, outer_r_mm, inner_r_mm)
    z0 = z0_mm.mm
    z1 = (z0_mm + thickness_mm).mm
    outer = outer_r_mm.mm
    inner = inner_r_mm.mm
    add_wall(entities, outer, z0, z1)
    add_wall(entities, inner, z0, z1)
    add_ring(entities, inner, outer, z0)
    add_ring(entities, inner, outer, z1)
  end

  # Base: disco cosido a ras, con el hueco central del poste.
  def build_cap(entities, model, z_mm, thickness_mm, hex)
    build_annulus_slab(entities, z_mm, thickness_mm, CYLINDER_RADIUS_MM, POST_HOLE_RADIUS_MM)
    material = costal_material(model, 'Tapa', hex)
    paint_new_faces(entities, material)
  end

  def dome_profile(base_r_mm, rise_mm, hole_r_mm, z0_mm, steps)
    ratio = [[hole_r_mm / base_r_mm, 1.0].min, 0.0].max
    angle_stop = Math.acos(ratio)
    return [] if angle_stop < 0.02

    vertical_scale = rise_mm / Math.sin(angle_stop)
    (0..steps).map do |i|
      angle = (i.to_f / steps) * angle_stop
      [base_r_mm * Math.cos(angle), z0_mm + (vertical_scale * Math.sin(angle))]
    end
  end

  # Domo hueco con espesor real. Genera la cara exterior, la cara interior
  # desplazada TAPA_THICKNESS_MM y la pared circular del hueco; ambas caras
  # enlazan directamente con su pared correspondiente del faldón. El PVC
  # sigue pasando de lado a lado, pero la tapa ya no queda abierta.
  def build_tapa_dome(entities, outer_base_r_mm, inner_base_r_mm, rise_mm, hole_r_mm, z0_mm, steps: 8)
    outer_profile = dome_profile(outer_base_r_mm, rise_mm, hole_r_mm, z0_mm, steps)
    inner_z0_mm = z0_mm - TAPA_THICKNESS_MM
    inner_profile = dome_profile(inner_base_r_mm, rise_mm, hole_r_mm, inner_z0_mm, steps)
    return if outer_profile.empty? || inner_profile.empty?

    steps.times do |i|
      r0, z0i = outer_profile[i]
      r1, z1i = outer_profile[i + 1]
      add_cone_wall(entities, r0.mm, r1.mm, z0i.mm, z1i.mm)

      r0, z0i = inner_profile[i]
      r1, z1i = inner_profile[i + 1]
      add_cone_wall(entities, r1.mm, r0.mm, z1i.mm, z0i.mm)
    end

    _outer_hole_r, outer_hole_z = outer_profile.last
    _inner_hole_r, inner_hole_z = inner_profile.last
    add_wall(entities, hole_r_mm.mm, inner_hole_z.mm, outer_hole_z.mm)
  end

  # Tapa desmontable -"como la tapa de una botella, una taparrosca SIN
  # rosca, entra a presión"-: faldón de pared DOBLE -grosor real de
  # plástico, no una lámina de una sola cara- que se resbala por FUERA
  # del cuerpo del tubo -TAPA_OUTER_R_MM, más ancho que el tubo mismo,
  # para que "embone"-, rematado arriba por un domo poco profundo y
  # REDONDEADO -build_tapa_dome-, no un disco plano con esquina viva.
  def build_tapa_lid(entities, model, hex)
    skirt_z0 = CYLINDER_LENGTH_MM
    outer_skirt_z1 = CYLINDER_LENGTH_MM + TAPA_SKIRT_HEIGHT_MM
    inner_skirt_z1 = outer_skirt_z1 - TAPA_THICKNESS_MM
    outer_r = TAPA_OUTER_R_MM.mm
    inner_r = (TAPA_OUTER_R_MM - TAPA_THICKNESS_MM).mm
    add_wall(entities, outer_r, skirt_z0.mm, outer_skirt_z1.mm)
    add_wall(entities, inner_r, skirt_z0.mm, inner_skirt_z1.mm)
    add_ring(entities, inner_r, outer_r, skirt_z0.mm) # remate abierto del faldón, ras con la punta del tubo
    build_tapa_dome(
      entities,
      TAPA_OUTER_R_MM,
      TAPA_OUTER_R_MM - TAPA_THICKNESS_MM,
      TAPA_DOME_RISE_MM,
      POST_HOLE_RADIUS_MM,
      outer_skirt_z1
    )
    material = costal_material(model, 'Tapa', hex)
    paint_new_faces(entities, material)
  end

  # Cinta cosida al perímetro de la tapa -mismo patrón de pared hueca que
  # build_tube_shell, aquí un tramo corto-. La bastilla/costura en sí ya
  # SÍ se modela -ver build_stitch_ring, llamado aparte en build_costal-,
  # esto solo arma la cinta de tela. Envuelve la orilla REAL de la tapa
  # -TAPA_OUTER_R_MM, no el radio del cuerpo del tubo, porque la tapa es
  # más ancha para poder embonar por fuera-.
  def build_cinta_ring(entities, model, z_mm, hex)
    z0 = z_mm.mm
    z1 = (z_mm + CINTA_HEIGHT_MM).mm
    inner = TAPA_OUTER_R_MM.mm
    outer = (TAPA_OUTER_R_MM + CINTA_WIDTH_MM).mm
    add_wall(entities, outer, z0, z1)
    add_wall(entities, inner, z0, z1)
    add_ring(entities, inner, outer, z0)
    add_ring(entities, inner, outer, z1)
    material = costal_material(model, 'Cinta', hex)
    paint_new_faces(entities, material)
  end

  # Costura en ANILLO -alrededor de una circunferencia completa, ej. la
  # unión base-cuerpo, o el hilo que fija la cinta a la tapa-: fila de
  # cuentas cortas separadas por huecos -imita puntadas de máquina, no
  # una línea lisa-, apenas levantadas radialmente hacia afuera.
  def build_stitch_ring(entities, model, z_mm, radius_mm)
    circumference_mm = 2 * Math::PI * radius_mm
    period_mm = STITCH_BEAD_LENGTH_MM + STITCH_GAP_MM
    count = (circumference_mm / period_mm).floor
    return if count < 4

    material = costal_material(model, 'Hilo', nil, fixed_color: STITCH_COLOR)
    angular_step = 2 * Math::PI / count
    angular_bead = angular_step * (STITCH_BEAD_LENGTH_MM / period_mm)
    r_out = (radius_mm + STITCH_BEAD_RAISE_MM).mm
    half_h = (STITCH_BEAD_WIDTH_MM / 2.0).mm
    z0 = z_mm.mm - half_h
    z1 = z_mm.mm + half_h
    count.times do |i|
      theta_mid = i * angular_step
      a0 = theta_mid - (angular_bead / 2.0)
      a1 = theta_mid + (angular_bead / 2.0)
      p1 = Geom::Point3d.new(r_out * Math.cos(a0), r_out * Math.sin(a0), z0)
      p2 = Geom::Point3d.new(r_out * Math.cos(a1), r_out * Math.sin(a1), z0)
      p3 = Geom::Point3d.new(r_out * Math.cos(a1), r_out * Math.sin(a1), z1)
      p4 = Geom::Point3d.new(r_out * Math.cos(a0), r_out * Math.sin(a0), z1)
      face = entities.add_face(p1, p2, p3, p4)
      next unless face
      face.material = material
      face.back_material = material
    end
  end

  # Costura RECTA -a lo largo del eje, a un radio y ángulo fijos: la
  # unión donde la lona se enrolló y se cosió para formar el cilindro-.
  # Mismo patrón de cuentas con huecos que build_stitch_ring.
  def build_stitch_line_straight(entities, model, theta, radius_mm, z0_mm, z1_mm)
    length_mm = z1_mm - z0_mm
    period_mm = STITCH_BEAD_LENGTH_MM + STITCH_GAP_MM
    count = (length_mm / period_mm).floor
    return if count < 2

    material = costal_material(model, 'Hilo', nil, fixed_color: STITCH_COLOR)
    r_out = (radius_mm + STITCH_BEAD_RAISE_MM).mm
    half_w = (STITCH_BEAD_WIDTH_MM / 2.0).mm
    tx = -Math.sin(theta)
    ty = Math.cos(theta)
    base_x = r_out * Math.cos(theta)
    base_y = r_out * Math.sin(theta)
    count.times do |i|
      z_mid = z0_mm + ((i + 0.5) * period_mm)
      za = (z_mid - (STITCH_BEAD_LENGTH_MM / 2.0)).mm
      zb = (z_mid + (STITCH_BEAD_LENGTH_MM / 2.0)).mm
      p1 = Geom::Point3d.new(base_x - (tx * half_w), base_y - (ty * half_w), za)
      p2 = Geom::Point3d.new(base_x + (tx * half_w), base_y + (ty * half_w), za)
      p3 = Geom::Point3d.new(base_x + (tx * half_w), base_y + (ty * half_w), zb)
      p4 = Geom::Point3d.new(base_x - (tx * half_w), base_y - (ty * half_w), zb)
      face = entities.add_face(p1, p2, p3, p4)
      next unless face
      face.material = material
      face.back_material = material
    end
  end

  # Bastilla de las cintas caramelo -pedido del usuario: "también las
  # franjas de caramelo deben tener costura porque son con bastilla"-.
  # Recorre las MISMAS franjas -mismos `k`, mismo muestreo fino en
  # ángulo- que build_stripe_ribbons, pero en vez de pintar la
  # superficie completa solo deja una hilera de cuentas -mismo patrón
  # que build_stitch_ring- justo en cada orilla -z_lo y z_hi- de cada
  # franja visible.
  def build_stripe_stitches(entities, model)
    material = costal_material(model, 'Hilo', nil, fixed_color: STITCH_COLOR)
    r_out = (CYLINDER_RADIUS_MM + CANDY_STRIPE_RAISE_MM + STITCH_BEAD_RAISE_MM).mm
    angular_bead = STITCH_BEAD_LENGTH_MM / (CYLINDER_RADIUS_MM + CANDY_STRIPE_RAISE_MM)
    half_h = (STITCH_BEAD_WIDTH_MM / 2.0).mm
    theta_steps = SEGMENTS * 2
    unwind_max = CANDY_TURNS * CYLINDER_LENGTH_MM
    k_min = -((unwind_max / CANDY_PERIOD_MM).ceil + 1)
    k_max = (CYLINDER_LENGTH_MM / CANDY_PERIOD_MM).ceil + 1

    (k_min..k_max).each do |k|
      (0..theta_steps).each do |i|
        theta = i * (2 * Math::PI / theta_steps)
        unwind_mm = (theta / (2 * Math::PI)) * unwind_max
        z_lo = unwind_mm + (k * CANDY_PERIOD_MM)
        z_hi = z_lo + CANDY_STRIPE_WIDTH_MM
        [z_lo, z_hi].each do |z_edge|
          next unless z_edge.between?(0.0, CYLINDER_LENGTH_MM)

          a0 = theta - (angular_bead / 2.0)
          a1 = theta + (angular_bead / 2.0)
          z0 = z_edge.mm - half_h
          z1 = z_edge.mm + half_h
          p1 = Geom::Point3d.new(r_out * Math.cos(a0), r_out * Math.sin(a0), z0)
          p2 = Geom::Point3d.new(r_out * Math.cos(a1), r_out * Math.sin(a1), z0)
          p3 = Geom::Point3d.new(r_out * Math.cos(a1), r_out * Math.sin(a1), z1)
          p4 = Geom::Point3d.new(r_out * Math.cos(a0), r_out * Math.sin(a0), z1)
          face = entities.add_face(p1, p2, p3, p4)
          next unless face
          face.material = material
          face.back_material = material
        end
      end
    end
  end

  def foam_disc_definition(model)
    name = format(
      'PlayIdea Foam Disc OD%.2f-ID%.2f-T%.2f',
      FOAM_DISC_RADIUS_MM * 2.0,
      POST_HOLE_RADIUS_MM * 2.0,
      FOAM_DISC_THICKNESS_MM
    )
    existing = model.definitions[name]
    return existing if existing

    definition = model.definitions.add(name)
    build_annulus_slab(
      definition.entities,
      0.0,
      FOAM_DISC_THICKNESS_MM,
      FOAM_DISC_RADIUS_MM,
      POST_HOLE_RADIUS_MM
    )
    material = costal_material(model, 'Foam', nil, fixed_color: FOAM_COLOR)
    paint_new_faces(definition.entities, material)
    definition.set_attribute(DICTIONARY, 'type', 'foam_disc')
    definition
  end

  # Construye una sola definición perforada y coloca 36 instancias. Conserva
  # exactamente el relleno de 36" sin duplicar miles de caras en cada rodillo.
  def build_foam_stack(entities, model)
    definition = foam_disc_definition(model)
    FOAM_DISC_COUNT.times do |i|
      z0 = i * FOAM_DISC_THICKNESS_MM
      transform = Geom::Transformation.translation([0, 0, z0.mm])
      instance = entities.add_instance(definition, transform)
      instance.name = format('FOAM-DISC-%02d', i + 1)
    end
  end

  # PVC visible -pedido del usuario: "te faltó poner el tubo PVC"-: una
  # varilla sólida -no hueca, simplificación visual, ver la constante
  # PVC_VISIBLE_OVERHANG_MM- que atraviesa TODO el costal por el hueco
  # central, de la base a la tapa, asomando un tramo de cada lado.
  def build_pvc_post(entities, model)
    z0 = -PVC_VISIBLE_OVERHANG_MM
    z1 = CYLINDER_LENGTH_MM + TAPA_SKIRT_HEIGHT_MM + TAPA_DOME_RISE_MM + PVC_VISIBLE_OVERHANG_MM
    r = PVC_RADIUS_MM.mm
    add_wall(entities, r, z0.mm, z1.mm)
    add_ring(entities, 0.mm, r, z0.mm)
    add_ring(entities, 0.mm, r, z1.mm)
    material = costal_material(model, 'PVC', nil, fixed_color: PVC_COLOR)
    paint_new_faces(entities, material)
  end

  # Cintas de vinil pegadas Y cosidas alrededor del cilindro, en diagonal
  # -"forma de caramelo"-. SEGUNDO INTENTO: la primera versión pintaba
  # gajos de una cuadrícula fija -cinta sí/cinta no por celda-, y eso le
  # metía dientes de sierra -"picos en las orillas"- a la orilla
  # diagonal, porque la frontera real es una línea recta y la
  # cuadrícula la aproximaba en escalones. Ahora la orilla de cada
  # cinta se calcula con la fórmula EXACTA -línea recta en el plano
  # "desenrollado" ángulo/Z, igual que un reloj de sol- y se muestrea
  # fino en `theta_steps`, así la cinta -"las cintas son rectas"- sale
  # lisa en vez de escalonada.
  #
  # `k` enumera cada posible franja -puede haber varias vueltas
  # traslapadas por la hélice, algunas totalmente fuera del rango
  # [0, CYLINDER_LENGTH_MM] para cierto ángulo, esas simplemente no
  # dibujan nada-. Para cada `k` se recorre el ángulo completo y se
  # calcula dónde empieza/termina esa franja en Z, recortado al rango
  # válido del tubo.
  def build_stripe_ribbons(entities, model, stripe_hex)
    material = costal_material(model, 'Cinta Caramelo', stripe_hex)
    r = (CYLINDER_RADIUS_MM + CANDY_STRIPE_RAISE_MM).mm
    theta_steps = SEGMENTS * 2
    unwind_max = CANDY_TURNS * CYLINDER_LENGTH_MM
    k_min = -((unwind_max / CANDY_PERIOD_MM).ceil + 1)
    k_max = (CYLINDER_LENGTH_MM / CANDY_PERIOD_MM).ceil + 1

    (k_min..k_max).each do |k|
      prev = nil
      (0..theta_steps).each do |i|
        theta = i * (2 * Math::PI / theta_steps)
        unwind_mm = (theta / (2 * Math::PI)) * unwind_max
        z_lo = (unwind_mm + (k * CANDY_PERIOD_MM)).clamp(0.0, CYLINDER_LENGTH_MM)
        z_hi = (unwind_mm + (k * CANDY_PERIOD_MM) + CANDY_STRIPE_WIDTH_MM).clamp(0.0, CYLINDER_LENGTH_MM)
        cur = { theta: theta, lo: z_lo, hi: z_hi }

        # Solo se conecta con el muestreo anterior si AMBOS tienen
        # ancho real -si uno de los 2 quedó recortado a cero por salirse
        # del tubo, se deja un pequeño hueco ahí en vez de forzar un
        # cuadrángulo degenerado-.
        if prev && (z_hi - z_lo) > 0.5 && (prev[:hi] - prev[:lo]) > 0.5
          p1 = Geom::Point3d.new(r * Math.cos(prev[:theta]), r * Math.sin(prev[:theta]), prev[:lo].mm)
          p2 = Geom::Point3d.new(r * Math.cos(prev[:theta]), r * Math.sin(prev[:theta]), prev[:hi].mm)
          p3 = Geom::Point3d.new(r * Math.cos(theta), r * Math.sin(theta), z_hi.mm)
          p4 = Geom::Point3d.new(r * Math.cos(theta), r * Math.sin(theta), z_lo.mm)
          # Triangula -no un solo cuadrángulo- por seguridad: si el
          # recorte al final del tubo hace que el ancho cambie un poco
          # entre `prev` y `cur`, el cuadrángulo deja de ser exactamente
          # plano y SketchUp lo rechaza -mismo error real que ya pasó
          # con el diseño anterior-.
          [[p1, p2, p3], [p1, p3, p4]].each do |points|
            face = entities.add_face(*points)
            next unless face
            face.material = material
            face.back_material = material
          end
        end

        prev = cur
      end
    end
  end

  # Colorea SOLO las caras recién creadas -sin material todavía-, mismo
  # patrón que net_add_rod en constructor_modulos_playidea/main.rb, para
  # no repintar piezas ya coloreadas al reusar el mismo `entities`.
  def paint_new_faces(entities, material)
    entities.grep(Sketchup::Face).each do |f|
      next if f.material
      f.material = material
      f.back_material = material
    end
  end

  # Un material por pieza+color, nunca comparte nombre con foam/cinchos/
  # plataformas de otras piezas -mismo criterio de separación por
  # Twinmotion ya aplicado a los ductos del tobogán, ver skill-.
  def costal_material(model, tag, hex, fixed_color: nil)
    name = fixed_color ? "PlayIdea Costal #{tag}" : "PlayIdea Costal #{tag} ##{hex}"
    material = model.materials[name] || model.materials.add(name)
    material.color = fixed_color || hex_to_color(hex)
    material
  end

  def hex_to_color(hex)
    Sketchup::Color.new(hex[0, 2].to_i(16), hex[2, 2].to_i(16), hex[4, 2].to_i(16))
  end

  def write_attributes(entity, params, code, variant)
    {
      'code' => code,
      'type' => 'costal',
      'variant' => variant,
      'cylinder_diameter_mm' => CYLINDER_DIAMETER_MM,
      'cylinder_length_mm' => CYLINDER_LENGTH_MM,
      'lona_width_in' => LONA_WIDTH_IN,
      'lona_length_in' => LONA_LENGTH_IN,
      'foam_disc_count' => FOAM_DISC_COUNT,
      'foam_disc_thickness_mm' => FOAM_DISC_THICKNESS_MM,
      'post_hole_diameter_mm' => POST_HOLE_RADIUS_MM * 2.0,
      'lona_color_hex' => params[:lona_hex],
      'stripe_color_hex' => params[:stripe_hex]
    }.each { |key, value| entity.set_attribute(DICTIONARY, key, value) }
    entity.set_attribute('minorusal_auditor', 'code', code)
  end

  class PlacementTool
    def initialize(params)
      @params = params
      @input_point = Sketchup::InputPoint.new
    end

    def activate
      Sketchup.set_status_text(
        'Haz clic para colocar el costal liso -eje vertical, se orienta después-; el caramelo se coloca junto a él.',
        SB_PROMPT
      )
    end

    def onMouseMove(_flags, x, y, view)
      @input_point.pick(view, x, y)
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      @input_point.pick(view, x, y)
      PlayIdeaCostalScript.build_pair(@params, @input_point.position)
      Sketchup.active_model.select_tool(nil)
    end

    def draw(view)
      @input_point.draw(view) if @input_point.valid?
    end

    def onCancel(_reason, _view)
      Sketchup.active_model.select_tool(nil)
    end
  end
end

PlayIdeaCostalScript.start
