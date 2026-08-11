---
name: playidea-sketchup
description: Desarrollar, diagnosticar, probar y empaquetar los plugins y scripts Ruby de SketchUp del repositorio Play Idea. Usar al trabajar con cualquier loader, main.rb, HtmlDialog, paquete RBZ o script de geometría de este repositorio, especialmente constructor_modulos_playidea, conectores, tubos, toboganes, accesorios, albercas, plataformas, paneles, auditoría, etiquetado, coloreado y cotización.
---

# Play Idea SketchUp

Trabajar como especialista en la arquitectura Ruby/SketchUp y las convenciones geométricas propias de Play Idea. Tratar el código actual como fuente de verdad; usar estas referencias como conocimiento de dominio y guardas de seguridad.

## Flujo obligatorio

1. Identificar si la tarea afecta un plugin instalable, un script suelto o ambos.
2. Leer los archivos afectados y sus loaders antes de proponer cambios. No confiar en números de versión, nombres o estados históricos sin verificarlos en disco.
3. Cargar solo las referencias pertinentes de la tabla siguiente.
4. Separar hechos confirmados, datos proporcionados por el usuario y supuestos provisionales.
5. Para diagnósticos, determinar y explicar la causa antes de editar. Editar solo cuando el usuario pida corregir o implementar.
6. Preservar las piezas que el usuario haya confirmado como correctas. No reescribir geometría validada para resolver un problema localizado.
7. Verificar sintaxis, compatibilidad de Ruby, unidades, transformaciones y geometría en proporción al cambio.
8. Empaquetar un RBZ únicamente cuando la solicitud incluya una versión instalable o cuando sea parte natural de entregar el cambio. Verificar siempre su contenido.

## Referencias por tarea

- Leer [architecture.md](references/architecture.md) para estructura del repositorio, dependencias, alcance entre plugins, nomenclatura y materiales.
- Leer [geometry.md](references/geometry.md) para crear o corregir geometría, transformaciones, unidades, caras, componentes, tubos y colisiones.
- Leer [testing-and-packaging.md](references/testing-and-packaging.md) para pruebas, diagnóstico con mocks/capturas, compatibilidad Ruby y empaquetado RBZ.
- Leer [tobogan.md](references/tobogan.md) para cualquier archivo `tobogan*`, piezas del ducto, brazos, soleras, tornillería, ligas, entrada o integración con el constructor.
- Leer [accessories.md](references/accessories.md) para scripts sueltos de accesorios, especialmente `scripts/costal_playidea.rb`.
- Leer [current-state.md](references/current-state.md) al trabajar con versiones, pendientes conocidos o decisiones que podrían haber quedado obsoletas.

## Reglas invariables

- No modificar `conectores_playidea` ni `creador_tubos_playidea` desde una tarea del constructor sin autorización explícita. Si allí parece estar la causa, presentar evidencia y pedir permiso.
- Usar milímetros explícitos y convertirlos mediante `.mm` al crear puntos o longitudes para SketchUp. Recordar que la unidad interna es la pulgada.
- Normalizar los vectores usados como ejes de `Geom::Transformation.axes`; un eje no unitario escala la geometría.
- Triangular superficies torcidas o helicoidales. No pasar cuadrángulos no coplanares a `add_face`.
- Nombrar instancias cotizables con su código real (`instance.name = CODE`), no con etiquetas genéricas.
- Mantener materiales separados por acabado físico aunque compartan el mismo color; Twinmotion distingue acabados por material de SketchUp.
- No asumir que `ruby -c` valida la geometría. Combinar sintaxis con pruebas matemáticas, mocks o datos reales de SketchUp.
- No editar ni resumir `.claude/skills/` como parte de una tarea ordinaria; son la base independiente de Claude.

## Entrega

Indicar qué se modificó, qué se verificó y qué necesita validación visual en SketchUp. Si se genera un RBZ, informar su ruta y versión. Si una medida o decisión física sigue siendo provisional, declararla claramente.
