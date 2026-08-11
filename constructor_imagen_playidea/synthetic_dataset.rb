require 'json'
require 'fileutils'

module PlayIdea
  module ConstructorImagen
    SYNTHETIC_CAMERA_DIRECTIONS = [
      [-1.0, 0.0, 0.15], [1.0, 0.0, 0.15],
      [0.0, -1.0, 0.15], [0.0, 1.0, 0.15],
      [-1.0, -1.0, 0.55], [1.0, -1.0, 0.55]
    ].freeze
    SYNTHETIC_COLORS = %w[Azul Rojo Verde Amarillo Naranja Morado].freeze
    SYNTHETIC_HALF_MODULE_MM = MODULE_INTERNAL_MM / 2.0

    def synthetic_dataset_root
      File.join(Dir.home, 'Library', 'Application Support', 'PlayIdea', 'constructor_imagen_dataset')
    end

    def generate_synthetic_dataset
      unless constructor_available?
        UI.messagebox('Activa el Constructor de Módulos y reinicia SketchUp antes de generar el dataset.')
        return
      end
      model = Sketchup.active_model
      unless model.active_entities.length.zero?
        UI.messagebox(
          "El generador necesita un modelo vacío para que otras piezas no aparezcan en las imágenes.\n\n" \
          'Abre un archivo nuevo vacío y vuelve a ejecutar este comando.'
        )
        return
      end
      values = UI.inputbox(
        ['Cantidad de estructuras (6 vistas cada una):'], [30],
        'Dataset sintético de postes'
      )
      return unless values
      count = values[0].to_i
      unless count.between?(1, 100)
        UI.messagebox('La cantidad debe estar entre 1 y 100 estructuras.')
        return
      end
      confirmation = UI.messagebox(
        "Se generarán #{count * SYNTHETIC_CAMERA_DIRECTIONS.length} imágenes etiquetadas. " \
        "SketchUp puede tardar varios minutos.\n\n¿Continuar?", MB_YESNO
      )
      return unless confirmation == IDYES

      original_camera = model.active_view.camera
      original_axes = [original_camera.eye, original_camera.target, original_camera.up, original_camera.perspective?, original_camera.fov]
      root = synthetic_dataset_root
      FileUtils.mkdir_p(root)
      generated_views = 0
      count.times do |index|
        generated_views += generate_one_synthetic_example(model, root, index + 1)
        Sketchup.set_status_text("Dataset sintético: #{index + 1}/#{count} estructuras", SB_PROMPT)
      end
      restore_synthetic_camera(model.active_view, original_axes)
      train_result = request_post_retraining
      message = "Dataset terminado: #{count} estructuras y #{generated_views} vistas etiquetadas."
      message += "\nDetector reentrenado." if train_result
      UI.messagebox(message)
    rescue StandardError => error
      restore_synthetic_camera(model.active_view, original_axes) if model && original_axes
      UI.messagebox("No fue posible generar el dataset sintético:\n#{error.message}")
      puts error.full_message
    ensure
      Sketchup.set_status_text('', SB_PROMPT)
    end

    def generate_one_synthetic_example(model, root, sequence)
      nx = rand(1..5)
      ny = rand(1..4)
      nz = rand(1..4)
      spacing = MODULE_INTERNAL_MM
      spacing_x = synthetic_axis_spacings(nx)
      spacing_y = synthetic_axis_spacings(ny)
      params = {
        modules_x: nx, modules_y: ny, modules_z: nz,
        spacing_x_mm: spacing_x, spacing_y_mm: spacing_y, spacing_z_mm: spacing,
        color: SYNTHETIC_COLORS.sample, code: "SYN-#{nx}X#{ny}X#{nz}",
        connectors: true, padding: false
      }
      group = PlayIdea::ConstructorModulos.create_module(params, ORIGIN)
      example_id = "ejemplo_sintetico_#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{sequence.to_s.rjust(3, '0')}_#{rand(1000..9999)}"
      directory = File.join(root, example_id)
      FileUtils.mkdir_p(directory)
      images = []
      views = []
      SYNTHETIC_CAMERA_DIRECTIONS.each_with_index do |direction, view_index|
        set_synthetic_camera(model.active_view, spacing_x, spacing_y, nz, spacing, direction)
        model.active_view.zoom_extents
        model.active_view.refresh
        width = model.active_view.vpwidth
        height = model.active_view.vpheight
        filename = "vista_#{(view_index + 1).to_s.rjust(2, '0')}.png"
        path = File.join(directory, filename)
        model.active_view.write_image(path, width, height, true, 0.92)
        posts = projected_synthetic_posts(model.active_view, spacing_x, spacing_y, nz, spacing, width, height)
        images << { index: view_index + 1, original_name: filename, file: filename }
        views << { view_index: view_index + 1, image_width: width, image_height: height, posts: posts }
      end
      annotation = {
        schema_version: 1, example_id: example_id, analysis_id: example_id,
        module_internal_mm: spacing, images: images, views: views,
        anchor_views: { front_view: 1, depth_view: 3 }, correspondences: [],
        training_scope: 'post_detection_synthetic',
        synthetic_parameters: {
          modules_x: nx, modules_y: ny, modules_z: nz, color: params[:color],
          spacing_x_mm: spacing_x, spacing_y_mm: spacing_y, spacing_z_mm: spacing
        },
        labels: { post: 'poste estructural vertical', endpoint_order: %w[top bottom] }
      }
      File.write(File.join(directory, 'annotations.json'), JSON.pretty_generate(annotation))
      model.active_entities.erase_entities(group) if group&.valid?
      SYNTHETIC_CAMERA_DIRECTIONS.length
    rescue StandardError
      model.active_entities.erase_entities(group) if group&.valid?
      raise
    end

    def synthetic_axis_spacings(count)
      Array.new(count) { rand < 0.35 ? SYNTHETIC_HALF_MODULE_MM : MODULE_INTERNAL_MM }
    end

    def synthetic_axis_positions(spacings)
      spacings.each_with_object([0.0]) { |value, positions| positions << positions[-1] + value }
    end

    def set_synthetic_camera(view, spacing_x, spacing_y, nz, spacing, direction)
      width = spacing_x.sum.mm
      depth = spacing_y.sum.mm
      height = (nz * spacing + PlayIdea::ConstructorModulos::BASE_GRID_HEIGHT_MM).mm
      center = Geom::Point3d.new(width / 2.0, depth / 2.0, height / 2.0)
      vector = Geom::Vector3d.new(*direction).normalize
      distance = [width, depth, height].max * 2.8
      eye = center.offset(vector, distance)
      camera = Sketchup::Camera.new(eye, center, Z_AXIS, true)
      camera.fov = 38.0
      view.camera = camera
    end

    def projected_synthetic_posts(view, spacing_x, spacing_y, nz, spacing, width, height)
      top_mm = PlayIdea::ConstructorModulos.grid_level_z(nz, nz, spacing).to_mm
      posts = []
      synthetic_axis_positions(spacing_x).each do |x_mm|
        synthetic_axis_positions(spacing_y).each do |y_mm|
          bottom = view.screen_coords(Geom::Point3d.new(x_mm.mm, y_mm.mm, 0))
          top = view.screen_coords(Geom::Point3d.new(x_mm.mm, y_mm.mm, top_mm.mm))
          next unless [bottom.x, bottom.y, top.x, top.y].all?(&:finite?)
          next if [bottom.x, top.x].max < 0 || [bottom.x, top.x].min >= width || [bottom.y, top.y].max < 0 || [bottom.y, top.y].min >= height
          posts << {
            post_index: posts.length, x: ((bottom.x + top.x) / 2.0).round(2),
            top_y: [top.y, bottom.y].min.round(2), bottom_y: [top.y, bottom.y].max.round(2),
            provisional_levels: nz, provisional_height_mm: (nz * spacing).round(1),
            confirmed: true, synthetic: true
          }
        end
      end
      posts
    end

    def restore_synthetic_camera(view, values)
      return unless view && values
      camera = Sketchup::Camera.new(values[0], values[1], values[2], values[3])
      camera.fov = values[4] if values[3]
      view.camera = camera
      view.refresh
    end

    def request_post_retraining
      start_local_api unless api_running?
      response = Net::HTTP.start(API_HOST, API_PORT, open_timeout: 1, read_timeout: 600) do |http|
        http.post('/train-post-detector', '', 'Content-Type' => 'application/json')
      end
      response.is_a?(Net::HTTPSuccess)
    rescue StandardError => error
      puts "No se pudo reentrenar después del dataset sintético: #{error.message}"
      false
    end
  end
end
