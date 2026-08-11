# Arquitectura y convenciones del repositorio

## Índice

- Tipos de artefacto
- Plugins y dependencias
- Alcance y fuentes de verdad
- Nombres, atributos y materiales
- Interfaces HTML

## Tipos de artefacto

Un plugin instalable suele tener:

- `nombre.rb`: loader que registra `SketchupExtension` y contiene la versión vigente.
- `nombre/main.rb`: lógica principal.
- `nombre/selector.html` u otros HTML: interfaz `UI::HtmlDialog`.
- `nombre/README.md`: documentación propia, si existe.
- `nombre_vX.Y.Z.rbz`: ZIP instalable con el loader y la carpeta, sin directorio contenedor adicional.

Los archivos en `scripts/` son prototipos o utilidades que se ejecutan con `load` desde la consola Ruby de SketchUp. No confundirlos con plugins RBZ. Algunas funciones se prueban primero como script suelto y después se portan al plugin real.

## Plugins y dependencias

El repositorio incluye constructor de módulos, conectores, tubos, plataformas, albercas, panel de laberinto, auditor, autoetiquetado, coloreado y cotizador, además de scripts experimentales.

`constructor_modulos_playidea/main.rb` depende de:

```ruby
require 'creador_tubos_playidea/main'
require 'conectores_playidea/main'
```

Estos son plugins separados. No duplicar ni incluir sus carpetas dentro del RBZ del constructor. El usuario los instala de forma independiente.

## Alcance y fuentes de verdad

- Leer el loader real para conocer la versión; no deducirla del RBZ más reciente.
- Leer el código real antes de usar una fórmula descrita en una bitácora.
- Conservar `conectores_playidea` y `creador_tubos_playidea` cuando una tarea solo autoriza cambios al constructor.
- Preferir reutilizar funciones públicas existentes como `build_connector_geometry`, `add_hollow_geometry`, `add_sleeve` y `add_branch_sleeve`.
- No copiar una implementación experimental al plugin real sin comparar ambas versiones y probar las fórmulas.

## Nombres, atributos y materiales

- El cotizador recorre jerarquías y prioriza `entity.name`; si está vacío usa el nombre de definición. Poner el código real en el nombre de instancia.
- El recubrimiento reconoce tubos por prefijo `TUB-` y extrae longitudes decimales del nombre. Mantener ese contrato al crear tubos estructurales nuevos.
- Mantener códigos y diccionarios de atributos estables para que auditor, recubrimiento y cotizador sigan reconociendo las piezas.
- Separar materiales según el acabado físico. Foam, vinil y fibra de vidrio pueden compartir hex, pero deben poder mapearse a materiales distintos en Twinmotion.

## Interfaces HTML

- Mantener sincronizados IDs, payload JSON, validación Ruby y valores predeterminados.
- Validar selecciones de celda/orilla/índice tanto en JavaScript como en Ruby.
- Cuando varios selectores comparten un canvas, hacer explícito cuál recibe el siguiente clic; el último selector activado debe convertirse en el objetivo activo.
- No agregar opciones que requieren canvas a diálogos automáticos sin vista previa.
