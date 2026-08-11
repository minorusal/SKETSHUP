# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# VERSION DEL SCRIPT: v2 -emparejado por tipo+cercanía, no por orden- (2026-08-06)
#
# QUÉ ES ESTO
# -----------
# Compara DOS grupos -las piezas DIRECTAS de cada uno, no las tuercas/
# opresores de adentro de cada conector- y reporta qué cambió: piezas que
# se movieron/giraron, piezas que aparecen en un lado y no en el otro
# -agregadas o quitadas-. Para poder corregir el código del plugin con
# números exactos en vez de "muévelo un poco más".
#
# A DIFERENCIA DE LA v1: ya NO exige que los dos grupos tengan la misma
# cantidad de piezas en el mismo orden -eso truena en cuanto corriges a
# mano agregando/quitando algo, que es lo normal-. Ahora empareja cada
# pieza del "antes" con la más parecida del "después" -mismo tipo -CON-12
# con CON-12, etc.- y la más CERCANA en posición-, y lo que sobra de un
# lado sale marcado como agregado/quitado.
#
# CÓMO USARLO
# -----------
# 1. Dejas el grupo que generó el plugin tal cual -es el "antes"-.
# 2. Lo seleccionas y corres CopiarGrupoReferencia.duplicar_seleccion
#    -te da una copia exacta al lado, ver copiar_grupo_referencia.rb-.
# 3. Corriges esa COPIA a mano en SketchUp -mueves, giras, agregas o
#    quitas lo que haga falta-, dejando el original intacto.
# 4. Seleccionas LOS DOS -el original y la copia ya corregida- y pegas
#    este script completo -se autoejecuta-.

module CompararGrupos
  extend self

  OUTPUT_DIR = '/Users/minorusal/Documents/SKETCHUP/inspect_output'
  UMBRAL_POSICION_MM = 1.0
  UMBRAL_ROTACION_DEG = 0.5

  def comparar_seleccion
    model = Sketchup.active_model
    seleccionados = model.selection.grep(Sketchup::Group) + model.selection.grep(Sketchup::ComponentInstance)
    if seleccionados.length != 2
      UI.messagebox(
        'Selecciona EXACTAMENTE 2 grupos -el original que generó el ' \
        'plugin y tu copia ya corregida a mano- y vuelve a correr esto.'
      )
      return
    end

    original, corregido = seleccionados
    piezas_original = piezas_directas(original)
    piezas_corregido = piezas_directas(corregido)

    emparejadas, solo_original, solo_corregido = emparejar(piezas_original, piezas_corregido)

    # Desfase GENERAL del grupo completo -si al duplicar/editar el grupo
    # entero quedó corrido un poquito respecto al original, eso no es una
    # corrección pieza por pieza, es ruido que tapa las correcciones
    # reales-. Se calcula como la MEDIANA del desplazamiento de todas las
    # piezas emparejadas -mediana y no promedio, para que no la jalen los
    # pares mal emparejados por el algoritmo voraz, que sí importan y
    # pueden ser enormes- y se resta antes de comparar contra el umbral.
    desfase_general = desfase_mediana(emparejadas)

    lineas = []
    lineas << "Comparación: '#{original.name}' (ANTES, #{piezas_original.length} piezas) vs " \
      "'#{corregido.name}' (DESPUÉS, #{piezas_corregido.length} piezas)"
    lineas << ('=' * 70)
    lineas << "Desfase general del grupo completo -restado abajo antes de comparar-: " \
      "[#{desfase_general.x.to_mm.round(2)}, #{desfase_general.y.to_mm.round(2)}, #{desfase_general.z.to_mm.round(2)}] mm"

    cambiadas = 0
    lineas << ''
    lineas << '--- PIEZAS QUE CAMBIARON (más allá del desfase general de arriba) ---'
    emparejadas.each do |po, pc|
      origen_corregido_neto = pc[:origin] - desfase_general
      delta_pos_mm = po[:origin].distance(origen_corregido_neto).to_mm
      angulo_deg = angulo_entre(po[:zaxis], pc[:zaxis])
      next if delta_pos_mm < UMBRAL_POSICION_MM && angulo_deg < UMBRAL_ROTACION_DEG

      cambiadas += 1
      offset_neto = origen_corregido_neto - po[:origin]
      lineas << ''
      lineas << "#{po[:nombre]}"
      lineas << "  posición ANTES:       [#{fmt_pt(po[:origin])}] mm"
      lineas << "  posición DESPUÉS:     [#{fmt_pt(pc[:origin])}] mm  (cruda, incluye el desfase general)"
      lineas << "  desplazamiento NETO:  [#{offset_neto.x.to_mm.round(2)}, #{offset_neto.y.to_mm.round(2)}, " \
        "#{offset_neto.z.to_mm.round(2)}] mm  (magnitud #{delta_pos_mm.round(2)}mm, YA sin el desfase general)"
      lineas << "  ⚠️ diferencia grande + rotación -revisa a ojo si esta pareja es correcta, puede que el " \
        'emparejamiento voraz se haya equivocado de pieza-' if delta_pos_mm > 200 && angulo_deg > 30
      next unless angulo_deg >= UMBRAL_ROTACION_DEG
      lineas << "  rotación cambiada:  #{angulo_deg.round(2)}°"
      lineas << "    zaxis ANTES:    [#{fmt_vec(po[:zaxis])}]"
      lineas << "    zaxis DESPUÉS:  [#{fmt_vec(pc[:zaxis])}]"
      lineas << "    xaxis ANTES:    [#{fmt_vec(po[:xaxis])}]"
      lineas << "    xaxis DESPUÉS:  [#{fmt_vec(pc[:xaxis])}]"
    end
    lineas << '' if cambiadas.zero?
    lineas << '  (ninguna -todas las emparejadas quedaron dentro del umbral-)' if cambiadas.zero?

    if solo_original.any?
      lineas << ''
      lineas << "--- SOLO EN EL ORIGINAL -#{solo_original.length}, posiblemente QUITADAS al corregir- ---"
      solo_original.each { |p| lineas << "  #{p[:nombre]}  en [#{fmt_pt(p[:origin])}] mm" }
    end

    if solo_corregido.any?
      lineas << ''
      lineas << "--- SOLO EN LA CORRECCIÓN -#{solo_corregido.length}, posiblemente AGREGADAS al corregir- ---"
      solo_corregido.each { |p| lineas << "  #{p[:nombre]}  en [#{fmt_pt(p[:origin])}] mm" }
    end

    lineas << ''
    lineas << "Resumen: #{cambiadas} cambiadas, #{solo_original.length} quitadas, #{solo_corregido.length} agregadas " \
      "-de #{piezas_original.length} piezas originales-."
    texto = lineas.join("\n")
    puts texto

    require 'fileutils'
    FileUtils.mkdir_p(OUTPUT_DIR)
    ruta_archivo = File.join(OUTPUT_DIR, "comparacion_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt")
    File.write(ruta_archivo, texto)
    puts "📄 Comparación guardada en: #{ruta_archivo}"
  end

  # Empareja cada pieza del "antes" con la del "después" que tenga el
  # MISMO tipo -incluye el nombre real -CON-12/CON-21/CON-10- o "TUBO"
  # para todo lo demás- y quede MÁS CERCA en posición -voraz: va tomando
  # el par más cercano disponible primero, lo saca de ambas bolsas, y
  # repite-. Lo que sobra sin pareja en cada bolsa se reporta aparte.
  def emparejar(piezas_a, piezas_b)
    tipos = (piezas_a.map { |p| p[:tipo] } + piezas_b.map { |p| p[:tipo] }).uniq
    emparejadas = []
    sobran_a = []
    sobran_b = []

    tipos.each do |tipo|
      bolsa_a = piezas_a.select { |p| p[:tipo] == tipo }.dup
      bolsa_b = piezas_b.select { |p| p[:tipo] == tipo }.dup

      until bolsa_a.empty? || bolsa_b.empty?
        mejor = nil
        bolsa_a.each_with_index do |pa, ia|
          bolsa_b.each_with_index do |pb, ib|
            dist = pa[:origin].distance(pb[:origin])
            mejor = [ia, ib, dist] if mejor.nil? || dist < mejor[2]
          end
        end
        ia, ib, = mejor
        emparejadas << [bolsa_a[ia], bolsa_b[ib]]
        bolsa_a.delete_at(ia)
        bolsa_b.delete_at(ib)
      end
      sobran_a.concat(bolsa_a)
      sobran_b.concat(bolsa_b)
    end

    [emparejadas, sobran_a, sobran_b]
  end

  def mediana(valores)
    ordenados = valores.sort
    n = ordenados.length
    return 0.0.mm if n.zero?
    medio = n / 2
    n.odd? ? ordenados[medio] : (ordenados[medio - 1] + ordenados[medio]) / 2.0
  end

  def desfase_mediana(emparejadas)
    return Geom::Vector3d.new(0, 0, 0) if emparejadas.empty?
    deltas = emparejadas.map { |po, pc| pc[:origin] - po[:origin] }
    Geom::Vector3d.new(
      mediana(deltas.map(&:x)),
      mediana(deltas.map(&:y)),
      mediana(deltas.map(&:z))
    )
  end

  def angulo_entre(v1, v2)
    v1.angle_between(v2) * 180.0 / Math::PI
  end

  def fmt_pt(pt)
    "#{pt.x.to_mm.round(2)}, #{pt.y.to_mm.round(2)}, #{pt.z.to_mm.round(2)}"
  end

  def fmt_vec(v)
    "#{v.x.round(4)}, #{v.y.round(4)}, #{v.z.round(4)}"
  end

  # Piezas DIRECTAS del grupo seleccionado -no las tuercas/opresores de
  # adentro de cada conector; comparar a ese nivel de detalle no aporta
  # nada y satura el reporte-, con su transform absoluto -relativo al
  # grupo seleccionado, que es lo único que importa para comparar-.
  def piezas_directas(grupo)
    entities = grupo.is_a?(Sketchup::Group) ? grupo.entities : grupo.definition.entities
    (entities.grep(Sketchup::Group) + entities.grep(Sketchup::ComponentInstance)).map do |pieza|
      nombre = pieza.name.to_s.empty? ? '(sin nombre)' : pieza.name
      tipo = %w[CON-12 CON-21 CON-10].include?(nombre) ? nombre : 'TUBO'
      t = pieza.transformation
      { nombre: nombre, tipo: tipo, origin: t.origin, xaxis: t.xaxis, yaxis: t.yaxis, zaxis: t.zaxis }
    end
  end
end

# Se autoejecuta al pegar el script COMPLETO -si ya tienes 2 grupos
# seleccionados, compara de inmediato; si no, imprime cómo correrlo
# después- para no depender de acordarte de pegar una segunda línea
# aparte.
if Sketchup.active_model.selection.length == 2
  CompararGrupos.comparar_seleccion
else
  puts "ℹ️  Script cargado. Selecciona los 2 grupos -original del plugin y tu copia corregida- y vuelve a pegar TODO este script otra vez."
end
nil
