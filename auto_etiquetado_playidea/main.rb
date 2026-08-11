# auto_etiquetado_playidea/main.rb
#
# Plugin de SketchUp para Play Idea: auto-etiquetado por geometría/textura +
# costeo de inventario. Convertido desde el script maestro que antes se
# pegaba a mano en la Consola de Ruby cada vez
# (script_auto_etiquetado.rb en la carpeta Modelado) -el cuerpo de abajo es
# una copia línea por línea de ese script -sin reescribir ninguna regla de
# clasificación ni de precio-, solo envuelto en un módulo con menú propio
# para no tener que pegarlo a mano.
#
# Acción 1 (pi_auto_etiquetar): auto-etiqueta + genera el reporte de
# inventario y costos, exportado a un .txt junto al modelo.
# Acción 2 (pi_lista_cortes_tubos): lista de cortes de tubos de la
# selección actual.

require 'sketchup.rb'
require 'json'

module PlayIdea
  module AutoEtiquetado
    extend self

# ==============================================================
# FUNCIÓN COMPARTIDA: Leer material de una pieza
# ==============================================================
def pi_leer_material(ent)
mats = []
mats << ent.material.name if ent.material && ent.material.name && !ent.material.name.empty?
ents_int = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
ents_int.grep(Sketchup::Face).each do |cara|
mats << cara.material.name if cara.material && cara.material.name && !cara.material.name.empty?
mats << cara.back_material.name if cara.back_material && cara.back_material.name && !cara.back_material.name.empty?
end
# Prioridad: Si alguna cara tiene malla, devolver malla
return "malla" if mats.any? { |m| m.downcase.include?("malla") || m.include?("gra1 c\u00f3pia") }
mats.first || "Sin_Material"
end

# ==============================================================
# FUNCIÓN COMPARTIDA: Obtener dimensiones reales aplicando escala
# ==============================================================
def pi_dimensiones(instancia, trans_acumulada)
t_global = trans_acumulada * instancia.transformation
x_scale = Geom::Vector3d.new(1,0,0).transform(t_global).length
y_scale = Geom::Vector3d.new(0,1,0).transform(t_global).length
z_scale = Geom::Vector3d.new(0,0,1).transform(t_global).length
lb = instancia.respond_to?(:definition) ? instancia.definition.bounds : instancia.bounds
dims = [
(lb.width * x_scale * 0.0254).round(2),
(lb.height * y_scale * 0.0254).round(2),
(lb.depth * z_scale * 0.0254).round(2)
].sort
{ grosor_min: dims[0], ancho: dims[1], largo: dims[2], grosor_max: dims[1], t_global: t_global }
end

# ==============================================================
# FUNCIÓN COMPARTIDA: buscar una entidad por su entityID -recorriendo TODO
# el árbol del modelo, no solo el nivel raíz-, para volver a encontrar en
# vivo una pieza que el diálogo solo conoce por su entityID.
# ==============================================================
def pi_buscar_por_entity_id(entities, entity_id)
  entities.each do |e|
    next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    return e if e.entityID == entity_id
    hijos = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
    encontrado = pi_buscar_por_entity_id(hijos, entity_id)
    return encontrado if encontrado
  end
  nil
end

# ==============================================================
# FUNCIÓN COMPARTIDA: inspección profunda de una sola entidad -MISMA
# lógica y MISMO formato de salida que scripts/inspect_geometry.rb (bounds
# local + mundo, transform, tabla plana, distancias entre pares), para que
# el .txt que genera este botón se pueda seguir leyendo/pegando igual que
# los que ya se venían generando pegando ese script a mano en la consola.
# Devuelve la ruta del .txt generado, en la MISMA carpeta OUTPUT_DIR.
# ==============================================================
def pi_inspeccionar_entidad(entity)
  require 'fileutils'
  require 'stringio'
  output_dir = '/Users/minorusal/Documents/SKETCHUP/inspect_output'
  max_depth = 4
  flat_index = []

  mm3 = ->(pt) { pt.to_a.map { |v| v.to_mm.round(3) } }
  entity_label = ->(e) { e.name.to_s.empty? ? "(sin nombre)" : e.name }
  child_entities_of = ->(e) {
    container = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
    container.grep(Sketchup::Group) + container.grep(Sketchup::ComponentInstance)
  }
  world_bounds_of = ->(bounds, ancestors_transform) {
    box = Geom::BoundingBox.new
    8.times { |i| box.add(bounds.corner(i).transform(ancestors_transform)) }
    box
  }
  bbox_gap = ->(b1, b2) {
    gx = [b1.min.x, b2.min.x].max - [b1.max.x, b2.max.x].min
    gy = [b1.min.y, b2.min.y].max - [b1.max.y, b2.max.y].min
    gz = [b1.min.z, b2.min.z].max - [b1.max.z, b2.max.z].min
    [gx.to_mm.round(3), gy.to_mm.round(3), gz.to_mm.round(3)]
  }

  describe_entity = lambda do |ent, indent, path, ancestors_transform, out|
    name = entity_label.call(ent)
    kind = ent.is_a?(Sketchup::Group) ? "Grupo" : "Componente"
    bounds = ent.bounds
    t = ent.transformation
    wbounds = world_bounds_of.call(bounds, ancestors_transform)
    world_origin = t.origin.transform(ancestors_transform)

    out.puts "#{indent}- #{name}  [#{kind}]  ruta: #{path}"
    out.puts "#{indent}    bounds min=#{mm3.call(bounds.min)}  max=#{mm3.call(bounds.max)}  (mm, LOCAL al padre inmediato)"
    out.puts "#{indent}    bounds MUNDO min=#{mm3.call(wbounds.min)}  max=#{mm3.call(wbounds.max)}  (mm, ABSOLUTAS del modelo)"
    out.puts "#{indent}    bounds size = #{[bounds.width.to_mm.round(3), bounds.height.to_mm.round(3), bounds.depth.to_mm.round(3)]} mm (X,Y,Z)"
    out.puts "#{indent}    transform origin LOCAL=#{mm3.call(t.origin)}  origin MUNDO=#{mm3.call(world_origin)}"
    out.puts "#{indent}    transform xaxis=#{t.xaxis.to_a.map { |v| v.round(4) }}  yaxis=#{t.yaxis.to_a.map { |v| v.round(4) }}  zaxis=#{t.zaxis.to_a.map { |v| v.round(4) }}"

    flat_index << { path: path, wbounds: wbounds }
    wbounds
  end

  inspect_recursive = nil
  inspect_recursive = lambda do |ent, indent, depth, path, ancestors_transform, out|
    describe_entity.call(ent, indent, path, ancestors_transform, out)
    next_children = child_entities_of.call(ent)
    return if depth >= max_depth || next_children.empty?

    my_world_transform = ancestors_transform * ent.transformation
    out.puts "#{indent}  Sub-piezas directas (#{next_children.length}):\n\n"
    next_children.each do |c|
      inspect_recursive.call(c, indent + "    ", depth + 1, "#{path} > #{entity_label.call(c)}", my_world_transform, out)
    end

    if next_children.length > 1
      out.puts "#{indent}  Distancias LOCALES entre hijos de '#{entity_label.call(ent)}' (mm por eje; negativo = se encimen):\n\n"
      next_children.combination(2).each do |a, b|
        out.puts "#{indent}    #{entity_label.call(a)}  <->  #{entity_label.call(b)}  :  gap XYZ = #{bbox_gap.call(a.bounds, b.bounds)}"
      end
      out.puts
    end
  end

  out = StringIO.new
  out.puts "=" * 70
  out.puts "RAÍZ: #{entity_label.call(entity)}  (profundidad máxima: #{max_depth})"
  out.puts "=" * 70
  inspect_recursive.call(entity, "", 0, entity_label.call(entity), Geom::Transformation.new, out)
  out.puts

  out.puts "=" * 70
  out.puts "TABLA PLANA — coordenadas de MUNDO de todas las piezas (#{flat_index.length})"
  out.puts "=" * 70
  flat_index.each do |e|
    out.puts e[:path]
    out.puts "    world bounds min=#{e[:wbounds].min.to_a.map { |v| v.to_mm.round(2) }}  max=#{e[:wbounds].max.to_a.map { |v| v.to_mm.round(2) }}"
  end

  if flat_index.length > 1
    out.puts
    out.puts "=" * 70
    out.puts "DISTANCIAS EN MUNDO entre TODOS los pares (mm por eje; negativo = se " \
      "encimen/traslapan en ese eje; compara CUALQUIER rama del árbol, no solo hermanos)"
    out.puts "=" * 70
    flat_index.combination(2).each do |a, b|
      out.puts a[:path]
      out.puts "  <-> #{b[:path]}"
      out.puts "  gap XYZ = #{bbox_gap.call(a[:wbounds], b[:wbounds])}"
    end
  end

  FileUtils.mkdir_p(output_dir)
  output_path = File.join(output_dir, "inspect_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt")
  File.write(output_path, out.string)
  output_path
end

# ==============================================================
# FUNCIÓN COMPARTIDA: agregar una regla nueva DIRECTO en este mismo
# archivo -sin pasar por la IA-, a partir de un DESCONOCIDO ya detectado
# (su huella: caras + largo x ancho x grosor, ya capturada en
# @pi_desconocidos) más el nombre y precio que el usuario escribe en el
# diálogo. Inserta la nueva regla como PRIMER elemento de
# huellas_estructurales -para que gane sobre cualquier regla genérica más
# amplia, igual que se hizo a mano con Colchoneta_Tumbling_Especial- y el
# precio como primera entrada de @precios. Guarda un respaldo con fecha
# antes de tocar el archivo, y recarga el plugin en caliente con `load`
# para que la regla ya sirva en la MISMA sesión de SketchUp, sin tener que
# reinstalar el .rbz ni reiniciar -el guard `file_loaded?` al final del
# archivo evita que este `load` duplique el menú-.
# ==============================================================
def pi_guardar_regla_desconocido(entity_id, tag_nuevo, precio)
  info = (@pi_desconocidos || []).find { |d| d[:entity_id] == entity_id }
  return { ok: false, error: 'No tengo los datos de esa pieza -vuelve a correr el auto-etiquetado y ábrela otra vez.' } unless info

  tag_limpio = tag_nuevo.to_s.strip.gsub(/[^A-Za-z0-9_]/, '_')
  return { ok: false, error: 'Escribe un nombre para la regla.' } if tag_limpio.empty?

  precio_num = precio.to_f
  return { ok: false, error: 'Escribe un precio válido (mayor que cero).' } unless precio_num.positive?

  require 'fileutils'
  main_path = __FILE__
  contenido = File.read(main_path)

  marcador_huellas = /^huellas_estructurales = \[\n/
  marcador_precios = /  @precios = \{\n/
  unless contenido =~ marcador_huellas
    return { ok: false, error: 'No encontré huellas_estructurales en el archivo -no se guardó nada.' }
  end
  unless contenido =~ marcador_precios
    return { ok: false, error: 'No encontré la tabla @precios en el archivo -no se guardó nada.' }
  end

  linea_huella =
    "{ descripcion: \"#{tag_limpio} (agregada desde el plugin: #{info[:caras]} caras, #{info[:medidas]})\", " \
    "condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities) rescue nil; " \
    "next false unless hijos; caras = hijos.grep(Sketchup::Face).count; d = pi_dimensiones(ent, Geom::Transformation.new); " \
    "(caras - #{info[:caras]}).abs <= 2 && (d[:largo] - #{info[:largo]}).abs < 0.05 && " \
    "(d[:ancho] - #{info[:ancho]}).abs < 0.05 && (d[:grosor_min] - #{info[:grosor]}).abs < 0.03 }, " \
    "tag: \"#{tag_limpio}\" },\n"
  linea_precio = "    \"#{tag_limpio}\" => #{precio_num},\n"

  contenido = contenido.sub(marcador_huellas) { |m| m + linea_huella }
  contenido = contenido.sub(marcador_precios) { |m| m + linea_precio }

  respaldo = "#{main_path}.bak_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
  FileUtils.mkdir_p(File.dirname(respaldo))
  FileUtils.cp(main_path, respaldo)
  File.write(main_path, contenido)

  begin
    load main_path
  rescue StandardError => error
    return {
      ok: false,
      error: "Se guardó en el archivo pero algo salió mal al recargarlo en caliente: #{error.message}\n" \
        "Respaldo del archivo anterior en: #{respaldo}\nRevisa el archivo o reinicia SketchUp."
    }
  end

  { ok: true, tag: tag_limpio, respaldo: respaldo }
rescue StandardError => error
  { ok: false, error: error.message }
end

# ==============================================================
# FUNCIÓN COMPARTIDA: Mostrar el reporte (el mismo texto que antes solo
# salía por consola, vía pi_log) en un diálogo gráfico -con una sección
# aparte para los DESCONOCIDOS: seleccionarlos en el modelo para verlos, o
# generarles su .txt de inspección profunda (mismo formato que
# inspect_geometry.rb) para poder pasárselo a la IA y que agregue una
# regla nueva-.
# ==============================================================
def pi_mostrar_reporte(texto, ruta_txt)
  unless defined?(UI::HtmlDialog)
    UI.messagebox(texto)
    return
  end
  @pi_dialogo_reporte&.close
  @pi_dialogo_reporte = UI::HtmlDialog.new(
    dialog_title: 'Reporte de Inventario y Costos - Play Idea',
    preferences_key: 'PlayIdeaAutoEtiquetadoReporte',
    scrollable: true,
    resizable: true,
    width: 760,
    height: 820,
    style: UI::HtmlDialog::STYLE_DIALOG
  )
  @pi_dialogo_reporte.set_file(File.join(__dir__, 'reporte.html'))
  @pi_dialogo_reporte.add_action_callback('ready') do |_action_context|
    @pi_dialogo_reporte.execute_script(
      "mostrarReporte(#{JSON.generate(texto: texto, ruta: ruta_txt, desconocidos: @pi_desconocidos || [])})"
    )
  end
  @pi_dialogo_reporte.add_action_callback('cerrar') { |_action_context| @pi_dialogo_reporte.close }
  @pi_dialogo_reporte.add_action_callback('seleccionar_desconocido') do |_action_context, entity_id|
    model = Sketchup.active_model
    ent = pi_buscar_por_entity_id(model.active_entities, entity_id)
    if ent
      model.selection.clear
      model.selection.add(ent)
      model.active_view.zoom(model.selection)
      @pi_dialogo_reporte.execute_script("marcarSeleccionado(#{JSON.generate(entity_id)})")
    else
      UI.messagebox('Esa pieza ya no existe en el modelo -pudo borrarse o el modelo se recargó desde el auto-etiquetado.')
    end
  end
  @pi_dialogo_reporte.add_action_callback('inspeccionar_desconocido') do |_action_context, entity_id|
    model = Sketchup.active_model
    ent = pi_buscar_por_entity_id(model.active_entities, entity_id)
    if ent
      model.selection.clear
      model.selection.add(ent)
      model.active_view.zoom(model.selection)
      ruta = pi_inspeccionar_entidad(ent)
      @pi_dialogo_reporte.execute_script("marcarInspeccionado(#{JSON.generate(entity_id: entity_id, ruta: ruta)})")
    else
      UI.messagebox('Esa pieza ya no existe en el modelo -pudo borrarse o el modelo se recargó desde el auto-etiquetado.')
    end
  end
  @pi_dialogo_reporte.add_action_callback('guardar_regla_desconocido') do |_action_context, payload|
    resultado = pi_guardar_regla_desconocido(payload['entity_id'], payload['tag'], payload['precio'])
    @pi_dialogo_reporte.execute_script("marcarReglaGuardada(#{JSON.generate(payload['entity_id'])}, #{JSON.generate(resultado)})")
  end
  @pi_dialogo_reporte.show
rescue StandardError => error
  UI.messagebox("No fue posible mostrar el reporte:\n#{error.message}")
  puts error.full_message
end

# ==============================================================
# ACCIÓN 1: Auto-Etiquetar (Tags + Carpetas)
# ==============================================================
def pi_auto_etiquetar
model = Sketchup.active_model
selection = model.selection

if selection.empty?
UI.messagebox("Por favor selecciona la estructura para auto-etiquetarla.")
return
end

layers = model.layers
@pi_tubos = 0; @pi_paneles = 0; @pi_conectores = 0; @pi_otros = 0
@pi_total_nodos = 0
@pi_longitud_tubos = 0
@pi_longitud_redondo = 0
@pi_sub_paneles = Hash.new(0)
@pi_paneles_mat = Hash.new(0)
@pi_sub_exactos = Hash.new(0)
@pi_desconocidos = []

  # --- HELPER: Verificar si tiene un subgrupo con nombre específico (Búsqueda Profunda) ---
  def pi_tiene_subgrupo_nombre(ent, nombre)
    return false unless ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities rescue []
    # 1. Buscar en hijos directos
    found = hijos.any? { |h| (h.respond_to?(:name) && h.name && h.name.include?(nombre)) || (h.respond_to?(:definition) && h.definition.name.include?(nombre)) }
    return true if found
    # 2. Buscar recursivamente
    hijos.any? { |h| (h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance)) && pi_tiene_subgrupo_nombre(h, nombre) }
  end

  # --- HELPER: Contar subgrupos con un número específico de caras (Búsqueda Profunda) ---
  def pi_cuenta_subgrupos_con_caras(ent, num_caras, tolerancia = 0)
    return 0 unless ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities rescue []
    conteo = 0
    hijos.each do |h|
      if h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance)
        sub_hijos = h.is_a?(Sketchup::Group) ? h.entities : h.definition.entities rescue []
        n = sub_hijos.grep(Sketchup::Face).length
        # Si este subgrupo coincide, lo contamos
        if (n - num_caras).abs <= tolerancia
          conteo += 1
        end
        # Siempre buscamos más profundo (incluso si este ya coincidió, por si hay más adentro)
        conteo += pi_cuenta_subgrupos_con_caras(h, num_caras, tolerancia)
      end
    end
    conteo
  end

  # --- HELPER: Limpiar tags internos para compatibilidad con Twinmotion ---
  # Mueve toda la geometría interna a Layer0 para que la visibilidad dependa solo del contenedor principal.
  def pi_limpiar_tags_internos(ent, layer0)
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities rescue nil
    return unless hijos
    hijos.each do |h|
      h.layer = layer0 if h.respond_to?(:layer=)
      if h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance)
        pi_limpiar_tags_internos(h, layer0)
      end
    end
  end

  layer0 = model.layers[0]

# CORRECCIÓN DE SCOPE: Definición de huellas antes de los ciclos de clasificación
huellas_estructurales = [
{ descripcion: "Panel_interactivo_yelcot (agregada desde el plugin: 0 caras, 1.17 x 1.17 x 0.04 m)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities) rescue nil; next false unless hijos; caras = hijos.grep(Sketchup::Face).count; d = pi_dimensiones(ent, Geom::Transformation.new); (caras - 0).abs <= 2 && (d[:largo] - 1.17).abs < 0.05 && (d[:ancho] - 1.17).abs < 0.05 && (d[:grosor_min] - 0.04).abs < 0.03 }, tag: "Panel_interactivo_yelcot" },
{ descripcion: "alberca_d_epelotas_area_de_bebes (agregada desde el plugin: 0 caras, 1.47 x 1.17 x 0.25 m)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities) rescue nil; next false unless hijos; caras = hijos.grep(Sketchup::Face).count; d = pi_dimensiones(ent, Geom::Transformation.new); (caras - 0).abs <= 2 && (d[:largo] - 1.47).abs < 0.05 && (d[:ancho] - 1.17).abs < 0.05 && (d[:grosor_min] - 0.25).abs < 0.03 }, tag: "alberca_d_epelotas_area_de_bebes" },
{ descripcion: "media_monta_a_cocodrilo (agregada desde el plugin: 0 caras, 0.92 x 0.6 x 0.55 m)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities) rescue nil; next false unless hijos; caras = hijos.grep(Sketchup::Face).count; d = pi_dimensiones(ent, Geom::Transformation.new); (caras - 0).abs <= 2 && (d[:largo] - 0.92).abs < 0.05 && (d[:ancho] - 0.6).abs < 0.05 && (d[:grosor_min] - 0.55).abs < 0.03 }, tag: "media_monta_a_cocodrilo" },
{ descripcion: "Alberca_de_esponjas_de_medida_1_94___4_26___0_50 (agregada desde el plugin: 0 caras, 4.48 x 2.15 x 0.79 m)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities) rescue nil; next false unless hijos; caras = hijos.grep(Sketchup::Face).count; d = pi_dimensiones(ent, Geom::Transformation.new); (caras - 0).abs <= 2 && (d[:largo] - 4.48).abs < 0.05 && (d[:ancho] - 2.15).abs < 0.05 && (d[:grosor_min] - 0.79).abs < 0.03 }, tag: "Alberca_de_esponjas_de_medida_1_94___4_26___0_50" },
{ descripcion: "Tina_de_alberca_de_esponjas (agregada desde el plugin: 28 caras, 5.08 x 1.95 x 0.65 m)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities) rescue nil; next false unless hijos; caras = hijos.grep(Sketchup::Face).count; d = pi_dimensiones(ent, Geom::Transformation.new); (caras - 28).abs <= 2 && (d[:largo] - 5.08).abs < 0.05 && (d[:ancho] - 1.95).abs < 0.05 && (d[:grosor_min] - 0.65).abs < 0.03 }, tag: "Tina_de_alberca_de_esponjas" },
{ descripcion: "topes_para_acceso_a_tumbling (agregada desde el plugin: 0 caras, 1.04 x 0.76 x 0.62 m)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities) rescue nil; next false unless hijos; caras = hijos.grep(Sketchup::Face).count; d = pi_dimensiones(ent, Geom::Transformation.new); (caras - 0).abs <= 2 && (d[:largo] - 1.04).abs < 0.05 && (d[:ancho] - 0.76).abs < 0.05 && (d[:grosor_min] - 0.62).abs < 0.03 }, tag: "topes_para_acceso_a_tumbling" },
{ descripcion: "Ducto Recto (sub-grupo 'Diferencia')", condicion: ->(ent) { pi_tiene_subgrupo_nombre(ent, "Diferencia") }, tag: "Ducto_Recto" },
{ descripcion: "Dona con Cadena (~102/26 x2 + ~2602 x1)", condicion: ->(ent) { (pi_cuenta_subgrupos_con_caras(ent, 102) >= 2 || pi_cuenta_subgrupos_con_caras(ent, 26) >= 2) && pi_cuenta_subgrupos_con_caras(ent, 2602, 50) >= 1 }, tag: "Dona_con_Cadena" },
{ descripcion: "Taza Giratoria (~12842 x2)", condicion: ->(ent) { pi_cuenta_subgrupos_con_caras(ent, 12842, 100) >= 2 }, tag: "Taza_Giratoria" },
{ descripcion: "Hormiguero (~11 caras x2)", condicion: ->(ent) { pi_cuenta_subgrupos_con_caras(ent, 11, 2) >= 2 }, tag: "Hormiguero" },
{ descripcion: "Montana Cocodrilo (~107 x10 + ~198 x1)", condicion: ->(ent) { pi_cuenta_subgrupos_con_caras(ent, 107, 8) >= 10 && pi_cuenta_subgrupos_con_caras(ent, 198, 10) >= 1 }, tag: "Montana_Cocodrilo" },
{ descripcion: "Zapatera FV (~5355 caras)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); n_sub = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count; caras = hijos.grep(Sketchup::Face).count; n_sub == 0 && (caras - 5355).abs <= 150 }, tag: "Zapatera_FV" },
{ descripcion: "Puerta Giratoria (~6 x2 + ~705 x1)", condicion: ->(ent) { pi_cuenta_subgrupos_con_caras(ent, 6, 1) >= 2 && pi_cuenta_subgrupos_con_caras(ent, 705, 30) >= 1 }, tag: "Puerta_Giratoria" },
{ descripcion: "Rodillo Galleta (~702 x1 + ~1302 x1)", condicion: ->(ent) { pi_cuenta_subgrupos_con_caras(ent, 702, 20) >= 1 && pi_cuenta_subgrupos_con_caras(ent, 1302, 30) >= 1 }, tag: "Rodillo_Galleta" },
{ descripcion: "Torre de Cubos (~54 x2+ + ~102 x1)", condicion: ->(ent) { pi_cuenta_subgrupos_con_caras(ent, 54, 5) >= 2 && pi_cuenta_subgrupos_con_caras(ent, 102, 10) >= 1 }, tag: "Torre_Cubos" },
{ descripcion: "Rodillo (~102 x1 + ~1302 x1)", condicion: ->(ent) { pi_cuenta_subgrupos_con_caras(ent, 102, 10) >= 1 && pi_cuenta_subgrupos_con_caras(ent, 1302, 30) >= 1 && pi_cuenta_subgrupos_con_caras(ent, 702, 20) == 0 }, tag: "Rodillo" },
{ descripcion: "Cuarto Piramide (~1845 caras)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); n_sub = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count; caras = hijos.grep(Sketchup::Face).count; n_sub == 0 && (caras - 1845).abs <= 100 }, tag: "Cuarto_Piramide" },
{ descripcion: "Cubo (hijos B#1, C, D, 1, 2)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); nombres = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.flat_map { |h| [h.respond_to?(:definition) ? h.definition.name.to_s : "", h.name.to_s].reject(&:empty?) }; ["B#1", "C", "D", "1", "2"].all? { |n| nombres.include?(n) } }, tag: "Cubo" },
{ descripcion: "Tope Chico (~14 caras, <0.6m)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); n_sub = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count; caras = hijos.grep(Sketchup::Face).count; if n_sub == 0 && (caras - 14).abs <= 4; t = ent.transformation; xs = Geom::Vector3d.new(1,0,0).transform(t).length; ys = Geom::Vector3d.new(0,1,0).transform(t).length; zs = Geom::Vector3d.new(0,0,1).transform(t).length; lb = ent.respond_to?(:definition) ? ent.definition.bounds : ent.bounds; dims = [(lb.width*xs*0.0254),(lb.height*ys*0.0254),(lb.depth*zs*0.0254)].sort; dims[2] < 0.6; else; false; end }, tag: "Tope_Chico" },
{ descripcion: "Puerta Hawaiana (7 tiras)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities).select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }; hijos.count == 7 && hijos.all? { |h| (h.is_a?(Sketchup::Group) ? h.entities : h.definition.entities).grep(Sketchup::Face).count == 1 } }, tag: "Puerta_Hawaiana" },
{ descripcion: "Pelota Individual (~288 caras)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); n_sub = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count; caras = hijos.grep(Sketchup::Face).count; if n_sub == 0 && (caras - 288).abs <= 20; t = ent.transformation; xs = Geom::Vector3d.new(1,0,0).transform(t).length; ys = Geom::Vector3d.new(0,1,0).transform(t).length; zs = Geom::Vector3d.new(0,0,1).transform(t).length; lb = ent.respond_to?(:definition) ? ent.definition.bounds : ent.bounds; dims = [(lb.width*xs*0.0254),(lb.height*ys*0.0254),(lb.depth*zs*0.0254)].sort; dims[2] < 0.15; else; false; end }, tag: "Pelota_Plastico" },
{ descripcion: "Contenedor de Pelotas (>=10 hijos pelotas)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); hijos_gc = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }; caras_directas = hijos.grep(Sketchup::Face).count; if caras_directas == 0 && hijos_gc.count >= 10; hijos_gc.first(5).all? { |h| sub = h.is_a?(Sketchup::Group) ? h.entities : h.definition.entities; sub_n = sub.select { |s| s.is_a?(Sketchup::Group) || s.is_a?(Sketchup::ComponentInstance) }.count; sub_c = sub.grep(Sketchup::Face).count; sub_n == 0 && (sub_c - 288).abs <= 20 }; else; false; end }, tag: "Pelota_Plastico" },
{ descripcion: "Pelotas Sueltas (Geometria Masiva sin grupos)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); n_sub = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count; caras = hijos.grep(Sketchup::Face).count; n_sub == 0 && caras > 5000 }, tag: "Pelota_Plastico" },
{ descripcion: "Panel Triangular (~296 caras)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); n_sub = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count; caras = hijos.grep(Sketchup::Face).count; if n_sub == 0 && (caras - 296).abs <= 15; t = ent.transformation; xs = Geom::Vector3d.new(1,0,0).transform(t).length; ys = Geom::Vector3d.new(0,1,0).transform(t).length; zs = Geom::Vector3d.new(0,0,1).transform(t).length; lb = ent.respond_to?(:definition) ? ent.definition.bounds : ent.bounds; dims = [(lb.width*xs*0.0254),(lb.height*ys*0.0254),(lb.depth*zs*0.0254)].sort; dims[2] > 1.0 && dims[0] < 0.10; else; false; end }, tag: "Panel_Triangular" },
{ descripcion: "Bandera (6 caras planas)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); n_sub = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count; caras = hijos.grep(Sketchup::Face).count; if n_sub == 0 && caras == 6; t = ent.transformation; xs = Geom::Vector3d.new(1,0,0).transform(t).length; ys = Geom::Vector3d.new(0,1,0).transform(t).length; zs = Geom::Vector3d.new(0,0,1).transform(t).length; lb = ent.respond_to?(:definition) ? ent.definition.bounds : ent.bounds; dims = [(lb.width*xs*0.0254).round(4),(lb.height*ys*0.0254).round(4),(lb.depth*zs*0.0254).round(4)].sort; dims[0] < 0.02 && dims[1] > 0.3 && dims[2] > 0.5; else; false; end }, tag: "banderas" },
{ descripcion: "Rampa (6 caras, larga >2m)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); n_sub = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count; caras = hijos.grep(Sketchup::Face).count; if n_sub == 0 && caras == 6; t = ent.transformation; xs = Geom::Vector3d.new(1,0,0).transform(t).length; ys = Geom::Vector3d.new(0,1,0).transform(t).length; zs = Geom::Vector3d.new(0,0,1).transform(t).length; lb = ent.respond_to?(:definition) ? ent.definition.bounds : ent.bounds; dims = [(lb.width*xs*0.0254),(lb.height*ys*0.0254),(lb.depth*zs*0.0254)].sort; dims[0] < 0.05 && dims[2] > 2.0; else; false; end }, tag: "Rampa" },
{ descripcion: "Rampa 2.82m (6 caras)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); caras = hijos.grep(Sketchup::Face).count; d = pi_dimensiones(ent, Geom::Transformation.new); caras == 6 && (d[:largo] - 2.82).abs < 0.05 && (d[:ancho] - 1.1).abs < 0.05 }, tag: "Rampa_2.82x1.1" },
{ descripcion: "Modulo Ligas (52 caras)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); caras = hijos.grep(Sketchup::Face).count; (caras - 52).abs <= 2 }, tag: "Modulo_Ligas" },
{ descripcion: "Rodillo Caramelo (~114x16 + ~2602x1)", condicion: ->(ent) { pi_cuenta_subgrupos_con_caras(ent, 114) >= 15 && pi_cuenta_subgrupos_con_caras(ent, 2602, 50) >= 1 }, tag: "Rodillo_Caramelo" },
{ descripcion: "Rodillo Entrada (1302 caras, 1.06x0.38)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); n_sub = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count; caras = hijos.grep(Sketchup::Face).count; d = pi_dimensiones(ent, Geom::Transformation.new); n_sub == 0 && (caras - 1302).abs <= 10 && (d[:largo] - 1.062).abs < 0.1 && (d[:ancho] - 0.381).abs < 0.1 }, tag: "Rodillo_Entrada" },
{ descripcion: "Rodillo Entrada Delgado (1302 caras, 1.06x0.24)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); n_sub = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count; caras = hijos.grep(Sketchup::Face).count; d = pi_dimensiones(ent, Geom::Transformation.new); n_sub == 0 && (caras - 1302).abs <= 10 && (d[:largo] - 1.06).abs < 0.1 && (d[:ancho] - 0.24).abs < 0.1 }, tag: "Rodillo_Entrada" },
{ descripcion: "Costal Doble Cadena (~33817x2 + ~4608x1)", condicion: ->(ent) { pi_cuenta_subgrupos_con_caras(ent, 33817, 100) >= 2 && pi_cuenta_subgrupos_con_caras(ent, 4608, 50) >= 1 }, tag: "Costal_Doble_Cadena" },
{ descripcion: "Costal Cruzado (ID por Huella)", condicion: ->(ent) { pi_cuenta_subgrupos_con_caras(ent, 33817, 100) >= 2 && pi_cuenta_subgrupos_con_caras(ent, 4608, 50) >= 1 }, tag: "Costal_Cruzado" },
{ descripcion: "Costal Chico (~33817x1 + ~4608x1)", condicion: ->(ent) { pi_cuenta_subgrupos_con_caras(ent, 33817, 100) == 1 && pi_cuenta_subgrupos_con_caras(ent, 4608, 50) >= 1 }, tag: "Costal_Chico" },
{ descripcion: "Tobogan de Fibra (~2602x2 + ~3600x8+)", condicion: ->(ent) { pi_cuenta_subgrupos_con_caras(ent, 2602, 50) >= 2 && pi_cuenta_subgrupos_con_caras(ent, 3600, 100) >= 8 }, tag: "Tobogan_Fibra" },
{ descripcion: "Panel Entrada Curvo Grande (2 caras, ~3.2x1.17)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); caras = hijos.grep(Sketchup::Face).count; d = pi_dimensiones(ent, Geom::Transformation.new); caras == 2 && (d[:largo] - 3.2).abs < 0.1 && (d[:ancho] - 1.17).abs < 0.1 }, tag: "Panel_Entrada_Curvo_Grande" },
{ descripcion: "Panel Entrada Curvo Chico (2 caras, ~1.63x1.17)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); caras = hijos.grep(Sketchup::Face).count; d = pi_dimensiones(ent, Geom::Transformation.new); caras == 2 && (d[:largo] - 1.63).abs < 0.1 && (d[:ancho] - 1.17).abs < 0.1 }, tag: "Panel_Entrada_Curvo_Chico" },
{ descripcion: "Piramide Completa (~158x6)", condicion: ->(ent) { pi_cuenta_subgrupos_con_caras(ent, 158, 10) >= 6 }, tag: "Piramide_Completa" },
{ descripcion: "Plataforma 1.19x0.7 (6 caras)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); n_sub = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count; caras = hijos.grep(Sketchup::Face).count; if n_sub == 0 && (caras - 6).abs <= 2; d = pi_dimensiones(ent, Geom::Transformation.new); (d[:largo] - 1.19).abs < 0.1 && (d[:ancho] - 0.7).abs < 0.1; else; false; end }, tag: "1.19x0.7" },
{ descripcion: "Plataforma 1.3x1.25 (29 caras)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); n_sub = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count; caras = hijos.grep(Sketchup::Face).count; if n_sub == 0 && (caras - 29).abs <= 2; d = pi_dimensiones(ent, Geom::Transformation.new); (d[:largo] - 1.3).abs < 0.1 && (d[:ancho] - 1.25).abs < 0.1; else; false; end }, tag: "1.3x1.25" },
{ descripcion: "Tope Largo (~14 caras, >0.6m)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); n_sub = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count; caras = hijos.grep(Sketchup::Face).count; if n_sub == 0 && (caras - 14).abs <= 4; d = pi_dimensiones(ent, Geom::Transformation.new); d[:largo] >= 0.6; else; false; end }, tag: "Tope_Largo" },
{ descripcion: "Panel con Ventanas (1 cara calada)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); caras = hijos.grep(Sketchup::Face).count; aristas = hijos.grep(Sketchup::Edge).count; caras == 1 && aristas > 50 }, tag: "Panel_Multiventanas" },
{ descripcion: "Colchoneta de Tumbling Especial (pieza 'Difference', 0.57x1.56x1.56, grosor fuera del rango de la regla dinamica)", condicion: ->(ent) { d = pi_dimensiones(ent, Geom::Transformation.new); (d[:grosor_min] - 0.57).abs < 0.03 && (d[:ancho] - 1.56).abs < 0.05 && (d[:largo] - 1.56).abs < 0.05 }, tag: "Colchoneta_Tumbling_Especial" },
{ descripcion: "Colchoneta (Dinamica por Medida)", condicion: ->(ent) { d = pi_dimensiones(ent, Geom::Transformation.new); d[:grosor_min] >= 0.1 && d[:grosor_min] <= 0.5 && d[:largo] > 1.5 && d[:ancho] > 1.0 }, tag: ->(ent) { d = pi_dimensiones(ent, Geom::Transformation.new); "Colchoneta_#{d[:largo]}x#{d[:ancho]}" } },
{ descripcion: "Panel Gato (~2602 caras x9 + ~1302 caras x9)", condicion: ->(ent) { pi_cuenta_subgrupos_con_caras(ent, 2602, 50) >= 8 && pi_cuenta_subgrupos_con_caras(ent, 1302, 30) >= 8 }, tag: "Gato" },
{ descripcion: "Modulo 4 Lianas (4 columpios de 306 caras)", condicion: ->(ent) { pi_cuenta_subgrupos_con_caras(ent, 306, 5) == 4 && pi_cuenta_subgrupos_con_caras(ent, 26, 2) == 8 }, tag: "Modulo_4_Lianas" },
{ descripcion: "Puerta de Lona Tipo Raton (21 caras, ~1.16x1.09m, grosor < 1cm)", condicion: ->(ent) { hijos = (ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities); n_sub = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count; caras = hijos.grep(Sketchup::Face).count; d = pi_dimensiones(ent, Geom::Transformation.new); n_sub == 0 && (caras - 21).abs <= 2 && (d[:largo] - 1.16).abs < 0.1 && (d[:ancho] - 1.09).abs < 0.1 && d[:grosor_min] < 0.01 }, tag: "Puerta_Raton" }
]

model.start_operation('PI Auto Etiquetar', true)

# PASO 0: Limpiar TODAS las tags y carpetas (excepto Layer0/Untagged)
puts "🧹 PASO 0: Limpiando panel de tags y subcarpetas..."

# Función auxiliar para limpieza profunda de carpetas
def pi_limpiar_carpetas_recursivo(layers_obj)
  loop do
    carpetas = []
    layers_obj.each_folder { |f| carpetas << f }
    break if carpetas.empty?
    carpetas.each do |f|
      # Intentar borrar subcarpetas primero si existen
      if f.respond_to?(:folders)
        f.folders.each { |sub| layers_obj.remove_folder(sub) rescue nil }
      end
      layers_obj.remove_folder(f) rescue nil
    end
  end
end

# 1. Mover TODAS las entidades del modelo a Layer0
layer0 = layers["Layer0"] || layers["Untagged"]
model.entities.each { |e| e.layer = layer0 if e.respond_to?(:layer=) }
model.definitions.each { |d| d.entities.each { |e| e.layer = layer0 if e.respond_to?(:layer=) } }

# 2. Eliminar todas las carpetas y subcarpetas de forma recursiva
pi_limpiar_carpetas_recursivo(layers)

# 3. Eliminar todas las tags excepto la default
tags_a_borrar = []
layers.each { |l| tags_a_borrar << l unless l.name == "Layer0" || l.name == "Untagged" }
tags_a_borrar.each { |l| layers.remove(l, true) rescue nil }

puts " ✅ Panel purgado: Tags y carpetas (incluyendo subniveles) eliminados."

layers = model.layers

# PASO 1.1: Clasificar Tubos
puts "✅ PASO 1.1: Clasificando Tubos por Nivel..."
folder_tubos = layers.add_folder("Tubos")
@pi_tubos_bounds = []
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
  next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
  next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
  d = pi_dimensiones(ent, Geom::Transformation.new)
  hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
  caras = hijos.grep(Sketchup::Face).count
  es_tubo_recto = d[:grosor_max] <= 0.20 && d[:grosor_max] > 0.01 && d[:largo] >= (d[:grosor_max] * 1.5) && (caras - 14).abs > 2
  subgrupos = hijos.grep(Sketchup::Group)
  es_tubo_curvo = caras == 0 && subgrupos.size == 2 && subgrupos.all? { |sg| sg.entities.grep(Sketchup::Face).count == 1562 }

  if es_tubo_recto || es_tubo_curvo
    # Determinar nivel por altura mínima (redondeado a 1 decimal)
    nivel_z = (ent.bounds.min.z.to_m.round(1))
    tag_name = "Tubos_Nivel_#{nivel_z}m"
    tag_obj = layers[tag_name] || layers.add(tag_name)
    tag_obj.folder = folder_tubos
    
    ent.layer = tag_obj
    pi_limpiar_tags_internos(ent, layer0)
    @pi_tubos += 1
    @pi_longitud_tubos += d[:largo]
    @pi_tubos_bounds << ent.bounds
    puts " ✅ Tubo en Nivel #{nivel_z}m: #{ent.name.empty? ? ent.definition.name : ent.name} (#{d[:largo]}m)" rescue nil
  end
end

# PASO 1.2: Clasificar Conectores
puts "✅ PASO 1.2: Clasificando Conectores..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
if d[:grosor_max] < 0.15 && d[:largo] < 0.15 && (d[:largo] - d[:ancho]).abs < 0.05
  tag_conectores = layers["Conectores"] || layers.add("Conectores")
  tag_conectores.folder = folder_tubos
  ent.layer = tag_conectores
  pi_limpiar_tags_internos(ent, layer0)
  @pi_conectores += 1
  @pi_total_nodos += 1
  puts " ✅ Conector: #{ent.name.empty? ? ent.definition.name : ent.name}" rescue nil
end
end

# PASO 1.2.1: Si no hay conectores explícitos, estimar por intersecciones
if @pi_total_nodos == 0 && @pi_tubos_bounds && !@pi_tubos_bounds.empty?
  puts "✅ PASO 1.2.1: Calculando Conectores por Intersecciones de Tubos..."
  nodos = []
  @pi_tubos_bounds.each_with_index do |b1, i|
    @pi_tubos_bounds[(i+1)..-1].each do |b2|
      inter = b1.intersect(b2)
      if inter.valid? && !inter.empty?
        centro = inter.center
        unless nodos.any? { |n| n.distance(centro) < 0.20 }
          nodos << centro
        end
      end
    end
  end
  @pi_total_nodos = nodos.size
  @pi_conectores = @pi_total_nodos
  puts " ✅ Nodos calculados por intersección: #{@pi_total_nodos}"
end

# PASO 1.2.5: Clasificar Banderas por medida específica
puts "✅ PASO 1.2.5: Clasificando Banderas por medida..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
# Criterio bandera por medida: ancho ~0.52 y largo en [1.14, 1.17, 1.2]
if (d[:ancho] - 0.52).abs < 0.01 && [1.14, 1.17, 1.20].any? { |l| (d[:largo] - l).abs < 0.05 }
tag = layers["banderas"] || layers.add("banderas")
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
end
end

# PASO 1.3: Clasificar Paneles (por medida aproximada)
puts "✅ PASO 1.3: Clasificando Paneles y Mallas..."
paneles_estandar = [0.60, 0.49, 1.14, 1.17, 0.94, 0.61, 0.39]
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count

# Solo procesar si es algo "plano" (grosor < 15cm)
next unless d[:grosor_min] < 0.15

mat_nombre = pi_leer_material(ent)
alias_mat = {"gra1 cópia" => "malla", "malla" => "malla"}[mat_nombre]

# Decisión: Si es malla por material, clasificar sin importar caras.
# Si no es malla, solo clasificar si tiene 6 caras (paneles estándar)
if alias_mat
    # Caso 1: Es una malla por material
    nivel_z = (ent.bounds.min.z.to_m.round(1))
    nombre_capa = "malla_#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
    tag = layers[nombre_capa] || layers.add(nombre_capa)
    ent.layer = tag
    pi_limpiar_tags_internos(ent, layer0)
    @pi_paneles_mat[nombre_capa] += 1
    @pi_longitud_redondo += (d[:largo] + d[:ancho]) * 2
    puts " ✅ Malla detectada: #{nombre_capa} (Material: #{mat_nombre})"
elsif caras == 6 && paneles_estandar.any? { |s| (d[:largo] - s).abs < 0.05 }
  # Caso 2: Es un panel estándar por medida
  nivel_z = (ent.bounds.min.z.to_m.round(1))
  nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
  tag = layers[nombre_capa] || layers.add(nombre_capa)
  ent.layer = tag
  pi_limpiar_tags_internos(ent, layer0)
  @pi_paneles += 1; @pi_sub_paneles[nombre_capa] += 1
  puts " ✅ Panel #{nombre_capa}: #{ent.name.empty? ? ent.definition.name : ent.name}" rescue nil
end
end

  # PASO 1.3.1: Clasificar Plataformas por Huella Digital (394 caras) - Tipo A (1.17x1.17)
  puts "✅ PASO 1.3.1: Clasificando Plataformas Especiales (1.17x1.17)..."
  model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
    
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
    caras = hijos.grep(Sketchup::Face).count
    d = pi_dimensiones(ent, Geom::Transformation.new)
    
    # Huella Digital: ~394 caras, medida ~1.17x1.17m y grosor ~0.05m
    if (caras - 394).abs <= 2 && (d[:largo] - 1.17).abs < 0.05 && (d[:ancho] - 1.17).abs < 0.05 && (d[:grosor_min] - 0.05).abs < 0.01
      nivel_z = (ent.bounds.min.z.to_m.round(1))
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.1): #{nombre_capa}"
    end
  end

  # PASO 1.3.2: NUEVA REGLA - Clasificar Plataformas por Huella Digital (394 caras) - Tipo B (0.6x0.39)
  puts "✅ PASO 1.3.2: Clasificando Plataformas Especiales (0.6x0.39)..."
  model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
    
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
    caras = hijos.grep(Sketchup::Face).count
    d = pi_dimensiones(ent, Geom::Transformation.new)
    
    # Huella Digital: ~394 caras, medida ~0.60x0.39m y grosor ~0.05m
    if (caras - 394).abs <= 2 && (d[:largo] - 0.60).abs < 0.05 && (d[:ancho] - 0.39).abs < 0.05 && (d[:grosor_min] - 0.05).abs < 0.01
      nivel_z = (ent.bounds.min.z.to_m.round(1))
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.2): #{nombre_capa}"
    end
  end

  # PASO 1.3.3: NUEVA REGLA - Clasificar Plataformas por Huella Digital (394 caras) - Tipo C (1.17x0.61)
  puts "✅ PASO 1.3.3: Clasificando Plataformas Especiales (1.17x0.61)..."
  model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
    
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
    caras = hijos.grep(Sketchup::Face).count
    d = pi_dimensiones(ent, Geom::Transformation.new)
    
    # Huella Digital: ~394 caras, medida ~1.17x0.61m y grosor ~0.05m
    if (caras - 394).abs <= 2 && (d[:largo] - 1.17).abs < 0.05 && (d[:ancho] - 0.61).abs < 0.05 && (d[:grosor_min] - 0.05).abs < 0.01
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.3): #{nombre_capa}"
    end
  end

  # PASO 1.3.3b: NUEVA REGLA - Clasificar Plataformas por Huella Digital (394 caras) - Tipo D (1.17x0.88)
  puts "✅ PASO 1.3.3b: Clasificando Plataformas Especiales (1.17x0.88)..."
  model.active_entities.each do |ent|
    next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
    
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities rescue next
    caras = hijos.grep(Sketchup::Face).count rescue next
    d = pi_dimensiones(ent, Geom::Transformation.new)
    
    # Huella Digital: ~394 caras, medida ~1.17x0.88m y grosor ~0.05m
    if (caras - 394).abs <= 2 && (d[:largo] - 1.17).abs < 0.05 && (d[:ancho] - 0.88).abs < 0.05 && (d[:grosor_min] - 0.05).abs < 0.01
      nivel_z = (ent.bounds.min.z.to_m.round(1))
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.3b): #{nombre_capa}"
    end
  end

  # PASO 1.3.3c: NUEVA REGLA - Clasificar Plataformas por Huella Digital (394 caras) - Tipo E (0.88x0.45)
  puts "✅ PASO 1.3.3c: Clasificando Plataformas Especiales (0.88x0.45)..."
  model.active_entities.each do |ent|
    next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
    
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities rescue next
    caras = hijos.grep(Sketchup::Face).count rescue next
    d = pi_dimensiones(ent, Geom::Transformation.new)
    
    # Huella Digital: ~394 caras, medida ~0.88x0.45m y grosor ~0.05m
    if (caras - 394).abs <= 2 && (d[:largo] - 0.88).abs < 0.05 && (d[:ancho] - 0.45).abs < 0.05 && (d[:grosor_min] - 0.05).abs < 0.01
      nivel_z = (ent.bounds.min.z.to_m.round(1))
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.3c): #{nombre_capa}"
    end
  end

  # PASO 1.3.3d: NUEVA REGLA - Clasificar Plataformas por Huella Digital (394 caras) - Tipo F (1.17x0.45)
  puts "✅ PASO 1.3.3d: Clasificando Plataformas Especiales (1.17x0.45)..."
  model.active_entities.each do |ent|
    next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
    
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities rescue next
    caras = hijos.grep(Sketchup::Face).count rescue next
    d = pi_dimensiones(ent, Geom::Transformation.new)
    
    # Huella Digital: ~394 caras, medida ~1.17x0.45m y grosor ~0.05m
    if (caras - 394).abs <= 2 && (d[:largo] - 1.17).abs < 0.05 && (d[:ancho] - 0.45).abs < 0.05 && (d[:grosor_min] - 0.05).abs < 0.01
      nivel_z = (ent.bounds.min.z.to_m.round(1))
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.3d): #{nombre_capa}"
    end
  end

  # PASO 1.3.3e: NUEVA REGLA - Clasificar Plataformas por Huella Digital (394 caras) - Tipo G (0.6x0.45)
  puts "✅ PASO 1.3.3e: Clasificando Plataformas Especiales (0.6x0.45)..."
  model.active_entities.each do |ent|
    next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
    
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities rescue next
    caras = hijos.grep(Sketchup::Face).count rescue next
    d = pi_dimensiones(ent, Geom::Transformation.new)
    
    # Huella Digital: ~394 caras, medida ~0.60x0.45m y grosor ~0.05m
    if (caras - 394).abs <= 2 && (d[:largo] - 0.60).abs < 0.05 && (d[:ancho] - 0.45).abs < 0.05 && (d[:grosor_min] - 0.05).abs < 0.01
      nivel_z = (ent.bounds.min.z.to_m.round(1))
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.3e): #{nombre_capa}"
    end
  end

  # PASO 1.3.3f: NUEVA REGLA - Clasificar Plataformas por Huella Digital (394 caras) - Tipo H (0.61x0.59)
  puts "✅ PASO 1.3.3f: Clasificando Plataformas Especiales (0.61x0.59)..."
  model.active_entities.each do |ent|
    next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
    
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities rescue next
    caras = hijos.grep(Sketchup::Face).count rescue next
    d = pi_dimensiones(ent, Geom::Transformation.new)
    
    # Huella Digital: ~394 caras, medida ~0.61x0.59m y grosor ~0.05m
    if (caras - 394).abs <= 2 && (d[:largo] - 0.61).abs < 0.05 && (d[:ancho] - 0.59).abs < 0.05 && (d[:grosor_min] - 0.05).abs < 0.01
      nivel_z = (ent.bounds.min.z.to_m.round(1))
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.3f): #{nombre_capa}"
    end
  end
  # PASO 1.3.3g: NUEVA REGLA - Clasificar Plataformas por Huella Digital (394 caras) - Tipo I (1.17x1.0)
  puts "✅ PASO 1.3.3g: Clasificando Plataformas Especiales (1.17x1.0)..."
  model.active_entities.each do |ent|
    next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
    
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities rescue next
    caras = hijos.grep(Sketchup::Face).count rescue next
    d = pi_dimensiones(ent, Geom::Transformation.new)
    
    # Huella Digital: ~394 caras, medida ~1.17x1.00m y grosor ~0.05m
    if (caras - 394).abs <= 2 && (d[:largo] - 1.17).abs < 0.05 && (d[:ancho] - 1.00).abs < 0.05 && (d[:grosor_min] - 0.05).abs < 0.01
      nivel_z = (ent.bounds.min.z.to_m.round(1))
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.3g): #{nombre_capa}"
    end
  end

  # PASO 1.3.3h: NUEVA REGLA - Clasificar Plataformas por Huella Digital (394 caras) - Tipo J (1.17x0.22)
  puts "✅ PASO 1.3.3h: Clasificando Plataformas Especiales (1.17x0.22)..."
  model.active_entities.each do |ent|
    next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
    
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities rescue next
    caras = hijos.grep(Sketchup::Face).count rescue next
    d = pi_dimensiones(ent, Geom::Transformation.new)
    
    # Huella Digital: ~394 caras, medida ~1.17x0.22m y grosor ~0.05m
    if (caras - 394).abs <= 2 && (d[:largo] - 1.17).abs < 0.05 && (d[:ancho] - 0.22).abs < 0.05 && (d[:grosor_min] - 0.05).abs < 0.01
      nivel_z = (ent.bounds.min.z.to_m.round(1))
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.3h): #{nombre_capa}"
    end
  end

  # PASO 1.3.3i: NUEVA REGLA - Clasificar Plataformas por Huella Digital (394 caras) - Tipo K (0.72x0.22)
  puts "✅ PASO 1.3.3i: Clasificando Plataformas Especiales (0.72x0.22)..."
  model.active_entities.each do |ent|
    next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
    
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities rescue next
    caras = hijos.grep(Sketchup::Face).count rescue next
    d = pi_dimensiones(ent, Geom::Transformation.new)
    
    # Huella Digital: ~394 caras, medida ~0.72x0.22m y grosor ~0.05m
    if (caras - 394).abs <= 2 && (d[:largo] - 0.72).abs < 0.05 && (d[:ancho] - 0.22).abs < 0.05 && (d[:grosor_min] - 0.05).abs < 0.01
      nivel_z = (ent.bounds.min.z.to_m.round(1))
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.3i): #{nombre_capa}"
    end
  end

  # PASO 1.3.3j: NUEVA REGLA - Clasificar Plataformas por Huella Digital (394 caras) - Tipo L (1.17x1.04)
  puts "✅ PASO 1.3.3j: Clasificando Plataformas Especiales (1.17x1.04)..."
  model.active_entities.each do |ent|
    next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
    
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities rescue next
    caras = hijos.grep(Sketchup::Face).count rescue next
    d = pi_dimensiones(ent, Geom::Transformation.new)
    
    # Huella Digital: ~394 caras, medida ~1.17x1.04m y grosor ~0.05m
    if (caras - 394).abs <= 2 && (d[:largo] - 1.17).abs < 0.05 && (d[:ancho] - 1.04).abs < 0.05 && (d[:grosor_min] - 0.05).abs < 0.01
      nivel_z = (ent.bounds.min.z.to_m.round(1))
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.3j): #{nombre_capa}"
    end
  end

  # PASO 1.3.3k: NUEVA REGLA - Clasificar Plataformas por Huella Digital (394 caras) - Tipo M (1.04x0.96)
  puts "✅ PASO 1.3.3k: Clasificando Plataformas Especiales (1.04x0.96)..."
  model.active_entities.each do |ent|
    next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
    
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities rescue next
    caras = hijos.grep(Sketchup::Face).count rescue next
    d = pi_dimensiones(ent, Geom::Transformation.new)
    
    # Huella Digital: ~394 caras, medida ~1.04x0.96m y grosor ~0.05m
    if (caras - 394).abs <= 2 && (d[:largo] - 1.04).abs < 0.05 && (d[:ancho] - 0.96).abs < 0.05 && (d[:grosor_min] - 0.05).abs < 0.01
      nivel_z = (ent.bounds.min.z.to_m.round(1))
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.3k): #{nombre_capa}"
    end
  end

  # PASO 1.3.3l: NUEVA REGLA - Clasificar Plataformas por Huella Digital (394 caras) - Tipo N (0.96x0.91)
  puts "✅ PASO 1.3.3l: Clasificando Plataformas Especiales (0.96x0.91)..."
  model.active_entities.each do |ent|
    next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
    
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities rescue next
    caras = hijos.grep(Sketchup::Face).count rescue next
    d = pi_dimensiones(ent, Geom::Transformation.new)
    
    # Huella Digital: ~394 caras, medida ~0.96x0.91m y grosor ~0.05m
    if (caras - 394).abs <= 2 && (d[:largo] - 0.96).abs < 0.05 && (d[:ancho] - 0.91).abs < 0.05 && (d[:grosor_min] - 0.05).abs < 0.01
      nivel_z = (ent.bounds.min.z.to_m.round(1))
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.3l): #{nombre_capa}"
    end
  end

  # PASO 1.3.4: Clasificar Plataforma 1.17x1.17 por Huella Digital (10 caras / 24 aristas)
  puts "✅ PASO 1.3.4: Clasificando Plataforma Especial (10 caras, 1.17x1.17)..."
  model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"

    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
    caras = hijos.grep(Sketchup::Face).count
    aristas = hijos.grep(Sketchup::Edge).count
    subgrupos = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count
    d = pi_dimensiones(ent, Geom::Transformation.new)
    mat_nombre = pi_leer_material(ent)

    # Huella Digital: plataforma 1.17x1.17m, grosor 0.05m, 10 caras, 24 aristas, sin grupos internos
    if subgrupos == 0 &&
       caras == 10 &&
       aristas == 24 &&
       (d[:largo] - 1.17).abs < 0.05 &&
       (d[:ancho] - 1.17).abs < 0.05 &&
       (d[:grosor_min] - 0.05).abs < 0.01 &&
       mat_nombre.to_s.downcase.include?("turquesa")

      nivel_z = (ent.bounds.min.z.to_m.round(1))
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.4 - 10 caras): #{nombre_capa}"
    end
  end

  # PASO 1.3.4b: Clasificar Plataforma por Huella Digital (6 caras, 1.62x1.10x0.05)
  puts "✅ PASO 1.3.4b: Clasificando Plataforma Especial (6 caras, 1.62x1.10)..."
  model.active_entities.each do |ent|
    next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"

    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
    caras = hijos.grep(Sketchup::Face).count
    aristas = hijos.grep(Sketchup::Edge).count
    subgrupos = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count
    d = pi_dimensiones(ent, Geom::Transformation.new)

    # Huella Digital: plataforma 1.62x1.10m, grosor 0.05m, 6 caras, 12 aristas, sin grupos internos
    if subgrupos == 0 &&
       caras == 6 &&
       aristas == 12 &&
       (d[:largo] - 1.62).abs < 0.05 &&
       (d[:ancho] - 1.10).abs < 0.05 &&
       (d[:grosor_min] - 0.05).abs < 0.01

      nivel_z = (ent.bounds.min.z.to_m.round(1))
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.4b - 6 caras): #{nombre_capa}"
    end
  end

  # PASO 1.3.4c: Clasificar Plataforma Especial (6 caras, 1.31x0.51)
  puts "✅ PASO 1.3.4c: Clasificando Plataforma Especial (6 caras, 1.31x0.51)..."
  model.active_entities.each do |ent|
    next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"

    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities rescue next
    caras = hijos.grep(Sketchup::Face).count rescue next
    aristas = hijos.grep(Sketchup::Edge).count rescue next
    subgrupos = hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count rescue next
    d = pi_dimensiones(ent, Geom::Transformation.new)

    # Huella Digital: plataforma 1.31x0.51m, grosor 0.05m, 6 caras, 12 aristas, sin grupos internos
    if subgrupos == 0 &&
       caras == 6 &&
       aristas == 12 &&
       (d[:largo] - 1.31).abs < 0.05 &&
       (d[:ancho] - 0.51).abs < 0.05 &&
       (d[:grosor_min] - 0.05).abs < 0.01

      nivel_z = (ent.bounds.min.z.to_m.round(1))
      nombre_capa = "#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
      tag = layers[nombre_capa] || layers.add(nombre_capa)
      ent.layer = tag
      pi_limpiar_tags_internos(ent, layer0)
      @pi_paneles += 1
      @pi_sub_paneles[nombre_capa] += 1
      puts "    ✅ Plataforma detectada (Huella 1.3.4c - 6 caras): #{nombre_capa}"
    end
  end

# PASO 1.3.5: Clasificar Tumbling (Alto 0.05m, 11 caras)
puts "✅ PASO 1.3.5: Clasificando Tumbling..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
# Tumbling: 11 caras y grosor_min (alto) ~ 0.05m
if caras == 11 && (d[:grosor_min] - 0.05).abs < 0.005
area = (d[:largo] * d[:ancho]).round(2)
nombre_capa = "tumbling_#{area}m2"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Tumbling detectado: #{area}m2 → '#{nombre_capa}'"
end
end

# PASO 1.3.6: Clasificar Resbaladillas (Basado en sub-componentes)
puts "✅ PASO 1.3.6: Clasificando Resbaladillas..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
n1532 = pi_cuenta_subgrupos_con_caras(ent, 1532, 20)
n101 = pi_cuenta_subgrupos_con_caras(ent, 101, 5)
if n1532 >= 2 && n101 >= 1
d = pi_dimensiones(ent, Geom::Transformation.new)
largo = d[:largo].round(2)
# Determinar tipo por conteo de piezas
tipo = "Resbaladilla"
tipo = "Resbaladilla_Doble" if n101 == 2
tipo = "Resbaladilla_Triple" if n101 >= 3
nombre_capa = "#{tipo}_#{largo}m"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " ✅ #{tipo} detectada: #{largo}m \u2192 '#{nombre_capa}'"
end
end

# PASO 1.3.7: Clasificar Escalera Circular de Esponja (106 caras)
puts "✅ PASO 1.3.7: Clasificando Escalera Circular de Esponja..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
# Escalera Circular de Esponja: 106 caras y medidas ~1.468x0.734x0.3m
if caras == 106 && (d[:largo] - 1.468).abs < 0.05 && (d[:ancho] - 0.734).abs < 0.05 && (d[:grosor_min] - 0.3).abs < 0.05
nombre_capa = "Escalera_Circular_Esponja"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Escalera Circular detectada: '#{nombre_capa}'"
end
end

# PASO 1.3.8: Clasificar Rampa para Topes (5 caras)
puts "✅ PASO 1.3.8: Clasificando Rampa para Topes..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
# Rampa Topes: 5 caras y medidas ~2.214x1.823x0.545m
if caras == 5 && (d[:largo] - 2.214).abs < 0.05 && (d[:ancho] - 1.823).abs < 0.05 && (d[:grosor_min] - 0.545).abs < 0.05
nombre_capa = "Rampa_Topes"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Rampa Topes detectada: '#{nombre_capa}'"
end
end

# PASO 1.3.9: Clasificar Marco Redondo de Entrada (188 caras)
puts "✅ PASO 1.3.9: Clasificando Marco Redondo de Entrada..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
# Marco Redondo Entrada: 188 caras y medidas ~1.984x1.285x0.01m
if caras == 188 && (d[:largo] - 1.984).abs < 0.05 && (d[:ancho] - 1.285).abs < 0.05 && (d[:grosor_min] - 0.01).abs < 0.05
nombre_capa = "Marco_Redondo_Entrada"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Marco Redondo Entrada detectado: '#{nombre_capa}'"
end
end

# PASO 1.3.10: Clasificar Mega Resbaladilla Sin Estructura (364 caras)
puts "✅ PASO 1.3.10: Clasificando Mega Resbaladilla Sin Estructura..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
# Mega Resbaladilla: 364 caras y medidas ~9.6x3.98x2.43m
if caras == 364 && (d[:largo] - 9.6).abs < 0.1 && (d[:ancho] - 3.98).abs < 0.1 && (d[:grosor_min] - 2.43).abs < 0.1
nombre_capa = "Mega_Resbaladilla_Sin_Estructura"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Mega Resbaladilla detectada: '#{nombre_capa}'"
end
end

# PASO 1.3.11: Clasificar Tope Chico Tipo 2 (158 caras)
puts "✅ PASO 1.3.11: Clasificando Tope Chico Tipo 2..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
# Tope Chico Tipo 2: 158 caras y medidas ~0.5x0.21x0.13m
if caras == 158 && (d[:largo] - 0.5).abs < 0.05 && (d[:ancho] - 0.213).abs < 0.05 && (d[:grosor_min] - 0.127).abs < 0.05
nombre_capa = "Tope_Chico"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Tope Chico Tipo 2 detectado: '#{nombre_capa}'"
end
end

# PASO 1.3.12: Clasificar Puente de Ludoteca (7 subgrupos)
puts "✅ PASO 1.3.12: Clasificando Puente de Ludoteca..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
subgrupos = hijos.grep(Sketchup::Group).count
# Puente Ludoteca: 0 caras, 7 subgrupos y medidas ~1.17x0.83x0.6m
if caras == 0 && subgrupos == 7 && (d[:largo] - 1.169).abs < 0.05 && (d[:ancho] - 0.829).abs < 0.05 && (d[:grosor_min] - 0.6).abs < 0.05
nombre_capa = "Puente_Ludoteca"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Puente Ludoteca detectado: '#{nombre_capa}'"
end
end

# PASO 1.3.13: Clasificar Montaña Completa (7 subgrupos)
puts "✅ PASO 1.3.13: Clasificando Montaña Completa..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
subgrupos = hijos.grep(Sketchup::Group).count
# Montaña Completa: 0 caras, 7 subgrupos y medidas ~1.26x1.26x0.53m
if caras == 0 && subgrupos == 7 && (d[:largo] - 1.259).abs < 0.05 && (d[:ancho] - 1.255).abs < 0.05 && (d[:grosor_min] - 0.527).abs < 0.05
nombre_capa = "Montana_Completa"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Montaña Completa detectada: '#{nombre_capa}'"
end
end

# PASO 1.3.14: Clasificar Tope Largo Tipo 2 (404 caras)
puts "✅ PASO 1.3.14: Clasificando Tope Largo Tipo 2..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
# Tope Largo Tipo 2: 404 caras y medidas ~1.8x0.09x0.09m
if caras == 404 && (d[:largo] - 1.797).abs < 0.05 && (d[:ancho] - 0.093).abs < 0.05 && (d[:grosor_min] - 0.091).abs < 0.05
nombre_capa = "Tope_Largo"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Tope Largo Tipo 2 detectado: '#{nombre_capa}'"
end
end

# PASO 1.3.15: Clasificar Galleta Giratoria (2 subgrupos)
puts "✅ PASO 1.3.15: Clasificando Galleta Giratoria..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
subgrupos = hijos.grep(Sketchup::Group).count
# Galleta Giratoria: 0 caras, 2 subgrupos y medidas ~1.55x0.56x0.56m
if caras == 0 && subgrupos == 2 && (d[:largo] - 1.551).abs < 0.05 && (d[:ancho] - 0.565).abs < 0.05 && (d[:grosor_min] - 0.565).abs < 0.05
nombre_capa = "Galleta_Giratoria"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Galleta Giratoria detectada: '#{nombre_capa}'"
end
end

# PASO 1.3.16: Clasificar Pasamanos (10 subgrupos)
puts "✅ PASO 1.3.16: Clasificando Pasamanos..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
subgrupos = hijos.grep(Sketchup::Group).count
if caras == 0 && subgrupos == 10 && (d[:largo] - 2.185).abs < 0.1 && (d[:ancho] - 0.485).abs < 0.1 && (d[:grosor_min] - 0.089).abs < 0.1
nombre_capa = "Pasamanos"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Pasamanos detectado: '#{nombre_capa}'"
end
end

# PASO 1.3.17: Clasificar Costal de Esponjas (75 subgrupos)
puts "✅ PASO 1.3.17: Clasificando Costal de Esponjas..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
subgrupos = hijos.grep(Sketchup::Group).count
if caras == 0 && subgrupos == 75 && (d[:largo] - 1.721).abs < 0.1 && (d[:ancho] - 0.967).abs < 0.1
nombre_capa = "Costal_Esponjas"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Costal de Esponjas detectado: '#{nombre_capa}'"
end
end

# PASO 1.3.18: Clasificar Pared de Choque (6 caras)
puts "✅ PASO 1.3.18: Clasificando Pared de Choque..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
if caras == 6 && (d[:largo] - 1.64).abs < 0.1 && (d[:ancho] - 1.168).abs < 0.1 && (d[:grosor_min] - 0.172).abs < 0.1
nombre_capa = "Pared_Choque"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Pared de Choque detectada: '#{nombre_capa}'"
end
end

# PASO 1.3.19: Clasificar Tirolesa (1637 caras)
puts "✅ PASO 1.3.19: Clasificando Tirolesa..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
if caras == 1637 && d[:largo] >= 5.0 && d[:ancho] < 0.45 && d[:grosor_min] < 0.4
nombre_capa = "Tirolesa"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Tirolesa detectada: '#{nombre_capa}'"
end
end

# PASO 1.3.20: Clasificar Rampa Topes Tipo 2 (5 caras)
puts "✅ PASO 1.3.20: Clasificando Rampa Topes Tipo 2..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
if caras == 5 && (d[:largo] - 2.304).abs < 0.1 && (d[:ancho] - 1.64).abs < 0.1 && (d[:grosor_min] - 0.545).abs < 0.1
nombre_capa = "Rampa_Topes"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Rampa Topes Tipo 2 detectada: '#{nombre_capa}'"
end
end

# PASO 1.3.21: Clasificar Tumbling Variante (102 caras)
puts "✅ PASO 1.3.21: Clasificando Tumbling Variante..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
if caras == 102 && (d[:largo] - 5.8).abs < 0.1 && (d[:ancho] - 2.8).abs < 0.1
area = (d[:largo] * d[:ancho]).round(2)
nombre_capa = "tumbling_#{area}m2"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Tumbling Variante detectado: #{area}m2 → '#{nombre_capa}'"
end
end

# PASO 1.3.22: Clasificar Cancha de Futbol (14 caras)
puts "✅ PASO 1.3.22: Clasificando Cancha de Futbol..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
if caras == 14 && (d[:largo] - 5.57).abs < 0.1 && (d[:ancho] - 3.44).abs < 0.1
area = (d[:largo] * d[:ancho]).round(2)
nombre_capa = "cancha_futbol_#{area}m2"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Cancha de Futbol detectada: #{area}m2 → '#{nombre_capa}'"
end
end

# PASO 1.3.23: Clasificar Plataforma Especial 2.34x2.34 (1206 caras)
puts "✅ PASO 1.3.23: Clasificando Plataforma Especial 2.34x2.34..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
if caras == 1206 && (d[:largo] - 2.337).abs < 0.1 && (d[:ancho] - 2.336).abs < 0.1
nombre_capa = "2.34x2.34"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Plataforma Especial detectada: '#{nombre_capa}'"
end
end

# PASO 1.3.24: Clasificar Estructuras 3D de Malla
puts "✅ PASO 1.3.24: Clasificando Estructuras 3D de Malla..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"

mat_nombre = pi_leer_material(ent)
next unless ["gra1 cópia", "malla", "gra1 copia"].include?(mat_nombre&.downcase) || mat_nombre&.downcase&.include?("malla")

d = pi_dimensiones(ent, Geom::Transformation.new)
nivel_z = (ent.bounds.min.z.to_m.round(1))
nombre_capa = "malla_#{d[:largo]}x#{d[:ancho]}_Nivel_#{nivel_z}m"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Estructura 3D de Malla detectada: '#{nombre_capa}'"
end

# PASO 1.3.25: Clasificar Plataforma Irregular
puts "✅ PASO 1.3.25: Clasificando Plataforma Irregular..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
if caras == 204 && d[:grosor_min] < 0.15
area = (d[:largo] * d[:ancho]).round(2)
nombre_capa = "Plataforma_Irregular_#{area}m2"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Plataforma Irregular detectada: #{area}m2 → '#{nombre_capa}'"
end
end

# PASO 1.3.26: Clasificar Bandera Circular
puts "✅ PASO 1.3.26: Clasificando Bandera Circular..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
d = pi_dimensiones(ent, Geom::Transformation.new)
hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
caras = hijos.grep(Sketchup::Face).count
if caras == 204 && (d[:grosor_min] - 0.6).abs < 0.1
area = (d[:largo] * d[:ancho]).round(2)
nombre_capa = "bandera_circular_#{area}m2"
tag = layers[nombre_capa] || layers.add(nombre_capa)
ent.layer = tag
pi_limpiar_tags_internos(ent, layer0)
@pi_otros += 1
puts " 🔍 Bandera Circular detectada: #{area}m2 → '#{nombre_capa}'"
end
end

# PASO 1.4: Clasificar por Nombres de Componente conocidos
puts "✅ PASO 1.4: Clasificando por nombres conocidos..."
mapeo_nombres = {
"hormiguero" => "Hormiguero", "resbaladilla" => "Resbaladilla", "modulo de ligas" => "Modulo_Ligas",
"ligas" => "Modulo_Ligas", "dona con cadena" => "Dona_con_Cadena", "ducto recto" => "Ducto_Recto",
"taza giratoria" => "Taza_Giratoria", "montana cocodrilo" => "Montana_Cocodrilo", "zapatera fv" => "Zapatera_FV",
"puerta giratoria" => "Puerta_Giratoria", "puerta hawaiana" => "Puerta_Hawaiana", "costal" => "Costal_Doble_Cadena",
"rodillo galleta" => "Rodillo_Galleta", "rodillo caramelo" => "Rodillo_Caramelo", "rodillo entrada" => "Rodillo_Entrada", "torre de cubos" => "Torre_Cubos",
"pelota" => "Pelota_Plastico", "bandera" => "Bandera", "tope" => "Tope_Chico", "rampa" => "Rampa",
"gato" => "Gato",
"columpios cruzados" => "Modulo_4_Lianas",
"liana" => "Liana",
"puerta raton" => "Puerta_Raton",
"puerta de lona" => "Puerta_Raton",
"panel" => "Panel_Otros", "plataforma" => "Panel_Otros"
}

# PASO 1.5: Clasificar elementos restantes
puts "✅ PASO 1.5: Clasificando elementos por nombre y huella..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
nombre_def = (ent.respond_to?(:definition) ? ent.definition.name : ent.name).to_s.downcase
nombre_capa = mapeo_nombres.find { |k, v| nombre_def.include?(k) }&.last
if nombre_capa.nil?
match = huellas_estructurales.find { |h| h[:condicion].call(ent) }
if match
  # Soporte para tags dinámicos vía lambda o strings estáticos
  nombre_capa = match[:tag].respond_to?(:call) ? match[:tag].call(ent) : match[:tag]
  puts " 🔍 Huella: #{match[:descripcion]} → #{nombre_capa}"
end
end

if nombre_capa
  nivel_z = (ent.bounds.min.z.to_m.round(1))
  nombre_tag = "#{nombre_capa}_Nivel_#{nivel_z}m"
  tag = layers[nombre_tag] || layers.add(nombre_tag)
  ent.layer = tag
  pi_limpiar_tags_internos(ent, layer0)
  puts " ✅ '#{nombre_def}' → '#{nombre_tag}'"
end
end

# PASO 1.6: Clasificar Desconocidos
puts "✅ PASO 1.6: Clasificando elementos NO reconocidos..."
model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
  next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
  next unless ent.layer.name == "Layer0" || ent.layer.name == "Untagged"
  
  nivel_z = (ent.bounds.min.z.to_m.round(1))
  nombre_tag = "DESCONOCIDOS_Nivel_#{nivel_z}m"
  tag = layers[nombre_tag] || layers.add(nombre_tag)
  ent.layer = tag
  pi_limpiar_tags_internos(ent, layer0)
  begin
    d = pi_dimensiones(ent, Geom::Transformation.new)
    hijos = ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
    @pi_desconocidos << {
      entity_id: ent.entityID,
      nombre: ent.respond_to?(:definition) ? ent.definition.name : ent.name,
      tag: nombre_tag,
      caras: hijos.grep(Sketchup::Face).count,
      largo: d[:largo],
      ancho: d[:ancho],
      grosor: d[:grosor_min],
      medidas: "#{d[:largo]} x #{d[:ancho]} x #{d[:grosor_min]} m"
    }
  rescue StandardError
    nil
  end
  puts " ⚠️ DESCONOCIDO: '#{ent.respond_to?(:definition) ? ent.definition.name : ent.name}' -> '#{nombre_tag}'" rescue nil
end

# PASO 2: Sub-clasificar PI_Panel_Otros por material/textura
puts "✅ PASO 2: Sub-clasificando 'Panel_Otros' por textura..."
alias_materiales = {
"gra1 cópia" => "malla", "malla" => "malla",
"Azul Palido Vinil" => "Panel_1.17x0.60", "Azul Marino Oscuro Vinil" => "Panel_1.17x0.60"
}
  model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer && ent.layer.name == "Panel_Otros"
    nombre_mat = pi_leer_material(ent)
    base_capa = alias_materiales[nombre_mat] || "Panel_Mat_#{nombre_mat}"
    nivel_z = (ent.bounds.min.z.to_m.round(1))
    nombre_capa = "#{base_capa}_Nivel_#{nivel_z}m"
    tag = layers[nombre_capa] || layers.add(nombre_capa)
    ent.layer = tag
    pi_limpiar_tags_internos(ent, layer0)
    @pi_paneles_mat[nombre_capa] += 1
  end

# PASO 3: Subdividir PI_Panel_1.17x0.60 por medidas exactas reales
puts "✅ PASO 3: Subdividiendo 'Panel_1.17x0.60' por medidas exactas..."
  model.active_entities.each do |ent|
next if ent.hidden? || (ent.layer.respond_to?(:visible?) && !ent.layer.visible?)
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    next unless ent.layer && ent.layer.name == "Panel_1.17x0.60"
    d = pi_dimensiones(ent, Geom::Transformation.new)
    base_capa = "#{d[:largo]}x#{d[:grosor_max]}"
    nivel_z = (ent.bounds.min.z.to_m.round(1))
    nombre_capa = "#{base_capa}_Nivel_#{nivel_z}m"
    tag = layers[nombre_capa] || layers.add(nombre_capa)
    ent.layer = tag
    pi_limpiar_tags_internos(ent, layer0)
    @pi_sub_exactos[nombre_capa] += 1
  end

# PASO 4: Organizar tags en carpetas y niveles
puts "✅ PASO 4: Organizando tags por niveles jerárquicos..."
folder_plataformas = nil
layers.each_folder { |f| folder_plataformas = f if f.display_name == "Plataformas" }
folder_plataformas ||= layers.add_folder("Plataformas")

folder_acc_raiz = nil
layers.each_folder { |f| folder_acc_raiz = f if f.display_name == "Accesorios" }
folder_acc_raiz ||= layers.add_folder("Accesorios")

# Tags de Plataformas para organizar
plataformas_base = ["0.6x", "0.94x", "1.14x", "1.17x", "2.34x", "Panel_Triangular", "Plataforma_Irregular"]

layers.each do |tag|
  next if tag.name == "Layer0" || tag.name == "Untagged" || tag.name.start_with?("Tubos")
  
  # A. Plataformas (Organización por Nivel)
  if plataformas_base.any? { |p| tag.name.start_with?(p) }
    if tag.name.include?("_Nivel_")
      nivel_str = tag.name.split("_Nivel_").last
      sub_name = "Nivel #{nivel_str}"
      begin
        sub = nil
        folder_plataformas.folders.each { |f| sub = f if f.display_name == sub_name }
        sub ||= folder_plataformas.add_folder(sub_name)
        tag.folder = sub
      rescue
        tag.folder = layers.add_folder("Plataformas - #{sub_name}")
      end
    else
      tag.folder = folder_plataformas
    end
    next
  end

    # B. Accesorios y Mallas (Organización por Nivel dentro de Accesorios)
    if tag.name.include?("_Nivel_") || tag.name.start_with?("malla")
      nivel_str = tag.name.include?("_Nivel_") ? tag.name.split("_Nivel_").last : "Indefinido"
      sub_name = "Nivel #{nivel_str}"
      
      begin
        sub = nil
        folder_acc_raiz.folders.each { |f| sub = f if f.display_name == sub_name }
        sub ||= folder_acc_raiz.add_folder(sub_name)
        tag.folder = sub
      rescue
        tag.folder = layers.add_folder("Accesorios - #{sub_name}")
      end
    else
      tag.folder = folder_acc_raiz
    end
  end

model.commit_operation

  # --- SISTEMA DE LOGGING DUAL ---
  @reporte_texto = ""
  def pi_log(msg)
    puts msg
    @reporte_texto += "#{msg}\n"
  end

  pi_log "\n"
  pi_log "╔══════════════════════════════════════════╗"
  pi_log "║       REPORTE DE INVENTARIO Y COSTOS     ║"
  pi_log "╚══════════════════════════════════════════╝"
  
  # Precios Unitarios (Base LISTA_MAESTRA_PRECIOS_PLAYIDEA.md)
  @precios = {
    "Panel_interactivo_yelcot" => 7644.0,
    "alberca_d_epelotas_area_de_bebes" => 4500.0,
    "media_monta_a_cocodrilo" => 3500.0,
    "Alberca_de_esponjas_de_medida_1_94___4_26___0_50" => 68000.0,
    "Tina_de_alberca_de_esponjas" => 5000.0,
    "topes_para_acceso_a_tumbling" => 7540.0,
    "1.17x1.17" => 1500, "1.19x0.7" => 1500, "1.3x1.25" => 1500, "0.6x0.39" => 900, "1.17x0.61" => 1200, "1.17x0.88" => 1500, "0.88x0.45" => 1500, "1.17x0.45" => 1500, "0.6x0.45" => 1500, "1.31x0.51" => 1500, "0.61x0.59" => 1500, "1.62x1.10" => 1950, "Panel_Triangular" => 1500, "Tobogan_Fibra" => 22000, "Panel_Entrada_Curvo_Grande" => 4500, "Panel_Entrada_Curvo_Chico" => 2500, "Rampa_2.82x1.1" => 3500, "Tope_Largo" => 450, "Panel_Multiventanas" => 3500,
    "Hormiguero" => 900, "Resbaladilla" => 8000, "Modulo_Ligas" => 3000, "Dona_con_Cadena" => 1500, "Costal_Cruzado" => 1500,
    "Ducto_Recto" => 26000, "Taza_Giratoria" => 10000, "Montana_Cocodrilo" => 3500, "Zapatera_FV" => 6000,
    "Puerta_Giratoria" => 3500, "Puerta_Hawaiana" => 300, "Rodillo_Galleta" => 2000, "Rodillo_Caramelo" => 1500, "Rodillo_Entrada" => 1500,
    "Torre_Cubos" => 3000, "Costal_Doble_Cadena" => 1500, "Costal_Chico" => 750, "Rodillo" => 1300,
    "Cubo" => 450, "Tope_Chico" => 250, "Pelota_Plastico" => 3.5, "banderas" => 250, "Rampa" => 2500, "Rampa_Topes" => 3500,
    "Cuarto_Piramide" => 2500, "Piramide_Completa" => 10000, "Resbaladilla_Triple" => 25000, "Dona" => 2500, "Liana" => 700,
    "Popotes" => 300, "Ducto_Codo_90" => 5000, "Canopi" => 3500, "Tope" => 700, "Hawaianas" => 300,
    "Panel_Accesorio" => 3500, "Pasto_Sintetico" => 450, "Alberca_Pelotas" => 4500, "Marco_Redondo_Entrada" => 4500, "Mega_Resbaladilla_Sin_Estructura" => 45000, "Puente_Ludoteca" => 8000, "Montana_Completa" => 8000, "Galleta_Giratoria" => 3500, "Pasamanos" => 3500, "Costal_Esponjas" => 2500, "Pared_Choque" => 1500, "Tirolesa" => 15000, "2.34x2.34" => 1530, "Gato" => 3500, "Modulo_4_Lianas" => 2800, "Puerta_Raton" => 700
  }

  def pi_get_precio(tag_name)
    base_name = tag_name.split("_Nivel_").first
    return 4500 if base_name.start_with?("tumbling_")
    return 2500 if base_name.start_with?("cancha_futbol_")
    return 1095.77 if base_name.start_with?("Plataforma_Irregular_")
    return 1666.67 if base_name.start_with?("bandera_circular_")
    return 400 if base_name.start_with?("malla_")
    return 25000 if base_name.start_with?("Resbaladilla_Triple")
    return 16000 if base_name.start_with?("Resbaladilla_Doble")
    return 8000 if base_name.start_with?("Resbaladilla")
    return 5000 if base_name.start_with?("Ducto_Codo")
    return 3500 if base_name.start_with?("Rampa_")
    # Pieza única (0.57x1.56x1.56, grupo "Difference"), sin precio de
    # proveedor conocido -no hay un cotizado real para esta colchoneta de
    # tumbling especial, a diferencia de los demás precios de esta lista-.
    # Estimado con la misma tarifa por m² de la regla dinámica de
    # colchonetas (850/m²) aplicada a su huella (1.56 x 1.56 = 2.4336 m²).
    # Ajusta este valor si consigues una cotización real del proveedor.
    return 2069 if base_name == "Colchoneta_Tumbling_Especial"
    return 850 if base_name.start_with?("Colchoneta")
    
    # Mapeo exacto
    return @precios[base_name] if @precios.key?(base_name)
    
    # Lógica de fallback para dimensiones o paneles
    if base_name =~ /^(\d+\.?\d*)x(\d+\.?\d*)$/
      return 1500 # Precio default para plataformas no listadas
    elsif base_name.start_with?("Panel_")
      return 1500 # Precio base para paneles diversos
    end
    
    0 # Sin precio detectado
  end

  def pi_get_area(tag_name)
    base_name = tag_name.split("_Nivel_").first
    if base_name =~ /malla_([\d.]+)x([\d.]+)/
      return ($1.to_f * $2.to_f).round(2)
    elsif base_name =~ /Colchoneta_([\d.]+)x([\d.]+)/
      return ($1.to_f * $2.to_f).round(2)
    elsif base_name =~ /tumbling_([\d.]+)m2/
      return $1.to_f
    elsif base_name =~ /cancha_futbol_([\d.]+)m2/
      return $1.to_f
    elsif base_name =~ /Plataforma_Irregular_([\d.]+)m2/
      return $1.to_f
    elsif base_name =~ /bandera_circular_([\d.]+)m2/
      return $1.to_f
    end
    1.0
  end

  total_general_costo = 0
  total_general_piezas = 0

  # Función auxiliar para procesar y mostrar un tag en el reporte
  pi_reportar_tag = lambda do |tag, entities_tag|
    # Conteo inteligente: Diferencia entre piezas individuales y geometría masiva (pelotas sueltas)
    conteo_real = 0
    entities_tag.each do |e|
      if tag.name.include?("Pelota_Plastico")
        hijos = (e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities) rescue nil
        n_sub = hijos ? hijos.select { |h| h.is_a?(Sketchup::Group) || h.is_a?(Sketchup::ComponentInstance) }.count : 0
        caras = hijos ? hijos.grep(Sketchup::Face).count : 0
        if n_sub == 0 && caras > 5000
          conteo_real += (caras / 288.0).round
        elsif n_sub > 0
          conteo_real += n_sub
        else
          conteo_real += 1
        end
      else
        conteo_real += 1
      end
    end
    
    return if conteo_real == 0
    
    if tag.name.start_with?("Tubos")
      long_total = 0
      entities_tag.each { |e| long_total += pi_dimensiones(e, Geom::Transformation.new)[:largo] }
      num_barras = (long_total / 6.0).ceil
      subtotal = num_barras * 700
      pi_log sprintf("  - %-25s | %4d | $%10s | $%10d", tag.name[0..24], num_barras, "700", subtotal)
      total_general_piezas += conteo_real
      total_general_costo += subtotal
    else
      precio = pi_get_precio(tag.name)
      area = pi_get_area(tag.name) rescue 1.0
      subtotal = (conteo_real * area * precio).to_i
      warning = precio == 0 ? " [SIN PRECIO]" : ""
      pi_log sprintf("  - %-25s | %4d | $%10d | $%10d%s", tag.name[0..24], conteo_real, precio, subtotal, warning)
      total_general_piezas += conteo_real
      total_general_costo += subtotal
    end
  end

  # Función recursiva para recorrer carpetas en el mismo orden del panel
  pi_reportar_carpeta = lambda do |folder, indent_level|
    prefix = "  " * indent_level
    folder_name = folder.display_name.upcase
    pi_log "\n#{prefix}📁 CARPETA: #{folder_name}"
    pi_log "#{prefix}----------------------------------------------------------------------"
    pi_log "#{prefix}  CONCEPTO                  | CANT | P.UNITARIO | SUBTOTAL"
    pi_log "#{prefix}----------------------------------------------------------------------"
    
    # 1. Reportar tags en esta carpeta
    layers.select { |l| l.folder == folder }.sort_by(&:name).each do |tag|
      entities = model.active_entities.select { |e| (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && e.layer == tag }
      pi_reportar_tag.call(tag, entities)
    end
    
    # 2. Reportar subcarpetas (Recursivo)
    if folder.respond_to?(:folders)
      folder.folders.sort_by(&:display_name).each do |sub|
        pi_reportar_carpeta.call(sub, indent_level + 1)
      end
    end
  end

  # --- EJECUCIÓN DEL REPORTE ---
  
  # 1. Carpetas Raíz (Tubos, Plataformas, Accesorios, etc.)
  root_folders = []
  layers.each_folder { |f| root_folders << f }
  root_folders.sort_by(&:display_name).each do |folder|
    pi_reportar_carpeta.call(folder, 0)
  end
  
  # 2. Tags sin carpeta (Sueltos)
  tags_sueltos = layers.select { |l| l.folder.nil? && l.name != "Layer0" && l.name != "Untagged" }
  if tags_sueltos.any? { |l| model.active_entities.any? { |e| e.respond_to?(:layer) && e.layer == l } }
    pi_log "\n📁 OTROS / SIN CLASIFICAR"
    pi_log "----------------------------------------------------------------------"
    tags_sueltos.sort_by(&:name).each do |tag|
      entities = model.active_entities.select { |e| (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && e.layer == tag }
      pi_reportar_tag.call(tag, entities)
    end
  end

pi_log "\n==========================================="
  if @pi_longitud_tubos > 0
    total_con_merma = @pi_longitud_tubos * 1.10
    total_foams = (total_con_merma / 2.4).ceil
    total_cinchos = (total_con_merma / 0.15).ceil
    
    costo_foams = total_foams * 175
    costo_cinchos_f = total_cinchos * 3
    
    pi_log " METRAJE TOTAL DE TUBOS       : #{@pi_longitud_tubos.round(2)} m"
    pi_log " PROTECTORES FOAM (2.4m) REQ. : #{total_foams} piezas | Costo: $#{costo_foams}"
    pi_log " CINCHOS (PARA FOAM) REQ.     : #{total_cinchos} piezas | Costo: $#{costo_cinchos_f}"
    total_general_costo += (costo_foams + costo_cinchos_f)
  end
  if @pi_longitud_redondo > 0
    total_redondo_con_merma = @pi_longitud_redondo * 1.10
    cinchos_malla = (total_redondo_con_merma / 0.15).ceil
    
    costo_redondo = (@pi_longitud_redondo * 123.56).round(2)
    costo_cinchos_m = cinchos_malla * 3
    
    pi_log "-------------------------------------------"
    pi_log " METRAJE REDONDO PULIDO       : #{@pi_longitud_redondo.round(2)} m | Costo: $#{costo_redondo}"
    pi_log " CINCHOS (PARA MALLA) REQ.    : #{cinchos_malla} piezas | Costo: $#{costo_cinchos_m}"
    total_general_costo += (costo_redondo + costo_cinchos_m)
  end
  # --- ANALIZANDO NODOS DE CONEXIÓN ---
  if @pi_total_nodos > 0
    total_conectores_merma = (@pi_total_nodos * 1.10).ceil
    costo_conectores = total_conectores_merma * 70
    pi_log "-------------------------------------------"
    pi_log " CONECTORES (CON 10% MERMA)   : #{total_conectores_merma} piezas | Costo: $#{costo_conectores}"
    total_general_costo += costo_conectores
  end

  iva = (total_general_costo * 0.16).round(2)
  total_final = (total_general_costo + iva).round(2)

  # --- AUDITORÍA DE GEOMETRÍAS FANTASMAS ---
  @fantasmas_vacios = 0
  @fantasmas_dim_cero = 0
  
  def self.pi_auditar_fantasmas_recursivo(entities)
    entities.each do |e|
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      
      # Caso 1: Contenedor vacío
      hijos = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities rescue nil
      if hijos && hijos.length == 0
        @fantasmas_vacios += 1
      end
      
      # Caso 2: Dimensión casi nula (Geometría degenerada)
      if e.bounds.diagonal < 0.001 # < 1mm
        @fantasmas_dim_cero += 1
      end
      
      # Profundizar
      pi_auditar_fantasmas_recursivo(hijos) if hijos
    end
  end
  pi_auditar_fantasmas_recursivo(model.active_entities)

  pi_log "-------------------------------------------"
  pi_log " TOTAL DE PIEZAS CLASIFICADAS : #{total_general_piezas}"
  if @fantasmas_vacios > 0 || @fantasmas_dim_cero > 0
    pi_log "⚠️ AVISO: Se detectaron #{@fantasmas_vacios + @fantasmas_dim_cero} Geometrías Fantasmas (Vacías o Dim. 0)."
  end
  pi_log "-------------------------------------------"
  pi_log " SUBTOTAL ESTIMADO (MXN)      : $#{total_general_costo.round(2).to_s.rjust(12)}"
  pi_log " IVA (16%)                    : $#{iva.to_s.rjust(12)}"
  pi_log " GRAN TOTAL CON IVA (MXN)     : $#{total_final.to_s.rjust(12)}"
  pi_log "===========================================\n\n"

  # --- FICHA TÉCNICA (EJES UNIVERSALES / DEFAULT DE SKETCHUP) ---
  bounds_todo = Geom::BoundingBox.new
  bounds_sin_zap = Geom::BoundingBox.new
  @has_zapateras_encontradas = false
  
  # Usamos la transformación identidad para alinearnos a los ejes por defecto de SketchUp
  t_axes = Geom::Transformation.new

  # Algoritmo de disección geométrica alineado a ejes visuales
  def self.pi_analizar_volumen_recursivo(entities, trans, b_todo, b_sin_zap, t_axes, excluyendo_zapatera = false)
    entities.each do |e|
      next unless e.respond_to?(:bounds)
      es_zap = (e.respond_to?(:layer) && e.layer.name.downcase.include?("zapatera"))
      @has_zapateras_encontradas = true if es_zap
      bloqueado_zap = excluyendo_zapatera || es_zap

      bbox = e.bounds
      for i in 0..7
        # Transformar punto a espacio global y LUEGO al espacio de los ejes del usuario
        pt_global = bbox.corner(i).transform(t_axes * trans)
        b_todo.add(pt_global)
        b_sin_zap.add(pt_global) unless bloqueado_zap
      end

      if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        hijos = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities rescue nil
        next unless hijos
        pi_analizar_volumen_recursivo(hijos, trans * e.transformation, b_todo, b_sin_zap, t_axes, bloqueado_zap)
      end
    end
  end

  pi_analizar_volumen_recursivo(model.active_entities, Geom::Transformation.new, bounds_todo, bounds_sin_zap, t_axes)

  # Extracción de métricas puras por coordenadas (X=Rojo, Y=Verde, Z=Azul)
  dim_x = (bounds_todo.max.x - bounds_todo.min.x).to_m.round(2)
  dim_y = (bounds_todo.max.y - bounds_todo.min.y).to_m.round(2)
  dim_z = (bounds_todo.max.z - bounds_todo.min.z).to_m.round(2)
  
  dim_x_s = (bounds_sin_zap.max.x - bounds_sin_zap.min.x).to_m.round(2)
  dim_y_s = (bounds_sin_zap.max.y - bounds_sin_zap.min.y).to_m.round(2)
  dim_z_s = (bounds_sin_zap.max.z - bounds_sin_zap.min.z).to_m.round(2)

  # Diferencias netas
  d_x = (dim_x - dim_x_s).round(2)
  d_y = (dim_y - dim_y_s).round(2)
  d_z = (dim_z - dim_z_s).round(2)

  # Punto más alto (para coincidir con medición manual del usuario)
  top_z = bounds_todo.max.z.to_m.round(2)

  pi_log "╔══════════════════════════════════════════╗"
  pi_log "║             FICHA TÉCNICA                ║"
  pi_log "╚══════════════════════════════════════════╝"
  pi_log "- ARCHIVO         : #{model.title.empty? ? "Sin Título" : model.title}"
  pi_log "- NIVEL MÁX. (Z)  : #{top_z} m (Referencia al origen)"
  
  if @has_zapateras_encontradas
    pi_log "- ALTURA (Azul)   : #{dim_z} m | Sin Zapateras: #{dim_z_s} m (Dif: #{d_z}m)"
    pi_log "- LARGO  (Verde)  : #{dim_y} m | Sin Zapateras: #{dim_y_s} m (Dif: #{d_y}m)"
    pi_log "- ANCHO  (Rojo)   : #{dim_x} m | Sin Zapateras: #{dim_x_s} m (Dif: #{d_x}m)"
    pi_log "  * NOTA: Medidas basadas en la geometría real de los ejes universales."
  else
    pi_log "- ALTURA (Azul)   : #{dim_z} m"
    pi_log "- LARGO  (Verde)  : #{dim_y} m"
    pi_log "- ANCHO  (Rojo)   : #{dim_x} m"
  end
  pi_log "===========================================\n\n"

  # --- EXPORTACIÓN A ARCHIVO TXT ---
  full_path = nil
  begin
    # Obtener ruta del modelo o carpeta de documentos si no está guardado
    base_path = model.path.empty? ? File.expand_path("~/Documents") : File.dirname(model.path)
    file_name = model.title.empty? ? "Reporte_Inventario_PlayIdea" : "#{model.title}_Inventario"
    full_path = File.join(base_path, "#{file_name}.txt")

    File.write(full_path, @reporte_texto)
    puts "📂 Reporte exportado exitosamente a: #{full_path}"
  rescue => e
    puts "❌ Error al exportar TXT: #{e.message}"
    full_path = nil
  end

  # El mismo texto que se fue armando línea por línea vía pi_log ahora se
  # muestra en un diálogo gráfico -antes solo vivía en la consola de Ruby-.
  pi_mostrar_reporte(@reporte_texto, full_path)
end

# ACCIÓN 2: Lista de Cortes
def pi_lista_cortes_tubos
model = Sketchup.active_model
selection = model.selection
return if selection.empty?
@pi_tubos_corte = Hash.new(0)
def pi_procesar_tubo(instancia, trans_acumulada)
return unless instancia.is_a?(Sketchup::ComponentInstance) || instancia.is_a?(Sketchup::Group)
d = pi_dimensiones(instancia, trans_acumulada)
if d[:grosor_max] <= 0.20 && d[:grosor_max] > 0.01 && d[:largo] >= (d[:grosor_max] * 1.5)
@pi_tubos_corte["#{d[:largo]}m"] += 1
else
hijos = instancia.is_a?(Sketchup::Group) ? instancia.entities : instancia.definition.entities rescue []
hijos.each { |h| pi_procesar_tubo(h, d[:t_global]) }
end
end
selection.each { |ent| pi_procesar_tubo(ent, Geom::Transformation.new) }
puts "\n===============================\n LISTA DE CORTES (TUBOS) \n==============================="
@pi_tubos_corte.sort_by { |largo, _| -largo.to_f }.each { |largo, cantidad| puts "► #{cantidad} tubo(s) de #{largo}" }
end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions').add_submenu('Play Idea - Auto Etiquetado')
      menu.add_item('Auto-Etiquetar (Tags + Carpetas + Costeo)') { pi_auto_etiquetar }
      menu.add_item('Lista de Cortes de Tubos (selección)') { pi_lista_cortes_tubos }
      file_loaded(__FILE__)
    end
  end
end
