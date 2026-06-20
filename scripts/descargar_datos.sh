#!/usr/bin/env bash
# =============================================================
# descargar_datos.sh — Descarga reproducible de GeoJSON
# Mapa Hídrico y Medioambiental · Comunidad de Madrid
#
# Uso:   bash scripts/descargar_datos.sh
# Req:   curl, python3 (stdlib)
# =============================================================

set -euo pipefail

DATA_DIR="$(cd "$(dirname "$0")/.." && pwd)/data"
TMP_DIR="$(mktemp -d)"
TIMEOUT=90
OK_COUNT=0
FAIL_COUNT=0

echo "=== Descarga de datos GeoJSON ==="
echo "Destino: $DATA_DIR"
echo ""

mkdir -p "$DATA_DIR"

# ── Función de descarga y validación ──────────────────────────
descargar_capa() {
  local nombre="$1"
  local url="$2"
  local destino="$3"

  local tmp_url="$TMP_DIR/url_${nombre}.txt"
  local tmp_raw="$TMP_DIR/raw_${nombre}.json"

  # P4: escribe URL a fichero temporal
  echo "$url" > "$tmp_url"

  echo -n "[$nombre] Descargando... "

  if curl -s --max-time "$TIMEOUT" -o "$tmp_raw" "$(cat "$tmp_url")"; then
    # Validar GeoJSON
    local resultado
    resultado=$(python3 - <<PYEOF 2>&1
import json, sys
try:
    with open('$tmp_raw') as f:
        d = json.load(f)
    t = d.get('type', '')
    feats = d.get('features', [])
    if t != 'FeatureCollection':
        print(f'ERROR: type={t} (no es FeatureCollection)')
        sys.exit(1)
    if len(feats) == 0:
        print('ERROR: 0 features')
        sys.exit(1)
    # Verificar CRS (coordenadas 4326, lon debe ser < 0 para Madrid)
    sample = feats[0].get('geometry', {})
    coords = sample.get('coordinates', [])
    def flat(c):
        if isinstance(c, (int, float)):
            return [c]
        out = []
        for x in c:
            out.extend(flat(x))
        return out
    nums = flat(coords)
    if len(nums) >= 2:
        # primer par de coords del primer feature
        lon_sample = nums[0]
        if lon_sample > 100:
            print(f'WARN: coordenadas parecen UTM (lon_sample={lon_sample:.0f}) — puede necesitar reproyección')
        else:
            print(f'OK: {len(feats)} features, lon_sample={lon_sample:.4f}')
    else:
        print(f'OK: {len(feats)} features')
PYEOF
)

    if echo "$resultado" | grep -q "^OK"; then
      cp "$tmp_raw" "$destino"
      echo "$resultado"
      OK_COUNT=$((OK_COUNT + 1))
    elif echo "$resultado" | grep -q "^WARN"; then
      cp "$tmp_raw" "$destino"
      echo "$resultado (guardado igualmente)"
      OK_COUNT=$((OK_COUNT + 1))
    else
      echo "FALLIDA: $resultado"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  else
    echo "FALLIDA: curl error (timeout o red)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# ── AGUAS ─────────────────────────────────────────────────────

BASE_ZONAS="https://idem.comunidad.madrid/geoidem/Zonas/ows"
WFS_PARAMS="service=WFS&version=1.0.0&request=GetFeature&outputFormat=application%2Fjson&srsName=EPSG:4326"

descargar_capa "embalses" \
  "${BASE_ZONAS}?${WFS_PARAMS}&typeName=Zonas:IDEM_MA_CEH_EMBALSES" \
  "$DATA_DIR/embalses.geojson"

descargar_capa "humedales" \
  "${BASE_ZONAS}?${WFS_PARAMS}&typeName=Zonas:IDEM_MA_CEH_HUMEDALES" \
  "$DATA_DIR/humedales.geojson"

# ── RÍOS: OpenStreetMap via Overpass API (ODbL) ───────────────
# Fuente primaria: Overpass API · waterway=river en bbox Madrid
# bbox Overpass: lat_min,lon_min,lat_max,lon_max
echo "[rios] Descargando desde Overpass API (OSM waterway=river)..."

OVERPASS_QUERY='[out:json][timeout:60][bbox:39.85,-4.60,41.17,-3.05];
(
  way["waterway"="river"];
  relation["waterway"="river"];
);
out geom;'

# P4: escribir query a fichero temporal
QUERY_FILE="$TMP_DIR/overpass_query_rios.txt"
printf '%s' "$OVERPASS_QUERY" > "$QUERY_FILE"

RAW_OSM="$TMP_DIR/raw_rios_osm.json"

# POST con data= form-encoded
QUERY_ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote(open('$QUERY_FILE').read()))")
if curl -s --max-time "$TIMEOUT" \
    -X POST \
    -d "data=${QUERY_ENCODED}" \
    -o "$RAW_OSM" \
    "https://overpass-api.de/api/interpreter"; then

  # Convertir OSM JSON → GeoJSON LineStrings
  RIOS_RESULT=$(python3 - <<PYEOF 2>&1
import json, sys

BBOX_LON_MIN, BBOX_LON_MAX = -4.60, -3.05
BBOX_LAT_MIN, BBOX_LAT_MAX = 39.85, 41.17

try:
    with open('$RAW_OSM') as f:
        d = json.load(f)
except Exception as e:
    print(f'ERROR: JSON inválido: {e}')
    sys.exit(1)

elements = d.get('elements', [])
ways = [e for e in elements if e.get('type') == 'way']

if not ways:
    print('ERROR: 0 ways en la respuesta')
    sys.exit(1)

features = []
for way in ways:
    geom = way.get('geometry', [])
    if not geom:
        continue
    coords = [[n['lon'], n['lat']] for n in geom]
    # Al menos un punto dentro del bbox
    in_bbox = any(
        BBOX_LON_MIN <= c[0] <= BBOX_LON_MAX and BBOX_LAT_MIN <= c[1] <= BBOX_LAT_MAX
        for c in coords
    )
    if not in_bbox:
        continue
    tags = way.get('tags', {})
    nombre = tags.get('name', tags.get('name:es', ''))
    features.append({
        'type': 'Feature',
        'geometry': {'type': 'LineString', 'coordinates': coords},
        'properties': {'nombre': nombre, 'waterway': tags.get('waterway', ''), 'osm_id': way['id']}
    })

geojson = {'type': 'FeatureCollection', 'features': features}
out = '$DATA_DIR/rios.geojson'
with open(out, 'w', encoding='utf-8') as f:
    json.dump(geojson, f, ensure_ascii=False)

sample_lon = features[0]['geometry']['coordinates'][0][0] if features else 0
print(f'OK: {len(features)} features, lon_sample={sample_lon:.4f}')
PYEOF
)

  if echo "$RIOS_RESULT" | grep -q "^OK"; then
    echo "[rios] $RIOS_RESULT (OSM/ODbL)"
    OK_COUNT=$((OK_COUNT + 1))
  else
    echo "[rios] FALLIDA: $RIOS_RESULT"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  echo "[rios] FALLIDA: curl error (timeout o red a overpass-api.de)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ── ARROYOS: OpenStreetMap via Overpass API (ODbL) ────────────
# Fuente: Overpass API · waterway=stream en bbox Madrid
# bbox Overpass: lat_min,lon_min,lat_max,lon_max
echo "[arroyos] Descargando desde Overpass API (OSM waterway=stream)..."

ARROYOS_QUERY='[out:json][timeout:90][bbox:39.85,-4.60,41.17,-3.05];
way["waterway"="stream"];
out geom;'

# P4: escribir query a fichero temporal
ARROYOS_QUERY_FILE="$TMP_DIR/overpass_query_arroyos.txt"
printf '%s' "$ARROYOS_QUERY" > "$ARROYOS_QUERY_FILE"

RAW_ARROYOS="$TMP_DIR/raw_arroyos_osm.json"

ARROYOS_QUERY_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote(open('$ARROYOS_QUERY_FILE').read()))")
if curl -s --max-time 120 \
    -X POST \
    -d "data=${ARROYOS_QUERY_ENC}" \
    -o "$RAW_ARROYOS" \
    "https://overpass-api.de/api/interpreter"; then

  ARROYOS_RESULT=$(python3 - <<PYEOF 2>&1
import json, sys

BBOX_LON_MIN, BBOX_LON_MAX = -4.60, -3.05
BBOX_LAT_MIN, BBOX_LAT_MAX = 39.85, 41.17

try:
    with open('$RAW_ARROYOS') as f:
        d = json.load(f)
except Exception as e:
    print(f'ERROR: JSON inválido: {e}')
    sys.exit(1)

elements = d.get('elements', [])
ways = [e for e in elements if e.get('type') == 'way']

if not ways:
    print('ERROR: 0 ways en la respuesta')
    sys.exit(1)

features = []
for way in ways:
    geom = way.get('geometry', [])
    if not geom:
        continue
    coords = [[n['lon'], n['lat']] for n in geom]
    in_bbox = any(
        BBOX_LON_MIN <= c[0] <= BBOX_LON_MAX and BBOX_LAT_MIN <= c[1] <= BBOX_LAT_MAX
        for c in coords
    )
    if not in_bbox:
        continue
    tags = way.get('tags', {})
    nombre = tags.get('name', tags.get('name:es', ''))
    features.append({
        'type': 'Feature',
        'geometry': {'type': 'LineString', 'coordinates': coords},
        'properties': {'nombre': nombre, 'waterway': 'stream', 'osm_id': way['id']}
    })

geojson = {'type': 'FeatureCollection', 'features': features}
out = '$DATA_DIR/arroyos.geojson'
with open(out, 'w', encoding='utf-8') as f:
    json.dump(geojson, f, ensure_ascii=False)

sample_lon = features[0]['geometry']['coordinates'][0][0] if features else 0
print(f'OK: {len(features)} features, lon_sample={sample_lon:.4f}')
PYEOF
)

  if echo "$ARROYOS_RESULT" | grep -q "^OK"; then
    echo "[arroyos] $ARROYOS_RESULT (OSM/ODbL)"
    OK_COUNT=$((OK_COUNT + 1))
  else
    echo "[arroyos] FALLIDA: $ARROYOS_RESULT"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  echo "[arroyos] FALLIDA: curl error (timeout o red a overpass-api.de)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ── RED NATURA / PROTEGIDOS ────────────────────────────────────

BASE_LP="https://idem.comunidad.madrid/geoidem/LugaresProtegidos/ows"

descargar_capa "zec_lic" \
  "${BASE_LP}?${WFS_PARAMS}&typeName=LugaresProtegidos:IDEM_MA_RED_NATURA_LIC_ZEC" \
  "$DATA_DIR/zec_lic.geojson"

descargar_capa "zepa" \
  "${BASE_LP}?${WFS_PARAMS}&typeName=LugaresProtegidos:IDEM_MA_RED_NATURA_ZEPA" \
  "$DATA_DIR/zepa.geojson"

descargar_capa "pn_guadarrama" \
  "${BASE_LP}?${WFS_PARAMS}&typeName=LugaresProtegidos:IDEM_MA_PN_GUADARRAMA_CM" \
  "$DATA_DIR/pn_guadarrama.geojson"

# Parques Regionales: descargar 3 subcapas y combinar
echo "[parques_regionales] Descargando 3 subcapas..."

SUBCAPAS=(
  "IDEM_MA_PR_CA_MANZANARES:Parque Regional Cuenca Alta del Manzanares"
  "IDEM_MA_PR_GUADARRAMA:Parque Regional de la Sierra de Guadarrama"
  "IDEM_MA_PR_SURESTE:Parque Regional del Sureste"
)

PR_OK=0
for item in "${SUBCAPAS[@]}"; do
  typeName="${item%%:*}"
  parqueNombre="${item#*:}"
  tmpFile="$TMP_DIR/raw_pr_${typeName}.json"

  echo -n "  [${typeName}] ... "
  urlFile="$TMP_DIR/url_pr_${typeName}.txt"
  echo "${BASE_LP}?${WFS_PARAMS}&typeName=LugaresProtegidos:${typeName}" > "$urlFile"

  if curl -s --max-time "$TIMEOUT" -o "$tmpFile" "$(cat "$urlFile")"; then
    n=$(python3 -c "
import json
try:
    with open('$tmpFile') as f: d=json.load(f)
    print(len(d.get('features',[])))
except: print(0)
")
    echo "${n} features"
    if [ "$n" -gt "0" ]; then
      PR_OK=$((PR_OK + 1))
    fi
  else
    echo "FALLIDA (curl error)"
  fi
done

# Combinar las subcapas descargadas
python3 - <<PYEOF
import json, os

subcapas = [
    ('$TMP_DIR/raw_pr_IDEM_MA_PR_CA_MANZANARES.json', 'Parque Regional Cuenca Alta del Manzanares'),
    ('$TMP_DIR/raw_pr_IDEM_MA_PR_GUADARRAMA.json', 'Parque Regional de la Sierra de Guadarrama'),
    ('$TMP_DIR/raw_pr_IDEM_MA_PR_SURESTE.json', 'Parque Regional del Sureste'),
]

features = []
for fpath, pnombre in subcapas:
    if not os.path.exists(fpath):
        continue
    try:
        with open(fpath) as f:
            d = json.load(f)
        for feat in d.get('features', []):
            if feat.get('properties') is None:
                feat['properties'] = {}
            feat['properties']['parque'] = pnombre
            features.append(feat)
    except Exception as e:
        print(f'  Aviso: no se pudo procesar {fpath}: {e}')

combined = {'type': 'FeatureCollection', 'features': features}
out = '$DATA_DIR/parques_regionales.geojson'
with open(out, 'w', encoding='utf-8') as f:
    json.dump(combined, f, ensure_ascii=False)
print(f'[parques_regionales] Combinados: {len(features)} features → {out}')
PYEOF

if [ -f "$DATA_DIR/parques_regionales.geojson" ]; then
  OK_COUNT=$((OK_COUNT + 1))
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ── ADMINISTRATIVO ─────────────────────────────────────────────

BASE_UA="https://idem.comunidad.madrid/geoidem/UnidadesAdministrativas/ows"

echo -n "[municipios] Probando typeName IDEM_CM_LIMITES_UNID_ADMIN... "
TMP_MUN="$TMP_DIR/raw_mun_limites.json"
curl -s --max-time "$TIMEOUT" -o "$TMP_MUN" \
  "${BASE_UA}?${WFS_PARAMS}&typeName=UnidadesAdministrativas:IDEM_CM_LIMITES_UNID_ADMIN"

N_LIMITES=$(python3 -c "
import json
try:
    with open('$TMP_MUN') as f: d=json.load(f)
    feats = d.get('features', [])
    # Comprueba que son Polygon (no LineString)
    polys = [f for f in feats if f.get('geometry',{}).get('type','') in ('Polygon','MultiPolygon')]
    print(len(polys))
except: print(0)
")

if [ "$N_LIMITES" -gt "0" ]; then
  cp "$TMP_MUN" "$DATA_DIR/municipios.geojson"
  echo "OK ($N_LIMITES polígonos)"
  OK_COUNT=$((OK_COUNT + 1))
else
  echo "sin polígonos, probando IDEM_CM_UNID_ADMIN..."
  descargar_capa "municipios" \
    "${BASE_UA}?${WFS_PARAMS}&typeName=UnidadesAdministrativas:IDEM_CM_UNID_ADMIN" \
    "$DATA_DIR/municipios.geojson"
fi

descargar_capa "comarcas_forestales" \
  "${BASE_ZONAS}?${WFS_PARAMS}&typeName=Zonas:IDEM_MA_COMARCAS_FORESTALES" \
  "$DATA_DIR/comarcas_forestales.geojson"

# ── EQUIPAMIENTOS (Nominatim) ──────────────────────────────────
echo ""
echo "[equipamientos] Geocodificando con Nominatim..."
python3 - <<PYEOF
import json, time, urllib.request, urllib.parse, os

def geocodificar(query):
    params = urllib.parse.urlencode({'q': query, 'format': 'json', 'limit': 1, 'countrycodes': 'es'})
    url = f'https://nominatim.openstreetmap.org/search?{params}'
    req = urllib.request.Request(url, headers={'User-Agent': 'mapa-madrid-hidrico/1.0 dev6@accon.es'})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
        if data:
            return float(data[0]['lon']), float(data[0]['lat'])
    except Exception as e:
        print(f'  Error: {e}')
    return None

equipamientos = [
    ('Arboreto Luis Ceballos', 'Arboreto Luis Ceballos, San Lorenzo de El Escorial, Madrid', 'Centro de Educación Ambiental', 'San Lorenzo de El Escorial', 'San Lorenzo de El Escorial, Madrid, España'),
    ('Bosque Sur', 'Bosque Sur, Fuenlabrada, Madrid', 'Centro de Educación Ambiental', 'Fuenlabrada', 'Fuenlabrada, Madrid, España'),
    ('Caserío de Henares', 'Caserío de Henares, San Fernando de Henares, Madrid', 'Centro de Educación Ambiental', 'San Fernando de Henares', 'San Fernando de Henares, Madrid, España'),
    ('El Águila', 'Centro El Águila, Chapinería, Madrid', 'Centro de Educación Ambiental', 'Chapinería', 'Chapinería, Madrid, España'),
    ('El Campillo', 'Centro El Campillo, Rivas-Vaciamadrid, Madrid', 'Centro de Educación Ambiental', 'Rivas-Vaciamadrid', 'Rivas-Vaciamadrid, Madrid, España'),
    ('Hayedo de Montejo', 'Hayedo de Montejo de la Sierra, Madrid', 'Centro de Educación Ambiental', 'Montejo de la Sierra', 'Montejo de la Sierra, Madrid, España'),
    ('Polvoranca', 'Parque Polvoranca, Leganés, Madrid', 'Centro de Educación Ambiental', 'Leganés', 'Leganés, Madrid, España'),
    ('Valle del Lozoya / Puente del Perdón', 'Puente del Perdón, Rascafría, Madrid', 'Centro de Educación Ambiental', 'Rascafría', 'Rascafría, Madrid, España'),
    ('Manzanares (CEA)', 'Centro de Educación Ambiental Manzanares, Manzanares el Real, Madrid', 'Centro de Educación Ambiental', 'Manzanares el Real', 'Manzanares el Real, Madrid, España'),
    ('La Pedriza', 'La Pedriza, Manzanares el Real, Madrid', 'Centro de Visitantes', 'Manzanares el Real', 'Manzanares el Real, Madrid, España'),
    ('Valle de la Fuenfría', 'Valle de la Fuenfría, Cercedilla, Madrid', 'Centro de Visitantes', 'Cercedilla', 'Cercedilla, Madrid, España'),
    ('Valle del Paular', 'Monasterio de El Paular, Rascafría, Madrid', 'Centro de Visitantes', 'Rascafría', 'Rascafría, Madrid, España'),
    ('Peñalara / Puerto de Cotos', 'Puerto de Cotos, Rascafría, Madrid', 'Centro de Visitantes', 'Rascafría/Cotos', 'Rascafría, Madrid, España'),
    ('Oficina Comarcal Alcalá de Henares', 'Alcalá de Henares, Madrid, España', 'Oficina Comarcal', 'Alcalá de Henares', 'Alcalá de Henares, Madrid, España'),
    ('Oficina Comarcal Aranjuez', 'Aranjuez, Madrid, España', 'Oficina Comarcal', 'Aranjuez', 'Aranjuez, Madrid, España'),
    ('Oficina Comarcal Arganda del Rey', 'Arganda del Rey, Madrid, España', 'Oficina Comarcal', 'Arganda del Rey', 'Arganda del Rey, Madrid, España'),
    ('Oficina Comarcal Buitrago de Lozoya', 'Buitrago de Lozoya, Madrid, España', 'Oficina Comarcal', 'Buitrago de Lozoya', 'Buitrago de Lozoya, Madrid, España'),
    ('Oficina Comarcal Colmenar Viejo', 'Colmenar Viejo, Madrid, España', 'Oficina Comarcal', 'Colmenar Viejo', 'Colmenar Viejo, Madrid, España'),
    ('Oficina Comarcal El Escorial', 'El Escorial, Madrid, España', 'Oficina Comarcal', 'El Escorial', 'El Escorial, Madrid, España'),
    ('Oficina Comarcal Navalcarnero', 'Navalcarnero, Madrid, España', 'Oficina Comarcal', 'Navalcarnero', 'Navalcarnero, Madrid, España'),
    ('Oficina Comarcal San Martín de Valdeiglesias', 'San Martín de Valdeiglesias, Madrid, España', 'Oficina Comarcal', 'San Martín de Valdeiglesias', 'San Martín de Valdeiglesias, Madrid, España'),
    ('Oficina Comarcal Torrelaguna', 'Torrelaguna, Madrid, España', 'Oficina Comarcal', 'Torrelaguna', 'Torrelaguna, Madrid, España'),
    ('Oficina Comarcal Villarejo de Salvanés', 'Villarejo de Salvanés, Madrid, España', 'Oficina Comarcal', 'Villarejo de Salvanés', 'Villarejo de Salvanés, Madrid, España'),
]

features = []
for nombre, query_exacta, tipo, municipio, query_fallback in equipamientos:
    print(f'  {nombre}...', end=' ')
    coords = geocodificar(query_exacta)
    aproximado = False
    time.sleep(1)
    if not coords:
        coords = geocodificar(query_fallback)
        aproximado = True
        time.sleep(1)
    if coords:
        print(f'OK ({coords[0]:.4f},{coords[1]:.4f}){"[APROX]" if aproximado else ""}')
        features.append({
            'type': 'Feature',
            'geometry': {'type': 'Point', 'coordinates': list(coords)},
            'properties': {'nombre': nombre, 'tipo': tipo, 'municipio': municipio, 'aproximado': aproximado}
        })
    else:
        print('FALLIDA')

out = os.path.join('$DATA_DIR', 'equipamientos.geojson')
with open(out, 'w', encoding='utf-8') as f:
    json.dump({'type': 'FeatureCollection', 'features': features}, f, ensure_ascii=False, indent=2)
print(f'[equipamientos] {len(features)}/23 geocodificados → {out}')
PYEOF

# ── RESUMEN ───────────────────────────────────────────────────
rm -rf "$TMP_DIR"
echo ""
echo "=== RESUMEN ==="
echo "  OK:     $OK_COUNT capas"
echo "  FALLO:  $FAIL_COUNT capas"
echo ""
echo "Ficheros en $DATA_DIR:"
ls -lh "$DATA_DIR/"
