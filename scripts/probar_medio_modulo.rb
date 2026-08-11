# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# VERSION DEL SCRIPT: v2 (2026-08-07)
#
# QUÉ ES ESTO
# -----------
# TODO en una sola corrida -limpia cualquier rastro de pruebas
# anteriores en TODO el modelo, genera las 3 estructuras de prueba, y
# diagnostica los largos/cantidades de tubos X inmediatamente después,
# sin depender de que se corran varios scripts en el orden correcto-.
# Así el diagnóstico siempre corresponde exacto a lo que se acaba de
# crear en ESTA corrida, nada de una anterior.
#
# `spacing_x_mm`/`spacing_y_mm` ahora aceptan, además del Float uniforme
# de siempre, un Array de Floats -un ancho de columna/fila por elemento,
# mismo patrón que `spacing_z_mm` ya soportaba para alturas distintas
# por nivel-.
#
# IMPORTANTE: torres de triángulo y soleras NO se prueban aquí a
# propósito -torres no están permitidas en medios/cuartos de módulo;
# soleras todavía asumen ancho uniforme, no se han generalizado-.

MAIN_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea/main.rb'
LOADER_RB = '/Users/minorusal/Documents/SKETCHUP/constructor_modulos_playidea.rb'

CODIGO_NORMAL = 'PRUEBA-MOD-NORMAL'
CODIGO_MEDIO = 'PRUEBA-MOD-MEDIO'
CODIGO_CUARTO = 'PRUEBA-MOD-CUARTO'

STANDARD_MM = 1168.4 # spacing_x_m/y_m real = 1.1684m, ver probar_dialogo_completo.rb

begin
  load LOADER_RB unless defined?(PlayIdea::ConstructorModulos::EXTENSION)
  load MAIN_RB
  puts "🔄 constructor_modulos_playidea recargado desde el archivo fuente."

  model = Sketchup.active_model

  # Purga CUALQUIER grupo 'PRUEBA-MOD-*' en TODO el modelo -a cualquier
  # nivel de anidamiento, no solo el contexto activo-, para garantizar
  # que lo que se mida después sea EXCLUSIVAMENTE de esta corrida.
  def purgar_pruebas(entities, borrados = [0])
    entities.grep(Sketchup::Group).each do |g|
      if g.name.to_s.start_with?('PRUEBA-MOD-')
        borrados[0] += 1
        g.erase!
      elsif g.valid?
        purgar_pruebas(g.entities, borrados)
      end
    end
    borrados[0]
  end
  model.start_operation('Purgar pruebas medio módulo', true)
  total_purgados = purgar_pruebas(model.entities)
  model.commit_operation
  puts "🧹 Borrados #{total_purgados} grupo(s) 'PRUEBA-MOD-*' de corridas anteriores."

  def base_params(code, modules_x, modules_y, spacing_x_mm, spacing_y_mm)
    {
      modules_x: modules_x, modules_y: modules_y, modules_z: 2,
      spacing_x_mm: spacing_x_mm, spacing_y_mm: spacing_y_mm, spacing_z_mm: STANDARD_MM,
      color: 'Azul', code: code,
      connectors: true, padding: false,
      padding_color_mode: 'single', padding_color_vertical: 'Azul', padding_color_horizontal: 'Azul',
      solera: false
    }
  end

  # 1) Referencia: 3x2x2 completo, ancho uniforme.
  origen_normal = Geom::Point3d.new(0, 0, 0)
  params_normal = base_params(CODIGO_NORMAL, 3, 2, STANDARD_MM, STANDARD_MM)
  estructura_normal = PlayIdea::ConstructorModulos.create_module(params_normal, origen_normal)
  raise 'create_module (normal) devolvió nil' unless estructura_normal

  # 2) 3 columnas en X: 2 normales + 1 media -toda la fila final en X a
  #    la mitad de ancho-. Y uniforme, 2 filas.
  origen_medio = Geom::Point3d.new(0, (STANDARD_MM * 3).mm, 0)
  params_medio = base_params(CODIGO_MEDIO, 3, 2, [STANDARD_MM, STANDARD_MM, STANDARD_MM / 2.0], STANDARD_MM)
  estructura_medio = PlayIdea::ConstructorModulos.create_module(params_medio, origen_medio)
  raise 'create_module (medio) devolvió nil' unless estructura_medio

  # 3) 2 columnas en X: 1 normal + 1 a un cuarto de ancho.
  origen_cuarto = Geom::Point3d.new(0, (STANDARD_MM * 6).mm, 0)
  params_cuarto = base_params(CODIGO_CUARTO, 2, 2, [STANDARD_MM, STANDARD_MM / 4.0], STANDARD_MM)
  estructura_cuarto = PlayIdea::ConstructorModulos.create_module(params_cuarto, origen_cuarto)
  raise 'create_module (cuarto) devolvió nil' unless estructura_cuarto

  puts '✅ Generadas las 3 estructuras de prueba.'

  # Diagnóstico inmediato -misma corrida, mismos objetos recién creados-.
  def largos_tubo_x(entities, encontrados = Hash.new(0))
    entities.grep(Sketchup::ComponentInstance).each do |instance|
      name = instance.definition.name.to_s
      next unless name.start_with?('TUB-MOD-X-')
      largo = name.sub('TUB-MOD-X-', '').to_f
      encontrados[largo] += 1
    end
    entities.grep(Sketchup::Group).each { |g| largos_tubo_x(g.entities, encontrados) }
    encontrados
  end

  [
    ['Normal (3x2x2, sin fracciones, esperado: 27 de 1120.1mm)', estructura_normal],
    ['Medio (2 normales + 1 media en X, esperado: 18 de 1120.1mm + 9 de 535.9mm)', estructura_medio],
    ['Cuarto (1 normal + 1 cuarto en X, esperado: 9 de 1120.1mm + 9 de 243.8mm)', estructura_cuarto]
  ].each do |etiqueta, grupo|
    puts ''
    puts "#{etiqueta}:"
    largos_tubo_x(grupo.entities).sort.each do |largo, cantidad|
      puts "  #{cantidad} tubos X de #{largo}mm"
    end
  end

  model.active_view.zoom([estructura_normal, estructura_medio, estructura_cuarto])
  model.selection.clear
  [estructura_normal, estructura_medio, estructura_cuarto].each { |e| model.selection.add(e) }
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(10)
end
nil
