---
name: tobogan-completo-playidea
description: Contexto y convenciones para trabajar en los ensambles de tobogán espiral (scripts/tobogan_completo_playidea.rb de referencia, scripts/tobogan_variedades_altura_playidea.rb paramétrico por altura, scripts/tobogan_con_estructura_playidea.rb unido a una estructura modular, PROBADOS SUELTOS antes de empacarse) y su versión EMPACADA dentro del plugin real constructor_modulos_playidea/tobogan/ (codo_90.rb, recto.rb, salida.rb, solera.rb, aro_entrada.rb, tornilleria.rb, builder.rb), incluyendo el selector de orilla/celda en selector.html. Úsala siempre que se edite alguno de esos archivos, se agregue un "brazo" de soporte nuevo, se toque la integración del tobogán con constructor_modulos_playidea, o se toque la tornillería de las uniones.
---

# Tobogán completo — poste central + brazos de soporte

## Qué es esto y dónde vive

`scripts/tobogan_completo_playidea.rb` es un script SUELTO (no un plugin
`.rbz` instalable) que se carga con `load '/ruta/al/archivo.rb'` en la
Consola de Ruby de SketchUp. Cada `load` vuelve a correr el archivo completo
y coloca la herramienta — es un flujo de trabajo distinto al de los plugins
empaquetados (ver la skill `sketchup-plugins` para esos). Ensambla, en una
sola pieza (`build_assembly`): tramo recto de entrada + `ELBOW_COUNT` codos
de 90° (codo_90_playidea.rb) formando una espiral de inclinación constante +
salida (salida_tobogan_playidea.rb), más un poste central vertical con
CON-61 en la base y uno o más "brazos" horizontales de soporte que conectan
el poste con el ducto real, cada uno con su propia solera (abrazadera) que
carga el peso del ducto.

Depende de (todos en `scripts/`, cargados como módulos Ruby normales, NO
como plugins separados): `codo_90_playidea.rb`, `salida_tobogan_playidea.rb`,
`tobogan_recto_playidea.rb`, `soporte_solera_playidea.rb`. Usa
`PlayIdea::CreadorTubos.build_tube` y `PlayIdea::Conectores.create_connector`
de los plugins reales (`creador_tubos_playidea`, `conectores_playidea`) vía
`require`.

## Antes de experimentar con un brazo nuevo: copiar el archivo

Si el usuario pide agregar un brazo/soporte nuevo mientras uno anterior ya
quedó confirmado como bueno ("ese no lo toques, quedó perfecto"), **copiar el
archivo completo a un nombre nuevo** (ej. `tobogan_completo_playidea_brazoN.rb`)
y renombrar el módulo dentro de la copia (`sed -i '' 's/NombreViejo/NombreNuevo/g'`,
incluyendo el `Object.send(:remove_const, ...)` y el `Script.start` final) en
vez de seguir editando el archivo original. Así un experimento que sale mal
nunca arriesga el trabajo ya validado. Confirmar con `ruby -c` tras el rename.

## Convenciones geométricas establecidas

- **Mapeo de ejes locales (Gram-Schmidt)**: para cualquier pieza que "viaja"
  a lo largo de una `direction` (codo, salida, soporte de solera, brazo):
  `local_x = direction.normalize; reference = local_x.parallel?(up_hint) ? Y_AXIS : up_hint;
  local_y = local_x.cross(reference).normalize; local_z = local_x.cross(local_y).normalize`,
  luego `Geom::Transformation.axes(punto, local_x, local_y, local_z)`.
- **Reorientar un conector ya colocado**: `PlayIdea::Conectores.create_connector`
  solo posiciona por traslación. Para orientarlo hay que reasignar
  `instance.transformation = Geom::Transformation.axes(punto, target_x, target_y, target_z)`
  con vectores UNITARIOS (`.normalize` — un vector `Point3d - Point3d` no
  normalizado como eje ahí ESTIRA la geometría, bug real ya visto más de una
  vez). Convención: se elige `target_x`/`target_z` según la orientación
  deseada y siempre `target_y = target_z.cross(target_x)`.
- **CON-10 "T acostada" vs "T de cabeza"**: acostada = paso principal
  VERTICAL (`target_x = Z_AXIS`, sigue al poste) + ramal HORIZONTAL
  (`target_z = direccion_del_brazo.reverse`). De cabeza = paso principal
  HORIZONTAL (`target_x = direccion_del_brazo`) + ramal VERTICAL hacia arriba
  (`target_z = Z_AXIS.reverse`, ya que de fábrica el ramal es local -Z).
- **CON-12 ("T inclinada a 45°", usada para refuerzos diagonales poste↔brazo)**:
  paso recto centrado en local X (se monta ENCIMA de un tubo existente, como
  abrazadera — no reemplaza nada) + un ramal a 45° fijo, en dirección local
  `(-1,0,-1)` normalizado, de 76.2mm. **Gotcha real, ya causó un "no embona"**:
  el ramal NO arranca en el punto de colocación del conector (el centro del
  paso recto) — arranca desplazado por el radio del propio cuerpo del
  conector (`PlayIdea::Conectores::OUTSIDE_MM / 2.0` = 24.15mm) en la
  dirección `target_z.reverse`. Al construir el tubo diagonal que une 2
  CON-12, el punto de arranque real en cada conector es
  `punto_de_colocacion.offset(target_z.reverse, con12_receiver_radius_mm)`,
  NO el punto de colocación directo. Para que el tubo diagonal entre parejo
  a 45° en ambos ramales, el triángulo poste-brazo debe ser ISÓSCELES: la
  distancia horizontal (sobre el brazo) debe ser igual a la caída vertical
  (sobre el poste).
- **`duct_segments` + `nearest_duct_point`/`point_at_segment_fraction`**:
  array que registra cada tramo del ducto real (`{type: :straight, ...}` o
  `{type: :elbow, entry:, direction:, exit_direction:, radius:, sweep:}`,
  `sweep` SIEMPRE el barrido físico de 90° del codo, nunca el avance de
  rumbo `step`/`delta_phi` de la espiral — son cosas distintas, confundirlas
  rompe la búsqueda). `nearest_duct_point` busca en TODO el ducto el punto
  más cercano en PLANTA (solo X,Y, ignora altura) — útil para orientar una
  solera pero puede "enganchar" un codo totalmente distinto si el punto de
  búsqueda se mueve mucho (ver más abajo, colisión con el ducto).
- **Patrón "ancla fija" para desacoplar la solera del giro del brazo**: si se
  quiere que rotar el brazo (`armN_shift_mm`) NO mueva la solera, se calcula
  un punto de ancla aparte con su propio ángulo de giro
  (`armN_leg_anchor_shift_mm`), y la pata/solera usan ese ancla en vez del
  punto en vivo del brazo. Trade-off real: el conector de en medio (que SÍ
  vive en el brazo, pegado a él) se separa visualmente de la pata/solera si
  el ancla y el brazo divergen demasiado — aceptable para desplazamientos
  chicos, se ve mal para desplazamientos grandes. Si se congela el ancla,
  **debe inicializarse igual al giro actual del brazo** (no en 0 a secas) o
  aparece desconectada desde el primer render — bug real cometido al copiar
  este patrón para un brazo nuevo.
- **Radio de rotación desacoplado del largo del brazo**: los ángulos de giro
  (`armN_rotation_rad = -(shift_mm / radius_mm)`, arco/radio) deben calcularse
  con un radio CONGELADO (`armN_rotation_radius_mm`, fijado con un valor
  histórico constante, ej. `+ 500.0`), no con `armN_mid_mm` en vivo — si no,
  acortar/alargar el brazo después cambia SILENCIOSAMENTE todos los ángulos
  ya calibrados (bug real, causó que "acortar 30cm" moviera la solera y
  bajara el brazo sin que se pidiera).
- **Holgura de conector (`CONNECTOR_SOCKET_CLEARANCE_MM`)**: un tubo que
  entra en un conector debe arrancar/terminar esa holgura ANTES del CENTRO
  del conector, nunca en el centro exacto — si no, invade el paso principal
  perpendicular del conector (ej. un CON-10 "acostado": el tubo del brazo
  debe parar en el límite de su ramal horizontal, no seguir hasta el centro
  donde vive el paso vertical que sigue al poste).

## Colisión brazo↔ducto: cómo NO calcularla mal (bug propio, ya corregido)

**Gotcha crítico al simular esta geometría en Ruby puro fuera de SketchUp**:
`Point3d#offset` tiene DOS firmas con significados distintos — `offset(vector)`
(un solo argumento) suma el vector TAL CUAL, sin normalizar; `offset(vector,
distancia)` (dos argumentos) normaliza el vector primero y luego escala por
`distancia`. El código real usa la primera forma para `bend_offset`
(`point.offset(bend_offset)`, un solo argumento — son ~550-780mm de
magnitud real). Una primera simulación aparte, hecha para medir qué tan
apretada está la espiral, usó por error la segunda forma en ese paso
(`.offset(bend_offset, 1.0)`), lo que dividía el offset entre su propia
magnitud y lo dejaba de ~1mm en vez de ~550-780mm — la espiral simulada salía
MUCHÍSIMO más apretada de lo real (el centro de cada codo, a solo ~60-70mm
del eje del poste). **Corregido y reverificado**: con la fórmula correcta,
el centro de cada codo queda a ~490-550mm del eje del poste (mucho más
razonable, del orden del propio radio de doblez de 550mm). Antes de confiar
en cualquier simulación geométrica de este archivo, verificar primero contra
un caso ya conocido -ej. que la altura calculada dé exacto 4.000m a
pitch=20.08°- para descartar este tipo de bug.

Aun con la geometría corregida, un brazo apuntando "derecho" (radial, sin
girar) desde el poste al centro de su codo objetivo SÍ suele rozar el codo
vecino -la espiral sigue siendo angosta comparada con el radio del ducto,
408mm-, así que hace falta girarlo un poco (t​ípicamente 100-130°, NO ~172°
-ese número venía del bug de arriba-) para separar el brazo del resto del
ducto. Ver más abajo (`tobogan_variedades_altura_playidea.rb`) la solución
que terminó adoptándose: en vez de "girar para esquivar", el usuario pidió
que el brazo sea SIEMPRE radial (apunte derecho al codo, sin ningún giro
artificial) y que sea su LARGO EXACTO -ni más ni menos que la distancia real
hasta quedar justo debajo del ducto- lo que evita la colisión. Con esa regla
NO hace falta ninguna búsqueda de "mejor ángulo de escape".

Para el tobogán de REFERENCIA (`tobogan_completo_playidea_hasta_brazo4_LISTO.rb`,
girado a mano viendo el render, valores como 850mm para el brazo 2) sigue
aplicando la lección original: **el valor de giro de un brazo NO se copia a
otro brazo sin verificar**, aunque el radio de giro salga parecido entre
ambos -la geometría alrededor de cada codo es distinta-.

## Unidades de rotación que usa el usuario

Pide giros en "cm de arco" (arco = `shift_mm`, convertido a radianes con
`angle_rad = shift_mm / radio_mm`, arco/radio) o en horas de reloj ("media
hora" = 15°), siempre combinado con sentido de manecillas del reloj. Convención
ya establecida en este archivo: manecillas del reloj (visto desde arriba) =
signo NEGATIVO en `Geom::Transformation.rotation(punto, Z_AXIS, angle_rad)`,
porque un ángulo positivo alrededor de +Z es antihorario visto desde arriba.

## `tobogan_variedades_altura_playidea.rb` — tobogán PARAMÉTRICO por altura

Generaliza el tobogán de referencia (que tiene la inclinación fija en
`PITCH_DEG=20.08` resuelta a mano por bisección para dar EXACTO 4.000m) para
aceptar CUALQUIER altura total, con brazos de soporte 100% automáticos -sin
ajuste fino a mano-. Backup confirmado:
`tobogan_variedades_altura_playidea_LISTO.rb`.

- **Bisección de altura → inclinación, en Ruby puro**: `height_mm_for_pitch`
  replica SOLO la caída vertical por los codos (`dir_at(...).z = -sin(pitch)`,
  no depende del rumbo/azimut en planta, así que no hace falta simular la
  espiral completa para resolver la altura) + `2×radio_exterior_ducto +
  CON61_BELOW_EXIT_MM` (una vez para "superficie exterior de arriba" al
  inicio, otra para "base" al final). Verificado exacto: da 4.000m en
  pitch=20.08°, coincide con el valor ya validado a mano.
- **Si la altura pedida es muy grande, el pitch necesario se dispara** -con
  el mismo `ELBOW_COUNT` fijo, pasa de 45° -límite físico del codo- antes de
  llegar a alturas razonables (~7m)-. Pedido del usuario: "si un tobogán
  queda muy alto, no debe subirse la inclinación, mejor agregarle vueltas".
  `elbow_count_and_pitch_for_height` busca el MENOR número de codos de
  espiral tal que el pitch resuelto no pase de `MAX_REASONABLE_PITCH_DEG`
  (22°, muy cerca del 20.08° ya validado) — un tobogán de 7m con 8 codos
  necesitaría ~44° (kamikaze); con 15 codos da ~20.5°.
- **Regla geométrica de los brazos, pedida explícitamente por el usuario
  -sin excepción-**: cada brazo apunta RADIAL -derecho del eje del poste
  al codo que sostiene, sin ningún giro artificial para "esquivar" nada- y
  su LARGO ES EXACTO -ni más ni menos que la distancia real hasta quedar
  justo debajo del ducto-. Es el largo exacto, no un giro, lo que evita que
  el brazo atraviese el ducto. Nunca inventar una búsqueda de "mejor ángulo
  de escape" para esto -se intentó, el usuario lo corrigió explícitamente-.
- **El tubito de la solera debe tocar la BASE real de la solera, en su MISMA
  inclinación** -no solo apuntar al centro del ducto, y no vertical
  genérico-. `solera_local_z(target_tangent)` replica el mismo Gram-Schmidt
  que usa `soporte_solera_playidea.rb` (`direction=target_tangent,
  up_hint=Z_AXIS.reverse`) para saber hacia dónde "cae" la solera en SU
  propia inclinación; `base_point = target_point.offset(local_z.reverse,
  SOLERA_OUTER_RADIUS_MM.mm)` es su superficie real -408mm desde el centro-,
  no el centro. Un CON-10 "de cabeza" solo puede apuntar su ramal DENTRO del
  plano perpendicular a su paso principal -nunca hacia adelante/atrás sobre
  el brazo mismo, es una T rígida, no una rótula-, así que la dirección real
  del tubito es la proyección de `local_z` sobre ese plano, no `local_z`
  directo.
- **`align_arm_to_solera_base`**: búsqueda conjunta por fuerza bruta -pura
  aritmética de vectores, sin crear geometría- de AZIMUT del brazo (giro
  fino alrededor del eje Z del poste, unos cuantos grados) + DROP (qué tan
  abajo arranca el poste del brazo respecto al codo) que minimizan el hueco
  entre la punta del tubito de la solera -con conector y todo- y
  `base_point`. Pedido explícito del usuario: "girar el brazo, no solo
  mover el drop" -mover solo el drop no bastaba, ver conversación-. El hueco
  residual nunca llega a cero -la restricción del CON-10 rígido de arriba lo
  impide- pero queda del orden de 2-2.5cm, aceptable.
- **Bug real, ya corregido, a vigilar si se copia este patrón**:
  `branch_raw.length < 1.0` como chequeo de "vector degenerado" solo es
  correcto si `branch_raw` viene de un vector con magnitud real en mm -como
  antes, cuando se proyectaba `to_solera`, una diferencia de puntos reales-.
  Al cambiar a proyectar `local_z` -que YA es unitario-, `branch_raw.length`
  SIEMPRE es ≤1.0 por construcción, así que ese chequeo se disparaba
  SIEMPRE y ningún brazo se construía ("no tiene brazos" reportado por el
  usuario). El umbral correcto para un vector ya unitario es algo como
  `< 0.01` -cercano a CERO, no a uno-.
- **`arm_plan_for_height` necesita una base mínima de 3, no 2**: repartir
  solo 2 brazos a lo largo del rango de codos da los dos EXTREMOS, sin
  ningún brazo real en medio -el usuario lo notó a simple vista, "le falta
  un soporte en medio"-. Con base 3, `(0...count).map { |k| (k*max_index/
  (count-1).to_f).round }` sí incluye un índice genuino de en medio.
- **Vector3d#dot devuelve Float CRUDO en pulgadas, no un Length** -a
  diferencia de `Vector3d#length`, que sí regresa Length con `.to_mm`-. Al
  usar el resultado de `.dot(...)` para una distancia real, multiplicar por
  `25.4` a mano -NO `.to_mm`, que no existe sobre un Float plano-. Bug real
  cometido y corregido en este archivo.

## `tobogan_con_estructura_playidea.rb` — tobogán unido a una estructura modular

Combina el tobogán paramétrico de arriba con una cuadrícula real construida
con el plugin `constructor_modulos_playidea`, llamando su API Ruby
directamente -sin pasar por su diálogo HTML-. Ver también la skill
`sketchup-plugins` para el contexto general de ese plugin.

- **Cómo invocar el constructor de módulos sin su UI**:
  `PlayIdea::ConstructorModulos.params_from_automatic_data({'ancho_m'=>...,
  'largo_m'=>..., 'alto_m'=>..., 'color'=>..., 'code'=>'', 'padding'=>bool,
  'solera'=>bool, 'platform'=>bool, 'net'=>bool})` regresa un `params` hash
  completo -mismo que usaría su herramienta interactiva-, listo para
  `PlayIdea::ConstructorModulos.create_module(params, origin)`. No hace
  falta calcular `modules_x/y/z`/`spacing_*_mm` a mano.
- **Nivel de plataforma real**: `place_platforms` en ese plugin solo cubre
  niveles `k=0..nz-1` -el nivel `k=nz`, el más alto, es solo el riel de
  cierre, sin piso-. El nivel útil para "parado sobre la estructura" es
  `k = nz-1`.
- **Centro/orilla de una celda, con las funciones del propio plugin**
  -reusar, no reinventar-: `axis_column_width_mm(index, spacing)` (ancho de
  esa columna/fila, Float CRUDO en mm) y `axis_cumulative_mm(index,
  spacing)` (offset acumulado hasta esa columna/fila, YA en Length) — ambas
  aceptan `spacing` como Float uniforme O Array -medio módulo-, sin que el
  caller necesite saber cuál es. `axis_cumulative_mm(nx, sx_mm)` -con `nx`,
  no `nx-1`- da la ORILLA real después de la última columna. `grid_level_z`
  necesita que `spacing_z_mm` -que puede venir como Float o Array de
  `params[:spacing_z_mm]`- se convierta PRIMERO con
  `spacing_z_length(...)` -Length o Array de Length-, no se le puede pasar
  el Float crudo directo.
  - **Gotcha de unidades real, ya corregido**: `axis_column_width_mm`
    regresa Float CRUDO (no Length) mientras `axis_cumulative_mm` regresa
    Length — sumarlos directo malinterpreta el Float como pulgadas. Hace
    falta `.mm` explícito sobre el resultado de `axis_column_width_mm`
    antes de sumarlo a un Length.
- **Altura del CON-61 del tobogán alineada con la de la estructura**: la
  altura total del tobogán (`target_height_mm`, definida como "de la base
  del CON-61 a la superficie EXTERIOR de arriba del recto") mide desde
  `ground_z` hasta la SUPERFICIE, pero el punto de entrada -`start_point`,
  usado para construir- es la LÍNEA CENTRAL del recto, un radio de ducto
  -`BODY_OUTSIDE_R_MM`, 408mm- más abajo que esa superficie. Para que
  `ground_z` -y con él, el CON-61 del tobogán- caiga EXACTO en `origin.z`
  -la altura de los CON-61 de la estructura-, el punto de entrada debe
  calcularse como `origin.z + (target_height_mm - duct_outside_r_mm).mm`,
  restando ese radio -NO `target_height_mm` directo-. Verificado
  algebraicamente con la identidad de `height_mm_for_pitch` (arriba).
- **El recto debe arrancar en la ORILLA real de la cuadrícula, no en medio
  de una celda** -pedido explícito tras la primera prueba, "el tobogán está
  metido en la estructura"-: usar `edge_x = axis_cumulative_mm(nx, sx_mm)`
  -la orilla, no el centro de una celda- como X del punto de entrada, con
  `heading = X_AXIS` -hacia afuera de la estructura, no hacia adentro-.
- **Unir el poste del tobogán a un poste real de la estructura en 2 alturas**
  -patrón `build_post_link`-: un CON-10 "acostado" en cada extremo -paso
  principal vertical, ramal horizontal apuntando al otro poste- más un tubo
  entre medio, mismo patrón que ya usan los brazos del tobogán con su propio
  poste. **La liga debe viajar derecho en X** -mismo Y en ambos extremos,
  usando la Y real del poste del tobogán, NO la Y de un nodo de la
  cuadrícula-, o si no viaja en diagonal y puede cruzar el ducto recto -bug
  real ya visto y corregido-.
- **Soporte de tierra en la punta del brazo de la salida** -replicado del
  "primer brazo" del tobogán de referencia, pedido explícito del usuario-:
  el brazo que sostiene cerca de la salida no solo cuelga de un conector de
  en medio -como los demás brazos automáticos-, sino que se extiende un
  tramo más allá y baja hasta un SEGUNDO CON-61, a la MISMA altura que el
  CON-61 del poste central, vía un segundo CON-10 "acostado" -paso principal
  vertical libre hacia abajo, ramal horizontal recibiendo el tubo desde el
  poste-. Ver `build_exit_ground_support`, llamada aparte con
  `loop_i = elbow_count - 1` después del ciclo normal de brazos.
- **Soporte extra para el tramo RECTO, parado sobre la propia estructura**
  -no sobre un codo de 90° del tobogán-: `build_recto_support` arranca desde
  el riel real de la estructura -mismo X que `structure_post_x`, Y real del
  recto- con un CON-10 "de cabeza" -paso principal horizontal a lo largo del
  riel, `target_x = Y_AXIS`; ramal vertical hacia arriba, `target_z =
  Z_AXIS.reverse`-, tubo vertical, y una solera abrazando el recto en su base
  real -un radio de ducto por debajo de su línea central-.
- **El recto es una pieza COMPARTIDA por todos los scripts de tobogán**:
  cambiar `TOTAL_LENGTH_MM` en `tobogan_recto_playidea.rb` afecta a los tres
  scripts (referencia, paramétrico, con estructura) a la vez — avisar
  explícitamente al usuario cuando se toque, no es un cambio aislado. Si
  crece el recto y se quiere que la ESPIRAL no se mueva -pedido real: "no
  hagas eso, solo crece el recto"-, hay que compensar `move_closer_mm` -en
  `tobogan_con_estructura_playidea.rb`- por la MISMA cantidad que creció,
  jalando `entry_point` hacia la estructura para que el extremo LEJANO
  -donde arranca la espiral- se quede exactamente donde ya estaba.

## `aro_entrada_tobogan_playidea.rb` — collar/pestaña en la entrada del recto

Pieza nueva, suelta, pedida para que quede en la zona que creció el recto -ver
arriba-: un aro más ancho que el recto -mismo radio interno que
`BODY_OUTSIDE_R_MM` del recto, 408mm, para que el recto entre justo- con un
escalón hacia afuera -la "pestaña"- en un extremo, que en corte a lo largo
del eje se ve como un ángulo de 90° -el perfil salta de golpe de un cilindro
angosto a uno más ancho, no un cono-. Reusa el mismo patrón
`circle_points`/`add_wall`/`add_ring` que `tobogan_recto_playidea.rb`.

- **Orientación real, corregida tras el primer intento** -"el aro va al
  revés"-: la pestaña debe quedar del lado de la ENTRADA -`entry_point`, del
  lado de la estructura, visible-, y el extremo liso/abierto -por donde
  entra el recto- del lado de la espiral. Para lograrlo, el aro se construye
  arrancando MÁS ADELANTE que `entry_point` -su propio largo total,
  `COLLAR_LENGTH_MM + FLANGE_THICKNESS_MM`- y con la `direction` INVERTIDA
  respecto al recto, así su remate -la pestaña- cae exacto en `entry_point`.
  No asumir que "mismo punto, misma dirección que el recto" es la
  orientación correcta -fue el primer intento, y estaba al revés-.
- Se integra en `tobogan_con_estructura_playidea.rb` justo después de
  construir el `lead_in` (el recto), en el mismo punto/dirección de entrada.

## `tornilleria_playidea.rb` — tornillos de las uniones de pestaña

Pieza nueva, suelta, que modela el juego de tornillería REAL -con costos de
factura trazables como BOM, ver `set_costing`/`costing_rows`- que asegura
cada unión de pestaña de los ductos y cada extremo de una solera. Un
tornillo coche 5/16"×1½" por juego: cabeza REDONDEADA -"bombudita"- que
queda DENTRO del ducto -no lastima al deslizarse-, cruza radialmente la
pared, y por fuera se aprieta con rondana + tuerca hexagonal + una tapa
-tuerca bellota- sobre lo que sobra de tornillo, cerrando la punta.

- **NO es tuerca hexagonal O tapa -bellota-, corrección real del usuario**:
  van LAS DOS, apiladas en orden -rondana, tuerca hexagonal, tapa sobre el
  sobrante-. El primer intento las trató como alternativas
  (`nut_type: :hex` vs `:bellota`); el usuario corrigió explícitamente que
  siempre van juntas. El largo de la tapa se ADAPTA a lo que sobre de
  tornillo tras la tuerca hexagonal -`cap_available_mm =
  (shaft_end_z - cap_start_z).to_mm`-, no es un tamaño fijo.
- **`add_ring` con radio interior 0 rompe `add_face`** -"Duplicate points in
  array"-: un anillo con radio interior 0 colapsa todos los puntos
  "internos" en el mismo punto. Para remates cerrados -la punta de un
  vástago, el ápice de un domo- hay que cerrar con un ABANICO de triángulos
  -`center + outer[i] + outer[i+1]`-, nunca con la tira de cuadrángulos
  normal de `add_ring`. Bug real, encontrado al primer test en SketchUp.
- **Radios distintos en la misma Z necesitan su propio anillo de cierre**:
  la cabeza -domo, radio `HEAD_R_MM`- se conecta al vástago -radio mucho más
  chico, `BOLT_SHAFT_R_MM`- en la misma Z; sin un `add_ring` explícito entre
  esos 2 radios ahí -la "cara de apoyo" de la cabeza contra la pared del
  ducto- queda un hueco abierto en la malla. Mismo tipo de bug que la
  transición cuerpo→ceja de las demás piezas, pero fácil de olvidar en una
  pieza nueva con radios variables como esta.
- **`Sketchup::View#zoom` no acepta un `BoundingBox`** -causó "no veo nada"
  con la herramienta de prueba, sin error, porque simplemente no hacía
  nada-: hay que pasarle un Array de entidades, `view.zoom([group])`, no
  `view.zoom(group.bounds)`.
- **Cachear la definición del tornillo, NO construir una nueva por
  instancia**: una sola unión de pestaña necesita 4 juegos, y un tobogán
  completo tiene ~9+ uniones más las soleras -30-40+ tornillos-. Construir
  cientos de caras por cada uno es carísimo. `bolt_definition(model,
  wall_thickness_mm)` cachea por `wall_thickness_mm` -la única variable real
  entre sitios de uso- y solo coloca instancias nuevas del mismo componente
  de ahí en adelante; la geometría se construye una sola vez.
- **Patrón "tache" (X), no "cruz" (+)**: los 4 tornillos de una unión no van
  alineados con `up_hint` -eso forma una cruz-, van desfasados 45°
  (`BOLT_PHASE_DEG`) para formar una X. Pedido explícito del usuario tras
  ver el primer resultado.
- **Centrar el tornillo A LA MITAD del traslape, no en la orilla/boca de la
  unión**: el punto natural que ya trae el código -`point` tras avanzar por
  el largo total de la ceja- es la BOCA de la ceja, la orilla exterior de la
  pieza — un tornillo ahí no agarra material real. Hay que retroceder
  `direction.reverse` la MITAD del largo de la ceja
  (`CEJA_LENGTH_MM / 2.0`) antes de llamar `build_flange_bolts`. Mismo
  criterio para el aro de entrada -se centra a la mitad de su CUERPO liso,
  no de su pestaña, que es solo el remate-.
- **Los tornillos de la solera van en los 2 EXTREMOS DEL ARCO, no en los
  lados de su ANCHO** -`soporte_solera_playidea.rb` va de `ARC_START_DEG=180°`
  a `ARC_END_DEG=360°`-, y metidos `SOLERA_BOLT_ARC_INSET_MM` -5cm- hacia el
  CENTRO del arco -hacia phi=270°, el punto más bajo-, SIGUIENDO LA
  CURVATURA -mismo radio, ángulo distinto-, no en línea recta. Puestos justo
  en la punta del arco -phi=180°/360° exactos- no tenían material real
  alrededor para agarrar y la solera se podía safar -corrección real del
  usuario-. `build_solera_bolts` replica el mismo Gram-Schmidt que usa
  `soporte_solera_playidea.rb#build_piece` -`up_hint=Z_AXIS.reverse`- para
  ubicar `local_y`/`local_z` y así el ángulo phi caiga exacto sobre el arco
  real de la solera.
- **Grosor de pared distinto según el tipo de unión**: unión ducto↔ducto -o
  aro↔recto- cruza 2 paredes de 8mm = 16mm total; solera↔ducto cruza la
  pared del ducto -8mm- + el grueso de la propia solera
  -`SUPPORT_THICKNESS_MM`, 6mm- = 14mm total. No es el mismo número en los
  2 casos.
- **Verificar geometría nueva con un arnés fuera de SketchUp antes de pedirle
  al usuario que reintente**: para diagnosticar "no veo nada" se armó un mock
  mínimo de `Geom::Point3d`/`Vector3d`/`Sketchup::Entities#add_face` -que
  simula el `ArgumentError: Duplicate points` real de SketchUp- y se corrió
  `build_flange_bolts` fuera de SketchUp, contando caras creadas/degeneradas
  y el bounding box resultante. Encontró los 2 bugs reales -`add_ring` con
  radio 0 y el `view.zoom` inválido- sin gastar ciclos de "vuelve a probar y
  dime qué ves". Mismo patrón ya usado antes con `build_support_arm` -ver
  arriba-, vale la pena repetirlo para cualquier geometría nueva no trivial.

## Empacado dentro de constructor_modulos_playidea -tobogán real, no de prueba-

Los scripts sueltos de arriba (`scripts/*.rb`) son solo para PROBAR con
`load` en la Consola de Ruby -nunca se empaquetan en un `.rbz`-. Para que
`constructor_modulos_playidea` pueda crear un tobogán cuando el plugin
está instalado normalmente -sin la Consola de Ruby abierta-, las 6 piezas
+ la lógica de armado se COPIARON -no se referencian por `load`- dentro de
`constructor_modulos_playidea/tobogan/`, namespaced bajo
`PlayIdea::ConstructorModulos::Tobogan::*` -`Codo90`, `Recto`, `Salida`,
`Solera`, `AroEntrada`, `Tornilleria`, `Builder`- para no chocar con los
módulos globales (`PlayIdeaCodo90Script`, etc.) que usan los scripts
sueltos si ambos llegan a cargarse en la misma sesión.

- **Decisión de arquitectura, confirmada con el usuario antes de empezar**:
  empacar DENTRO de constructor_modulos_playidea -no un plugin
  `tobogan_playidea` aparte, aunque sería más reusable- porque es menos
  trabajo YA y el tobogán todavía no lo necesita ningún otro plugin. Costo
  aceptado: si se corrige algo en la geometría, hay que replicarlo en 2
  lugares -el script suelto de prueba Y la copia empacada-, no hay una
  sola fuente de verdad. Si el tobogán llega a necesitarse desde OTRO
  plugin, ahí sí conviene partirlo a su propio `.rbz`.
- **`Tobogan::Builder.attach(params, origin)`** es el punto de entrada real,
  llamado desde `ModulePlacementTool#onLButtonDown` en main.rb -DESPUÉS de
  `create_module`, con los mismos `params`/`origin` que ya se usaron para
  construir la cuadrícula-. Es la versión "solo la mitad de después" del
  `build_structure_with_tobogan` del script suelto: la construcción de la
  cuadrícula/torre ya la hizo el flujo normal del diálogo, `attach` arranca
  justo después de eso.
- **La altura del tobogán no siempre viene de un campo "alto total"**: el
  diálogo AUTOMÁTICO sí tiene `alto_m` -mismo significado que
  `target_height_mm`, se guarda tal cual en `params[:tobogan_height_mm]`
  dentro de `params_from_automatic_data`-, pero el diálogo MANUAL solo
  tiene cantidad de módulos + medida de cada uno, sin ese campo. Para el
  manual, `PlayIdea::ConstructorModulos.real_total_height_mm(params)`
  -nuevo método- la reconstruye a partir de `modules_z`/`spacing_z_mm` vía
  `grid_level_z(nz,nz,sz) - TOP_SEGMENT_TO_LAST_CINCHO_TOP_MM`: es la
  inversa EXACTA de `fit_modules_z_and_spacing` -sin pérdida por
  redondeo, el sobrante de la planta baja absorbe el residuo completo por
  construcción-, así que aplicada a una estructura creada por el AUTOMÁTICO
  reproduce el `alto_m` original tal cual.
- **Elegir la orilla/celda de arranque, pedido explícito del usuario**:
  antes el tobogán estaba fijo a la orilla +X, fila centrada. Ahora
  `params[:tobogan_edge]` -`:x_near`/`:x_far`/`:y_near`/`:y_far`- +
  `params[:tobogan_index]` -índice de celda a lo largo de esa orilla-
  controlan esto, con default -edge `:x_far`, índice centrado- si no se
  especifican -así el diálogo AUTOMÁTICO, que no tiene selector, conserva
  el comportamiento de siempre sin cambiar nada-. `Tobogan::Builder.attach`
  resuelve `heading` -hacia dónde sale el tobogán- y `rail_axis` -hacia
  dónde corre el riel real de la estructura en esa orilla, antes fijo a
  `Y_AXIS`, ahora pasado a `build_recto_support`- según el edge elegido.
- **Selector interactivo, mismo patrón que ya usaba la torre**: en
  `selector.html` -diálogo MANUAL, el automático no tiene vista previa de
  cuadrícula-, clic en una celda de la ORILLA de la vista de arriba
  (`drawTopView`) elige el tobogán -`edgeForCell(i,j,layout)` determina a
  cuál de las 4 orillas pertenece una celda, y devuelve `null` -no
  elegible- para las celdas de ESQUINA, que tocan 2 orillas a la vez y son
  ambiguas; a diferencia de la torre, aquí no hace falta excluir aparte las
  columnas/filas de medio módulo-. Si torre Y tobogán están AMBOS
  activados, un solo selector (`#pickModeField`, oculto si no aplica)
  decide a cuál de las 2 selecciones apunta el siguiente clic -evita la
  ambigüedad de "¿este clic era para la torre o el tobogán?"-.

## Alineamiento salida↔entrada -INTENTADO Y REVERTIDO, no reintentar así

Pedido del usuario: que la salida del tobogán apunte en la MISMA dirección
que la entrada. Se intentó -`elbow_count_and_pitch_for_height` buscando,
entre TODOS los `elbow_count` del rango -`MIN_STEADY_ELBOW_COUNT` a
`MAX_STEADY_ELBOW_COUNT`-, el que diera menor desalineamiento- y se
**REVIRTIÓ** por regresión real reportada por el usuario: para una
estructura de 5m, esa búsqueda elegía `elbow_count=20` -pitch=9.3°, ~5
VUELTAS- en vez del `elbow_count=10` -pitch=20°, ~2.7 vueltas- que daba
el criterio original -primer `elbow_count` con pitch ≤22°-, y el
desalineamiento apenas mejoraba de todos modos -~28° en ambos casos,
verificado numéricamente-. Con tantas vueltas apretadas los ductos salen
"pegados" entre sí -reportado por el usuario, "no manches salen bien
pegados los ductos"-. Los 3 lugares donde vive esta función
-`tobogan_con_estructura_playidea.rb`,
`tobogan_variedades_altura_playidea.rb`,
`constructor_modulos_playidea/tobogan/builder.rb`- están de vuelta al
criterio ORIGINAL: primer `elbow_count` válido, sin buscar alineamiento.

**Por qué la búsqueda de alineamiento no valía la pena, verificado
numéricamente antes de revertir**: el codo de 90° tiene un radio de
doblez FIJO, así que `delta_phi` -cuánto gira cada codo "parejo" de la
espiral- queda atrapado en una banda angosta -~90-100° para cualquier
pitch entre 0 y 22°-. Eso significa que, para una altura dada, solo hay
~15 combinaciones DISCRETAS de giro total alcanzables, y el MEJOR
desalineamiento posible entre ellas ronda igual los 20-30° en la
mayoría de los casos -a veces tan bueno como ~4.5°, pero sin patrón
previsible-: la ganancia real casi nunca justifica el costo -muchas más
vueltas, pitch mucho más angosto, ductos apretados-.

Se probaron y DESCARTARON otras 2 alternativas antes de revertir del
todo:
- **Ampliar el rango de `elbow_count`** -hasta 60 en vez de 20-: no
  mejora consistentemente -a veces empeora- y produce toboganes
  absurdos -pitch de 1.5°, 15 vueltas completas para solo 3m de altura-.
- **Fijar el giro EXACTO y dejar la altura con tolerancia** -resolver
  pitch para que el giro dé multiplo exacto de 360°, aceptando que la
  altura real se desvíe unos mm/cm del pedido-: el error de altura
  resultante fue de METROS -1-3.6m de diferencia en las pruebas-.
  Completamente inaceptable -la altura debe coincidir con la estructura
  real, no es negociable-.

**Conclusión, y NO reintentar sin esto**: no hay una palanca de diseño
barata para garantizar alineamiento exacto sin rediseñar la pieza del
codo -ej. un codo con radio de doblez variable, o una pieza de "ajuste
fino" en el ángulo de salida-. Si el usuario vuelve a pedir esto, la
respuesta correcta es explicar esta limitación de entrada -no
implementar otra búsqueda "más lista" dentro del diseño actual del
codo fijo, ya se intentó dos veces y ambas veces terminó rota o
descartada-.

## El tubo del soporte del recto debe medir SIEMPRE ~20cm -no lo que salga-

Pedido del usuario, corrección real: el tubo del soporte que carga el
tramo recto -desde el riel real de la estructura hasta el recto- debe
medir SIEMPRE `RECTO_SUPPORT_LEG_MM` -200mm-, sin importar la altura
pedida. Antes de esta corrección, `target_height_mm` se tomaba
DIRECTAMENTE del dato del usuario -`alto_m`/`params[:tobogan_height_mm]`-
y `entry_z` -dónde arranca el recto- se derivaba de ESE valor; el hueco
resultante entre el riel -`structure_top_z`, el ÚLTIMO NIVEL USABLE,
`k=nz-1`, no el tope real de la cuadrícula `k=nz`- y el recto salía lo
que la geometría diera -normalmente mucho más de 20cm, del orden de un
módulo completo-.

**El orden de causalidad se invirtió**: ahora `structure_top_z` se
calcula PRIMERO, `entry_z` se ancla a `structure_top_z +
RECTO_SUPPORT_LEG_MM + duct_outside_r_mm` -el tubo fijo, más el radio del
ducto porque `entry_z` es la LÍNEA CENTRAL, no la superficie inferior-, y
`target_height_mm` se RECALCULA despejando la fórmula ya validada
`entry_z = origin.z + (target_height_mm - duct_outside_r_mm)` al revés
-en vez de usarla en el sentido original-. El dato del usuario
-`alto_m`/`tobogan_height_mm`- YA NO se usa para esto -queda como
metadata sin uso real en `attach`-: la altura real del tobogán la
determina la estructura misma -su último nivel usable + este margen
fijo-, no un número aparte que podía desalinearse. Esto preserva la
otra garantía ya validada -`ground_z` del tobogán sigue cayendo exacto
en `origin.z`- porque es la MISMA identidad algebraica, solo despejada
al revés.

Aplicado en los 2 lugares donde vive esta lógica:
`constructor_modulos_playidea/tobogan/builder.rb#attach` -el real- y
`scripts/tobogan_con_estructura_playidea.rb#build_structure_with_tobogan`
-la copia suelta de prueba-.

## Ligas poste↔estructura: evitar ductos reales, no adivinar un offset fijo

Pedido del usuario, corrección real: "veo que roza mucho un ducto de
90°" -la liga de ARRIBA, que antes usaba un offset fijo
-`top_link_drop_mm=450mm` bajo `entry_point.z`- caía justo dentro del
PRIMER codo de la espiral -ese arranca plano -pitch de entrada 0- y no
baja gran cosa en su primer tramo, así que un offset chico cae
exactamente ahí-. Pedido también: entre más alto el tobogán, más ligas
-antes siempre 2, fijas-.

**`link_zs_avoiding_ducts`** -mismo patrón que ya usa `build_support_arm`
con `point_at_segment_fraction`, aplicado aquí al revés: en vez de
buscar DÓNDE está un codo para apuntarle un brazo, busca DÓNDE NO hay
problema para pasar una liga-: para cada Z objetivo, calcula el azimut
-respecto al eje del poste- de cada codo real (`duct_segments`) y elige
el que tenga el azimut MÁS ALEJADO del azimut hacia la estructura -el
ducto de la espiral queda del lado CONTRARIO del poste en esa Z, no
cruzando el camino de la liga-, con al menos 60° de librancia si es
posible; si ninguno alcanza eso cerca de la Z buscada, se conforma con
el más cercano que haya. **Requiere que `build_tobogan` regrese
`duct_segments`** en su hash de resultado -antes solo regresaba
`group`/`centroid_x_mm`/`centroid_y_mm`/`ground_z`/`start_z`-.

**Más ligas conforme crece el tobogán**: `LINK_SPACING_MM` -1800mm-
define cada cuánto se agrega una liga extra; `extra_link_count = [1 +
round(post_span_mm / LINK_SPACING_MM), 1].max` -siempre mínimo 1, más
conforme el poste es más alto-. La liga de ABAJO -`bottom_z`, cerca del
suelo, sin problema reportado- se queda con su offset fijo de siempre
-`bottom_link_drop_mm=150mm`, sin buscar codos ahí-; las EXTRA se
reparten parejas entre `bottom_z` y `entry_point.z` y cada una busca su
propio codo seguro vía `link_zs_avoiding_ducts`.

**Gotcha real, ya corregido**: `Array#filter_map` es Ruby 2.7+; el Ruby
del sistema en esta máquina es 2.6.10 -`ruby -c` para sintaxis SÍ pasa
igual, pero `NoMethodError` real al ejecutar-. No hay precedente de
`filter_map` en el resto del proyecto -revisar con `grep` antes de
usar sintaxis Ruby "moderna" en este codebase; usar `.select{}.map{}`
en su lugar-. El Ruby que empaca SketchUp puede ser más nuevo, pero no

## Ligas poste↔estructura, versión 2: por AZIMUT no basta, hace falta distancia real

Corrección real del usuario tras probar la primera versión -"varios de
los tubos... atraviesan los ductos"-: el chequeo por azimut de arriba
-comparar solo el ángulo del punto MEDIO de cada codo contra el azimut
hacia la estructura- tenía 2 huecos reales: (1) solo miraba los tramos
`:elbow`, NUNCA los `:straight` -la ceja de 100mm después de cada codo,
Y el recto/aro de la entrada misma-, y (2) un codo con azimut "lejano"
en su punto MEDIO puede de todos modos acercarse mucho a la liga cerca
de sus EXTREMOS -barre 90°, el azimut cambia a lo largo de todo el
codo, no es constante-. Ambos huecos dejaban pasar colisiones reales.

**Reemplazado por un chequeo de distancia real** -`link_clearance_mm` +
`point_to_segment_distance_mm`-: para una Z candidata, arma el segmento
horizontal exacto de la liga -poste↔estructura-, MUESTREA cada tramo de
`duct_segments` -recto Y codo, cada uno en ~12 puntos vía
`point_at_segment_fraction`- y calcula la distancia mínima punto-a-
segmento de CADA muestra a la liga, restando el radio real del ducto
-`duct_outside_r_mm`-. `link_zs_avoiding_ducts` escanea TODO el rango
`bottom_z..top_z` cada `LINK_SCAN_STEP_MM` -50mm- con este chequeo y
elige, para cada Z objetivo, la Z real más cercana con al menos
`LINK_CLEARANCE_SAFETY_MM` -60mm, margen extra sobre el radio del ducto
para el grosor de la liga misma- de espacio libre; si NINGUNA Z del
rango alcanza eso, se conforma con la de más espacio libre disponible
-mejor que la peor posible, nunca sin liga-. Verificado con un arnés de
prueba fuera de SketchUp -mismo patrón ya usado varias veces en este
proyecto-: una Z "ingenua" que antes se hubiera usado dio espacio libre
de **-258mm** -choque real, profundo-, mientras el algoritmo nuevo
encontró Z's con 78-96mm de espacio libre genuino para el mismo caso.

## Recubrimiento de espuma también en la estructura del tobogán

Pedido del usuario: el poste/brazos/ligas del tobogán -tubos
ESTRUCTURALES, no las piezas de fibra de vidrio del ducto mismo- deben
recubrirse con espuma + cinchos igual que el resto de la cuadrícula,
mismos colores elegidos (`padding_color_mode`/`vertical`/`horizontal`).

- **`pad_existing_tubes` ya existía y es genérico** -mismo usado para la
  torre-: recorre un grupo, encuentra instancias cuyo NOMBRE DE
  DEFINICIÓN empiece con `'TUB-'`, y las envuelve. Las piezas de fibra
  de vidrio -codos, recto, salida, aro, tornillería- usan sus propios
  prefijos -`TOBOGAN-...`, `TORNILLERIA-...`- así que YA quedan
  excluidas solas, sin necesidad de ningún chequeo extra.
- **2 gotchas reales, ambos corregidos, para que el tobogán calificara**:
  -1- sus tubos usaban códigos `'TUBO-ESTRUCTURAL-...'` -con "O"-, que
  NO hace match con `start_with?('TUB-')` -cuatro caracteres exactos,
  el cuarto tiene que ser el guion-; renombrados a `'TUB-ESTRUCTURAL-
  ...'`. -2- `pad_existing_tubes` además EXTRAE EL LARGO del nombre de
  la definición vía `name.scan(/\d+\.\d+/).last` -un patrón decimal-,
  así que aunque el prefijo ya hiciera match, un código sin ningún
  número decimal -`'TUB-ESTRUCTURAL-POSTE'` a secas- lo dejaba sin
  largo y se saltaba esa instancia (`next unless length_str`); hubo que
  agregar el largo real formateado a 1 decimal al final de CADA código
  -`"TUB-ESTRUCTURAL-POSTE-#{format('%.1f', post_total_length_mm)}"`-,
  mismo patrón que ya usa la cuadrícula (`TUB-MOD-#{eje}-#{largo}`).
- **Dónde se llama**: `Tobogan::Builder.attach` ahora regresa
  `{tobogan_group:, link_group:}` -antes solo el group del tobogán,
  sin el de las ligas-, y `ModulePlacementTool#onLButtonDown` -en
  main.rb- llama `pad_existing_tubes` en AMBOS grupos, DESPUÉS de
  `attach` -no antes, el tobogán no existe todavía cuando se recubre
  el resto de la estructura/torre-, con su propio
  `padding_color_selector(@params)` -mismo criterio de color que ya
  usa el resto-.

## Colores de los ductos del tobogán -3 modos, materiales SEPARADOS del foam

Pedido del usuario: los ductos de fibra de vidrio del tobogán -codo,
recto, salida, aro- deben poder usar los mismos 8 colores de
`STANDARD_COLOR_PALETTE`, con 3 modos -mono/bicolor/aleatorio-, mismo
concepto que ya existía para el recubrimiento
(`padding_color_mode`/`_vertical`/`_horizontal`) pero un modo más
-"bicolor" no existía-.

- **`Tobogan::Builder.tobogan_color_picker(params)`** regresa un PROC,
  no un valor -se llama una vez POR PIEZA construida, en el orden que se
  van armando (recto, aro, cada codo, salida)-: `'mono'` siempre el
  mismo hex; `'bicolor'` alterna 2 hex con un contador cerrado sobre el
  proc; `'aleatorio'` un `.sample` distinto cada llamada. Sin
  `tobogan_color_mode` -params vacío- da `nil` siempre, cada pieza cae
  en su propio gris por default -mismo comportamiento que antes de este
  cambio, sin romper a quien no mande estos params-.
- **`build_tobogan` ahora recibe un 4to parámetro** -`color_params`,
  default `{}`- y `attach` le pasa el `params` completo. Cada llamada a
  `Codo90`/`Recto`/`Salida`/`AroEntrada`.build_piece ahora manda
  `{color_hex: next_color.call}` en vez de `{}` -por eso el primer
  parámetro de esos 4 `build_piece`, antes `_params` -ignorado a
  propósito-, pasó a llamarse `params` de verdad-.
- **Pedido explícito, importante para el render en Twinmotion**: aunque
  el foam/cinchos y los ductos del tobogán usen el MISMO color -mismo
  hex-, deben ser materiales de SketchUp DISTINTOS -Twinmotion mapea
  cada material de SketchUp a su propio acabado, y el foam/cinchos son
  brillosos, las plataformas de vinil menos, y la fibra de vidrio del
  tobogán es LA MÁS brillosa de todas; si comparten un material no se
  puede dar cada acabado por separado-. `apply_hex_material` -la función
  ya existente, usada por foam/cinchos/plataformas- SIEMPRE crea/reusa
  un material `"Color #HEX"` COMPARTIDO entre todo lo que lo use -EN LOS
  HECHOS, foam, cinchos Y plataformas de vinil ya comparten ese mismo
  material hoy, aunque el usuario diga que deberían ser 2 acabados
  distintos -es un problema real, preexistente, fuera del alcance de
  este cambio, "empezar a separarlos" fue la frase del usuario-. Los
  ductos del tobogán NO llaman a `apply_hex_material`: cada pieza tiene
  su PROPIA función de material -`tobogan_material(model, color_hex)` en
  Codo90/Recto/Salida, `aro_material(model, color_hex)` en AroEntrada-
  que arma un nombre PROPIO -`"PlayIdea Tobogán Fibra de Vidrio #HEX"`,
  `"PlayIdea Aro Entrada #HEX"`- nunca `"Color #HEX"`, así Twinmotion
  los ve como materiales distintos aunque el hex sea idéntico.
- **Gotcha real, ya corregido, al escribir las 4 funciones de
  material**: un primer intento con `sed`/regex dejó una línea
  redundante -`material = model.materials[name] || model.materials.add(name)`-
  ANTES de recalcular `name` con el hex, creando un material genérico
  sin usar/sin color propio en el modelo por cada pieza construida
  -inofensivo funcionalmente -la variable se sobreescribe después-, pero
  basura real en `model.materials`-. Revisar el resultado de una
  transformación por regex a mano antes de darla por buena, no solo con
  `ruby -c`.

## Cotizador: cuenta piezas por NOMBRE, `instance.name` debe llevar el CODE real

`cotizador_playidea` -ver `reference_play_idea_explorer_pricing_catalog`
en memoria- cuenta piezas seleccionadas recorriendo la jerarquía y
comparando NOMBRES contra regexes -`recorrer()`, `piece_name(entity)`-.
`piece_name` usa `entity.name` -el nombre de la INSTANCIA- si no está
vacío, y SOLO cae al nombre de la definición si `entity.name` está
vacío. **Gotcha real, ya corregido**: `tornilleria.rb`
-`build_bolt_set`- ponía `instance.name = 'TORNILLO'` -genérico, a
secas- en vez de `instance.name = CODE` -como hacen TODAS las demás
piezas-, así que aunque la DEFINICIÓN sí se llamaba
`TORNILLERIA-5-16-1.5` -con el código real-, el cotizador nunca lo veía
porque la INSTANCIA ganaba con su nombre genérico. Cualquier pieza
nueva que se agregue a este sistema debe poner
`instance.name = CODE` -nunca un string genérico- para que el cotizador
-o `pad_existing_tubes`, mismo patrón de conteo por nombre- pueda
reconocerla.

## "Entrada" de la estructura -selector de celda de orilla SIN malla, no es del tobogán-

Feature independiente del tobogán -la estructura puede tener entrada
sin tobogán, o los dos en orillas distintas- pero documentada aquí
porque vive en los mismos archivos (`constructor_modulos_playidea/
main.rb`, `selector.html`) y reutiliza EXACTO el mismo patrón
`{i,j,edge}`/`edgeForCell` ya construido para `tobogan_edge`/
`tobogan_index`.

Pedido del usuario: la malla de seguridad (`place_nets`) se ponía en
TODAS las caras verticales de TODOS los niveles, sin excepción -"por
ahora en toda la cuadrícula, se quita a mano donde no haga falta"-,
pero eso no sirve para el paño exacto donde la gente entra caminando a
la estructura, en planta baja. El usuario pidió poder ELEGIR ese lugar
en el plugin, no quitar el paño a mano después en SketchUp.

- Checkbox `entrada` -solo visible/relevante si `net` está marcado,
  anidado justo debajo de él en `selector.html`, se auto-desmarca si
  `net` se desmarca-. Al activarse habilita el mismo click-picker de
  celda de orilla que el tobogán -`edgeForCell`, rechaza esquinas-,
  pero SIEMPRE en nivel 0 -no hay índice de nivel que elegir, a
  diferencia de nada más en el plugin-.
- `selectedEntradaCell` es un estado JS independiente de
  `selectedToboganCell`/`selectedTowerCell` -mismo shape `{i,j,edge}`-.
  `activePickTargets()`/`activePickTarget()` generalizados de 2 a 3
  posibles selecciones simultáneas -torre, tobogán, entrada-;
  `pickMode` ahora oculta las opciones de checkboxes inactivos
  -`opt.hidden`- en vez de ser un dropdown fijo de 2 valores.
- Payload: `entrada` (bool), `entrada_edge`, `entrada_index` -mismo
  significado que `tobogan_edge`/`tobogan_index`: index es la fila -edges
  X- o columna -edges Y- de la celda de orilla-.
- `main.rb#validate_dialog_data`: bloque `if params[:net] && data['entrada']
  == true` -mismas validaciones de edge/index válidos que el tobogán,
  mismo mensaje de error si no se eligió celda-. Guarda
  `params[:entrada] = {edge:, index:}`.
- `place_nets` recibe `params[:entrada]`, le agrega `x_boundary: nx,
  y_boundary: ny` -para no repetir `nx`/`ny` en cada llamada-, y usa
  `net_panel_is_entrada?(entrada, k, orientation, boundary_index,
  cell_index)` -función pura, sin dependencias de SketchUp, verificada
  con un script Ruby standalone antes de integrarla- para saltarse
  exactamente 1 paño vertical -el de la celda/orilla elegida- SOLO en
  `k == 0`. Los otros 2 loops de `place_nets` -paños perpendiculares a
  X y a Y- llaman `next if net_panel_is_entrada?(...)` justo antes de
  crear/instanciar el paño.
- **Solo existe en el diálogo MANUAL** -`selector.html`, que sí tiene
  vista previa/canvas para hacer clic-, NO en `automatico.html` -mismo
  precedente que el picker del tobogán, que tampoco vive ahí: sin
  canvas no hay dónde hacer clic, así que ese diálogo simplemente no
  ofrece la opción-.

### Bug real: activar "entrada" con torre ya activa movía la torre en vez de elegir la entrada

`updatePickModeVisibility()` solo reasigna `pickMode.value` cuando el
valor ACTUAL no está entre los targets activos -`!targets.includes(...)`-,
y como `activePickTargets()` empuja `'tower'` antes que `'entrada'`, el
fallback `targets[0]` siempre prefería la torre. Resultado real
reportado por el usuario: con "Agregar torre" ya activa, al marcar
"Definir entrada" el siguiente clic en la vista previa seguía
moviendo la torre -el dropdown `pickMode` quedaba en "Columna de la
torre" sin que el usuario lo notara-, y no había forma de elegir la
celda de la entrada. **Fix**: cada checkbox picker -`tower`, `tobogan`,
`entrada`- ahora fuerza `$('pickMode').value` a su propio valor al
activarse -`if($('tower').checked)$('pickMode').value='tower'`, etc.,
después de `updatePickModeVisibility()`-, así el ÚLTIMO picker que el
usuario acaba de marcar es siempre el que recibe el siguiente clic. El
dropdown `pickMode` sigue disponible para cambiar manualmente de
picker después, solo ya no arranca apuntando al equivocado.
