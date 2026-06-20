/**
 * mapa.js — Lógica principal del Mapa Hídrico y Medioambiental
 * Comunidad de Madrid
 *
 * Capas:
 *   AGUAS:           Ríos (OSM/ODbL), Embalses, Humedales
 *   PROTEGIDOS:      ZEC/LIC, ZEPA, Parque Nacional, Parques Regionales
 *   ADMINISTRATIVO:  Comarcas Forestales, Límites Municipales
 *   EQUIPAMIENTOS:   Centros Ed. Ambiental, Centros Visitantes, Oficinas Comarcales
 */

(function () {
  'use strict';

  /* ── 1. INICIALIZAR MAPA ─────────────────────────────── */
  const map = L.map('map', {
    center: [40.45, -3.70],
    zoom: 9,
    zoomControl: true,
    attributionControl: true
  });

  /* ── 2. CAPAS BASE ──────────────────────────────────── */
  const baseLayers = {};

  // IGN Base Todo (teselas TMS)
  const ignBase = L.tileLayer(
    'https://tms-ign-base.idee.es/1.0.0/IGNBaseTodo/{z}/{x}/{-y}.jpeg',
    {
      tms: true,
      maxZoom: 20,
      attribution: '&copy; <a href="https://www.ign.es" target="_blank">Instituto Geográfico Nacional de España</a>'
    }
  ).addTo(map);
  baseLayers['IGN Base'] = ignBase;

  // OSM como respaldo
  const osm = L.tileLayer(
    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
    {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }
  );
  baseLayers['OpenStreetMap'] = osm;

  // CartoDB Positron teñido — ocre claro
  const cartoOcre = L.tileLayer(
    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    {
      subdomains: 'abcd',
      maxZoom: 19,
      attribution: '&copy; OpenStreetMap, &copy; CARTO',
      className: 'base-ocre'
    }
  );
  baseLayers['Minimalista ocre'] = cartoOcre;

  /* ── 3. ATRIBUCIÓN GENERAL ──────────────────────────── */
  map.attributionControl.setPrefix(
    'Datos: <a href="https://idem.comunidad.madrid" target="_blank">IDEM Comunidad de Madrid</a> (CC BY 4.0), ' +
    '<a href="https://www.ign.es" target="_blank">IGN</a>, MITECO · ' +
    'Ríos: &copy; <a href="https://www.openstreetmap.org/copyright" target="_blank">OpenStreetMap</a> (ODbL) · ' +
    'Base: IGN'
  );

  /* ── 4. ESTILOS (desde patrones.js) ─────────────────── */
  const P = window.MapaPatrones;

  /* ── 5. FUNCIÓN: CARGAR GEOJSON ─────────────────────── */
  function cargarGeoJSON(ruta, opciones) {
    return fetch(ruta)
      .then(function (resp) {
        if (!resp.ok) throw new Error('HTTP ' + resp.status);
        return resp.json();
      })
      .then(function (data) {
        if (!data.features || data.features.length === 0) {
          console.warn('[mapa] Sin features en', ruta);
          return null;
        }
        return L.geoJSON(data, opciones);
      })
      .catch(function (err) {
        console.error('[mapa] Error cargando', ruta, err);
        return null;
      });
  }

  /* ── 6. FUNCIÓN: POPUP GENÉRICO ──────────────────────── */
  function popupNombre(campos) {
    return function (feature, layer) {
      var props = feature.properties || {};
      var nombre = '';
      for (var i = 0; i < campos.length; i++) {
        if (props[campos[i]]) { nombre = props[campos[i]]; break; }
      }
      if (!nombre) nombre = '(sin nombre)';
      layer.bindPopup('<strong>' + nombre + '</strong>');
    };
  }

  function popupEquipamiento(feature, layer) {
    var p = feature.properties || {};
    var aprox = p.aproximado
      ? '<div class="popup-aprox">* Ubicación aproximada (nivel municipio)</div>'
      : '';
    layer.bindPopup(
      '<strong>' + (p.nombre || '(sin nombre)') + '</strong>' +
      '<div class="popup-tipo">' + (p.tipo || '') + '</div>' +
      '<div class="popup-detalle">' + (p.municipio || '') + '</div>' +
      aprox
    );
  }

  /* ── 7. ICONO DE EQUIPAMIENTO ────────────────────────── */
  function iconoEquipamiento(color) {
    return L.divIcon({
      className: '',
      html: '<div class="equip-marker" style="width:14px;height:14px;background:' + color + ';border-radius:50%;border:2px solid rgba(0,0,0,0.4);box-shadow:0 1px 4px rgba(0,0,0,0.4);"></div>',
      iconSize: [14, 14],
      iconAnchor: [7, 7],
      popupAnchor: [0, -10]
    });
  }

  /* ── 8. CAPAS TEMÁTICAS ──────────────────────────────── */
  var overlayLayers = {};

  // Contenedor de promesas para saber cuándo todo terminó
  var promesas = [];

  /* --- AGUAS --- */

  // Ríos (OSM via Overpass, ODbL)
  promesas.push(
    cargarGeoJSON('data/rios.geojson', {
      style: P.rio(),
      onEachFeature: popupNombre(['nombre', 'name'])
    }).then(function (layer) {
      if (layer) {
        overlayLayers['Ríos'] = layer;
      }
    })
  );

  // Arroyos (OSM via Overpass, ODbL)
  promesas.push(
    cargarGeoJSON('data/arroyos.geojson', {
      style: P.arroyo(),
      onEachFeature: function (feature, layer) {
        var nombre = (feature.properties && feature.properties.nombre) || '';
        layer.bindPopup('<strong>' + (nombre || '(sin nombre)') + '</strong>');
      }
    }).then(function (layer) {
      if (layer) {
        overlayLayers['Arroyos'] = layer;
      }
    })
  );

  // Embalses
  promesas.push(
    cargarGeoJSON('data/embalses.geojson', {
      style: P.embalse(),
      onEachFeature: popupNombre(['DS_NOMBRE', 'NOMBRE', 'Name', 'name'])
    }).then(function (layer) {
      if (layer) {
        overlayLayers['Embalses'] = layer;
      }
    })
  );

  // Humedales
  promesas.push(
    cargarGeoJSON('data/humedales.geojson', {
      style: P.humedal(),
      onEachFeature: popupNombre(['DS_HUMEDAL', 'DS_ZONA', 'NOMBRE', 'name'])
    }).then(function (layer) {
      if (layer) {
        overlayLayers['Humedales'] = layer;
      }
    })
  );

  /* --- ESPACIOS PROTEGIDOS --- */

  // ZEC / LIC
  promesas.push(
    cargarGeoJSON('data/zec_lic.geojson', {
      style: P.zecLic(),
      onEachFeature: popupNombre(['DS_ZEC_NAME', 'DS_NOMBRE', 'NOMBRE', 'name'])
    }).then(function (layer) {
      if (layer) {
        overlayLayers['ZEC / LIC'] = layer;
      }
    })
  );

  // ZEPA (puntitos)
  promesas.push(
    cargarGeoJSON('data/zepa.geojson', {
      style: P.zepa(),
      onEachFeature: popupNombre(['DS_ZEPA', 'DS_NOMBRE', 'NOMBRE', 'name'])
    }).then(function (layer) {
      if (layer) {
        overlayLayers['ZEPA'] = layer;
      }
    })
  );

  // Parque Nacional Guadarrama
  // El GeoJSON contiene 2 features: CD_ZONA="PN" (parque nacional) y CD_ZONA="ZPP" (zona periférica).
  // El PN se pinta con relleno rojo cedro sólido. La ZPP solo con contorno fino discontinuo.
  promesas.push(
    fetch('data/pn_guadarrama.geojson')
      .then(function (resp) {
        if (!resp.ok) throw new Error('HTTP ' + resp.status);
        return resp.json();
      })
      .then(function (data) {
        if (!data.features || data.features.length === 0) {
          console.warn('[mapa] Sin features en pn_guadarrama.geojson');
          return null;
        }
        var layer = L.geoJSON(data, {
          style: function (feature) {
            var cd = (feature.properties && feature.properties.CD_ZONA) || '';
            if (cd === 'PN') return P.parqueNacional();
            return P.zonaPerifericaProteccion();
          },
          onEachFeature: function (feature, lyr) {
            var props = feature.properties || {};
            var nombre = props.DS_ZONA || '(sin nombre)';
            lyr.bindPopup('<strong>' + nombre + '</strong>');
          }
        });
        return layer;
      })
      .then(function (layer) {
        if (layer) {
          overlayLayers['Parque Nacional Guadarrama'] = layer;
        }
      })
      .catch(function (err) {
        console.error('[mapa] Error cargando pn_guadarrama.geojson', err);
      })
  );

  // Parques Regionales (relleno sólido tenue + contorno, color por parque)
  promesas.push(
    cargarGeoJSON('data/parques_regionales.geojson', {
      style: function (feature) {
        var nombre = (feature.properties && feature.properties.parque) || '';
        return P.parqueRegional(nombre);
      },
      onEachFeature: function (feature, layer) {
        var props = feature.properties || {};
        var nombre = props.parque || '(sin nombre)';
        layer.bindPopup('<strong>' + nombre + '</strong>');
      }
    }).then(function (layer) {
      if (layer) {
        overlayLayers['Parques Regionales'] = layer;
      }
    })
  );

  /* --- ADMINISTRATIVO --- */

  // Comarcas Forestales (línea negra gruesa)
  // DS_COMARCA contiene el número de comarca (e.g. "7"); DS_NOMBRE contiene el nombre completo.
  promesas.push(
    cargarGeoJSON('data/comarcas_forestales.geojson', {
      style: P.comarcaForestal(),
      onEachFeature: function (feature, layer) {
        var props = feature.properties || {};
        var num = props.DS_COMARCA || '';
        var nombre = props.DS_NOMBRE || '(sin nombre)';
        var texto = num
          ? 'Comarca Forestal n&ordm; ' + num + ' &mdash; ' + nombre
          : nombre;
        layer.bindPopup('<strong>' + texto + '</strong>');
      }
    }).then(function (layer) {
      if (layer) {
        overlayLayers['Comarcas Forestales'] = layer;
      }
    })
  );

  // Límites Municipales (trazo gris dashed)
  promesas.push(
    cargarGeoJSON('data/municipios.geojson', {
      style: P.municipio(),
      onEachFeature: popupNombre(['DS_NOMBRE', 'DS_DESCRIPCION', 'NOMBRE', 'name'])
    }).then(function (layer) {
      if (layer) {
        overlayLayers['Límites Municipales'] = layer;
      }
    })
  );

  /* --- EQUIPAMIENTOS --- */

  // Separar equipamientos por tipo
  promesas.push(
    fetch('data/equipamientos.geojson')
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var tipos = {
          'Centro de Educación Ambiental': { color: '#2196F3', features: [] },
          'Centro de Visitantes':          { color: '#FF9800', features: [] },
          'Oficina Comarcal':              { color: '#9C27B0', features: [] }
        };

        (data.features || []).forEach(function (f) {
          var tipo = (f.properties || {}).tipo;
          if (tipos[tipo]) tipos[tipo].features.push(f);
        });

        Object.keys(tipos).forEach(function (tipo) {
          var cfg = tipos[tipo];
          if (!cfg.features.length) return;

          var fc = { type: 'FeatureCollection', features: cfg.features };
          var layer = L.geoJSON(fc, {
            pointToLayer: function (feature, latlng) {
              return L.marker(latlng, { icon: iconoEquipamiento(cfg.color) });
            },
            onEachFeature: popupEquipamiento
          });

          overlayLayers[tipo + 's'] = layer;
        });
      })
      .catch(function (err) {
        console.error('[mapa] Error cargando equipamientos:', err);
      })
  );

  /* ── 9. CONTROL DE CAPAS ──────────────────────────────── */
  Promise.all(promesas).then(function () {
    // Orden explícito según la leyenda (AGUAS → PROTEGIDOS → ADMINISTRATIVO → EQUIPAMIENTOS)
    var ORDEN_OVERLAYS = [
      'Ríos',
      'Arroyos',
      'Embalses',
      'Humedales',
      'ZEC / LIC',
      'ZEPA',
      'Parque Nacional Guadarrama',
      'Parques Regionales',
      'Comarcas Forestales',
      'Límites Municipales',
      'Centro de Educación Ambientals',
      'Centro de Visitantess',
      'Oficina Comarcals'
    ];
    var overlaysOrdenado = {};
    ORDEN_OVERLAYS.forEach(function (k) {
      if (overlayLayers[k]) overlaysOrdenado[k] = overlayLayers[k];
    });
    // Añadir al final cualquier capa que exista y no esté en el orden (salvaguarda)
    Object.keys(overlayLayers).forEach(function (k) {
      if (!(k in overlaysOrdenado)) overlaysOrdenado[k] = overlayLayers[k];
    });

    L.control.layers(baseLayers, overlaysOrdenado, {
      collapsed: true,
      position: 'topright'
    }).addTo(map);

    console.log('[mapa] Capas cargadas:', Object.keys(overlaysOrdenado));
  });

  /* ── 10. LEYENDA INTERACTIVA (plegar) ──────────────── */
  document.addEventListener('DOMContentLoaded', function () {
    var btn = document.getElementById('btn-leyenda-toggle');
    var body = document.getElementById('leyenda-body');
    if (btn && body) {
      btn.addEventListener('click', function () {
        body.classList.toggle('hidden');
        btn.textContent = body.classList.contains('hidden') ? '+' : '−';
      });
    }
  });

  // Si el DOM ya cargó (script al final del body), ejecutar ahora
  if (document.readyState !== 'loading') {
    var btn = document.getElementById('btn-leyenda-toggle');
    var body = document.getElementById('leyenda-body');
    if (btn && body) {
      // En móvil la leyenda arranca plegada
      if (window.matchMedia('(max-width: 600px)').matches) {
        body.classList.add('hidden');
        btn.textContent = '+';
      }
      btn.addEventListener('click', function () {
        body.classList.toggle('hidden');
        btn.textContent = body.classList.contains('hidden') ? '+' : '−';
      });
    }
  }

})();
