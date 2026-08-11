# Estado actual y puntos que siempre deben verificarse

## Versiones observadas al crear este skill

Estas versiones son una instantánea del 11 de agosto de 2026, no una fuente permanente. Leer siempre el loader antes de actuar.

| Plugin | Versión del loader |
|---|---:|
| `alberca_esponjas_playidea` | 0.1.1 |
| `alberca_pelotas_playidea` | 0.1.0 |
| `auditor_juegos` | 0.2.0 |
| `auto_etiquetado_playidea` | 1.2.0 |
| `colorear_tubos_playidea` | 0.1.1 |
| `conectores_playidea` | 0.8.0 |
| `constructor_modulos_playidea` | 0.30.1 |
| `cotizador_playidea` | 0.23.0 |
| `creador_plataformas_playidea` | 0.1.0 |
| `creador_tubos_playidea` | 0.2.0 |
| `panel_laberinto_playidea` | 0.2.0 |

Los RBZ visibles pueden ir detrás de los loaders. Por ejemplo, al crear este skill el constructor tenía loader 0.30.1 pero el paquete visible más nuevo era 0.21.0; cotizador tenía loader 0.23.0 pero RBZ 0.19.0; conectores tenía loader 0.8.0 aunque existían RBZ 0.9.0 y 0.10.0. No publicar ni instalar basándose solo en nombres de paquetes.

## Pendientes que requieren confirmación

- Verificar cualquier medida marcada como provisional directamente con el usuario o contra una pieza real.
- Confirmar la construcción física de la tapa del costal antes de cambiar materiales, cinta o costuras.
- Confirmar visualmente en SketchUp las funciones nuevas sin referencia física equivalente.
- Mantener fuera del skill cualquier precio o ID de catálogo que solo provenga de memoria conversacional y no exista en archivos o fuente consultable.

## Historial de Claude

Los archivos `.claude/skills/*/SKILL.md` conservan la bitácora completa de experimentos y correcciones. Consultarlos solo cuando sea necesario reconstruir una decisión histórica no cubierta aquí. No tratarlos como estado vigente sin contrastar cada afirmación con el código.
