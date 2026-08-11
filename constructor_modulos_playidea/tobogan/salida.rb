# Pieza de salida de tobogán, empacada dentro de constructor_modulos_
# playidea. Ver scripts/salida_tobogan_playidea.rb para el detalle de
# cómo se construyó esta geometría -idéntica aquí-. Namespaced bajo
# PlayIdea::ConstructorModulos::Tobogan::Salida.

module PlayIdea
  module ConstructorModulos
    module Tobogan
      module Salida
        extend self

        DICTIONARY = 'playidea_tobogan'.freeze
        SEGMENTS = 48
        HALF_SEGMENTS = SEGMENTS / 2

        INSIDE_DIAMETER_MM = 800.0
        WALL_THICKNESS_MM = 8.0
        CEJA_LENGTH_MM = 100.0
        STRAIGHT_ROUND_LENGTH_MM = 100.0
        HALF_TUBE_LENGTH_MM = 300.0
        LIP_FOLD_WIDTH_MM = 15.0

        BODY_INSIDE_R_MM = INSIDE_DIAMETER_MM / 2.0
        BODY_OUTSIDE_R_MM = BODY_INSIDE_R_MM + WALL_THICKNESS_MM

        DEFAULT_COLOR_HEX = 'E1E1E8'.freeze # gris -sin color elegido-
        CODE = 'TOBOGAN-SALIDA'.freeze

        def full_ring_points(radius, x_value)
          SEGMENTS.times.map do |seg|
            phi = (2.0 * Math::PI * seg) / SEGMENTS
            Geom::Point3d.new(x_value, radius * Math.cos(phi), radius * Math.sin(phi))
          end
        end

        def bottom_half_ring_points(radius, x_value)
          (0..HALF_SEGMENTS).map do |k|
            phi = Math::PI + (Math::PI * k / HALF_SEGMENTS)
            Geom::Point3d.new(x_value, radius * Math.cos(phi), radius * Math.sin(phi))
          end
        end

        def top_half_ring_points(radius, x_value)
          (0..HALF_SEGMENTS).map do |k|
            phi = Math::PI * k / HALF_SEGMENTS
            Geom::Point3d.new(x_value, radius * Math.cos(phi), radius * Math.sin(phi))
          end
        end

        def add_wall_between_rings(entities, ring_a, ring_b)
          SEGMENTS.times do |index|
            following = (index + 1) % SEGMENTS
            entities.add_face(ring_a[index], ring_a[following], ring_b[following])
            entities.add_face(ring_a[index], ring_b[following], ring_b[index])
          end
        end

        def add_ring_face(entities, inner_ring, outer_ring)
          SEGMENTS.times do |index|
            following = (index + 1) % SEGMENTS
            entities.add_face(outer_ring[index], outer_ring[following], inner_ring[following])
            entities.add_face(outer_ring[index], inner_ring[following], inner_ring[index])
          end
        end

        def add_open_wall_between_rings(entities, ring_a, ring_b)
          (ring_a.length - 1).times do |index|
            entities.add_face(ring_a[index], ring_a[index + 1], ring_b[index + 1])
            entities.add_face(ring_a[index], ring_b[index + 1], ring_b[index])
          end
        end

        def add_open_ring_face(entities, inner_ring, outer_ring)
          (inner_ring.length - 1).times do |index|
            entities.add_face(outer_ring[index], outer_ring[index + 1], inner_ring[index + 1])
            entities.add_face(outer_ring[index], inner_ring[index + 1], inner_ring[index])
          end
        end

        def add_edge_cap(entities, inner_a, outer_a, inner_b, outer_b)
          entities.add_face(inner_a, outer_a, outer_b)
          entities.add_face(inner_a, outer_b, inner_b)
        end

        def lip_collar(point, tangent, fold_width)
          outward = Geom::Vector3d.new(0, point.y, point.z)
          outward = Geom::Vector3d.new(0, 1, 0) if outward.length < 0.001.mm
          outward = outward.normalize
          side = outward.cross(tangent).normalize
          p0 = point
          p1 = p0 + Geom::Vector3d.new(outward.x * fold_width, outward.y * fold_width, outward.z * fold_width)
          p2 = p1 + Geom::Vector3d.new(side.x * fold_width, side.y * fold_width, side.z * fold_width)
          p3 = p2 - Geom::Vector3d.new(outward.x * fold_width, outward.y * fold_width, outward.z * fold_width)
          [p0, p1, p2, p3]
        end

        def add_rolled_lip(entities, path_points, fold_width)
          collars = path_points.each_with_index.map do |point, i|
            prev_pt = i.zero? ? point : path_points[i - 1]
            next_pt = i == path_points.length - 1 ? point : path_points[i + 1]
            tangent = next_pt - prev_pt
            tangent = Geom::Vector3d.new(1, 0, 0) if tangent.length < 0.001.mm
            lip_collar(point, tangent.normalize, fold_width)
          end
          (collars.length - 1).times do |i|
            add_open_wall_between_rings(entities, collars[i], collars[i + 1])
          end
          cap_lip_profile(entities, collars.first)
          cap_lip_profile(entities, collars.last)
        end

        def cap_lip_profile(entities, profile)
          entities.add_face(profile[0], profile[1], profile[2])
          entities.add_face(profile[0], profile[2], profile[3])
        end

        def soften_circular_edges(entities)
          entities.grep(Sketchup::Edge).each do |edge|
            edge.soft = true
            edge.smooth = true
          end
        end

        def build_piece(params, start_point, direction, up_hint = Z_AXIS)
          model = Sketchup.active_model
          model.start_operation('Crear salida de tobogán', true)

          definition = model.definitions.add(unique_name(model, CODE))
          entities = definition.entities

          x0 = 0.0.mm
          x_step = CEJA_LENGTH_MM.mm
          x_round_end = x_step + STRAIGHT_ROUND_LENGTH_MM.mm
          x_cut = x_round_end + HALF_TUBE_LENGTH_MM.mm

          body_inner_start = full_ring_points(BODY_INSIDE_R_MM.mm, x0)
          body_outer_start = full_ring_points(BODY_OUTSIDE_R_MM.mm, x0)
          add_ring_face(entities, body_inner_start, body_outer_start)

          body_inner_end = full_ring_points(BODY_INSIDE_R_MM.mm, x_round_end)
          body_outer_end = full_ring_points(BODY_OUTSIDE_R_MM.mm, x_round_end)
          add_wall_between_rings(entities, body_inner_start, body_inner_end)
          add_wall_between_rings(entities, body_outer_start, body_outer_end)

          top_inner_cap = top_half_ring_points(BODY_INSIDE_R_MM.mm, x_round_end)
          top_outer_cap = top_half_ring_points(BODY_OUTSIDE_R_MM.mm, x_round_end)
          add_open_ring_face(entities, top_inner_cap, top_outer_cap)

          half_inner_start = bottom_half_ring_points(BODY_INSIDE_R_MM.mm, x_round_end)
          half_outer_start = bottom_half_ring_points(BODY_OUTSIDE_R_MM.mm, x_round_end)
          half_inner_end = bottom_half_ring_points(BODY_INSIDE_R_MM.mm, x_cut)
          half_outer_end = bottom_half_ring_points(BODY_OUTSIDE_R_MM.mm, x_cut)
          add_open_wall_between_rings(entities, half_inner_start, half_inner_end)
          add_open_wall_between_rings(entities, half_outer_start, half_outer_end)

          add_edge_cap(entities, half_inner_start.first, half_outer_start.first, half_inner_end.first, half_outer_end.first)
          add_edge_cap(entities, half_inner_start.last, half_outer_start.last, half_inner_end.last, half_outer_end.last)

          soften_circular_edges(entities)

          lip_path = [half_outer_start.first] + half_outer_end + [half_outer_start.last]
          add_rolled_lip(entities, lip_path, LIP_FOLD_WIDTH_MM.mm)

          material = tobogan_material(model, params[:color_hex])
          entities.grep(Sketchup::Face).each do |f|
            f.material = material
            f.back_material = material
          end

          definition.set_attribute(DICTIONARY, 'type', 'tobogan_salida')
          definition.set_attribute(DICTIONARY, 'inside_diameter_mm', INSIDE_DIAMETER_MM)
          definition.set_attribute(DICTIONARY, 'wall_thickness_mm', WALL_THICKNESS_MM)
          definition.set_attribute(DICTIONARY, 'half_tube_length_mm', HALF_TUBE_LENGTH_MM)
          definition.set_attribute(DICTIONARY, 'ceja_length_mm', CEJA_LENGTH_MM)
          definition.set_attribute(DICTIONARY, 'lip_fold_width_mm', LIP_FOLD_WIDTH_MM)

          local_x = direction.normalize
          reference = local_x.parallel?(up_hint) ? Y_AXIS : up_hint
          local_y = local_x.cross(reference).normalize
          local_z = local_x.cross(local_y).normalize
          transform = Geom::Transformation.axes(start_point, local_x, local_y, local_z)
          instance = model.active_entities.add_instance(definition, transform)
          instance.name = CODE

          model.selection.clear
          model.selection.add(instance)
          model.commit_operation
          instance
        rescue StandardError
          model.abort_operation
          raise
        end

        def tobogan_material(model, color_hex)
          name = 'PlayIdea Tobogán Fibra de Vidrio'
          hex = color_hex || DEFAULT_COLOR_HEX
          name = "#{name} ##{hex}"
          material = model.materials[name] || model.materials.add(name)
          material.color = Sketchup::Color.new(hex[0..1].to_i(16), hex[2..3].to_i(16), hex[4..5].to_i(16))
          material
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
      end
    end
  end
end
