# Auditor de Juegos Modulares para SketchUp

Versión 0.2.0.

Primera versión de una extensión Ruby que revisa la organización técnica de un
modelo y produce un inventario preliminar de sus piezas.

## Instalación para prueba

1. Comprime `auditor_juegos.rb` y la carpeta `auditor_juegos` en un archivo ZIP.
2. Cambia la extensión del ZIP a `.rbz`.
3. En SketchUp abre **Extensiones > Administrador de extensiones > Instalar extensión**.
4. Reinicia SketchUp si fuera necesario.
5. Abre un diseño y ejecuta **Extensiones > Auditor de Juegos Modulares >
   Analizar modelo actual**.

También puede copiarse el archivo y la carpeta directamente al directorio
`Plugins` de SketchUp durante el desarrollo.

## Qué revisa esta versión

- Componentes, grupos y geometría suelta.
- Nombres genéricos o ausentes.
- Código de pieza en el diccionario de atributos `minorusal_auditor`.
- Materiales faltantes.
- Escala no uniforme.
- Organización básica mediante etiquetas.
- Elementos ocultos.
- Definiciones y materiales sin uso.
- Conteo preliminar de piezas.
- Análisis jerárquico de grupos y componentes.
- Ruta completa de cada grupo anidado.
- Dimensiones globales en metros, material, etiqueta y geometría directa.
- Clasificación preliminar de tubos, ensambles, plataformas, redes y accesorios.
- Exportación de hallazgos e inventario a CSV.

El comando **Analizar por grupos (selección o modelo)** analiza los grupos
seleccionados. Si no hay ningún grupo seleccionado, analiza el modelo completo.
Esta operación es de sólo lectura y no cambia etiquetas ni geometría.

## Alcance

La auditoría técnica no reemplaza una revisión visual o de ingeniería. Para
evaluar estética, seguridad, procesos de fabricación y costos se deben añadir
las reglas y estándares reales del fabricante.
