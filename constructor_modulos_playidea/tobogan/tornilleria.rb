# Tornillería que asegura cada unión de pestaña de los ductos y cada
# extremo de una solera, empacada dentro de constructor_modulos_playidea.
# Ver scripts/tornilleria_playidea.rb para el detalle de cómo se
# construyó -idéntica aquí, incluyendo los bugs ya corregidos ahí (ver
# la skill tobogan-completo-playidea)-. Namespaced bajo
# PlayIdea::ConstructorModulos::Tobogan::Tornilleria.
#
# Tornillo coche galvanizado 5/16"×1½": cabeza redondeada -"bombudita"-
# adentro del ducto, cruza la pared, y por fuera lleva rondana + tuerca
# hexagonal + una tapa -tuerca bellota- sobre el sobrante, cerrando la
# punta -las 2 tuercas van juntas, no son alternativas-.

module PlayIdea
  module ConstructorModulos
    module Tobogan
      module Tornilleria
        extend self

        DICTIONARY = 'playidea_tornilleria'.freeze
        SEGMENTS = 24

        BOLT_DIAMETER_MM = 7.94
        BOLT_SHAFT_R_MM = BOLT_DIAMETER_MM / 2.0
        BOLT_LENGTH_MM = 38.1
        HEAD_DIAMETER_MM = 19.5
        HEAD_R_MM = HEAD_DIAMETER_MM / 2.0
        HEAD_HEIGHT_MM = 6.5

        WASHER_OUTER_DIAMETER_MM = 22.225
        WASHER_OUTER_R_MM = WASHER_OUTER_DIAMETER_MM / 2.0
        WASHER_INNER_R_MM = (BOLT_DIAMETER_MM / 2.0) + 0.4
        WASHER_THICKNESS_MM = 1.6

        NUT_R_MM = 7.4
        NUT_HEIGHT_MM = 7.9
        NUT_CAP_HEIGHT_MM = 4.5
        NUT_BORE_R_MM = WASHER_INNER_R_MM

        BOLT_COLOR = Sketchup::Color.new(120, 120, 125)
        NUT_COLOR = Sketchup::Color.new(105, 105, 110)

        CODE = 'TORNILLERIA-5-16-1.5'.freeze
        BOLT_PHASE_DEG = 45.0

        def circle_points(radius, z_value)
          SEGMENTS.times.map do |index|
            angle = (2.0 * Math::PI * index) / SEGMENTS
            Geom::Point3d.new(radius * Math.cos(angle), radius * Math.sin(angle), z_value)
          end
        end

        def add_wall(entities, r0, r1, z0, z1)
          bottom = circle_points(r0, z0)
          top = circle_points(r1, z1)
          SEGMENTS.times do |index|
            following = (index + 1) % SEGMENTS
            entities.add_face(bottom[index], bottom[following], top[following], top[index])
          end
        end

        def add_ring(entities, inner_r, outer_r, z_value)
          outer = circle_points(outer_r, z_value)
          if inner_r <= 0.mm
            center = Geom::Point3d.new(0, 0, z_value)
            SEGMENTS.times do |index|
              following = (index + 1) % SEGMENTS
              entities.add_face(center, outer[index], outer[following])
            end
            return
          end

          inner = circle_points(inner_r, z_value)
          SEGMENTS.times do |index|
            following = (index + 1) % SEGMENTS
            entities.add_face(outer[index], outer[following], inner[following], inner[index])
          end
        end

        def add_dome(entities, base_r, height, z0, steps: 6)
          profile = (0..steps).map do |i|
            t = i.to_f / steps
            angle = t * (Math::PI / 2.0)
            [base_r * Math.sin(angle), z0 + (height * (1.0 - Math.cos(angle)))]
          end
          apex = Geom::Point3d.new(0, 0, z0)
          top = circle_points(profile[1][0], profile[1][1])
          SEGMENTS.times do |index|
            following = (index + 1) % SEGMENTS
            entities.add_face(apex, top[index], top[following])
          end
          (1...steps).each do |i|
            r0, z0i = profile[i]
            r1, z1i = profile[i + 1]
            add_wall(entities, r0, r1, z0i, z1i)
          end
        end

        def soften_circular_edges(entities)
          entities.grep(Sketchup::Edge).each do |edge|
            vector = edge.end.position - edge.start.position
            next if vector.parallel?(Z_AXIS)

            edge.soft = true
            edge.smooth = true
          end
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

        def material_for(model, name, color)
          material = model.materials[name] || model.materials.add(name)
          material.color = color
          material
        end

        def set_costing(definition, rows)
          definition.set_attribute(DICTIONARY, 'type', 'tornilleria_set')
          definition.set_attribute(DICTIONARY, 'costing_rows', rows.to_json)
        end

        def bolt_definition(model, wall_thickness_mm)
          @definitions_cache ||= {}
          key = wall_thickness_mm.round(3)
          cached = @definitions_cache[key]
          return cached if cached && model.definitions[cached.name] == cached

          model.start_operation('Crear pieza de tornillería', true)
          definition = build_bolt_definition(model, wall_thickness_mm)
          model.commit_operation
          @definitions_cache[key] = definition
          definition
        rescue StandardError
          model.abort_operation
          raise
        end

        def build_bolt_definition(model, wall_thickness_mm)
          definition = model.definitions.add(unique_name(model, CODE))
          entities = definition.entities

          head_tip_z = 0.mm
          head_base_z = HEAD_HEIGHT_MM.mm
          shaft_end_z = head_base_z + BOLT_LENGTH_MM.mm
          washer_start_z = head_base_z + wall_thickness_mm.mm
          washer_end_z = washer_start_z + WASHER_THICKNESS_MM.mm
          hex_start_z = washer_end_z
          hex_end_z = hex_start_z + NUT_HEIGHT_MM.mm

          cap_start_z = hex_end_z
          cap_available_mm = [(shaft_end_z - cap_start_z).to_mm, 1.0].max
          cap_dome_mm = [NUT_CAP_HEIGHT_MM, cap_available_mm].min
          cap_skirt_mm = cap_available_mm - cap_dome_mm
          cap_skirt_end_z = cap_start_z + cap_skirt_mm.mm

          add_dome(entities, HEAD_R_MM.mm, HEAD_HEIGHT_MM.mm, head_tip_z, steps: 6)
          add_ring(entities, BOLT_SHAFT_R_MM.mm, HEAD_R_MM.mm, head_base_z)
          add_wall(entities, BOLT_SHAFT_R_MM.mm, BOLT_SHAFT_R_MM.mm, head_base_z, hex_start_z)

          add_wall(entities, WASHER_INNER_R_MM.mm, WASHER_INNER_R_MM.mm, washer_start_z, washer_end_z)
          add_wall(entities, WASHER_OUTER_R_MM.mm, WASHER_OUTER_R_MM.mm, washer_start_z, washer_end_z)
          add_ring(entities, WASHER_INNER_R_MM.mm, WASHER_OUTER_R_MM.mm, washer_start_z)
          add_ring(entities, WASHER_INNER_R_MM.mm, WASHER_OUTER_R_MM.mm, washer_end_z)

          add_wall(entities, NUT_R_MM.mm, NUT_R_MM.mm, hex_start_z, hex_end_z)
          add_wall(entities, NUT_BORE_R_MM.mm, NUT_BORE_R_MM.mm, hex_start_z, hex_end_z)
          add_ring(entities, NUT_BORE_R_MM.mm, NUT_R_MM.mm, hex_start_z)
          add_ring(entities, NUT_BORE_R_MM.mm, NUT_R_MM.mm, hex_end_z)

          add_wall(entities, NUT_R_MM.mm, NUT_R_MM.mm, cap_start_z, cap_skirt_end_z)
          add_wall(entities, NUT_BORE_R_MM.mm, NUT_BORE_R_MM.mm, cap_start_z, cap_skirt_end_z)
          add_ring(entities, NUT_BORE_R_MM.mm, NUT_R_MM.mm, cap_start_z)
          add_dome(entities, NUT_R_MM.mm, cap_dome_mm.mm, cap_skirt_end_z, steps: 5)

          soften_circular_edges(entities)

          bolt_material = material_for(model, 'PlayIdea Tornillo Galvanizado', BOLT_COLOR)
          nut_material = material_for(model, 'PlayIdea Tuerca/Rondana Galvanizada', NUT_COLOR)
          entities.grep(Sketchup::Face).each do |face|
            inside_nut_zone = face.vertices.all? { |v| v.position.z >= washer_start_z - 0.1.mm }
            material = inside_nut_zone ? nut_material : bolt_material
            face.material = material
            face.back_material = material
          end

          # Factura consolidada -corrección del usuario, reemplaza la
          # factura vieja del tornillo (FFM-11729, proveedor distinto)-:
          # los 4 renglones -tornillo, rondana, tuerca hexagonal, tuerca
          # bellota- vienen de la MISMA factura TB5668, mismo proveedor,
          # mismo UUID.
          rows = [
            { item: 'Tornillo cabeza de coche galvanizado 5/16"-18 NC', unit_cost_mxn: 1.4575, unit_cost_iva_mxn: 1.69,
              provider: 'Tornillos y Birlos de México', rfc: 'TBM901216PE2', invoice: 'TB5668', date: '2024-11-29',
              uuid: '4FF42A36-C115-44E1-8FF2-92FDE413EFE5' },
            { item: 'Rondana plana galvanizada 5/16"x7/8"', unit_cost_mxn: 0.862069, unit_cost_iva_mxn: 1.00,
              provider: 'Tornillos y Birlos de México', rfc: 'TBM901216PE2', invoice: 'TB5668', date: '2024-11-29',
              uuid: '4FF42A36-C115-44E1-8FF2-92FDE413EFE5' },
            { item: 'Tuerca hexagonal ligera galvanizada 5/16"-18 NC', unit_cost_mxn: 0.5025, unit_cost_iva_mxn: 0.58,
              provider: 'Tornillos y Birlos de México', rfc: 'TBM901216PE2', invoice: 'TB5668', date: '2024-11-29',
              uuid: '4FF42A36-C115-44E1-8FF2-92FDE413EFE5' },
            { item: 'Tuerca bellota niquelada 5/16"-18 NC -tapa-', unit_cost_mxn: 1.7875, unit_cost_iva_mxn: 2.07,
              provider: 'Tornillos y Birlos de México', rfc: 'TBM901216PE2', invoice: 'TB5668', date: '2024-11-29',
              uuid: '4FF42A36-C115-44E1-8FF2-92FDE413EFE5' }
          ]
          set_costing(definition, rows)
          definition
        end

        def build_bolt_set(_params, bore_surface_point, outward_direction, wall_thickness_mm)
          model = Sketchup.active_model
          definition = bolt_definition(model, wall_thickness_mm)

          model.start_operation('Colocar tornillo', true)
          z_axis = outward_direction.normalize
          helper = z_axis.parallel?(Z_AXIS) ? X_AXIS : Z_AXIS
          x_axis = helper.cross(z_axis).normalize
          y_axis = z_axis.cross(x_axis).normalize
          tip_point = bore_surface_point.offset(z_axis.reverse, HEAD_HEIGHT_MM.mm)
          transform = Geom::Transformation.axes(tip_point, x_axis, y_axis, z_axis)
          instance = model.active_entities.add_instance(definition, transform)
          # CODE, no un nombre genérico -bug real: con 'TORNILLO' a secas
          # el cotizador -que lee `entity.name` antes que el nombre de la
          # definición- no podía reconocer estas instancias por patrón-.
          instance.name = CODE

          model.commit_operation
          instance
        rescue StandardError
          model.abort_operation
          raise
        end

        def build_flange_bolts(instances, joint_center, axis_direction, inner_r_mm, wall_thickness_mm, up_hint: Z_AXIS, count: 4)
          axis = axis_direction.normalize
          reference = axis.parallel?(up_hint) ? X_AXIS : up_hint
          radial_a = axis.cross(reference).normalize
          radial_b = axis.cross(radial_a).normalize
          phase = BOLT_PHASE_DEG * Math::PI / 180.0

          count.times do |i|
            angle = phase + ((2.0 * Math::PI * i) / count)
            radial_dir = Geom::Vector3d.new(
              (radial_a.x * Math.cos(angle)) + (radial_b.x * Math.sin(angle)),
              (radial_a.y * Math.cos(angle)) + (radial_b.y * Math.sin(angle)),
              (radial_a.z * Math.cos(angle)) + (radial_b.z * Math.sin(angle))
            ).normalize
            bore_point = joint_center.offset(radial_dir, inner_r_mm.mm)
            bolt = build_bolt_set({}, bore_point, radial_dir, wall_thickness_mm)
            instances << bolt
          end
        end
      end
    end
  end
end
