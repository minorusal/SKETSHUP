# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# VERSION DEL SCRIPT: v2 -largo de tubo calculado por pieza, no fijo- (2026-08-05)
#
# QUÉ ES ESTO
# -----------
# El primer intento (generar_torres_referencia.rb) dibujaba CAJAS -no se
# parecía en nada a la pieza real-. El segundo (copiar_grupo_referencia.rb)
# copiaba el grupo real, pero DEPENDE de que el original siga existiendo en
# el modelo -no prueba que se pueda construir desde cero-.
#
# Este es el paso intermedio entre los dos: construye los 4 diseños DESDE
# CERO -sin copiar nada, sin necesitar el original en el modelo- pero con
# GEOMETRÍA REAL -tubos huecos de verdad, conectores completos con
# receptores/tuercas/opresores, igual que arma el plugin de verdad-, en vez
# de cajas. La diferencia con llamar directo al plugin
# (constructor_modulos_playidea) es que este script usa los transforms
# EXACTOS ya verificados -origen + xaxis/yaxis/zaxis de cada una de las 19
# piezas, extraídos y comprobados número por número contra tus 4 diseños
# hechos a mano- en vez de recalcularlos con la lógica del plugin -así no
# depende de que el plugin instalado esté actualizado, ni de su fórmula de
# "near/far" o "capped/limpio"-.
#
# Si esto se ve idéntico a lo que construiste a mano, confirma que:
#   1. Los transforms guardados son correctos -ya lo sabíamos por número-.
#   2. Los mismos tubos/conectores REALES del catálogo -no cajas- calzan
#      bien con esos transforms -sin huecos, sin traslapes-.
# Eso deja MUY claro que cualquier diferencia que salga al correr
# constructor_modulos_playidea de verdad es un problema de SU lógica
# -cómo calcula esos transforms-, no de los transforms en sí.
#
# Requiere: conectores_playidea y creador_tubos_playidea instalados -NO
# requiere constructor_modulos_playidea, este script no lo usa-.
#
# CÓMO USARLO
# -----------
#   TorresDesdeCero.construir(1)      # solo el diseño 1
#   TorresDesdeCero.construir_todos   # los 4, en fila

module TorresDesdeCero
  extend self

  SEPARACION_X_MM = 4500.0
  OUTSIDE_MM = 38.1
  WALL_MM = 1.5
  COLOR_TUBO = 'Azul'

  DISENOS_REFERENCIA = {
    1 => [
      { nombre: "(sin nombre)", tipo: "Componente", min: [1274.1300, 1193.0700, 654.7390], max: [2323.1140, 2242.0540, 692.8390], origen: [1287.6010, 1206.5410, 673.7890], xaxis: [-0.7071, 0.7071, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [0.7071, 0.7071, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [1239.7870, 1145.9640, 630.4590], max: [1344.8980, 1265.2220, 717.1190], origen: [1273.9400, 1170.1140, 673.7890], xaxis: [-1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [-0.0000, -1.0000, -0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [2246.1940, 2161.7360, 630.4590], max: [2365.4520, 2266.8470, 717.1190], origen: [2341.3020, 2232.6940, 673.7890], xaxis: [0.0000, 1.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [1.0000, 0.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [2319.2140, 1196.1590, 654.4210], max: [2357.3140, 2316.2590, 692.5210], origen: [2338.2640, 2316.2590, 673.4710], xaxis: [1.0000, 0.0000, 0.0000], yaxis: [-0.0000, 0.0000, 1.0000], zaxis: [0.0000, -1.0000, 0.0000] },
      { nombre: "CON-10", tipo: "Componente", min: [2314.2880, 2264.6700, 642.4270], max: [2381.7680, 2362.7700, 705.9270], origen: [2338.4380, 2338.6200, 674.1770], xaxis: [0.0000, 0.0000, 1.0000], yaxis: [1.0000, 0.0000, 0.0000], zaxis: [0.0000, 1.0000, 0.0000] },
      { nombre: "CON-21", tipo: "Componente", min: [2249.7550, 1125.6750, 630.0550], max: [2361.5550, 1243.9550, 716.7150], origen: [2313.2550, 1193.1550, 673.3850], xaxis: [0.0000, -1.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [1.0000, 0.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1190.4300, 1150.8190, 654.4210], max: [2310.5300, 1188.9190, 692.5210], origen: [2310.5300, 1169.8690, 673.4710], xaxis: [0.0000, -1.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
      { nombre: "CON-10", tipo: "Componente", min: [1143.0640, 1126.0740, 642.4270], max: [1241.1640, 1193.5540, 705.9270], origen: [1167.2140, 1169.4040, 674.1770], xaxis: [0.0000, 0.0000, 1.0000], yaxis: [0.0000, -1.0000, 0.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1181.6840, 1265.5590, 1296.1220], max: [2230.6680, 2314.5430, 1334.2220], origen: [1195.1540, 1279.0300, 1315.1720], xaxis: [0.7071, -0.7071, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [0.7071, 0.7071, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [1134.5770, 1231.2160, 1271.8420], max: [1253.8360, 1336.3270, 1358.5020], origen: [1158.7270, 1265.3690, 1315.1720], xaxis: [0.0000, -1.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [2150.3500, 2237.6230, 1271.8420], max: [2255.4610, 2356.8810, 1358.5020], origen: [2221.3080, 2332.7310, 1315.1720], xaxis: [1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [0.0000, 1.0000, 0.0000] },
      { nombre: "CON-21", tipo: "Componente", min: [2249.7550, 1125.6750, 1830.0550], max: [2361.5550, 1243.9550, 1916.7150], origen: [2313.2550, 1193.1550, 1873.3850], xaxis: [0.0000, -1.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [1.0000, 0.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1274.1300, 1193.0700, 1854.7390], max: [2323.1140, 2242.0540, 1892.8390], origen: [1287.6010, 1206.5410, 1873.7890], xaxis: [-0.7071, 0.7071, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [0.7071, 0.7071, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [1239.7870, 1145.9640, 1830.4590], max: [1344.8980, 1265.2220, 1917.1190], origen: [1273.9400, 1170.1140, 1873.7890], xaxis: [-1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [-0.0000, -1.0000, -0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [2246.1940, 2161.7360, 1830.4590], max: [2365.4520, 2266.8470, 1917.1190], origen: [2341.3020, 2232.6940, 1873.7890], xaxis: [0.0000, 1.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [1.0000, 0.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [2319.2140, 1196.1590, 1854.4210], max: [2357.3140, 2316.2590, 1892.5210], origen: [2338.2640, 2316.2590, 1873.4710], xaxis: [1.0000, 0.0000, 0.0000], yaxis: [-0.0000, 0.0000, 1.0000], zaxis: [0.0000, -1.0000, 0.0000] },
      { nombre: "CON-10", tipo: "Componente", min: [2314.2880, 2264.6700, 1842.4270], max: [2381.7680, 2362.7700, 1905.9270], origen: [2338.4380, 2338.6200, 1874.1770], xaxis: [0.0000, 0.0000, 1.0000], yaxis: [1.0000, 0.0000, 0.0000], zaxis: [0.0000, 1.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1190.4300, 1150.8190, 1854.4210], max: [2310.5300, 1188.9190, 1892.5210], origen: [2310.5300, 1169.8690, 1873.4710], xaxis: [0.0000, -1.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
      { nombre: "CON-10", tipo: "Componente", min: [1143.0640, 1126.0740, 1842.4270], max: [1241.1640, 1193.5540, 1905.9270], origen: [1167.2140, 1169.4040, 1874.1770], xaxis: [0.0000, 0.0000, 1.0000], yaxis: [0.0000, -1.0000, 0.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
    ],
    2 => [
      { nombre: "(sin nombre)", tipo: "Componente", min: [1274.1300, 1193.0700, 654.7390], max: [2323.1140, 2242.0540, 692.8390], origen: [1287.6010, 1206.5410, 673.7890], xaxis: [-0.7071, 0.7071, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [0.7071, 0.7071, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [1239.7870, 1145.9640, 630.4590], max: [1344.8980, 1265.2220, 717.1190], origen: [1273.9400, 1170.1140, 673.7890], xaxis: [-1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [-0.0000, -1.0000, -0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [2246.1940, 2161.7360, 630.4590], max: [2365.4520, 2266.8470, 717.1190], origen: [2341.3020, 2232.6940, 673.7890], xaxis: [0.0000, 1.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [1.0000, 0.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [2319.2140, 1196.1590, 654.4210], max: [2357.3140, 2316.2590, 692.5210], origen: [2338.2640, 2316.2590, 673.4710], xaxis: [1.0000, 0.0000, 0.0000], yaxis: [-0.0000, 0.0000, 1.0000], zaxis: [0.0000, -1.0000, 0.0000] },
      { nombre: "CON-10", tipo: "Componente", min: [2314.2880, 2264.6700, 642.4270], max: [2381.7680, 2362.7700, 705.9270], origen: [2338.4380, 2338.6200, 674.1770], xaxis: [0.0000, 0.0000, 1.0000], yaxis: [1.0000, 0.0000, 0.0000], zaxis: [0.0000, 1.0000, 0.0000] },
      { nombre: "CON-21", tipo: "Componente", min: [2249.7550, 1125.6750, 630.0550], max: [2361.5550, 1243.9550, 716.7150], origen: [2313.2550, 1193.1550, 673.3850], xaxis: [0.0000, -1.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [1.0000, 0.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1190.4300, 1150.8190, 654.4210], max: [2310.5300, 1188.9190, 692.5210], origen: [2310.5300, 1169.8690, 673.4710], xaxis: [0.0000, -1.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
      { nombre: "CON-10", tipo: "Componente", min: [1143.0640, 1126.0740, 642.4270], max: [1241.1640, 1193.5540, 705.9270], origen: [1167.2140, 1169.4040, 674.1770], xaxis: [0.0000, 0.0000, 1.0000], yaxis: [0.0000, -1.0000, 0.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1181.6840, 1265.5590, 1296.1220], max: [2230.6680, 2314.5430, 1334.2220], origen: [1195.1540, 1279.0300, 1315.1720], xaxis: [0.7071, -0.7071, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [0.7071, 0.7071, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [1134.5770, 1231.2160, 1271.8420], max: [1253.8360, 1336.3270, 1358.5020], origen: [1158.7270, 1265.3690, 1315.1720], xaxis: [0.0000, -1.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [2150.3500, 2237.6230, 1271.8420], max: [2255.4610, 2356.8810, 1358.5020], origen: [2221.3080, 2332.7310, 1315.1720], xaxis: [1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [0.0000, 1.0000, 0.0000] },
      { nombre: "CON-21", tipo: "Componente", min: [2249.7550, 1125.6750, 1830.0550], max: [2361.5550, 1243.9550, 1916.7150], origen: [2313.2550, 1193.1550, 1873.3850], xaxis: [0.0000, -1.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [1.0000, 0.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1274.1300, 1193.0700, 1854.7390], max: [2323.1140, 2242.0540, 1892.8390], origen: [1287.6010, 1206.5410, 1873.7890], xaxis: [-0.7071, 0.7071, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [0.7071, 0.7071, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [1239.7870, 1145.9640, 1830.4590], max: [1344.8980, 1265.2220, 1917.1190], origen: [1273.9400, 1170.1140, 1873.7890], xaxis: [-1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [-0.0000, -1.0000, -0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [2246.1940, 2161.7360, 1830.4590], max: [2365.4520, 2266.8470, 1917.1190], origen: [2341.3020, 2232.6940, 1873.7890], xaxis: [0.0000, 1.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [1.0000, 0.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [2319.2140, 1196.1590, 1854.4210], max: [2357.3140, 2316.2590, 1892.5210], origen: [2338.2640, 2316.2590, 1873.4710], xaxis: [1.0000, 0.0000, 0.0000], yaxis: [-0.0000, 0.0000, 1.0000], zaxis: [0.0000, -1.0000, 0.0000] },
      { nombre: "CON-10", tipo: "Componente", min: [2314.2880, 2264.6700, 1842.4270], max: [2381.7680, 2362.7700, 1905.9270], origen: [2338.4380, 2338.6200, 1874.1770], xaxis: [0.0000, 0.0000, 1.0000], yaxis: [1.0000, 0.0000, 0.0000], zaxis: [0.0000, 1.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1190.4300, 1150.8190, 1854.4210], max: [2310.5300, 1188.9190, 1892.5210], origen: [2310.5300, 1169.8690, 1873.4710], xaxis: [0.0000, -1.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
      { nombre: "CON-10", tipo: "Componente", min: [1143.0640, 1126.0740, 1842.4270], max: [1241.1640, 1193.5540, 1905.9270], origen: [1167.2140, 1169.4040, 1874.1770], xaxis: [0.0000, 0.0000, 1.0000], yaxis: [0.0000, -1.0000, 0.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
    ],
    3 => [
      { nombre: "(sin nombre)", tipo: "Componente", min: [1275.9430, 1291.5380, 654.7390], max: [2294.2660, 2309.8600, 692.8390], origen: [2280.7950, 1305.0080, 673.7890], xaxis: [-0.7071, -0.7071, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [-0.7071, 0.7071, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [2239.3370, 1241.0560, 630.4590], max: [2358.5950, 1346.1680, 717.1190], origen: [2334.4450, 1275.2100, 673.7890], xaxis: [0.0000, -1.0000, 0.0000], yaxis: [0.0000, -0.0000, -1.0000], zaxis: [1.0000, 0.0000, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [1239.4590, 2240.4160, 630.4590], max: [1344.5700, 2359.6740, 717.1190], origen: [1273.6120, 2335.5240, 673.7890], xaxis: [-1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [0.0000, 1.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1189.5970, 2316.1360, 654.4210], max: [2309.6970, 2354.2360, 692.5210], origen: [1189.5970, 2335.1860, 673.4710], xaxis: [0.0000, 1.0000, 0.0000], yaxis: [-0.0000, 0.0000, 1.0000], zaxis: [1.0000, 0.0000, 0.0000] },
      { nombre: "CON-10", tipo: "Componente", min: [1143.5540, 2311.2100, 642.4270], max: [1241.6540, 2378.6900, 705.9270], origen: [1167.7040, 2335.3600, 674.1770], xaxis: [0.0000, 0.0000, 1.0000], yaxis: [0.0000, 1.0000, 0.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
      { nombre: "CON-21", tipo: "Componente", min: [2259.8670, 2249.3030, 630.0550], max: [2378.1470, 2361.1030, 716.7150], origen: [2310.6670, 2312.8030, 673.3850], xaxis: [1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [0.0000, 1.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [2315.6400, 1189.3490, 654.4210], max: [2353.7400, 2309.4490, 692.5210], origen: [2334.6900, 2309.4490, 673.4710], xaxis: [1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [0.0000, -1.0000, 0.0000] },
      { nombre: "CON-10", tipo: "Componente", min: [2311.0050, 1144.3330, 642.4270], max: [2378.4850, 1242.4330, 705.9270], origen: [2335.1550, 1168.4830, 674.1770], xaxis: [0.0000, 0.0000, 1.0000], yaxis: [1.0000, 0.0000, 0.0000], zaxis: [0.0000, -1.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1183.6810, 1192.3250, 1296.1220], max: [2232.6640, 2241.3080, 1334.2220], origen: [2219.1940, 1205.7950, 1315.1720], xaxis: [0.7071, 0.7071, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [-0.7071, 0.7071, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [2161.8960, 1145.2180, 1271.8420], max: [2267.0080, 1264.4760, 1358.5020], origen: [2232.8540, 1169.3680, 1315.1720], xaxis: [1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [0.0000, -1.0000, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [1141.3430, 2160.9910, 1271.8420], max: [1260.6010, 2266.1020, 1358.5020], origen: [1165.4930, 2231.9490, 1315.1720], xaxis: [0.0000, 1.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
      { nombre: "CON-21", tipo: "Componente", min: [2254.2690, 2242.5000, 1830.0550], max: [2372.5490, 2354.3000, 1916.7150], origen: [2305.0690, 2306.0000, 1873.3850], xaxis: [1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [0.0000, 1.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1256.1700, 1266.8750, 1854.7390], max: [2305.1530, 2315.8590, 1892.8390], origen: [2291.6830, 1280.3450, 1873.7890], xaxis: [-0.7071, -0.7071, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [-0.7071, 0.7071, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [2233.0020, 1240.6050, 1830.4590], max: [2352.2600, 1345.7160, 1917.1190], origen: [2328.1100, 1274.7580, 1873.7890], xaxis: [0.0000, -1.0000, 0.0000], yaxis: [0.0000, -0.0000, -1.0000], zaxis: [1.0000, 0.0000, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [1231.3760, 2238.9380, 1830.4590], max: [1336.4880, 2358.1970, 1917.1190], origen: [1265.5290, 2334.0470, 1873.7890], xaxis: [-1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [0.0000, 1.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1181.9650, 2311.9590, 1854.4210], max: [2302.0650, 2350.0590, 1892.5210], origen: [1181.9650, 2331.0090, 1873.4710], xaxis: [0.0000, 1.0000, 0.0000], yaxis: [-0.0000, 0.0000, 1.0000], zaxis: [1.0000, 0.0000, 0.0000] },
      { nombre: "CON-10", tipo: "Componente", min: [1135.4530, 2307.0330, 1842.4270], max: [1233.5530, 2374.5130, 1905.9270], origen: [1159.6030, 2331.1830, 1874.1770], xaxis: [0.0000, 0.0000, 1.0000], yaxis: [0.0000, 1.0000, 0.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [2309.3040, 1194.3760, 1854.8020], max: [2347.0230, 2303.2750, 1892.5210], origen: [2328.1640, 2303.2750, 1873.6610], xaxis: [1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [0.0000, -1.0000, 0.0000] },
      { nombre: "CON-10", tipo: "Componente", min: [2304.6690, 1146.4550, 1842.4270], max: [2372.1490, 1244.5550, 1905.9270], origen: [2328.8190, 1170.6050, 1874.1770], xaxis: [0.0000, 0.0000, 1.0000], yaxis: [1.0000, 0.0000, 0.0000], zaxis: [0.0000, -1.0000, 0.0000] },
    ],
    4 => [
      { nombre: "(sin nombre)", tipo: "Componente", min: [1208.7470, 1197.7030, 654.7390], max: [2227.0690, 2216.0250, 692.8390], origen: [1222.2170, 2202.5550, 673.7890], xaxis: [0.7071, 0.7071, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [0.7071, -0.7071, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [1144.4170, 2161.3950, 630.4590], max: [1263.6750, 2266.5060, 717.1190], origen: [1168.5670, 2232.3530, 673.7890], xaxis: [0.0000, 1.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [2158.4420, 1147.8890, 630.4590], max: [2263.5540, 1267.1470, 717.1190], origen: [2229.4010, 1172.0390, 673.7890], xaxis: [1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [0.0000, -1.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1193.3160, 1153.3260, 654.4210], max: [2313.4160, 1191.4260, 692.5210], origen: [2313.4160, 1172.3760, 673.4710], xaxis: [0.0000, -1.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
      { nombre: "CON-10", tipo: "Componente", min: [2261.3580, 1128.8720, 642.4270], max: [2359.4580, 1196.3520, 705.9270], origen: [2335.3080, 1172.2020, 674.1770], xaxis: [0.0000, 0.0000, 1.0000], yaxis: [0.0000, -1.0000, 0.0000], zaxis: [1.0000, 0.0000, 0.0000] },
      { nombre: "CON-21", tipo: "Componente", min: [1124.8660, 1146.4600, 630.0550], max: [1243.1460, 1258.2600, 716.7150], origen: [1192.3460, 1194.7600, 673.3850], xaxis: [-1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [0.0000, -1.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1149.2730, 1198.1140, 654.4210], max: [1187.3730, 2318.2140, 692.5210], origen: [1168.3230, 1198.1140, 673.4710], xaxis: [-1.0000, 0.0000, 0.0000], yaxis: [0.0000, -0.0000, 1.0000], zaxis: [0.0000, 1.0000, 0.0000] },
      { nombre: "CON-10", tipo: "Componente", min: [1124.5280, 2265.1290, 642.4270], max: [1192.0080, 2363.2290, 705.9270], origen: [1167.8580, 2339.0790, 674.1770], xaxis: [0.0000, 0.0000, 1.0000], yaxis: [-1.0000, 0.0000, 0.0000], zaxis: [0.0000, 1.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1255.2630, 1256.3420, 1296.1220], max: [2304.2470, 2305.3260, 1334.2220], origen: [1268.7340, 2291.8560, 1315.1720], xaxis: [-0.7071, -0.7071, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [0.7071, -0.7071, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [1220.9200, 2233.1740, 1271.8420], max: [1326.0310, 2352.4320, 1358.5020], origen: [1255.0730, 2328.2820, 1315.1720], xaxis: [-1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [0.0000, 1.0000, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [2227.3260, 1231.5490, 1271.8420], max: [2346.5850, 1336.6600, 1358.5020], origen: [2322.4350, 1265.7020, 1315.1720], xaxis: [0.0000, -1.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [1.0000, 0.0000, 0.0000] },
      { nombre: "CON-21", tipo: "Componente", min: [1124.8780, 1143.9350, 1830.0550], max: [1243.1580, 1255.7350, 1916.7150], origen: [1192.3580, 1192.2350, 1873.3850], xaxis: [-1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [0.0000, -1.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1192.2730, 1182.3770, 1854.7390], max: [2241.2570, 2231.3600, 1892.8390], origen: [1205.7440, 2217.8900, 1873.7890], xaxis: [0.7071, 0.7071, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [0.7071, -0.7071, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [1145.1670, 2161.3240, 1830.4590], max: [1264.4250, 2266.4360, 1917.1190], origen: [1169.3170, 2232.2830, 1873.7890], xaxis: [0.0000, 1.0000, 0.0000], yaxis: [0.0000, 0.0000, -1.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
      { nombre: "CON-12", tipo: "Componente", min: [2160.9390, 1140.0390, 1830.4590], max: [2266.0500, 1259.2970, 1917.1190], origen: [2231.8970, 1164.1890, 1873.7890], xaxis: [1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [0.0000, -1.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1195.3620, 1148.1770, 1854.4210], max: [2315.4620, 1186.2770, 1892.5210], origen: [2315.4620, 1167.2270, 1873.4710], xaxis: [0.0000, -1.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [-1.0000, 0.0000, 0.0000] },
      { nombre: "CON-10", tipo: "Componente", min: [2263.8730, 1123.7230, 1842.4270], max: [2361.9730, 1191.2030, 1905.9270], origen: [2337.8230, 1167.0530, 1874.1770], xaxis: [0.0000, 0.0000, 1.0000], yaxis: [0.0000, -1.0000, 0.0000], zaxis: [1.0000, 0.0000, 0.0000] },
      { nombre: "(sin nombre)", tipo: "Componente", min: [1150.4030, 1194.9610, 1854.8020], max: [1188.1220, 2303.8600, 1892.5210], origen: [1169.2630, 1194.9610, 1873.6610], xaxis: [-1.0000, 0.0000, 0.0000], yaxis: [0.0000, 0.0000, 1.0000], zaxis: [0.0000, 1.0000, 0.0000] },
      { nombre: "CON-10", tipo: "Componente", min: [1125.2770, 2262.4850, 1842.4270], max: [1192.7570, 2360.5850, 1905.9270], origen: [1168.6070, 2336.4350, 1874.1770], xaxis: [0.0000, 0.0000, 1.0000], yaxis: [-1.0000, 0.0000, 0.0000], zaxis: [0.0000, 1.0000, 0.0000] },
    ],
  }.freeze

  def dependencias_ok?
    defined?(PlayIdea::Conectores) && defined?(PlayIdea::CreadorTubos) &&
      PlayIdea::Conectores.respond_to?(:build_connector_geometry) &&
      PlayIdea::CreadorTubos.respond_to?(:add_hollow_geometry)
  end

  def crear_definicion_tubo(model, largo_mm, nombre)
    definicion = model.definitions.add(unique_name(model, nombre))
    params = {
      length_mm: largo_mm,
      outside_mm: OUTSIDE_MM,
      inside_mm: OUTSIDE_MM - (2.0 * WALL_MM)
    }
    PlayIdea::CreadorTubos.add_hollow_geometry(definicion.entities, params)
    PlayIdea::CreadorTubos.apply_material(model, definicion, COLOR_TUBO)
    definicion
  end

  def crear_definicion_conector(model, codigo, nombre, material, hardware)
    definicion = model.definitions.add(unique_name(model, nombre))
    PlayIdea::Conectores.build_connector_geometry(definicion.entities, codigo, material, hardware)
    definicion
  end

  def unique_name(model, base)
    return base unless model.definitions[base]
    n = 2
    n += 1 while model.definitions["#{base}-#{n}"]
    "#{base}-#{n}"
  end

  # Largo REAL del tubo, calculado por pieza -no un número fijo copiado de
  # un solo ejemplo-. Se proyectan las 8 esquinas de su caja LOCAL sobre
  # sus propios ejes -los mismos xaxis/yaxis/zaxis ya extraídos y
  # verificados-, y el rango más grande de los 3 ejes propios ES el largo
  # -sin importar en qué ángulo esté parado el tubo, ni si su origen queda
  # en una punta o al centro-. Antes se usaba un largo fijo -1618.6mm,
  # leído de un solo diseño- para TODOS los tubos diagonales de los 4
  # diseños; como la distancia real entre conectores varía un poco de un
  # diseño a otro -imprecisión normal de construir a mano-, ese largo fijo
  # se pasaba de largo en algunos casos y el tubo atravesaba el conector.
  def largo_tubo_real(pieza)
    ox, oy, oz = pieza[:origen]
    xa, ya, za = pieza[:xaxis], pieza[:yaxis], pieza[:zaxis]
    mn, mx = pieza[:min], pieza[:max]
    esquinas = [
      [mn[0], mn[1], mn[2]], [mx[0], mn[1], mn[2]], [mn[0], mx[1], mn[2]], [mn[0], mn[1], mx[2]],
      [mx[0], mx[1], mn[2]], [mx[0], mn[1], mx[2]], [mn[0], mx[1], mx[2]], [mx[0], mx[1], mx[2]]
    ]
    rangos = [xa, ya, za].map do |eje|
      proyecciones = esquinas.map do |ex, ey, ez|
        (ex - ox) * eje[0] + (ey - oy) * eje[1] + (ez - oz) * eje[2]
      end
      proyecciones.max - proyecciones.min
    end
    rangos.max
  end

  def definicion_tubo_para(model, largo_mm)
    @tubos ||= {}
    clave = largo_mm.round(2)
    @tubos[clave] ||= crear_definicion_tubo(model, clave, "TUB-REF-#{clave}")
  end

  def definiciones_conectores(model)
    return @conectores if @conectores

    material = PlayIdea::Conectores.connector_material(model, 'Galvanizado')
    hardware = PlayIdea::Conectores.hardware_material(model)
    @conectores = {
      'CON-12' => crear_definicion_conector(model, '12', 'CON-REF-12', material, hardware),
      'CON-21' => crear_definicion_conector(model, '21', 'CON-REF-21', material, hardware),
      'CON-10' => crear_definicion_conector(model, '10', 'CON-REF-10', material, hardware)
    }
  end

  def esquina_minima(piezas)
    xs = piezas.flat_map { |p| [p[:min][0], p[:max][0]] }
    ys = piezas.flat_map { |p| [p[:min][1], p[:max][1]] }
    zs = piezas.flat_map { |p| [p[:min][2], p[:max][2]] }
    [xs.min, ys.min, zs.min]
  end

  def construir(numero_diseno)
    piezas = DISENOS_REFERENCIA[numero_diseno]
    raise "No existe el diseño #{numero_diseno} -usa 1, 2, 3 o 4." unless piezas

    model = Sketchup.active_model
    conectores = definiciones_conectores(model)

    model.start_operation("Torre desde cero, diseño #{numero_diseno}", true)
    container = model.active_entities.add_group
    container.name = "DESDE-CERO-DISEÑO-#{numero_diseno}"
    entities = container.entities

    offset = esquina_minima(piezas)
    piezas.each do |pieza|
      origen_norm = [
        (pieza[:origen][0] - offset[0]).mm,
        (pieza[:origen][1] - offset[1]).mm,
        (pieza[:origen][2] - offset[2]).mm
      ]
      punto = Geom::Point3d.new(*origen_norm)
      transform = Geom::Transformation.axes(
        punto,
        Geom::Vector3d.new(*pieza[:xaxis]),
        Geom::Vector3d.new(*pieza[:yaxis]),
        Geom::Vector3d.new(*pieza[:zaxis])
      )

      definicion =
        if %w[CON-12 CON-21 CON-10].include?(pieza[:nombre])
          conectores[pieza[:nombre]]
        else
          definicion_tubo_para(model, largo_tubo_real(pieza))
        end

      instancia = entities.add_instance(definicion, transform)
      instancia.name = pieza[:nombre] == '(sin nombre)' ? 'TUBO' : pieza[:nombre]
    end

    desplazamiento_x = (numero_diseno - 1) * SEPARACION_X_MM
    container.transformation = Geom::Transformation.translation(Geom::Point3d.new(desplazamiento_x.mm, 0, 0))

    model.selection.add(container)
    model.commit_operation
    puts "✅ DESDE-CERO-DISEÑO-#{numero_diseno}: #{piezas.length} piezas con geometría real -0 cajas-."
    container
  end

  def construir_todos
    unless dependencias_ok?
      UI.messagebox('Necesitas conectores_playidea y creador_tubos_playidea instalados -y SketchUp reiniciado después de instalarlos- para correr esto.')
      return
    end
    model = Sketchup.active_model
    model.selection.clear
    (1..4).each { |n| construir(n) }
    model.active_view.zoom(model.selection.to_a)
    puts "✅ Los 4 diseños creados DESDE CERO -sin copiar nada, geometría real-, en fila cada #{SEPARACION_X_MM}mm."
  end
end

TorresDesdeCero.construir_todos
nil
