# Codo de 90° de tobogán de fibra de vidrio, empacado dentro de
# constructor_modulos_playidea para que el constructor pueda agregar un
# tobogán sin depender de los scripts sueltos de scripts/ (esos siguen
# existiendo para pruebas rápidas con `load`, pero un plugin instalado
# normalmente no puede depender de que alguien los haya cargado a mano
# en la Consola de Ruby). Geometría idéntica a scripts/codo_90_playidea.rb
# -ver ese archivo para el detalle de cómo se construyó-, namespaced
# bajo PlayIdea::ConstructorModulos::Tobogan::Codo90 para no chocar con
# el módulo global PlayIdeaCodo90Script que usan los scripts sueltos.

module PlayIdea
  module ConstructorModulos
    module Tobogan
      module Codo90
        extend self

        DICTIONARY = 'playidea_tobogan'.freeze
        SEGMENTS = 48
        ANGLE_STEPS = 24

        INSIDE_DIAMETER_MM = 800.0
        WALL_THICKNESS_MM = 8.0
        CEJA_LENGTH_MM = 100.0
        SWEEP_ANGLE_DEG = 90.0
        SWEEP_ANGLE_RAD = SWEEP_ANGLE_DEG * Math::PI / 180.0

        BODY_INSIDE_R_MM = INSIDE_DIAMETER_MM / 2.0
        BODY_OUTSIDE_R_MM = BODY_INSIDE_R_MM + WALL_THICKNESS_MM
        CEJA_CLEARANCE_MM = 0.0
        CEJA_INSIDE_R_MM = BODY_OUTSIDE_R_MM + CEJA_CLEARANCE_MM
        CEJA_OUTSIDE_R_MM = CEJA_INSIDE_R_MM + WALL_THICKNESS_MM

        BEND_RADIUS_MM = 550.0

        DEFAULT_COLOR_HEX = 'E1E1E8'.freeze # gris -sin color elegido-
        CODE = 'TOBOGAN-CODO-90'.freeze

        def ring_point(theta, radius, phi)
          center_x = BEND_RADIUS_MM.mm * Math.sin(theta)
          center_y = BEND_RADIUS_MM.mm - (BEND_RADIUS_MM.mm * Math.cos(theta))
          radial_x = Math.sin(theta)
          radial_y = -Math.cos(theta)
          r = radius * Math.cos(phi)
          x = center_x + (r * radial_x)
          y = center_y + (r * radial_y)
          z = radius * Math.sin(phi)
          Geom::Point3d.new(x, y, z)
        end

        def ring_points(theta, radius)
          SEGMENTS.times.map { |seg| ring_point(theta, radius, (2.0 * Math::PI * seg) / SEGMENTS) }
        end

        def exit_frame
          theta = SWEEP_ANGLE_RAD
          origin = Geom::Point3d.new(
            BEND_RADIUS_MM.mm * Math.sin(theta),
            BEND_RADIUS_MM.mm - (BEND_RADIUS_MM.mm * Math.cos(theta)),
            0
          )
          forward = Geom::Vector3d.new(Math.cos(theta), Math.sin(theta), 0)
          radial = Geom::Vector3d.new(Math.sin(theta), -Math.cos(theta), 0)
          [origin, forward, radial]
        end

        def straight_ring_points(origin, forward, radial, up, offset_mm, radius)
          SEGMENTS.times.map do |seg|
            phi = (2.0 * Math::PI * seg) / SEGMENTS
            base = origin + Geom::Vector3d.new(forward.x * offset_mm, forward.y * offset_mm, forward.z * offset_mm)
            u = radius * Math.cos(phi)
            v = radius * Math.sin(phi)
            base + Geom::Vector3d.new(radial.x * u + up.x * v, radial.y * u + up.y * v, radial.z * u + up.z * v)
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

        def soften_circular_edges(entities)
          entities.grep(Sketchup::Edge).each do |edge|
            edge.soft = true
            edge.smooth = true
          end
        end

        def build_piece(params, start_point, direction, up_hint = Z_AXIS)
          model = Sketchup.active_model
          model.start_operation('Crear codo de 90° de tobogán', true)

          definition = model.definitions.add(unique_name(model, CODE))
          entities = definition.entities

          inner_rings = (0..ANGLE_STEPS).map { |i| ring_points(SWEEP_ANGLE_RAD * (i.to_f / ANGLE_STEPS), BODY_INSIDE_R_MM.mm) }
          outer_rings = (0..ANGLE_STEPS).map { |i| ring_points(SWEEP_ANGLE_RAD * (i.to_f / ANGLE_STEPS), BODY_OUTSIDE_R_MM.mm) }
          ANGLE_STEPS.times do |i|
            add_wall_between_rings(entities, inner_rings[i], inner_rings[i + 1])
            add_wall_between_rings(entities, outer_rings[i], outer_rings[i + 1])
          end
          add_ring_face(entities, inner_rings.first, outer_rings.first)

          exit_origin, forward, radial = exit_frame
          up = Z_AXIS
          ceja_z0_inner = straight_ring_points(exit_origin, forward, radial, up, 0, CEJA_INSIDE_R_MM.mm)
          ceja_z0_outer = straight_ring_points(exit_origin, forward, radial, up, 0, CEJA_OUTSIDE_R_MM.mm)
          ceja_z1_inner = straight_ring_points(exit_origin, forward, radial, up, CEJA_LENGTH_MM.mm, CEJA_INSIDE_R_MM.mm)
          ceja_z1_outer = straight_ring_points(exit_origin, forward, radial, up, CEJA_LENGTH_MM.mm, CEJA_OUTSIDE_R_MM.mm)

          add_ring_face(entities, inner_rings.last, ceja_z0_inner)
          add_ring_face(entities, outer_rings.last, ceja_z0_outer)
          add_wall_between_rings(entities, ceja_z0_inner, ceja_z1_inner)
          add_wall_between_rings(entities, ceja_z0_outer, ceja_z1_outer)
          add_ring_face(entities, ceja_z1_inner, ceja_z1_outer)

          soften_circular_edges(entities)

          material = tobogan_material(model, params[:color_hex])
          entities.grep(Sketchup::Face).each do |f|
            f.material = material
            f.back_material = material
          end

          definition.set_attribute(DICTIONARY, 'type', 'tobogan_codo_90')
          definition.set_attribute(DICTIONARY, 'inside_diameter_mm', INSIDE_DIAMETER_MM)
          definition.set_attribute(DICTIONARY, 'wall_thickness_mm', WALL_THICKNESS_MM)
          definition.set_attribute(DICTIONARY, 'bend_radius_mm', BEND_RADIUS_MM)
          definition.set_attribute(DICTIONARY, 'ceja_length_mm', CEJA_LENGTH_MM)

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
