---
name: sketchup-plugins
description: Contexto y flujo de trabajo para depurar/extender los plugins Ruby de SketchUp en este repo (Play Idea + Auditor de Juegos). Úsala siempre que se trabaje en auditor_juegos, conectores_playidea, constructor_modulos_playidea o creador_tubos_playidea.
---

# Plugins de SketchUp — Play Idea / Auditor de Juegos

## Qué hay en este repo

Cuatro extensiones de SketchUp, cada una con el patrón: loader `nombre.rb` en la
raíz (registra `SketchupExtension`) + carpeta `nombre/` con `main.rb` (lógica),
`selector.html` (UI en `UI::HtmlDialog`, si aplica) y `README.md` (changelog).
Los `.rbz` en la raíz son paquetes ya comprimidos listos para instalar.

- **creador_tubos_playidea** — tubos huecos paramétricos. Base de los otros.
- **conectores_playidea** — biblioteca de 8 conectores estructurales (10, 12,
  19, 21, 35, 40, 61, COPLE). El más grande y con más historial de ajustes
  geométricos finos (ver su README para el detalle versión por versión).
- **constructor_modulos_playidea** — genera cuadrículas 3D combinando los dos
  anteriores. Los usa vía `require 'conectores_playidea/main'` /
  `'creador_tubos_playidea/main'` y llama sus funciones públicas
  (`build_connector_geometry`, `add_hollow_geometry`, `add_sleeve`,
  `add_branch_sleeve`, etc.) directamente — **no los duplica ni los empaqueta**
  dentro de su propio `.rbz`. Su `.rbz` solo trae su propio loader + carpeta.
- **auditor_juegos** — independiente, analiza cualquier modelo y lee el
  diccionario compartido `minorusal_auditor` que los otros tres escriben.

## Reglas de alcance (pedidas explícitamente por el usuario)

- No modificar `conectores_playidea` ni `creador_tubos_playidea` desde
  `constructor_modulos_playidea` sin autorización explícita — el usuario
  considera esos dos "ya correctos" y solo quiere que el constructor los
  orqueste. Si una investigación apunta a que el bug real vive ahí, **pedir
  permiso antes de tocarlos**, incluso si ya se autorizó una vez (puede que la
  próxima vez la respuesta sea distinta).
- Nunca reescribir geometría "inventando" una variante nueva como parche
  rápido: ya pasó una vez (ver Bitácora) y produjo geometría peor, no mejor.
  Preferir primero verificar numéricamente (ver más abajo) antes de tocar
  código.

## Reempacar un `.rbz` tras editar código

El `.rbz` es solo un zip renombrado con el loader + la carpeta del plugin en
la raíz del zip (sin carpeta contenedora extra). Patrón:

```bash
zip -X nombre_vX.Y.Z.rbz.new nombre.rb nombre/main.rb nombre/README.md nombre/selector.html
mv nombre_vX.Y.Z.rbz.new nombre_vX.Y.Z.rbz
unzip -l nombre_vX.Y.Z.rbz   # verificar que main.rb cambió de tamaño/fecha
```

`constructor_modulos_playidea.rbz` **no** necesita reempacarse si solo se editó
`conectores_playidea` o `creador_tubos_playidea` — son plugins separados que
el usuario instala independientemente.

## Gotcha crítico: SketchUp no recarga Ruby en caliente

Reinstalar un `.rbz` actualizado con SketchUp abierto **no** recarga el código
Ruby ya cargado en esa sesión. El usuario debe **cerrar y volver a abrir
SketchUp por completo** después de reinstalar, o cualquier prueba seguirá
corriendo el código viejo. Confirmar esto explícitamente si un fix "no hizo
nada" antes de asumir que el fix está mal.

## No hay acceso a SketchUp — flujo de depuración por capturas

No hay SketchUp instalado en este entorno. Todo diagnóstico visual depende de
que el usuario tome capturas y las deje en el Escritorio (`~/Desktop`).

- Los nombres de captura de macOS usan un **espacio angosto sin separación
  (U+202F)** antes de "a.m."/"p.m." (`Screenshot 2026-07-27 at 3.05.06 p.m..png`
  con ese carácter especial, no un espacio normal). Nunca retipear el nombre a
  mano — siempre listar el directorio con Python/`os.listdir` y copiar por
  índice/mtime a un nombre normal en el scratchpad antes de leer con `Read`.
- Ordenar por `mtime` (no por nombre) para encontrar "la última imagen".
- Cuando el usuario dice "la penúltima es la mala, la última es la buena",
  confirmar cuáles dos archivos son exactamente antes de analizar — pedir
  aclaración si hay ambigüedad sobre cuántas capturas nuevas hay.

## Verificar geometría con matemática, no solo a ojo en la foto

Las capturas son en perspectiva y engañan fácil (¿es un hueco real o solo el
ángulo de cámara mirando hacia la boca de un tubo hueco corto y gordo?). Hay
dos herramientas complementarias — usar ambas antes de editar código:

### 1. Pedir datos exactos desde SketchUp (preferido, no depende de fotos)

`scripts/inspect_geometry.rb` (en la raíz del proyecto, no en `.claude/`, para
que sea visible en Finder) reporta cada pieza en DOS sistemas de coordenadas:
local (relativo al padre inmediato, como antes) y **MUNDO** (absolutas del
modelo, acumulando todos los transforms de los ancestros — el script hace
esa multiplicación, no hay que hacerla a mano). Esto se agregó en la ronda 6
porque comparar a mano una pieza anidada 3 niveles adentro de un conector
contra un tubo que cuelga directo del módulo raíz (dos sistemas de
coordenadas locales distintos) fue la causa de al menos un error de cálculo
en rondas anteriores. También imprime al final una tabla plana con las
coordenadas de mundo de TODAS las piezas inspeccionadas, para comparar
cualquier par sin rastrear el árbol. Es un script que el
**usuario** pega en Ventana > Consola de Ruby de SketchUp con la pieza
seleccionada. Imprime, por cada sub-grupo/componente: bounds min/max en mm,
tamaño, origen y ejes de su `transformation`, y el hueco/encime (mm, por eje)
entre cada par de sub-piezas. Pedirle al usuario que lo corra sobre:
- la pieza que sale mal (para ver bounds/gaps reales, no interpretados), y
- si existe, una referencia armada a mano de cómo debería verse, para
  comparar números contra números.

Este texto es la fuente de verdad — más confiable que cualquier captura.

### 2. Simular las fórmulas del plugin en Ruby puro (para probar un fix ANTES de tocar código)

1. Escribir un mock mínimo de la API `Geom` de SketchUp en Ruby puro
   (`Point3d`, `Vector3d`, `Transformation` con `axes`/`translation`/
   `rotation`, `Numeric#mm`/`#degrees`) — no requiere SketchUp instalado.
2. Portar **literalmente** las fórmulas relevantes del `main.rb` real (no
   reinventar) para calcular coordenadas de mundo exactas.
3. Comparar distancias/tangencias numéricamente antes de proponer un fix.
4. Verificar el fix propuesto con el mismo script ANTES de aplicarlo al
   código real — en este proyecto ya pasó que un fix "parecía lógico" pero
   la verificación numérica después de aplicarlo mostró que empeoraba el
   contacto entre piezas (ver Bitácora). Idealmente, contrastar el resultado
   del mock contra los números reales de `inspect_geometry.rb` (herramienta 1)
   para confirmar que el mock replica el comportamiento real antes de confiar
   en él.

## Bitácora de hallazgos (ir agregando aquí)

- **`constructor_modulos_playidea`**: conector `26` (recto, dos salidas
  opuestas) es código muerto — `connector_code_for_horizontal` nunca puede
  seleccionarlo para una cuadrícula válida (nx,ny≥1), porque un mismo nodo no
  puede tener simultáneamente ambas direcciones de un eje y cero del otro sin
  que nx=0 o ny=0. No confirmado si se corrige o se elimina.
- **Conector 21 (`conectores_playidea/main.rb`, `build_21`) — RESUELTO.** Al
  insertarlo solo se veía como una "dona/gancho" en vez de tres brazos rectos.
  Dos intentos fallaron por adivinar desde fotos en perspectiva (un intento de
  "emparejar" el offset de `green_origin` con el de `blue`/`main` restándole
  el mismo radio empeoró el contacto — verificado con script numérico,
  revertido). La causa real se confirmó con `scripts/inspect_geometry.rb`
  corrido por el usuario sobre la pieza mala y sobre una referencia armada a
  mano: `green_origin` arrancaba exactamente en el nodo `(radius, 0, radius)`
  y se extendía 50.8mm solo hacia adelante, mientras `blue`/`main` sí estaban
  retrocedidos un radio. Eso dejaba a `green` tocando a `blue` en una línea de
  solo 24.15mm (la mitad del diámetro), dejando el resto del borde de `blue`
  sin cobertura — ahí se veía el hueco. Fix aplicado: centrar `green_origin`
  sobre el nodo restándole `short_length / 2.0` (25.4mm) en su propio eje de
  avance, en vez de arrancar en el nodo. Eso duplica la línea de contacto a
  48.3mm (el diámetro completo). Verificado numéricamente contra los datos
  reales de consola del usuario (coincide dentro de ~0.2mm, la imprecisión
  normal de mover a mano). Empaquetado en `conectores_playidea_v0.8.0.rbz`.
  **Lección**: `scripts/inspect_geometry.rb` corrido sobre la pieza mala Y
  sobre una referencia buena, comparando números línea por línea, resolvió en
  un intento lo que dos rondas de interpretación de fotos no lograron —
  preferir este método desde el principio la próxima vez que haya un defecto
  geométrico reportado.

  **Ronda 2 (con el mismo método):** tras centrar `green_origin`, quedaba un
  segundo defecto invisible a simple vista en la foto pero obvio en los
  números: la tuerca de `green` (siempre colocada en su eje local +X por
  `add_hardware`) apuntaba hacia -X, directo hacia el cuerpo de `blue`
  (18-19mm de encime en la tabla de gaps). `local_axes()` es compartida por
  todos los conectores — no tocar esa función. Fix: `green.transform!` con un
  giro de 180° alrededor de su propio eje (`Geom::Transformation.rotation
  (green_origin, Y_AXIS, 180.degrees)`) justo después de crear el grupo,
  antes o después de `add_hardware` (da igual, el hardware es hijo del grupo
  y se mueve con él). Verificado que reproduce exactamente los signos de
  `xaxis`/`yaxis` de la referencia buena. Diferencias residuales de ~0.2-0.7mm
  en `origin.x` entre ambas capturas de consola se consideran imprecisión
  normal de mover/rotar a mano en SketchUp, no una corrección pendiente.
- `constructor_modulos_playidea` fue revertido a su geometría original (solo
  usa `PlayIdea::Conectores.build_connector_geometry` sin variantes propias)
  tras confirmar que un intento de geometría asimétrica personalizada para el
  nivel 0 (conectores 35/40 tocando el 61) producía piezas mal formadas.

- **Hueco vertical del nivel 0 (35/40 sin tocar el 61) — RESUELTO, ronda 2.**
  El usuario reprodujo el problema completo en un módulo 1x1x1 real, corrigió
  a mano en SketchUp la esquina de abajo (solo 21 en un 1x1x1), y corrió
  `inspect_geometry.rb` sobre el módulo malo y sobre su corrección — comparé
  ambos volcados con un script propio (`diff_dumps.py`, normalizando por la
  posición del CON-61 de cada esquina ya que el usuario movió el módulo en la
  escena). Hallazgo: bajó TODA la parrilla horizontal del nivel 0 (tubos y
  conectores) de `BASE_GRID_HEIGHT_MM` (138.45mm) a `BOTTOM_GRID_HEIGHT_MM`
  (76.2mm = 50.8 tope del 61 + 25.4 mitad del largo de "Verde"), y giró el
  conector 21 de abajo: en vez de que "Principal" (asimétrico, 87.65mm de
  alcance) toque el 61, ahora es "Verde" (ya centrada ±25.4mm por el fix de
  green_origin) quien lo toca, y "Principal" pasa a servir la dirección Y.
  A esta altura más baja, "Principal" ya no alcanzaría el 61 sin invertirse
  bajo tierra, y el manguito central de 35/40 (ya simétrico ±31.75mm) SÍ
  alcanza a tocarlo casi exacto (pequeño traslape de ~6mm, aceptable) sin
  necesitar geometría especial — se resuelve solo con el cambio de altura.
  Implementado: `BOTTOM_GRID_HEIGHT_MM`, `bottom_corner_transform` (mismo
  patrón que `corner_transform` pero con `yaxis=Z_AXIS`, `zaxis=y_target.
  reverse`, mismo ancla `(-radius,0,-radius)` — un primer intento con un
  ancla extra de 25.4mm en Y fue un error de doble conteo, revertido),
  `bottom_level_transform` (dispatcher para k=0; 26/35/40 reusan las
  rotaciones existentes sin cambios). Aplica solo a `k.zero?`; niveles
  superiores (k≥1) sin cambios. Verificado con `geom_mock.rb`: posición del
  CON-21 y ejes coinciden con los datos de consola del usuario dentro de
  ~0.3mm; verde toca el 61 en `[50.8, 101.6]` exacto; blue queda a Z=76.2,
  igual que el tubo X (antes de verificar esto por separado casi se envía un
  fix con blue desalineado del tubo — clave revisar TODOS los brazos, no solo
  el que motivó el cambio). Empaquetado en `constructor_modulos_playidea_v0.5.0.rbz`.
  **Lección de proceso**: cuando el usuario ya corrió el script de inspección
  en dos estados (malo/bueno) él mismo, compararlos con un script propio
  (parseo + diff normalizado) en vez de pedir más descripciones en palabras —
  la data ya contenía la respuesta completa.

  **Ronda 3 (revertida en ronda 5, ver abajo)**: con el fix anterior, el
  nivel 0 salió idéntico en malo/bueno (confirmado, cerrado). Se creyó ver
  una diferencia de ~24mm en el nivel de ARRIBA (último nivel, k==nz) y se
  "corrigió" sumando `RECEIVER_RADIUS_MM.mm` a `z` solo para `k==nz &&
  code=='21'`, para que "Principal" alcanzara la punta exacta del poste.
  **Esto resultó ser un error**: ver ronda 5.

  **Ronda 4**: `inspect_geometry.rb` se hizo recursivo (bajaba solo 1 nivel
  antes; ahora baja hasta dentro de los conectores, `MAX_DEPTH=4`) porque el
  usuario señaló que el script no daba toda la información necesaria — tenía
  razón, faltaba lo que hay DENTRO de cada conector. Con los volcados
  recursivos y un `diff` real (no lectura a ojo) se confirmó que TODOS los
  CON-61 y CON-21 (12 piezas) eran 100% idénticos entre malo/bueno — el fix
  de la ronda 3 parecía estar funcionando. La única diferencia real estaba en
  2 de los 12 tubos (el X y el Y del nivel superior), que en "bueno" quedaron
  ~24mm más arriba que los conectores mismos y con tamaños distintos.

  **Ronda 5 — causa raíz real, fix de la ronda 3 revertido**: el usuario
  aclaró que TODO en "bueno" es intencional, incluyendo mover esos tubos —
  no era ruido de edición manual, como se asumió por error en la ronda 4. Al
  recalcular con los datos recursivos del propio "malo" (con el fix de la
  ronda 3 activo): el conector de la esquina superior queda en Z=1306.85,
  pero su "Azul" interno (`local origin (0,0,radius)` transformado por la
  instancia) termina en **Z=1331.0** — exactamente 1306.85+24.15. El fix de
  la ronda 3 sube TODO el conector como cuerpo rígido (para que "Principal"
  alcance la punta del poste), pero eso también sube "Azul"/"Verde" con él —
  y el tubo horizontal se sigue creando en la altura vieja (1306.85), sin
  moverse. El usuario estaba tapando ese hueco moviendo los tubos a mano; la
  causa real era mi propio fix de la ronda 3. Revertido por completo (línea
  `z += RECEIVER_RADIUS_MM.mm if k == nz && code == '21'` eliminada) — el
  pequeño tramo de poste que sobresale sin tocar nada en la punta del último
  nivel (24.15mm) nunca fue reportado como problema real por el usuario; es
  análogo a como blue/green tampoco cubren la longitud completa del tubo
  horizontal en ningún otro nivel, así que probablemente ni haga falta
  corregirlo. Empaquetado en constructor_modulos_playidea_v0.5.0.rbz.

  **Lección de proceso (repetida, esta vez con más costo)**: verificar UN
  ángulo del fix (aquí: "¿Principal ya toca la punta del poste?") sin
  reverificar los otros dos brazos del mismo conector después del cambio.
  Ya había pasado con el fix de `green` (rondas 1-2) y volvió a pasar con el
  fix del nivel superior. Regla a seguir siempre: tras cualquier cambio de
  posición/rotación de un conector con más de un brazo, releer TODOS sus
  brazos (no solo el que motivó el cambio) contra la altura/posición de sus
  tubos correspondientes antes de dar el fix por bueno.

  **Ronda 6/7 — fix correcto: subir tubos Y conectores juntos.**
  `inspect_geometry.rb` se mejoró para reportar coordenadas de MUNDO
  (absolutas, acumulando transforms de ancestros) además de las locales —
  necesario porque comparar a mano una pieza anidada 3 niveles adentro de un
  conector contra un tubo que cuelga directo del root fue la causa del error
  de la ronda 5. Con datos de mundo reales del usuario se confirmó: la
  intuición original de la ronda 3 (subir el conector del último nivel un
  radio para que "Principal" alcance la punta del poste) SÍ era correcta —
  el error de la ronda 3 fue mover solo el conector y no los tubos con él.
  Fix final: helper `grid_level_z(k, nz, sz)` compartido por
  `create_grid_tubes` y `create_grid_connectors`, que centraliza la altura
  de cada parrilla — nivel 0 usa `BOTTOM_GRID_HEIGHT_MM`, último nivel
  (`k==nz`) suma `RECEIVER_RADIUS_MM` a la fórmula normal, niveles
  intermedios sin cambio. Como es un desplazamiento uniforme en Z (sin
  reorientar nada, a diferencia del fix del nivel 0), no hizo falta una
  variante nueva de `connector_transform` — el mismo de siempre funciona
  con el `point.z` ya desplazado. Verificado: predice point.z=1331.0 (dato
  real del usuario=1330.234) y origin.z del conector=1306.85 (dato
  real=1306.084), ambos dentro de ~0.8mm. Empaquetado en
  constructor_modulos_playidea_v0.5.0.rbz.

  **Ronda 8 — causa raíz REAL del "no embona", encontrada por fin.**
  Tras el fix del nivel superior, el usuario seguía viendo mal ajuste.
  Varias rondas de comparar capturas casi idénticas no sirvieron — el
  render en SketchUp es demasiado sutil para diferenciar a ojo estos
  problemas; hay que pedir `inspect_geometry.rb` desde el principio, no
  como último recurso. La descripción en palabras simples del usuario
  ("el tubo atraviesa la geometría del conector" vs "choca con la pared")
  fue lo que por fin desbloqueó el diagnóstico correcto — más útil que
  cualquier captura. Con `inspect_geometry.rb` corrido sobre el CONECTOR +
  EL TUBO seleccionados juntos (no el módulo completo) en malo y bueno: el
  tubo horizontal arranca exactamente en el nodo matemático (X=0) y llega
  hasta el siguiente nodo (X=sx) — pero el receptor del conector (Azul)
  no empieza a cubrirlo hasta un radio (24.15mm) más adentro del nodo. Eso
  deja un tramo de ~24mm de tubo desnudo/expuesto en cada extremo, antes
  de "entrar" al receptor — visualmente se ve como si el tubo la
  atravesara en vez de terminar limpio contra la pared del conector. El
  usuario lo corrigió a mano acortando el tubo para que arranque ya
  dentro de la zona cubierta por el receptor. Fix: nueva constante
  `HORIZONTAL_TUBE_INSET_MM = RECEIVER_RADIUS_MM`; los tubos X/Y ahora se
  crean `2 * INSET` más cortos y se colocan desplazados `+INSET` desde el
  nodo en su propio eje de avance — arrancan y terminan ya dentro de la
  zona de cobertura del receptor en ambos extremos, sin tramo expuesto.
  Solo aplica a tubos horizontales (X, Y); el poste vertical (Z) es un
  solo tramo continuo por columna, diseño distinto, no tocado. Verificado
  contra los datos reales del usuario (tube_start y tube_length calculados
  coinciden dentro de ~2-3mm). Empaquetado en
  constructor_modulos_playidea_v0.5.0.rbz.

  **Lección de proceso, la más cara de todas**: cuando las capturas de
  pantalla se ven "casi iguales" entre malo y bueno pero el usuario insiste
  en que hay diferencia, NO es momento de comparar más capturas — es
  momento de pedir `inspect_geometry.rb` sobre la pieza exacta en cuestión
  (conector + tubo juntos, no el módulo completo) y/o pedir una descripción
  en palabras simples de qué se ve mal. Ambas cosas, combinadas, resolvieron
  en un intento lo que ~4 rondas de comparar imágenes no lograron.

  **Ronda 9 — el inset de la ronda 8 sobrecorrigió "Verde" (Y en k>=1).**
  Tras la ronda 8 casi todo embonaba, pero el usuario reportó lo opuesto:
  tuvo que ALARGAR ciertos tubos a mano para que "atravesaran" el conector,
  justo lo contrario del fix anterior. La ronda 8 asumió que TODOS los
  receptores horizontales tienen el mismo patrón asimétrico que Azul (boca
  a un radio del nodo, hacia adelante). Falso: derivando a mano la
  composición `world_axes * local_anchor_correction` de `corner_transform`
  sobre la geometría local de `build_21` (conectores_playidea/main.rb) se
  confirma que "Verde" —el receptor Y en niveles k>=1, ver el comentario de
  centrado en `build_21`— quedó CENTRADA sobre el nodo (cubre de
  nodo-25.4mm a nodo+25.4mm), no desplazada hacia adelante como Azul. Un
  tubo apenas insetado 24.15mm nunca llega a la pared trasera del receptor.
  "Principal" en cambio SÍ sigue el patrón asimétrico de Azul (confirmado
  con la misma derivación sobre `bottom_corner_transform`), y como en el
  nivel 0 es Principal quien sirve la dirección Y (ver comentario de
  `BOTTOM_GRID_HEIGHT_MM`), el inset original SÍ es correcto ahí. Fix:
  nueva constante `VERDE_HALF_LENGTH_MM = 25.4`; los tubos Y se dividen en
  dos definiciones — `y_bottom` (k==0, igual que antes, insetados) y
  `y_upper` (k>=1, alargados `+VERDE_HALF_LENGTH_MM` en cada extremo en vez
  de acortados). Verificado con Ruby puro contra datos reales de una
  referencia "bueno" hecha a mano: la fórmula predice el extremo cercano
  del tubo a 0.19mm del valor medido (el extremo lejano varía ~3.9mm, más
  esperable tratándose de un ajuste manual arrastrado a ojo, no tecleado).
  Empaquetado en constructor_modulos_playidea_v0.6.0.rbz.

  **Ronda 10 — confirmado: 35/40 necesitaban su propio offset, y además
  un tubo puede tener conectores DISTINTOS en cada extremo.**
  El usuario probó un módulo de más de 1 en X/Y (activa conectores 35/40,
  antes nunca ejercitados) y reportó "varios errores". `inspect_geometry.rb`
  sobre el módulo completo lo confirmó: el error de la ronda 9 (extender
  los tubos Y de k>=1 por VERDE_HALF_LENGTH_MM) se aplicaba de forma
  UNIFORME a todos los tubos del eje, sin importar qué conector hay en
  cada extremo. Un tubo entre una esquina 21 y un borde 35 SÍ necesita
  extenderse en el extremo 21 (Verde, centrada) pero necesita ACORTARSE
  23.15mm en el extremo 35 (`add_branch_sleeve`, boca asimétrica que
  empieza en `OUTSIDE_MM/2 - 1`, NO en `RECEIVER_RADIUS_MM` -son
  conectores de fábrica distintos, con offsets distintos aunque se vean
  parecidos-). Con la arquitectura anterior (una sola definición de tubo
  compartida por eje) esto era imposible de expresar: cada tubo necesita
  su propio largo según la COMBINACIÓN específica de conectores en sus dos
  extremos. Fix: se eliminó el concepto de definición de tubo única por
  eje. `create_grid_tubes` ahora calcula, por cada instancia individual,
  el código de conector en cada extremo vía `horizontal_connector_code`
  (reusa `horizontal_directions`/`connector_code_for_horizontal`, ya
  usados por `create_grid_connectors` — nunca reinventar esa lógica en
  paralelo) y su offset correspondiente vía `x_mouth_offset_mm`/
  `y_mouth_offset_mm`, luego arma el tubo a la medida exacta y cachea la
  definición por largo (`cached_tube_definition`) para no duplicar
  geometría entre tramos que casualmente miden igual. Verificado con un
  script Ruby puro replicando la lógica de asignación de código de
  conector (sin depender de la API de SketchUp) contra una cuadrícula
  2×2: tubo esquina(21)→borde(35) da offsets +24.15/-25.4 (extender) en el
  extremo 21 y +23.15 (acortar) en el extremo 35, exactamente como predice
  la geometría real de `add_branch_sleeve`; nodo interior (1,1) en 2×2
  resuelve correctamente a '40'. Empaquetado en
  constructor_modulos_playidea_v0.7.0.rbz.

  **Lección de arquitectura**: cuando un valor "por eje" (X vs Y) en
  realidad depende de qué hay en cada EXTREMO del tramo, no basta con una
  variable por eje -aunque funcione en el caso más simple (módulo 1x1x1,
  donde todo nodo es esquina)-. Antes de generalizar un fix, preguntarse
  qué otras combinaciones de vecinos existen en la cuadrícula y si el
  caso probado las cubre todas.

  **Ronda 11 — bug real (no de offsets) en la colocación de 35/26: usaban
  `rotation(point,...)` como transform de posicionamiento.**
  Con `modules_y=2` el usuario reportó, con capturas, que los conectores
  35 "aparecen lejos y duplicados" del lugar correcto — el bounding box de
  selección se veía enorme comparado con la estructura visible. Encontrado
  con `inspect_geometry.rb` sobre el módulo completo: `edge_transform_35`
  (y por el mismo patrón, `straight_transform_26`, aunque nunca alcanzable)
  usaban `Geom::Transformation.rotation(point, Z_AXIS, angle)` como ÚNICO
  transform al colocar la instancia. Ese constructor NO coloca el origen
  local del conector en `point` -solo garantiza que `point` se queda fijo
  al girar-. Como el origen local (0,0,0) de la definición de 35/26
  representa el nodo (sin `local_anchor_correction`, a diferencia del 21),
  el resultado real es `point - rotate(angle, point)`, que para nodos
  lejos del origen del modelo cae LEJOS del nodo real -verificado con
  datos reales: un 35 en (0, 1168.4) con angle=-90° apareció en
  (-1168.4, 1168.4, 0), un módulo entero de distancia, prediciendo la
  fórmula con error 0.0mm-. Nunca se había visto porque hasta esta ronda
  nadie había probado `modules_x>1`/`modules_y>1` con conectores
  habilitados -con `modules_x=modules_y=1` cada nodo es esquina (21), que
  usa `Transformation.axes(...)` y sí coloca bien-. Fix: en vez de
  `rotation(point,...)` solo, usar
  `translation(point) * rotation(ORIGIN, Z_AXIS, angle)` -gira primero
  alrededor del origen del mundo (donde SÍ queda fijo en 0,0,0 porque la
  geometría local está definida ahí), luego traslada a `point`-. Mismo
  fix aplicado a `straight_transform_26` por el mismo patrón, aunque
  `connector_code_for_horizontal` nunca puede devolver '26' -confirmado
  en rondas anteriores-, así que no había forma de que este bug
  específico se manifestara ahí; se corrigió solo por consistencia.
  Empaquetado en constructor_modulos_playidea_v0.8.0.rbz.

  **Nota de proceso**: para leer capturas de pantalla directamente sin que
  el usuario las suba al chat, se pueden copiar desde `~/Desktop` con
  Python (`os.listdir` + ordenar por `getmtime`, NUNCA reconstruir el
  nombre de archivo a mano por el espacio angosto U+202F antes de
  "a.m./p.m.") a una carpeta del scratchpad con nombre seguro, y leerlas
  con la herramienta Read normal -Read sí soporta imágenes-. No hace falta
  pedirle al usuario que las pegue si ya se sabe que están en Desktop.

  **Ronda 12 — los tubos de fila/columna deben ser UNA pieza continua, no
  un tramo por nodo; el 35 necesita paso central horizontal.**
  El usuario aclaró (tras la ronda 11): en un nodo intermedio de una
  fila/columna, el conector central debe alinearse con los de la orilla
  -ya resuelto en la ronda 11- Y el tubo lateral debe atravesarlo como UNA
  sola pieza de extremo a extremo, porque el conector de en medio permite
  el paso. Confirmado con pregunta directa: el paso central vertical (Z,
  para el poste) debe COEXISTIR con el nuevo paso horizontal continuo, no
  reemplazarlo -son perpendiculares, no chocan-. Insight clave que
  simplifica todo: por cómo ya funciona `horizontal_directions`, CUALQUIER
  nodo interior en un eje (0<i<nx para X, 0<j<ny para Y) tiene SIEMPRE
  ambas direcciones opuestas de ese eje presentes, sin importar el otro
  eje ni si el conector ahí es 35 o 40 -es decir, la continuidad de un eje
  depende solo de si ese índice es interior en ESE eje, nunca del código
  del conector-. Fix en dos partes:
  (1) `conectores_playidea/main.rb`: `build_35` ya no arma 3 ramales
  separados (+X, -X, +Y) sino un paso central continuo en X
  (`add_centered_sleeve`, igual patrón que ya usa el Z) más un solo ramal
  lateral en Y -el mismo cuerpo base, rotado por `edge_transform_35`,
  cubre las 4 orientaciones posibles-. Empaquetado en
  conectores_playidea_v0.9.0.rbz.
  (2) `constructor_modulos_playidea/main.rb`: `create_grid_tubes`
  reescrito por completo — en vez de un tramo de tubo por cada nodo a
  nodo, ahora es UN tubo por fila X (de i=0 a i=nx) y UN tubo por columna
  Y (de j=0 a j=ny), largo `nx*sx` o `ny*sy` menos los offsets de los DOS
  EXTREMOS reales únicamente (los nodos intermedios ya no influyen en el
  cálculo del tubo en absoluto, solo en la geometría del conector que
  atraviesan). `write_module_attributes` también se corrigió para contar
  tubos por fila/columna en vez de por segmento. Verificado con Ruby puro
  contra la cuadrícula 1×2 ya confirmada en rondas anteriores: los tramos
  extremos (esquina-esquina) dan exactamente los mismos valores que antes
  -matemáticamente equivalente cuando nx=1, ya que "nx tramos" con nx=1 es
  un solo tramo-, y el tramo con el 35 intermedio (X en j=1) da 1122.1mm,
  igual al valor ya confirmado contra los datos reales del usuario.
  Empaquetado en constructor_modulos_playidea_v0.9.0.rbz.

  **Ronda 13 — corrección: no modificar conectores; reusar el 21 tal cual
  en nodos intermedios, no un 35 modificado.**
  El usuario corrigió el enfoque de la ronda 12: "los conectores ni se
  modifican a menos que yo te lo pida... y donde pusiste los 35 mal
  hechos van 21". Se revirtió `build_35` en conectores_playidea a su
  forma original (3 ramales separados, sin paso central en X) y se
  eliminó por completo el código '35' del flujo de creación de la
  cuadrícula: `connector_code_for_horizontal` ahora devuelve '21' tanto
  para esquinas reales (2 direcciones) como para nodos intermedios (3
  direcciones) -'35' queda tan inalcanzable como '26' ya lo estaba desde
  antes-. Nueva función `middle_transform`: para un nodo de 3
  direcciones, encuentra cuál es la "sencilla" (sin pareja opuesta en la
  lista) y cuál es la "continua" (parte de la pareja completa), y arma el
  mismo cuerpo del 21 con Azul→sencilla y Verde→continua -sin importar si
  esa dirección continua es X o Y en el mundo, a diferencia de
  `corner_transform` que ata Azul a X y Verde a Y fijo por construcción-.
  Verificado con Ruby puro contra 4 combinaciones de signos/ejes: el
  hallazgo de roles (sencilla/continua) es correcto en los 4 casos.
  Al revisar esto se encontró un bug real en `y_mouth_offset_mm` que la
  ronda 12 no había cubierto: la fórmula asumía "extender con Verde" para
  CUALQUIER nodo con código '21' en niveles k>=1, pero eso solo es cierto
  en esquinas REALES (2 direcciones) -en un nodo intermedio (3
  direcciones) Verde está ocupada sirviendo el paso continuo del otro eje,
  así que en SU propio eje (siempre el sencillo ahí, por definición del
  extremo de fila/columna que se consulta) es Azul quien sirve, en TODOS
  los niveles, sin excepción-. Esto solo se manifiesta con `modules_x>=2`
  en una columna Y interior -el caso de prueba anterior (nx=1) nunca lo
  ejercitaba porque con nx=1 ninguna columna Y puede ser interior-. Fix:
  `y_mouth_offset_mm` ahora recibe `(i, j, nx, ny, k)` en vez de un código
  ya resuelto, y decide extender SOLO si `horizontal_directions(i,j,nx,ny).length == 2`
  (esquina real) Y `k>=1`; en cualquier otro caso usa el offset asimétrico
  de Azul. `x_mouth_offset_mm` se simplificó a una constante -X en su
  propio extremo de fila SIEMPRE es el eje sencillo ahí, nunca depende del
  tipo de nodo ni del nivel-. `BRANCH_INSET_MM` quedó sin ningún uso -era
  exclusivo del código '35', ahora inalcanzable- y se eliminó. Verificado
  con Ruby puro: el caso ya confirmado (nx=1,ny=2) reproduce EXACTAMENTE
  los mismos valores que antes (regresión limpia); un caso nuevo
  (nx=2,ny=1, columna Y interior) confirma que antes del fix habría dado
  el valor de Verde (incorrecto) en la columna interior a nivel superior,
  y con el fix da el valor de Azul (correcto). Empaquetado en
  conectores_playidea_v0.10.0.rbz (revertido) y
  constructor_modulos_playidea_v0.10.0.rbz.

  **Lección de proceso, otra vez**: no asumir que "modificar geometría de
  conectores" es aceptable solo porque resuelve el problema numéricamente
  -el usuario tiene una regla explícita de no tocar conectores sin permiso
  incluso cuando parece la solución más directa-. Cuando la geometría
  existente (21, con Verde ya centrada) YA sirve para el nuevo caso de uso
  con la orientación correcta, preferir reusarla con una nueva
  transformación antes que crear/modificar una definición de conector.

  **Ronda 14 — `inspect_geometry.rb` ahora escribe a archivo, no a
  consola.**
  A petición del usuario: el script ya no imprime el resultado en la
  consola de Ruby de SketchUp -se volvía enorme para copiar a mano-. Ahora
  redirige `$stdout` a un `StringIO` durante toda la ejecución (con
  `begin/ensure` para garantizar que se restaura aunque algo truene a
  medio camino) y al final escribe ese buffer a un archivo nuevo en
  `OUTPUT_DIR = '/Users/minorusal/Documents/SKETCHUP/inspect_output'`
  -la carpeta que contiene los 4 plugins-, con nombre
  `inspect_YYYYMMDD_HHMMSS.txt` (marca de tiempo, nunca sobreescribe una
  corrida anterior). La consola solo muestra la ruta del archivo creado.
  Como esto corre en la misma máquina donde vive esta sesión de Claude
  Code, el archivo se puede leer directo con Bash/Read -mismo truco que
  copiar capturas de pantalla desde `~/Desktop`- sin que el usuario tenga
  que pegar nada manualmente; solo hace falta que diga "ya corrí el
  script" o similar y buscar el .txt más reciente en `inspect_output/`
  por fecha de modificación.
  También se agregó, en el mismo script, una tabla de "Distancias en
  MUNDO" entre TODOS los pares de la selección (no solo hermanos
  directos como la tabla LOCAL existente) — necesaria para el próximo
  caso de prueba (`modules_z>1`), donde hay que comparar piezas en ramas
  distintas del árbol (ej. "Principal" anidado dentro de un conector vs.
  el poste Z que cuelga aparte).

  **Confirmado por el usuario**: módulo 1×2×1 (`modules_y=2`) queda
  correcto tras la ronda 13, en ambos plugins, sin más cambios por ahora.
  El usuario avisó que probará `modules_z>1` (más de un nivel) a
  continuación y mandará una referencia corregida a mano si algo falla
  ahí -mismo proceso: pedir `inspect_geometry.rb` + descripción simple
  antes de tocar código-. Sospecha propia para cuando llegue esa prueba:
  en un nivel Z verdaderamente intermedio (ni k=0 ni k=nz), el poste Z
  continúa hacia AMBOS lados del conector -no solo hacia abajo, como en
  una esquina o en `middle_transform` actual-, y "Principal" (la pieza
  que sirve el rol Z tanto en esquinas como en `middle_transform`) es
  asimétrica, apunta a un solo lado. Igual que con Azul/Verde en la ronda
  13, probablemente la solución sea una transformación nueva que reuse
  geometría existente -no modificar ningún conector- una vez que haya
  datos reales para verificarlo.

  **Ronda 15 — módulo 1x2x2 (primer nivel Z intermedio real): el poste Z
  también se parte, y el conector intermedio reorienta su cuerpo para
  recibirlo.**
  Con `modules_z=2` aparece por primera vez un nivel k verdaderamente
  intermedio (0<k<nz). El usuario mandó varias iteraciones de referencia
  corregida a mano (usar SIEMPRE la más reciente por fecha de archivo en
  `inspect_output/` -el usuario puede revisar varias veces antes de decir
  "así debe quedar"-) hasta un diseño final verificado así:
  - El poste Z, que hasta ahora era SIEMPRE una sola pieza continua por
    columna, se PARTE en un tramo por nivel (confirmado con datos reales:
    2 piezas de ~1288mm cada una con `modules_z=2`, con un hueco donde se
    aloja el conector intermedio -antes ni se sospechaba esto, todos los
    módulos probados hasta ahora tenían `modules_z=1`, sin nivel
    intermedio real que lo revelara-).
  - En el nivel 0 y en niveles intermedios reales (k<nz, "algo continúa
    arriba, sea el poste completo en k==0 o partido en dos en un nivel
    intermedio"), TODO nodo con 3 direcciones horizontales -y en niveles
    intermedios reales, TAMBIÉN los de 2 (esquinas reales)- usa un cuerpo
    basado en el 35 (3 ramales + 1 pieza central) EN VEZ del 21, porque
    necesita cubrir el eje Z de forma simétrica -el poste sigue o se
    parte ahí, nunca termina-.
  - Ese cuerpo del 35 usa los mismos 3 ramales de fábrica (nunca
    modificados) PERO con la pieza central sustituida por una centrada de
    50.8mm -mismo largo que "Verde" del 21, NO 63.5mm- en vez del
    manguito asimétrico original. Verificado con el largo real del tubo Y
    continuo en nivel intermedio: 2387.6mm con nx=1,ny=2 → alargue de
    25.4mm por extremo, exactamente la mitad de 50.8, no de 63.5.
    Implementado como `build_connector_35_verde` en
    constructor_modulos_playidea -mismo patrón que `build_connector_26`,
    sin tocar conectores_playidea en absoluto-.
  - En un NIVEL INTERMEDIO REAL específicamente (ni el 0 ni el más alto),
    el poste se parte ahí mismo, así que el cuerpo se reorienta distinto
    a como se usa en el nivel 0: el PAR OPUESTO de ramales -normalmente
    horizontal, X en la plantilla base- pasa a servir Z (recibiendo cada
    mitad del poste por separado), y las dos direcciones horizontales
    reales del nodo -sean las 2 de una esquina real o la sencilla+la
    continua de un nodo intermedio de fila/columna- las cubren el ramal
    sencillo y la pieza centrada, sin importar cuál sea cuál. Nueva
    función `swapped_z_body_transform`, verificada con datos reales:
    para una esquina con horizontal=[X_AXIS.reverse, Y_AXIS] predice
    xaxis=[0,0,1], yaxis=[-1,0,0], zaxis=[0,1,0] -coincide exactamente
    con lo medido, sin margen de error-. En el nivel 0 en cambio (el
    poste NO se parte ahí, solo pasa continuo) se sigue usando
    `edge_transform_35` sin cambios -mismo cuerpo, distinta orientación-.
  - Consecuencia para los TUBOS horizontales (`create_grid_tubes`,
    reescrito): el eje X SIEMPRE va segmentado (un tramo por módulo, en
    TODOS los niveles) porque Azul -asimétrico- nunca cambia de rol, en
    ningún nivel. El eje Y va segmentado SOLO en el nivel 0; en cualquier
    nivel k>=1 -sea el intermedio real o el de arriba- cada columna Y es
    un tubo continuo de punta a punta, porque en niveles k>=1 Y siempre
    topa contra una pieza centrada en sus extremos reales -Verde en una
    esquina real de arriba, o la pieza centrada del cuerpo reorientado en
    un nivel intermedio real-. Esto **revirtió** una condición que se
    había "corregido" mal a medio camino de esta misma ronda (`k==nz` en
    vez de `!k.zero?` para decidir si Y alarga): la condición ORIGINAL
    de rondas anteriores (`!k.zero?`) resultó ser la correcta después de
    todo; el error fue asumir, con datos de un archivo intermedio que el
    usuario todavía estaba corrigiendo, que el nivel intermedio real
    debía ir segmentado como el nivel 0. Lección: cuando el usuario dice
    "ahí está" y sigue mandando archivos más nuevos sin decir
    explícitamente "esta es la versión final", NO asumir que el primer
    archivo recibido ya es la referencia definitiva -preguntar o esperar
    confirmación explícita antes de derivar una fórmula de un archivo que
    podría ser un intento intermedio-.
  - `write_module_attributes` actualizado para la nueva cuenta de tramos
    (X siempre segmentado; Y segmentado solo en k=0; Z ahora con `nz`
    tramos por columna en vez de uno continuo).
  Verificado end-to-end con Ruby puro (sin la API de SketchUp): el conteo
  de conectores resultante (10×21, 8×35) coincide EXACTO con la
  referencia final del usuario; los largos de tubo Y (1120.1mm segmentado
  en k=0, 2387.6mm continuo en k>=1) coinciden EXACTOS. El tamaño preciso
  del hueco del poste Z en el nivel intermedio no se pudo verificar con
  la misma exactitud -depende de `spacing_z_mm`, un parámetro que el
  usuario ingresó y no quedó registrado en los datos, y la referencia a
  mano tiene ruido de posición notable ahí (varios mm a varias decenas de
  mm)-, así que se implementó con el mismo radio (24.15mm) usado en todos
  los demás huecos del proyecto, pendiente de confirmar visualmente.
  Empaquetado en constructor_modulos_playidea_v0.11.0.rbz -conectores_playidea
  NO se tocó en esta ronda, se mantiene en v0.10.0-.

  **Ronda 16 — módulo 2x2x1 (primer nodo interior verdadero, código '40'):
  en el nivel superior reusa el mismo cuerpo del 35, con una TERCERA
  asignación de roles.**
  Con `modules_x=2, modules_y=2` aparece por primera vez un nodo
  genuinamente interior en AMBOS ejes (4 direcciones horizontales, código
  '40', en (i=1,j=1)). El usuario mandó malo+bueno; la diferencia exacta:
  el nodo interior en el nivel 0 se queda como estaba (código '40', sin
  tocar -sigue pendiente, sin datos que lo cubran-), pero el del nivel MÁS
  ALTO (k==nz) cambió de '40' a '35' -mismo cuerpo `build_connector_35_verde`
  ya usado en rondas anteriores, sin modificarlo de nuevo-, con una
  asignación de roles que el 21 no podría dar -el 21 solo tiene 2 salidas
  horizontales, hacen falta 4-: el PAR OPUESTO del cuerpo (2 ramales
  separados) sirve el eje X -siempre segmentado en cualquier nivel, ver
  `x_mouth_offset_mm`, necesita dos bocas separadas para los dos tramos
  que llegan-; la pieza CENTRADA sirve Y -continuo en cualquier nivel
  k>=1, ver `y_mouth_offset_mm`, necesita una sola boca atravesada de lado
  a lado-; el ramal SENCILLO sirve Z hacia abajo -asimétrico, igual que
  Principal en una esquina real de ese mismo nivel, porque nada continúa
  arriba-. Nueva función `interior_top_transform`, verificada exacta
  contra los datos reales (posición dentro de 1mm, orientación exacta).
  Confirma el patrón general que ya se venía repitiendo: el mismo cuerpo
  de 3 ramales + 1 centrada puede representar CUALQUIER combinación de
  roles -según qué necesite cada eje en cada nodo/nivel- con una
  transformación distinta cada vez, sin nunca tocar la geometría de
  conectores_playidea. Verificado end-to-end (conteo de conectores 12×21,
  5×35, 1×40, exacto contra la referencia). Empaquetado en
  constructor_modulos_playidea_v0.12.0.rbz.

  **Ronda 17 — módulo 2x2x2 (nodo interior en un nivel intermedio real):
  el 40 ORIGINAL, sin tocar, ya alcanza — solo hacía falta otra rotación.**
  Con `modules_x=2, modules_y=2, modules_z=2` aparece el nodo interior
  verdadero combinado con un nivel intermedio real. Diferencia entre malo
  y bueno: los CONTEOS de conector no cambiaron nada (12×21, 13×35, 2×40,
  idénticos) — la única diferencia fue la ORIENTACIÓN del CON-40 del
  nivel intermedio (el de nivel 0 sigue sin tocarse, todavía pendiente).
  A diferencia de las rondas 15/16, aquí NO hizo falta ninguna pieza
  nueva ni build_connector_35_verde: el `build_40` ORIGINAL de
  conectores_playidea (nunca modificado) ya tiene, de fábrica, exactamente
  lo necesario -su manguito central YA es continuo/simétrico (mismo
  patrón que add_centered_sleeve) y sus 4 ramales YA son dos pares
  independientes (±X, ±Y)-, solo faltaba permutar qué eje del mundo sirve
  cada pieza: el manguito central -continuo- pasa a servir Y (continuo en
  cualquier nivel k>=1); el par ±Y -ya son dos ramales SEPARADOS de
  fábrica- se reorienta a Z, recibiendo cada mitad del poste partido; el
  par ±X se queda sirviendo X sin cambios. A diferencia de
  swapped_z_body_transform/interior_top_transform, aquí NO hay ambigüedad
  que resolver por búsqueda de "cuál dirección es cuál": en un nodo de 4
  direcciones X e Y siempre están completos los dos, así que el mapeo es
  FIJO -misma fórmula sin importar la posición del nodo-. Nueva función
  `interior_middle_transform`, un simple `axes(point, X_AXIS, Z_AXIS,
  Y_AXIS.reverse)`, sin necesidad de anclas ni búsquedas de dirección.
  Empaquetado en constructor_modulos_playidea_v0.13.0.rbz.

  **Patrón que se repite y ya se puede dar por establecido**: cada vez que
  aparece una combinación nueva de (tipo de nodo × nivel), la respuesta
  casi nunca es geometría nueva -ya van dos rondas seguidas (16, 17) donde
  el cuerpo existente, sin tocar, ya alcanzaba con solo una rotación
  distinta-. Antes de proponer una pieza nueva, primero preguntar: ¿algún
  cuerpo YA EXISTENTE (21, 35-verde, 40 original) tiene, de fábrica, el
  número y tipo de piezas correcto -continuas vs. pares separados vs.
  sencillas- para los roles que hacen falta en este nodo? Si sí, es pura
  cuestión de transformación, no de geometría.

  **Ronda 18 — nueva funcionalidad: recubrimiento de espuma (polyfoam)
  como opción del constructor, con costeo real del proceso.**
  Primera funcionalidad NUEVA de la sesión (no un fix de geometría de
  módulos/conectores). El usuario quiere que el constructor pueda forrar
  TODA la estructura -tubos y conectores por igual, incluso el bulto del
  conector- con tubo de espuma de 8.5cm de diámetro exterior. Decisiones
  confirmadas por el usuario (vía AskUserQuestion):
    - Diámetro interior del hueco = el mismo que el diámetro del
      CONECTOR (`PlayIdea::Conectores::OUTSIDE_MM` = 48.3mm, no el del
      tubo estructural de 38.1mm) -porque también debe cubrir el
      conector, no solo el tubo-.
    - Cobertura de PUNTA A PUNTA de cada fila/columna/poste, sin
      insertarse ni detenerse en los nodos como los tubos estructurales
      -el recubrimiento no necesita encajar en ningún receptor, así que
      su lógica de posicionamiento es mucho más simple que la de los
      tubos: solo depende del ancho total de la cuadrícula en cada eje,
      nada de offsets por tipo de conector ni por nivel-.
    - Vive como checkbox dentro del constructor de módulos -mismo patrón
      que "Agregar conectores automáticamente"-, no como herramienta
      aparte sobre selección.
    - El costeo sigue el mismo patrón ya establecido en
      conectores_playidea (`capture_costs`): diálogo con `UI.inputbox`,
      valores por defecto editables guardados con
      `Sketchup.write_default` bajo una preference key propia
      (`PlayIdeaRecubrimientoCostos`).
  Proceso real del material (según el usuario, para el desglose de
  costo): tubo crudo de 2m Ø8.5cm se perfora con máquina -mano de obra +
  electricidad-; para llegar a la medida comercial de 2.4m se pega un
  tramo de 40cm cortado de OTRO tubo crudo -mano de obra de empalme-;
  luego se forra con pegamento (solvente + adhesivo, aplicado con
  brocha) y un plástico que da color/textura -material + mano de obra de
  aplicarlo-; ya seco, se suelda la costura con una resistencia -mano de
  obra-. Modelado como costo por "tubo terminado de 2.4m": material =
  1.2× el precio de un tubo crudo (1 completo + fracción 0.4/2.0 de
  otro, sin optimizar el sobrante de 1.6m del tubo donante, mismo nivel
  de aproximación que el resto de los costeos del proyecto) + cada
  renglón de mano de obra/insumos. Número de tubos terminados
  necesarios = techo(largo total de recubrimiento / 2400mm).
  Implementación: nuevas constantes (`PADDING_OUTSIDE_MM`,
  `PADDING_INSIDE_MM`, `PADDING_STOCK_LENGTH_MM`,
  `PADDING_FINISHED_LENGTH_MM`, `PADDING_SPLICE_LENGTH_MM`,
  `PADDING_RAW_MATERIAL_FACTOR`, `PADDING_DEFAULT_COSTS`);
  `create_grid_padding` (geometría, reusa
  `PlayIdea::CreadorTubos.add_hollow_geometry` -mismo helper que ya usan
  los tubos estructurales y el creador de tubos aparte, sin duplicar
  código de geometría de tubo hueco-); `capture_padding_costs` (diálogo
  de costos); `padding_attributes` (cálculo y guardado de costo total).
  Checkbox nuevo en `selector.html`. Verificado con Ruby puro (largo
  total, número de tubos, costo por tubo, costo total) para un módulo
  1x1x1 simple: números razonables (14.7m de recubrimiento, 7 tubos
  terminados, ~$408 MXN c/u). Empaquetado en
  constructor_modulos_playidea_v0.14.0.rbz. Pendiente de que el usuario
  lo pruebe visualmente en SketchUp -esta ronda se verificó la
  aritmética, no la geometría en 3D todavía-.

  **Pendiente, no tocado todavía**: el nodo interior verdadero en el
  NIVEL 0 (`modules_x>=2` Y `modules_y>=2` A LA VEZ) sigue sin tocarse,
  código '40' con transform de traslación simple (sin rotar), pendiente
  de que el usuario lo pruebe y corrija a mano. Dado el patrón de la
  ronda 17, es muy probable que la solución sea, otra vez, una rotación
  del 40 original -su manguito central podría servir Z (tocando el 61,
  como Verde en una esquina real) y alguno de sus pares horizontales
  quedarse igual- pero NO ADIVINAR: pedir referencia corregida a mano +
  `inspect_geometry.rb` cuando el usuario lo pruebe, igual que en todas
  las rondas anteriores.

  **Ronda 19 — nueva funcionalidad: torre de pisos triangulares (tubos
  diagonales a 45° como "escalones" para subir de nivel).**
  El usuario armó a mano 2-3 ejemplos de referencia (uno embebido en un
  módulo 2x4x2) de una torre con tubos atravesados en diagonal dentro de
  una celda, formando escalones espaciados verticalmente, para subir
  entre niveles sin escalera convencional. Análisis de los `.txt` de
  `inspect_geometry.rb` de esos ejemplos:
    - Cada escalón = 1 tubo diagonal a 45° en el plano horizontal +
      2 conectores CON-12 (`conectores_playidea`'s "T inclinada a 45°",
      `build_12`: manguito centrado 63.5mm en su eje local X + ramal
      MITRADO de 76.2mm hacia `Vector3d.new(-1,0,-1).normalize` local,
      vía `add_mitered_branch_12`) -uno en cada extremo de la diagonal-.
    - Separación vertical entre escalones = 600mm
      (`TRIANGLE_STEP_SPACING_MM`), **exacta**, confirmada en 3 ejemplos
      independientes de distinto tamaño/orientación de módulo.
    - El acortamiento del tubo diagonal en cada extremo (para dejar
      espacio al conector) ≈70mm (`TRIANGLE_DIAGONAL_INSET_MM`) -esto
      solo se derivó de UN ejemplo, queda marcado en el código como
      aproximado, no tan sólido como el resto de las constantes-.
    - Fórmula de rotación del CON-12 para que su ramal a 45° apunte
      exacto hacia cualquiera de las 4 diagonales horizontales posibles:
      dado un vector unitario de diagonal `D` en el plano mundo X-Y, hay
      que resolver qué eje local (X o Z, del conector) recibe cuál eje
      del mundo tal que `local_X_mundo + local_Z_mundo = -√2 * D` -porque
      el ramal angulado de `build_12` vive en el plano local X-Z, en
      dirección `-(local_x+local_z)` normalizada-. Implementado en
      `diagonal_connector_transform`: `local_x = X_AXIS` si
      `-D.x*√2 > 0` si no `X_AXIS.reverse`; `local_z = Y_AXIS` si
      `-D.y*√2 > 0` si no `Y_AXIS.reverse`; `local_y =
      local_z.cross(local_x)`. Verificado con CERO margen de error
      numérico contra 3 puntos de datos reales (2 ejemplos distintos), y
      además con un dry-run puro en Ruby (sin SketchUp) que confirma que
      la rama resultante coincide EXACTO con las 4 diagonales posibles y
      que la base local queda ortonormal en los 4 casos.
    - Hallazgo importante, ya avisado y confirmado por el usuario: la
      asignación de CUÁL eje del mundo (X o Y) recibe `local_x` vs.
      `local_z` en los ejemplos reales NO sigue una regla fija -depende,
      caso por caso, de qué conector de la cuadrícula base ya existía en
      ese nodo, y el usuario tuvo que ajustar el entorno a mano para que
      los tubos diagonales embonaran-. Cita textual: *"depende, puede
      que si embone al conector que ya existía queda bien pues ya se
      deja así pero si no pues yo tuve que cambiar varias cosas del
      entorno para que encajaran los tubos diagonales."* Se optó, de
      acuerdo con el usuario, por una convención FIJA y autoconsistente
      (documentada en un comentario largo junto a
      `diagonal_connector_transform`) que da SIEMPRE la dirección
      correcta del ramal, aunque no necesariamente coincida con el
      ajuste manual del usuario en sus ejemplos -esto es intencional y
      suficiente para el generador de torres AUTÓNOMAS (celda vacía, sin
      cuadrícula base preexistente)-.

  **Alcance explícitamente NO cubierto en esta ronda** (confirmado con
  el usuario, no automatizar todavía): el ajuste de los conectores de la
  cuadrícula base (CON-35/CON-40 preexistentes) donde cae la diagonal,
  cuando la torre se integra a una cuadrícula ya armada -eso sigue
  siendo trabajo manual, caso por caso, hasta que haya más ejemplos
  anotados por el usuario que permitan ver el patrón-. Tampoco se
  implementó el rol de CON-10 en la torre (aparece en los ejemplos pero
  no se determinó su función esta ronda).

  Implementación: constantes `TRIANGLE_STEP_SPACING_MM=600.0` y
  `TRIANGLE_DIAGONAL_INSET_MM=70.0`; `TriangleTowerPlacementTool` (calca
  `ModulePlacementTool`, un clic = esquina donde arranca la diagonal);
  `start_triangle_tower` / `validate_triangle_dialog_data` /
  `diagonal_connector_transform` / `create_triangle_tower`; diálogo
  nuevo `torre_triangular.html` (mismo patrón que `selector.html`:
  medida de celda, dirección de la diagonal `sw_ne`/`se_nw`, cantidad de
  escalones 1-50 -NO fija, el usuario aclaró que depende de la altura
  requerida-, separación entre escalones, altura del primer escalón,
  color, código). Nuevo ítem de menú "Agregar torre de pisos
  triangulares", independiente de "Crear estructura modular", para
  poder colocar la torre en cualquier ubicación sobre una cuadrícula ya
  existente o sobre un punto vacío. No se tocó `conectores_playidea` en
  absoluto -se reutiliza `build_12` tal cual, vía
  `PlayIdea::Conectores.build_connector_geometry(entities, '12', ...)`-.
  Verificado con dry-run puro en Ruby (rotación del CON-12 exacta en 4
  casos; geometría del tubo simétrica, deja el inset completo en ambos
  extremos) antes de empaquetar. Empaquetado en
  `constructor_modulos_playidea_v0.15.0.rbz`. Pendiente de que el
  usuario lo pruebe visualmente en SketchUp -esta ronda, igual que la
  18, solo se verificó la aritmética/geometría analítica, no el
  resultado 3D real-.

  **Bug real encontrado al primer uso en SketchUp (corregido en
  v0.15.1)**: el usuario probó la torre con la celda por defecto
  (1.1684m) y pidió revisar el `.txt` de `inspect_geometry.rb` más
  nuevo. Los dos CON-12 del primer escalón quedaron a 29677.36mm de
  distancia en mundo -una celda de ~29.68m, absurda para un módulo de
  playground-. Causa: `create_triangle_tower` construía
  `Geom::Vector3d.new(params[:cell_x_mm], params[:cell_y_mm], 0)`
  pasando NÚMEROS PLANOS EN MILÍMETROS directo a la API de SketchUp, que
  interpreta números sueltos como PULGADAS -nunca se les aplicó `.mm`-.
  1168.4 "pulgadas" mal interpretadas × 25.4 = 29677.36mm, coincide
  exacto con lo visto en el `.txt`. La dirección del tubo (`direction`,
  vía `.normalize`) salió bien porque normalizar borra la escala -por
  eso la rotación de los CON-12 y la orientación general no se veían
  raras a simple vista, solo la distancia/tamaño real-. Fix: separar el
  cálculo en números planos mm (`full_length_mm` vía Pitágoras, para
  `diagonal_length_mm`) de los puntos reales que sí necesitan `.mm`
  (`corner_b` vía `offset_point` con `sign_x * params[:cell_x_mm].mm`).
  Verificado con dry-run: 1168.4mm × 1168.4mm ahora da una diagonal de
  1652.37mm, no 41970mm. **Lección de proceso**: cuando se maneja una
  magnitud real (largo, distancia) en vez de solo una dirección
  normalizada, hay que rastrear ejes por ejes qué es un número plano-mm
  y qué es un `Length` de SketchUp -mezclar los dos sin `.mm` no truena
  en `ruby -c` ni en un dry-run que no involucre la API real de
  SketchUp, así que ese tipo de bug NO se detecta sin probar en
  SketchUp o sin que el dry-run imite explícitamente la semántica de
  unidades de la API-. Empaquetado en
  `constructor_modulos_playidea_v0.15.1.rbz` (v0.15.0, con el bug, se
  eliminó).

  **Ronda 20 — flujo de UI encadenado entre estructura y torre.** El
  usuario preguntó cómo debería quedar la interfaz para poder crear
  estructuras "con torre integrada y sin torre". Se le presentaron 3
  opciones vía AskUserQuestion (menús separados como hasta ahora,
  checkbox integrado en el mismo diálogo de crear estructura, o un flujo
  encadenado con confirmación al terminar) con mockups ASCII de cada
  una; eligió el **flujo encadenado**. Implementación:
    - `ModulePlacementTool#onLButtonDown`: tras `create_module`, muestra
      `UI.messagebox('...¿Agregar una torre...?', MB_YESNO)`; si
      `IDYES`, llama a `start_triangle_tower(color:, cell_x_m:,
      cell_y_m:)` precargando el color y la medida de celda (spacing_x/y
      en metros) de la estructura recién creada -así el usuario no tiene
      que volver a escribirlos, aunque puede cambiarlos en el diálogo-.
    - `TriangleTowerPlacementTool#onLButtonDown`: tras crear una torre,
      pregunta '¿Agregar otra torre...?'; si sí, reabre
      `start_triangle_tower` con el MISMO prefill (color/celda) que
      acaba de usar, permitiendo encadenar varias torres sin repetir
      datos; si no, termina la herramienta.
    - `start_triangle_tower` ahora acepta un `prefill = {}` opcional
      (color, cell_x_m, cell_y_m) que se pasa a `loadDefaults` en el
      diálogo; el ítem de menú standalone lo sigue llamando sin
      argumentos (usa los defaults normales, DEFAULT_SPACING_M y sin
      color forzado).
    - `torre_triangular.html`: `loadDefaults` ahora acepta X/Y por
      separado (`default_spacing_m` / `default_spacing_y_m`, antes solo
      había un valor para ambos) y un `color` opcional para preseleccionar
      el `<select>`.
  Sin estructura previa, el usuario sigue pudiendo usar "Agregar torre
  de pisos triangulares" del menú de forma independiente -el flujo
  encadenado es un atajo opcional (contestar "No" dos veces = comportamiento
  idéntico al de antes), no reemplaza los dos puntos de entrada
  existentes-. `MB_YESNO`/`IDYES` son constantes top-level de la API de
  SketchUp -mismo patrón ya usado en el código para `SB_PROMPT`, se
  resuelven igual por herencia de Object sin necesidad de calificarlas-.
  Solo verificado con `ruby -c`, sin dry-run adicional -no hay geometría
  nueva, solo flujo de diálogos-. Empaquetado en
  `constructor_modulos_playidea_v0.16.0.rbz`. Pendiente de que el
  usuario lo pruebe en SketchUp.

  **Ronda 21 — dos bugs reales de geometría encontrados por el usuario
  probando v0.15.1/v0.16.0, corregidos con análisis exhaustivo contra
  LOS EJEMPLOS ORIGINALES del usuario (no solo contra lo que generaba mi
  propio plugin).** El usuario reportó: "salen los tubos fuera de los
  conectores 12 y no bien embonados además que salen apuntando hacia el
  mismo lado y así no es una escalera de triángulos la cual sea de un
  lado y después el otro de otro lado". Investigación con
  `inspect_geometry.rb` sobre DOS fuentes:
    1. El `.txt` más nuevo generado por mi propio plugin
       (`inspect_20260728_164955.txt`, torre de 3 escalones) -para ver
       el síntoma-.
    2. Los DOS `.txt` de ejemplos reales hand-built del usuario que
       seguían disponibles de rondas anteriores
       (`inspect_20260728_122206.txt`, MOD-2X2X2, y
       `inspect_20260728_160720.txt`, MOD-4X2X2 -la versión "corregida",
       más nueva que `151303.txt`-) -para sacar la fórmula correcta,
       siguiendo la disciplina del proyecto de nunca adivinar-.
  Con un script Python (regex sobre los `.txt`, ya que son de cientos de
  miles de líneas) se ubicaron los 3 tubos diagonales reales de cada
  ejemplo (por su `zaxis` a 45° en el plano XY) y los CON-12 más
  cercanos a cada uno, comparando sus matrices `xaxis/yaxis/zaxis`
  reales.

  **Hallazgo 1 -zigzag real, confirmado-**: en AMBOS ejemplos, los
  escalones 1 y 3 (primero y tercero) usan CON-12 con la MISMA
  orientación exacta, y el escalón 2 (de en medio) usa una orientación
  distinta -equivalente a la diagonal opuesta de la misma celda-. Esto
  es justo el patrón de una escalera real en zigzag que el usuario
  describió. Mi implementación anterior usaba la MISMA diagonal para
  todos los escalones -bug confirmado-.

  **Hallazgo 2 -punto de embone real, confirmado-**: comparando el
  origen real del tubo diagonal contra dos hipótesis (a: la punta del
  ramal mitrado de 76.2mm de `build_12`; b: el mismo `RECEIVER_RADIUS_MM`
  de 24.15mm que usan TODOS los demás tubos del proyecto, medido a lo
  largo del eje Z LOCAL del propio CON-12, no de la diagonal), la
  hipótesis (b) ganó por mucho margen: error de ~2.1mm (0.14% de una
  diagonal de ~1470-1650mm) en los 4 escalones "limpios" -los que no
  comparten nodo con un conector de cuadrícula preexistente- de los 2
  ejemplos, contra decenas de mm de error de la hipótesis (a) y de mi
  constante empírica anterior (`TRIANGLE_DIAGONAL_INSET_MM=70`, error
  real de ~77mm). El escalón intermedio de AMBOS ejemplos -el único que
  SÍ cae en un nodo de la cuadrícula base- se desvía ~12-37mm de la
  fórmula limpia, consistente con lo que el usuario ya había dicho
  ("tuve que cambiar varias cosas del entorno para que encajaran los
  tubos diagonales") -confirma, de nuevo con datos, que el ajuste de
  conectores de cuadrícula base sigue fuera de alcance, ver la nota ya
  existente-.

  **Fix implementado**: `create_triangle_tower` ahora alterna
  `params[:diagonal]` en cada escalón (par usa la elegida, impar la
  opuesta, vía nuevo helper `opposite_diagonal`); nueva función
  `triangle_cell_corners` calcula las 4 esquinas SO/SE/NE/NO de la celda
  desde `origin` -siempre la esquina SO-; nueva función
  `diagonal_connector_mouth(transform)` calcula el punto de embone real
  (`Point3d.new(0,0,-RECEIVER_RADIUS_MM.mm).transform(transform)`) para
  cada CON-12, y el tubo se construye EXACTO entre los dos puntos de
  embone -largo y dirección reales, ya no una diagonal pura con un
  acortamiento aproximado-, garantizando cero espacio/traslape en
  ambos extremos. Se eliminó `TRIANGLE_DIAGONAL_INSET_MM` por completo
  -ya no hace falta, la fórmula es exacta, no empírica-. Verificado con
  dry-run en Ruby puro reproduciendo los números reales de ambos
  ejemplos (error ~2.1mm, igual al medido a mano) y un caso sintético
  de 4 escalones confirmando la alternancia y el largo consistente del
  tubo.

  **Lección de proceso, importante**: la ronda anterior (20) había
  fijado `TRIANGLE_DIAGONAL_INSET_MM=70` a partir de UN solo ejemplo,
  con la aproximación ya marcada como tal en el código -pero aun así
  resultó tener 77mm de error real-. Cuando hay MÁS de un ejemplo
  disponible (como en este caso, 2 estructuras con 3 escalones cada
  una), hay que cruzarlos TODOS antes de fijar una fórmula, no
  conformarse con que "ajusta razonablemente bien" en un solo caso. Los
  `.txt` de ejemplos reales del usuario, aunque sean de rondas
  anteriores, siguen siendo la fuente de verdad más confiable
  disponible -mejor que inventar geometría nueva o que verificar solo
  contra la propia salida del plugin-.

  **Ronda 21, segunda parte — integración de la torre al flujo de crear
  estructura (UI).** El usuario, después de ver el resultado del
  "flujo encadenado" de la ronda 20 (mensaje de confirmación después de
  crear la estructura), dijo explícitamente que no le gustaba que la
  torre se creara aparte y pidió poder crear estructura + torre juntas.
  Se reemplazó el encadenado por integración real en el MISMO diálogo:
    - `selector.html` ahora tiene un checkbox "Agregar torre de pisos
      triangulares" que despliega un sub-panel con los campos de la
      torre (celda, escalones, diagonal inicial, altura del primer
      escalón, separación) dentro del MISMO formulario que crea la
      estructura -ya no hay un segundo diálogo/ventana-.
    - `validate_dialog_data` + nuevo helper `tower_params_from_dialog`
      parsean y validan los campos `tower_*` del mismo payload,
      reusando el color y agregando `-TORRE` al código de la
      estructura.
    - `ModulePlacementTool` ahora es una herramienta de 2 etapas: si
      `params[:tower]` viene lleno, después de crear la estructura con
      el primer clic, cambia el texto de estado y espera un SEGUNDO
      clic (esquina SO de la celda de la torre) en la MISMA operación
      de colocación, sin mensajes ni ventanas de por medio.
    - El menú independiente "Agregar torre de pisos triangulares"
      -y su diálogo `torre_triangular.html`- se mantienen intactos,
      para seguir pudiendo agregar una torre a una estructura YA
      existente en cualquier momento; no son mutuamente excluyentes.
  Limpieza pedida explícitamente por el usuario: solo se conservan los
  últimos 2 `.rbz` de cada plugin en la carpeta raíz -se borraron los
  `.rbz` viejos de `constructor_modulos_playidea` (v0.5.0 a v0.15.1) y
  de `conectores_playidea` (v0.8.0)-. Empaquetado en
  `constructor_modulos_playidea_v0.17.0.rbz`. Pendiente de que el
  usuario lo pruebe visualmente en SketchUp.

  **Ronda 22 — elegir la columna de la torre haciendo clic en la vista
  previa, y separación de escalones auto-calculada entre 50-60cm.** El
  usuario pidió poder decidir en qué parte de la estructura va la torre.
  Aclarado por AskUserQuestion (2 rondas): (1) no bastaba con el clic en
  el visor 3D de la ronda 21 -quería elegir la columna directo en el
  dibujo de vista previa del propio diálogo-, y de paso pidió que los
  escalones fueran de 50-60cm de separación calculados solos según el
  punto elegido, no escritos a mano; (2) confirmó que la torre debe
  subir SIEMPRE toda la altura de la estructura -de la base al último
  nivel de esa columna-, no un tramo parcial.
  Implementación:
    - `selector.html`: el canvas de vista previa ahora es clicable.
      `pickCell(px,py)` invierte analíticamente la proyección isométrica
      `project(x,y,z)` -para z=0- para saber en qué celda (i,j) cayó el
      clic; la celda elegida se resalta en naranja semitransparente y
      persiste mientras se ajustan otros campos. Los campos manuales de
      celda/escalones/altura/separación de la torre desaparecieron por
      completo -ya no hacen falta-; solo queda el selector de diagonal
      inicial y un texto que muestra en vivo la columna elegida, cuántos
      escalones caben y su separación real (réplica en JS de la fórmula
      de Ruby, solo para la vista previa).
    - Nueva función `auto_tower_step_fit(total_height_mm)`: busca, entre
      1 y 40 huecos, la cantidad de escalones cuya separación caiga en
      500-600mm; si varias califican, prefiere la más cercana a 600mm
      -menos escalones, coincide con el valor ya confirmado con datos
      reales en rondas anteriores-; si NINGUNA cae exacto en el rango
      -alturas "incómodas", ej. una estructura de 1 solo módulo de alto
      dio 627mm, 27mm arriba del rango-, devuelve la que menos se aleje
      en vez de fallar -se muestra el número real en el resumen, sin
      bloquear la creación por un desajuste de pocos mm-.
    - `tower_params_from_dialog` ya NO recibe medida de celda ni
      escalones del diálogo: usa la MISMA medida de la estructura
      (`spacing_x_mm`/`spacing_y_mm`) para la celda de la torre, calcula
      la altura total real con `grid_level_z(0,...)` a `grid_level_z(nz,
      ...)` -los mismos niveles que usa la cuadrícula, así los
      escalones caen en las mismas alturas que los nodos reales-, llama
      a `auto_tower_step_fit`, y guarda `offset_x_mm`/`offset_y_mm`
      (`i*spacing_x_mm`, `j*spacing_y_mm`) para ubicar la celda (i,j)
      exacta.
    - `ModulePlacementTool` vuelve a ser de UN SOLO clic -ya no hace
      falta un segundo clic para la torre, porque la celda (i,j) ya se
      fijó en el diálogo-: tras crear la estructura, si hay torre,
      calcula su esquina SO sumando `offset_x_mm/offset_y_mm` al mismo
      punto de clic y llama a `create_triangle_tower` de inmediato.
    - El flujo independiente (menú "Agregar torre de pisos
      triangulares" + `torre_triangular.html`, para agregar una torre a
      una estructura YA existente sin volver a crearla) se deja SIN
      TOCAR -ahí no hay vista previa de cuadrícula ni altura total
      conocida de antemano, así que sigue con escalones/altura/
      separación manuales-.
  Verificado con dry-run en Ruby puro reproduciendo `auto_tower_step_fit`
  con alturas reales de 1 a 4 niveles (usando `DEFAULT_SPACING_M`): 2, 3
  y 4 niveles caen dentro o muy cerca del rango 500-600mm (605.8mm,
  598.6mm, 595.0mm); 1 nivel solo da 627.4mm -aceptable como caso límite,
  una torre de escaleras en un módulo de un solo nivel no tiene mucho
  sentido de todas formas-. También se verificó a mano la fórmula
  `pickCell` como inversa exacta de `project`. Empaquetado en
  `constructor_modulos_playidea_v0.18.0.rbz`. Pendiente de que el
  usuario lo pruebe visualmente en SketchUp.

  **Ronda 23 — nuevo plugin independiente: `alberca_esponjas_playidea`
  (alberca de esponjas).** El usuario pausó el trabajo de la torre
  triangular para preparar un ejemplo nuevo -"son cubos ordenados de
  manera aleatoria"- y pidió (1) analizar el `.txt` más nuevo de
  `inspect_geometry.rb` y (2) un plugin nuevo que reciba ancho/alto/largo
  y llene ese volumen con cubos de esponja en posición y rotación
  aleatoria, simulando una alberca de esponjas.
  Análisis del `.txt` (`inspect_20260729_122045.txt`, 12 cubos dentro de
  un contenedor de ~740x733x235mm): las bounding boxes de los 12 cubos
  variaban mucho (202x250x231mm, 150x205x205mm, etc.) por estar cada uno
  rotado distinto, pero aplicando la fórmula de bounding box de un cubo
  rotado -`bbox_en_un_eje = arista * suma de valores absolutos de esa
  fila de la matriz de rotación (xaxis/yaxis/zaxis)`- contra los datos
  reales se confirmó, con coincidencia EXACTA a 3+ decimales en varios
  cubos (ej. 150*(0.866+0.5)=204.9mm, igual al bounds real), que **todos
  los cubos miden exactamente 150mm de arista**. Las rotaciones no
  seguían un patrón fijo de incrementos de 30°/45° -salvo un cubo que
  por casualidad quedó en una rotación limpia de 30° en un solo eje-, así
  que se interpretó como rotación libre (eje y ángulo al azar). La tabla
  de "Distancias LOCALES" mostraba huecos negativos frecuentes (hasta
  -260mm), confirmando traslape intencional entre cubos vecinos -look de
  alberca revuelta, no cuadrícula ordenada-.
  Plugin nuevo (`alberca_esponjas_playidea/`, independiente, no depende
  de `conectores_playidea` ni `creador_tubos_playidea` -solo necesita
  geometría de cubo sólido, mucho más simple que un tubo hueco-):
    - `DEFAULT_CUBE_SIZE_MM=150.0` -del análisis-, `JITTER_FACTOR=0.35`
      -fracción del tamaño de cubo que se mueve cada uno respecto al
      centro de su celda de cuadrícula, para que los vecinos alcancen a
      traslaparse igual que en el ejemplo real-, `MAX_CUBE_COUNT=4000`
      -techo de seguridad, si la combinación de volumen/tamaño de cubo
      lo excede, el diálogo pide agrandar el cubo o achicar el volumen
      en vez de intentarlo-.
    - `grid_counts`: cuántos cubos caben por eje (redondeado, mínimo 1)
      para que la cuadrícula base cubra el volumen completo.
    - `add_cube_geometry`: cubo sólido (6 caras, sin hueco -a diferencia
      de los tubos estructurales, una esponja no necesita interior
      hueco-), centrado en el origen local.
    - `cube_definition_for`: una definición cacheada por color -hasta 7,
      una por color de la paleta Play Idea-, para no duplicar geometría
      por cada instancia.
    - `random_rotation_transform`: eje aleatorio (vector con
      componentes `rand(-1.0..1.0)`, normalizado por
      `Transformation.rotation`) + ángulo aleatorio 0-2π, compuesto como
      `translation(point) * rotation(ORIGIN, axis, angle)` -mismo patrón
      ya usado en el proyecto para rotar respecto al propio centro del
      objeto, no respecto al origen del modelo-.
    - Color: mezcla aleatoria de la paleta de 7 colores Play Idea (una
      al azar por cubo) o un solo color fijo, elegido por el usuario.
    - Diálogo (`selector.html`): ancho/alto/largo (m), tamaño de cubo
      (cm), modo de color, código; vista previa en vivo del número
      aproximado de cubos. Un clic para la esquina inferior -mismo
      patrón `PlacementTool`/`InputPoint` que el resto de los plugins-.
  Verificado con dry-run en Ruby puro: geometría del cubo (8 esquinas
  únicas, 6 caras planas, cubriendo las 6 orientaciones sin repetir) y
  el techo de seguridad (3x3x1m con cubo de 15cm da 2800 cubos, bajo el
  límite; 5x5x2m con cubo de 5cm da 400,000, dispara el límite
  correctamente). Empaquetado en `alberca_esponjas_playidea_v0.1.0.rbz`.
  Pendiente de que el usuario lo pruebe visualmente en SketchUp -esta
  ronda, igual que otras de geometría nueva, solo se verificó la
  aritmética/estructura, no el resultado 3D real-.

## Torre triangular — herramientas de iteración rápida (rondas 24+)

A partir de aquí el usuario pidió explícitamente **dejar de reinstalar el
`.rbz` para cada prueba** y armar scripts que reconstruyan estructura+torre
desde cero en segundos, pegándolos en la consola de Ruby. Estos scripts viven
en `scripts/` (raíz del proyecto, visibles en Finder) y son la herramienta
principal de esta fase — más importante que `inspect_geometry.rb` solo, que
sigue usándose para extraer datos de referencias hechas a mano.

- **`scripts/copiar_grupo_referencia.rb`**: duplica exacto un grupo
  seleccionado (`entities.add_instance(original.definition, transform)`,
  reusa la `definition` sin reconstruir geometría) en `original.parent.
  entities` -NUNCA `model.active_entities`, eso genera una copia invisible
  en el contexto equivocado, ya pasó-. Genera un reporte recursivo
  (nombre/tipo/bounds/origen/ejes de cada sub-pieza, sin límite de
  profundidad) a `inspect_output/reporte_grupo_TIMESTAMP.txt`. Auto-corre si
  se pega con algo ya seleccionado.
- **`scripts/comparar_grupos.rb`** (v2): compara las piezas DIRECTAS -no las
  tuercas/opresores internos de cada conector- de 2 grupos seleccionados,
  emparejando por tipo (`CON-12`/`CON-21`/`CON-10`/`TUBO`) + posición más
  cercana (voraz, no por orden ni cantidad -v1 exigía mismo conteo/orden y
  truena en cuanto se corrige algo a mano-). Resta la MEDIANA del
  desplazamiento entre todos los pares emparejados antes de reportar -para
  no confundir un desfase sistemático del grupo completo (ej. la copia quedó
  1cm corrida) con correcciones reales pieza por pieza-. Flujo: seleccionar
  el original (salida del plugin) + una copia corregida a mano al lado
  (`copiar_grupo_referencia.rb`), pegar este script con ambos seleccionados.
- **`scripts/probar_integrado.rb`**: `load` (no `require`, para que SÍ
  re-ejecute el archivo aunque ya esté cargado, redefiniendo los métodos del
  módulo en el mismo lugar) directo sobre `constructor_modulos_playidea/
  main.rb` -el archivo FUENTE, no el instalado en Plugins-, borra el
  resultado de la corrida anterior por prefijo de código, y reconstruye
  estructura + torre integrada (mismo flujo que el checkbox real del
  diálogo, vía `tower_params_from_dialog` + `create_triangle_tower`) en un
  solo paso. Cualquier edición a `main.rb` se ve reflejada pegando el script
  de nuevo, sin empacar `.rbz` ni reinstalar. **Gotcha real, ya resuelto**:
  `main.rb` usa la constante `EXTENSION` -normalmente la define el loader
  `constructor_modulos_playidea.rb`, que registra la extensión de verdad- y
  truena con `uninitialized constant` si no hay ninguna versión instalada en
  esa sesión de SketchUp (ej. el usuario la desinstaló para probar una
  versión nueva desde cero). Fix: `load LOADER_RB unless defined?(PlayIdea::
  ConstructorModulos::EXTENSION)` antes del `load` de `main.rb`.

### Metodología reafirmada por el usuario en esta fase

- **Nunca capturas de pantalla si hay matemáticas disponibles** -cita
  textual: *"por qué capturas de pantalla si tenemos las matemáticas
  cartesianas para sketchup... eso te debería permitir ver a través de los
  números"*-. Pedir siempre el `.txt` de `copiar_grupo_referencia.rb`/
  `inspect_geometry.rb`, nunca interpretar una imagen si hay datos exactos
  disponibles. Solo se volvió a captura cuando los números YA coincidían
  exacto con la referencia y el usuario seguía reportando "mal" -señal de
  que el problema real no era el que se estaba verificando (ver hallazgo de
  la esquina SE/SO más abajo)-.
- **El usuario corrige a mano en SketchUp para que yo detecte la corrección
  por número, no para que le pregunte qué cambió** -cita: *"por eso hice las
  correcciones manuales para que las detectes y no preguntes"*-.
- **No editar código a partir de un cálculo propio si no viene de una
  corrección real del usuario** -lección cara de esta fase, ver "el inset de
  105mm" más abajo-: un ajuste de CON-21 a 105mm calculado por mí mismo
  -geometría de colisión contra el poste, sin ningún dato del usuario detrás-
  no cambió nada visible cuando se probó, y el usuario lo notó de inmediato
  ("ya veo que estás a prueba y error"). Se revirtió a 34.65mm -el único
  valor con evidencia real, aunque de una sola muestra-. Regla: cualquier
  número que no salga de comparar datos reales (antes/después del usuario)
  se marca explícitamente como no verificado en el comentario, y no se
  "mejora" adivinando.
- **Verificar el archivo COMPLETO antes de derivar una fórmula, no solo lo
  que se alcanza a leer en el chat** -el reporte de `copiar_grupo_
  referencia.rb` puede llegar truncado en el mensaje pegado por el usuario
  pero el script YA lo guardó completo en `inspect_output/`; leerlo del
  disco con `Read`/`grep` en vez de asumir que lo pegado es todo lo que hay
  reveló, más de una vez en esta fase, que el escalón "faltante" sí estaba
  ahí, solo no se había leído hasta el final-.

### Hallazgo — comparar la esquina equivocada de la celda (SO vs. SE)

El script de prueba (`probar_integrado.rb`) pedía `tower_corner: 'se'` por
costumbre de rondas anteriores, pero la referencia real más nueva del
usuario tenía el CON-21 pegado a la esquina física `(45,45)` -la que
`triangle_cell_corners` etiqueta como `:sw`, no `:se`-. Varias rondas de
"sigue mal" fueron en realidad comparar triángulos en dos esquinas OPUESTAS
de la misma celda -no un error de geometría, un error de qué esquina usar en
el script de prueba-. **Lección**: cuando la comparación numérica formal
-posición Y rotación, verificadas por separado- da error casi perfecto (0-3mm)
pero el usuario sigue insistiendo en que está mal, sospechar primero de una
discrepancia de CONFIGURACIÓN entre lo que se está probando y lo que se está
comparando (¿misma esquina? ¿mismo grupo? ¿misma versión del archivo?), no
seguir ajustando la fórmula.

### Fixes de geometría de la torre, con evidencia numérica

1. **CON-12 diagonal: dirección de la fórmula estaba invertida, no solo la
   magnitud.** La fórmula original alejaba cada CON-12 a lo largo de la
   DIAGONAL -hacia la esquina opuesta, `near.offset((far-near).normalize,
   INSET)`-. Con datos reales -4 instancias, 2 escalones- el desplazamiento
   medido resultó ser puro ±X o puro ±Y -NUNCA diagonal a 45°-, siempre
   apuntando hacia la esquina del ÁNGULO RECTO de ese escalón, a lo largo del
   borde de celda propio de cada CON-12 -`near.offset((ra_point-near).
   normalize, INSET)`, no `(far-near)`-. Esto explica por qué el tubo nunca
   embonaba bien pese a que la MAGNITUD (105mm, ver abajo) ya estaba cerca de
   la correcta: la dirección era otra. Verificado también contra
   `DISENOS_REFERENCIA` (ronda 19), que ya mostraba el mismo patrón sin que
   se hubiera notado antes.
2. **Magnitud del inset del CON-12: 105mm, no 186mm.** Una ronda anterior
   había subido el inset de 90mm (medido en 4 torres aisladas, sin
   cuadrícula alrededor) a 186mm, comparando contra una "corrección a mano"
   que resultó no ser la referencia buena -el usuario lo aclaró después: *"te
   paso la torre correcta"* resultó ser justo la que tenía 40 piezas -sin
   corregir-, no la de 43 -la que se había usado como "después"-. Con la
   referencia correcta confirmada, las 4 instancias de CON-12 dieron 104.2,
   104.9, 104.8 y 106.6mm -promedio 105.1mm-, consistente con el rango
   original de 65-114mm de la ronda 19. **Lección repetida de esta fase**:
   cuando el usuario dice "esta es la correcta", confirmar CUÁL de los
   archivos/grupos disponibles es -aquí, comparar conteo de piezas y valores
   contra lo ya analizado- antes de re-derivar cualquier constante a partir
   de ella.
3. **Tubo de la pata (CON-21↔CON-10): NO es un tubo entre esos dos
   conectores, es un tubo de BORDE DE CELDA estándar.** El código original
   calculaba el largo del tubo desde la boca del CON-21 -ya movido 34.65mm
   de su esquina- hasta la boca del CON-10. Real: es un tubo esquina-cruda a
   esquina-cruda -`ra_point` a `leg_point`, SIN el inset del CON-21- con la
   misma inserción `RECEIVER_RADIUS_MM` (24.15mm) que cualquier tubo recto de
   la cuadrícula, no `TRIANGLE_MOUTH_INSET_MM` (12.075mm). Confirmado: el
   nombre real del tubo es `TUB-MOD-X-1120.1` = separación de celda menos
   2×24.15mm -EXACTA la fórmula de un tubo de borde normal, ni una constante
   nueva-, y ambos extremos caen a 1-3mm de esa fórmula contra los datos
   reales. El CON-21 se queda donde estaba -su posición/rotación ya estaban
   verificadas correctas por separado-, solo el TUBO se desconecta de su
   posición y se ancla a la geometría cruda de la celda.
4. **Boca del tubo diagonal (CON-12↔CON-12): offset COMPUESTO en 2 ejes
   locales, no 1.** La fórmula original desplazaba la boca solo a lo largo
   del eje Z local del CON-12 (`-TRIANGLE_MOUTH_INSET_MM`). Con la tabla de
   rotación CAPPED -la única en uso ahora que todos los escalones llevan
   triángulo completo, ver punto 6- el offset real resultó compuesto: X local
   ≈ `-TRIANGLE_MOUTH_INSET_MM`, Z local ≈ `-RECEIVER_RADIUS_MM` -mismas dos
   constantes ya existentes, combinadas, no valores nuevos-. Verificado con
   ~2.1mm de error en una instancia. Al promediar las 4 instancias
   disponibles (2 escalones) hubo ruido real -de -12 a +0.68mm en X, -19.76 a
   -32.67mm en Z-, así que el valor final no salió de una fórmula limpia sino
   de iterar con retroalimentación visual directa del usuario -"muévelo hacia
   la parte contraria del ángulo de 45, como 1cm"-, incluyendo una corrección
   de signo cuando el primer ajuste resultó ir en la dirección contraria a la
   pedida. Valores finales en producción: `DIAGONAL_MOUTH_LOCAL_X_MM=-2.0`,
   `DIAGONAL_MOUTH_LOCAL_Z_MM=-28.5`. **Lección**: cuando ni la fórmula
   analítica ni el promedio de las muestras disponibles convergen del todo,
   iterar con el usuario mirando el resultado en vivo -preguntando dirección
   y magnitud aproximada- es válido y más rápido que seguir derivando de
   datos ya de por sí ruidosos; solo hay que estar listo para que la primera
   corrección salga con el signo equivocado y haya que revertir.
5. **Escalones ALTERNAN la esquina del ángulo recto, no usan siempre la
   misma.** Confirmado con datos reales: el CON-21 del escalón 1 está pegado
   a una esquina de la celda, el del escalón 2 a la esquina DIAGONALMENTE
   OPUESTA -no la misma-. `step_corner` ahora alterna: pares usan
   `params[:right_angle_corner]`, impares la opuesta
   (`TRIANGLE_CORNER_ORDER[(idx+2)%4]`). Verificado exacto -posición Y
   rotación- contra el escalón 2 usando las tablas de rotación que ya
   existían en el código (`TRIANGLE_CONNECTOR_AXES_CAPPED[:ne]`) pero nunca
   se seleccionaban porque el código siempre usaba la esquina fija del
   parámetro original.
6. **TODOS los escalones llevan el triángulo completo -CON-21+2 patas-, no
   solo el primero y el último.** El diseño original (ronda 19, con datos de
   torres aisladas de solo 2-3 escalones) tapaba solo el primer/último
   escalón con el triángulo completo y dejaba los de en medio con solo la
   diagonal. Al escalar a más escalones (`nz>1`), el usuario confirmó que
   CADA escalón necesita su propio ángulo recto. Con esto, `TRIANGLE_
   CONNECTOR_AXES` -la tabla "sin tapa"- quedó sin ningún uso y se eliminó;
   `TRIANGLE_CONNECTOR_AXES_CAPPED` es ahora la única tabla de rotación del
   CON-12 en toda la torre.

### Escalones que escalan con la altura real de la estructura (parcialmente en `main.rb`, resto solo en copia experimental)

El usuario pidió que la torre, con `modules_z>1`, suba con más escalones -no
se quede fija en 2- y que la separación se calcule sola entre 50-60cm
dependiendo de la altura REAL de cada módulo (`spacing_z_mm`), no de un
número fijo inventado. Esto pasó por varias vueltas de diseño, algunas
revertidas:

- **Primer intento (revertido)**: hacer que la torre suba hasta el nivel
  real de arriba de la cuadrícula (`grid_level_z(nz,...)`). Contradicho por
  datos reales: con 1 módulo de alto, la torre confirmada por el usuario
  tiene exactamente 2 escalones -506mm y ~1006mm- y se queda ahí, SIN llegar
  al nivel real de arriba (1337mm en ese caso). Revertido a fijo 2
  escalones/500mm para `nz=1`.
- **`main.rb` (producción actual)**: para `nz` cualquiera, usa `auto_tower_
  step_fit(nz * TOWER_FIRST_STEP_HEIGHT_MM)` -un solo auto-ajuste sobre un
  total de `nz*500mm`-. Funciona pero es una fórmula desconectada de la
  altura REAL del módulo (`spacing_z_mm`) -solo coincide por casualidad con
  el caso validado de `nz=1`-.
- **Corrección pedida explícitamente por el usuario, NO llevada a `main.rb`
  todavía -"no modifiques nada de lo que ya funciona, crea nuevas versiones
  para estas pruebas"-**: el número de escalones y su separación deben
  depender de la altura REAL de cada módulo, tramo por tramo entre cada
  nivel real de la cuadrícula -no una sola separación uniforme para toda la
  torre-, Y la torre es una ESCALERA de planta baja a la ÚLTIMA planta -sube
  por cada nivel real intermedio pero se DETIENE en la base del último
  módulo, sin seguir escalones dentro de él, igual que una escalera real no
  sigue subiendo si ya no hay más pisos-. Con `nz=1` no aplica esta lógica
  -no hay "siguiente piso"-, se queda con el patrón fijo ya validado (2
  escalones/500mm).
- **Feature relacionada, tampoco en `main.rb`**: si la altura de un escalón
  coincide con un nivel real de la cuadrícula -tolerancia
  `GRID_LEVEL_COINCIDENCE_TOLERANCE_MM=5.0mm, sin validar con datos reales
  todavía-, ese escalón debe omitir el CON-21+2 patas -el nivel real YA
  tiene sus propios conectores/tubos ahí, duplicar sería incorrecto- y dejar
  solo la diagonal + sus 2 CON-12.

**Toda esta lógica nueva vive SOLO en `scripts/main_niveles_experimental.rb`
-copia completa de `main.rb`, módulo renombrado a `PlayIdea::
ConstructorModulosNiveles` -`extend self`, mismo patrón- para no pisar nada
del plugin real ni siquiera si ambos están cargados en la misma sesión de
SketchUp-, probada con `scripts/probar_torre_niveles.rb`,
`scripts/probar_torre_niveles_dinamico.rb` y `scripts/probar_torre_alturas_
variables.rb`.** Pendiente de portar a `main.rb` cuando el usuario confirme
que el diseño ya quedó -sigue siendo una copia de pruebas, no producción-.

Funciones nuevas en la copia experimental:
- `auto_tower_step_heights(bottom_z_mm, real_grid_levels_mm, nz)`: con
  `nz<=1` devuelve el patrón fijo validado (`[bottom_z_mm, bottom_z_mm +
  TOWER_FIRST_STEP_HEIGHT_MM]`). Con `nz>1`, sube tramo por tramo entre
  `real_grid_levels_mm[1..(nz-1)]` -del segundo nivel real al PENÚLTIMO,
  nunca hasta el tope-, auto-ajustando cada tramo por separado con
  `auto_tower_step_fit` para que el escalón final de cada tramo caiga
  EXACTO en el nivel real correspondiente.
- `grid_level_z(k, nz, sz)` ampliada: `sz` ahora puede ser un `Length` único
  -separación uniforme, como siempre- O un `Array` de `Length` -una altura
  por módulo, para estructuras con cada piso de altura distinta-; con
  Array, la altura acumulada hasta el nivel k es `sz[0...k].sum`, no
  `k*sz`. Todos los ~10 sitios que ya llamaban `grid_level_z(k,nz,sz)` en
  `create_grid_tubes`/`create_grid_connectors` siguen funcionando SIN
  tocarlos -la variabilidad se resolvió centralizada en esta única función-;
  solo hizo falta un helper nuevo `spacing_z_length(spacing_z_mm)` en los 4
  puntos donde se convierte `params[:spacing_z_mm]` a `Length` (`.mm` no
  funciona sobre un Array) y una corrección en `write_module_attributes`
  -hacía `nz * params[:spacing_z_mm]`, que revienta con un Array; ahora usa
  `.sum` cuando es Array-. El poste Z vertical YA calculaba su largo
  dinámicamente por segmento (`length_mm = (z_end - z_start).to_mm` dentro
  del loop, con `cached_tube_definition` por largo exacto) desde una ronda
  anterior -no necesitó ningún cambio para soportar alturas variables-.

**Verificado con datos calculados (no con referencia hecha a mano; esta
sub-feature es nueva y sin ejemplo real todavía)**: con 3 módulos de
1700/1600/1500mm, `auto_tower_step_heights` da 7 escalones, deteniéndose
exacto en el nivel real 2 (base del tercer módulo, 3438.45mm) sin subir
hasta su tope (4962.6mm) -patrón "escalera al último piso" confirmado por
diseño, pendiente de que el usuario lo confirme viéndolo en SketchUp con
más ejemplos-.

## Estado de empaquetado a la fecha de esta bitácora

`constructor_modulos_playidea.rb` dice versión `0.7.9`, pero el `.rbz`
correspondiente fue borrado y regenerado varias veces durante esta fase -y
la última vez que se generó (`v0.7.9.rbz`) fue ANTES de dos rondas de
edición directa a `main.rb` (escalones ligados a `nz*500mm` en vez de fijo,
y "todos los escalones con triángulo completo")-. **`main.rb` en disco está
más adelantado que cualquier `.rbz` empacado**: antes de darle este proyecto
por "listo para instalar", reempacar desde el `main.rb` actual (ver patrón de
reempacado más arriba) y subir el número de versión.
