# Script suelto (NO es un plugin instalable) para probar rápido la
# textura de la red de nylon sin reiniciar SketchUp: edita este archivo
# y en la Consola de Ruby -Window > Ruby Console- corre
#   load '/Users/minorusal/Documents/SKETCHUP/scripts/red_nylon_playidea.rb'
# -o arrastra el archivo a la ventana de SketchUp-. Cada `load` vuelve a
# ejecutar el archivo completo y abre el diálogo de inmediato.
#
# La red -miles de hilos torcidos anudados- es imposible de modelar como
# geometría 3D real a escala de lienzo completo (20 x 2.4m con abertura
# de 1 pulgada serían ~75,000 celdas). Se representa como una TEXTURA -imagen
# PNG generada aquí mismo, con el hilo opaco y la abertura transparente-
# aplicada a un solo panel plano del tamaño real del lienzo. Para verla
# transparente hace falta que el estilo de vista tenga "Transparencia"
# activada -si no, SketchUp puede mostrarla sólida-.

require 'zlib'

Object.send(:remove_const, :PlayIdeaRedNylonScript) if defined?(PlayIdeaRedNylonScript)

module PlayIdeaRedNylonScript
  extend self

  DICTIONARY = 'playidea_red'.freeze

  # Datos reales de la cotización de Grupo Aazzynet -sin factura todavía,
  # ver mensaje del usuario-. Un lienzo completo mide 20 x 2.4m. La
  # abertura del cuadro es de 1 PULGADA -confirmado con el usuario, no
  # 2cm como se leyó primero de la cotización-.
  LIENZO_WIDTH_MM = 20000.0
  LIENZO_HEIGHT_MM = 2400.0
  ABERTURA_MM = 25.4 # 1 pulgada
  CALIBRE_MM = 1.7   # grosor del hilo -calibre 18, redondo-

  # Resolución del tile de la textura -en px-, y grosor del hilo dentro
  # del tile, en proporción a ABERTURA_MM/CALIBRE_MM -aprox visual, no
  # es una medida física exacta del tejido real-. El nudo -donde cruzan
  # hilo horizontal y vertical- sale un poco más grueso que el hilo,
  # como en la red real.
  TILE_PX = 128
  LINE_WIDTH_PX = (TILE_PX * (CALIBRE_MM / ABERTURA_MM)).round.clamp(2, TILE_PX / 4)
  KNOT_RADIUS_PX = LINE_WIDTH_PX * 1.4

  CORD_COLOR = [15, 15, 15, 255].freeze   # negro, opaco
  GAP_COLOR = [0, 0, 0, 0].freeze         # transparente

  def start
    prompts = ['Ancho del panel a crear (m)', 'Alto del panel a crear (m)']
    defaults = [LIENZO_WIDTH_MM / 1000.0, LIENZO_HEIGHT_MM / 1000.0]
    values = UI.inputbox(prompts, defaults, 'Crear panel de red de nylon Play Idea')
    return unless values

    width_mm = values[0].to_f * 1000.0
    height_mm = values[1].to_f * 1000.0
    if width_mm <= 0 || height_mm <= 0
      UI.messagebox('El ancho y el alto deben ser mayores que cero.')
      return
    end

    params = { width_mm: width_mm, height_mm: height_mm }
    Sketchup.active_model.select_tool(PlacementTool.new(params))
  rescue StandardError => error
    UI.messagebox("No fue posible iniciar el creador de red de nylon:\n#{error.message}")
    puts error.full_message
  end

  def build_panel(params, corner_point)
    model = Sketchup.active_model
    model.start_operation('Crear panel de red de nylon', true)

    definition = model.definitions.add(unique_name(model, 'RED-NYLON'))
    entities = definition.entities
    w = params[:width_mm].mm
    h = params[:height_mm].mm
    pts = [
      Geom::Point3d.new(0, 0, 0),
      Geom::Point3d.new(w, 0, 0),
      Geom::Point3d.new(w, 0, h),
      Geom::Point3d.new(0, 0, h)
    ]
    face = entities.add_face(pts)
    face.reverse! if face.normal.y > 0

    # SIN position_material a propósito: con solo fijar texture.size -ver
    # net_material- y asignar el material a la cara, SketchUp repite la
    # textura sola a su tamaño real. Un mapeo UV manual en metros -como
    # se hizo antes- pisa esa escala y hace que la red salga mucho más
    # grande de lo real.
    material = net_material(model)
    face.material = material
    face.back_material = material

    definition.set_attribute(DICTIONARY, 'type', 'red_nylon')
    definition.set_attribute(DICTIONARY, 'width_mm', params[:width_mm])
    definition.set_attribute(DICTIONARY, 'height_mm', params[:height_mm])
    definition.set_attribute(DICTIONARY, 'abertura_mm', ABERTURA_MM)
    definition.set_attribute(DICTIONARY, 'calibre_mm', CALIBRE_MM)

    instance = model.active_entities.add_instance(definition, Geom::Transformation.new(corner_point))
    instance.name = 'RED-NYLON'

    model.selection.clear
    model.selection.add(instance)
    model.commit_operation
    instance
  rescue StandardError
    model.abort_operation
    raise
  end

  # Regenera el PNG y actualiza el material -aunque ya existan de una
  # corrida anterior- cada vez que se llama: mientras se está ajustando
  # el patrón/tamaño a mano -como ahorita-, cachear por nombre de
  # archivo/material dejaría viendo la versión vieja después de cada
  # `load`, sin ningún aviso de que sigue desactualizada.
  def net_material(model)
    name = 'PlayIdea Red Nylon Negra'
    path = texture_path
    write_net_png(path)

    material = model.materials[name] || model.materials.add(name)
    material.texture = path
    # texture.size es el tamaño REAL de un tile repetido sobre la cara
    # -sin position_material, SketchUp la reparte sola con este tamaño-.
    material.texture.size = ABERTURA_MM.mm
    material.alpha = 1.0 # el alfa real vive en la textura -PNG RGBA-, no aquí
    material
  end

  def texture_path
    File.join(Sketchup.temp_dir, 'playidea_red_nylon_tile.png')
  end

  # Genera el PNG del tile: cuadrícula RECTA -líneas horizontales y
  # verticales, no en rombo/diagonal- con un nudo redondo en cada cruce
  # -un poco más grueso que el hilo, como en la red real-, hilo opaco
  # sobre fondo transparente. Sin dependencias externas -solo zlib, ya
  # viene con Ruby-.
  def write_net_png(path)
    half_line = LINE_WIDTH_PX / 2.0
    pixels = Array.new(TILE_PX) { Array.new(TILE_PX) }
    TILE_PX.times do |y|
      TILE_PX.times do |x|
        dx = [x % TILE_PX, TILE_PX - (x % TILE_PX)].min
        dy = [y % TILE_PX, TILE_PX - (y % TILE_PX)].min
        on_line = dx <= half_line || dy <= half_line
        on_knot = Math.sqrt((dx**2) + (dy**2)) <= KNOT_RADIUS_PX
        pixels[y][x] = (on_line || on_knot) ? CORD_COLOR : GAP_COLOR
      end
    end
    write_png(path, TILE_PX, TILE_PX, pixels)
  end

  def write_png(path, width, height, pixels)
    raw = String.new(encoding: Encoding::ASCII_8BIT)
    height.times do |y|
      raw << 0.chr
      width.times do |x|
        raw << pixels[y][x].pack('C4')
      end
    end
    compressed = Zlib::Deflate.deflate(raw, 9)

    png = String.new(encoding: Encoding::ASCII_8BIT)
    png << [137, 80, 78, 71, 13, 10, 26, 10].pack('C8')
    png << png_chunk('IHDR', [width, height, 8, 6, 0, 0, 0].pack('N2C5'))
    png << png_chunk('IDAT', compressed)
    png << png_chunk('IEND', String.new(encoding: Encoding::ASCII_8BIT))

    File.open(path, 'wb') { |f| f.write(png) }
  end

  def png_chunk(type, data)
    chunk = type.dup.force_encoding(Encoding::ASCII_8BIT) + data
    [data.bytesize].pack('N') + chunk + [Zlib.crc32(chunk)].pack('N')
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
    def initialize(params)
      @params = params
      @input_point = Sketchup::InputPoint.new
    end

    def activate
      Sketchup.set_status_text('Haz clic para colocar la esquina inferior del panel.', SB_PROMPT)
    end

    def onMouseMove(_flags, x, y, view)
      @input_point.pick(view, x, y)
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      @input_point.pick(view, x, y)
      PlayIdeaRedNylonScript.build_panel(@params, @input_point.position)
      Sketchup.active_model.select_tool(nil)
    end

    def draw(view)
      @input_point.draw(view) if @input_point.valid?
    end

    def onCancel(_reason, _view)
      Sketchup.active_model.select_tool(nil)
    end

    def getExtents
      bounds = Geom::BoundingBox.new
      bounds.add(@input_point.position) if @input_point.valid?
      bounds
    end
  end
end

PlayIdeaRedNylonScript.start
