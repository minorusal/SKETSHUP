# Soporte de solera curva -abraza el ducto por abajo-, empacado dentro
# de constructor_modulos_playidea. Ver scripts/soporte_solera_playidea.rb
# para el detalle de cómo se construyó -idéntica aquí-. Namespaced bajo
# PlayIdea::ConstructorModulos::Tobogan::Solera.

module PlayIdea
  module ConstructorModulos
    module Tobogan
      module Solera
        extend self

        DICTIONARY = 'playidea_tobogan'.freeze
        SEGMENTS = 24

        SUPPORT_WIDTH_MM = 50.8
        SUPPORT_THICKNESS_MM = 6.0
        TUBE_OUTER_RADIUS_MM = 408.0
        ARC_START_DEG = 180.0
        ARC_END_DEG = 360.0

        COLOR = Sketchup::Color.new(90, 90, 95)
        CODE = 'TOBOGAN-SOPORTE-SOLERA'.freeze

        def arc_ring_points(radius, x_value)
          start_rad = ARC_START_DEG * Math::PI / 180.0
          end_rad = ARC_END_DEG * Math::PI / 180.0
          (0..SEGMENTS).map do |k|
            phi = start_rad + ((end_rad - start_rad) * k / SEGMENTS)
            Geom::Point3d.new(x_value, radius * Math.cos(phi), radius * Math.sin(phi))
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

        def add_arc_end_cap(entities, inner_a, outer_a, inner_b, outer_b)
          entities.add_face(inner_a, outer_a, outer_b)
          entities.add_face(inner_a, outer_b, inner_b)
        end

        def soften_edges(entities)
          entities.grep(Sketchup::Edge).each do |edge|
            edge.soft = true
            edge.smooth = true
          end
        end

        def build_piece(_params, start_point, direction, up_hint = Z_AXIS, width_mm = SUPPORT_WIDTH_MM)
          model = Sketchup.active_model
          model.start_operation('Crear soporte de solera', true)

          definition = model.definitions.add(unique_name(model, CODE))
          entities = definition.entities

          x0 = -(width_mm.mm) / 2.0
          x1 = (width_mm.mm) / 2.0
          inner_r = TUBE_OUTER_RADIUS_MM.mm
          outer_r = inner_r + SUPPORT_THICKNESS_MM.mm

          inner_front = arc_ring_points(inner_r, x0)
          inner_back = arc_ring_points(inner_r, x1)
          outer_front = arc_ring_points(outer_r, x0)
          outer_back = arc_ring_points(outer_r, x1)

          add_open_wall_between_rings(entities, outer_front, outer_back)
          add_open_wall_between_rings(entities, inner_back, inner_front)
          add_open_ring_face(entities, inner_front, outer_front)
          add_open_ring_face(entities, inner_back, outer_back)
          add_arc_end_cap(entities, inner_front.first, outer_front.first, inner_back.first, outer_back.first)
          add_arc_end_cap(entities, inner_front.last, outer_front.last, inner_back.last, outer_back.last)

          soften_edges(entities)

          material = soporte_material(model)
          entities.grep(Sketchup::Face).each do |f|
            f.material = material
            f.back_material = material
          end

          definition.set_attribute(DICTIONARY, 'type', 'tobogan_soporte_solera')
          definition.set_attribute(DICTIONARY, 'width_mm', width_mm)
          definition.set_attribute(DICTIONARY, 'thickness_mm', SUPPORT_THICKNESS_MM)
          definition.set_attribute(DICTIONARY, 'tube_outer_radius_mm', TUBE_OUTER_RADIUS_MM)

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

        def soporte_material(model)
          name = 'PlayIdea Soporte Solera'
          material = model.materials[name] || model.materials.add(name)
          material.color = COLOR
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
