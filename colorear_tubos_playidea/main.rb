require 'sketchup.rb'
require 'json'
require 'digest'
require 'fileutils'

module PlayIdea
  module ColorearTubos
    extend self

    # Mismos valores de detección verificados en scripts/colorear_tubos_esponja.rb
    # -ver ese archivo para la explicación completa de la fórmula de ajuste de
    # cilindro-. El diámetro de referencia (85mm) es el del recubrimiento de
    # polyfoam de constructor_modulos_playidea.
    DIAMETER_REFERENCE_MM = 85.0
    DIAMETER_TOLERANCE_MM = 10.0
    MIN_ASPECT_RATIO = 2.0
    RESIDUAL_RELATIVE_TOLERANCE = 0.02

    # Tolerancia (mm) para considerar que dos extremos de tubo son "el mismo
    # nodo" -ver cluster_endpoints-.
    JOINT_BUCKET_MM = 20.0

    # Catálogo FIJO de colores -el usuario solo puede escoger entre estos 8,
    # no capturar un color libre-. El diálogo muestra cada uno como casilla
    # con su muestra de color; el usuario marca cuáles usar (mínimo 1, máximo
    # 8, que es el total del catálogo).
    PALETTE = [
      { hex: 'FF0000', label: 'Rojo' },
      { hex: '84E311', label: 'Verde lima' },
      { hex: 'FFA400', label: 'Naranja' },
      { hex: '039CD4', label: 'Azul' },
      { hex: 'FFFF1E', label: 'Amarillo' },
      { hex: '11D9B4', label: 'Turquesa' },
      { hex: 'D911CB', label: 'Magenta' },
      { hex: '6E247D', label: 'Morado' }
    ].freeze

    # Misma carpeta que usan los demás scripts/plugins de este proyecto para
    # dejar sus reportes.
    OUTPUT_DIR = '/Users/minorusal/Documents/SKETCHUP/inspect_output'.freeze

    def start
      unless defined?(UI::HtmlDialog)
        UI.messagebox('Esta herramienta necesita una versión de SketchUp compatible con HtmlDialog.')
        return
      end

      @dialog&.close
      @dialog = UI::HtmlDialog.new(
        dialog_title: 'Colorear Tubos de Esponja Play Idea',
        preferences_key: 'PlayIdeaColorearTubos',
        scrollable: true,
        resizable: true,
        width: 420,
        height: 600,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_file(File.join(__dir__, 'selector.html'))
      @dialog.add_action_callback('ready') do |_action_context|
        @dialog.execute_script("loadPalette(#{JSON.generate(PALETTE)})")
      end
      @dialog.add_action_callback('colorTubes') do |_action_context, data|
        handle_color_request(data)
      end
      @dialog.show
    rescue StandardError => error
      UI.messagebox("No fue posible abrir el diálogo:\n#{error.message}")
      puts error.full_message
    end

    def handle_color_request(data)
      allowed_hexes = PALETTE.map { |c| c[:hex] }
      hexes = Array(data['colors']).map(&:to_s).select { |h| allowed_hexes.include?(h) }.uniq.first(8)
      if hexes.empty?
        @dialog.execute_script("showError(#{JSON.generate('Elige al menos un color de la lista.')})")
        return
      end

      result = color_tubes(hexes)
      if result.nil?
        @dialog.execute_script(
          "showError(#{JSON.generate("No se encontró ningún tubo de esponja (~#{DIAMETER_REFERENCE_MM.to_i}mm de diámetro) en el modelo.")})"
        )
        return
      end
      @dialog.close
      UI.messagebox(result[:summary])
    rescue StandardError => error
      @dialog.execute_script("showError(#{JSON.generate(error.message)})")
      puts error.full_message
    end

    def hex_to_color(hex)
      Sketchup::Color.new(hex[0..1].to_i(16), hex[2..3].to_i(16), hex[4..5].to_i(16))
    end

    def child_container(entity)
      entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
    end

    def direct_faces(entity)
      child_container(entity).grep(Sketchup::Face)
    end

    def child_entities(entity)
      container = child_container(entity)
      container.grep(Sketchup::Group) + container.grep(Sketchup::ComponentInstance)
    end

    # Ajusta L (largo) y D (diámetro) por mínimos cuadrados dado un eje
    # candidato `direction` (unitario) y la caja delimitadora `bbox`.
    def solve_cylinder_fit(bbox, direction)
      a = direction.map(&:abs)
      b = direction.map { |v| Math.sqrt([1.0 - (v * v), 0.0].max) }
      saa = a.zip(a).sum { |x, y| x * y }
      sab = a.zip(b).sum { |x, y| x * y }
      sbb = b.zip(b).sum { |x, y| x * y }
      s_a_bbox = a.zip(bbox).sum { |x, y| x * y }
      s_b_bbox = b.zip(bbox).sum { |x, y| x * y }
      det = (saa * sbb) - (sab * sab)
      return nil if det.abs < 1e-9
      length = ((s_a_bbox * sbb) - (s_b_bbox * sab)) / det
      diameter = ((saa * s_b_bbox) - (sab * s_a_bbox)) / det
      return nil if length <= 0 || diameter <= 0
      predicted = a.zip(b).map { |ai, bi| (length * ai) + (diameter * bi) }
      residual = predicted.zip(bbox).sum { |p, o| (p - o).abs }
      [length, diameter, residual]
    end

    def foam_tube_fit(entity)
      t = entity.transformation
      bounds = entity.bounds
      bbox = [bounds.width.to_mm, bounds.height.to_mm, bounds.depth.to_mm]
      candidates = [t.xaxis, t.yaxis, t.zaxis]
      fits = candidates.each_index.map do |i|
        fit = solve_cylinder_fit(bbox, candidates[i].to_a)
        fit && [i, *fit]
      end.compact
      return nil if fits.empty?
      axis_index, length, diameter, residual = fits.min_by { |_i, _l, _d, res| res }
      return nil if (residual / bbox.sum) > RESIDUAL_RELATIVE_TOLERANCE
      return nil if (diameter - DIAMETER_REFERENCE_MM).abs > DIAMETER_TOLERANCE_MM
      return nil if length < MIN_ASPECT_RATIO * diameter
      { length_mm: length, diameter_mm: diameter, direction: candidates[axis_index] }
    end

    def collect_foam_tubes(entity, ancestors_transform, found)
      faces = direct_faces(entity)
      children = child_entities(entity)
      if !faces.empty? || children.empty?
        fit = foam_tube_fit(entity)
        return unless fit
        world_center = entity.bounds.center.transform(ancestors_transform)
        world_direction = fit[:direction].transform(ancestors_transform)
        world_direction = world_direction.normalize unless world_direction.length.zero?
        half = (fit[:length_mm] / 2.0).mm
        endpoint_a = world_center.offset(world_direction.reverse, half)
        endpoint_b = world_center.offset(world_direction, half)
        found << {
          entity: entity,
          world_center: world_center,
          world_direction: world_direction,
          endpoint_a: endpoint_a,
          endpoint_b: endpoint_b,
          length_mm: fit[:length_mm],
          diameter_mm: fit[:diameter_mm]
        }
      else
        my_transform = ancestors_transform * entity.transformation
        children.each { |child| collect_foam_tubes(child, my_transform, found) }
      end
    end

    # Agrupa TODOS los extremos por cercanía real en 3D -distancia euclidiana,
    # no redondeo por eje independiente, que puede perder conexiones reales
    # cuando dos puntos caen justo en bordes de celdas distintas-.
    def cluster_endpoints(found)
      points = []
      found.each_index do |i|
        points << { tube: i, point: found[i][:endpoint_a] }
        points << { tube: i, point: found[i][:endpoint_b] }
      end
      clusters = []
      used = Array.new(points.length, false)
      points.each_index do |a|
        next if used[a]
        cluster = [points[a]]
        used[a] = true
        ((a + 1)...points.length).each do |b|
          next if used[b]
          next if points[a][:point].distance(points[b][:point]).to_mm > JOINT_BUCKET_MM
          cluster << points[b]
          used[b] = true
        end
        clusters << cluster
      end
      clusters
    end

    def build_neighbors(found)
      neighbors = Array.new(found.length) { [] }
      cluster_endpoints(found).each do |cluster|
        tube_indices = cluster.map { |p| p[:tube] }.uniq
        next if tube_indices.length < 2
        tube_indices.each do |i|
          tube_indices.each { |j| neighbors[i] << j if i != j }
        end
      end
      neighbors.map(&:uniq)
    end

    def orientation_label(direction)
      ax, ay, az = direction.x.abs, direction.y.abs, direction.z.abs
      if az > 0.9
        'vertical'
      elsif ax > 0.9
        'horizontal-X'
      elsif ay > 0.9
        'horizontal-Y'
      else
        'diagonal'
      end
    end

    # Pinta y DEVUELVE cuántas caras realmente tocó y qué entidad quedó
    # pintada. SIEMPRE vuelve única la entidad primero -un Group, igual que un
    # ComponentInstance, puede compartir su definición con otras copias; sin
    # esto, pintar un tubo pinta también a todos sus "hermanos" con la misma
    # definición-. `make_unique` puede devolver una instancia NUEVA -hay que
    # quedarse con lo que devuelve-.
    def paint(entity, hex, materials)
      entity = entity.make_unique
      material = materials[hex] ||= begin
        name = "Color ##{hex}"
        m = Sketchup.active_model.materials[name] || Sketchup.active_model.materials.add(name)
        m.color = hex_to_color(hex)
        m
      end
      faces = direct_faces(entity)
      faces.each do |face|
        face.material = material
        face.back_material = material
      end
      { entity: entity, faces_painted: faces.length }
    end

    # Recorre TODO el modelo -no hace falta seleccionar nada primero-, detecta
    # cada tubo de esponja y lo colorea con uno de `colors_hex`, elegido por
    # hash MD5 del entityID -no depende de ningún orden ni posición, ver
    # scripts/colorear_tubos_esponja.rb para el porqué-. Devuelve nil si no
    # encontró ningún tubo, o {summary:, output_path:, total:} si coloreó.
    def color_tubes(colors_hex)
      model = Sketchup.active_model
      found = []
      identity = Geom::Transformation.new
      top_level = model.entities.grep(Sketchup::Group) + model.entities.grep(Sketchup::ComponentInstance)
      top_level.each { |entity| collect_foam_tubes(entity, identity, found) }
      return nil if found.empty?

      color_indices = found.map do |item|
        id = item[:entity].entityID
        Digest::MD5.hexdigest(id.to_s).to_i(16) % colors_hex.length
      end

      neighbors = build_neighbors(found)
      max_degree = neighbors.map(&:length).max

      materials = {}
      painted = Hash.new(0)
      report_rows = []
      mismatches = []
      painted_entities = []
      model.start_operation('Colorear tubos de esponja', true)
      begin
        found.each_with_index do |item, index|
          hex = colors_hex[color_indices[index]]
          result = paint(item[:entity], hex, materials)
          painted[hex] += 1
          painted_entities << result[:entity]

          actual_face = direct_faces(result[:entity]).first
          actual_material = actual_face&.material&.name
          expected_material = "Color ##{hex}"
          verified = actual_material == expected_material
          mismatches << {
            id: result[:entity].entityID,
            expected: expected_material,
            actual: actual_material || '(sin material)',
            faces_painted: result[:faces_painted]
          } unless verified

          c = item[:world_center]
          orientation = orientation_label(item[:world_direction])
          report_rows << {
            n: index + 1,
            id: result[:entity].entityID,
            length_mm: item[:length_mm].round(1),
            diameter_mm: item[:diameter_mm].round(1),
            x: c.x.to_mm.round(1),
            y: c.y.to_mm.round(1),
            z: c.z.to_mm.round(1),
            color: hex,
            orientation: orientation,
            neighbor_count: neighbors[index].length,
            verified: verified
          }
        end
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      color_conflicts = 0
      shared_joint_pairs = 0
      found.each_index do |i|
        neighbors[i].each do |j|
          next if j <= i
          shared_joint_pairs += 1
          color_conflicts += 1 if color_indices[i] == color_indices[j]
        end
      end

      total = painted.values.sum
      output_path = write_report(
        total: total, mismatches: mismatches, max_degree: max_degree,
        shared_joint_pairs: shared_joint_pairs, color_conflicts: color_conflicts,
        report_rows: report_rows, painted: painted, colors_hex: colors_hex
      )

      model.selection.clear
      model.selection.add(painted_entities)
      model.active_view.invalidate

      summary =
        "Listo. #{total} tubo(s) de esponja (~#{DIAMETER_REFERENCE_MM.to_i}mm de diámetro) coloreados " \
        "con #{colors_hex.length} color(es).\n" \
        "Verificados: #{total - mismatches.length} / #{total}\n" \
        "Tubos que comparten nodo con el mismo color: #{color_conflicts} de #{shared_joint_pairs} pares " \
        "(máx. #{max_degree} tubos en un nodo).\n\n" \
        "Detalle guardado en:\n#{output_path}"
      { summary: summary, output_path: output_path, total: total }
    end

    def write_report(total:, mismatches:, max_degree:, shared_joint_pairs:, color_conflicts:, report_rows:, painted:, colors_hex:)
      lines = []
      lines << "Tubos de esponja coloreados: #{total}"
      lines << "Colores usados (#{colors_hex.length}): #{colors_hex.map { |h| "##{h}" }.join(', ')}"
      lines << "Verificados (material real coincide con el asignado): #{total - mismatches.length} / #{total}"
      lines << "Máximo de tubos que se tocan en un solo nodo: #{max_degree}"
      lines << "Pares de tubos que comparten nodo: #{shared_joint_pairs}  -  con el MISMO color: #{color_conflicts}"
      lines << ('=' * 70)
      report_rows.each do |r|
        check = r[:verified] ? 'OK' : '¡NO COINCIDE!'
        lines << "##{r[:n]}  entityID=#{r[:id]}  largo=#{r[:length_mm]}mm  " \
          "diámetro=#{r[:diameter_mm]}mm  posición=(#{r[:x]}, #{r[:y]}, #{r[:z]})mm  " \
          "vecinos_en_nodo=#{r[:neighbor_count]}  color=##{r[:color]}  [#{check}]"
      end
      lines << ('=' * 70)
      lines << 'Resumen por color:'
      painted.each { |hex, n| lines << "  ##{hex}: #{n}" }
      lines << ('=' * 70)
      lines << 'Resumen por orientación:'
      report_rows.group_by { |r| r[:orientation] }.each do |orientation, rows|
        counts = Hash.new(0)
        rows.each { |r| counts[r[:color]] += 1 }
        lines << "  #{orientation} (#{rows.length} pieza(s)):"
        counts.sort.each { |hex, n| lines << "    ##{hex}: #{n}" }
      end
      unless mismatches.empty?
        lines << ('=' * 70)
        lines << "PIEZAS DONDE EL MATERIAL NO QUEDÓ COMO SE ESPERABA (#{mismatches.length}):"
        mismatches.each do |m|
          lines << "  entityID=#{m[:id]}  esperado=#{m[:expected]}  real=#{m[:actual]}  caras_pintadas=#{m[:faces_painted]}"
        end
      end

      FileUtils.mkdir_p(OUTPUT_DIR)
      output_path = File.join(OUTPUT_DIR, "colorear_tubos_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt")
      File.write(output_path, lines.join("\n"))
      output_path
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions').add_submenu('Play Idea - Colorear Tubos de Esponja')
      menu.add_item('Colorear tubos de esponja') { start }
      file_loaded(__FILE__)
    end
  end
end
