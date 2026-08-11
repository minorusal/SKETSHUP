# Tramo recto de tobogán, empacado dentro de constructor_modulos_playidea.
# Ver scripts/tobogan_recto_playidea.rb para el detalle de cómo se
# construyó esta geometría -idéntica aquí-. Namespaced bajo
# PlayIdea::ConstructorModulos::Tobogan::Recto.

module PlayIdea
  module ConstructorModulos
    module Tobogan
      module Recto
        extend self

        DICTIONARY = 'playidea_tobogan'.freeze
        SEGMENTS = 48

        INSIDE_DIAMETER_MM = 800.0
        WALL_THICKNESS_MM = 8.0
        TOTAL_LENGTH_MM = 1100.0
        CEJA_LENGTH_MM = 100.0
        BODY_LENGTH_MM = TOTAL_LENGTH_MM - CEJA_LENGTH_MM

        BODY_INSIDE_R_MM = INSIDE_DIAMETER_MM / 2.0
        BODY_OUTSIDE_R_MM = BODY_INSIDE_R_MM + WALL_THICKNESS_MM
        CEJA_CLEARANCE_MM = 0.0
        CEJA_INSIDE_R_MM = BODY_OUTSIDE_R_MM + CEJA_CLEARANCE_MM
        CEJA_OUTSIDE_R_MM = CEJA_INSIDE_R_MM + WALL_THICKNESS_MM

        DEFAULT_COLOR_HEX = 'E1E1E8'.freeze # gris -sin color elegido-
        CODE = "TOBOGAN-RECTO-#{(TOTAL_LENGTH_MM / 10.0).round}".freeze

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
          inner = circle_points(inner_r, z_value)
          outer = circle_points(outer_r, z_value)
          SEGMENTS.times do |index|
            following = (index + 1) % SEGMENTS
            entities.add_face(outer[index], outer[following], inner[following], inner[index])
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

        def build_piece(params, start_point, direction)
          model = Sketchup.active_model
          model.start_operation('Crear tramo recto de tobogán', true)

          definition = model.definitions.add(unique_name(model, CODE))
          entities = definition.entities

          z0 = 0.mm
          z_step = BODY_LENGTH_MM.mm
          z1 = TOTAL_LENGTH_MM.mm
          body_inside = BODY_INSIDE_R_MM.mm
          body_outside = BODY_OUTSIDE_R_MM.mm
          ceja_inside = CEJA_INSIDE_R_MM.mm
          ceja_outside = CEJA_OUTSIDE_R_MM.mm

          add_wall(entities, body_inside, z0, z_step)
          add_wall(entities, body_outside, z0, z_step)
          add_ring(entities, body_inside, body_outside, z0)
          add_ring(entities, body_outside, ceja_outside, z_step)
          add_ring(entities, body_inside, ceja_inside, z_step)
          add_wall(entities, ceja_inside, z_step, z1)
          add_wall(entities, ceja_outside, z_step, z1)
          add_ring(entities, ceja_inside, ceja_outside, z1)

          soften_circular_edges(entities)

          material = tobogan_material(model, params[:color_hex])
          entities.grep(Sketchup::Face).each do |f|
            f.material = material
            f.back_material = material
          end

          definition.set_attribute(DICTIONARY, 'type', 'tobogan_recto')
          definition.set_attribute(DICTIONARY, 'inside_diameter_mm', INSIDE_DIAMETER_MM)
          definition.set_attribute(DICTIONARY, 'wall_thickness_mm', WALL_THICKNESS_MM)
          definition.set_attribute(DICTIONARY, 'total_length_mm', TOTAL_LENGTH_MM)
          definition.set_attribute(DICTIONARY, 'ceja_length_mm', CEJA_LENGTH_MM)

          z_axis = direction.normalize
          helper = z_axis.parallel?(Z_AXIS) ? X_AXIS : Z_AXIS
          x_axis = helper.cross(z_axis).normalize
          y_axis = z_axis.cross(x_axis).normalize
          transform = Geom::Transformation.axes(start_point, x_axis, y_axis, z_axis)
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
