#!/usr/bin/env node
'use strict';

// Paints the faction-war world map art (msw-painter, maple cartoon pixel style) straight to PNG.
// Every image is a grid of 2x2-pixel dots: no curves, no gradients, no fractional coordinates.
// The district shapes follow the real Kaohsiung districts (approximate outlines, lat/lon);
// the same grid produces the terrain base, one white mask per district (tinted by owner at runtime)
// and layout.json with each town's node position in UI pixels (map centre origin, +y up).
//
//   node assets/worldmap/paint_worldmap.cjs
//
// Output: assets/worldmap/{terrain,mask_nanzih,mask_zuoying,mask_gushan,mask_yancheng,crest}.png, layout.json

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const OUT = __dirname;
const DOT = 2;            // pixels per dot
const GW = 310;           // dots across  -> 620 px
const GH = 405;           // dots down    -> 810 px

// Equirectangular projection around 22.7N: 1 deg lon = 102.7 km, 1 deg lat = 110.6 km.
const LON0 = 120.225;
const LON1 = 120.365;
const LAT1 = 22.770;
const KX = GW / (LON1 - LON0);
const KY = KX / 102.7 * 110.6;

function dot([lat, lon]) { return [(lon - LON0) * KX, (LAT1 - lat) * KY]; }
const poly = (pts) => pts.map(dot);

// Mainland: the coast from the north, the harbour's north shore, then the map's east edge.
const COAST = poly([
  [22.772, 120.243], [22.760, 120.245], [22.750, 120.248], [22.742, 120.2525], [22.735, 120.255],
  [22.722, 120.262], [22.712, 120.266], [22.7075, 120.265], [22.704, 120.2605], [22.700, 120.259],
  [22.696, 120.2615], [22.690, 120.267], [22.683, 120.268], [22.676, 120.266], [22.670, 120.261],
  [22.660, 120.255], [22.650, 120.252], [22.640, 120.2515], [22.632, 120.254], [22.626, 120.259],
  [22.6205, 120.2635], [22.617, 120.267], [22.6155, 120.272], [22.6165, 120.278], [22.6165, 120.284],
  [22.6155, 120.2905], [22.612, 120.297], [22.607, 120.302], [22.599, 120.305],
  [22.599, 120.367], [22.772, 120.367],
]);
const QIJIN = poly([
  [22.6135, 120.2655], [22.6115, 120.2685], [22.606, 120.2745], [22.599, 120.2810],
  [22.599, 120.2765], [22.604, 120.2715], [22.609, 120.2670],
]);
// Shared borders keep neighbouring districts gap-free; west edges run out to sea and are clipped by the coast.
const NZ = [[22.708, 120.200], [22.708, 120.266], [22.706, 120.285], [22.700, 120.300], [22.703, 120.315], [22.700, 120.328]];
const ZG = [[22.676, 120.200], [22.676, 120.266], [22.672, 120.280], [22.668, 120.292], [22.664, 120.300]];
const Z_EAST = [[22.700, 120.328], [22.685, 120.326], [22.675, 120.318], [22.668, 120.308], [22.664, 120.300]];
const G_EAST = [[22.664, 120.300], [22.652, 120.297], [22.640, 120.293], [22.6315, 120.2905]];
const Y_WEST = [[22.6315, 120.2905], [22.6315, 120.2795], [22.626, 120.2775], [22.618, 120.2775], [22.608, 120.2775]];
const DISTRICTS = {
  nanzih: poly([...NZ, [22.712, 120.336], [22.728, 120.338], [22.742, 120.330], [22.748, 120.312], [22.745, 120.292],
    [22.742, 120.272], [22.740, 120.256], [22.740, 120.200]]),
  zuoying: poly([...NZ, ...Z_EAST.slice(1), ...ZG.slice().reverse().slice(1)]),
  gushan: poly([...ZG, ...G_EAST.slice(1), ...Y_WEST.slice(1), [22.608, 120.200]]),
  yancheng: poly([...Y_WEST, [22.608, 120.2905]]),
};
const HILLS = [
  poly([[22.672, 120.264], [22.668, 120.270], [22.660, 120.274], [22.650, 120.276], [22.640, 120.274], [22.632, 120.268],
    [22.630, 120.261], [22.638, 120.255], [22.650, 120.2545], [22.662, 120.257]]),       // Shoushan
  poly([[22.6915, 120.287], [22.695, 120.2915], [22.699, 120.300], [22.6985, 120.306], [22.6945, 120.305], [22.691, 120.296]]), // Banpingshan
];
const LAKE = poly([[22.679, 120.2925], [22.687, 120.2945], [22.6875, 120.2985], [22.679, 120.297]]); // Lotus Pond
const RIVER = poly([[22.612, 120.2905], [22.628, 120.2905], [22.634, 120.2905], [22.640, 120.293], [22.652, 120.297],
  [22.664, 120.301], [22.668, 120.312], [22.676, 120.322], [22.686, 120.332], [22.696, 120.342], [22.706, 120.354]]); // Love River

function inside(pts, x, y) {
  let hit = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const [xi, yi] = pts[i];
    const [xj, yj] = pts[j];
    if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) hit = !hit;
  }
  return hit;
}

function distanceToLine(pts, x, y) {
  let best = Infinity;
  for (let i = 0; i + 1 < pts.length; i++) {
    const [ax, ay] = pts[i];
    const [bx, by] = pts[i + 1];
    const dx = bx - ax;
    const dy = by - ay;
    const t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)));
    best = Math.min(best, Math.hypot(ax + t * dx - x, ay + t * dy - y));
  }
  return best;
}

// --- classify every dot --------------------------------------------------------
const IDS = ['nanzih', 'zuoying', 'gushan', 'yancheng'];
const SEA = 0;
const LAND = 1;          // 2..5 = IDS[n-2]
const cell = new Uint8Array(GW * GH);
const water = new Uint8Array(GW * GH);   // river or lake on land
const hill = new Uint8Array(GW * GH);
const at = (x, y) => y * GW + x;
for (let y = 0; y < GH; y++) {
  for (let x = 0; x < GW; x++) {
    const cx = x + 0.5;
    const cy = y + 0.5;
    const mainland = inside(COAST, cx, cy);
    let kind = mainland || inside(QIJIN, cx, cy) ? LAND : SEA;
    if (mainland) {
      IDS.forEach((id, n) => { if (kind === LAND && inside(DISTRICTS[id], cx, cy)) kind = n + 2; });
    }
    cell[at(x, y)] = kind;
    if (kind !== SEA) {
      if (inside(LAKE, cx, cy) || distanceToLine(RIVER, cx, cy) <= 0.9) water[at(x, y)] = 1;
      else if (HILLS.some((h) => inside(h, cx, cy))) hill[at(x, y)] = 1;
    }
  }
}

const get = (x, y) => (x < 0 || y < 0 || x >= GW || y >= GH ? -1 : cell[at(x, y)]);
const N4 = [[1, 0], [-1, 0], [0, 1], [0, -1]];
const N8 = [...N4, [1, 1], [1, -1], [-1, 1], [-1, -1]];

// Distance (in dots, 4-neighbour steps) from the sea to the nearest land, capped.
const seaDist = new Uint8Array(GW * GH).fill(255);
{
  const queue = [];
  for (let y = 0; y < GH; y++) for (let x = 0; x < GW; x++) if (cell[at(x, y)] !== SEA) { seaDist[at(x, y)] = 0; queue.push(at(x, y)); }
  for (let head = 0; head < queue.length; head++) {
    const i = queue[head];
    const d = seaDist[i];
    if (d >= 12) continue;
    const x = i % GW;
    const y = (i - x) / GW;
    for (const [dx, dy] of N4) {
      const nx = x + dx;
      const ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= GW || ny >= GH) continue;
      const j = at(nx, ny);
      if (seaDist[j] > d + 1) { seaDist[j] = d + 1; queue.push(j); }
    }
  }
}

// Distance from each hill dot to the hill's edge, and each hill's centre, for stepped shading.
const hillDist = new Uint8Array(GW * GH);
const hillCentre = [];
{
  const queue = [];
  for (let y = 0; y < GH; y++) for (let x = 0; x < GW; x++) {
    if (!hill[at(x, y)]) continue;
    const edge = N4.some(([dx, dy]) => { const nx = x + dx; const ny = y + dy; return nx < 0 || ny < 0 || nx >= GW || ny >= GH || !hill[at(nx, ny)]; });
    hillDist[at(x, y)] = edge ? 1 : 0;
    if (edge) queue.push(at(x, y));
  }
  for (let head = 0; head < queue.length; head++) {
    const i = queue[head];
    const x = i % GW;
    const y = (i - x) / GW;
    for (const [dx, dy] of N4) {
      const j = at(x + dx, y + dy);
      if (hill[j] && hillDist[j] === 0) { hillDist[j] = hillDist[i] + 1; queue.push(j); }
    }
  }
  HILLS.forEach((h) => {
    const xs = h.map((p) => p[0]);
    const ys = h.map((p) => p[1]);
    hillCentre.push({ pts: h, x: (Math.min(...xs) + Math.max(...xs)) / 2, y: (Math.min(...ys) + Math.max(...ys)) / 2 });
  });
}

const hex = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16), 255];
const CLEAR = [0, 0, 0, 0];
const C = {
  seaDeep: hex('#5B8BA3'), seaDeep2: hex('#5F90A8'), seaMid: hex('#6C9CB2'), seaShallow: hex('#7FB0C2'),
  seaEdge: hex('#3F6E85'), grid: hex('#77A5BA'),
  land: hex('#CBB98F'), land2: hex('#C5B289'), landShore: hex('#B39C70'), landBorder: hex('#9A7B56'),
  district: hex('#ECDDB8'), districtShore: hex('#C8AE80'), districtBorder: hex('#6B4A2E'),
  river: hex('#6A9DB4'), riverBank: hex('#4C7C93'),
  hill: hex('#9DB47A'), hillLight: hex('#B6C994'), hillShade: hex('#7E9860'), hillEdge: hex('#5E7446'),
  frame: hex('#4A3322'), frameInner: hex('#8A6A48'),
  maskRim: hex('#FFFFFF'), maskFill: hex('#D6D6D6'),
};

function neighbours(x, y, list, test) { return list.some(([dx, dy]) => test(get(x + dx, y + dy), x + dx, y + dy)); }
const isDistrict = (k) => k >= 2;
const isWater = (x, y) => x >= 0 && y >= 0 && x < GW && y < GH && water[at(x, y)] === 1;
const isHill = (x, y) => x >= 0 && y >= 0 && x < GW && y < GH && hill[at(x, y)] === 1;

function terrainColor(x, y) {
  if (x < 2 || y < 2 || x >= GW - 2 || y >= GH - 2) return C.frame;
  if (x < 3 || y < 3 || x >= GW - 3 || y >= GH - 3) return C.frameInner;
  const k = cell[at(x, y)];
  if (k === SEA) {
    const d = seaDist[at(x, y)];
    if (d <= 1) return C.seaEdge;
    if (d <= 3) return C.seaShallow;
    if (d <= 6) return C.seaMid;
    if ((x % 40 === 0 || y % 40 === 0) && (x + y) % 2 === 0) return C.grid;
    return (x + y) % 2 === 0 ? C.seaDeep : C.seaDeep2;
  }
  if (water[at(x, y)]) {
    return neighbours(x, y, N4, (n, nx, ny) => n > SEA && !isWater(nx, ny)) ? C.riverBank : C.river;
  }
  const coast = neighbours(x, y, N4, (n) => n === SEA);
  if (isDistrict(k) && neighbours(x, y, N4, (n) => n > SEA && n !== k)) return C.districtBorder;
  if (!isDistrict(k) && neighbours(x, y, N4, (n) => isDistrict(n))) return C.landBorder;
  if (hill[at(x, y)]) {
    // Stepped relief: outline, a lit band on the north-west slope, a shaded band on the south-east, then the crest.
    const d = hillDist[at(x, y)];
    if (d <= 1) return C.hillEdge;
    const centre = hillCentre.find((h) => inside(h.pts, x + 0.5, y + 0.5)) || hillCentre[0];
    const northWest = (x - centre.x) + (y - centre.y) < 0;
    if (d <= 4) return northWest ? C.hillLight : C.hillShade;
    if (d >= 9 && (x + y) % 2 === 0) return C.hillLight;
    return C.hill;
  }
  if (isDistrict(k)) return coast ? C.districtShore : C.district;
  if (coast) return C.landShore;
  return (x + y) % 2 === 0 ? C.land : C.land2;
}

// A district's mask covers its plain land: not its border line, coast dots, hills or water.
function inMask(id, x, y) {
  if (x < 3 || y < 3 || x >= GW - 3 || y >= GH - 3) return false;
  const k = IDS.indexOf(id) + 2;
  if (cell[at(x, y)] !== k || water[at(x, y)] || hill[at(x, y)]) return false;
  return !neighbours(x, y, N4, (n) => n !== k);
}

function maskColor(id, x, y) {
  if (!inMask(id, x, y)) return CLEAR;
  return N8.some(([dx, dy]) => !inMask(id, x + dx, y + dy)) ? C.maskRim : C.maskFill;
}

// --- PNG ----------------------------------------------------------------------
const CRC = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; table[n] = c >>> 0; }
  return (buf) => { let c = 0xffffffff; for (const b of buf) c = table[(c ^ b) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
})();
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(CRC(body));
  return Buffer.concat([len, body, crc]);
}
function writePng(file, gw, gh, colorAt) {
  const w = gw * DOT;
  const h = gh * DOT;
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let py = 0; py < h; py++) {
    raw[py * (w * 4 + 1)] = 0;
    for (let px = 0; px < w; px++) {
      const c = colorAt(Math.floor(px / DOT), Math.floor(py / DOT));
      raw.set(c, py * (w * 4 + 1) + 1 + px * 4);
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const png = Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
  fs.writeFileSync(path.isAbsolute(file) ? file : path.join(OUT, file), png);
  return `${file} ${w}x${h} ${png.length}B`;
}

// --- crest: a white shield with a castle, tinted with the owner's colour at runtime ----
const CG = 32;
function crestColor(x, y) {
  const half = (yy) => (yy < 2 || yy > 29 ? -1 : yy <= 17 ? 12 : 12 - (yy - 17));
  const inShield = (xx, yy) => { const w = half(yy); return w >= 0 && xx >= 16 - w && xx <= 15 + w; };
  if (!inShield(x, y)) {
    // selective AA: one soft dot on each outer step of the tapered edge
    if (y > 17 && y <= 29 && (inShield(x + 1, y - 1) || inShield(x - 1, y - 1)) && !inShield(x, y - 1)) return hex('#9A9A9A');
    return CLEAR;
  }
  if (N4.some(([dx, dy]) => !inShield(x + dx, y + dy))) return hex('#3A3A3A');
  const castle = (x >= 11 && x <= 20 && y >= 11 && y <= 21) || (y >= 9 && y <= 10 && [11, 12, 15, 16, 19, 20].includes(x));
  if (castle) {
    if (x >= 15 && x <= 16 && y >= 17) return hex('#4E4E4E');
    if ((x === 13 || x === 18) && y >= 13 && y <= 14) return hex('#4E4E4E');
    return x <= 12 || y <= 10 ? hex('#9C9C9C') : hex('#7E7E7E');
  }
  const w = half(y);
  if (y <= 3 || x <= 16 - w + 1) return hex('#FFFFFF');
  if (x >= 15 + w - 1 || y >= 26) return hex('#BEBEBE');
  return hex('#EAEAEA');
}

// --- layout: node position per town = centre of its mask, in UI px (map centre origin, +y up) ---
function nodeOf(id) {
  let sx = 0; let sy = 0; let n = 0;
  for (let y = 0; y < GH; y++) for (let x = 0; x < GW; x++) if (inMask(id, x, y)) { sx += x + 0.5; sy += y + 0.5; n++; }
  const px = (sx / n) * DOT;
  const py = (sy / n) * DOT;
  return { x: Math.round(px - (GW * DOT) / 2), y: Math.round((GH * DOT) / 2 - py), dots: n };
}

const report = [];
report.push(writePng('terrain.png', GW, GH, terrainColor));
for (const id of IDS) report.push(writePng(`mask_${id}.png`, GW, GH, (x, y) => maskColor(id, x, y)));
report.push(writePng('crest.png', CG, CG, crestColor));
// Neighbouring places the game does not use, as faint map labels.
const PLACES = [
  ['台灣海峽', 22.700, 120.2385], ['梓官', 22.762, 120.262], ['橋頭', 22.764, 120.320], ['仁武', 22.712, 120.354],
  ['三民', 22.648, 120.322], ['壽山', 22.651, 120.264], ['愛河', 22.676, 120.330], ['旗津', 22.603, 120.262],
];
function uiPoint(lat, lon) {
  const [dx, dy] = dot([lat, lon]);
  return { x: Math.round(dx * DOT - (GW * DOT) / 2), y: Math.round((GH * DOT) / 2 - dy * DOT) };
}
const layout = { size: { w: GW * DOT, h: GH * DOT }, towns: {}, places: [] };
for (const id of IDS) layout.towns[id] = nodeOf(id);
for (const [name, lat, lon] of PLACES) layout.places.push({ name, ...uiPoint(lat, lon) });

// Local preview only (not uploaded): the terrain with the four masks tinted like the starting board.
if (process.argv.includes('--preview')) {
  const tint = { nanzih: [200, 70, 60], zuoying: [200, 70, 60], gushan: [60, 111, 200], yancheng: [60, 111, 200] };
  const alpha = 0.5;
  writePng(process.argv[process.argv.indexOf('--preview') + 1], GW, GH, (x, y) => {
    const base = terrainColor(x, y).slice();
    for (const id of IDS) {
      const m = maskColor(id, x, y);
      if (m[3] === 0) continue;
      for (let k = 0; k < 3; k++) base[k] = Math.round(base[k] * (1 - alpha) + (m[k] / 255) * tint[id][k] * alpha);
    }
    return base;
  });
}
fs.writeFileSync(path.join(OUT, 'layout.json'), JSON.stringify(layout, null, 2) + '\n');
console.log(report.join('\n'));
console.log(JSON.stringify(layout));
