/**
 * patrones.js — Generación de patrones SVG para capas Leaflet
 *
 * Usamos SVG patterns embebidos en elementos <defs> de un SVG oculto
 * y los referenciamos como fillPattern en las opciones de cada capa.
 *
 * Técnica: inyectamos un <svg> con <defs> al DOM y usamos
 * `fill: url(#pattern-id)` en los paths de Leaflet mediante
 * una clase CSS aplicada en el pathOptions.className.
 */

(function () {
  'use strict';

  // SVG con patrones (solo los que siguen en uso)
  const svgPatterns = `
<svg xmlns="http://www.w3.org/2000/svg" width="0" height="0"
     style="position:absolute;overflow:hidden;width:0;height:0;"
     aria-hidden="true">
  <defs>
  </defs>
</svg>`;

  // Inyectar al DOM cuando cargue
  document.addEventListener('DOMContentLoaded', function () {
    const div = document.createElement('div');
    div.innerHTML = svgPatterns;
    document.body.insertBefore(div.firstChild, document.body.firstChild);
  });

  // Exponer estilos de capa al módulo principal
  window.MapaPatrones = {

    /** Polígono sólido genérico */
    solido: function (color, fillOpacity, weight) {
      return {
        color: color,
        weight: weight || 1.5,
        fillColor: color,
        fillOpacity: fillOpacity !== undefined ? fillOpacity : 0.55
      };
    },

    /** ZEPA: relleno naranja sólido tenue */
    zepa: function () {
      return {
        color: '#E65100',
        weight: 1.5,
        fillColor: '#FF8C00',
        fillOpacity: 0.42
      };
    },

    /** Parque Nacional (solo feature PN): rojo cedro sólido tenue */
    parqueNacional: function () {
      return {
        color: '#8B2E2B',
        weight: 1.5,
        fillColor: '#B0413E',
        fillOpacity: 0.42,
        fillRule: 'nonzero'
      };
    },

    /** Zona Periférica de Protección (ZPP): relleno rojo pálido tenue + contorno fino */
    zonaPerifericaProteccion: function () {
      return {
        color: '#C97A7A',
        weight: 1,
        fillColor: '#F0B0B0',
        fillOpacity: 0.30,
        fillRule: 'nonzero'
      };
    },

    /** Parques Regionales: relleno sólido tenue con contorno, 3 colores */
    parqueRegional: function (nombreParque) {
      var paleta = {
        'Parque Regional Cuenca Alta del Manzanares': { fill: '#2e7d32', border: '#1b5e20' },
        'Parque Regional de la Sierra de Guadarrama':  { fill: '#00695c', border: '#004d40' },
        'Parque Regional del Sureste':                 { fill: '#558b2f', border: '#33691e' }
      };
      var col = paleta[nombreParque] || { fill: '#388e3c', border: '#1b5e20' };
      return {
        color: col.border,
        weight: 2,
        fillColor: col.fill,
        fillOpacity: 0.35
      };
    },

    /** Embalses: azul sólido */
    embalse: function () {
      return {
        color: '#1a6fad',
        weight: 1.5,
        fillColor: '#1a6fad',
        fillOpacity: 0.6
      };
    },

    /** Humedales: turquesa sólido */
    humedal: function () {
      return {
        color: '#00838f',
        weight: 1.2,
        fillColor: '#00bcd4',
        fillOpacity: 0.5
      };
    },

    /** Comarcas forestales: línea negra gruesa, sin relleno */
    comarcaForestal: function () {
      return {
        color: '#212121',
        weight: 3,
        fillColor: 'none',
        fillOpacity: 0
      };
    },

    /** Límites municipales: trazo gris dashed */
    municipio: function () {
      return {
        color: '#888888',
        weight: 1,
        dashArray: '5, 5',
        fillColor: 'none',
        fillOpacity: 0
      };
    },

    /** ZEC/LIC: verde sólido */
    zecLic: function () {
      return {
        color: '#388e3c',
        weight: 1.5,
        fillColor: '#4caf50',
        fillOpacity: 0.55
      };
    },

    /** Ríos: línea azul */
    rio: function () {
      return {
        color: '#1565c0',
        weight: 2,
        fillOpacity: 0
      };
    },

    /** Arroyos: línea azul más fina y clara que los ríos */
    arroyo: function () {
      return {
        color: '#4a90d9',
        weight: 1,
        fillOpacity: 0
      };
    }
  };

})();
