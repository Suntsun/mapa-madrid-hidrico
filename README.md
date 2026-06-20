# Mapa Hídrico y Medioambiental — Comunidad de Madrid

Mapa web interactivo construido con **Leaflet 1.9.4** (vendorizado en `vendor/leaflet/`) y datos estáticos GeoJSON. Muestra 13 capas temáticas activables de la Comunidad de Madrid: recursos hídricos, espacios naturales protegidos, división administrativa y equipamientos ambientales.

Leaflet se sirve en local (sin CDN ni SRI), lo que garantiza compatibilidad con GitHub Pages y elimina dependencias de disponibilidad de `unpkg.com`.

---

## Ver en local

Se necesita un servidor HTTP local (los ficheros GeoJSON se cargan vía `fetch`, que no funciona con `file://`).

```bash
# Con Python 3 (recomendado):
cd /ruta/al/proyecto
python3 -m http.server 8080

# Abre en el navegador:
# http://localhost:8080
```

Con Node.js (si está instalado):
```bash
npx serve .
```

---

## Capas disponibles

### Aguas (azul)
| Capa | Color | Estado |
|------|-------|--------|
| Embalses | Azul sólido | OK (14) |
| Humedales | Turquesa sólido | OK (80) |
| Ríos | Línea azul | FALLIDA (servicio IGN no disponible) |

### Espacios Protegidos
| Capa | Símbolo | Estado |
|------|---------|--------|
| ZEC / LIC | Relleno verde sólido | OK (7) |
| ZEPA | Puntitos naranjas | OK (7) |
| Parque Nacional Guadarrama | Rayas rojas diagonales | OK (2 zonas) |
| Parques Regionales | Triangulitos morados | OK (68: Manzanares + Guadarrama + Sureste) |

### Administrativo
| Capa | Símbolo | Estado |
|------|---------|--------|
| Comarcas Forestales | Línea negra gruesa | OK (17) |
| Límites Municipales | Trazo gris dashed | OK (194 municipios) |

### Equipamientos
| Capa | Icono | Estado |
|------|-------|--------|
| Centros de Educación Ambiental | Punto azul | OK (9) — 2 aproximados |
| Centros de Visitantes | Punto naranja | OK (4) |
| Oficinas Comarcales | Punto morado | OK (10) |

---

## Funcionalidad

- **Control de capas** (arriba derecha): activa/desactiva cada capa independientemente. También cambia la base cartográfica (IGN Base, IGN Raster, OSM).
- **Popup**: haz clic sobre cualquier elemento para ver su nombre.
- **Leyenda** (abajo derecha): plegable con el botón `−/+`.
- **Responsive**: usable en móvil.

---

## Fuentes y atribución

| Dato | Fuente | Licencia |
|------|--------|----------|
| Embalses, Humedales, Comarcas Forestales | [IDEM Comunidad de Madrid](https://idem.comunidad.madrid) | CC BY 4.0 |
| ZEC/LIC, ZEPA, Parque Nacional, Parques Regionales | IDEM Comunidad de Madrid | CC BY 4.0 |
| Límites Municipales | IDEM Comunidad de Madrid | CC BY 4.0 |
| Ríos (no disponible) | IGN/CNIG (WFS hidrografía) | CC BY 4.0 |
| Equipamientos (coordenadas) | OpenStreetMap / Nominatim | ODbL |
| Base cartográfica | [Instituto Geográfico Nacional](https://www.ign.es) | CC BY 4.0 |

---

## Re-descargar los datos

Los GeoJSON en `data/` son estáticos. Para actualizarlos:

```bash
bash scripts/descargar_datos.sh
```

El script descarga todas las capas desde los WFS del IDEM (y Nominatim para equipamientos), valida que sean GeoJSON válidos y no vacíos, y los sobreescribe en `data/`.

---

## Desplegar en GitHub Pages

1. Crea un repositorio en GitHub y sube este directorio:
   ```bash
   git init
   git add .
   git commit -m "Mapa hídrico Comunidad de Madrid"
   git remote add origin https://github.com/TU_USUARIO/TU_REPO.git
   git push -u origin main
   ```

2. En GitHub > Settings > Pages, selecciona rama `main` y carpeta raíz (`/`).

3. El mapa estará en `https://TU_USUARIO.github.io/TU_REPO/` en pocos minutos.

> Los GeoJSON se sirven estáticamente junto con el HTML — no hay backend ni dependencias de servicios WFS en tiempo de ejecución.

---

## Estructura del proyecto

```
mapa-madrid-hidrico/
├── index.html              # Página principal
├── css/
│   └── mapa.css            # Estilos del mapa y leyenda
├── js/
│   ├── patrones.js         # SVG patterns y estilos de capa
│   └── mapa.js             # Lógica Leaflet (capas, popups, control)
├── vendor/
│   └── leaflet/            # Leaflet 1.9.4 vendorizado (sin CDN)
│       ├── leaflet.js
│       ├── leaflet.css
│       └── images/         # Iconos de marcadores y capas
├── data/                   # GeoJSON estáticos (descargados)
│   ├── embalses.geojson
│   ├── humedales.geojson
│   ├── zec_lic.geojson
│   ├── zepa.geojson
│   ├── pn_guadarrama.geojson
│   ├── parques_regionales.geojson
│   ├── comarcas_forestales.geojson
│   ├── municipios.geojson
│   └── equipamientos.geojson
└── scripts/
    └── descargar_datos.sh  # Script reproducible de descarga
```
