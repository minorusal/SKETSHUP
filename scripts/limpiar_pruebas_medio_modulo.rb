# Pega esto en la consola de Ruby ANTES de volver a correr
# probar_medio_modulo.rb. Borra CUALQUIER grupo -en cualquier nivel de
# anidamiento, no solo en el contexto activo- cuyo nombre empiece con
# 'PRUEBA-MOD-', para descartar que estemos viendo geometría acumulada
# de corridas anteriores.

def purgar_pruebas(entities, borrados = [0])
  entities.grep(Sketchup::Group).each do |g|
    if g.name.to_s.start_with?('PRUEBA-MOD-')
      borrados[0] += 1
      g.erase!
    else
      purgar_pruebas(g.entities, borrados) if g.valid?
    end
  end
  borrados[0]
end

model = Sketchup.active_model
model.start_operation('Purgar pruebas medio módulo', true)
total = purgar_pruebas(model.entities)
model.commit_operation
puts "🧹 Borrados #{total} grupo(s) 'PRUEBA-MOD-*' en todo el modelo."
nil
