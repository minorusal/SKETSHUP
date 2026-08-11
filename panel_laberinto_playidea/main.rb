require 'sketchup.rb'
require 'json'

module PlayIdea
  module PanelLaberinto
    extend self

    DICTIONARY = 'PlayIdeaPanelLaberinto'

    # Se imprime en consola cada vez que se genera un panel, para poder
    # confirmar a simple vista -sin adivinar- que SketchUp está corriendo
    # esta versión y no una copia vieja en caché.
    VERSION = '0.2.0-ramificado'

    # Techo de seguridad: más cuentas que esto puede volverse muy lento -cada
    # cuenta agrega una caja al canal, y todas se unen con `union` una por
    # una-.
    MAX_NUM_CUENTAS = 60

    # Cuántas cuentas precargar en el diálogo -calibrado para que el panel
    # estándar (1.1684 x 1.1684m) no salga con solo un par de carriles
    # sueltos; el usuario lo puede subir o bajar libremente.
    DEFAULT_NUM_CUENTAS = 26

    SPHERE_SEGMENTS = 16

    # Mismo valor de referencia (Módulo Play Idea estándar) que usan los
    # demás plugins de este proyecto -alberca_pelotas_playidea usa el mismo
    # DEFAULT_SPACING_M-, solo para precargar el diálogo con el ancho/alto
    # de panel por defecto.
    DEFAULT_PANEL_M = 1.1684

    # Mismo catálogo fijo de 8 colores que usan los demás plugins Play Idea
    # -colorear_tubos_playidea, alberca_pelotas_playidea-, para que las
    # cuentas combinen con el resto de piezas ya coloreadas con esta paleta.
    COLOR_PALETTE = [
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
      unless defined?(UI::HtmlDialog)
        UI.messagebox('Esta herramienta necesita una versión de SketchUp compatible con HtmlDialog.')
        return
      end

      @dialog&.close
      @dialog = UI::HtmlDialog.new(
        dialog_title: 'Panel Laberinto de Cuentas Play Idea',
        preferences_key: 'PlayIdeaPanelLaberinto',
        scrollable: true,
        resizable: true,
        width: 460,
        height: 760,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_file(File.join(__dir__, 'selector.html'))
      @dialog.add_action_callback('ready') do |_action_context|
        @dialog.execute_script(
          "loadDefaults(#{JSON.generate(
            palette: COLOR_PALETTE,
            max_cuentas: MAX_NUM_CUENTAS,
            default_panel_cm: DEFAULT_PANEL_M * 100.0,
            default_num_cuentas: DEFAULT_NUM_CUENTAS
          )})"
        )
      end
      @dialog.add_action_callback('createPanel') do |_action_context, data|
        params = validate_dialog_data(data)
        next unless params
        @dialog.close
        Sketchup.active_model.select_tool(PlacementTool.new(params))
      end
      @dialog.show
    rescue StandardError => error
      UI.messagebox("No fue posible abrir el generador de paneles:\n#{error.message}")
      puts error.full_message
    end

    def validate_dialog_data(data)
      allowed_hexes = COLOR_PALETTE.map { |c| c[:hex] }
      colors = Array(data['colors']).map(&:to_s).select { |h| allowed_hexes.include?(h) }.uniq

      params = {
        ancho_mm: data['ancho_cm'].to_f * 10.0,
        alto_mm: data['alto_cm'].to_f * 10.0,
        grosor_mm: data['grosor_mm'].to_f,
        canal_ancho_mm: data['canal_ancho_mm'].to_f,
        canal_profundidad_mm: data['canal_profundidad_mm'].to_f,
        cuenta_diametro_mm: data['cuenta_diametro_mm'].to_f,
        num_cuentas: data['num_cuentas'].to_i,
        colors: colors,
        code: data['code'].to_s.strip
      }

      valid = params[:ancho_mm].positive? && params[:alto_mm].positive? && params[:grosor_mm].positive? &&
        params[:canal_ancho_mm].positive? && params[:canal_profundidad_mm].positive? && params[:cuenta_diametro_mm].positive?
      unless valid
        UI.messagebox('Revisa las medidas del panel -deben ser mayores que cero.')
        return nil
      end
      if params[:canal_profundidad_mm] >= params[:grosor_mm]
        UI.messagebox('La profundidad del canal debe ser menor que el grosor del panel -si no, lo atraviesa de lado a lado.')
        return nil
      end
      margen_mm = margen_para(params)
      if margen_mm * 2 >= [params[:ancho_mm], params[:alto_mm]].min
        UI.messagebox(
          "El panel es muy chico para ese ancho de canal/diámetro de cuenta -necesitas un panel de al menos " \
          "#{(margen_mm * 2).round}mm por lado, o reduce el canal/la cuenta."
        )
        return nil
      end
      if params[:num_cuentas] < 3 || params[:num_cuentas] > MAX_NUM_CUENTAS
        UI.messagebox("El número de cuentas debe estar entre 3 y #{MAX_NUM_CUENTAS}.")
        return nil
      end
      if colors.empty?
        UI.messagebox('Marca al menos un color de la lista.')
        return nil
      end

      params[:code] = default_code(params) if params[:code].empty?
      params
    end

    # Qué tan lejos del borde del panel debe quedar la ruta del laberinto,
    # para que ni el canal ni las cuentas -lo que sea más ancho de los dos-
    # queden colgando fuera del panel. Se usa tanto para validar en el
    # diálogo como para generar la ruta real.
    def margen_para(params)
      [params[:canal_ancho_mm] / 2.0, params[:cuenta_diametro_mm] / 2.0].max + 15.0
    end

    def default_code(params)
      a = (params[:ancho_mm] / 10.0).round(1)
      b = (params[:alto_mm] / 10.0).round(1)
      "PANEL-LABERINTO-#{a}X#{b}CM-#{params[:num_cuentas]}CUENTAS"
    end

    def unique_name(model, base)
      return base unless model.definitions[base]
      n = 2
      n += 1 while model.definitions["#{base}-#{n}"]
      "#{base}-#{n}"
    end

    def hex_to_color(hex)
      Sketchup::Color.new(hex[0..1].to_i(16), hex[2..3].to_i(16), hex[4..5].to_i(16))
    end

    def apply_material(model, definition, material_name, hex)
      material = model.materials[material_name] || model.materials.add(material_name)
      material.color = hex_to_color(hex)
      definition.entities.grep(Sketchup::Face).each do |face|
        face.material = material
        face.back_material = material
      end
    end

    # Esfera sólida -mismo generador UV-sphere que alberca_pelotas_playidea-.
    def add_sphere_geometry(entities, diameter_mm, segments = SPHERE_SEGMENTS)
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

    # Caja sólida axis-aligned, como grupo aparte -para poder unirla/restarla
    # luego con Solid Tools-. Igual que en el script ya verificado
    # panel_laberinto_cuentas.rb v3.
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

    # Laberinto RAMIFICADO repartido por todo el panel -no una sola ruta en
    # serpentina, sino un árbol con bifurcaciones y callejones sin salida,
    # como un laberinto de verdad-. Se arma sobre una cuadrícula de celdas
    # que cubre el área útil completa del panel:
    #
    # 1. Se calcula una posición X por columna y una Y por fila -con un
    #    jitter chico pero COMPARTIDO por toda la fila/columna, no por
    #    celda-, para que cualquier tramo entre celdas vecinas salga
    #    perfectamente horizontal o vertical -add_box solo sabe armar cajas
    #    rectas alineadas a los ejes; si cada celda tuviera su propio jitter
    #    independiente en ambos ejes, un tramo "horizontal" entre dos celdas
    #    de la misma fila saldría con Y ligeramente distinta en cada punta,
    #    y la caja resultante sería un bloque ancho en vez de un canal
    #    delgado-.
    # 2. Sobre esa cuadrícula se corre un DFS aleatorio -"recursive
    #    backtracker", el algoritmo clásico de generación de laberintos-:
    #    arranca en una celda al azar, salta a una vecina sin visitar
    #    elegida al azar, y si ya no quedan vecinas libres retrocede hasta
    #    encontrar una celda con alguna vecina libre. El resultado visita
    #    TODAS las celdas -cubre todo el panel- y deja un árbol de
    #    conexiones con bifurcaciones repartidas por todos lados, no una
    #    sola línea.
    #
    # Devuelve {centros:, aristas:, rows:, cols:} -`centros[r][c]` es
    # [x_mm, y_mm] de esa celda; `aristas` es la lista de tramos
    # [[r1,c1],[r2,c2]] entre celdas vecinas conectadas-.
    def generar_laberinto_ramificado(ancho_mm, alto_mm, margen_mm, num_celdas)
      ancho_util = ancho_mm - 2 * margen_mm
      alto_util = alto_mm - 2 * margen_mm
      aspecto = ancho_util / alto_util

      cols = [(Math.sqrt(num_celdas * aspecto)).round, 2].max
      rows = [(num_celdas.to_f / cols).ceil, 2].max
      cell_w = ancho_util / cols
      cell_h = alto_util / rows

      xs_columna = (0...cols).map { |c| margen_mm + ((c + 0.5) * cell_w) + rand(-cell_w * 0.2..cell_w * 0.2) }
      ys_fila = (0...rows).map { |r| margen_mm + ((r + 0.5) * cell_h) + rand(-cell_h * 0.2..cell_h * 0.2) }
      centros = Array.new(rows) { |r| Array.new(cols) { |c| [xs_columna[c], ys_fila[r]] } }

      visitadas = Array.new(rows) { Array.new(cols, false) }
      aristas = []
      pila = []

      r, c = rand(rows), rand(cols)
      visitadas[r][c] = true
      pila.push([r, c])

      until pila.empty?
        r, c = pila.last
        vecinas = []
        vecinas << [r - 1, c] if r.positive? && !visitadas[r - 1][c]
        vecinas << [r + 1, c] if r < rows - 1 && !visitadas[r + 1][c]
        vecinas << [r, c - 1] if c.positive? && !visitadas[r][c - 1]
        vecinas << [r, c + 1] if c < cols - 1 && !visitadas[r][c + 1]

        if vecinas.empty?
          pila.pop
          next
        end

        nr, nc = vecinas.sample
        visitadas[nr][nc] = true
        aristas << [[r, c], [nr, nc]]
        pila.push([nr, nc])
      end

      { centros: centros, aristas: aristas, rows: rows, cols: cols }
    end

    # Un color al azar por cuenta, evitando repetir el mismo color que la
    # cuenta inmediata anterior -si hay más de un color marcado-, para que
    # se note la variedad en vez de salir rachas largas del mismo color.
    def colores_al_azar(count, paleta_hex)
      colores = []
      count.times do
        candidatos = paleta_hex
        candidatos = paleta_hex - [colores.last] if paleta_hex.length > 1 && colores.last
        colores << candidatos.sample
      end
      colores
    end

    # `origin` es el punto que el usuario marca con el clic -esquina
    # inferior-izquierda del panel, Z=0-. Arma el panel completo cerca del
    # origen del modelo y al final mueve el grupo contenedor a `origin`,
    # para no tener que desplazar cada punto de la geometría interna.
    def create_panel(params, origin)
      puts "▶️  panel_laberinto_playidea #{VERSION} | panel #{params[:ancho_mm]}x#{params[:alto_mm]}mm | #{params[:num_cuentas]} cuentas"
      model = Sketchup.active_model
      model.start_operation("Crear panel laberinto #{params[:code]}", true)
      container = model.active_entities.add_group
      container.name = params[:code]
      entities = container.entities

      panel_group = add_box(entities, 0, 0, 0, params[:ancho_mm].mm, params[:alto_mm].mm, params[:grosor_mm].mm)
      panel_group.name = 'Panel base'

      margen_mm = margen_para(params)
      laberinto = generar_laberinto_ramificado(params[:ancho_mm], params[:alto_mm], margen_mm, params[:num_cuentas])
      centros = laberinto[:centros]
      puts "   laberinto: #{laberinto[:cols]}x#{laberinto[:rows]} celdas | #{laberinto[:aristas].length} tramos " \
        "(margen #{margen_mm.round}mm, panel #{params[:ancho_mm].round}x#{params[:alto_mm].round}mm)"
      medio_ancho = (params[:canal_ancho_mm] / 2.0).mm
      # El canal se hunde canal_profundidad_mm desde la cara superior, y se
      # extiende 2mm por encima de esa cara -para atravesarla limpio, sin
      # dejar caras coplanares que puedan confundir la resta-.
      canal_z_min = (params[:grosor_mm] - params[:canal_profundidad_mm]).mm
      canal_z_max = (params[:grosor_mm] + 2.0).mm

      cajas_canal = laberinto[:aristas].map do |(r1, c1), (r2, c2)|
        xa, ya = centros[r1][c1]
        xb, yb = centros[r2][c2]
        min_x = [xa, xb].min.mm - medio_ancho
        max_x = [xa, xb].max.mm + medio_ancho
        min_y = [ya, yb].min.mm - medio_ancho
        max_y = [ya, yb].max.mm + medio_ancho
        add_box(entities, min_x, min_y, canal_z_min, max_x, max_y, canal_z_max)
      end

      canal_final = cajas_canal.shift
      cajas_canal.each { |caja| canal_final = canal_final.union(caja) }
      canal_final.name = 'Canal'

      # OJO: en esta instalación de SketchUp, `A.subtract(B)` da "B menos A"
      # -al revés de la documentación oficial-, comprobado numéricamente con
      # el script de prueba panel_laberinto_cuentas.rb. Por eso aquí
      # llamamos canal.subtract(panel) para obtener "panel menos canal".
      panel_con_canal = canal_final.subtract(panel_group)
      raise 'La resta booleana devolvió vacío -el canal quedó fuera del panel.' unless panel_con_canal

      ancho_resultado = panel_con_canal.bounds.width.to_mm
      alto_resultado = panel_con_canal.bounds.height.to_mm
      if ancho_resultado < params[:ancho_mm] * 0.9 || alto_resultado < params[:alto_mm] * 0.9
        raise "La resta booleana dio un resultado más chico de lo esperado " \
          "(#{ancho_resultado.round(1)}x#{alto_resultado.round(1)}mm en vez de " \
          "#{params[:ancho_mm]}x#{params[:alto_mm]}mm) -sigue invertido el orden de subtract."
      end
      panel_con_canal.name = 'Panel Laberinto de Cuentas'

      hex_panel = params[:colors].sample
      material_panel_name = "PlayIdea Panel Laberinto - ##{hex_panel}"
      material_panel = model.materials[material_panel_name] || model.materials.add(material_panel_name)
      material_panel.color = hex_to_color(hex_panel)
      panel_con_canal.entities.grep(Sketchup::Face).each do |cara|
        cara.material = material_panel
        cara.back_material = material_panel
      end

      cuentas_group = entities.add_group
      cuentas_group.name = 'Cuentas'
      cue = cuentas_group.entities
      cuenta_centro_z = (params[:grosor_mm] - params[:canal_profundidad_mm] + (params[:cuenta_diametro_mm] / 2.0)).mm

      # Una cuenta por celda del laberinto -todas quedan visitadas por el
      # DFS, así que las cuentas terminan repartidas por todo el panel,
      # sobre cada cruce/vuelta/callejón del laberinto ramificado-.
      celdas = centros.flatten(1)
      definition_cache = {}
      colores_cuentas = colores_al_azar(celdas.length, params[:colors])
      celdas.each_with_index do |(x, y), i|
        hex = colores_cuentas[i]
        definition = definition_cache[hex] ||= begin
          d = model.definitions.add(unique_name(model, "CUENTA-#{hex}"))
          add_sphere_geometry(d.entities, params[:cuenta_diametro_mm])
          apply_material(model, d, "PlayIdea Cuenta - ##{hex}", hex)
          d
        end
        centro = Geom::Point3d.new(x.mm, y.mm, cuenta_centro_z)
        cue.add_instance(definition, Geom::Transformation.translation(centro))
      end

      container.transformation = Geom::Transformation.translation(origin)
      container.set_attribute(DICTIONARY, 'type', 'panel_laberinto')
      container.set_attribute(DICTIONARY, 'ancho_mm', params[:ancho_mm])
      container.set_attribute(DICTIONARY, 'alto_mm', params[:alto_mm])
      container.set_attribute(DICTIONARY, 'num_cuentas', params[:num_cuentas])
      container.set_attribute('minorusal_auditor', 'code', params[:code])

      model.selection.clear
      model.selection.add(container)
      model.commit_operation
      container
    rescue StandardError
      model.abort_operation
      raise
    end

    class PlacementTool
      def initialize(params)
        @params = params
        @input = Sketchup::InputPoint.new
      end

      def activate
        Sketchup.set_status_text(
          'Haz clic para colocar la esquina inferior-izquierda del panel.',
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
        PanelLaberinto.create_panel(@params, @input.position)
        Sketchup.active_model.select_tool(nil)
      rescue StandardError => error
        UI.messagebox(
          "No fue posible crear el panel:\n#{error.message}\n\n" \
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

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions').add_submenu('Play Idea - Panel Laberinto')
      menu.add_item('Crear panel laberinto de cuentas (aleatorio)') { start }
      file_loaded(__FILE__)
    end
  end
end
