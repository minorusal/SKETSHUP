# Accesorios sueltos Play Idea

## Índice

- Alcance
- Costal/rodillo
- Reglas geométricas
- Estado funcional

## Alcance

Los accesorios individuales viven como scripts en `scripts/*_playidea.rb` y no pertenecen automáticamente al constructor modular ni al tobogán. Se cargan con `load` desde la consola Ruby de SketchUp. Mantener este flujo hasta que el usuario pida convertirlos en plugin o integrarlos al cotizador.

## Costal/rodillo

`scripts/costal_playidea.rb` genera variantes lisa y caramelo. Los datos históricos confirmados incluyen un cuerpo de 12 pulgadas de diámetro, una lona de 44 por 36 pulgadas y foam de 1 pulgada. Verificar siempre las constantes actuales antes de editar.

El cilindro se ha interpretado con 36 pulgadas de largo porque coincide con 36 discos de foam; tratarlo como una decisión del proyecto sujeta a corrección física, no como una verdad universal. La cinta caramelo fue corregida a 10 pulgadas. El hueco central está pensado para PVC nominal de 2 1/2 pulgadas; el código usa el diámetro exterior de PVC cédula 40 y holgura. Confirmar el tubo real si cambia el proveedor.

## Reglas geométricas

- Construir paredes huecas y losas anulares explícitamente.
- Triangular cintas helicoidales para evitar `ArgumentError: Points are not planar`.
- Calcular fronteras diagonales exactas; una cuadrícula de celdas pintadas produce bordes en escalera.
- Mantener perforado el cuerpo, cada disco, base y tapa si el PVC debe atravesar todo el rodillo.
- Dibujar costuras como puntadas separadas, no como líneas sólidas, y no inventar costura donde la unión es pegada.
- Cachear el disco de foam si la cantidad de geometría repetida vuelve lenta la creación.
- Validar que domos y tapas no invadan el hueco central.

La implementación vigente en la rama de Codex construye la tapa como una malla cerrada con cara exterior, cara interior y pared alrededor del hueco. Su faldón baja 2 pulgadas sobre el cuerpo. El PVC mide exactamente lo mismo que el cuerpo, sin sobresalir. Los 36 discos reutilizan una sola definición perforada mediante instancias; preservar estos contratos al hacer cambios posteriores.

## Estado funcional

El accesorio puede nombrar variantes para una futura cotización, pero no asumir que ya existen productos o tarifas en el cotizador/API. La integración de materiales y precios fue pospuesta. La naturaleza física de la tapa y su combinación de plástico, vinil, cinta y costura requiere confirmación del usuario antes de retirar o reinterpretar piezas.
