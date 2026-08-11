# Pega este script completo en Ventana > Consola de Ruby de SketchUp.
#
# VERSION DEL SCRIPT: v1 (2026-08-05)
#
# QUÉ ES ESTO
# -----------
# El usuario construyó A MANO 4 torres triangulares de referencia -las que
# él considera correctas- y las inspeccionó con el script de inspección del
# proyecto, generando 4 archivos .txt gigantes (77-99MB cada uno) en
# /Users/minorusal/Documents/SKETCHUP/inspect_output/ (los últimos 4 al
# momento de escribir esto: inspect_20260805_162750.txt, _162801.txt,
# _162813.txt, _162822.txt).
#
# En vez de leer esos archivos línea por línea -inviables de leer a mano,
# son >1.6 millones de líneas cada uno-, se parsearon con un script Python
# para extraer, de cada una de las 19 piezas DIRECTAS del grupo
# 'MOD-3X4X2-TORRE' de cada diseño -los 3 tipos de conector (CON-12, CON-21,
# CON-10) más los tramos de tubo sin nombre-, su caja LOCAL (min/max,
# relativa al propio grupo de la torre) y su transform completo (origen +
# xaxis/yaxis/zaxis).
#
# Este script NO reconstruye la lógica general de la torre -eso viene
# DESPUÉS, cuando el usuario dé el visto bueno de que esto reproduce bien
# los 4 diseños-. Por ahora es deliberadamente "tonto": toma la tabla de
# datos extraída tal cual y dibuja una CAJA por pieza, usando exactamente su
# min/max local -así no hay ningún riesgo de que una composición de
# transformaciones salga mal; es una copia literal de la geometría medida-.
# Cada caja se colorea según el tipo de pieza para que sea fácil leer a
# simple vista qué es qué:
#   - CON-12  -> naranja
#   - CON-21  -> azul
#   - CON-10  -> verde
#   - tubo (sin nombre) -> gris
#
# Los 4 diseños se colocan en fila, separados en X, cerca del origen del
# modelo -NO en las coordenadas originales gigantescas donde el usuario los
# construyó-, para poder compararlos lado a lado sin tener que viajar por
# el modelo. Cada uno queda en su propio grupo, nombrado
# "REFERENCIA-DISEÑO-N", normalizado para que su propia esquina
# mínima quede en (0,0,0) dentro de su grupo.
#
# CÓMO USARLO
# -----------
#   GenerarTorresReferencia.construir(1)              # solo el diseño 1
#   GenerarTorresReferencia.construir_todos            # los 4, en fila
#
# Cuando esto se vea igual que lo que el usuario construyó a mano, el
# siguiente paso -pendiente, NO incluido aquí todavía- es generalizar estas
# 4 tablas hacia una regla paramétrica (por esquina/escalón) e integrarla al
# plugin constructor_modulos_playidea, reemplazando TRIANGLE_CONNECTOR_AXES
# y compañía.

module GenerarTorresReferencia
  extend self

  SEPARACION_X_MM = 4500.0

  COLOR_POR_TIPO = {
    'CON-12' => Sketchup::Color.new(0xE5, 0x6B, 0x18),
    'CON-21' => Sketchup::Color.new(0x17, 0x3B, 0x68),
    'CON-10' => Sketchup::Color.new(0x2C, 0x7A, 0x3D),
    'TUBO'   => Sketchup::Color.new(0x9A, 0x9A, 0x9A)
  }.freeze

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

  def tipo_pieza(nombre)
    return nombre if COLOR_POR_TIPO.key?(nombre)
    'TUBO'
  end

  def add_box(entities, min_pt, max_pt, color, nombre)
    group = entities.add_group
    group.name = nombre
    ge = group.entities
    pts = [
      Geom::Point3d.new(min_pt[0].mm, min_pt[1].mm, min_pt[2].mm),
      Geom::Point3d.new(max_pt[0].mm, min_pt[1].mm, min_pt[2].mm),
      Geom::Point3d.new(max_pt[0].mm, max_pt[1].mm, min_pt[2].mm),
      Geom::Point3d.new(min_pt[0].mm, max_pt[1].mm, min_pt[2].mm)
    ]
    face = ge.add_face(pts)
    face.reverse! if face.normal.z < 0
    face.pushpull((max_pt[2] - min_pt[2]).mm)

    material_name = "RefTorre - #{tipo_pieza(nombre)}"
    material = Sketchup.active_model.materials[material_name] || Sketchup.active_model.materials.add(material_name)
    material.color = color
    ge.grep(Sketchup::Face).each { |f| f.material = material; f.back_material = material }
    group
  end

  # Normaliza para que la esquina mínima de TODAS las piezas del diseño
  # quede en (0,0,0) -las coordenadas originales del usuario estaban muy
  # lejos del origen del modelo-.
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
    model.start_operation("Referencia torre triangular #{numero_diseno}", true)
    container = model.active_entities.add_group
    container.name = "REFERENCIA-DISEÑO-#{numero_diseno}"
    entities = container.entities

    offset = esquina_minima(piezas)
    piezas.each do |pieza|
      min_norm = [pieza[:min][0] - offset[0], pieza[:min][1] - offset[1], pieza[:min][2] - offset[2]]
      max_norm = [pieza[:max][0] - offset[0], pieza[:max][1] - offset[1], pieza[:max][2] - offset[2]]
      tipo = tipo_pieza(pieza[:nombre])
      color = COLOR_POR_TIPO[tipo]
      add_box(entities, min_norm, max_norm, color, pieza[:nombre] == '(sin nombre)' ? 'TUBO' : pieza[:nombre])
    end

    desplazamiento_x = (numero_diseno - 1) * SEPARACION_X_MM
    container.transformation = Geom::Transformation.translation(Geom::Point3d.new(desplazamiento_x.mm, 0, 0))

    model.selection.add(container)
    model.commit_operation
    puts "✅ REFERENCIA-DISEÑO-#{numero_diseno}: #{piezas.length} piezas -" \
      "#{piezas.count { |p| p[:nombre] == 'CON-12' }} CON-12, " \
      "#{piezas.count { |p| p[:nombre] == 'CON-21' }} CON-21, " \
      "#{piezas.count { |p| p[:nombre] == 'CON-10' }} CON-10, " \
      "#{piezas.count { |p| p[:nombre] == '(sin nombre)' }} tubos."
    container
  end

  def construir_todos
    model = Sketchup.active_model
    model.selection.clear
    (1..4).each { |n| construir(n) }
    puts "✅ Los 4 diseños de referencia quedaron en fila, separados #{SEPARACION_X_MM}mm entre sí, cerca del origen."
  end
end

nil
