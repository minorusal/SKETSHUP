require 'sketchup.rb'
require 'net/http'
require 'json'

module PlayIdea
  module Cotizador
    # Servidor local de play-idea-explorer -catálogo de materiales/recetas
    # y cotizador de precios-, ver POST /api/cotizaciones/calcular y GET
    # /api/productos/por-codigo/:codigo en ese proyecto.
    API_BASE = 'http://localhost:3210'.freeze
    # Mismo nombre de diccionario de atributos que usa
    # constructor_modulos_playidea -'playidea_modulo'-, para poder leer
    # el color guardado en cada cincho sin depender de que ese plugin
    # esté cargado.
    DICTIONARY = 'playidea_modulo'.freeze

    # Mismo catálogo de 8 colores estándar que constructor_modulos_
    # playidea/colorear_tubos_playidea/alberca_pelotas_playidea, solo
    # para traducir el hex guardado en cada cincho a un nombre legible.
    COLOR_LABELS = {
      'FF0000' => 'Rojo', '84E311' => 'Verde lima', 'FFA400' => 'Naranja',
      '039CD4' => 'Azul', 'FFFF1E' => 'Amarillo', '11D9B4' => 'Turquesa',
      'D911CB' => 'Magenta', '6E247D' => 'Morado'
    }.freeze

    # Código de producto_terminado para cada color REAL de la paleta -ver
    # COLOR_LABELS/STANDARD_COLOR_PALETTE-, no necesariamente el mismo
    # texto ni el mismo color físico que el material de compra -ej.
    # "Verde lima" en la estructura es el cincho "Verde" en la factura; el
    # protector TURQUESA se amarra con cincho VERDE, y el MAGENTA con
    # cincho ROSA -confirmado con el usuario: esos colores de cincho no
    # se compran/fabrican, se usa un sustituto real-. Un color de
    # COLOR_LABELS sin código aquí -o sin ese producto todavía en el
    # catálogo- simplemente sale marcado como "incompleto" en el reporte,
    # no rompe nada.
    CINCHO_CODIGOS = {
      'Rojo' => 'CINCHO-ROJO', 'Verde lima' => 'CINCHO-VERDE', 'Naranja' => 'CINCHO-NARANJA',
      'Azul' => 'CINCHO-AZUL', 'Amarillo' => 'CINCHO-AMARILLO', 'Turquesa' => 'CINCHO-VERDE',
      'Magenta' => 'CINCHO-ROSA', 'Morado' => 'CINCHO-MORADO'
    }.freeze

    # Título a mostrar en build_cotizacion_html cuando una tabla agrupa
    # renglones de códigos DISTINTOS -ver `familia` en el payload de
    # POST /api/cotizaciones/calcular-. Solo hace falta una entrada aquí
    # por cada familia que de verdad mezcle códigos; el resto usa el
    # nombre del renglón tal cual, no necesita traducción.
    FAMILIA_TITULOS = {
      'PLATAFORMA' => 'Plataformas',
      'CONECTOR' => 'Conectores',
      'TOBOGAN' => 'Tobogán -ductos de fibra de vidrio-'
    }.freeze

    # Largo de barra cruda de la que se cortan los tubos estructurales
    # -6m, medida comercial estándar-. Todas las variantes de tubo
    # -X/Y/Z/DIAG/PATA- comparten el mismo diámetro/cédula, así que se
    # cortan de la MISMA barra cruda: el estimado es UNO solo, sumando
    # el largo total de TODOS los ejes.
    STRUCTURAL_STOCK_LENGTH_MM = 6000.0

    def self.strip_dedup_suffix(name)
      name.to_s.sub(/\s*\(\d+\)\s*\z/, '')
    end

    def self.piece_name(entity)
      raw = entity.name.to_s
      raw = entity.definition.name.to_s if raw.empty? && entity.is_a?(Sketchup::ComponentInstance)
      strip_dedup_suffix(raw)
    end

    # Mismo patrón para cinchos y recubrimiento: ambos guardan su color
    # -hex- en la definición vía el diccionario DICTIONARY.
    def self.color_label(entity)
      hex = entity.is_a?(Sketchup::ComponentInstance) ? entity.definition.get_attribute(DICTIONARY, 'color') : nil
      COLOR_LABELS[hex.to_s] || (hex ? "##{hex}" : '(color desconocido)')
    end

    # Cliente HTTP mínimo hacia play-idea-explorer -corriendo en la misma
    # Mac-. Nunca deja tronar el reporte si el servidor no está prendido
    # o tarda de más: regresa {'error' => mensaje legible} en vez de subir
    # la excepción, para que build_report_html lo muestre en vez de que
    # falle todo el diálogo.
    def self.api_post(path, body)
      uri = URI("#{API_BASE}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 3
      http.read_timeout = 5
      req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
      req.body = JSON.generate(body)
      res = http.request(req)
      JSON.parse(res.body)
    rescue StandardError => e
      { 'error' => "No se pudo conectar con el catálogo de precios en #{API_BASE} (#{e.message}). " \
                   '¿Está corriendo el servidor de play-idea-explorer?' }
    end

    def self.h(text)
      text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
    end

    # Monto con separador de miles -"1,234.56"-, para identificar rápido
    # cientos/miles en cantidades grandes. `nil` -receta incompleta- se
    # muestra como guion, no como "0.00" -no inventa un valor-.
    def self.money(value, decimals: 2)
      return '—' if value.nil?
      entero, decimal = format("%.#{decimals}f", value).split('.')
      negativo = entero.start_with?('-')
      entero = entero.delete_prefix('-').reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      "#{negativo ? '-' : ''}#{entero}.#{decimal}"
    end

    def self.blank_counts
      {
        conectores_por_tipo: Hash.new(0),      # tipo -"61","21",...- => cantidad
        cinchos_por_color: Hash.new(0),        # nombre de color => cantidad
        tubo_largo_por_mm: Hash.new(0),        # largo en mm -redondeado- => cantidad de tramos
        recubrimiento_por_color: Hash.new(0),  # nombre de color => cantidad de tramos
        soleras: 0,
        plataformas_por_codigo: Hash.new(0),   # codigo del producto (API) => cantidad
        red_por_medida: Hash.new(0),           # [ancho_cm, alto_cm] => cantidad de paños -area y perimetro salen distintos aunque coincida el area, no se puede agrupar solo por area-
        red_cinchos_blancos: 0,                # total de cinchos blancos -cada 15cm de perimetro de malla-
        tobogan_por_codigo: Hash.new(0),       # codigo del producto (API) => cantidad -codo/recto/salida/aro de fibra de vidrio-
        tornilleria: 0                         # juegos de tornillo+rondana+tuerca hex+tuerca bellota, uniones del tobogan
      }
    end

    # Recorre TODO lo seleccionado, a cualquier profundidad, y solo
    # tabula lo que se pidió por ahora: conectores (total), cinchos por
    # color, largo total de tubo -para el estimado de barras de 6m- y
    # tramos de recubrimiento de espuma -cada uno ya es una barra de
    # 2.4m o menos, contar tramos = contar barras a comprar-. Todo lo
    # demás -soleras, tornillería, tuercas/opresores, sub-partes internas
    # de los conectores- se ignora a propósito, pero se sigue recorriendo
    # hacia adentro para no saltarse nada que sí importe.
    def self.recorrer(entities, counts)
      entities.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        nombre = piece_name(e)
        case nombre
        when /\ATUB-MOD-[A-Z]+-([\d.]+)\z/
          counts[:tubo_largo_por_mm][Regexp.last_match(1).to_f.round] += 1
        when /\ACON-(?:MOD-)?(\d+)\z/
          counts[:conectores_por_tipo][Regexp.last_match(1)] += 1
        when /\ACINCHO-/
          counts[:cinchos_por_color][color_label(e)] += 1
        when /\AREC-/
          counts[:recubrimiento_por_color][color_label(e)] += 1
        when /\ASOLERA-1IN\z/
          counts[:soleras] += 1
        when /\APLATAFORMA-(\d+)X(\d+)\z/
          # Normaliza 122X61/61X122 -misma pieza rotada- al mismo código,
          # ver platform_code_for en constructor_modulos_playidea.
          ancho, largo = [Regexp.last_match(1).to_i, Regexp.last_match(2).to_i].sort
          counts[:plataformas_por_codigo]["PLATAFORMA-#{ancho}X#{largo}"] += 1
        when /\APLATAFORMA-TRIANGULO-(\d+)\z/
          counts[:plataformas_por_codigo]["PLATAFORMA-TRIANGULO-#{Regexp.last_match(1)}"] += 1
        when /\ARED-(\d+)X(\d+)\z/
          # Nombre en cm -ver net_code_for en constructor_modulos_
          # playidea-. Se agrupa por medida exacta -no solo por área-
          # porque dos paños de área igual pueden tener perímetro
          # distinto -ej. 1x2.85 vs 1.5x1.9, ambos 2.85 m2- y el marco de
          # redondo pulido depende del perímetro, no del área.
          ancho_cm = Regexp.last_match(1).to_f
          alto_cm = Regexp.last_match(2).to_f
          counts[:red_por_medida][[ancho_cm, alto_cm]] += 1
          # El redondo pulido del marco se amarra a la estructura con
          # cinchos blancos cada 15cm de PERÍMETRO, mismo espaciado que
          # CABLE_TIE_SPACING_MM en constructor_modulos_playidea.
          perimetro_mm = 2 * ((ancho_cm * 10) + (alto_cm * 10))
          counts[:red_cinchos_blancos] += (perimetro_mm / 150.0).ceil
        when /\ATOBOGAN-CODO-90\z/
          counts[:tobogan_por_codigo]['TOBOGAN-CODO-90'] += 1
        when /\ATOBOGAN-RECTO-/
          # El nombre trae el largo -TOBOGAN-RECTO-110, etc.-, pero por
          # ahora solo hay un precio pactado por pieza -sin variar por
          # largo-, así que se agrupan todos bajo el mismo código.
          counts[:tobogan_por_codigo]['TOBOGAN-RECTO'] += 1
        when /\ATOBOGAN-SALIDA\z/
          counts[:tobogan_por_codigo]['TOBOGAN-SALIDA'] += 1
        when /\ATOBOGAN-ARO-ENTRADA\z/
          counts[:tobogan_por_codigo]['TOBOGAN-ARO-ENTRADA'] += 1
        when /\ATORNILLERIA-5-16-1\.5\z/
          counts[:tornilleria] += 1
        end
        hijos = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
        recorrer(hijos, counts)
      end
    end

    # Sección "Cotización" del reporte. TODA la aritmética -incluida la de
    # cada renglón del desglose- ya viene calculada desde POST /api/
    # cotizaciones/calcular; aquí solo se pinta. Dos formatos según cuántos
    # insumos tiene la receta de cada pieza -no hardcoded por tipo de
    # pieza, para que cualquier producto nuevo caiga solo en el formato
    # que le toca-:
    #   - 1 solo insumo -ej. un cincho, que ES el material tal cual, sin
    #     nada que lo arme- -> UNA fila en una tabla compartida, sin
    #     desglose que mostrar -no hay "de qué se compone", es la pieza
    #     misma-.
    #   - 2+ insumos -ej. una solera, que se arma de barra+disco+mano de
    #     obra+tornillos- -> tarjeta propia con desglose plegable, como ya
    #     estaba.
    # Un código no encontrado o con receta incompleta sale en su propia
    # tarjeta de aviso, nunca tumba el resto del reporte.
    def self.build_cotizacion_html(cotizacion)
      return '' if cotizacion.nil?
      return "<div class=\"error-card\">#{h(cotizacion['error'])}</div>" if cotizacion['error']

      items = cotizacion['items'] || []
      errores = items.select { |item| item['error'] }
      validos = items.reject { |item| item['error'] }
      # `es_simple` ya viene calculado por la API -no se decide aquí por
      # cuántos componentes trae-, ver POST /api/cotizaciones/calcular.
      # Un simple -1 solo insumo, ej. un cincho- normalmente cae en la
      # tabla COMPARTIDA de abajo, sin encabezado propio -mezclado con
      # cualquier otro simple del reporte-. Pero si el plugin le puso una
      # `familia` EXPLÍCITA -distinta de su propio código- es porque
      # quiere agruparlo con otros códigos bajo SU PROPIO título -ej. los
      # 4 códigos del tobogán, bajo "Tobogán"-, igual que ya hacían los
      # complejos -conectores, plataformas-. Sin esto, esos renglones
      # quedaban indistinguibles entre docenas de cinchos/protectores en
      # la tabla genérica -bug real reportado por el usuario: "no veo los
      # ductos de fibra", estaban ahí pero sin ningún título que los
      # distinguiera del resto-.
      simples = validos.select { |item| item['es_simple'] && (item['familia'].nil? || item['familia'] == item['codigo']) }
      simples_agrupados = validos.select { |item| item['es_simple'] && item['familia'] && item['familia'] != item['codigo'] }
      complejos = validos.reject { |item| item['es_simple'] }
      grupos_por_familia = (cotizacion['grupos'] && cotizacion['grupos']['por_familia']) || {}

      # TODO lo que tenga tabla propia -complejos de siempre, MÁS los
      # simples agrupados de arriba-. `familia` -mandado en el payload,
      # ver start/PLATFORM_FAMILIA- junta renglones de códigos DISTINTOS
      # en una sola tabla -ej. las 4 medidas de plataforma, o los 4
      # códigos del tobogán-; si no se manda, cada código es su propia
      # familia -ej. tubo estructural, ya agrupado por código porque los
      # distintos largos comparten el mismo código-.
      complejos_por_familia = (complejos + simples_agrupados).group_by { |item| item['familia'] || item['codigo'] }

      errores_html = errores.map { |item| "<div class=\"error-card\">#{h(item['codigo'])}: #{h(item['error'])}</div>" }.join

      simples_rows = simples.map do |item|
        etiqueta = item['area_m2'] ? "#{h(item['nombre'])} (#{item['area_m2']} m²)" : h(item['nombre'])
        <<~ROW
          <tr>
            <td>#{etiqueta}</td>
            <td class='num'>#{item['cantidad']}</td>
            <td class='num'>$#{money(item['costo_unitario'])}</td>
            <td class='num'>$#{money(item['precio_venta_unitario'])}</td>
            <td class='num'>$#{money(item['subtotal_costo'])}</td>
            <td class='num'>$#{money(item['subtotal_venta'])}</td>
          </tr>
        ROW
      end.join
      # Fila de totales al pie de las columnas de Cant./Inversión/Venta.
      # Sumado AQUÍ, sobre `simples` ya filtrado -no con "grupos.simples"
      # de la API, que suma TODOS los simples originales sin saber que
      # algunos -los agrupados, ej. el tobogán- se movieron a su propia
      # tabla del lado de acá; usar ese total ciego habría dejado un pie
      # de tabla que no cuadra con las filas que sí se ven arriba-.
      simples_totales_row = if simples.any?
                              total_cantidad = simples.sum { |item| item['cantidad'].to_i }
                              total_costo = simples.sum { |item| item['subtotal_costo'].to_f }
                              total_venta = simples.sum { |item| item['subtotal_venta'].to_f }
                              <<~TOTALES_ROW
                                <tr class="fila-total">
                                  <td>Total</td>
                                  <td class='num'>#{total_cantidad}</td>
                                  <td></td>
                                  <td></td>
                                  <td class='num'>$#{money(total_costo)}</td>
                                  <td class='num'>$#{money(total_venta)}</td>
                                </tr>
                              TOTALES_ROW
                            else
                              ''
                            end
      simples_html = simples.empty? ? '' : <<~SIMPLES_HTML
        <table>
          <thead><tr><th>Pieza</th><th class='num'>Cant.</th><th class='num'>Costo c/u</th><th class='num'>Venta c/u</th><th class='num'>Inversión</th><th class='num'>Venta</th></tr></thead>
          <tbody>#{simples_rows}#{simples_totales_row}</tbody>
        </table>
      SIMPLES_HTML

      # UNA tabla por familia -ver arriba-, con un renglón por variante y
      # el desglose de esa variante plegable dentro de la misma tabla.
      complejos_html = complejos_por_familia.map do |familia, grupo|
        nombre_grupo = grupo.map { |item| item['codigo'] }.uniq.size > 1 ? FAMILIA_TITULOS.fetch(familia, familia) : grupo.first['nombre']
        columna_variante = if grupo.any? { |item| item['largo_mm'] }
                             'Largo'
                           elsif grupo.any? { |item| item['color'] }
                             'Color'
                           elsif grupo.any? { |item| item['area_m2'] }
                             'Área'
                           else
                             'Detalle'
                           end
        filas = grupo.each_with_index.map do |item, idx|
          desglose_rows = (item['componentes'] || []).map do |c|
            unitario_txt = c['costo_unitario'].nil? ? '—' : "$#{money(c['costo_unitario'])}"
            total_txt = c['costo_total'].nil? ? '—' : "$#{money(c['costo_total'])}"
            "<tr><td>#{h(c['descripcion'])}</td><td class='num'>#{unitario_txt}</td><td class='num'>#{total_txt}</td></tr>"
          end.join
          etiqueta_variante = if item['largo_mm']
                                "#{format('%.2f', item['largo_mm'] / 1000.0)} m"
                              elsif item['color']
                                item['color']
                              elsif item['area_m2']
                                "#{item['area_m2']} m²"
                              else
                                item['nombre'] || ''
                              end
          toggle_id = "desglose-#{h(familia).gsub(/[^a-zA-Z0-9]/, '')}-#{idx}"
          # Un simple agrupado -ej. un ducto del tobogán, 1 solo insumo,
          # el precio pactado tal cual- no tiene nada que desglosar: sin
          # el toggle/fila de desglose, solo el renglón con su costo.
          toggle_html = item['es_simple'] ? '' : "<div class=\"toggle\" onclick=\"document.getElementById('#{toggle_id}').classList.toggle('open')\">▸ ver desglose</div>"
          desglose_row_html = item['es_simple'] ? '' : <<~DESGLOSE
            <tr id="#{toggle_id}" class="desglose-row">
              <td colspan="6">
                <table><thead><tr><th>Componente</th><th class='num'>Costo x pieza</th><th class='num'>Total x #{item['cantidad']}</th></tr></thead><tbody>#{desglose_rows}</tbody></table>
              </td>
            </tr>
          DESGLOSE
          <<~FILA
            <tr>
              <td>#{h(etiqueta_variante)}
                #{toggle_html}
              </td>
              <td class='num'>#{item['cantidad']}</td>
              <td class='num'>$#{money(item['costo_unitario'])}</td>
              <td class='num'>$#{money(item['precio_venta_unitario'])}</td>
              <td class='num'>$#{money(item['subtotal_costo'])}</td>
              <td class='num'>$#{money(item['subtotal_venta'])}</td>
            </tr>
            #{desglose_row_html}
          FILA
        end.join
        grupo_total = grupos_por_familia[familia]
        fila_total = grupo_total ? <<~TOTALES_ROW : ''
          <tr class="fila-total">
            <td>Total</td>
            <td class='num'>#{grupo_total['total_cantidad']}</td>
            <td></td>
            <td></td>
            <td class='num'>$#{money(grupo_total['total_costo'])}</td>
            <td class='num'>$#{money(grupo_total['total_venta'])}</td>
          </tr>
        TOTALES_ROW
        <<~GRUPO_HTML
          <h3 style="font-size:13px;margin:12px 0 4px;color:#173b68">#{h(nombre_grupo)}</h3>
          <table>
            <thead><tr><th>#{columna_variante}</th><th class='num'>Cant.</th><th class='num'>Costo c/u</th><th class='num'>Venta c/u</th><th class='num'>Inversión</th><th class='num'>Venta</th></tr></thead>
            <tbody>#{filas}#{fila_total}</tbody>
          </table>
        GRUPO_HTML
      end.join

      "<h2>Cotización</h2>#{errores_html}#{simples_html}#{complejos_html}"
    end

    # `cotizacion` = respuesta de POST /api/cotizaciones/calcular -ya con
    # todo calculado, incluido el desglose por componente- o {'error'=>...}
    # si no se pudo conectar.
    def self.build_report_html(counts, cotizacion = nil)
      tubo_largo_total_mm = counts[:tubo_largo_por_mm].sum { |largo_mm, cantidad| largo_mm * cantidad }
      barras_6m = (tubo_largo_total_mm / STRUCTURAL_STOCK_LENGTH_MM).ceil
      cotizacion_html = build_cotizacion_html(cotizacion)
      # Suma de TODO el dinero -no solo la sección "Cotización" de
      # arriba-, hasta el fondo del reporte. `cotizacion['total_costo']`/
      # `total_venta` ya vienen sumados por la API sobre TODOS los
      # renglones cotizados -soleras, plataformas, tubo, protectores,
      # cinchos-, no se suma nada aquí.
      total_general_html = if cotizacion && !cotizacion['error']
                             "<div class=\"card\">Total cotizado: inversión <b>$#{money(cotizacion['total_costo'])}</b>, venta <b>$#{money(cotizacion['total_venta'])}</b> -margen #{cotizacion['margen_porcentaje']}%-</div>"
                           else
                             ''
                           end

      <<~HTML
        <!doctype html><html><head><meta charset="utf-8">
        <style>
          body{font-family:-apple-system,Segoe UI,Arial,sans-serif;margin:0;padding:18px;color:#1c2733;background:#f4f6f9}
          h1{font-size:19px;margin:0 0 14px}
          h2{font-size:14px;margin:20px 0 6px;color:#173b68}
          table{width:100%;border-collapse:collapse;background:white;border-radius:8px;overflow:hidden;box-shadow:0 1px 4px #0001}
          th,td{padding:8px 12px;text-align:left;border-bottom:1px solid #eef1f4;font-size:14px}
          th{background:#173b68;color:white;font-weight:600}
          td.num,th.num{text-align:right}
          tr:last-child td{border-bottom:0}
          .big{font-size:28px;font-weight:700;color:#173b68}
          .card{background:white;border-radius:8px;box-shadow:0 1px 4px #0001;padding:14px 16px;margin-bottom:6px}
          .estimado{font-size:11px;color:#8a7000;background:#fff8e1;border-radius:6px;padding:8px 10px;margin-top:8px}
          .error-card{background:#fdeceb;color:#a33;border-radius:8px;padding:12px 14px;margin-bottom:6px;font-size:13px}
          .toggle{margin:10px 0 4px;cursor:pointer;color:#2367bd;font-size:13px;user-select:none}
          .desglose{display:none;margin-top:6px}
          .desglose.open{display:block}
          .desglose-row{display:none}
          .desglose-row.open{display:table-row}
          .desglose-row td{padding:0 12px 10px;border-bottom:1px solid #eef1f4}
          .venta-inversion{display:flex;gap:20px;margin-top:8px;font-size:14px}
          .fila-total td{font-weight:700;border-top:2px solid #173b68;background:#f4f6f9}
        </style></head>
        <body>
          <h1>Cantidades de la selección</h1>

          #{cotizacion_html}

          <div class="card">Barras crudas de tubo de 6m: <span class="big">#{barras_6m}</span>
            <div class="estimado">Largo total de tubo cortado: #{(tubo_largo_total_mm / 1000.0).round(2)} m ÷ 6m, redondeado hacia arriba -estimado simple, NO es un plan de corte optimizado-.</div>
          </div>

          #{total_general_html}
        </body></html>
      HTML
    end

    def self.start
      model = Sketchup.active_model
      selection = model.selection
      if selection.empty?
        UI.messagebox('Selecciona primero la estructura -o las piezas- que quieres contar.')
        return
      end

      counts = blank_counts
      recorrer(selection, counts)

      # Por ahora solo se cotizan placas de solera, cinchos y tubo
      # estructural -conectores y protectores de esponja todavía no
      # tienen receta cargada en el catálogo-. UNA sola llamada -ya trae
      # costo, venta y el desglose por componente, con toda la
      # aritmética hecha del lado del servidor-. Se acumula por CÓDIGO
      # -no por color de estructura- porque dos colores distintos pueden
      # compartir el mismo cincho real -ver CINCHO_CODIGOS-, y no se
      # quiere mandar el mismo código dos veces con cantidades separadas.
      cantidad_por_codigo = Hash.new(0)
      cantidad_por_codigo['SOLERA-20CM'] += counts[:soleras] if counts[:soleras].positive?
      counts[:cinchos_por_color].each do |color, cantidad|
        codigo = CINCHO_CODIGOS[color]
        cantidad_por_codigo[codigo] += cantidad if codigo
      end
      # Blanco no lo usa ningún color de protector -ver CINCHO_CODIGOS-,
      # así que sumar aquí no se mezcla con los cinchos de recubrimiento.
      cantidad_por_codigo['CINCHO-BLANCO'] += counts[:red_cinchos_blancos] if counts[:red_cinchos_blancos].positive?
      items = cantidad_por_codigo.map { |codigo, cantidad| { codigo: codigo, cantidad: cantidad } }
      # `familia: 'PLATAFORMA'`/`'CONECTOR'` -ver FAMILIA_TITULOS/build_
      # cotizacion_html- junta varios códigos DISTINTOS -las 4 medidas de
      # plataforma, o los 6 tipos de conector- en UNA sola tabla del
      # reporte, aunque cada uno tenga su propio costo real. El tipo
      # -"61","21",...- ya coincide directo con el código de la API
      # -"CON-61","CON-21",...-, sin tabla de traducción.
      items += counts[:plataformas_por_codigo].map do |codigo, cantidad|
        { codigo: codigo, cantidad: cantidad, familia: 'PLATAFORMA' }
      end
      items += counts[:conectores_por_tipo].map do |tipo, cantidad|
        { codigo: "CON-#{tipo}", cantidad: cantidad, familia: 'CONECTOR' }
      end
      # El protector de esponja siempre se fabrica de 2.4m -confirmado
      # con el usuario-, el color del forro no cambia la receta/precio,
      # pero SÍ se manda UN renglón por color -mismo código repetido,
      # como el tubo con distinto largo- para que salgan desglosados por
      # color en la misma tabla en vez de un solo total ciego.
      items += counts[:recubrimiento_por_color].map do |color, cantidad|
        { codigo: 'PROTECTOR-240CM', cantidad: cantidad, color: color }
      end
      # El tubo estructural sí varía de largo por tramo -a diferencia de
      # la solera, que siempre corta 20cm-, así que no se puede agrupar
      # solo por código: cada largo distinto es su propio renglón, con
      # `cantidad_consumida_override` -en mm- para que la API escale la
      # materia prima proporcional pero deje fijo el costo de corte -ver
      # POST /api/cotizaciones/calcular y receta de TUBO-ESTRUCTURAL-6M-.
      items += counts[:tubo_largo_por_mm].map do |largo_mm, cantidad|
        { codigo: 'TUBO-ESTRUCTURAL-6M', cantidad: cantidad, cantidad_consumida_override: largo_mm }
      end
      # La malla se cotiza por la medida real de cada paño -no hay tamaño
      # fijo como la plataforma, se corta a la medida de cada cuadro/
      # techo-. Dos medidas variables A LA VEZ -tela por área, marco de
      # redondo pulido por perímetro-, por eso `overrides` en vez del
      # `cantidad_consumida_override` de un solo valor -ver override_key
      # en la receta RED-NYLON y POST /api/cotizaciones/calcular-.
      items += counts[:red_por_medida].map do |(ancho_cm, alto_cm), cantidad|
        area_m2 = ((ancho_cm / 100.0) * (alto_cm / 100.0)).round(2)
        perimetro_mm = 2 * ((ancho_cm * 10) + (alto_cm * 10))
        {
          codigo: 'RED-NYLON', cantidad: cantidad, familia: 'RED-NYLON', area_m2: area_m2,
          overrides: { area_m2: area_m2, perimetro_mm: perimetro_mm }
        }
      end
      # Ductos del tobogán -codo/recto/salida/aro, fibra de vidrio-:
      # precio pactado con cliente por ahora -Pedido #13-, sin desglose
      # de material todavía, ver la tarifa "(precio pactado)" de cada uno
      # en el catálogo. Igual que plataformas/conectores, varios códigos
      # DISTINTOS agrupados en una sola tabla del reporte -familia
      # 'TOBOGAN'-.
      items += counts[:tobogan_por_codigo].map do |codigo, cantidad|
        { codigo: codigo, cantidad: cantidad, familia: 'TOBOGAN' }
      end
      # Juego de tornillería -tornillo+rondana+tuerca hex+tuerca bellota-
      # de cada unión de pestaña/solera del tobogán. Un solo código -no
      # varía por tamaño de ducto todavía-, así que sale en su propia
      # tarjeta simple, no en la tabla del tobogán -no comparte familia
      # con los ductos, es tornillería, no fibra de vidrio-.
      items << { codigo: 'TORNILLERIA-5-16-1.5', cantidad: counts[:tornilleria] } if counts[:tornilleria].positive?

      cotizacion = items.any? ? api_post('/api/cotizaciones/calcular', { items: items }) : nil
      # La API no regresa `cantidad_consumida_override` en la raíz del
      # item -solo aparece dentro de la descripción de su componente de
      # materia prima-, pero el orden de `cotizacion['items']` respeta el
      # orden de la petición -ver calcularCotizacion en db.js-, así que
      # se puede volver a asociar aquí para que build_cotizacion_html
      # distinga tarjetas de tubo con distinto largo.
      if cotizacion && cotizacion['items']
        cotizacion['items'].each_with_index do |item, idx|
          origen = items[idx]
          next unless origen
          item['largo_mm'] = origen[:cantidad_consumida_override] if origen[:cantidad_consumida_override] && origen[:codigo] == 'TUBO-ESTRUCTURAL-6M'
          item['color'] = origen[:color] if origen[:color]
          item['area_m2'] = origen[:area_m2] if origen[:area_m2]
        end
      end

      dialog = UI::HtmlDialog.new(
        dialog_title: 'Play Idea - Cantidades de la selección',
        preferences_key: 'PlayIdeaCotizadorReporte',
        scrollable: true, resizable: true, width: 460, height: 560
      )
      dialog.set_html(build_report_html(counts, cotizacion))
      dialog.show
    end

    unless file_loaded?(__FILE__)
      UI.menu('Extensions').add_item('Play Idea > Cotizador: contar cantidades de la selección') { PlayIdea::Cotizador.start }
      file_loaded(__FILE__)
    end
  end
end
