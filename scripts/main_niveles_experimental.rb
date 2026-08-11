require 'sketchup.rb'
require 'json'
require 'creador_tubos_playidea/main'
require 'conectores_playidea/main'

module PlayIdea
  module ConstructorModulosNiveles
    extend self

    DICTIONARY = 'playidea_modulo'.freeze
    DEFAULT_SPACING_M = 1.1684
    RECEIVER_RADIUS_MM = PlayIdea::Conectores::OUTSIDE_MM / 2.0
    # El 21 tiene 63.5 mm hacia abajo desde su origen y su eje horizontal se
    # encuentra un radio arriba. Esta cota evita que invada el receptor 61.
    BASE_GRID_HEIGHT_MM = 50.8 + 63.5 + RECEIVER_RADIUS_MM
    # Altura de la parrilla horizontal del NIVEL 0 (la que se apoya en el
    # receptor 61). A la altura normal (BASE_GRID_HEIGHT_MM) solo "Principal"
    # -asimétrico- alcanza a tocar el 61; a esta altura más baja es "Verde"
    # -centrada tras el fix de conectores_playidea- quien lo toca en cambio.
    # 50.8 = tope del receptor 61. 25.4 = mitad del largo de "Verde" (50.8mm).
    BOTTOM_GRID_HEIGHT_MM = 50.8 + 25.4
    # Cada extremo de un tubo horizontal necesita un desplazamiento propio
    # -no uno uniforme por eje- porque depende de qué papel (Azul o Verde)
    # sirve ese eje en el nodo de ese extremo -ver x_mouth_offset_mm/
    # y_mouth_offset_mm y middle_transform-:
    #
    #   - Azul (asimétrico, SIEMPRE sirve el eje en su propio extremo de
    #     fila/columna -nunca puede ser el eje interior/continuo justo en
    #     el extremo que se consulta-): la boca del receptor empieza un
    #     radio (24.15mm) ADELANTE del nodo, en la dirección del tubo. El
    #     tubo debe acortarse ese tanto para arrancar ya dentro del
    #     receptor. Aplica siempre a X; aplica a Y salvo en la única
    #     excepción de abajo.
    #   - Verde (centrado, solo puede darse en Y y solo en una esquina
    #     real -2 direcciones- de nivel k>=1, ver corner_transform): quedó
    #     CENTRADO sobre el nodo tras su fix en conectores_playidea (cubre
    #     de nodo-25.4 a nodo+25.4). El tubo debe ALARGARSE 25.4mm para
    #     atravesar todo el receptor y llegar a su pared trasera.
    #
    # Cada tubo se construye a su propia medida combinando el offset de SU
    # extremo de inicio con el de SU extremo final -pueden diferir, p.ej.
    # una esquina real de nivel 0 en un extremo y de nivel 1 en el otro no
    # aplica aquí porque ambos extremos comparten nivel k, pero esquina
    # real vs nodo intermedio sí puede diferir entre extremos-.
    VERDE_HALF_LENGTH_MM = 50.8 / 2.0
    STRUCTURAL_OUTSIDE_MM = 38.1
    STRUCTURAL_WALL_MM = 1.5
    STRUCTURAL_SCHEDULE = 'ESTRUCTURAL'.freeze

    # Recubrimiento de espuma (polyfoam) que forra toda la estructura -tubos
    # Y conectores, de ahí que el hueco interior sea el diámetro del
    # conector (48.3mm) y no el del tubo estructural (38.1mm)-. Cada tramo
    # (fila X, columna Y, poste Z) se recubre de PUNTA A PUNTA sin
    # detenerse en los nodos -a diferencia de los tubos estructurales, el
    # recubrimiento no necesita insertarse dentro de ningún receptor-.
    PADDING_OUTSIDE_MM = 85.0
    PADDING_INSIDE_MM = PlayIdea::Conectores::OUTSIDE_MM
    # El tubo crudo mide 2m; para llegar a la medida comercial de 2.4m se
    # pega un tramo de 40cm cortado de OTRO tubo crudo. El costo de
    # material por tubo terminado se aproxima como 1.2x el precio de un
    # tubo crudo -1 completo + una fracción de 0.4/2.0 de otro-, sin
    # modelar el aprovechamiento del sobrante de 1.6m del tubo donante.
    PADDING_STOCK_LENGTH_MM = 2000.0
    PADDING_FINISHED_LENGTH_MM = 2400.0
    PADDING_SPLICE_LENGTH_MM = 400.0
    PADDING_RAW_MATERIAL_FACTOR = 1 + (PADDING_SPLICE_LENGTH_MM / PADDING_STOCK_LENGTH_MM)
    PADDING_DEFAULT_COSTS = {
      'raw_tube' => 250.0,
      'perforation_labor' => 15.0,
      'electricity' => 3.0,
      'splice_labor' => 10.0,
      'wrap_material' => 40.0,
      'adhesive' => 20.0,
      'apply_labor' => 12.0,
      'weld_labor' => 8.0
    }.freeze

    # Torre de pisos triangulares: un tubo diagonal a 45° por escalón,
    # cruzando una sola celda de esquina a esquina, con un CON-12 en cada
    # extremo. TODOS los escalones usan la MISMA diagonal -sin alternar-;
    # una versión anterior alternaba (zigzag) por 4 ejemplos previos en
    # otras estructuras, pero se retiró tras analizar 5 ejemplos nuevos
    # (4 direcciones corregidas a mano por el usuario + el original del
    # plugin) sobre esta misma estructura (MOD-3X4X2): en los 4 corregidos,
    # los 3 escalones de cada torre -incluidos los que sí coinciden con un
    # nodo de la cuadrícula base- usan exactamente la misma diagonal, sin
    # excepción. Los escalones siguen espaciados 600mm entre sí, sin
    # importar el tamaño del módulo.
    #
    # DIRECCIÓN -4 opciones, una por esquina de la celda-: en vez de elegir
    # "cuál diagonal", el usuario elige qué ESQUINA de la celda (SO/SE/NE/
    # NO) sería el ángulo recto de un triángulo completo ahí -aunque este
    # plugin solo construye la hipotenusa (el tubo diagonal), no las 2
    # patas ni el conector de esquina, ver NOTA DE ALCANCE-. Esa esquina
    # determina sola las otras dos (sus vecinas, unidas por la diagonal que
    # SÍ se construye), verificado con exactitud contra los 4 ejemplos
    # corregidos: dado un orden fijo de esquinas alrededor de la celda
    # `ORDERED_CORNERS = [sw, nw, ne, se]`, si la esquina elegida es `c`,
    # la diagonal conecta `siguiente(c)` con `anterior(c)` en ese mismo
    # orden -confirmado exacto en los 4 casos (NO⇒SO-NE con inicio en NE,
    # SE⇒SO-NE con inicio en SO, NE⇒SE-NO con inicio en SE, SO⇒SE-NO con
    # inicio en NO-).
    TRIANGLE_STEP_SPACING_MM = 600.0
    # Altura mínima de arranque de la torre -el primer escalón no puede
    # coincidir con el nivel 0 -conector 61-, así que arranca en una
    # altura intermedia fija en vez de en 0. 500mm queda cómodo por
    # encima de BOTTOM_GRID_HEIGHT_MM y dentro del rango ideal de
    # separación entre escalones (ver TRIANGLE_STEP_SPACING_MM).
    TOWER_FIRST_STEP_HEIGHT_MM = 500.0
    # EXPERIMENTAL: qué tan cerca -en mm- tiene que estar la altura de un
    # escalón de un nivel real de la cuadrícula para tratarlo como
    # "coincide" -y saltarse el CON-21+patas de ese escalón-. Valor
    # estimado, no medido con datos reales todavía -no hay ninguna
    # referencia real de un escalón coincidiendo con un nivel-.
    GRID_LEVEL_COINCIDENCE_TOLERANCE_MM = 5.0
    # Cuánto se aleja el CON-12 diagonal de su propia esquina real -a lo
    # largo de la diagonal, hacia el otro extremo-, NO toda la celda ni
    # los demás conectores. Medido directo en una torre + cuadrícula real
    # que el usuario confirmó correcta -reporte_grupo_20260806_110850.txt,
    # 2 escalones, parseado con script en vez de a mano-: las 4 instancias
    # de CON-12 -2 por escalón, en los 2 escalones- dieron 104.2, 104.9,
    # 104.8 y 106.6mm, promedio 105.1mm. (Un intento anterior de 186mm,
    # basado en comparar contra una corrección a mano que resultó no ser
    # la buena, quedaba muy lejos de esta referencia confirmada -no se
    # usa-.)
    TRIANGLE_DIAGONAL_INSET_MM = 105.0
    # Cuánto se aleja el CON-21 -ángulo recto- de su propia esquina real,
    # hacia la esquina OPUESTA de la celda -la que no toca ni la
    # diagonal ni ninguna pata-. Viene de una sola medición real (con
    # comparar_grupos.rb, misma corrección que dio el número de arriba)
    # -34.65mm-, no de 4 como el CON-12; ojo si hace falta ajustarlo con
    # más muestras REALES -no calculadas-.
    TRIANGLE_RIGHT_ANGLE_INSET_MM = 34.65
    # Orden fijo de las 4 esquinas alrededor de la celda -ver DIRECCIÓN
    # arriba-; el vecino SIGUIENTE de una esquina en este orden es donde
    # arranca la diagonal (`near`), el ANTERIOR es donde termina (`far`).
    TRIANGLE_CORNER_ORDER = %i[sw nw ne se].freeze

    # Cuánto se mete el tubo -diagonal o pata- dentro de cada conector,
    # medido a lo largo del eje LOCAL de ese conector. `diagonal_connector_
    # mouth`/`right_angle_connector_mouth`/`leg_connector_mouth` usaban
    # RECEIVER_RADIUS_MM completo -24.15mm- en cada boca, pero midiendo el
    # largo REAL de los tubos en 4 torres hechas a mano -comparando la
    # distancia cruda entre conectores contra el largo real del tubo,
    # proyectado sobre sus propios ejes- ese inset resultó ser de ~11.3mm
    # por boca -la mitad de RECEIVER_RADIUS_MM-, consistente en el escalón
    # limpio de los 4 diseños y en los escalones tapados de 2 de los 4
    # -las otras 2 mediciones del escalón tapado inferior salieron muy
    # distintas entre sí, ~30mm, más parecido a ruido de construcción a
    # mano que a una regla real-. Con el inset completo (48.3mm totales
    # por tubo) el tubo calculado quedaba más corto que el hueco real entre
    # conectores, así que sobraba tubo y atravesaba la geometría del
    # conector en vez de detenerse en su boca.
    TRIANGLE_MOUTH_INSET_MM = RECEIVER_RADIUS_MM / 2.0

    # Orientación EXACTA del CON-12 -ejes local_x/local_y/local_z, para
    # `Geom::Transformation.axes`- por (ángulo recto elegido, papel
    # near/far), tomada DIRECTAMENTE de los 4 ejemplos corregidos por el
    # usuario -ya NO de una fórmula-. Se intentó primero una fórmula
    # basada solo en el signo de la dirección de la diagonal
    # (`diagonal_direction.x/y positivo o negativo`, la versión anterior
    # de `diagonal_connector_transform`) pero verificada numéricamente
    # contra los 4 archivos solo coincidía en 3 de los 8 casos reales -la
    # orientación correcta depende de CUÁL esquina y de su papel (near vs
    # far), no solo del signo de la dirección-. Como este plugin solo
    # construye exactamente estas 4 direcciones × 2 conectores cada una
    # -8 casos, ni uno más-, una tabla con los 8 valores reales es exacta
    # y no necesita ninguna fórmula.
    #
    # TRIÁNGULO COMPLETO en TODOS los escalones -diagonal + 2 patas, con un
    # CON-21 en el ángulo recto y un CON-10 en cada esquina vecina-. Esto NO
    # es integración con la cuadrícula base -verificado en los 4 ejemplos:
    # las alturas de esos escalones NO coinciden con ningún nivel real de
    # conectores de la estructura (CON-40/CON-35 de la cuadrícula base
    # existente)-, es simplemente que la torre "tapa" cada escalón con el
    # triángulo completo, flotando igual que la diagonal.
    #
    # Esto es una tabla de los 8 valores reales (4 ángulos rectos × pata
    # cercana/lejana) tomados de los 4 ejemplos, no una fórmula.
    TRIANGLE_CONNECTOR_21_AXES = {
      nw: [Y_AXIS.reverse, Z_AXIS.reverse, X_AXIS],
      se: [Y_AXIS.reverse, Z_AXIS.reverse, X_AXIS],
      ne: [X_AXIS, Z_AXIS.reverse, Y_AXIS],
      sw: [X_AXIS.reverse, Z_AXIS.reverse, Y_AXIS.reverse]
    }.freeze

    TRIANGLE_CONNECTOR_10_AXES = {
      nw: { near: [Z_AXIS, Y_AXIS.reverse, X_AXIS.reverse], far: [Z_AXIS, X_AXIS, Y_AXIS] },
      se: { near: [Z_AXIS, Y_AXIS.reverse, X_AXIS.reverse], far: [Z_AXIS, X_AXIS, Y_AXIS] },
      ne: { near: [Z_AXIS, X_AXIS, Y_AXIS.reverse], far: [Z_AXIS, Y_AXIS, X_AXIS.reverse] },
      sw: { near: [Z_AXIS, X_AXIS.reverse, Y_AXIS], far: [Z_AXIS, Y_AXIS.reverse, X_AXIS] }
    }.freeze

    # Orientación real del CON-12 -diagonal-, en TODOS los escalones -ver
    # TRIANGLE_CONNECTOR_21_AXES para el CON-21 del mismo escalón-.
    TRIANGLE_CONNECTOR_AXES_CAPPED = {
      nw: { near: [X_AXIS.reverse, Z_AXIS.reverse, Y_AXIS.reverse], far: [Y_AXIS, Z_AXIS, X_AXIS] },
      se: { near: [X_AXIS.reverse, Z_AXIS.reverse, Y_AXIS.reverse], far: [Y_AXIS, Z_AXIS, X_AXIS] },
      ne: { near: [Y_AXIS.reverse, Z_AXIS.reverse, X_AXIS], far: [X_AXIS.reverse, Z_AXIS, Y_AXIS] },
      sw: { near: [Y_AXIS, Z_AXIS.reverse, X_AXIS.reverse], far: [X_AXIS, Z_AXIS, Y_AXIS.reverse] }
    }.freeze
    # El punto real donde el tubo diagonal toca cada CON-12 -analizado
    # contra los 4 escalones "limpios" (los que no comparten nodo con un
    # conector de cuadrícula ya existente, ver NOTA DE ALCANCE) de los 2
    # ejemplos reales- NO es la punta del ramal mitrado de 76.2mm de
    # build_12; es el mismo RECEIVER_RADIUS_MM (24.15mm) usado en TODO el
    # resto del proyecto para tubos rectos, medido a lo largo del eje
    # local Z del propio CON-12 -el ramal de 76.2mm es el manguito que
    # RECIBE al tubo por dentro, oculto, igual que los manguitos centrados
    # de los conectores 21/35/40-. Verificado con error de ~2.1mm (0.14%
    # de una diagonal de ~1470mm) en los 4 escalones limpios de los 2
    # ejemplos -el error previo de una versión anterior (constante fija de
    # 70mm a lo largo de la diagonal pura) era de ~77mm, por eso los tubos
    # salían flotando fuera del conector-. Ver `diagonal_connector_mouth`.
    #
    # NOTA DE ALCANCE: esto solo construye el tubo diagonal y sus dos
    # CON-12 -la parte confirmada y verificada con exactitud numérica
    # contra datos reales-. NO modifica ningún conector de la cuadrícula
    # base en las esquinas donde cae la diagonal -el usuario confirmó que
    # a veces el conector que ya está ahí embona tal cual y a veces hay
    # que cambiarlo a mano, según el caso; de hecho, el escalón intermedio
    # de ambos ejemplos reales -el único que SÍ coincide con un nodo de la
    # cuadrícula base- se desvía ~36mm de esta fórmula limpia, justo
    # porque el usuario tuvo que ajustarlo a mano por esa razón-. Ese
    # ajuste, si hace falta, se sigue haciendo a mano en SketchUp después.

    def start
      unless defined?(UI::HtmlDialog)
        UI.messagebox('Este constructor necesita una versión de SketchUp compatible con HtmlDialog.')
        return
      end
      unless dependencies_available?
        UI.messagebox(
          "No se encontraron los plugins de tubos y conectores.\n\n" \
          'Instálalos y reinicia SketchUp antes de crear módulos.'
        )
        return
      end

      @dialog&.close
      @dialog = UI::HtmlDialog.new(
        dialog_title: 'Constructor de Módulos Play Idea',
        preferences_key: 'PlayIdeaConstructorModulos',
        scrollable: true,
        resizable: true,
        width: 820,
        height: 720,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_file(File.join(__dir__, 'selector.html'))
      @dialog.add_action_callback('ready') do |_action_context|
        @dialog.execute_script(
          "loadDefaults(#{JSON.generate(
            default_spacing_m: DEFAULT_SPACING_M,
            base_grid_height_mm: BASE_GRID_HEIGHT_MM,
            bottom_grid_height_mm: BOTTOM_GRID_HEIGHT_MM,
            receiver_radius_mm: RECEIVER_RADIUS_MM
          )})"
        )
      end
      @dialog.add_action_callback('createModule') do |_action_context, data|
        params = validate_dialog_data(data)
        next unless params
        if params[:padding]
          padding_costs = capture_padding_costs
          next unless padding_costs
          params[:padding_costs] = padding_costs
        end
        @dialog.close
        Sketchup.active_model.select_tool(ModulePlacementTool.new(params))
      end
      @dialog.show
    rescue StandardError => error
      UI.messagebox("No fue posible abrir el constructor:\n#{error.message}")
      puts error.full_message
    end

    def dependencies_available?
      defined?(PlayIdea::CreadorTubos) &&
        defined?(PlayIdea::Conectores) &&
        PlayIdea::CreadorTubos.respond_to?(:add_hollow_geometry) &&
        PlayIdea::Conectores.respond_to?(:build_connector_geometry)
    end

    def validate_dialog_data(data)
      params = {
        modules_x: data['modules_x'].to_i,
        modules_y: data['modules_y'].to_i,
        modules_z: data['modules_z'].to_i,
        spacing_x_mm: data['spacing_x_m'].to_f * 1000.0,
        spacing_y_mm: data['spacing_y_m'].to_f * 1000.0,
        spacing_z_mm: data['spacing_z_m'].to_f * 1000.0,
        color: data['color'].to_s,
        code: data['code'].to_s.strip,
        connectors: data['connectors'] == true,
        padding: data['padding'] == true
      }
      valid_counts = [:modules_x, :modules_y, :modules_z].all? do |key|
        params[key].between?(1, 20)
      end
      valid_spacing = [:spacing_x_mm, :spacing_y_mm, :spacing_z_mm].all? do |key|
        params[key].positive?
      end
      unless valid_counts && valid_spacing
        UI.messagebox('Las cantidades deben estar entre 1 y 20 y las medidas deben ser mayores que cero.')
        return nil
      end
      params[:code] = module_code(params) if params[:code].empty?
      if data['tower'] == true
        tower = tower_params_from_dialog(data, params)
        if tower.nil?
          UI.messagebox(
            'Elige una columna de la cuadrícula haciendo clic en la vista ' \
            'previa para colocar la torre -o revisa que la estructura sea ' \
            'lo bastante alta (al menos 50cm) para que quepa un escalón.'
          )
          return nil
        end
        params[:tower] = tower
      end
      params
    end

    def module_code(params)
      "MOD-#{params[:modules_x]}X#{params[:modules_y]}X#{params[:modules_z]}"
    end

    # Cuántos escalones caben, con separación entre 50 y 60cm, en
    # `total_height_mm` de punta a punta. Entre las opciones válidas
    # prefiere la separación más cercana a 600mm -menos escalones-; si
    # ninguna cantidad de escalones cae exactamente dentro del rango,
    # devuelve la que menos se aleje. `nil` si no cabe ni un escalón.
    def auto_tower_step_fit(total_height_mm)
      return nil if total_height_mm < 500.0
      best = nil
      (1..40).each do |gaps|
        spacing = total_height_mm / gaps
        next if spacing > 900.0
        error = if spacing < 500.0
                  500.0 - spacing
                elsif spacing > 600.0
                  spacing - 600.0
                else
                  0.0
                end
        next unless best.nil? || error < best[:error] || (error == best[:error] && gaps < best[:gaps])
        best = { gaps: gaps, spacing: spacing, error: error }
      end
      return nil if best.nil?
      { steps: best[:gaps] + 1, spacing_mm: best[:spacing] }
    end

    # EXPERIMENTAL: lista de alturas -mm- de TODOS los escalones de la
    # torre. Es una ESCALERA de planta baja a la ÚLTIMA planta -confirmado
    # por el usuario, analogía de una casa de 2 pisos-: sube TRAMO POR
    # TRAMO por cada nivel real INTERMEDIO -k=1 a nz-1-, pero se DETIENE
    # en la base del último módulo -nivel k=nz-1-, sin seguir subiendo
    # DENTRO del último módulo -no hay más pisos arriba de eso, no sería
    # coherente seguir poniendo escalones-. Con nz=1 -un solo módulo, sin
    # "siguiente piso" al que subir- no aplica esta lógica de escalera:
    # se queda con el patrón fijo ya validado -2 escalones a
    # TOWER_FIRST_STEP_HEIGHT_MM de separación, ver reporte_grupo_
    # 20260806_110850.txt-, independiente de la altura del módulo. Cada
    # tramo -de un nivel real al siguiente- se auto-ajusta aparte con
    # `auto_tower_step_fit`, así que el escalón final de cada tramo cae
    # EXACTO en el nivel real, sin importar qué tan alto sea el módulo.
    def auto_tower_step_heights(bottom_z_mm, real_grid_levels_mm, nz)
      if nz <= 1
        return [bottom_z_mm, bottom_z_mm + TOWER_FIRST_STEP_HEIGHT_MM]
      end
      objetivos = real_grid_levels_mm[1..(nz - 1)] || []
      alturas = [bottom_z_mm]
      actual = bottom_z_mm
      objetivos.each do |objetivo|
        fit = auto_tower_step_fit(objetivo - actual)
        if fit.nil?
          alturas << objetivo
        else
          (1...fit[:steps]).each { |i| alturas << actual + i * fit[:spacing_mm] }
        end
        actual = objetivo
      end
      alturas
    end

    # Campos `tower_*` del mismo diálogo (checkbox "Agregar torre de pisos
    # triangulares" en selector.html), reutilizando color y código de la
    # estructura -no hay un segundo diálogo para la torre en este flujo
    # integrado-. La celda de la torre YA NO se escribe a mano: el usuario
    # elige una columna (i,j) real de la cuadrícula haciendo clic en la
    # vista previa, así que usa la MISMA medida de celda que la
    # estructura (`spacing_x_mm`/`spacing_y_mm`). Escalones auto-
    # calculados vía `auto_tower_step_fit`, ver el comentario grande junto
    # a `fit` más abajo. Devuelve `nil` si algo no es válido.
    def tower_params_from_dialog(data, structure_params)
      return nil if data['tower_cell_i'].nil? || data['tower_cell_j'].nil?
      i = data['tower_cell_i'].to_i
      j = data['tower_cell_j'].to_i
      return nil unless i.between?(0, structure_params[:modules_x] - 1)
      return nil unless j.between?(0, structure_params[:modules_y] - 1)
      right_angle_corner = data['tower_corner'].to_s.to_sym
      return nil unless TRIANGLE_CORNER_ORDER.include?(right_angle_corner)

      nz = structure_params[:modules_z]
      # El primer escalón nunca arranca EXACTO en el nivel 0 -ahí ya está
      # el conector 61 recibiendo el poste vertical, no cabe un tubo
      # diagonal ahí-, así que arranca en TOWER_FIRST_STEP_HEIGHT_MM
      # -500mm, siempre por encima de BOTTOM_GRID_HEIGHT_MM-, punto fijo,
      # no depende de la altura de módulo elegida.
      #
      # La torre NO sube hasta el nivel real de arriba de la cuadrícula
      # -confirmado con datos reales, reporte_grupo_20260806_110850.txt:
      # con 1 módulo de alto -nz=1- la torre tiene exactamente 2 escalones
      # -506mm y ~1006mm, separación 500mm-, y se queda ahí sin llegar al
      # nivel real de arriba -1337mm en ese caso-.
      #
      # EXPERIMENTAL -reemplaza la versión de "separación uniforme fija"-:
      # en vez de una sola separación para toda la torre -antes nz*500mm,
      # sin relación con la altura REAL del módulo elegida por el
      # usuario-, ahora se sube TRAMO POR TRAMO entre cada nivel real de
      # la cuadrícula -`auto_tower_step_heights`-, así que el número de
      # escalones intermedios y su separación dependen de la altura real
      # de cada módulo, no de un valor fijo inventado para que "quepan
      # bien" 2 escalones.
      return nil if nz < 1
      bottom_z_mm = TOWER_FIRST_STEP_HEIGHT_MM

      # Niveles reales de la cuadrícula -en mm-, para que create_triangle_
      # tower pueda saltarse el CON-21+patas en cualquier escalón cuya
      # altura caiga en uno de estos niveles -ahí ya hay conectores/tubos
      # reales de la cuadrícula, no hace falta duplicar, solo la
      # diagonal- Y para que auto_tower_step_heights sepa dónde tienen que
      # caer los escalones finales de cada tramo.
      sz = spacing_z_length(structure_params[:spacing_z_mm])
      real_grid_levels_mm = (0..nz).map { |k| grid_level_z(k, nz, sz).to_mm }
      step_heights_mm = auto_tower_step_heights(bottom_z_mm, real_grid_levels_mm, nz)

      # REVERTIDO: la celda de la torre SÍ usa las 4 esquinas reales de la
      # cuadrícula, sin inset -ver el comentario grande junto a
      # TRIANGLE_DIAGONAL_INSET_MM más abajo-. Midiendo 4 estructuras
      # reales hechas a mano (torre + cuadrícula juntas) resultó que
      # CON-21 y CON-10 SÍ van pegados/cerca de la columna real -a propio
      # propósito, no es un choque-; solo el CON-12 diagonal necesita
      # alejarse, y no de toda la celda: solo él, de su propia esquina.
      # Ver `diagonal_connector_transform` y create_triangle_tower.
      {
        cell_x_mm: structure_params[:spacing_x_mm],
        cell_y_mm: structure_params[:spacing_y_mm],
        right_angle_corner: right_angle_corner,
        step_heights_mm: step_heights_mm,
        color: structure_params[:color],
        code: "#{structure_params[:code]}-TORRE",
        offset_x_mm: i * structure_params[:spacing_x_mm],
        offset_y_mm: j * structure_params[:spacing_y_mm],
        real_grid_levels_mm: real_grid_levels_mm
      }
    end

    # Mismo patrón que capture_costs en conectores_playidea: valores por
    # defecto editables, guardados con Sketchup.write_default para que la
    # siguiente vez ya aparezcan los últimos capturados. Cada renglón
    # corresponde a un paso real del proceso: tubo crudo, perforado (mano
    # de obra + luz), empalme a 2.4m, forro de plástico, pegamento con
    # solvente, mano de obra de aplicarlo, y soldado de la costura.
    def capture_padding_costs
      prompts = [
        'Precio de un tubo crudo de polyfoam 2m (MXN)',
        'Mano de obra de perforado por tubo terminado (MXN)',
        'Electricidad de perforado por tubo terminado (MXN)',
        'Mano de obra de empalme/pegado a 2.4m (MXN)',
        'Material de forro (plástico) por tubo terminado (MXN)',
        'Pegamento con solvente por tubo terminado (MXN)',
        'Mano de obra de aplicar el pegamento (MXN)',
        'Mano de obra de soldar la costura (MXN)'
      ]
      keys = %w[raw_tube perforation_labor electricity splice_labor wrap_material adhesive apply_labor weld_labor]
      defaults = keys.map do |key|
        stored = Sketchup.read_default('PlayIdeaRecubrimientoCostos', key, nil)
        stored.nil? || stored.to_f <= 0 ? PADDING_DEFAULT_COSTS[key] : stored.to_f
      end
      values = UI.inputbox(prompts, defaults, 'Costos del recubrimiento de espuma')
      return nil unless values
      keys.each_with_index do |key, index|
        Sketchup.write_default('PlayIdeaRecubrimientoCostos', key, values[index].to_f)
      end
      keys.zip(values.map(&:to_f)).to_h
    end

    def create_module(params, origin)
      model = Sketchup.active_model
      model.start_operation("Crear módulo #{params[:code]}", true)
      container = model.active_entities.add_group
      container.name = params[:code]

      create_grid_tubes(container.entities, params, origin, model)

      connector_counts = Hash.new(0)
      if params[:connectors]
        connector_definitions = create_connector_definitions(model)
        create_grid_connectors(
          container.entities, connector_definitions, connector_counts,
          params, origin
        )
      end

      padding_length_mm = params[:padding] ? create_grid_padding(container.entities, params, origin, model) : 0.0

      write_module_attributes(container, params, connector_counts, padding_length_mm)
      model.selection.clear
      model.selection.add(container)
      model.commit_operation
      container
    rescue StandardError
      model.abort_operation
      raise
    end

    def create_tube_definition(model, length_mm, color, axis_name)
      params = {
        length_mm: length_mm,
        outside_mm: STRUCTURAL_OUTSIDE_MM,
        schedule: STRUCTURAL_SCHEDULE,
        wall_mm: STRUCTURAL_WALL_MM,
        inside_mm: STRUCTURAL_OUTSIDE_MM - (2.0 * STRUCTURAL_WALL_MM),
        code: "TUB-MOD-#{axis_name}-#{format('%.1f', length_mm)}",
        color: color,
        length_mode: 'modular',
        standard_name: (length_mm - DEFAULT_SPACING_M * 1000.0).abs < 0.05 ?
          'Módulo Play Idea — 1.1684 m' : '',
        connector_compatible: true,
        connector_clearance_mm: PlayIdea::Conectores::INSIDE_MM - STRUCTURAL_OUTSIDE_MM
      }
      definition = model.definitions.add(unique_name(model, params[:code]))
      PlayIdea::CreadorTubos.add_hollow_geometry(definition.entities, params)
      PlayIdea::CreadorTubos.apply_material(model, definition, color)
      PlayIdea::CreadorTubos.write_attributes(definition, params)
      definition
    end

    # Altura Z de una parrilla horizontal completa (tubos y conectores),
    # compartida entre create_grid_tubes y create_grid_connectors para que
    # ambos siempre se muevan juntos. Nivel 0: ver BOTTOM_GRID_HEIGHT_MM.
    # Último nivel (k==nz): el poste termina justo ahí (no continúa a otro
    # conector arriba), así que toda la parrilla sube un radio para que el
    # receptor vertical de cada conector alcance la punta real del poste
    # en vez de quedarse corto.
    # EXPERIMENTAL: `sz` puede ser un solo Length -separación uniforme,
    # como siempre- O un Array de Length -una altura por módulo, para
    # estructuras de varios pisos con altura distinta cada uno-. Con
    # Array, la altura acumulada hasta el nivel k es la suma de las
    # primeras k alturas -sz[0...k]-, no k*sz.
    def grid_level_z(k, nz, sz)
      return BOTTOM_GRID_HEIGHT_MM.mm if k.zero?
      altura_acumulada = sz.is_a?(Array) ? sz[0...k].inject(0.mm, :+) : k * sz
      z = BASE_GRID_HEIGHT_MM.mm + altura_acumulada
      z += RECEIVER_RADIUS_MM.mm if k == nz
      z
    end

    # EXPERIMENTAL: convierte `spacing_z_mm` -Float uniforme o Array de
    # Floats, una altura de módulo por elemento- a Length -o Array de
    # Length-, para usarse directo en `grid_level_z`.
    def spacing_z_length(spacing_z_mm)
      spacing_z_mm.is_a?(Array) ? spacing_z_mm.map(&:mm) : spacing_z_mm.mm
    end

    # Desplazamiento (acortamiento) de un tubo X en un extremo nodo-a-nodo
    # (i, i+1). X siempre lo sirve Azul -asimétrico, nunca centrado, en
    # NINGÚN nivel, ni siquiera arriba de todo- así que los tubos X van
    # SIEMPRE segmentados un tramo por módulo, con el mismo radio en ambos
    # extremos, sin excepción de nivel.
    def x_mouth_offset_mm(_i, _j, _nx, _ny)
      RECEIVER_RADIUS_MM
    end

    # Desplazamiento (acortamiento, o alargamiento si es negativo) de un
    # tubo Y en un extremo REAL de columna (j=0 o j=ny). Solo en el NIVEL 0
    # el eje Y lo sirve una pieza asimétrica -Principal, vía
    # bottom_corner_transform, porque "Verde" está volteada tocando el 61-,
    # así que ahí Y se acorta igual que X. En CUALQUIER OTRO nivel (k>=1,
    # sea el intermedio real o el de arriba) una esquina real (2
    # direcciones) siempre queda servida por una pieza CENTRADA -"Verde"
    # arriba, vía corner_transform; el par opuesto reorientado a Z en un
    # nivel intermedio real deja la pieza centrada libre para Y, vía
    # swapped_z_body_transform-, así que el tubo debe alargarse para
    # atravesarla del todo. Un nodo de 3 direcciones (i interior, columna
    # con paso propio en X) nunca alarga en Y -confirmado en la ronda 13-,
    # sin importar el nivel: en su propio extremo Y siempre es el eje
    # sencillo ahí. Confirmado con datos reales de modules_z=2: en nivel 0
    # el tubo Y mide 1120.1mm por tramo (acorta 24.15 en ambos extremos);
    # en el nivel intermedio real Y en niveles k>=1 mide 2387.6mm de punta
    # a punta (alarga 25.4 en ambos extremos, sean esquinas reales).
    def y_mouth_offset_mm(i, j, nx, ny, k)
      horizontal = horizontal_directions(i, j, nx, ny)
      return -VERDE_HALF_LENGTH_MM if horizontal.length == 2 && !k.zero?
      RECEIVER_RADIUS_MM
    end

    # Reutiliza (o crea) la definición de tubo para un largo exacto, para
    # no duplicar geometría cuando varias combinaciones de extremos dan el
    # mismo largo -lo más común, ej. todos los tramos esquina-a-esquina-.
    def cached_tube_definition(model, cache, length_mm, color, axis_name)
      key = length_mm.round(4)
      cache[key] ||= create_tube_definition(model, length_mm, color, axis_name)
    end

    # Los tubos X siempre van segmentados, un tramo por módulo, en TODOS los
    # niveles (ver x_mouth_offset_mm). Los tubos Y van segmentados solo en
    # el nivel 0; en cualquier nivel k>=1 -intermedio real o el de arriba-
    # cada columna Y es un tubo continuo de punta a punta, porque ahí Y
    # siempre topa contra una pieza centrada en sus extremos reales (ver
    # y_mouth_offset_mm) que necesita ser atravesada por dentro, no solo
    # tocada en el borde.
    def create_grid_tubes(entities, params, origin, model)
      nx = params[:modules_x]
      ny = params[:modules_y]
      nz = params[:modules_z]
      sx_mm = params[:spacing_x_mm]
      sy_mm = params[:spacing_y_mm]
      sz = spacing_z_length(params[:spacing_z_mm])
      cache = {}

      (0..nz).each do |k|
        z = grid_level_z(k, nz, sz)
        (0..ny).each do |j|
          nx.times do |i|
            start_offset = x_mouth_offset_mm(i, j, nx, ny)
            end_offset = x_mouth_offset_mm(i + 1, j, nx, ny)
            length_mm = sx_mm - start_offset - end_offset
            definition = cached_tube_definition(model, cache, length_mm, params[:color], 'X')
            point = offset_point(origin, i * sx_mm.mm + start_offset.mm, j * sy_mm.mm, z)
            add_oriented_instance(entities, definition, point, X_AXIS)
          end
        end
      end

      (0..nz).each do |k|
        z = grid_level_z(k, nz, sz)
        if k.zero?
          (0..nx).each do |i|
            ny.times do |j|
              start_offset = y_mouth_offset_mm(i, j, nx, ny, k)
              end_offset = y_mouth_offset_mm(i, j + 1, nx, ny, k)
              length_mm = sy_mm - start_offset - end_offset
              definition = cached_tube_definition(model, cache, length_mm, params[:color], 'Y')
              point = offset_point(origin, i * sx_mm.mm, j * sy_mm.mm + start_offset.mm, z)
              add_oriented_instance(entities, definition, point, Y_AXIS)
            end
          end
        else
          (0..nx).each do |i|
            start_offset = y_mouth_offset_mm(i, 0, nx, ny, k)
            end_offset = y_mouth_offset_mm(i, ny, nx, ny, k)
            length_mm = ny * sy_mm - start_offset - end_offset
            definition = cached_tube_definition(model, cache, length_mm, params[:color], 'Y')
            point = offset_point(origin, i * sx_mm.mm, start_offset.mm, z)
            add_oriented_instance(entities, definition, point, Y_AXIS)
          end
        end
      end

      # El poste Z solo es continuo DENTRO de un mismo nivel -nace en el 61
      # (k==0) y termina en el último nivel (k==nz) sin cortes-, pero se
      # PARTE en dos en cada nivel intermedio real (0<k<nz, solo existe con
      # modules_z>=2): el conector de ahí recibe cada mitad por separado con
      # su par de ramales reorientado a Z (ver swapped_z_body_transform),
      # así que el tubo no debe cruzarlo de largo. Confirmado con datos
      # reales: con modules_z=2 el poste aparece partido en dos piezas de
      # 1288.12mm cada una, con un hueco de ~40mm donde se aloja el
      # conector intermedio -aquí se usa el mismo radio de siempre
      # (24.15mm) para ese hueco, dentro del margen de imprecisión de un
      # ajuste hecho a mano en SketchUp-.
      (0...nz).each do |k|
        z_start = k.zero? ? 0.mm : grid_level_z(k, nz, sz) + RECEIVER_RADIUS_MM.mm
        z_end = k == nz - 1 ? grid_level_z(nz, nz, sz) : grid_level_z(k + 1, nz, sz) - RECEIVER_RADIUS_MM.mm
        length_mm = (z_end - z_start).to_mm
        z_definition = cached_tube_definition(model, cache, length_mm, params[:color], 'Z')
        (0..ny).each do |j|
          (0..nx).each do |i|
            point = offset_point(origin, i * sx_mm.mm, j * sy_mm.mm, z_start)
            add_oriented_instance(entities, z_definition, point, Z_AXIS)
          end
        end
      end
    end

    # Reutiliza (o crea) la definición del tubo de recubrimiento para un
    # largo exacto -mismo patrón que cached_tube_definition-.
    def cached_padding_definition(model, cache, length_mm, color)
      key = length_mm.round(4)
      cache[key] ||= create_padding_definition(model, length_mm, color)
    end

    def create_padding_definition(model, length_mm, color)
      geometry_params = {
        length_mm: length_mm,
        outside_mm: PADDING_OUTSIDE_MM,
        inside_mm: PADDING_INSIDE_MM
      }
      definition = model.definitions.add(
        unique_name(model, "REC-#{format('%.1f', length_mm)}")
      )
      PlayIdea::CreadorTubos.add_hollow_geometry(definition.entities, geometry_params)
      PlayIdea::CreadorTubos.apply_material(model, definition, color)
      definition.set_attribute(DICTIONARY, 'type', 'recubrimiento')
      definition.set_attribute(DICTIONARY, 'length_mm', length_mm)
      definition.set_attribute(DICTIONARY, 'outside_diameter_mm', PADDING_OUTSIDE_MM)
      definition.set_attribute(DICTIONARY, 'inside_diameter_mm', PADDING_INSIDE_MM)
      definition
    end

    # El recubrimiento cubre cada fila X, columna Y y poste Z de PUNTA A
    # PUNTA -sin insetarse en los nodos como los tubos estructurales, ver
    # la constante PADDING_OUTSIDE_MM/PADDING_INSIDE_MM-, así que no
    # necesita conocer nada de la lógica de conectores por tipo/nivel: solo
    # el ancho total de la cuadrícula en cada eje. Regresa el largo total
    # construido (mm), usado por write_module_attributes para el costeo.
    def create_grid_padding(entities, params, origin, model)
      nx = params[:modules_x]
      ny = params[:modules_y]
      nz = params[:modules_z]
      sx_mm = params[:spacing_x_mm]
      sy_mm = params[:spacing_y_mm]
      sz = spacing_z_length(params[:spacing_z_mm])
      color = params[:color]
      cache = {}
      total_length_mm = 0.0

      (0..nz).each do |k|
        z = grid_level_z(k, nz, sz)
        (0..ny).each do |j|
          length_mm = nx * sx_mm
          definition = cached_padding_definition(model, cache, length_mm, color)
          point = offset_point(origin, 0, j * sy_mm.mm, z)
          add_oriented_instance(entities, definition, point, X_AXIS)
          total_length_mm += length_mm
        end
      end
      (0..nz).each do |k|
        z = grid_level_z(k, nz, sz)
        (0..nx).each do |i|
          length_mm = ny * sy_mm
          definition = cached_padding_definition(model, cache, length_mm, color)
          point = offset_point(origin, i * sx_mm.mm, 0, z)
          add_oriented_instance(entities, definition, point, Y_AXIS)
          total_length_mm += length_mm
        end
      end
      z_length_mm = grid_level_z(nz, nz, sz).to_mm
      (0..ny).each do |j|
        (0..nx).each do |i|
          definition = cached_padding_definition(model, cache, z_length_mm, color)
          point = offset_point(origin, i * sx_mm.mm, j * sy_mm.mm, 0)
          add_oriented_instance(entities, definition, point, Z_AXIS)
          total_length_mm += z_length_mm
        end
      end
      total_length_mm
    end

    def create_connector_definitions(model)
      %w[21 26 35 40 61].each_with_object({}) do |code, result|
        definition = model.definitions.add(
          unique_name(model, "CON-MOD-#{code}")
        )
        material = PlayIdea::Conectores.connector_material(model, 'Galvanizado')
        hardware = PlayIdea::Conectores.hardware_material(model)
        if code == '26'
          build_connector_26(definition.entities, material, hardware)
          metadata = connector_26_metadata
          write_connector_26_attributes(definition, metadata)
        elsif code == '35'
          build_connector_35_verde(definition.entities, material, hardware)
          metadata = connector_metadata(code)
          PlayIdea::Conectores.write_attributes(
            definition, code, 'Galvanizado', metadata
          )
        else
          PlayIdea::Conectores.build_connector_geometry(
            definition.entities, code, material, hardware
          )
          metadata = connector_metadata(code)
          PlayIdea::Conectores.write_attributes(
            definition, code, 'Galvanizado', metadata
          )
        end
        result[code] = [definition, metadata]
      end
    end

    # Variante del 35 exclusiva del constructor -no toca conectores_playidea,
    # mismo patrón que build_connector_26-: los mismos 3 ramales del 35
    # original (par opuesto en X + ramal sencillo en Y), pero con la pieza
    # central reemplazada por una centrada de 50.8mm -del mismo largo que
    # "Verde" del 21- en vez del manguito asimétrico de 63.5mm. Se usa en
    # nodos donde el poste Z no termina ahí -pasa continuo (nivel 0) o se
    # parte en dos (nivel intermedio real, ver swapped_z_body_transform)-,
    # así que necesita una pieza SIMÉTRICA para cubrir ambos lados del
    # nodo en Z, igual que Verde ya resuelve esto en el 21. Verificado
    # contra el largo real del tubo Y continuo del usuario en nivel
    # intermedio (2387.6mm con nx=1,ny=2 → alargue de 25.4mm por extremo,
    # exactamente la mitad de 50.8mm, no de 63.5mm).
    def build_connector_35_verde(entities, material, hardware)
      positive = PlayIdea::Conectores.add_branch_sleeve(
        entities, X_AXIS, 50.8, material, hardware
      )
      positive.name = 'Salida lateral +X 2 pulgadas'
      lateral = PlayIdea::Conectores.add_branch_sleeve(
        entities, Y_AXIS, 50.8, material, hardware
      )
      lateral.name = 'Salida lateral +Y 2 pulgadas'
      negative = PlayIdea::Conectores.add_branch_sleeve(
        entities, X_AXIS.reverse, 50.8, material, hardware
      )
      negative.name = 'Salida lateral -X 2 pulgadas'
      central = PlayIdea::Conectores.add_centered_sleeve(
        entities, Z_AXIS, 50.8, material, hardware
      )
      central.name = 'Salida verde 2 pulgadas'
    end

    # Conector 26 exclusivo del constructor: poste central pasante y dos
    # receptores horizontales enfrentados a 180 grados.
    def build_connector_26(entities, material, hardware)
      central = PlayIdea::Conectores.add_centered_sleeve(
        entities, Z_AXIS, 63.5, material, hardware
      )
      central.name = 'Paso central del conector 26'
      positive = PlayIdea::Conectores.add_branch_sleeve(
        entities, X_AXIS, 50.8, material, hardware
      )
      positive.name = 'Salida lateral +X del conector 26'
      negative = PlayIdea::Conectores.add_branch_sleeve(
        entities, X_AXIS.reverse, 50.8, material, hardware
      )
      negative.name = 'Salida lateral -X del conector 26'
    end

    def connector_26_metadata
      costs = PlayIdea::Conectores::DEFAULT_COSTS.each_with_object({}) do |(key, default), result|
        stored = Sketchup.read_default('PlayIdeaConectoresCostos', key, nil)
        result[key] = stored.nil? || stored.to_f <= 0 ? default : stored.to_f
      end
      cuts = [63.5, 50.8, 50.8]
      rows = cuts.each_with_index.map do |length, index|
        PlayIdea::Conectores.cost_row(
          "Tubo receptor #{index + 1} — #{length} mm",
          length / 6000.0, 'barra de 6 m', costs['bar_6m']
        )
      end
      rows.concat([
        PlayIdea::Conectores.cost_row('Tuercas', 3, 'pieza', costs['nut']),
        PlayIdea::Conectores.cost_row('Opresores Allen', 3, 'pieza', costs['screw']),
        PlayIdea::Conectores.cost_row('Cortes de tubo', 3, 'corte', costs['cut']),
        PlayIdea::Conectores.cost_row('Uniones soldadas', 5, 'operación', costs['weld']),
        PlayIdea::Conectores.cost_row('Consumibles de soldadura', 1, 'conector', costs['welding_supplies']),
        PlayIdea::Conectores.cost_row('Electricidad', 1, 'conector', costs['electricity']),
        PlayIdea::Conectores.cost_row('Acabado / pintura', 1, 'conector', costs['finish']),
        PlayIdea::Conectores.cost_row('Otros insumos', 1, 'conector', costs['other'])
      ])
      {
        receiver_material: 'Acero al carbón',
        hardware_size: 'M8',
        costing: { rows: rows, total: rows.inject(0.0) { |sum, row| sum + row[:subtotal] } },
        investment_cost_mxn: rows.inject(0.0) { |sum, row| sum + row[:subtotal] }
      }
    end

    def write_connector_26_attributes(entity, metadata)
      data = {
        'code' => 'CON-26',
        'connector_type' => '26',
        'description' => 'Paso central con dos salidas opuestas',
        'receiver_nominal_size' => '1 1/2 pulgadas',
        'receiver_schedule' => '30',
        'receiver_outside_mm' => PlayIdea::Conectores::OUTSIDE_MM,
        'receiver_inside_mm' => PlayIdea::Conectores::INSIDE_MM,
        'receiver_wall_mm' => PlayIdea::Conectores::WALL_MM,
        'color' => 'Galvanizado',
        'investment_cost_mxn' => metadata[:investment_cost_mxn],
        'currency' => 'MXN',
        'receiver_material' => metadata[:receiver_material],
        'tube_cuts_mm' => '63.5, 50.8, 50.8',
        'total_tube_length_mm' => 165.1,
        'nut_specification' => metadata[:hardware_size],
        'nut_quantity' => 3,
        'set_screw_specification' => metadata[:hardware_size],
        'set_screw_quantity' => 3,
        'has_base_plate' => false,
        'cost_breakdown_json' => JSON.generate(metadata[:costing][:rows])
      }
      data.each do |key, value|
        entity.set_attribute(PlayIdea::Conectores::DICTIONARY, key, value)
      end
      entity.set_attribute('minorusal_auditor', 'code', 'CON-26')
      entity.set_attribute(
        'minorusal_auditor',
        'investment_cost_mxn',
        metadata[:investment_cost_mxn]
      )
    end

    def connector_metadata(code)
      costs = PlayIdea::Conectores::DEFAULT_COSTS.each_with_object({}) do |(key, default), result|
        stored = Sketchup.read_default('PlayIdeaConectoresCostos', key, nil)
        result[key] = stored.nil? || stored.to_f <= 0 ? default : stored.to_f
      end
      costing = PlayIdea::Conectores.build_cost_breakdown(code, costs)
      {
        receiver_material: 'Acero al carbón',
        hardware_size: 'M8',
        costing: costing,
        investment_cost_mxn: costing[:total]
      }
    end

    def create_grid_connectors(entities, definitions, counts, params, origin)
      nx = params[:modules_x]
      ny = params[:modules_y]
      nz = params[:modules_z]
      sx = params[:spacing_x_mm].mm
      sy = params[:spacing_y_mm].mm
      sz = spacing_z_length(params[:spacing_z_mm])

      (0..nz).each do |k|
        (0..ny).each do |j|
          (0..nx).each do |i|
            horizontal = horizontal_directions(i, j, nx, ny)
            if k.zero?
              add_connector_instance(
                entities, definitions, counts, '61',
                offset_point(origin, i * sx, j * sy, 0),
                Geom::Transformation.translation(
                  offset_point(origin, i * sx, j * sy, 0)
                )
              )
            end

            code = connector_code_for_horizontal(horizontal)
            # El poste Z solo es continuo dentro de un mismo nivel; se PARTE
            # en cada nivel intermedio real (0<k<nz) -ver create_grid_tubes-,
            # así que ahí CUALQUIER nodo (esquina real o intermedio) necesita
            # el cuerpo del 35 para recibir cada mitad del poste, no solo los
            # nodos que ya tenían 3 direcciones horizontales. En el nivel más
            # alto (k==nz) no hay nada que continúe arriba, así que un nodo
            # intermedio de 3 direcciones no necesita el 35 -reusa el 21, ver
            # middle_transform-. Un nodo interior verdadero de 4 direcciones
            # (código '40') en ese mismo nivel más alto SÍ necesita el cuerpo
            # del 35 -no el del 21, que solo tiene 2 salidas horizontales,
            # insuficientes para las 4 reales de un nodo interior-: su par
            # opuesto sirve el eje X (siempre segmentado, ver
            # x_mouth_offset_mm, necesita dos bocas separadas) y su pieza
            # centrada sirve Y (continuo en cualquier nivel k>=1, necesita
            # una sola boca que se atraviese), ver interior_top_transform.
            # NO se toca el nodo interior en niveles k<nz -sigue pendiente,
            # sin datos reales todavía que confirmen su diseño correcto-.
            if k == nz
              code = '21' if code == '35'
              code = '35' if code == '40'
            elsif !k.zero?
              code = '35' if code == '21'
            end
            definition, metadata = definitions.fetch(code)
            z = grid_level_z(k, nz, sz)
            point = offset_point(origin, i * sx, j * sy, z)
            transform = connector_transform(code, point, horizontal, k, nz)
            instance = entities.add_instance(definition, transform)
            instance.name = "CON-#{code}"
            if code == '26'
              write_connector_26_attributes(instance, metadata)
            else
              PlayIdea::Conectores.write_attributes(
                instance, code, 'Galvanizado', metadata
              )
            end
            counts[code] += 1
          end
        end
      end
    end

    def horizontal_directions(i, j, nx, ny)
      directions = []
      directions << X_AXIS if i < nx
      directions << X_AXIS.reverse if i > 0
      directions << Y_AXIS if j < ny
      directions << Y_AXIS.reverse if j > 0
      directions
    end

    # Código estructural (por CANTIDAD de direcciones), sin conocer todavía
    # el nivel k. El nivel decide luego, en create_grid_connectors, si un
    # nodo de 2 direcciones (esquina real) o de 3 (nodo intermedio de fila/
    # columna) necesita este código tal cual o se remapea a otro -ver el
    # override ahí mismo y los comentarios de connector_transform-.
    def connector_code_for_horizontal(horizontal)
      if horizontal.length == 2
        return '26' if horizontal[0].parallel?(horizontal[1])
        return '21'
      end
      return '35' if horizontal.length == 3
      '40'
    end

    def add_connector_instance(entities, definitions, counts, code, point, transform)
      definition, metadata = definitions.fetch(code)
      instance = entities.add_instance(definition, transform)
      instance.name = "CON-#{code}"
      if code == '26'
        write_connector_26_attributes(instance, metadata)
      else
        PlayIdea::Conectores.write_attributes(
          instance, code, 'Galvanizado', metadata
        )
      end
      counts[code] += 1
      instance
    end

    # Único punto de despacho para TODOS los niveles -antes eran dos
    # funciones separadas (una para k==0, otra para k>=1), pero esa
    # división estaba mal desde el principio: lo que realmente distingue
    # el comportamiento no es "k==0 vs el resto" sino "k==nz (arriba de
    # todo, nada continúa) vs k<nz (algo sigue de largo, sea el poste
    # entero en k==0 o partido en dos en un nivel intermedio real)".
    #   - code=='21', 2 direcciones (esquina real):
    #       k==nz  -> corner_transform (normal, Principal asimétrico hacia
    #                 abajo está bien porque nada sigue arriba).
    #       k==0   -> bottom_corner_transform (Verde se voltea a tocar el
    #                 61 porque el poste sigue de largo, completo, arriba).
    #       0<k<nz -> NO debería llegar aquí -create_grid_connectors ya
    #                 remapea esquinas reales a '35' en niveles
    #                 intermedios reales, ver ahí el porqué-.
    #   - code=='21', 3 direcciones (nodo intermedio de fila/columna):
    #       solo llega aquí cuando k==nz (ver el mismo remapeo) ->
    #       middle_transform.
    #   - code=='35' (siempre 0<k<nz o k==0 con 3 direcciones, nunca
    #     k==nz, por el mismo remapeo):
    #       k==0   -> edge_transform_35 (el poste pasa CONTINUO por este
    #                 nivel, solo necesita una funda simétrica -"Verde"
    #                 sustituyendo el manguito central original, ver
    #                 build_connector_35_verde-, sin tocar la orientación
    #                 horizontal normal del cuerpo).
    #       0<k<nz -> swapped_z_body_transform (aquí el poste SÍ se parte
    #                 en dos -ver create_grid_tubes-, así que el PAR
    #                 OPUESTO de ramales del cuerpo -normalmente
    #                 horizontal- se reorienta para servir Z, recibiendo
    #                 cada mitad del poste por separado).
    def connector_transform(code, point, horizontal, k, nz)
      case code
      when '21'
        if horizontal.length == 2
          k.zero? ? bottom_corner_transform(point, horizontal) : corner_transform(point, horizontal + [Z_AXIS.reverse])
        else
          middle_transform(point, horizontal)
        end
      when '26'
        straight_transform_26(point, horizontal)
      when '35'
        if horizontal.length == 4
          interior_top_transform(point, horizontal)
        else
          k.zero? ? edge_transform_35(point, horizontal) : swapped_z_body_transform(point, horizontal)
        end
      when '40'
        k.zero? ? Geom::Transformation.translation(point) : interior_middle_transform(point)
      else
        Geom::Transformation.translation(point)
      end
    end

    # Nodo intermedio de una fila/columna (3 direcciones horizontales):
    # exactamente una es "sencilla" (sin pareja opuesta en la lista) y las
    # otras dos son un eje completo (ambas direcciones presentes). Reusa el
    # MISMO cuerpo del 21 sin modificarlo -Azul a la sencilla, Verde
    # -centrada- al eje completo, sirviendo de paso continuo-, sin importar
    # si ese eje es X o Y en el mundo -a diferencia de corner_transform, que
    # ata Azul a X y Verde a Y fijo, aquí el amarre es por rol, no por eje-.
    def middle_transform(point, horizontal)
      single = horizontal.find do |direction|
        horizontal.none? { |other| other.samedirection?(direction.reverse) }
      end
      continuous = horizontal.find { |direction| !direction.samedirection?(single) }
      world_axes = Geom::Transformation.axes(point, single.reverse, continuous, Z_AXIS)
      local_anchor_correction = Geom::Transformation.translation(
        Geom::Vector3d.new(-RECEIVER_RADIUS_MM.mm, 0, -RECEIVER_RADIUS_MM.mm)
      )
      world_axes * local_anchor_correction
    end

    # El 26 base está alineado sobre X. Se gira 90 grados cuando la línea
    # intermedia corre sobre el eje Y.
    #
    # `Transformation.rotation(point, eje, angulo)` NO coloca el origen local
    # del conector en `point` -solo garantiza que `point` quede fijo al girar-;
    # como origen local (0,0,0) de esta definición representa el nodo, hay que
    # girar alrededor de ORIGIN (ahí sí queda fijo en 0,0,0) y LUEGO trasladar
    # a `point`. Usar rotation(point,...) solo, como transform de colocación,
    # deja el conector en un lugar completamente distinto al nodo real -ver
    # misma corrección en edge_transform_35, donde se confirmó numéricamente-.
    def straight_transform_26(point, horizontal)
      along_y = horizontal.first.parallel?(Y_AXIS)
      angle = along_y ? 90.degrees : 0.degrees
      Geom::Transformation.translation(point) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, angle)
    end

    # El conector 21 base apunta a -X, +Y y -Z. Esta transformación alinea
    # sus tres receptores con las tres direcciones reales de cada esquina.
    def corner_transform(point, directions)
      x_target = directions.find { |vector| vector.parallel?(X_AXIS) }
      y_target = directions.find { |vector| vector.parallel?(Y_AXIS) }
      z_target = directions.find { |vector| vector.parallel?(Z_AXIS) }
      world_axes = Geom::Transformation.axes(
        point, x_target.reverse, y_target, z_target.reverse
      )
      # En el 21 aprobado, el nodo común está en (radio, 0, radio), no en el
      # origen de la definición. Se compensa para que las bocas horizontales
      # y el poste vertical coincidan con el nodo matemático de la cuadrícula.
      local_anchor_correction = Geom::Transformation.translation(
        Geom::Vector3d.new(
          -RECEIVER_RADIUS_MM.mm,
          0,
          -RECEIVER_RADIUS_MM.mm
        )
      )
      world_axes * local_anchor_correction
    end

    # Variante del 21 para el nivel 0 (BOTTOM_GRID_HEIGHT_MM): "Verde" -ya
    # centrada por conectores_playidea- pasa a apuntar hacia abajo para tocar
    # el receptor 61, mientras "Principal" pasa a servir la dirección Y y
    # "Azul" conserva la X. Es el mismo patrón que corner_transform pero
    # intercambiando los papeles de Y y Z.
    def bottom_corner_transform(point, directions)
      x_target = directions.find { |vector| vector.parallel?(X_AXIS) }
      y_target = directions.find { |vector| vector.parallel?(Y_AXIS) }
      world_axes = Geom::Transformation.axes(
        point, x_target.reverse, Z_AXIS, y_target.reverse
      )
      # El nodo común de la definición sigue en (radio, 0, radio) -el centro
      # de "Verde" tras su fix de centrado coincide con ese mismo punto-, así
      # que el ancla es idéntica a la de corner_transform.
      local_anchor_correction = Geom::Transformation.translation(
        Geom::Vector3d.new(-RECEIVER_RADIUS_MM.mm, 0, -RECEIVER_RADIUS_MM.mm)
      )
      world_axes * local_anchor_correction
    end

    # El 35 base tiene ramales +X, -X y +Y; le falta -Y. Se gira para que
    # esa dirección ausente coincida con el exterior del perímetro.
    def edge_transform_35(point, horizontal)
      all = [X_AXIS, X_AXIS.reverse, Y_AXIS, Y_AXIS.reverse]
      missing = all.find do |candidate|
        horizontal.none? { |direction| direction.samedirection?(candidate) }
      end
      angle =
        if missing.samedirection?(Y_AXIS.reverse)
          0.degrees
        elsif missing.samedirection?(X_AXIS)
          90.degrees
        elsif missing.samedirection?(Y_AXIS)
          180.degrees
        else
          -90.degrees
        end
      # Ver nota en straight_transform_26: rotation(point,...) sola NO coloca
      # el origen local en `point`, solo lo deja fijo si ya estuviera ahí.
      # Verificado con datos reales: con este bug, el conector de (0,1168.4)
      # con angle=-90° terminaba en (-1168.4,1168.4,0) -un módulo entero de
      # distancia-, coincidiendo exactamente con la fórmula
      # point - rotate(angle, point). Se gira primero alrededor de ORIGIN y
      # se traslada después a `point`.
      Geom::Transformation.translation(point) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, angle)
    end

    # Nivel intermedio REAL (0<k<nz, solo existe con modules_z>=2): aquí el
    # poste Z se PARTE en dos tramos en vez de pasar continuo (ver
    # create_grid_tubes) -confirmado con datos reales del usuario: el
    # bounding box del conector crece en Z, no en el eje horizontal que
    # tendría el 35 normal-. El cuerpo del 35 (par opuesto de ramales +
    # ramal sencillo + pieza centrada, ver build_connector_35_verde) se
    # reorienta para que el PAR OPUESTO -normalmente horizontal- sirva Z en
    # su lugar, recibiendo cada mitad del poste por separado; las dos
    # direcciones horizontales reales de este nodo -sean 2 de una esquina
    # real o 1 sencilla + 1 continua de un nodo intermedio de fila/
    # columna- las cubren el ramal sencillo y la pieza centrada, sin
    # importar cuál sea cuál -ambas alcanzan igual de bien una dirección
    # sencilla; la centrada de más simplemente sobra un poco, sin problema-.
    # Verificado con datos reales: para una esquina con horizontal=
    # [X_AXIS.reverse, Y_AXIS], esta fórmula predice xaxis=[0,0,1],
    # yaxis=[-1,0,0], zaxis=[0,1,0] -coincide exactamente con lo medido-.
    def swapped_z_body_transform(point, horizontal)
      single = horizontal.find do |direction|
        horizontal.none? { |other| other.samedirection?(direction.reverse) }
      end
      other = horizontal.find { |direction| !direction.samedirection?(single) && !direction.parallel?(single) }
      Geom::Transformation.axes(point, Z_AXIS, single, other)
    end

    # Nodo interior verdadero (4 direcciones horizontales: los dos ejes
    # completos, X e Y) en el nivel MÁS ALTO (k==nz) — el único caso donde
    # esto se remapea a '35' en vez de quedarse en '40', ver el override en
    # create_grid_connectors. El 21 no sirve aquí -solo tiene 2 salidas
    # horizontales, hacen falta 4-, así que se reusa el mismo cuerpo del 35
    # (par opuesto + ramal sencillo + pieza centrada, build_connector_35_verde)
    # con una tercera asignación de roles: el par opuesto sirve el eje X
    # -SIEMPRE segmentado en cualquier nivel, ver x_mouth_offset_mm, necesita
    # dos bocas separadas para los dos tramos que llegan-; la pieza centrada
    # sirve Y -continuo en cualquier nivel k>=1, ver y_mouth_offset_mm,
    # necesita una sola boca que se atraviese de lado a lado-; el ramal
    # sencillo sirve Z hacia abajo -asimétrico, como Principal en una
    # esquina real de este mismo nivel, porque nada continúa arriba-.
    # Verificado con datos reales: para horizontal=[X_AXIS,X_AXIS.reverse,
    # Y_AXIS,Y_AXIS.reverse] predice xaxis=[1,0,0], yaxis=[0,0,-1],
    # zaxis=[0,1,0] -coincide con lo medido, la posición coincide dentro de
    # 1mm de diferencia-.
    def interior_top_transform(point, horizontal)
      x_target = horizontal.find { |direction| direction.parallel?(X_AXIS) }
      y_target = horizontal.find { |direction| direction.parallel?(Y_AXIS) }
      Geom::Transformation.axes(point, x_target, Z_AXIS.reverse, y_target)
    end

    # Nodo interior verdadero (4 direcciones) en un nivel intermedio REAL
    # (0<k<nz) — el poste Z se parte ahí (ver create_grid_tubes), igual que
    # en swapped_z_body_transform, pero aquí NO hace falta ninguna pieza
    # nueva ni reasignar roles por búsqueda: el 40 original -sin tocar- ya
    # tiene, de fábrica, exactamente las tres piezas necesarias con la
    # forma correcta -su manguito central YA es continuo/simétrico
    # (`add_sleeve` centrado en Z_AXIS, igual patrón que `add_centered_sleeve`)
    # y sus 4 ramales YA son dos pares independientes (±X, ±Y)-, solo hace
    # falta permutar a qué eje del mundo apunta cada uno: el manguito
    # central -continuo- sirve Y (continuo en cualquier nivel k>=1, ver
    # y_mouth_offset_mm); el par ±Y -dos ramales SEPARADOS- se reorienta a
    # Z, recibiendo cada mitad del poste partido; el par ±X se queda en X
    # -siempre segmentado, cada ramal ya sirve un tramo distinto sin
    # cambios-. No hay ambigüedad de "cuál eje es cuál" que resolver por
    # búsqueda -a diferencia de swapped_z_body_transform/interior_top_
    # transform-: en un nodo de 4 direcciones X e Y SIEMPRE están completos
    # los dos, así que el mapeo es fijo. Verificado con datos reales: el
    # signo exacto de Y (aquí invertido) no importa -la pieza central es
    # simétrica, cualquier signo da el mismo resultado físico-, coincide
    # con lo medido de todos modos.
    def interior_middle_transform(point)
      Geom::Transformation.axes(point, X_AXIS, Z_AXIS, Y_AXIS.reverse)
    end

    def add_oriented_instance(entities, definition, point, direction)
      helper = direction.parallel?(Z_AXIS) ? X_AXIS : Z_AXIS
      x_axis = helper.cross(direction).normalize
      y_axis = direction.cross(x_axis).normalize
      transform = Geom::Transformation.axes(
        point, x_axis, y_axis, direction
      )
      instance = entities.add_instance(definition, transform)
      definition.attribute_dictionaries&.each do |dictionary|
        dictionary.each_pair do |key, value|
          instance.set_attribute(dictionary.name, key, value)
        end
      end
      instance
    end

    def offset_point(origin, x, y, z)
      Geom::Point3d.new(origin.x + x, origin.y + y, origin.z + z)
    end

    def write_module_attributes(group, params, connector_counts, padding_length_mm = 0.0)
      # Ver create_grid_tubes: X siempre va segmentado (un tramo por módulo,
      # en todos los niveles); Y va segmentado solo en el nivel 0 y continuo
      # -un tramo por columna- en cualquier nivel k>=1; el poste Z se parte
      # en un tramo por nivel (nz tramos por columna, ya no uno continuo).
      nx = params[:modules_x]
      ny = params[:modules_y]
      nz = params[:modules_z]
      tube_counts = {
        x: nx * (ny + 1) * (nz + 1),
        y: (nx + 1) * (ny + nz),
        z: (nx + 1) * (ny + 1) * nz
      }
      total_tubes = tube_counts.values.inject(0, :+)
      # El largo total no depende de en cuántos tramos se corte cada fila/
      # columna/poste -mismo material, solo cambia cuántas piezas son-.
      # EXPERIMENTAL: spacing_z_mm puede ser Array -altura variable por
      # módulo-, ahí la altura total es la suma, no nz*valor.
      altura_z_total_mm = params[:spacing_z_mm].is_a?(Array) ? params[:spacing_z_mm].sum : nz * params[:spacing_z_mm]
      total_length_mm =
        (ny + 1) * (nz + 1) * nx * params[:spacing_x_mm] +
        (nx + 1) * (nz + 1) * ny * params[:spacing_y_mm] +
        (nx + 1) * (ny + 1) * (
          BASE_GRID_HEIGHT_MM +
          altura_z_total_mm
        )
      data = {
        'code' => params[:code],
        'modules_x' => params[:modules_x],
        'modules_y' => params[:modules_y],
        'modules_z' => params[:modules_z],
        'spacing_x_mm' => params[:spacing_x_mm],
        'spacing_y_mm' => params[:spacing_y_mm],
        'spacing_z_mm' => params[:spacing_z_mm],
        'tube_count_x' => tube_counts[:x],
        'tube_count_y' => tube_counts[:y],
        'tube_count_z' => tube_counts[:z],
        'tube_count_total' => total_tubes,
        'tube_total_length_mm' => total_length_mm,
        'connector_counts_json' => JSON.generate(connector_counts),
        'base_grid_height_mm' => BASE_GRID_HEIGHT_MM,
        'geometry_basis' => 'ejes normalizados; poste vertical continuo; penetración pendiente de calibración',
        'type' => 'modulo'
      }
      data.merge!(padding_attributes(params, padding_length_mm)) if params[:padding]
      data.each { |key, value| group.set_attribute(DICTIONARY, key, value) }
      group.set_attribute('minorusal_auditor', 'code', params[:code])
      group.set_attribute(
        'minorusal_auditor', 'investment_cost_mxn', data['padding_investment_cost_mxn']
      ) if params[:padding]
    end

    # Costo por tubo terminado de 2.4m: 1.2x el tubo crudo -ver
    # PADDING_RAW_MATERIAL_FACTOR- más cada paso de mano de obra/insumos
    # capturado en capture_padding_costs. El número de tubos necesarios se
    # redondea hacia arriba -no se puede comprar/fabricar una fracción de
    # tubo terminado-.
    def padding_attributes(params, padding_length_mm)
      costs = params[:padding_costs]
      sticks_needed = (padding_length_mm / PADDING_FINISHED_LENGTH_MM).ceil
      cost_per_stick =
        (costs['raw_tube'] * PADDING_RAW_MATERIAL_FACTOR) +
        costs['perforation_labor'] + costs['electricity'] +
        costs['splice_labor'] + costs['wrap_material'] +
        costs['adhesive'] + costs['apply_labor'] + costs['weld_labor']
      {
        'padding_outside_mm' => PADDING_OUTSIDE_MM,
        'padding_inside_mm' => PADDING_INSIDE_MM,
        'padding_total_length_mm' => padding_length_mm.round(1),
        'padding_finished_sticks_needed' => sticks_needed,
        'padding_cost_per_stick_mxn' => cost_per_stick.round(2),
        'padding_investment_cost_mxn' => (sticks_needed * cost_per_stick).round(2),
        'padding_cost_breakdown_json' => JSON.generate(costs)
      }
    end

    def unique_name(model, base)
      name = base
      index = 2
      while model.definitions[name]
        name = "#{base} (#{index})"
        index += 1
      end
      name
    end

    # Coloca la estructura y, si `params[:tower]` viene lleno -checkbox
    # "Agregar torre de pisos triangulares" marcado en el mismo diálogo de
    # crear estructura-, encadena UN SEGUNDO clic para la esquina de la
    # torre, todo dentro de la MISMA herramienta/operación de colocación
    # -sin ventanas ni confirmaciones de por medio-, para poder crear
    # estructura + torre juntas en un solo flujo.
    class ModulePlacementTool
      def initialize(params)
        @params = params
        @input = Sketchup::InputPoint.new
      end

      def activate
        Sketchup.set_status_text(
          'Haz clic para colocar la esquina inferior del módulo.',
          SB_PROMPT
        )
      end

      def onMouseMove(_flags, x, y, view)
        @input.pick(view, x, y)
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @input.pick(view, x, y)
        return unless @input.valid?
        ConstructorModulos.create_module(@params, @input.position)
        if @params[:tower]
          tower = @params[:tower]
          tower_origin = ConstructorModulos.offset_point(
            @input.position, tower[:offset_x_mm].mm, tower[:offset_y_mm].mm, 0
          )
          ConstructorModulos.create_triangle_tower(tower, tower_origin)
        end
        Sketchup.active_model.select_tool(nil)
      rescue StandardError => error
        UI.messagebox(
          "No fue posible crear la estructura:\n#{error.message}\n\n" \
          "Ubicación: #{error.backtrace&.first}"
        )
        puts error.full_message
        Sketchup.active_model.select_tool(nil)
      end

      def draw(view)
        @input.draw(view) if @input.valid?
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end
    end

    class TriangleTowerPlacementTool
      def initialize(params)
        @params = params
        @input = Sketchup::InputPoint.new
      end

      def activate
        Sketchup.set_status_text(
          'Haz clic para colocar la esquina suroeste de la celda de la torre.',
          SB_PROMPT
        )
      end

      def onMouseMove(_flags, x, y, view)
        @input.pick(view, x, y)
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @input.pick(view, x, y)
        return unless @input.valid?
        ConstructorModulos.create_triangle_tower(@params, @input.position)
        Sketchup.active_model.select_tool(nil)
        if UI.messagebox('¿Agregar otra torre de pisos triangulares?', MB_YESNO) == IDYES
          ConstructorModulos.start_triangle_tower(
            color: @params[:color],
            cell_x_m: @params[:cell_x_mm] / 1000.0,
            cell_y_m: @params[:cell_y_mm] / 1000.0
          )
        end
      rescue StandardError => error
        UI.messagebox(
          "No fue posible crear la torre triangular:\n#{error.message}\n\n" \
          "Ubicación: #{error.backtrace&.first}"
        )
        puts error.full_message
        Sketchup.active_model.select_tool(nil)
      end

      def draw(view)
        @input.draw(view) if @input.valid?
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end
    end

    # `prefill` -opcional- llega cuando esta torre se abre encadenada
    # justo después de crear una estructura (ModulePlacementTool) o de
    # colocar otra torre (TriangleTowerPlacementTool), para no obligar al
    # usuario a volver a escribir el color/medida de celda que ya usó.
    def start_triangle_tower(prefill = {})
      unless defined?(UI::HtmlDialog)
        UI.messagebox('Esta herramienta necesita una versión de SketchUp compatible con HtmlDialog.')
        return
      end
      unless dependencies_available?
        UI.messagebox(
          "No se encontraron los plugins de tubos y conectores.\n\n" \
          'Instálalos y reinicia SketchUp antes de crear una torre.'
        )
        return
      end

      @triangle_dialog&.close
      @triangle_dialog = UI::HtmlDialog.new(
        dialog_title: 'Torre de Pisos Triangulares Play Idea',
        preferences_key: 'PlayIdeaTorreTriangular',
        scrollable: true,
        resizable: true,
        width: 560,
        height: 620,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @triangle_dialog.set_file(File.join(__dir__, 'torre_triangular.html'))
      @triangle_dialog.add_action_callback('ready') do |_action_context|
        @triangle_dialog.execute_script(
          "loadDefaults(#{JSON.generate(
            default_spacing_m: prefill[:cell_x_m] || DEFAULT_SPACING_M,
            default_spacing_y_m: prefill[:cell_y_m] || prefill[:cell_x_m] || DEFAULT_SPACING_M,
            step_spacing_mm: TRIANGLE_STEP_SPACING_MM,
            color: prefill[:color]
          )})"
        )
      end
      @triangle_dialog.add_action_callback('createTriangleTower') do |_action_context, data|
        params = validate_triangle_dialog_data(data)
        next unless params
        @triangle_dialog.close
        Sketchup.active_model.select_tool(TriangleTowerPlacementTool.new(params))
      end
      @triangle_dialog.show
    rescue StandardError => error
      UI.messagebox("No fue posible abrir la torre triangular:\n#{error.message}")
      puts error.full_message
    end

    def validate_triangle_dialog_data(data)
      params = {
        cell_x_mm: data['cell_x_m'].to_f * 1000.0,
        cell_y_mm: data['cell_y_m'].to_f * 1000.0,
        right_angle_corner: data['corner'].to_s.to_sym,
        steps: data['steps'].to_i,
        start_height_mm: data['start_height_m'].to_f * 1000.0,
        step_spacing_mm: data['step_spacing_mm'].to_f,
        color: data['color'].to_s,
        code: data['code'].to_s.strip
      }
      valid = params[:cell_x_mm].positive? && params[:cell_y_mm].positive? &&
        params[:steps].between?(1, 50) && params[:step_spacing_mm].positive? &&
        TRIANGLE_CORNER_ORDER.include?(params[:right_angle_corner])
      unless valid
        UI.messagebox('Revisa las medidas de celda, la cantidad de escalones (1-50) y la esquina elegida.')
        return nil
      end
      # El primer escalón no puede arrancar en el nivel 0 -ahí ya está el
      # conector 61 recibiendo el poste vertical, no cabe un tubo diagonal
      # a 45° en ese nivel, en ninguna orientación-.
      if params[:start_height_mm] < BOTTOM_GRID_HEIGHT_MM
        UI.messagebox(
          "La altura inicial debe ser de al menos #{(BOTTOM_GRID_HEIGHT_MM / 1000.0).round(3)}m -en el " \
          'nivel 0 ya está el conector 61 del poste vertical, no cabe un escalón triangular ahí.'
        )
        return nil
      end
      params[:code] = "TORRE-#{params[:steps]}" if params[:code].empty?
      params
    end

    # Coloca un CON-12 en `point` con la orientación exacta de
    # TRIANGLE_CONNECTOR_AXES_CAPPED -ver ese comentario- para
    # (`right_angle_corner`, `role`).
    def diagonal_connector_transform(point, right_angle_corner, role)
      local_x, local_y, local_z = TRIANGLE_CONNECTOR_AXES_CAPPED[right_angle_corner][role]
      Geom::Transformation.axes(point, local_x, local_y, local_z)
    end

    # El punto real donde debe llegar el tubo diagonal: por el codo de 45°
    # del receptor mitrado de build_12, es un desplazamiento COMPUESTO en 2
    # ejes locales del propio CON-12 -no un solo eje-. Medido directo en
    # los 4 CON-12 con tapa de reporte_grupo_20260806_110850.txt -2
    # escalones × 2 conectores-, comparando cada boca calculada contra el
    # extremo real del tubo diagonal: X local dio -11.99, -10.16, -9.93 y
    # +0.68mm -mediana -10.05-; Z local dio -26.28, -27.18, -32.67 y
    # -19.76mm -mediana -26.73-. Bastante ruido entre las 4 muestras -son
    # de una estructura hecha a mano, no todas van a calzar igual de bien-,
    # así que si se sigue viendo desfasado hace falta una referencia más
    # limpia -solo estos 2 tubos diagonales, sin el resto de la
    # estructura alrededor- para afinar más. `transform` es el resultado
    # de `diagonal_connector_transform` para ese mismo conector.
    # Ajustado con la indicación del usuario -"hacia la parte contraria de
    # donde forma el ángulo de 45"-. Primer intento: -10.05 a -12.0mm en X
    # local -insuficiente-. Segundo intento: subir la magnitud a -22.0mm
    # -CONFIRMADO AL REVÉS por el usuario, eso movió el punto HACIA el
    # ángulo de 45, no en contra-. Corregido: hacer X local MENOS negativo
    # -no más- para alejarse del ángulo. Desde -12.0mm, +10mm en esa
    # dirección: -2.0mm.
    DIAGONAL_MOUTH_LOCAL_X_MM = -2.0
    DIAGONAL_MOUTH_LOCAL_Z_MM = -28.5
    def diagonal_connector_mouth(transform)
      Geom::Point3d.new(DIAGONAL_MOUTH_LOCAL_X_MM.mm, 0, DIAGONAL_MOUTH_LOCAL_Z_MM.mm).transform(transform)
    end

    # CON-21 en el ángulo recto: orientación de TRIANGLE_CONNECTOR_21_AXES,
    # colocado exactamente en la esquina (mismo punto que usa `near`/`far`
    # para el CON-12, sin inset -ver triangle_cell_corners-).
    def right_angle_connector_transform(point, right_angle_corner)
      local_x, local_y, local_z = TRIANGLE_CONNECTOR_21_AXES[right_angle_corner]
      Geom::Transformation.axes(point, local_x, local_y, local_z)
    end

    # CON-10 en cada esquina vecina del ángulo recto: orientación de
    # TRIANGLE_CONNECTOR_10_AXES, colocado en la MISMA esquina que usa el
    # CON-12 de esa pata (`near`/`far`).
    def leg_connector_transform(point, right_angle_corner, leg_role)
      local_x, local_y, local_z = TRIANGLE_CONNECTOR_10_AXES[right_angle_corner][leg_role]
      Geom::Transformation.axes(point, local_x, local_y, local_z)
    end

    # Dado el ángulo recto elegido (una de TRIANGLE_CORNER_ORDER), devuelve
    # las esquinas [near, far] de la diagonal que SÍ construye este plugin
    # -ver el comentario DIRECCIÓN junto a TRIANGLE_CORNER_ORDER-: `near` es
    # la esquina siguiente a la elegida en ese orden fijo, `far` la
    # anterior. Verificado exacto contra los 4 ejemplos corregidos por el
    # usuario (NO→near=NE,far=SO; SE→near=SO,far=NE; NE→near=SE,far=NO;
    # SO→near=NO,far=SE).
    def diagonal_near_far_corners(right_angle_corner, corners)
      order = TRIANGLE_CORNER_ORDER
      idx = order.index(right_angle_corner)
      near_key = order[(idx + 1) % order.length]
      far_key = order[(idx - 1) % order.length]
      [corners[near_key], corners[far_key]]
    end

    # Las 4 esquinas de la celda de la torre, con `origin` -el punto que
    # marca el usuario- siempre como la esquina SO. `z` ya viene en
    # unidades reales de SketchUp (con `.mm` aplicado).
    def triangle_cell_corners(origin, params, z)
      {
        sw: offset_point(origin, 0, 0, z),
        se: offset_point(origin, params[:cell_x_mm].mm, 0, z),
        ne: offset_point(origin, params[:cell_x_mm].mm, params[:cell_y_mm].mm, z),
        nw: offset_point(origin, 0, params[:cell_y_mm].mm, z)
      }
    end

    # `origin` es la esquina SO de la celda -la que el usuario marca con el
    # clic-. Los escalones se apilan hacia arriba desde `start_height_mm`,
    # cada `step_spacing_mm` -600mm por defecto, confirmado con datos
    # reales-, TODOS con la MISMA diagonal -sin alternar entre escalones,
    # ver el comentario grande junto a TRIANGLE_STEP_SPACING_MM-. El primer
    # y último escalón llevan además las 2 patas + CON-21 + 2×CON-10 -ver
    # TRIANGLE_CONNECTOR_21_AXES-; no toca ningún conector de la cuadrícula
    # base -verificado que esos escalones no coinciden con niveles reales
    # de la estructura, ver el mismo comentario-.
    def create_triangle_tower(params, origin)
      model = Sketchup.active_model
      model.start_operation("Crear torre triangular #{params[:code]}", true)
      container = model.active_entities.add_group
      container.name = params[:code]
      entities = container.entities

      material = PlayIdea::Conectores.connector_material(model, 'Galvanizado')
      hardware = PlayIdea::Conectores.hardware_material(model)
      con12_definition = model.definitions.add(unique_name(model, 'CON-MOD-12'))
      PlayIdea::Conectores.build_connector_geometry(con12_definition.entities, '12', material, hardware)
      metadata12 = connector_metadata('12')
      PlayIdea::Conectores.write_attributes(con12_definition, '12', 'Galvanizado', metadata12)

      con21_definition = model.definitions.add(unique_name(model, 'CON-MOD-21'))
      PlayIdea::Conectores.build_connector_geometry(con21_definition.entities, '21', material, hardware)
      metadata21 = connector_metadata('21')
      PlayIdea::Conectores.write_attributes(con21_definition, '21', 'Galvanizado', metadata21)

      con10_definition = model.definitions.add(unique_name(model, 'CON-MOD-10'))
      PlayIdea::Conectores.build_connector_geometry(con10_definition.entities, '10', material, hardware)
      metadata10 = connector_metadata('10')
      PlayIdea::Conectores.write_attributes(con10_definition, '10', 'Galvanizado', metadata10)

      tube_cache = {}

      # EXPERIMENTAL: `params[:step_heights_mm]` -lista de alturas, una
      # por escalón, tramo por tramo entre niveles reales, ver
      # `auto_tower_step_heights`- si viene de `tower_params_from_dialog`;
      # si no viene -flujo del diálogo manual de torre suelta, sin
      # estructura de referencia, con `steps`+`start_height_mm`+
      # `step_spacing_mm` fijos en su lugar-, se genera la lista
      # equivalente con separación uniforme, igual que antes.
      step_heights_mm = params[:step_heights_mm] ||
        Array.new(params[:steps]) { |step| params[:start_height_mm] + step * params[:step_spacing_mm] }

      step_heights_mm.each_with_index do |z_mm, step|
        # TODOS los escalones llevan el triángulo completo -diagonal +
        # CON-21 + 2 patas-, no solo el primero y el último. Antes solo
        # esos 2 lo llevaban -diseño original, confirmado contra la
        # referencia aislada de 4 torres, que solo tenía 2 o 3 escalones
        # y nunca escalaba con nz-; con torres de más escalones -nz>1- el
        # usuario confirmó que cada escalón necesita su propio ángulo
        # recto, no solo los extremos.
        # Los escalones ALTERNAN esquina: el escalón 0 usa la esquina dada
        # -params[:right_angle_corner]-, el escalón 1 usa la esquina
        # CONTRARIA -diagonalmente opuesta en la celda-, el 2 vuelve a la
        # dada, etc. Confirmado con datos reales -reporte_grupo_20260806_
        # 110850.txt-: el CON-21 del escalón 1 estaba pegado a una
        # esquina, y el del escalón 2 pegado a la esquina diagonalmente
        # opuesta, no a la misma. Antes este código usaba SIEMPRE la
        # misma esquina en todos los escalones -confirmado erróneo-.
        step_corner = if step.even?
                        params[:right_angle_corner]
                      else
                        idx = TRIANGLE_CORNER_ORDER.index(params[:right_angle_corner])
                        TRIANGLE_CORNER_ORDER[(idx + 2) % 4]
                      end
        z = z_mm.mm
        corners = triangle_cell_corners(origin, params, z)
        near, far = diagonal_near_far_corners(step_corner, corners)
        ra_point = corners[step_corner]

        # Solo el CON-12 se aleja de la esquina real -a lo largo de su
        # PROPIO borde de celda, hacia la esquina del ÁNGULO RECTO, NO a
        # lo largo de la diagonal hacia la esquina opuesta-. Confirmado
        # con datos reales -reporte_grupo_20260806_110850.txt, parseado
        # con script-: en las 4 instancias medidas, el desplazamiento real
        # fue puro ±X o puro ±Y -nunca diagonal a 45°-, siempre apuntando
        # hacia la esquina del ángulo recto de ese escalón. También
        # confirmado contra DISENOS_REFERENCIA -diseño 1, escalón capped-.
        # El código anterior movía cada CON-12 hacia el OTRO extremo de la
        # diagonal -confirmado erróneo, por eso el tubo no embonaba bien-.
        # `near`/`far` SIN alejar se siguen usando tal cual para el CON-21
        # y los CON-10 -esos si van pegados a la columna real, confirmado
        # con datos-, así que no se tocan aquí.
        near_diag = near.offset((ra_point - near).normalize, TRIANGLE_DIAGONAL_INSET_MM.mm)
        far_diag = far.offset((ra_point - far).normalize, TRIANGLE_DIAGONAL_INSET_MM.mm)

        transform_near = diagonal_connector_transform(near_diag, step_corner, :near)
        transform_far = diagonal_connector_transform(far_diag, step_corner, :far)
        mouth_near = diagonal_connector_mouth(transform_near)
        mouth_far = diagonal_connector_mouth(transform_far)
        tube_vector = mouth_far - mouth_near
        tube_length_mm = tube_vector.length.to_mm

        if tube_length_mm <= 0
          model.abort_operation
          UI.messagebox('La celda es demasiado pequeña para que el tubo diagonal quepa entre los dos conectores.')
          return nil
        end
        tube_direction = tube_vector.normalize
        tube_definition = tube_cache[tube_length_mm.round(4)] ||=
          create_tube_definition(model, tube_length_mm, params[:color], 'DIAG')
        add_oriented_instance(entities, tube_definition, mouth_near, tube_direction)

        [transform_near, transform_far].each do |transform|
          instance = entities.add_instance(con12_definition, transform)
          instance.name = 'CON-12'
          PlayIdea::Conectores.write_attributes(instance, '12', 'Galvanizado', metadata12)
        end

        # EXPERIMENTAL: si la altura de este escalón COINCIDE con un nivel
        # real de la cuadrícula -tolerancia GRID_LEVEL_COINCIDENCE_
        # TOLERANCE_MM-, ese nivel YA tiene sus propios conectores/tubos
        # ahí -CON-61 y el tubo recto de esquina a esquina-, así que este
        # escalón NO pone el CON-21 + 2 patas -se duplicaría con lo que ya
        # existe-, solo la diagonal de arriba. `real_grid_levels_mm` viene
        # de `tower_params_from_dialog`; si no viene, se trata como si
        # nunca coincidiera.
        grid_levels = params[:real_grid_levels_mm] || []
        coincide_con_nivel_real = grid_levels.any? { |lvl| (z.to_mm - lvl).abs < GRID_LEVEL_COINCIDENCE_TOLERANCE_MM }
        next if coincide_con_nivel_real

        # El CON-21 también se aleja de su esquina real, hacia la esquina
        # OPUESTA de la celda -la que no toca ni la diagonal ni ninguna
        # pata-, ver TRIANGLE_RIGHT_ANGLE_INSET_MM.
        opposite_key = TRIANGLE_CORNER_ORDER[(TRIANGLE_CORNER_ORDER.index(step_corner) + 2) % 4]
        ra_point_inset = ra_point.offset((corners[opposite_key] - ra_point).normalize, TRIANGLE_RIGHT_ANGLE_INSET_MM.mm)

        transform_ra = right_angle_connector_transform(ra_point_inset, step_corner)
        ra_instance = entities.add_instance(con21_definition, transform_ra)
        ra_instance.name = 'CON-21'
        PlayIdea::Conectores.write_attributes(ra_instance, '21', 'Galvanizado', metadata21)

        { near: near, far: far }.each do |leg_role, leg_point|
          transform_leg = leg_connector_transform(leg_point, step_corner, leg_role)
          # El tubo de la pata NO va del CON-21 -ya movido 34.65mm- al
          # CON-10: es un tubo de borde de celda ESTÁNDAR, esquina cruda a
          # esquina cruda -ra_point a leg_point-, con la misma inserción
          # RECEIVER_RADIUS_MM -24.15mm- que cualquier tubo recto de la
          # cuadrícula, no TRIANGLE_MOUTH_INSET_MM -12.075mm-. Confirmado
          # con datos reales -reporte_grupo_20260806_110850.txt-: el
          # nombre del tubo real es 1120.1mm = separación de celda menos
          # 2×24.15mm, exactamente la fórmula de un tubo de borde normal,
          # y ambos extremos caen a ~1-3mm de esa fórmula. El CON-21 sigue
          # en su posición -ya confirmada correcta-, pero el tubo no sale
          # de ahí, sale del borde real de la celda.
          mouth_ra = ra_point.offset((leg_point - ra_point).normalize, RECEIVER_RADIUS_MM.mm)
          mouth_leg = leg_point.offset((ra_point - leg_point).normalize, RECEIVER_RADIUS_MM.mm)
          leg_vector = mouth_ra - mouth_leg
          leg_length_mm = leg_vector.length.to_mm
          next if leg_length_mm <= 0
          leg_direction = leg_vector.normalize
          leg_tube_definition = tube_cache[[:leg, leg_length_mm.round(4)]] ||=
            create_tube_definition(model, leg_length_mm, params[:color], 'PATA')
          add_oriented_instance(entities, leg_tube_definition, mouth_leg, leg_direction)

          leg_instance = entities.add_instance(con10_definition, transform_leg)
          leg_instance.name = 'CON-10'
          PlayIdea::Conectores.write_attributes(leg_instance, '10', 'Galvanizado', metadata10)
        end
      end

      container.set_attribute(DICTIONARY, 'type', 'torre_triangular')
      container.set_attribute(DICTIONARY, 'steps', step_heights_mm.length)
      container.set_attribute(DICTIONARY, 'step_heights_mm', step_heights_mm.join(','))
      container.set_attribute(DICTIONARY, 'right_angle_corner', params[:right_angle_corner].to_s)
      container.set_attribute('minorusal_auditor', 'code', params[:code])
      model.selection.clear
      model.selection.add(container)
      model.commit_operation
      container
    rescue StandardError
      model.abort_operation
      raise
    end

    puts '▶️  main_niveles_experimental cargado -módulo aislado, sin menú, solo para pruebas de consola-.'
  end
end
