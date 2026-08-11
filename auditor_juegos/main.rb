require 'sketchup.rb'
require 'json'
require 'csv'
require 'cgi'

module Minorusal
  module AuditorJuegos
    extend self

    DICTIONARY = 'minorusal_auditor'.freeze
    GENERIC_NAMES = /\A(group|component|component#\d+|grupo|componente)?\z/i

    def analyze_model(group_scope = false)
      model = Sketchup.active_model
      instances = []
      groups = []
      loose_edges = 0
      loose_faces = 0
      hidden = 0
      untagged = 0
      walk_entities(model.entities) do |entity, path|
        hidden += 1 if entity.respond_to?(:hidden?) && entity.hidden?
        if entity.is_a?(Sketchup::ComponentInstance)
          instances << [entity, path]
          groups << [entity, path] if entity.is_a?(Sketchup::Group)
          untagged += 1 if default_tag?(entity)
        elsif entity.is_a?(Sketchup::Edge)
          loose_edges += 1 if path.empty?
        elsif entity.is_a?(Sketchup::Face)
          loose_faces += 1 if path.empty?
        end
      end

      unnamed = instances.select { |instance, _| display_name(instance).match?(GENERIC_NAMES) }
      scaled = instances.select { |instance, _| non_uniform_scale?(instance.transformation) }
      missing_code = instances.select { |instance, _| blank?(part_value(instance, 'code')) }
      missing_material = instances.select { |instance, _| effective_material(instance).nil? }
      duplicate_codes = duplicate_part_codes(instances)
      unused_definitions = model.definitions.count { |definition| !definition.image? && definition.instances.empty? }
      unused_materials = model.materials.count { |material| material.count_used.zero? rescue false }

      issues = []
      add_issue(issues, :high, 'Geometría suelta en el nivel principal',
                loose_edges + loose_faces,
                'Agrupa cada pieza fabricable como componente. La geometría suelta se pega accidentalmente y no puede contarse bien.')
      add_issue(issues, :high, 'Piezas sin código',
                missing_code.length,
                'Asigna un código único de catálogo o fabricación a cada tipo de pieza.')
      add_issue(issues, :high, 'Códigos usados en piezas diferentes',
                duplicate_codes,
                'Un mismo código debe representar una sola definición y especificación.')
      add_issue(issues, :medium, 'Componentes o grupos sin nombre descriptivo',
                unnamed.length,
                'Usa nombres como TUB-048-1500 o Plataforma 1200x1200, evitando “Grupo” y “Componente”.')
      add_issue(issues, :medium, 'Piezas sin material identificable',
                missing_material.length,
                'Asigna material, acabado o color para poder revisar y presupuestar.')
      add_issue(issues, :medium, 'Instancias con escala no uniforme',
                scaled.length,
                'Evita deformar componentes con escala; usa dimensiones paramétricas o una definición específica.')
      add_issue(issues, :low, 'Elementos en la etiqueta predeterminada',
                untagged,
                'Organiza conjuntos principales con etiquetas; mantén aristas y caras internas sin etiquetar.')
      add_issue(issues, :low, 'Elementos ocultos',
                hidden,
                'Revisa que los elementos ocultos sean intencionales antes de entregar o cuantificar.')
      add_issue(issues, :low, 'Definiciones de componente sin uso',
                unused_definitions,
                'Purga definiciones no utilizadas para reducir peso y confusión.')
      add_issue(issues, :low, 'Materiales sin uso',
                unused_materials,
                'Purga materiales no utilizados antes de entregar el archivo.')

      counts = Hash.new(0)
      instances.each { |instance, _| counts[part_key(instance)] += 1 }

      group_rows = analyze_groups(group_scope)

      {
        generated_at: Time.now.strftime('%Y-%m-%d %H:%M'),
        model_name: model.title.to_s.empty? ? 'Modelo sin guardar' : model.title,
        summary: {
          component_instances: instances.length - groups.length,
          groups: groups.length,
          definitions: model.definitions.count { |d| !d.image? },
          materials: model.materials.length,
          tags: model.layers.length,
          issues: issues.sum { |issue| issue[:count] }
        },
        issues: issues,
        parts: counts.sort_by { |name, _| name.downcase }.map { |name, quantity| { name: name, quantity: quantity } },
        groups: group_rows,
        scope: group_scope && !model.selection.empty? ? 'Selección actual' : 'Modelo completo'
      }
    end

    def analyze_groups(selection_only = false)
      model = Sketchup.active_model
      selected = model.selection.select { |e| container?(e) }
      roots = selection_only && !selected.empty? ? selected : model.entities.select { |e| container?(e) }
      rows = []
      roots.each do |entity|
        collect_group_rows(entity, Geom::Transformation.new, [], 0, rows, {})
      end
      rows
    end

    def collect_group_rows(entity, parent_transform, parent_path, depth, rows, ancestors)
      return unless container?(entity)
      definition = entity.definition
      return if ancestors[definition.object_id]

      global_transform = parent_transform * entity.transformation
      name = display_name(entity)
      path = parent_path + [name.empty? ? '(sin nombre)' : name]
      children = definition.entities.select { |child| container?(child) }
      faces = definition.entities.grep(Sketchup::Face).length
      edges = definition.entities.grep(Sketchup::Edge).length
      dimensions = transformed_dimensions(definition.bounds, global_transform)
      material = effective_material(entity)
      rows << {
        depth: depth,
        path: path.join(' > '),
        name: name.empty? ? '(sin nombre)' : name,
        kind: entity.is_a?(Sketchup::Group) ? 'Grupo' : 'Componente',
        children: children.length,
        faces: faces,
        edges: edges,
        dimensions: dimensions.map { |value| format('%.2f', value) }.join(' × '),
        material: material ? material.display_name.to_s : 'Sin material',
        tag: entity.layer ? entity.layer.display_name.to_s : 'Sin etiqueta',
        classification: group_classification(entity, dimensions, faces, children.length)
      }

      branch = ancestors.merge(definition.object_id => true)
      children.each do |child|
        collect_group_rows(child, global_transform, path, depth + 1, rows, branch)
      end
    end

    def container?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

    def transformed_dimensions(bounds, transformation)
      transformed = Geom::BoundingBox.new
      8.times { |index| transformed.add(bounds.corner(index).transform(transformation)) }
      [transformed.width.to_m, transformed.height.to_m, transformed.depth.to_m].map(&:abs)
    end

    def group_classification(entity, dimensions, faces, children)
      text = [display_name(entity), entity.layer&.name, effective_material(entity)&.display_name]
             .compact.join(' ').downcase
      return 'Malla / red' if text.match?(/malla|red/)
      return 'Plataforma' if text.match?(/plataforma|piso/)
      return 'Protección / forro' if text.match?(/foam|forro|prote|vinil/)
      return 'Obstáculo / accesorio' if text.match?(/liga|colump|resbal|rodillo|rampa|ducto|tobogan/)

      sorted = dimensions.sort
      if sorted[1] <= 0.20 && sorted[2] >= sorted[1] * 1.5
        'Posible tubo'
      elsif children.positive? && faces.zero?
        'Ensamble'
      elsif faces.positive?
        'Pieza geométrica'
      else
        'Contenedor vacío'
      end
    end

    def walk_entities(entities, path = [], visited = {}, &block)
      entities.each do |entity|
        yield(entity, path)
        next unless entity.is_a?(Sketchup::ComponentInstance)
        definition = entity.definition
        next if visited[definition.object_id]
        branch = visited.merge(definition.object_id => true)
        walk_entities(definition.entities, path + [display_name(entity)], branch, &block)
      end
    end

    def add_issue(issues, severity, title, count, recommendation)
      return if count.to_i.zero?
      issues << { severity: severity, title: title, count: count, recommendation: recommendation }
    end

    def display_name(instance)
      name = instance.name.to_s.strip
      name = instance.definition.name.to_s.strip if name.empty?
      name
    end

    def part_key(instance)
      code = part_value(instance, 'code').to_s.strip
      code.empty? ? display_name(instance) : "#{code} — #{display_name(instance)}"
    end

    def part_value(instance, key)
      instance.get_attribute(DICTIONARY, key) ||
        instance.definition.get_attribute(DICTIONARY, key)
    end

    def effective_material(instance)
      return instance.material if instance.material
      instance.definition.entities.find { |entity| entity.respond_to?(:material) && entity.material }&.material
    end

    def default_tag?(entity)
      layer = entity.layer
      layer.nil? || layer == entity.model.layers[0]
    end

    def non_uniform_scale?(transformation)
      x = transformation.xaxis.length
      y = transformation.yaxis.length
      z = transformation.zaxis.length
      ([x, y, z].max - [x, y, z].min) > 0.001
    end

    def duplicate_part_codes(instances)
      owners = Hash.new { |hash, key| hash[key] = {} }
      instances.each do |instance, _|
        code = part_value(instance, 'code').to_s.strip
        owners[code][instance.definition.object_id] = true unless code.empty?
      end
      owners.count { |_, definitions| definitions.length > 1 }
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def show_report(group_scope = false)
      report = analyze_model(group_scope)
      @last_report = report
      dialog = UI::HtmlDialog.new(
        dialog_title: 'Auditor de Juegos Modulares',
        preferences_key: 'minorusal.auditor_juegos',
        scrollable: true,
        resizable: true,
        width: 900,
        height: 700,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      dialog.set_html(report_html(report))
      dialog.add_action_callback('exportCsv') { |_context| export_csv(@last_report) }
      dialog.show
      @dialog = dialog
    rescue StandardError => error
      UI.messagebox("No fue posible analizar el modelo:\n#{error.message}")
      puts error.full_message
    end

    def export_csv(report)
      path = UI.savepanel('Guardar reporte de auditoría', '', 'auditoria_modelo.csv')
      return unless path
      CSV.open(path, 'wb') do |csv|
        csv << %w[SEVERIDAD HALLAZGO CANTIDAD RECOMENDACION]
        report[:issues].each do |issue|
          csv << [issue[:severity].to_s.upcase, issue[:title], issue[:count], issue[:recommendation]]
        end
        csv << []
        csv << ['PIEZA', 'CANTIDAD']
        report[:parts].each { |part| csv << [part[:name], part[:quantity]] }
        csv << []
        csv << ['RUTA DEL GRUPO', 'TIPO', 'CLASIFICACION', 'DIMENSIONES XYZ (m)',
                'HIJOS', 'CARAS DIRECTAS', 'ARISTAS DIRECTAS', 'MATERIAL', 'ETIQUETA']
        report[:groups].each do |group|
          csv << [group[:path], group[:kind], group[:classification], group[:dimensions],
                  group[:children], group[:faces], group[:edges], group[:material], group[:tag]]
        end
      end
      UI.messagebox("Reporte guardado en:\n#{path}")
    end

    def report_html(report)
      summary = report[:summary].map do |key, value|
        "<div class='card'><strong>#{value}</strong><span>#{label_for(key)}</span></div>"
      end.join
      issues = if report[:issues].empty?
                 "<p class='ok'>No se detectaron problemas con las reglas actuales.</p>"
               else
                 report[:issues].map do |issue|
                   "<tr><td><span class='badge #{issue[:severity]}'>#{severity_label(issue[:severity])}</span></td>" \
                   "<td><b>#{h(issue[:title])}</b><br><small>#{h(issue[:recommendation])}</small></td>" \
                   "<td class='number'>#{issue[:count]}</td></tr>"
                 end.join
               end
      parts = report[:parts].map do |part|
        "<tr><td>#{h(part[:name])}</td><td class='number'>#{part[:quantity]}</td></tr>"
      end.join
      groups = report[:groups].map do |group|
        "<tr><td style='padding-left:#{10 + group[:depth] * 16}px'>#{h(group[:name])}</td>" \
        "<td>#{h(group[:kind])}</td><td>#{h(group[:classification])}</td>" \
        "<td>#{h(group[:dimensions])}</td><td class='number'>#{group[:children]}</td>" \
        "<td>#{h(group[:material])}</td><td>#{h(group[:tag])}</td></tr>"
      end.join
      <<~HTML
        <!doctype html><html><head><meta charset="utf-8"><style>
        body{font:14px Arial,sans-serif;color:#24303b;margin:24px;background:#f6f8fa}
        h1{margin:0 0 4px;color:#17324d} .meta{color:#657786;margin-bottom:20px}
        .cards{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
        .card{background:white;border-radius:8px;padding:15px;border:1px solid #dde3e8}
        .card strong{display:block;font-size:24px;color:#087f5b}.card span{color:#657786}
        table{width:100%;border-collapse:collapse;background:white;margin:10px 0 24px}
        th,td{padding:10px;border-bottom:1px solid #e5e9ed;text-align:left;vertical-align:top}
        th{background:#17324d;color:white}.number{text-align:right;font-weight:bold}
        small{color:#657786}.badge{padding:3px 7px;border-radius:10px;color:white;font-size:11px}
        .high{background:#c92a2a}.medium{background:#e67700}.low{background:#1971c2}
        button{background:#087f5b;color:white;border:0;padding:10px 16px;border-radius:5px;cursor:pointer}
        .ok{background:#d3f9d8;padding:14px;border-radius:6px}
        </style></head><body>
        <h1>Auditor de Juegos Modulares</h1>
        <div class="meta">#{h(report[:model_name])} · #{report[:generated_at]} · #{h(report[:scope])}</div>
        <div class="cards">#{summary}</div>
        <h2>Hallazgos y recomendaciones</h2>
        <table><thead><tr><th>Nivel</th><th>Hallazgo</th><th>Cantidad</th></tr></thead><tbody>#{issues}</tbody></table>
        <h2>Inventario detectado</h2>
        <table><thead><tr><th>Pieza</th><th>Cantidad</th></tr></thead><tbody>#{parts}</tbody></table>
        <h2>Análisis jerárquico por grupo</h2>
        <table><thead><tr><th>Grupo / ruta</th><th>Tipo</th><th>Clasificación</th><th>Dimensiones XYZ (m)</th><th>Hijos</th><th>Material</th><th>Etiqueta</th></tr></thead><tbody>#{groups}</tbody></table>
        <button onclick="sketchup.exportCsv()">Exportar CSV</button>
        </body></html>
      HTML
    end

    def h(value)
      CGI.escapeHTML(value.to_s)
    end

    def label_for(key)
      {
        component_instances: 'Componentes', groups: 'Grupos', definitions: 'Definiciones',
        materials: 'Materiales', tags: 'Etiquetas', issues: 'Observaciones'
      }[key]
    end

    def severity_label(severity)
      { high: 'ALTA', medium: 'MEDIA', low: 'BAJA' }[severity]
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions').add_submenu('Auditor de Juegos Modulares')
      menu.add_item('Analizar modelo actual') { show_report }
      menu.add_item('Analizar por grupos (selección o modelo)') { show_report(true) }
      file_loaded(__FILE__)
    end
  end
end
