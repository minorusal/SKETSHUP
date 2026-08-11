require 'sketchup.rb'
require 'json'

module PlayIdea
  module Conectores
    extend self

    DICTIONARY = 'playidea_conector'.freeze
    SEGMENTS = 24
    OUTSIDE_MM = 48.3
    WALL_MM = 3.18
    INSIDE_MM = OUTSIDE_MM - (2.0 * WALL_MM)

    CONNECTORS = {
      '10' => 'T sencilla a 90°',
      '12' => 'T inclinada a 45°',
      '19' => 'Conector lateral de dos receptores',
      '21' => 'T lateral de tres direcciones',
      '35' => 'Cruz con tres salidas laterales',
      '40' => 'Paso central con cuatro salidas radiales',
      '61' => 'Receptor con base',
      'COPLE' => 'Cople recto para extensión'
    }.freeze

    SPECS = {
      '10' => { cuts: [63.5, 50.8], nuts: 2, screws: 2, plate: false },
      '12' => { cuts: [63.5, 76.2], nuts: 2, screws: 2, plate: false },
      '19' => { cuts: [50.8, 50.8], nuts: 2, screws: 2, plate: false },
      '21' => { cuts: [63.5, 50.8, 50.8], nuts: 3, screws: 3, plate: false },
      '35' => { cuts: [63.5, 50.8, 50.8, 50.8], nuts: 4, screws: 4, plate: false },
      '40' => { cuts: [63.5, 50.8, 50.8, 50.8, 50.8], nuts: 5, screws: 5, plate: false },
      '61' => { cuts: [50.8], nuts: 1, screws: 1, plate: true },
      'COPLE' => { cuts: [101.6], nuts: 2, screws: 2, plate: false }
    }.freeze

    # Valores iniciales aproximados en MXN. Son editables y se recuerdan para
    # las siguientes inserciones.
    DEFAULT_COSTS = {
      'bar_6m' => 700.0,
      'nut' => 6.0,
      'screw' => 12.0,
      'base_plate' => 45.0,
      'cut' => 10.0,
      'weld' => 30.0,
      'welding_supplies' => 18.0,
      'electricity' => 10.0,
      'finish' => 25.0,
      'other' => 12.0
    }.freeze

    def start
      return start_legacy unless defined?(UI::HtmlDialog)

      @selector_dialog&.close
      @selector_dialog = UI::HtmlDialog.new(
        dialog_title: 'Conectores Play Idea',
        preferences_key: 'PlayIdeaConectoresSelector',
        scrollable: true,
        resizable: true,
        width: 780,
        height: 650,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @selector_dialog.set_file(File.join(__dir__, 'selector.html'))
      @selector_dialog.add_action_callback('ready') do |_action_context|
        items = build_preview_catalog
        @selector_dialog.execute_script(
          "loadConnectors(#{JSON.generate(items)})"
        )
      end
      @selector_dialog.add_action_callback('insertConnector') do |_action_context, code, color, receiver_material, hardware_size|
        unless CONNECTORS.key?(code.to_s)
          UI.messagebox('El código seleccionado no existe.')
          next
        end
        costing = capture_costs(code.to_s)
        next unless costing
        metadata = {
          receiver_material: receiver_material.to_s,
          hardware_size: hardware_size.to_s,
          costing: costing,
          investment_cost_mxn: costing[:total]
        }
        @selector_dialog.close
        Sketchup.active_model.select_tool(
          PlacementTool.new(code.to_s, color.to_s, metadata)
        )
      end
      @selector_dialog.show
    end

    # Las imágenes del catálogo se producen con la misma geometría 3D que se
    # inserta en el modelo. De esta manera nunca pueden contradecir al plugin.
    def build_preview_catalog
      model = Sketchup.active_model
      CONNECTORS.map do |code, description|
        definition = model.definitions.add(
          unique_name(model, "Vista temporal Conector #{code}")
        )
        build_connector_geometry(definition.entities, code, nil, nil)
        definition.invalidate_bounds
        set_top_thumbnail_camera(definition)
        path = File.join(
          Sketchup.temp_dir,
          "playidea_conector_#{code.downcase}_preview.png"
        )
        definition.refresh_thumbnail
        saved = definition.save_thumbnail(path)
        {
          code: code,
          description: description,
          preview: saved ? file_url(path) : nil
        }
      ensure
        if definition && definition.valid? &&
           model.definitions.respond_to?(:remove)
          model.definitions.remove(definition)
        end
      end
    end

    def set_top_thumbnail_camera(definition)
      return unless definition.respond_to?(:thumbnail_camera=)

      bounds = definition.bounds
      center = bounds.center
      extent = [bounds.width, bounds.height, bounds.depth, 1.0].max
      eye = center.offset(Z_AXIS, extent * 3.0)
      camera = Sketchup::Camera.new(eye, center, Y_AXIS, false)
      camera.height = extent * 1.35 if camera.respond_to?(:height=)
      definition.thumbnail_camera = camera
    end

    def file_url(path)
      normalized = File.expand_path(path).tr('\\', '/')
      "file://#{normalized.gsub(' ', '%20')}"
    end

    # Selector compatible con versiones antiguas de SketchUp sin HtmlDialog.
    def start_legacy
      labels = CONNECTORS.map { |code, description| "#{code} — #{description}" }
      result = UI.inputbox(
        ['Tipo de conector', 'Color', 'Material del receptor', 'Medida de tuerca/opresor'],
        [labels.first, 'Galvanizado', 'Acero al carbón', 'M8'],
        [labels.join('|'), 'Galvanizado|Azul|Rojo|Amarillo|Verde|Naranja|Negro',
         'Acero al carbón|Acero galvanizado|Acero inoxidable', 'M6|M8|M10|M12'],
        'Insertar conector Play Idea'
      )
      return unless result

      code = result[0].to_s.split(' — ').first
      color = result[1].to_s
      costing = capture_costs(code)
      return unless costing
      metadata = {
        receiver_material: result[2].to_s,
        hardware_size: result[3].to_s,
        costing: costing,
        investment_cost_mxn: costing[:total]
      }
      Sketchup.active_model.select_tool(PlacementTool.new(code, color, metadata))
    end

    def capture_costs(code)
      prompts = [
        'Precio de una barra de tubo de 6 m (MXN)',
        'Costo por tuerca (MXN)',
        'Costo por opresor Allen (MXN)',
        'Costo de placa base por pieza (MXN)',
        'Mano de obra por corte (MXN)',
        'Mano de obra por unión soldada (MXN)',
        'Consumibles de soldadura por conector (MXN)',
        'Electricidad por conector (MXN)',
        'Acabado/pintura por conector (MXN)',
        'Otros insumos por conector (MXN)'
      ]
      keys = %w[bar_6m nut screw base_plate cut weld welding_supplies electricity finish other]
      defaults = keys.map do |key|
        stored = Sketchup.read_default('PlayIdeaConectoresCostos', key, nil)
        stored.nil? || stored.to_f <= 0 ? DEFAULT_COSTS[key] : stored.to_f
      end
      values = UI.inputbox(prompts, defaults, 'Costos de fabricación')
      return nil unless values
      keys.each_with_index do |key, index|
        Sketchup.write_default('PlayIdeaConectoresCostos', key, values[index].to_f)
      end
      build_cost_breakdown(code, keys.zip(values.map(&:to_f)).to_h)
    end

    def build_cost_breakdown(code, costs)
      spec = SPECS.fetch(code)
      receiver_joints = [spec[:cuts].length - 1, 0].max
      welded_nuts = spec[:nuts]
      welding_operations = receiver_joints + welded_nuts + (spec[:plate] ? 1 : 0)
      rows = spec[:cuts].each_with_index.map do |length_mm, index|
        cost_row(
          "Tubo receptor #{index + 1} — #{length_mm} mm",
          length_mm / 6000.0,
          'barra de 6 m',
          costs['bar_6m']
        )
      end
      rows.concat([
        cost_row('Tuercas', spec[:nuts], 'pieza', costs['nut']),
        cost_row('Opresores Allen', spec[:screws], 'pieza', costs['screw']),
        cost_row('Cortes de tubo', spec[:cuts].length, 'corte', costs['cut']),
        cost_row('Uniones soldadas', welding_operations, 'operación', costs['weld']),
        cost_row('Consumibles de soldadura', 1, 'conector', costs['welding_supplies']),
        cost_row('Electricidad', 1, 'conector', costs['electricity']),
        cost_row('Acabado / pintura', 1, 'conector', costs['finish']),
        cost_row('Otros insumos', 1, 'conector', costs['other'])
      ])
      rows.insert(
        spec[:cuts].length + 2,
        cost_row('Placa redonda Ø90 × 6 mm', 1, 'pieza', costs['base_plate'])
      ) if spec[:plate]
      { rows: rows, total: rows.inject(0.0) { |sum, row| sum + row[:subtotal] } }
    end

    def cost_row(item, quantity, unit, unit_cost)
      {
        item: item,
        quantity: quantity,
        unit: unit,
        unit_cost: unit_cost,
        subtotal: quantity * unit_cost
      }
    end

    def create_connector(code, color, metadata, point)
      model = Sketchup.active_model
      model.start_operation("Insertar conector #{code}", true)
      definition = model.definitions.add(unique_name(model, "Conector #{code}"))
      material = connector_material(model, color)
      hardware = hardware_material(model)

      build_connector_geometry(
        definition.entities, code, material, hardware
      )

      write_attributes(definition, code, color, metadata)
      instance = model.active_entities.add_instance(definition, Geom::Transformation.translation(point))
      instance.name = "CON-#{code}"
      write_attributes(instance, code, color, metadata)
      model.selection.clear
      model.selection.add(instance)
      model.commit_operation
      instance
    rescue StandardError
      model.abort_operation
      raise
    end

    def build_connector_geometry(entities, code, material, hardware)
      case code
      when '10' then build_10(entities, material, hardware)
      when '12' then build_12(entities, material, hardware)
      when '19' then build_19(entities, material, hardware)
      when '21' then build_21(entities, material, hardware)
      when '35' then build_35(entities, material, hardware)
      when '40' then build_40(entities, material, hardware)
      when '61' then build_61(entities, material, hardware)
      when 'COPLE' then build_coupling(entities, material, hardware)
      else raise ArgumentError, "Conector desconocido: #{code}"
      end
    end

    # T: cuerpo horizontal de 2.5" y ramal vertical de 2".
    def build_10(entities, material, hardware)
      add_centered_sleeve(entities, X_AXIS, 63.5, material, hardware)
      add_branch_sleeve(entities, Z_AXIS.reverse, 50.8, material, hardware)
    end

    # T con ramal de 3" inclinado a 45°.
    def build_12(entities, material, hardware)
      add_centered_sleeve(entities, X_AXIS, 63.5, material, hardware)
      # El paso recto y la diagonal deben estar en el mismo plano X-Z para
      # poder formar un bastidor triangular.
      angled = Geom::Vector3d.new(-1, 0, -1).normalize
      add_mitered_branch_12(entities, angled, 76.2, material, hardware)
    end

    # Dos receptores de 2"; geometría base a 90°.
    def build_19(entities, material, hardware)
      length_mm = 50.8
      radius = OUTSIDE_MM / 2.0

      horizontal_origin = Geom::Point3d.new(0, 0, radius.mm)
      horizontal = add_sleeve(
        entities, horizontal_origin, X_AXIS.reverse, length_mm, material
      )
      add_hardware(
        horizontal.entities,
        Geom::Point3d.new(0, 0, (length_mm * 0.65).mm),
        X_AXIS,
        hardware
      )

      # Geometría confirmada mediante el tercer diagrama:
      # horizontal X<=0 entre Z=0 y Z=D; vertical completamente a la derecha,
      # pared izquierda en X=0 y base en Z=D/2. Sólo existe contacto
      # superficial desde Z=D/2 hasta Z=D, sin intersección.
      vertical_origin = Geom::Point3d.new(
        radius.mm,
        0,
        radius.mm
      )
      vertical = add_sleeve(
        entities, vertical_origin, Z_AXIS, length_mm, material
      )
      add_hardware(
        vertical.entities,
        Geom::Point3d.new(0, 0, (length_mm * 0.65).mm),
        X_AXIS,
        hardware
      )
    end

    # Cuerpo de 2.5" con dos salidas perpendiculares de 2".
    def build_21(entities, material, hardware)
      radius = OUTSIDE_MM / 2.0
      short_length = 50.8
      main_length = 63.5

      # Salida horizontal hacia la izquierda. Su parte inferior está en Z=0.
      blue_origin = Geom::Point3d.new(0, 0, radius.mm)
      blue = add_sleeve(
        entities, blue_origin, X_AXIS.reverse, short_length, material
      )
      blue.name = 'Salida azul 2 pulgadas'
      add_hardware(
        blue.entities,
        Geom::Point3d.new(0, 0, (short_length * 0.65).mm),
        X_AXIS,
        hardware
      )

      # Segunda salida a 90°, centrada sobre el nodo (mitad hacia atrás,
      # mitad hacia adelante) en vez de arrancar justo en el nodo. Así su
      # línea de contacto con la salida azul cubre el diámetro completo
      # (48.3 mm) en vez de solo la mitad, y no deja el borde descubierto.
      green_origin = Geom::Point3d.new(radius.mm, -(short_length / 2.0).mm, radius.mm)
      green = add_sleeve(
        entities, green_origin, Y_AXIS, short_length, material
      )
      # Gira 180° sobre su propio eje: local_axes() deja su tuerca apuntando
      # hacia -X por defecto, directo hacia el cuerpo de la salida azul. Con
      # este giro queda apuntando hacia +X, del lado libre.
      green.transform!(Geom::Transformation.rotation(green_origin, Y_AXIS, 180.degrees))
      green.name = 'Salida verde 2 pulgadas'
      add_hardware(
        green.entities,
        Geom::Point3d.new(0, 0, (short_length * 0.65).mm),
        X_AXIS,
        hardware
      )

      # Principal vertical colocado debajo de la salida verde. Su tapa
      # superior está en Z=0 y el cuerpo se desarrolla hacia abajo. Toca las
      # superficies inferiores sin compartir volumen con las salidas.
      main_origin = Geom::Point3d.new(radius.mm, 0, 0)
      main = add_sleeve(
        entities, main_origin, Z_AXIS.reverse, main_length, material
      )
      main.name = 'Principal 2.5 pulgadas'
      add_hardware(
        main.entities,
        Geom::Point3d.new(0, 0, (main_length * 0.65).mm),
        X_AXIS,
        hardware
      )
    end

    # Cuerpo de 2.5" con tres salidas radiales de 2".
    def build_35(entities, material, hardware)
      add_centered_sleeve(entities, Z_AXIS, 63.5, material, hardware)
      add_branch_sleeve(entities, X_AXIS, 50.8, material, hardware)
      add_branch_sleeve(entities, Y_AXIS, 50.8, material, hardware)
      add_branch_sleeve(entities, X_AXIS.reverse, 50.8, material, hardware)
    end

    # Conector 40: un manguito vertical continuo y cuatro receptores
    # horizontales a 90°. El manguito está abierto por ambos extremos para
    # que el tubo estructural vertical atraviese completamente la pieza.
    # Los ramales comienzan en su pared exterior y no invaden el paso central.
    def build_40(entities, material, hardware)
      central_length = 63.5
      central_start = ORIGIN.offset(
        Z_AXIS.reverse, (central_length / 2.0).mm
      )
      central = add_sleeve(
        entities, central_start, Z_AXIS, central_length, material
      )
      central.name = 'Paso central continuo 2.5 pulgadas'
      # Se coloca por encima del plano de los cuatro ramales para que la
      # tuerca y el opresor centrales no queden enterrados en la soldadura.
      add_hardware(
        central.entities,
        Geom::Point3d.new(0, 0, (central_length * 0.82).mm),
        X_AXIS,
        hardware
      )

      [
        ['Salida +X', X_AXIS],
        ['Salida -X', X_AXIS.reverse],
        ['Salida +Y', Y_AXIS],
        ['Salida -Y', Y_AXIS.reverse]
      ].each do |name, direction|
        branch = add_branch_sleeve(
          entities, direction, 50.8, material, hardware
        )
        branch.name = "#{name} 2 pulgadas"
      end
    end

    # Receptor de 2" soldado a una placa inferior.
    def build_61(entities, material, hardware)
      length_mm = 50.8
      # El receptor comienza en Z=0, directamente sobre la cara superior de
      # la placa. No se aplica el desplazamiento usado por los ramales.
      sleeve = add_sleeve(entities, ORIGIN, Z_AXIS, length_mm, material)
      sleeve.name = 'Receptor de placa 2 pulgadas'
      add_hardware(
        sleeve.entities,
        Geom::Point3d.new(0, 0, (length_mm * 0.65).mm),
        X_AXIS,
        hardware
      )
      add_round_base_plate(entities, material)
    end

    # Manguito recto de 4" con opresor en cada extremo.
    def build_coupling(entities, material, hardware)
      group = add_sleeve(entities, ORIGIN, Z_AXIS, 101.6, material)
      add_hardware(group.entities, Geom::Point3d.new(0, 0, 22.0.mm), X_AXIS, hardware)
      add_hardware(group.entities, Geom::Point3d.new(0, 0, 79.6.mm), X_AXIS, hardware)
    end

    def add_centered_sleeve(entities, direction, length_mm, material, hardware)
      start = ORIGIN.offset(direction.reverse, (length_mm / 2.0).mm)
      group = add_sleeve(entities, start, direction, length_mm, material)
      local_position = Geom::Point3d.new(0, 0, (length_mm / 2.0).mm)
      add_hardware(group.entities, local_position, X_AXIS, hardware)
      group
    end

    def add_branch_sleeve(entities, direction, length_mm, material, hardware, start_distance_mm = nil)
      # El ramal comienza en la superficie exterior del cuerpo principal para
      # no invadir el hueco por donde pasa el tubo estructural.
      start_distance_mm ||= OUTSIDE_MM / 2.0 - 1.0
      start = ORIGIN.offset(direction, start_distance_mm.mm)
      group = add_sleeve(entities, start, direction, length_mm, material)
      local_position = Geom::Point3d.new(0, 0, (length_mm * 0.65).mm)
      add_hardware(group.entities, local_position, X_AXIS, hardware)
      group
    end

    # Receptor diagonal cuyo extremo se corta con un plano horizontal. El
    # resultado es un corte oblicuo de 45° que apoya bajo el tubo principal.
    def add_mitered_branch_12(entities, direction, length_mm, material, hardware)
      radius = OUTSIDE_MM / 2.0
      contact = Geom::Point3d.new(0, 0, -radius.mm)
      group = entities.add_group
      add_mitered_hollow_tube(
        group.entities, length_mm.mm, material, direction, Z_AXIS
      )
      group.transform!(axes_transform(contact, direction))
      group.name = "Receptor diagonal 45° — #{format('%.1f', length_mm)} mm"
      local_position = Geom::Point3d.new(0, 0, (length_mm * 0.65).mm)
      add_hardware(group.entities, local_position, X_AXIS, hardware)
      group
    end

    def add_sleeve(entities, start, direction, length_mm, material)
      group = entities.add_group
      add_hollow_tube(group.entities, length_mm.mm, material)
      group.transform!(axes_transform(start, direction))
      group.name = "Receptor #{format('%.1f', length_mm)} mm"
      group
    end

    def add_hollow_tube(entities, length, material)
      outer = (OUTSIDE_MM / 2.0).mm
      inner = (INSIDE_MM / 2.0).mm
      ob = circle_points(outer, 0)
      ot = circle_points(outer, length)
      ib = circle_points(inner, 0)
      it = circle_points(inner, length)

      SEGMENTS.times do |index|
        following = (index + 1) % SEGMENTS
        faces = []
        faces << entities.add_face(ob[index], ob[following], ot[following], ot[index])
        faces << entities.add_face(ib[index], it[index], it[following], ib[following])
        faces << entities.add_face(ob[following], ob[index], ib[index], ib[following])
        faces << entities.add_face(ot[index], ot[following], it[following], it[index])
        faces.compact.each do |face|
          face.material = material
          face.back_material = material
        end
      end
      soften_round_edges(entities)
    end

    def add_mitered_hollow_tube(entities, length, material, global_axis, plane_normal)
      outer = (OUTSIDE_MM / 2.0).mm
      inner = (INSIDE_MM / 2.0).mm
      x_axis, y_axis, z_axis = local_axes(global_axis)
      ob = miter_circle_points(outer, x_axis, y_axis, z_axis, plane_normal)
      ib = miter_circle_points(inner, x_axis, y_axis, z_axis, plane_normal)
      ot = circle_points(outer, length)
      it = circle_points(inner, length)

      SEGMENTS.times do |index|
        following = (index + 1) % SEGMENTS
        faces = []
        faces << entities.add_face(ob[index], ob[following], ot[following], ot[index])
        faces << entities.add_face(ib[index], it[index], it[following], ib[following])
        faces << entities.add_face(ob[following], ob[index], ib[index], ib[following])
        faces << entities.add_face(ot[index], ot[following], it[following], it[index])
        faces.compact.each do |face|
          face.material = material
          face.back_material = material
        end
      end
      soften_round_edges(entities)
    end

    def miter_circle_points(radius, x_axis, y_axis, z_axis, plane_normal)
      denominator = z_axis.dot(plane_normal)
      SEGMENTS.times.map do |index|
        angle = (2.0 * Math::PI * index) / SEGMENTS
        x = radius * Math.cos(angle)
        y = radius * Math.sin(angle)
        projected = (x * x_axis.dot(plane_normal)) + (y * y_axis.dot(plane_normal))
        z = -projected / denominator
        Geom::Point3d.new(x, y, z)
      end
    end

    def add_hardware(entities, position, radial_direction, material)
      outside_radius = OUTSIDE_MM / 2.0
      inside_radius = INSIDE_MM / 2.0
      nut = entities.add_group
      add_prism(nut.entities, 7.0.mm, 8.0.mm, 6, material)
      nut.transform!(axes_transform(position.offset(radial_direction, outside_radius.mm), radial_direction))
      nut.name = 'Tuerca'

      screw = entities.add_group
      # Se representa retraído: llega hasta la pared interior sin atravesar el
      # paso libre. Al apretarlo avanzaría contra el tubo insertado.
      screw_start_radius = outside_radius + 8.0
      screw_length = screw_start_radius - inside_radius
      add_prism(screw.entities, 3.0.mm, screw_length.mm, 12, material)
      screw.transform!(axes_transform(position.offset(radial_direction, screw_start_radius.mm), radial_direction.reverse))
      screw.name = 'Opresor Allen'
    end

    def add_prism(entities, radius, length, segments, material)
      edges = entities.add_circle(ORIGIN, Z_AXIS, radius, segments)
      face = entities.add_face(edges)
      face.material = material
      face.pushpull(length)
      entities.grep(Sketchup::Face).each do |item|
        item.material = material
        item.back_material = material
      end
    end

    def add_round_base_plate(entities, material)
      radius = 45.0.mm
      thickness = 6.0.mm
      edges = entities.add_circle(ORIGIN, Z_AXIS, radius, 48)
      face = entities.add_face(edges)
      face.reverse! if face.normal.z < 0
      face.pushpull(-thickness)
      entities.grep(Sketchup::Face).each do |item|
        item.material = material
        item.back_material = material
      end
    end

    def circle_points(radius, z_value)
      SEGMENTS.times.map do |index|
        angle = (2.0 * Math::PI * index) / SEGMENTS
        Geom::Point3d.new(radius * Math.cos(angle), radius * Math.sin(angle), z_value)
      end
    end

    def soften_round_edges(entities)
      entities.grep(Sketchup::Edge).each do |edge|
        vector = edge.end.position - edge.start.position
        next if vector.parallel?(Z_AXIS)
        edge.soft = true
        edge.smooth = true
      end
    end

    def axes_transform(origin, z_axis)
      x, y, z = local_axes(z_axis)
      Geom::Transformation.axes(origin, x, y, z)
    end

    def local_axes(z_axis)
      z = z_axis.normalize
      helper = z.parallel?(Z_AXIS) ? X_AXIS : Z_AXIS
      x = helper.cross(z).normalize
      y = z.cross(x).normalize
      [x, y, z]
    end

    def connector_material(model, name)
      material_name = "PlayIdea Conector - #{name}"
      material = model.materials[material_name] || model.materials.add(material_name)
      material.color = {
        'Galvanizado' => Sketchup::Color.new(175, 182, 185),
        'Azul' => Sketchup::Color.new(25, 85, 210),
        'Rojo' => Sketchup::Color.new(220, 40, 40),
        'Amarillo' => Sketchup::Color.new(245, 205, 25),
        'Verde' => Sketchup::Color.new(35, 170, 80),
        'Naranja' => Sketchup::Color.new(245, 125, 20),
        'Negro' => Sketchup::Color.new(35, 35, 35)
      }[name] || Sketchup::Color.new(175, 182, 185)
      material
    end

    def hardware_material(model)
      material = model.materials['PlayIdea Herrajes'] || model.materials.add('PlayIdea Herrajes')
      material.color = Sketchup::Color.new(55, 58, 62)
      material
    end

    def write_attributes(entity, code, color, metadata)
      spec = SPECS.fetch(code)
      total_tube_mm = spec[:cuts].inject(0.0, :+)
      materials = [
        {
          item: 'Tubo receptor',
          specification: "1 1/2 pulgadas cédula 30 - #{metadata[:receiver_material]}",
          cuts_mm: spec[:cuts],
          total_length_mm: total_tube_mm
        },
        {
          item: 'Tuerca',
          specification: metadata[:hardware_size],
          quantity: spec[:nuts]
        },
        {
          item: 'Opresor Allen',
          specification: metadata[:hardware_size],
          quantity: spec[:screws]
        }
      ]
      materials << {
        item: 'Placa base',
        specification: 'Redonda Ø90 × 6 mm',
        quantity: 1
      } if spec[:plate]

      data = {
        'code' => "CON-#{code}",
        'connector_type' => code,
        'description' => CONNECTORS[code],
        'receiver_nominal_size' => '1 1/2 pulgadas',
        'receiver_schedule' => '30',
        'receiver_outside_mm' => OUTSIDE_MM,
        'receiver_inside_mm' => INSIDE_MM,
        'receiver_wall_mm' => WALL_MM,
        'color' => color,
        'investment_cost_mxn' => metadata[:investment_cost_mxn],
        'currency' => 'MXN',
        'receiver_material' => metadata[:receiver_material],
        'tube_cuts_mm' => spec[:cuts].join(', '),
        'total_tube_length_mm' => total_tube_mm,
        'nut_specification' => metadata[:hardware_size],
        'nut_quantity' => spec[:nuts],
        'set_screw_specification' => metadata[:hardware_size],
        'set_screw_quantity' => spec[:screws],
        'has_base_plate' => spec[:plate],
        'materials_json' => JSON.generate(materials),
        'cost_breakdown_json' => JSON.generate(metadata[:costing][:rows])
      }
      data.each { |key, value| entity.set_attribute(DICTIONARY, key, value) }
      entity.set_attribute('minorusal_auditor', 'code', "CON-#{code}")
      entity.set_attribute('minorusal_auditor', 'investment_cost_mxn', metadata[:investment_cost_mxn])
    end

    def show_selected_metadata
      entity = Sketchup.active_model.selection.find do |item|
        item.respond_to?(:get_attribute) &&
          item.get_attribute(DICTIONARY, 'connector_type')
      end
      unless entity
        UI.messagebox('Selecciona primero un conector creado con Play Idea.')
        return
      end

      read = lambda do |key|
        entity.get_attribute(DICTIONARY, key) ||
          (entity.respond_to?(:definition) && entity.definition.get_attribute(DICTIONARY, key))
      end
      message = [
        "FICHA DEL CONECTOR #{read.call('connector_type')}",
        '',
        "Código: #{read.call('code')}",
        "Descripción: #{read.call('description')}",
        "Costo de inversión: $#{format('%.2f', read.call('investment_cost_mxn').to_f)} MXN",
        "Material: #{read.call('receiver_material')}",
        "Tubo receptor: #{read.call('receiver_nominal_size')} cédula #{read.call('receiver_schedule')}",
        "Cortes: #{read.call('tube_cuts_mm')} mm",
        "Longitud total de tubo: #{read.call('total_tube_length_mm')} mm",
        "Tuercas: #{read.call('nut_quantity')} × #{read.call('nut_specification')}",
        "Opresores Allen: #{read.call('set_screw_quantity')} × #{read.call('set_screw_specification')}",
        "Placa base: #{read.call('has_base_plate') ? 'Sí' : 'No'}",
        "Color/acabado: #{read.call('color')}"
      ]
      begin
        rows = JSON.parse(read.call('cost_breakdown_json').to_s)
        message << ''
        message << 'DESGLOSE DE INVERSIÓN'
        rows.each do |row|
          message << format(
            '%s: %.4g %s × $%.2f = $%.2f',
            row['item'], row['quantity'].to_f, row['unit'],
            row['unit_cost'].to_f, row['subtotal'].to_f
          )
        end
        message << "TOTAL: $#{format('%.2f', read.call('investment_cost_mxn').to_f)} MXN"
      rescue JSON::ParserError
        message << 'No existe desglose para este conector.'
      end
      UI.messagebox(message.join("\n"))
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

    class PlacementTool
      def initialize(code, color, metadata)
        @code = code
        @color = color
        @metadata = metadata
        @input = Sketchup::InputPoint.new
      end

      def activate
        Sketchup.set_status_text("Haz clic para colocar el conector #{@code}.", SB_PROMPT)
      end

      def onMouseMove(_flags, x, y, view)
        @input.pick(view, x, y)
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @input.pick(view, x, y)
        return unless @input.valid?
        Conectores.create_connector(@code, @color, @metadata, @input.position)
        Sketchup.active_model.select_tool(nil)
      rescue StandardError => error
        location = error.backtrace && error.backtrace.first
        UI.messagebox(
          "No fue posible crear el conector:\n#{error.message}\n\n" \
          "Ubicación: #{location}"
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
      menu = UI.menu('Extensions').add_submenu('Play Idea - Conectores')
      menu.add_item('Insertar conector') { start }
      menu.add_item('Ver ficha del conector seleccionado') { show_selected_metadata }
      file_loaded(__FILE__)
    end
  end
end
