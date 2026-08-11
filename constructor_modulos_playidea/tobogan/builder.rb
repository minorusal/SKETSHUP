# Tobogán paramétrico -por altura- unido a una estructura de módulos ya
# construida por el propio constructor_modulos_playidea. Ported de
# scripts/tobogan_con_estructura_playidea.rb -ya validado en pruebas
# sueltas antes de este port, ver la skill tobogan-completo-playidea
# para el detalle de cada decisión de diseño-. Aquí solo vive la parte
# de ATTACH -todo lo que pasaba DESPUÉS de create_module en el script
# original-: la cuadrícula/torre ya las construye el flujo normal del
# diálogo automático antes de llamar a `attach`.
#
# Namespaced bajo PlayIdea::ConstructorModulos::Tobogan::Builder,
# reusando las piezas hermanas Codo90/Recto/Salida/Solera/AroEntrada/
# Tornilleria de este mismo directorio.

module PlayIdea
  module ConstructorModulos
    module Tobogan
      module Builder
        extend self

        MIN_STEADY_ELBOW_COUNT = 6
        MAX_STEADY_ELBOW_COUNT = 20
        MAX_REASONABLE_PITCH_DEG = 22.0
        TRANSITION_SWEEP_RAD = Math::PI / 2.0

        CENTRAL_TUBE_OUTSIDE_MM = 38.1
        CENTRAL_TUBE_WALL_MM = 1.50
        CENTRAL_TUBE_INSIDE_MM = CENTRAL_TUBE_OUTSIDE_MM - (2.0 * CENTRAL_TUBE_WALL_MM)
        CENTRAL_TUBE_COLOR = 'Negro'.freeze
        CON61_BELOW_EXIT_MM = 300.0
        CONNECTOR_SOCKET_CLEARANCE_MM = 25.0

        SOLERA_OUTER_RADIUS_MM = 408.0
        SOLERA_LEG_LENGTH_MM = 100.0
        SOLERA_LEG_RAISE_MM = 25.0
        SOLERA_BOLT_ARC_INSET_MM = 50.0

        EXIT_ARM_TIP_EXTRA_MM = 150.0
        TIP_POST_EXTRA_MM = 40.0

        # Pedido del usuario: el tubo del soporte que carga el tramo recto
        # -desde el riel real de la estructura hasta el recto- debe medir
        # SIEMPRE esto, sin importar la altura pedida. Ver `attach`.
        RECTO_SUPPORT_LEG_MM = 200.0

        # Pedido del usuario: entre más alto el tobogán, más ligas poste↔
        # estructura -antes siempre 2, fijo-. Esto es cada cuánto -en mm
        # de poste- se agrega una liga extra. Ver `attach`.
        LINK_SPACING_MM = 1800.0

        def dir_at(phi, pitch)
          Geom::Vector3d.new(
            Math.cos(pitch) * Math.cos(phi),
            Math.cos(pitch) * Math.sin(phi),
            -Math.sin(pitch)
          )
        end

        # --- Bisección de inclinación por altura -------------------------------
        def total_drop_mm_for_pitch(pitch_deg, elbow_count, bend_radius_mm, ceja_mm)
          pitch = pitch_deg * Math::PI / 180.0
          dx_local = bend_radius_mm * Math.sin(TRANSITION_SWEEP_RAD)
          dy_local = bend_radius_mm * (1.0 - Math.cos(TRANSITION_SWEEP_RAD))
          z = 0.0
          elbow_count.times do |i|
            is_entry = i.zero?
            is_exit = (i == elbow_count - 1)
            entry_pitch = is_entry ? 0.0 : pitch
            exit_pitch = is_exit ? 0.0 : pitch
            dz = -Math.sin(entry_pitch)
            edz = -Math.sin(exit_pitch)
            z += (dz * dx_local) + (edz * dy_local)
            z += edz * ceja_mm
          end
          -z
        end

        def height_mm_for_pitch(pitch_deg, elbow_count, bend_radius_mm, ceja_mm, duct_outside_r_mm)
          total_drop_mm_for_pitch(pitch_deg, elbow_count, bend_radius_mm, ceja_mm) + (2.0 * duct_outside_r_mm) + CON61_BELOW_EXIT_MM
        end

        def pitch_deg_for_height(target_height_mm, elbow_count, bend_radius_mm, ceja_mm, duct_outside_r_mm)
          low = 1.0
          high = 44.0
          return nil if height_mm_for_pitch(high, elbow_count, bend_radius_mm, ceja_mm, duct_outside_r_mm) < target_height_mm

          30.times do
            mid = (low + high) / 2.0
            h = height_mm_for_pitch(mid, elbow_count, bend_radius_mm, ceja_mm, duct_outside_r_mm)
            if h < target_height_mm
              low = mid
            else
              high = mid
            end
          end
          (low + high) / 2.0
        end

        # REVERTIDO -pedido del usuario, regresión real-: se había cambiado
        # a buscar el `elbow_count` con MEJOR alineamiento salida↔entrada
        # en TODO el rango -ver skill tobogan-completo-playidea, sección
        # "Alineamiento salida↔entrada"-, pero eso podía elegir un
        # `elbow_count` mucho más alto -más vueltas, pitch mucho más
        # angosto- solo para ganar unos grados de alineamiento que casi
        # nunca importaban -verificado numéricamente: para una estructura
        # de 5m, elegía elbow_count=20 -pitch=9.3°, ~5 vueltas- en vez de
        # elbow_count=10 -pitch=20°, ~2.7 vueltas-, con el desalineamiento
        # apenas mejorando de todos modos -~28° en ambos casos-. Ductos
        # tan apretados quedan "pegados" entre sí -reportado por el
        # usuario-. De vuelta al PRIMER `elbow_count` con pitch razonable,
        # sin buscar alineamiento -el comportamiento original, validado-.
        def elbow_count_and_pitch_for_height(target_height_mm, bend_radius_mm, ceja_mm, duct_outside_r_mm)
          steady = MIN_STEADY_ELBOW_COUNT
          while steady <= MAX_STEADY_ELBOW_COUNT
            elbow_count = steady + 2
            pitch_deg = pitch_deg_for_height(target_height_mm, elbow_count, bend_radius_mm, ceja_mm, duct_outside_r_mm)
            return [elbow_count, pitch_deg] if pitch_deg && pitch_deg <= MAX_REASONABLE_PITCH_DEG

            steady += 1
          end
          elbow_count = MAX_STEADY_ELBOW_COUNT + 2
          pitch_deg = pitch_deg_for_height(target_height_mm, elbow_count, bend_radius_mm, ceja_mm, duct_outside_r_mm) || 44.0
          [elbow_count, pitch_deg]
        end

        def point_at_segment_fraction(seg, fraction)
          if seg[:type] == :straight
            t_mm = seg[:length].to_mm * fraction
            [seg[:start].offset(seg[:direction], t_mm.mm), seg[:direction]]
          else
            theta = seg[:sweep] * fraction
            dx_local = seg[:radius] * Math.sin(theta)
            dy_local = seg[:radius] * (1.0 - Math.cos(theta))
            point = seg[:entry].offset(Geom::Vector3d.new(
              (seg[:direction].x * dx_local) + (seg[:exit_direction].x * dy_local),
              (seg[:direction].y * dx_local) + (seg[:exit_direction].y * dy_local),
              (seg[:direction].z * dx_local) + (seg[:exit_direction].z * dy_local)
            ))
            tangent = Geom::Vector3d.new(
              (Math.cos(theta) * seg[:direction].x) + (Math.sin(theta) * seg[:exit_direction].x),
              (Math.cos(theta) * seg[:direction].y) + (Math.sin(theta) * seg[:exit_direction].y),
              (Math.cos(theta) * seg[:direction].z) + (Math.sin(theta) * seg[:exit_direction].z)
            )
            [point, tangent]
          end
        end

        def align_arm_to_solera_base(direction_before_rotation, radial_length_mm, centroid_x_mm, centroid_y_mm, ground_z, target_point, local_z, base_point)
          best_unit = nil
          best_drop_mm = nil
          best_gap_mm = Float::INFINITY

          evaluate = lambda do |deg|
            angle = deg * Math::PI / 180.0
            rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, angle)
            unit = direction_before_rotation.transform(rotation).normalize
            along_arm = local_z.dot(unit)
            branch_raw = Geom::Vector3d.new(
              local_z.x - (unit.x * along_arm), local_z.y - (unit.y * along_arm), local_z.z - (unit.z * along_arm)
            )
            next if branch_raw.length < 0.01

            branch_dir = branch_raw.normalize
            (50..800).step(10) do |drop_mm|
              candidate_z = target_point.z - drop_mm.mm
              next if candidate_z <= ground_z

              candidate_post_axis = Geom::Point3d.new(centroid_x_mm.mm, centroid_y_mm.mm, candidate_z)
              candidate_mid_point = candidate_post_axis.offset(unit, radial_length_mm.mm)
              candidate_tip = candidate_mid_point.offset(branch_dir, (SOLERA_LEG_RAISE_MM + SOLERA_LEG_LENGTH_MM).mm)
              gap_mm = candidate_tip.distance(base_point).to_mm
              if gap_mm < best_gap_mm
                best_gap_mm = gap_mm
                best_unit = unit
                best_drop_mm = drop_mm.to_f
              end
            end
          end

          (-45..45).step(3) { |deg| evaluate.call(deg) }
          center_deg = best_unit ? (Math.atan2(
            direction_before_rotation.cross(best_unit).dot(Z_AXIS), direction_before_rotation.dot(best_unit)
          ) * 180.0 / Math::PI) : 0.0
          (center_deg - 3.0).step(center_deg + 3.0, 0.2) { |deg| evaluate.call(deg) }

          [best_unit, best_drop_mm]
        end

        def solera_local_z(target_tangent)
          local_x = target_tangent.normalize
          reference = local_x.parallel?(Z_AXIS.reverse) ? Y_AXIS : Z_AXIS.reverse
          local_y = local_x.cross(reference).normalize
          local_x.cross(local_y).normalize
        end

        def solera_bolt_wall_mm
          Codo90::WALL_THICKNESS_MM + Solera::SUPPORT_THICKNESS_MM
        end

        def build_solera_bolts(instances, anchor_point, direction, up_hint)
          local_x = direction.normalize
          reference = local_x.parallel?(up_hint) ? Y_AXIS : up_hint
          local_y = local_x.cross(reference).normalize
          local_z = local_x.cross(local_y).normalize
          duct_inside_r_mm = Codo90::BODY_INSIDE_R_MM

          arc_radius_mm = Solera::TUBE_OUTER_RADIUS_MM
          inset_rad = SOLERA_BOLT_ARC_INSET_MM / arc_radius_mm
          start_rad = (Solera::ARC_START_DEG * Math::PI / 180.0) + inset_rad
          end_rad = (Solera::ARC_END_DEG * Math::PI / 180.0) - inset_rad

          [start_rad, end_rad].each do |phi|
            radial_dir = Geom::Vector3d.new(
              (local_y.x * Math.cos(phi)) + (local_z.x * Math.sin(phi)),
              (local_y.y * Math.cos(phi)) + (local_z.y * Math.sin(phi)),
              (local_y.z * Math.cos(phi)) + (local_z.z * Math.sin(phi))
            ).normalize
            bore_point = anchor_point.offset(radial_dir, duct_inside_r_mm.mm)
            bolt = Tornilleria.build_bolt_set({}, bore_point, radial_dir, solera_bolt_wall_mm)
            instances << bolt
          end
        rescue StandardError => error
          puts "  (tornillos de solera omitidos: #{error.message})"
        end

        def build_support_arm(ctx, instances, loop_i)
          elbow_segment = ctx[:duct_segments][1 + (2 * loop_i)]
          return unless elbow_segment && elbow_segment[:type] == :elbow

          target_point, target_tangent = point_at_segment_fraction(elbow_segment, 0.5)
          original_axis_point = Geom::Point3d.new(ctx[:centroid_x_mm].mm, ctx[:centroid_y_mm].mm, target_point.z)
          direction_before_rotation = target_point - original_axis_point
          radial_length_mm = direction_before_rotation.length.to_mm
          return if radial_length_mm < 1.0

          local_z = solera_local_z(target_tangent)
          base_point = target_point.offset(local_z.reverse, SOLERA_OUTER_RADIUS_MM.mm)

          unit_direction, best_drop_mm = align_arm_to_solera_base(
            direction_before_rotation, radial_length_mm, ctx[:centroid_x_mm], ctx[:centroid_y_mm], ctx[:ground_z], target_point, local_z, base_point
          )
          return if unit_direction.nil? || best_drop_mm.nil?

          along_arm = local_z.dot(unit_direction)
          branch_raw = Geom::Vector3d.new(
            local_z.x - (unit_direction.x * along_arm),
            local_z.y - (unit_direction.y * along_arm),
            local_z.z - (unit_direction.z * along_arm)
          )
          return if branch_raw.length < 0.01

          mid_branch_direction = branch_raw.normalize

          arm_z = target_point.z - best_drop_mm.mm
          post_axis = Geom::Point3d.new(ctx[:centroid_x_mm].mm, ctx[:centroid_y_mm].mm, arm_z)
          mid_point = post_axis.offset(unit_direction, radial_length_mm.mm)

          con10 = PlayIdea::Conectores.create_connector('10', 'Galvanizado', ctx[:con10_metadata], post_axis)
          con10_target_x = Z_AXIS
          con10_target_z = unit_direction.reverse
          con10_target_y = con10_target_z.cross(con10_target_x)
          con10.transformation = Geom::Transformation.axes(post_axis, con10_target_x, con10_target_y, con10_target_z)
          instances << con10

          con10_mid = PlayIdea::Conectores.create_connector('10', 'Galvanizado', ctx[:con10_metadata], mid_point)
          con10_mid_target_x = unit_direction
          con10_mid_target_z = mid_branch_direction.reverse
          con10_mid_target_y = con10_mid_target_z.cross(con10_mid_target_x)
          con10_mid.transformation = Geom::Transformation.axes(mid_point, con10_mid_target_x, con10_mid_target_y, con10_mid_target_z)
          instances << con10_mid

          mid_leg_start = mid_point.offset(mid_branch_direction, SOLERA_LEG_RAISE_MM.mm)
          mid_leg = PlayIdea::CreadorTubos.build_tube(
            ctx[:tube_params_base].merge(length_mm: SOLERA_LEG_LENGTH_MM, code: "TUB-ESTRUCTURAL-PATA-BRAZO-AUTO-#{format('%.1f', SOLERA_LEG_LENGTH_MM)}"),
            mid_leg_start, mid_branch_direction
          )
          instances << mid_leg

          solera = Solera.build_piece({}, target_point, target_tangent, Z_AXIS.reverse, 76.2)
          instances << solera
          build_solera_bolts(instances, target_point, target_tangent, Z_AXIS.reverse)

          tube_1_growth_mm = 70.0
          tube_1_start = post_axis.offset(unit_direction, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
          tube_1_length_mm = radial_length_mm - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM) + tube_1_growth_mm
          return if tube_1_length_mm <= 0.0

          tube_1 = PlayIdea::CreadorTubos.build_tube(
            ctx[:tube_params_base].merge(length_mm: tube_1_length_mm, code: "TUB-ESTRUCTURAL-BRAZO-AUTO-#{format('%.1f', tube_1_length_mm)}"),
            tube_1_start, unit_direction
          )
          instances << tube_1

          brace_distance_mm = [radial_length_mm * 0.6, 400.0].min
          brace_arm_point = post_axis.offset(unit_direction, brace_distance_mm.mm)
          brace_post_point = Geom::Point3d.new(post_axis.x, post_axis.y, post_axis.z - brace_distance_mm.mm)
          return if brace_post_point.z <= ctx[:ground_z]

          con12_post = PlayIdea::Conectores.create_connector('12', 'Galvanizado', ctx[:con10_metadata], brace_post_point)
          con12_post_target_x = Z_AXIS.reverse
          con12_post_target_z = unit_direction.reverse
          con12_post_target_y = con12_post_target_z.cross(con12_post_target_x)
          con12_post.transformation = Geom::Transformation.axes(brace_post_point, con12_post_target_x, con12_post_target_y, con12_post_target_z)
          instances << con12_post

          con12_arm = PlayIdea::Conectores.create_connector('12', 'Galvanizado', ctx[:con10_metadata], brace_arm_point)
          con12_arm_target_x = unit_direction
          con12_arm_target_z = Z_AXIS
          con12_arm_target_y = con12_arm_target_z.cross(con12_arm_target_x)
          con12_arm.transformation = Geom::Transformation.axes(brace_arm_point, con12_arm_target_x, con12_arm_target_y, con12_arm_target_z)
          instances << con12_arm

          con12_receiver_radius_mm = PlayIdea::Conectores::OUTSIDE_MM / 2.0
          contact_post = brace_post_point.offset(con12_post_target_z.reverse, con12_receiver_radius_mm.mm)
          contact_arm = brace_arm_point.offset(con12_arm_target_z.reverse, con12_receiver_radius_mm.mm)
          brace_vector = contact_arm - contact_post
          return if brace_vector.length.to_mm <= (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM)

          brace_direction = brace_vector.normalize
          brace_start = contact_post.offset(brace_direction, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
          brace_length_mm = brace_vector.length.to_mm - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM)
          brace_tube = PlayIdea::CreadorTubos.build_tube(
            ctx[:tube_params_base].merge(length_mm: brace_length_mm, code: "TUB-ESTRUCTURAL-DIAGONAL-AUTO-#{format('%.1f', brace_length_mm)}"),
            brace_start, brace_direction
          )
          instances << brace_tube
        rescue StandardError => error
          puts "  (brazo loop_i=#{loop_i} omitido: #{error.message})"
        end

        def build_exit_ground_support(ctx, instances, loop_i)
          elbow_segment = ctx[:duct_segments][1 + (2 * loop_i)]
          return unless elbow_segment && elbow_segment[:type] == :elbow

          target_point, target_tangent = point_at_segment_fraction(elbow_segment, 0.5)
          original_axis_point = Geom::Point3d.new(ctx[:centroid_x_mm].mm, ctx[:centroid_y_mm].mm, target_point.z)
          direction_before_rotation = target_point - original_axis_point
          radial_length_mm = direction_before_rotation.length.to_mm
          return if radial_length_mm < 1.0

          local_z = solera_local_z(target_tangent)
          base_point = target_point.offset(local_z.reverse, SOLERA_OUTER_RADIUS_MM.mm)
          unit_direction, best_drop_mm = align_arm_to_solera_base(
            direction_before_rotation, radial_length_mm, ctx[:centroid_x_mm], ctx[:centroid_y_mm], ctx[:ground_z], target_point, local_z, base_point
          )
          return if unit_direction.nil? || best_drop_mm.nil?

          arm_z = target_point.z - best_drop_mm.mm
          post_axis = Geom::Point3d.new(ctx[:centroid_x_mm].mm, ctx[:centroid_y_mm].mm, arm_z)
          mid_point = post_axis.offset(unit_direction, radial_length_mm.mm)

          arm_end_point = mid_point.offset(unit_direction, EXIT_ARM_TIP_EXTRA_MM.mm)

          tube_extra_start = mid_point.offset(unit_direction, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
          tube_extra_length_mm = EXIT_ARM_TIP_EXTRA_MM - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM)
          if tube_extra_length_mm > 0.0
            tube_extra = PlayIdea::CreadorTubos.build_tube(
              ctx[:tube_params_base].merge(length_mm: tube_extra_length_mm, code: "TUB-ESTRUCTURAL-BRAZO-SALIDA-EXT-#{format('%.1f', tube_extra_length_mm)}"),
              tube_extra_start, unit_direction
            )
            instances << tube_extra
          end

          con10_up = PlayIdea::Conectores.create_connector('10', 'Galvanizado', ctx[:con10_metadata], arm_end_point)
          con10_up_target_x = Z_AXIS
          con10_up_target_z = unit_direction
          con10_up_target_y = con10_up_target_z.cross(con10_up_target_x)
          con10_up.transformation = Geom::Transformation.axes(arm_end_point, con10_up_target_x, con10_up_target_y, con10_up_target_z)
          instances << con10_up

          tip_con61_point = Geom::Point3d.new(arm_end_point.x, arm_end_point.y, ctx[:ground_z])
          tip_con61 = PlayIdea::Conectores.create_connector('61', 'Galvanizado', ctx[:con10_metadata], tip_con61_point)
          instances << tip_con61

          tip_post_length_mm = (arm_end_point.z - ctx[:ground_z]).to_mm + TIP_POST_EXTRA_MM
          tip_post = PlayIdea::CreadorTubos.build_tube(
            ctx[:tube_params_base].merge(length_mm: tip_post_length_mm, code: "TUB-ESTRUCTURAL-PATA-BRAZO-SALIDA-#{format('%.1f', tip_post_length_mm)}"),
            tip_con61_point, Z_AXIS
          )
          instances << tip_post
        rescue StandardError => error
          puts "  (soporte de tierra en la salida omitido: #{error.message})"
        end

        def arm_plan_for_height(elbow_count)
          steady = elbow_count - 2
          count = [[3 + ((steady - 6) / 2.0).round, 3].max, elbow_count - 2].min
          indices = if count <= 1
                      [0]
                    else
                      max_index = elbow_count - 2
                      (0...count).map { |k| (k * max_index / (count - 1).to_f).round }
                    end
          (indices + [elbow_count - 1]).uniq
        end

        # Pedido del usuario: los ductos del tobogán -fibra de vidrio- usan
        # los mismos 8 colores del catálogo estándar
        # -PlayIdea::ConstructorModulos::STANDARD_COLOR_PALETTE-, con 3
        # modos -params[:tobogan_color_mode]-: 'mono' -un solo color fijo,
        # params[:tobogan_color]-, 'bicolor' -2 colores alternados,
        # params[:tobogan_color_a]/[:tobogan_color_b]-, 'aleatorio' -al
        # azar en cada pieza-. Regresa un proc: cada llamada -una por
        # pieza construida, en orden- da el hex a usar en ESA pieza.
        # Sin `tobogan_color_mode` -params vacío, ej. scripts sueltos de
        # prueba- da `nil` siempre, y cada pieza cae en su propio
        # DEFAULT_COLOR_HEX -gris-, comportamiento de antes.
        def tobogan_color_picker(params)
          palette = PlayIdea::ConstructorModulos::STANDARD_COLOR_PALETTE
          hex_por_label = palette.to_h { |c| [c[:label], c[:hex]] }
          case params[:tobogan_color_mode]
          when 'bicolor'
            hex_a = hex_por_label[params[:tobogan_color_a]] || palette[0][:hex]
            hex_b = hex_por_label[params[:tobogan_color_b]] || palette[1][:hex]
            count = 0
            lambda do
              hex = count.even? ? hex_a : hex_b
              count += 1
              hex
            end
          when 'aleatorio'
            -> { palette.sample[:hex] }
          when 'mono'
            hex = hex_por_label[params[:tobogan_color]] || palette[0][:hex]
            -> { hex }
          else
            -> {}
          end
        end

        # --- El tobogán, una sola vez -------------------------------------------
        def build_tobogan(target_height_mm, start_point, heading = X_AXIS, color_params = {})
          next_color = tobogan_color_picker(color_params)
          model = Sketchup.active_model
          instances = []

          transition_radius_mm = Codo90::BEND_RADIUS_MM
          transition_ceja_mm = Codo90::CEJA_LENGTH_MM
          duct_outside_r_mm = Codo90::BODY_OUTSIDE_R_MM
          duct_inside_r_mm = Codo90::BODY_INSIDE_R_MM
          flange_bolt_wall_mm = 2.0 * Codo90::WALL_THICKNESS_MM

          elbow_count, pitch_deg = elbow_count_and_pitch_for_height(target_height_mm, transition_radius_mm, transition_ceja_mm, duct_outside_r_mm)
          pitch = pitch_deg * Math::PI / 180.0
          tan2_pitch = Math.tan(pitch)**2
          delta_phi = Math.acos(-tan2_pitch)

          point = start_point
          heading_phi = Math.atan2(heading.y, heading.x)
          phi = heading_phi
          start_z = point.z

          spiral_points = []
          duct_segments = []

          lead_in_direction = dir_at(phi, 0.0)
          duct_segments << { type: :straight, start: point, direction: lead_in_direction,
                              length: Recto::TOTAL_LENGTH_MM.mm }
          lead_in = Recto.build_piece({ color_hex: next_color.call }, point, lead_in_direction)
          instances << lead_in

          aro_total_mm = AroEntrada::COLLAR_LENGTH_MM + AroEntrada::FLANGE_THICKNESS_MM
          aro_start = point.offset(lead_in_direction, aro_total_mm.mm)
          aro_entrada = AroEntrada.build_piece({ color_hex: next_color.call }, aro_start, lead_in_direction.reverse)
          instances << aro_entrada

          aro_bolt_center = point.offset(lead_in_direction, ((AroEntrada::COLLAR_LENGTH_MM / 2.0) + AroEntrada::FLANGE_THICKNESS_MM).mm)
          Tornilleria.build_flange_bolts(instances, aro_bolt_center, lead_in_direction, duct_inside_r_mm, flange_bolt_wall_mm)

          point = point.offset(lead_in_direction, Recto::TOTAL_LENGTH_MM.mm)
          recto_bolt_center = point.offset(lead_in_direction.reverse, (Recto::CEJA_LENGTH_MM / 2.0).mm)
          Tornilleria.build_flange_bolts(instances, recto_bolt_center, lead_in_direction, duct_inside_r_mm, flange_bolt_wall_mm)

          dx_local = transition_radius_mm.mm * Math.sin(TRANSITION_SWEEP_RAD)
          dy_local = transition_radius_mm.mm * (1.0 - Math.cos(TRANSITION_SWEEP_RAD))

          elbow_count.times do |i|
            is_entry_transition = i.zero?
            is_exit_transition = (i == elbow_count - 1)
            is_transition = is_entry_transition || is_exit_transition

            entry_pitch = is_entry_transition ? 0.0 : pitch
            exit_pitch = is_exit_transition ? 0.0 : pitch
            step = is_transition ? TRANSITION_SWEEP_RAD : delta_phi

            entry_phi = phi
            exit_phi = entry_phi + step

            direction = dir_at(entry_phi, entry_pitch)
            exit_direction = dir_at(exit_phi, exit_pitch)

            spiral_points << point unless is_transition

            up_hint = exit_direction.cross(direction)
            instance = Codo90.build_piece({ color_hex: next_color.call }, point, direction, up_hint)
            instances << instance

            duct_segments << { type: :elbow, entry: point, direction: direction, exit_direction: exit_direction,
                                radius: transition_radius_mm.mm, sweep: TRANSITION_SWEEP_RAD }

            bend_offset = Geom::Vector3d.new(
              (direction.x * dx_local) + (exit_direction.x * dy_local),
              (direction.y * dx_local) + (exit_direction.y * dy_local),
              (direction.z * dx_local) + (exit_direction.z * dy_local)
            )
            point = point.offset(bend_offset)
            duct_segments << { type: :straight, start: point, direction: exit_direction, length: transition_ceja_mm.mm }
            point = point.offset(exit_direction, transition_ceja_mm.mm)
            elbow_bolt_center = point.offset(exit_direction.reverse, (transition_ceja_mm / 2.0).mm)
            Tornilleria.build_flange_bolts(instances, elbow_bolt_center, exit_direction, duct_inside_r_mm, flange_bolt_wall_mm)

            phi = exit_phi
          end

          final_direction = dir_at(phi, 0.0)
          salida = Salida.build_piece({ color_hex: next_color.call }, point, final_direction, Z_AXIS.reverse)
          instances << salida
          salida_round_length_mm = Salida::CEJA_LENGTH_MM + Salida::STRAIGHT_ROUND_LENGTH_MM
          duct_segments << { type: :straight, start: point, direction: final_direction, length: salida_round_length_mm.mm }

          spiral_xs_mm = spiral_points.map(&:x).map(&:to_mm)
          spiral_ys_mm = spiral_points.map(&:y).map(&:to_mm)
          centroid_x_mm = (spiral_xs_mm.min + spiral_xs_mm.max) / 2.0
          centroid_y_mm = (spiral_ys_mm.min + spiral_ys_mm.max) / 2.0

          exit_bottom_z = point.z - Salida::BODY_OUTSIDE_R_MM.mm
          ground_z = exit_bottom_z - CON61_BELOW_EXIT_MM.mm

          con61_metadata = { receiver_material: 'Galvanizado', hardware_size: '3/8"', investment_cost_mxn: 0, costing: { rows: [] } }
          con61_point = Geom::Point3d.new(centroid_x_mm.mm, centroid_y_mm.mm, ground_z)
          con61 = PlayIdea::Conectores.create_connector('61', 'Galvanizado', con61_metadata, con61_point)
          instances << con61

          tube_params_base = {
            outside_mm: CENTRAL_TUBE_OUTSIDE_MM,
            wall_mm: CENTRAL_TUBE_WALL_MM,
            inside_mm: CENTRAL_TUBE_INSIDE_MM,
            schedule: 'ESTRUCTURAL',
            color: CENTRAL_TUBE_COLOR,
            length_mode: 'manual',
            standard_name: '',
            connector_compatible: true,
            connector_clearance_mm: PlayIdea::CreadorTubos::CONNECTOR_INSIDE_MM - CENTRAL_TUBE_OUTSIDE_MM
          }
          con10_metadata = { receiver_material: 'Galvanizado', hardware_size: '3/8"', investment_cost_mxn: 0, costing: { rows: [] } }

          post_total_length_mm = (start_z - ground_z).to_mm
          post = PlayIdea::CreadorTubos.build_tube(
            tube_params_base.merge(length_mm: post_total_length_mm, code: "TUB-ESTRUCTURAL-POSTE-#{format('%.1f', post_total_length_mm)}"),
            con61_point, Z_AXIS
          )
          instances << post

          ctx = {
            centroid_x_mm: centroid_x_mm, centroid_y_mm: centroid_y_mm, ground_z: ground_z,
            duct_segments: duct_segments, con10_metadata: con10_metadata, tube_params_base: tube_params_base
          }
          arm_indices = arm_plan_for_height(elbow_count)
          arm_indices.each { |loop_i| build_support_arm(ctx, instances, loop_i) }
          build_exit_ground_support(ctx, instances, elbow_count - 1)

          resulting_height_mm = post_total_length_mm.to_mm + (2.0 * Salida::BODY_OUTSIDE_R_MM) + CON61_BELOW_EXIT_MM
          total_loops = (phi - heading_phi) / (2.0 * Math::PI)

          model.start_operation('Agrupar tobogán', true)
          group = model.active_entities.add_group(instances)
          group.name = "Tobogán #{(target_height_mm / 1000.0).round(1)}m (pitch=#{pitch_deg.round(2)}°, " \
                       "#{elbow_count} codos, ~#{total_loops.round(2)} vueltas, #{arm_indices.length} brazos)"
          model.commit_operation

          puts "Tobogán: pitch=#{pitch_deg.round(2)}°, codos=#{elbow_count}, vueltas=#{total_loops.round(2)}, " \
               "brazos=#{arm_indices.length}, altura_real=#{(resulting_height_mm / 1000.0).round(3)}m"
          { group: group, centroid_x_mm: centroid_x_mm, centroid_y_mm: centroid_y_mm, ground_z: ground_z, start_z: start_z, duct_segments: duct_segments }
        end

        # --- Unión del tobogán a la estructura de módulos, YA CONSTRUIDA -------
        # `params` es el mismo hash devuelto por
        # PlayIdea::ConstructorModulos.params_from_automatic_data/
        # validate_dialog_data -y ya pasado a create_module por el flujo
        # normal del diálogo-, con `params[:tobogan_height_mm]` agregado por
        # esos mismos métodos cuando el checkbox "Agregar tobogán" está
        # marcado. `origin` es el MISMO punto donde se colocó la estructura.
        #
        # Pedido del usuario: poder elegir por CUÁL de las 4 orillas de la
        # cuadrícula arranca el tobogán -antes fijo a +X-, y en qué celda a
        # lo largo de esa orilla -antes siempre centrado-.
        # `params[:tobogan_edge]` -:x_near/:x_far/:y_near/:y_far, default
        # :x_far- y `params[:tobogan_index]` -índice de celda a lo largo de
        # esa orilla, default centrado- controlan esto; el diálogo manual
        # los llena desde el selector interactivo de la vista previa -mismo
        # patrón que ya usa la torre-, el automático se queda con el
        # default de siempre.
        def attach(params, origin)
          nx = params[:modules_x]
          ny = params[:modules_y]
          nz = params[:modules_z]
          sx_mm = params[:spacing_x_mm]
          sy_mm = params[:spacing_y_mm]
          sz_mm = params[:spacing_z_mm]

          edge = params[:tobogan_edge] || :x_far

          case edge
          when :x_near, :x_far
            j0 = params[:tobogan_index] || [ny / 2, ny - 1].min
            if params[:tower] && ny > 1
              tower_offset_y_mm = params[:tower][:offset_y_mm]
              candidate_y_mm = PlayIdea::ConstructorModulos.axis_cumulative_mm(j0, sy_mm).to_mm
              j0 = j0.zero? ? 1 : j0 - 1 if (candidate_y_mm - tower_offset_y_mm).abs < 1.0
            end
            cell_depth_mm = PlayIdea::ConstructorModulos.axis_column_width_mm(j0, sy_mm)
            center_perp = PlayIdea::ConstructorModulos.axis_cumulative_mm(j0, sy_mm) + (cell_depth_mm / 2.0).mm
            edge_offset = edge == :x_far ? PlayIdea::ConstructorModulos.axis_cumulative_mm(nx, sx_mm) : 0.mm
            heading = edge == :x_far ? X_AXIS : X_AXIS.reverse
            rail_axis = Y_AXIS
            edge_x = origin.x + edge_offset
            edge_y = origin.y + center_perp
          when :y_near, :y_far
            i0 = params[:tobogan_index] || [nx / 2, nx - 1].min
            if params[:tower] && nx > 1
              tower_offset_x_mm = params[:tower][:offset_x_mm]
              candidate_x_mm = PlayIdea::ConstructorModulos.axis_cumulative_mm(i0, sx_mm).to_mm
              i0 = i0.zero? ? 1 : i0 - 1 if (candidate_x_mm - tower_offset_x_mm).abs < 1.0
            end
            cell_depth_mm = PlayIdea::ConstructorModulos.axis_column_width_mm(i0, sx_mm)
            center_perp = PlayIdea::ConstructorModulos.axis_cumulative_mm(i0, sx_mm) + (cell_depth_mm / 2.0).mm
            edge_offset = edge == :y_far ? PlayIdea::ConstructorModulos.axis_cumulative_mm(ny, sy_mm) : 0.mm
            heading = edge == :y_far ? Y_AXIS : Y_AXIS.reverse
            rail_axis = X_AXIS
            edge_x = origin.x + center_perp
            edge_y = origin.y + edge_offset
          else
            raise "tobogan_edge inválido: #{edge.inspect}"
          end

          k = [nz - 1, 0].max
          sz_length = PlayIdea::ConstructorModulos.spacing_z_length(sz_mm)
          structure_top_z = origin.z + PlayIdea::ConstructorModulos.grid_level_z(k, nz, sz_length)

          # Pedido del usuario: el tubo del soporte que carga el recto debe
          # medir SIEMPRE ~20cm, sin importar la altura pedida para la
          # estructura -antes salía lo que la geometría diera, normalmente
          # mucho más largo-. Para lograrlo, el recto ya NO se ancla a
          # `params[:tobogan_height_mm]` -eso mediría contra el TOPE real
          # de la cuadrícula, `k=nz`- sino contra `structure_top_z` -el
          # riel real del último NIVEL usable, `k=nz-1`, que es de donde
          # sale el tubo del soporte-, con ese tubo fijo a
          # RECTO_SUPPORT_LEG_MM. `target_height_mm` se recalcula para que
          # sea CONSISTENTE con ese punto de entrada -misma fórmula
          # `entry_z = origin.z + (target_height_mm - duct_outside_r_mm)`
          # ya validada, solo despejada al revés- para que `ground_z` del
          # tobogán -su propio CON-61- se siga alineando exacto con
          # `origin.z`, igual que antes.
          duct_outside_r_mm = Codo90::BODY_OUTSIDE_R_MM
          entry_z = structure_top_z + (RECTO_SUPPORT_LEG_MM + duct_outside_r_mm).mm
          target_height_mm = (entry_z - origin.z).to_mm + duct_outside_r_mm
          move_closer_mm = 150.0
          entry_point = Geom::Point3d.new(edge_x, edge_y, entry_z)
          entry_point = entry_point.offset(heading.reverse, move_closer_mm.mm)

          tobogan = build_tobogan(target_height_mm, entry_point, heading, params)

          # El poste de la estructura que recibe las ligas -y el soporte del
          # recto- vive sobre el riel real de la orilla elegida: fijo en el
          # eje de la orilla -edge_x/edge_y-, alineado con el centroide del
          # tobogán en el eje perpendicular, para que las ligas viajen
          # derecho -sin cruzar el recto en diagonal-.
          structure_post_x = (edge == :x_near || edge == :x_far) ? edge_x : tobogan[:centroid_x_mm].mm
          structure_post_y = (edge == :y_near || edge == :y_far) ? edge_y : tobogan[:centroid_y_mm].mm

          link_con10_metadata = { receiver_material: 'Galvanizado', hardware_size: '3/8"', investment_cost_mxn: 0, costing: { rows: [] } }
          link_tube_params_base = {
            outside_mm: CENTRAL_TUBE_OUTSIDE_MM, wall_mm: CENTRAL_TUBE_WALL_MM, inside_mm: CENTRAL_TUBE_INSIDE_MM,
            schedule: 'ESTRUCTURAL', color: CENTRAL_TUBE_COLOR, length_mode: 'manual', standard_name: '',
            connector_compatible: true, connector_clearance_mm: PlayIdea::CreadorTubos::CONNECTOR_INSIDE_MM - CENTRAL_TUBE_OUTSIDE_MM
          }

          # Pedido del usuario -corrección-: la liga de arriba rozaba un
          # ducto de 90° -el offset fijo de antes, 450mm bajo la entrada,
          # caía justo dentro del primer codo, que empieza plano -pitch de
          # entrada 0- y no baja gran cosa-. En vez de adivinar OTRO
          # offset fijo, se usan los puntos MEDIOS reales de los codos
          # -`duct_segments`, mismo patrón que `build_support_arm`- cuyo
          # azimut respecto al eje del poste queda lo más ALEJADO posible
          # del azimut hacia la estructura -el ducto de la espiral queda
          # del lado CONTRARIO del poste en esa Z, no en medio del camino
          # de la liga-. Pedido del usuario, también: entre más alto el
          # tobogán, más ligas -antes siempre 2, fijo-.
          link_instances = []
          bottom_link_drop_mm = 150.0
          bottom_z = origin.z + bottom_link_drop_mm.mm

          post_span_mm = (entry_point.z - bottom_z).to_mm
          extra_link_count = [1 + (post_span_mm / LINK_SPACING_MM).round, 1].max
          extra_targets_z = (0...extra_link_count).map do |i|
            fraction = (i + 1).to_f / (extra_link_count + 1)
            entry_point.z - ((entry_point.z - bottom_z) * fraction)
          end
          extra_zs = link_zs_avoiding_ducts(
            tobogan[:duct_segments], tobogan[:centroid_x_mm], tobogan[:centroid_y_mm],
            structure_post_x, structure_post_y, extra_targets_z, duct_outside_r_mm, bottom_z, entry_point.z
          )

          link_zs = ([bottom_z] + extra_zs).uniq
          link_zs.each_with_index do |link_z, index|
            tobogan_point = Geom::Point3d.new(tobogan[:centroid_x_mm].mm, tobogan[:centroid_y_mm].mm, link_z)
            structure_point = Geom::Point3d.new(structure_post_x, structure_post_y, link_z)
            code_suffix = if index.zero?
                            'ABAJO'
                          elsif index == link_zs.length - 1
                            'ARRIBA'
                          else
                            "MEDIO-#{index}"
                          end
            build_post_link(link_instances, tobogan_point, structure_point, link_con10_metadata, link_tube_params_base, code_suffix)
          end

          recto_point = Geom::Point3d.new(
            (edge == :x_near || edge == :x_far) ? structure_post_x : entry_point.x,
            (edge == :y_near || edge == :y_far) ? structure_post_y : entry_point.y,
            entry_point.z
          )
          # base_x/base_y = los MISMOS que recto_point, no structure_post_x/y
          # -que para el eje LIBRE es el centroide del tobogán, un punto
          # distinto-: si no, la pata queda inclinada -alcanzando desde el
          # centroide hasta el recto- en vez de subir derecha desde el riel
          # justo debajo del recto.
          build_recto_support(link_instances, recto_point.x, recto_point.y, structure_top_z, recto_point, heading, rail_axis, link_con10_metadata, link_tube_params_base)

          link_group = nil
          unless link_instances.empty?
            model = Sketchup.active_model
            model.start_operation('Unir tobogán a la estructura', true)
            link_group = model.active_entities.add_group(link_instances)
            link_group.name = 'Liga tobogán-estructura'
            model.commit_operation
          end

          { tobogan_group: tobogan[:group], link_group: link_group }
        end

        # `rail_axis` -Y_AXIS para una orilla del lado X, X_AXIS para una
        # orilla del lado Y- es hacia dónde corre el riel real de la
        # estructura en ese punto -antes fijo a Y_AXIS, solo válido para la
        # orilla +X-.
        def build_recto_support(instances, base_x, base_y, structure_top_z, recto_point, recto_tangent, rail_axis, con10_metadata, tube_params_base)
          base_point = Geom::Point3d.new(base_x, base_y, structure_top_z)
          duct_outside_r_mm = Codo90::BODY_OUTSIDE_R_MM
          base_target = recto_point.offset(Z_AXIS.reverse, duct_outside_r_mm.mm)
          vector = base_target - base_point
          return if vector.length.to_mm < 1.0

          unit = vector.normalize

          con_base = PlayIdea::Conectores.create_connector('10', 'Galvanizado', con10_metadata, base_point)
          con_base_target_x = rail_axis
          con_base_target_z = Z_AXIS.reverse
          con_base_target_y = con_base_target_z.cross(con_base_target_x)
          con_base.transformation = Geom::Transformation.axes(base_point, con_base_target_x, con_base_target_y, con_base_target_z)
          instances << con_base

          leg_raise_mm = 25.0
          leg_start = base_point.offset(unit, leg_raise_mm.mm)
          leg_length_mm = vector.length.to_mm - leg_raise_mm
          return if leg_length_mm <= 0.0

          leg = PlayIdea::CreadorTubos.build_tube(
            tube_params_base.merge(length_mm: leg_length_mm, code: "TUB-ESTRUCTURAL-SOPORTE-RECTO-#{format('%.1f', leg_length_mm)}"),
            leg_start, unit
          )
          instances << leg

          solera = Solera.build_piece({}, recto_point, recto_tangent, Z_AXIS.reverse, 76.2)
          instances << solera
          build_solera_bolts(instances, recto_point, recto_tangent, Z_AXIS.reverse)
        rescue StandardError => error
          puts "  (soporte del recto omitido: #{error.message})"
        end

        # Distancia MÍNIMA de `point` al segmento de recta `seg_a`-`seg_b`
        # -no a la recta infinita-, en mm. Aritmética de vectores pura, sin
        # crear geometría.
        def point_to_segment_distance_mm(point, seg_a, seg_b)
          ab = seg_b - seg_a
          len2 = (ab.x * ab.x) + (ab.y * ab.y) + (ab.z * ab.z)
          return point.distance(seg_a).to_mm if len2 < 1e-9

          ap = point - seg_a
          t = ((ap.x * ab.x) + (ap.y * ab.y) + (ap.z * ab.z)) / len2
          t = [[t, 0.0].max, 1.0].min
          closest = Geom::Point3d.new(seg_a.x + (ab.x * t), seg_a.y + (ab.y * t), seg_a.z + (ab.z * t))
          point.distance(closest).to_mm
        end

        # Espacio libre -mm- entre el segmento de la liga -`tobogan_point`
        # a `structure_point`- y el ducto REAL más cercano: muestrea CADA
        # tramo de `duct_segments` -recto O codo, no solo el punto medio
        # de los codos- en varios puntos a lo largo de su recorrido, mide
        # la distancia de cada uno al segmento de la liga, y resta el
        # radio exterior del ducto -para que sea espacio libre, no
        # distancia centro a centro-. Negativo/cero = choca.
        def link_clearance_mm(duct_segments, tobogan_point, structure_point, duct_outside_r_mm, samples_per_segment: 12)
          min_distance_mm = Float::INFINITY
          duct_segments.each do |seg|
            (0..samples_per_segment).each do |i|
              point, = point_at_segment_fraction(seg, i.to_f / samples_per_segment)
              distance_mm = point_to_segment_distance_mm(point, tobogan_point, structure_point)
              min_distance_mm = distance_mm if distance_mm < min_distance_mm
            end
          end
          min_distance_mm - duct_outside_r_mm
        end

        # Margen extra sobre el radio del ducto: la liga misma tiene
        # grosor -tubo + conectores-, no es una línea de cero grosor.
        LINK_CLEARANCE_SAFETY_MM = 60.0
        LINK_SCAN_STEP_MM = 50.0

        # Para cada Z objetivo en `target_zs`, recorre TODO el rango
        # `bottom_z`..`top_z` -cada `LINK_SCAN_STEP_MM`- midiendo el
        # espacio libre real -`link_clearance_mm`- de la liga horizontal
        # a esa Z, y elige la Z SEGURA -espacio libre >=
        # LINK_CLEARANCE_SAFETY_MM- más cercana a la buscada. Si NINGUNA Z
        # del rango es segura, se conforma con la de MÁS espacio libre
        # -mejor esa que la peor posible-.
        def link_zs_avoiding_ducts(duct_segments, centroid_x_mm, centroid_y_mm, structure_x, structure_y, target_zs, duct_outside_r_mm, bottom_z, top_z)
          evaluated = []
          z = bottom_z
          while z <= top_z
            tobogan_point = Geom::Point3d.new(centroid_x_mm.mm, centroid_y_mm.mm, z)
            structure_point = Geom::Point3d.new(structure_x, structure_y, z)
            clearance_mm = link_clearance_mm(duct_segments, tobogan_point, structure_point, duct_outside_r_mm)
            evaluated << { z: z, clearance_mm: clearance_mm }
            z += LINK_SCAN_STEP_MM.mm
          end
          return [] if evaluated.empty?

          safe = evaluated.select { |c| c[:clearance_mm] >= LINK_CLEARANCE_SAFETY_MM }
          if safe.empty?
            best_clearance = evaluated.map { |c| c[:clearance_mm] }.max
            safe = evaluated.select { |c| c[:clearance_mm] >= best_clearance - 1.0 }
          end
          target_zs.map { |target_z| safe.min_by { |c| (c[:z] - target_z).to_mm.abs }[:z] }
        end

        def build_post_link(instances, point_a, point_b, con10_metadata, tube_params_base, code_suffix)
          vector = point_b - point_a
          return if vector.length.to_mm < 1.0

          unit = vector.normalize

          con_a = PlayIdea::Conectores.create_connector('10', 'Galvanizado', con10_metadata, point_a)
          con_a_target_x = Z_AXIS
          con_a_target_z = unit.reverse
          con_a_target_y = con_a_target_z.cross(con_a_target_x)
          con_a.transformation = Geom::Transformation.axes(point_a, con_a_target_x, con_a_target_y, con_a_target_z)
          instances << con_a

          con_b = PlayIdea::Conectores.create_connector('10', 'Galvanizado', con10_metadata, point_b)
          con_b_target_x = Z_AXIS
          con_b_target_z = unit
          con_b_target_y = con_b_target_z.cross(con_b_target_x)
          con_b.transformation = Geom::Transformation.axes(point_b, con_b_target_x, con_b_target_y, con_b_target_z)
          instances << con_b

          tube_start = point_a.offset(unit, CONNECTOR_SOCKET_CLEARANCE_MM.mm)
          tube_length_mm = vector.length.to_mm - (2.0 * CONNECTOR_SOCKET_CLEARANCE_MM)
          return if tube_length_mm <= 0.0

          tube = PlayIdea::CreadorTubos.build_tube(
            tube_params_base.merge(length_mm: tube_length_mm, code: "TUB-ESTRUCTURAL-LIGA-#{code_suffix}-#{format('%.1f', tube_length_mm)}"),
            tube_start, unit
          )
          instances << tube
        end
      end
    end
  end
end
