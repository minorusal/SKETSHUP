# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# VERSION DEL SCRIPT: v1 (2026-08-05)
#
# QUÉ ES ESTO
# -----------
# El intento anterior (generar_torres_referencia.rb) reconstruía la torre a
# partir de números extraídos a mano de un .txt de inspección -solo la caja
# (min/max) de cada pieza directa-, así que salía como bloques rectangulares
# sueltos, nada parecido a la pieza real (con sus receptores, tuercas,
# opresores...). Esto es al revés y mucho más simple: en vez de RECONSTRUIR
# la geometría desde números, DUPLICA el grupo real tal cual existe en el
# modelo -mismo componente, mismas caras, mismo material-, así que la copia
# es EXACTA por definición, no una aproximación.
#
# CÓMO USARLO
# -----------
# 1. En el modelo, selecciona el grupo (o los grupos) que quieras copiar
#    -por ejemplo, uno de tus 4 'MOD-3X4X2-TORRE' hechos a mano-.
# 2. Corre en la consola: CopiarGrupoReferencia.duplicar_seleccion
# 3. Aparece una copia exacta pegada al lado del original -desplazada en X
#    lo que mide de ancho más 300mm de aire-, para comparar lado a lado.
#
# Si seleccionas varios grupos a la vez, duplica cada uno.
#
# Además, cada copia se reporta con detalle -nombre, caja LOCAL, tamaño y
# transform (origen + xaxis/yaxis/zaxis) de CADA pieza que tenga adentro,
# a cualquier profundidad-, tanto impreso en consola como guardado en un
# .txt aparte en inspect_output/. A diferencia de los reportes de 90MB de
# antes, este está acotado SOLO a la pieza copiada -no al modelo entero-,
# así que sale chico y se puede leer directo. La idea es ir acumulando
# estos reportes chicos como base para, más adelante, generar la torre por
# reglas -sin depender de tener un original que copiar- y en otros tamaños.
#
# CÓMO FUNCIONA (para quien lea el código)
# -----------------------------------------
# Todo Sketchup::Group -y Sketchup::ComponentInstance- tiene un
# `.definition` -el "molde" con la geometría real, aunque nunca lo hayas
# convertido a componente explícitamente-. Crear OTRA instancia de esa
# MISMA definición, con una transformación distinta, da una copia
# geométricamente idéntica sin tocar el original ni reconstruir nada a
# mano.

module CopiarGrupoReferencia
  extend self

  ESPACIO_MM = 300.0
  OUTPUT_DIR = '/Users/minorusal/Documents/SKETCHUP/inspect_output'

  def duplicar_seleccion
    model = Sketchup.active_model
    seleccionados = model.selection.grep(Sketchup::Group) + model.selection.grep(Sketchup::ComponentInstance)
    if seleccionados.empty?
      UI.messagebox('Selecciona primero uno o más grupos/componentes -por ejemplo, tu torre hecha a mano- y vuelve a correr esto.')
      return
    end

    model.start_operation('Copiar grupo(s) de referencia', true)
    copias = seleccionados.map { |original| duplicar_uno(model, original) }
    model.selection.clear
    copias.each { |c| model.selection.add(c) }
    model.commit_operation
    model.active_view.zoom(copias)
    puts "✅ #{copias.length} copia(s) exacta(s) creada(s) junto al original -la vista ya hizo zoom a la copia, y queda seleccionada-."
    copias.each { |copia| reportar(copia) }
    copias
  rescue StandardError => e
    model.abort_operation
    puts "❌ Error: #{e.message}"
    puts e.backtrace.first(5)
  end

  # Reporte DETALLADO de una sola pieza -recorre TODO lo que tenga adentro,
  # a cualquier profundidad-, pero acotado nada más a esta pieza -no al
  # modelo completo-, así que sale chico y se puede leer directo en la
  # consola -a diferencia de los .txt de inspección de 90MB de antes, que
  # inspeccionaban TODO el modelo-. Se imprime en pantalla Y se guarda en
  # un .txt aparte -mismo folder que usa siempre este proyecto-, con la
  # idea de ir acumulando estos reportes chicos como material para,
  # eventualmente, poder generar la torre por reglas -sin depender de tener
  # que copiar un original- y en distintos tamaños.
  def reportar(entidad)
    lineas = []
    nombre_raiz = entidad.name.to_s.empty? ? '(sin nombre)' : entidad.name
    lineas << "=" * 70
    lineas << "REPORTE DETALLADO: #{nombre_raiz}"
    lineas << "=" * 70
    describir_pieza(entidad, 0, lineas)
    texto = lineas.join("\n")
    puts texto

    require 'fileutils'
    FileUtils.mkdir_p(OUTPUT_DIR)
    ruta = File.join(OUTPUT_DIR, "reporte_grupo_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt")
    File.write(ruta, texto)
    puts "📄 Reporte guardado en: #{ruta}"
    texto
  end

  def fmt(length_o_float)
    valor = length_o_float.respond_to?(:to_mm) ? length_o_float.to_mm : length_o_float
    valor.round(3)
  end

  def describir_pieza(entidad, profundidad, lineas)
    indent = '  ' * profundidad
    nombre = entidad.name.to_s.empty? ? '(sin nombre)' : entidad.name
    es_grupo = entidad.is_a?(Sketchup::Group)
    tipo = es_grupo ? 'Grupo' : 'Componente'
    definicion_nombre = es_grupo ? nil : (entidad.definition.name rescue nil)

    b = entidad.bounds
    t = entidad.transformation
    origen = t.origin
    xa = t.xaxis
    ya = t.yaxis
    za = t.zaxis

    lineas << "#{indent}- #{nombre}  [#{tipo}]#{definicion_nombre ? " (definición: #{definicion_nombre})" : ''}"
    lineas << "#{indent}    bounds LOCAL min=[#{fmt(b.min.x)}, #{fmt(b.min.y)}, #{fmt(b.min.z)}]  " \
      "max=[#{fmt(b.max.x)}, #{fmt(b.max.y)}, #{fmt(b.max.z)}]  (mm, relativo al padre inmediato)"
    lineas << "#{indent}    size=[#{fmt(b.width)}, #{fmt(b.height)}, #{fmt(b.depth)}] mm (X,Y,Z)"
    lineas << "#{indent}    transform origen LOCAL=[#{fmt(origen.x)}, #{fmt(origen.y)}, #{fmt(origen.z)}] mm"
    lineas << "#{indent}    transform xaxis=[#{xa.x.round(4)}, #{xa.y.round(4)}, #{xa.z.round(4)}]  " \
      "yaxis=[#{ya.x.round(4)}, #{ya.y.round(4)}, #{ya.z.round(4)}]  " \
      "zaxis=[#{za.x.round(4)}, #{za.y.round(4)}, #{za.z.round(4)}]"

    hijos = es_grupo ? entidad.entities : entidad.definition.entities
    directos = hijos.grep(Sketchup::Group) + hijos.grep(Sketchup::ComponentInstance)
    return if directos.empty?

    lineas << "#{indent}  Sub-piezas directas (#{directos.length}):"
    directos.each { |hijo| describir_pieza(hijo, profundidad + 1, lineas) }
  end

  def duplicar_uno(model, original)
    ancho_mm = original.bounds.width.to_mm
    offset = Geom::Vector3d.new((ancho_mm + ESPACIO_MM).mm, 0, 0)
    nueva_transform = Geom::Transformation.translation(offset) * original.transformation
    # OJO: la copia debe agregarse en el MISMO contexto (mismo `entities`)
    # donde ya vive el original -no en `model.active_entities`, que es
    # donde estás parado TÚ ahora mismo en el Outliner, y puede ser un
    # contexto distinto si el original está anidado dentro de otros
    # grupos-. `original.transformation` es relativa a ESE contexto, así
    # que si se agrega en el contexto equivocado la copia aparece en un
    # lugar del modelo que no tiene nada que ver -eso era el bug: "no sale
    # nada" porque la copia sí se creaba, pero lejos, fuera de vista-.
    destino = original.parent.entities
    copia = destino.add_instance(original.definition, nueva_transform)
    copia.name = "#{original.name} (COPIA)"
    copia
  end
end

# Se autoejecuta al pegar el script COMPLETO -si ya tienes algo
# seleccionado en el modelo, lo copia de inmediato; si no, imprime cómo
# correrlo después- para no depender de acordarte de pegar una segunda
# línea aparte.
if Sketchup.active_model.selection.empty?
  puts "ℹ️  Script cargado. Selecciona un grupo/componente en el modelo -por ejemplo tu torre- y vuelve a pegar TODO este script otra vez."
else
  CopiarGrupoReferencia.duplicar_seleccion
end
nil
