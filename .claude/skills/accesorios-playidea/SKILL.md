---
name: accesorios-playidea
description: Contexto y convenciones para los scripts sueltos de "accesorios" de juegos infantiles (costales/rodillos, y los que sigan — gato, zapateras, etc.) en scripts/, independientes del sistema de tobogán/estructura modular. Úsala siempre que se cree o edite un accesorio nuevo en scripts/*_playidea.rb que no sea parte de constructor_modulos_playidea ni del tobogán.
---

# Accesorios sueltos — costales, y los que sigan

## Qué es esto y dónde vive

Serie de scripts SUELTOS (no plugins `.rbz`, no viven dentro de
`constructor_modulos_playidea/`) que arman accesorios individuales de
juego -piezas que no son parte de la cuadrícula/estructura ni del
tobogán-. Mismo flujo de trabajo que los scripts sueltos del tobogán
-ver skill `tobogan-completo-playidea`, sección "Antes de experimentar
con un brazo nuevo"-: se cargan con
`load '/Users/minorusal/Documents/SKETCHUP/scripts/<archivo>.rb'` en la
Consola de Ruby de SketchUp, cada `load` re-ejecuta el archivo completo
y coloca la herramienta de inmediato.

Primer pedido del usuario -2026-08-11-: "es momento de comenzar a
hacer los scripts que construyan todos los accesorios, vamos con
costales". Costales es el PRIMERO; se espera que sigan más -el usuario
ya mencionó antes "gato"/"zapateras" en el pedido #13 sin construir
todavía, ver `reference_play_idea_explorer_pricing_catalog` en
memoria-.

## `costal_playidea.rb` — rodillo/costal de gimnasia, liso o caramelo

Rodillo cilíndrico relleno de foam, construido como un tubo de lona
(vinil) cosido, con una base permanente en un extremo y una tapa
desmontable -pegada con Plastigón- en el otro, para poder rellenarlo y
volver a cerrarlo. 2 variantes: liso -un solo color- y caramelo
-cintas diagonales de otro color, tipo dulce de bastón-. `start` coloca
LAS 2 variantes de una vez, lado a lado, con un solo clic -mismo
patrón que `VARIANT_SPACING_MM` en
`tobogan_variedades_altura_playidea.rb`- para comparar acabados sin
tener que correr el script 2 veces.

### Medidas: cuáles vienen del usuario y cuáles son supuestos

- `CYLINDER_DIAMETER_MM` = 12" (304.8mm) — dato DIRECTO del usuario, no
  derivado de nada.
- `CYLINDER_LENGTH_MM` = 36" (914.4mm) — la lona real mide 44"x36", el
  usuario NO dijo cuál lado es cuál. SUPUESTO: el lado de 36" es el
  LARGO del cilindro, porque encaja EXACTO con 36 discos de foam de 1"
  -`FOAM_DISC_COUNT = (CYLINDER_LENGTH_MM / FOAM_DISC_THICKNESS_MM).round`
  da 36.0 limpio, demasiado exacto para ser casualidad-, y el lado de
  44" envuelve la circunferencia con margen de costura -12" de diámetro
  da ~37.7" de circunferencia teórica (π×12), los ~6.3" extra son
  costura/traslape del cilindro-. Si el usuario dice que está al
  revés al verlo, son solo 2 constantes que voltear
  (`LONA_WIDTH_IN`/`LONA_LENGTH_IN`).
- `CYLINDER_WALL_MM`, `BASE_THICKNESS_MM`, `TAPA_THICKNESS_MM`,
  `CINTA_WIDTH_MM`, `CINTA_HEIGHT_MM` — PROVISIONALES, sin medida real
  del usuario, mismo patrón que `CORNER_CHAMFER_MM` en
  `plataforma_playidea.rb`: ajustar la constante y volver a `load` para
  iterar rápido una vez que el usuario vea la pieza.
- Cintas "caramelo": `CANDY_STRIPE_COUNT=6`, ancho angular = medio hueco
  entre cintas -~50% de cobertura, look clásico de barbería-,
  `CANDY_TURNS=1.0` -da ~45° de diagonal para estas proporciones-. Todo
  PROVISIONAL, sin referencia visual real todavía.

### Construcción: pared hueca SIEMPRE por `add_wall`/`add_ring`, nunca por 2 círculos concéntricos con hueco automático

Intento inicial (descartado antes de mostrárselo al usuario): confiar
en que SketchUp detecta solo un hueco cuando dibujas 2 círculos
coplanares concéntricos (`entities.add_circle` 2 veces + 1 `pushpull`
del anillo resultante). Se revisó `tobogan_recto_playidea.rb` -pieza YA
validada visualmente por el usuario- y ESA pieza NO usa ese truco: usa
`circle_points`/`add_wall` (2 paredes cilíndricas explícitas, exterior
e interior, por gajos) + `add_ring` (anillo plano explícito, también
por gajos) para cerrar los extremos abiertos. `costal_playidea.rb`
reescribió `build_tube_shell`/`build_cinta_ring` para copiar EXACTO ese
patrón -mismos nombres de función- en vez de arriesgar el truco no
probado. Los discos macizos SÍ pueden seguir usando
`entities.add_circle` + `pushpull` de un solo círculo -sin hueco
anidado-, porque ESE patrón sí está probado en el proyecto
(`net_add_rod` en `constructor_modulos_playidea/main.rb`,
`plataforma_playidea.rb`).

### Bug real encontrado y corregido antes de pasarlo al usuario: puntos sin `.mm`

`build_cap` y `build_foam_stack` construían su `Geom::Point3d` central
con la coordenada Z en milímetros CRUDOS -`z_mm`, un Float normal- en
vez de convertirla con `.mm` -que SketchUp necesita para pasar de mm a
su unidad interna, pulgadas-. Sin `.mm`, un valor como `914.4` se
interpreta como 914.4 PULGADAS, ~25x más grande de lo esperado. Se
encontró ANTES de que el usuario lo viera, con un harness de Ruby
puro -mismo patrón de mocks de SketchUp usado varias veces esta
sesión, ver `tobogan-completo-playidea`- que carga el archivo real,
llama cada `build_*` con un `Numeric#mm` mock que sí distingue mm de
pulgadas (`self / 25.4`), y revisa que ningún punto generado se salga
de la caja delimitadora esperada de la pieza. **Si se agrega geometría
nueva a este archivo -o a cualquier accesorio nuevo-, correr ese mismo
tipo de harness antes de pedirle al usuario que lo cargue en
SketchUp**, no confiar solo en `ruby -c` -eso solo revisa sintaxis, no
que las unidades cuadren-.

### Relleno: mismo material "Polyfon" que ya se usa para recubrir tubos

"el polyfoam es de 1"" del usuario -grosor del relleno- es el MISMO
material "Polyfon" ya dado de alta en la API de play-idea-explorer
-ver `reference_play_idea_explorer_pricing_catalog` en memoria-, el
mismo que ya usa `constructor_modulos_playidea` para el recubrimiento
de tubos -ahí se usa enrollado como manguera; aquí se corta en discos
planos, mismo material, otro corte-. Entrada más reciente/vigente en la
API: id 82 "Rollo De Polyfon De Pulg", $6,200/rollo, fecha
2026-06-03 -hay varias entradas duplicadas más viejas con precios
distintos, ids 581/1100/1371, usar la más reciente al conectar con el
cotizador-.

### Pendiente -explícitamente pospuesto por el usuario-

"después vemos que se conecte al cotizador" — el costal TODAVÍA no
tiene `CODE` reconocido por `cotizador_playidea` -sí tiene
`CODE_LISO`/`CODE_CARAMELO` como nombre de instancia, listo para
cuando se conecte, mismo patrón `instance.name = CODE` ya establecido,
ver "Cotizador: cuenta piezas por NOMBRE" en `tobogan-completo-
playidea`-, ni entrada en la API de productos/tarifas -el hilo Domino,
el Plastigón y el Polyfon YA tienen factura real capturada en el
pedido del usuario, faltan darlos de alta como materiales/tarifas
cuando se haga esa conexión-.

Tampoco está resuelto CÓMO se monta el costal en una estructura real
-en la pieza actual el eje largo queda vertical, orientación por
default sin significado físico real; un costal/rodillo normalmente
cuelga u obstruye HORIZONTAL, atravesado por un poste-. Eso se deja
para cuando se integre a una estructura, mismo orden de trabajo que se
siguió con el tobogán -primero la pieza sola, luego la integración-.

### Bug real -reportado por el usuario al probarlo en SketchUp-: `ArgumentError: Points are not planar`

`build_stripe_ribbons` armaba cada segmento de la cinta caramelo como
UN cuadrángulo -`add_face(edge_a[j], edge_b[j], edge_b[j+1], edge_a[j+1])`-,
asumiendo que era plano igual que los cuadrángulos de `add_wall`/
`add_ring`. La diferencia real: en `add_wall` los 4 puntos de cada
cuadrángulo forman un PARALELOGRAMO exacto -2 puntos comparten X,Y
-mismo ángulo-, solo cambia Z-, así que siempre son coplanares sin
importar la curvatura. En la cinta caramelo, en cambio, el ángulo
CAMBIA entre `j` y `j+1` -por el giro de la hélice, `theta_center`
avanza con `frac`-, así que las 2 orillas de la cinta -`edge_a`/
`edge_b`- quedan torcidas entre un segmento y el siguiente: los 4
puntos ya NO son coplanares, y SketchUp lo rechaza con
`ArgumentError: Points are not planar` -no es un error silencioso, sí
truena, y sí llegó hasta el usuario porque el mock harness de la
sesión anterior no valida planaridad de verdad, solo rango de
coordenadas-. **Fix**: partir cada segmento en 2 TRIÁNGULOS en vez de 1
cuadrángulo -un triángulo siempre es plano por definición, sin
importar el giro-. Cualquier geometría nueva que conecte puntos de 2
"orillas" que roten entre sí -hélices, cintas diagonales, lo que sea
con un giro progresivo- debe triangular desde el principio, NO asumir
que un cuadrángulo funciona solo porque funcionó en `add_wall`/
`add_ring` -esos son casos especiales sin giro-.

**Nota para la próxima vez**: el harness de mocks de Ruby puro -ver la
sección de arriba sobre el bug de `.mm`- NO detecta este tipo de
problema porque `MockFace`/`add_face` no valida planaridad real, solo
cuenta puntos. Sirve para bugs de unidades/rango, NO para bugs de
geometría 3D como este. Para geometría con giro/torsión, triangular
por default en vez de confiar en que el mock "pasó".

### Corrección real del usuario: cintas caramelo no se veían -mismo nivel del vinil- y ancho debía ser 6"/6" exactas

2 pedidos concretos tras ver la primera versión en SketchUp:
1. "parece que esta al mismo nivel que el vinil del cilindro" -con
   `CANDY_STRIPE_RAISE_MM=1.0` la cinta no se despegaba lo suficiente de
   la pared de abajo para leerse como una pieza aparte por encima-.
   Subido a `4.0`.
2. "esas cintas son de 6 pulgadas y... deben tener esa misma
   separación para que se vea 6 pulg de cinta y 6 pulg de cilindro,
   etc" — dato DIRECTO, no un conteo arbitrario de cintas. Esto
   obligó a rediseñar `build_stripe_ribbons` por completo: en vez de
   generar N cintas discretas -conteo fijo, ancho angular derivado del
   conteo-, ahora subdivide TODA la superficie en una cuadrícula
   `SEGMENTS x SEGMENTS` de gajos SIN giro entre extremos -mismo
   cuadrángulo que `add_wall`, mismo argumento de paralelogramo, así
   que sigue sin riesgo de "Points are not planar"- y pinta cada gajo
   solo si su centro cae dentro de una franja de cinta, decidido por
   `in_candy_stripe?(theta, z_mm)`: "desenrolla" la hélice -convierte
   la posición angular en el desplazamiento de Z equivalente que
   tendría si el cilindro se aplanara- y alterna cinta/hueco cada
   `CANDY_STRIPE_WIDTH_MM` -6"- sobre esa coordenada combinada. Con
   `CANDY_TURNS=1.0` el patrón cierra EXACTO sin costura visible al dar
   la vuelta completa -36"/6"=6 franjas por vuelta, verificado
   numéricamente: cobertura ~50%, transición cada 6.0-6.02" al viajar
   por Z a ángulo fijo, y el mismo estado de cinta/hueco en θ=0 y
   θ≈2π-. Verificación hecha en Ruby puro -sin SketchUp- ANTES de
   pasarle el archivo al usuario, mismo patrón que el resto de esta
   skill.

### 3 correcciones más del usuario, todas aplicadas y verificadas con el mismo harness de mocks

1. **"las cintas son rectas y les pone picos en las orillas"**: la
   cuadrícula fija -pintar sí/no por celda- de la primera versión de
   `build_stripe_ribbons` aproximaba la frontera diagonal real -que
   matemáticamente es una línea recta en el plano "desenrollado"
   ángulo/Z- con escalones, visibles como dientes de sierra. Reescrito
   para calcular la frontera con la fórmula EXACTA por cada `k` -franja
   posible, puede haber varias por el traslape de la hélice, algunas
   totalmente fuera de rango y no dibujan nada- y muestrear fino en
   ángulo -`theta_steps = SEGMENTS*2`-, triangulando siempre -no un solo
   cuadrángulo- por la misma razón de planaridad ya documentada arriba.
2. **"las cintas son de 10 pulgadas, no de 6, ahí me equivoqué yo"**:
   corrección del propio usuario sobre un dato que él mismo había dado
   antes. Con 10" el largo del tubo -914.4mm- ya NO cabe un número
   entero de períodos -914.4/508=1.8, antes con 6" cabían 3 exactos-,
   así que el patrón se recorta en vez de cerrar "parejo"; el diseño
   basado en `k`+recorte al rango real ya lo soporta sin cambios
   adicionales.
3. **"la tapa es como la tapa de un bote, solo que sin rosca"**: la
   tapa desmontable -lado pegado con Plastigón- ya NO es un disco liso
   igual que la base -eso quedó solo para la base cosida-. Ahora es un
   perfil de tapa-de-cubeta: `build_tapa_lid` arma un faldón
   -`add_wall`, un solo tramo- que se resbala por FUERA del cuerpo del
   tubo -`TAPA_OUTER_R_MM = CYLINDER_RADIUS_MM + TAPA_CLEARANCE_MM`,
   más ancho para "embonar"- y arriba un disco plano que la cierra
   -`build_annulus_slab`-. La cinta cosida al perímetro ahora envuelve
   la orilla REAL de la tapa -`TAPA_OUTER_R_MM`-, no el radio del
   cuerpo.

### Perforación central para el poste de estructura

"además a estos rodillos necesito que en el centro les pongas una
perforación vertical para que entre justo un tubo de estructura" —
confirma la sospecha ya apuntada en la sección "Pendiente" de arriba
-el costal se monta atravesado en un poste-. `POST_HOLE_RADIUS_MM` usa
el mismo diámetro que `STRUCTURAL_OUTSIDE_MM` -38.1mm- en
`constructor_modulos_playidea/main.rb` -el tubo estructural estándar de
esta línea, encontrado por búsqueda directa en ese archivo, no
inventado- más una holgura chica. Como la base, cada disco de foam Y el
disco de arriba de la tapa antes eran discos MACIZOS -círculo simple +
pushpull, ver la sección de arriba sobre qué truco de círculo SÍ está
probado en este proyecto-, hubo que rediseñarlos TAMBIÉN como
"rondanas gruesas" -`build_annulus_slab`, mismo patrón de 2
`add_wall`+2 `add_ring` que ya usa `build_tube_shell`- para dejar un
hueco pasante real, no solo cosmético, de un extremo al otro del
costal. El faldón de la tapa NO necesita hueco -está muy por fuera del
radio del poste, no lo toca-.

**Nota de rendimiento, no confirmada, vigilar**: con 36 discos de foam
+ base + tapa como "rondanas" -cada una son 2 paredes + 2 anillos, no
un solo círculo+pushpull barato- la geometría por costal creció
bastante -~15,000 puntos generados en el harness de mocks, antes
~800-. Si el usuario reporta que tarda mucho en crear el costal en
SketchUp real, la salida ya usada en otras piezas de este proyecto
-tornillería- es cachear UN disco perforado como definición de
componente y usarlo como instancia 36 veces, en vez de geometría suelta
repetida.

### Corrección: NO es tubo estructural metálico, es PVC de 2 1/2" -y le faltaba detalle de costuras

- "no un tubo de estructura debe de pasar un pvc que es de 2 1/2
  pulgadas": `POST_HOLE_RADIUS_MM` ya NO usa `STRUCTURAL_OUTSIDE_MM`
  -38.1mm, tubo metálico-, usa el diámetro EXTERIOR real de PVC cédula
  40 para la nominal 2 1/2" -`PVC_POST_OUTSIDE_MM = 73.03` (2.875"),
  SUPUESTO explícito: el usuario dio la medida NOMINAL de plomería, que
  siempre es MENOR que el diámetro exterior real -convención estándar
  de tubería PVC, muy distinta de un tubo metálico donde "2 1/2" sí
  sería literal-. Si el PVC real que usan mide otra cosa, avisar.
- "la tapa sigue viéndose igual de fea, estaría bien más detalle de las
  costuras y detalles apegados a la realidad no tan recto todo": se
  agregaron 2 helpers nuevos -`build_stitch_ring`/
  `build_stitch_line_straight`- que dibujan la costura como una fila de
  "cuentas" cortas CON HUECOS entre ellas -imitando puntadas de máquina
  de coser real, no una línea lisa continua-, apenas levantadas de la
  superficie. Se llaman en 4 lugares de `build_costal`: unión
  base-cuerpo -anillo en z=0-, costura larga del enrollado de la lona
  -línea recta a lo largo del cuerpo, a un ángulo fijo, representa
  dónde se cosió la lona para formar el cilindro-, e hilo de la cinta
  cosida a la tapa -2 anillos, borde interior y exterior de la cinta-.
  Deliberadamente NO hay costura en la unión cuerpo-tapa -ese lado va
  PEGADO con Plastigón, no cosido, sería incorrecto ponerle hilo ahí-.
  Ambos helpers reutilizan el mismo cuadrángulo-siempre-plano de
  `add_wall` -2 puntos comparten Z o comparten un desplazamiento
  tangencial FIJO, nunca rotan dentro del mismo cuadrángulo-, así que
  siguen sin riesgo de "Points are not planar".
- Sigue pendiente si "no tan recto todo" pide algo más allá de las
  costuras -ej. que la lona misma no se vea perfectamente cilíndrica,
  con arrugas/pandeo típico de tela real-; eso es mucho más caro de
  modelar -deformación con ruido, no solo geometría analítica- y no se
  intentó todavía, a propósito, para no meter una técnica nueva sin
  verificar en la misma pasada que ya trae 3 correcciones.

### 3 correcciones más -PVC visible, tapa REAL de taparrosca, bastilla de las cintas caramelo

1. **"te faltó poner el tubo PVC"**: el hueco central ya existía -ver
   arriba-, pero nunca se dibujó el PVC de verdad pasando por ahí.
   `build_pvc_post` -varilla sólida simplificada, no hueca- ahora
   atraviesa TODO el costal por el centro, asomando
   `PVC_VISIBLE_OVERHANG_MM` de cada lado -PROVISIONAL, solo para que
   se note que atraviesa; en una instalación real seguiría hacia los
   postes de la estructura-.
2. **"la tapa sigue viéndose igual de fea... imagínate un bote de
   plástico con su tapa sin rosca... entra a la punta de la botella sin
   roscar solo con presión"**: la corrección ANTERIOR -faldón + disco
   plano arriba- tampoco era correcta: un disco plano con esquina viva
   no se ve como una taparrosca real. Rediseño completo de
   `build_tapa_lid`: faldón de PARED DOBLE -grosor real de plástico,
   `add_wall` por fuera Y por dentro, no una lámina de una sola cara- +
   un domo POCO PROFUNDO y REDONDEADO arriba -`build_tapa_dome`, mismo
   truco de perfil de cuarto de círculo que `add_dome` en
   `tornilleria_playidea.rb`, ya probado ahí para cabezas de tornillo y
   tapa bellota-. Diferencia clave con un bolt normal: el domo de la
   tapa NO cierra en punta -tiene que dejar pasar el PVC-, así que
   `build_tapa_dome` recibe un `hole_r_mm` y el perfil se DETIENE ahí
   -`Math.acos(hole_r_mm/base_r_mm)` da el ángulo exacto donde cortar-,
   en vez de barrer todo el cuarto de círculo hasta radio 0. Se agregó
   `add_cone_wall` -pared con radio DISTINTO en cada extremo, a
   diferencia de `add_wall`- para el perfil del domo, SIEMPRE
   triangulado -mismo motivo que las cintas caramelo: con radios
   distintos el cuadrángulo ya no es exactamente plano-.
3. **"también las franjas de caramelo deben tener costura porque son
   con bastilla"**: `build_stripe_stitches` recorre las MISMAS franjas
   -mismos `k`, mismo muestreo en ángulo- que `build_stripe_ribbons`,
   pero en vez de pintar la superficie completa solo deja una hilera de
   cuentas -mismo patrón que `build_stitch_ring`- en cada orilla -z_lo
   y z_hi- de cada franja visible.

Las 3 correcciones se verificaron con el harness de mocks antes de
mandarlas -incluyendo una prueba nueva específica: que el domo de la
tapa NO tape el hueco del poste, comparando el radio mínimo generado
contra `POST_HOLE_RADIUS_MM`-.

**Pendiente de aclarar, no asumido**: la tapa ahora se describe/luce
como plástico rígido -taparrosca real-, pero sigue usando el color de
la LONA -`params[:lona_hex]`- y todavía tiene una cinta de tela cosida
alrededor -`build_cinta_ring`/costuras-, herencia del diseño anterior
donde la tapa era de vinil. Si el usuario confirma que ahora es
plástico rígido de verdad -no vinil-, la cinta+costura de la tapa ya
no tendría sentido físico y habría que quitarlas.
