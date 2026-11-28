#!/usr/bin/env node
'use strict';

// Paint the Kaohsiung map on a 2x2 pixel grid. The shared district lines are from
// the MOI township boundaries (see import_boundaries.py); the four town masks
// are painted from the same grid and aligned by layout.json.
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const { land, districts } = require('./kaohsiung_boundaries.json');

const OUT = __dirname;
const DOT = 2;
const GW = 740;
const GH = 810;
const K = 700;
const LON0 = 120.04;
const LAT1 = 23.548;
const LON_SCALE = Math.cos(23 * Math.PI / 180);
const CODES = { '64000010': 'yancheng', '64000020': 'gushan', '64000030': 'zuoying', '64000040': 'nanzih' };
const dot = ([lon, lat]) => [(lon - LON0) * K * LON_SCALE, (LAT1 - lat) * K];
const trace = points => points.map(([lat, lon]) => dot([lon, lat]));
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

const SEA = 0;
const LAND = 1;
const cells = new Uint8Array(GW * GH);
const water = new Uint8Array(cells.length);
const hill = new Uint8Array(cells.length);
const at = (x, y) => y * GW + x;
const inGrid = (x, y) => x >= 0 && x < GW && y >= 0 && y < GH;
const get = (x, y) => inGrid(x, y) ? cells[at(x, y)] : SEA;
const N4 = [[1, 0], [-1, 0], [0, 1], [0, -1]];
const N8 = [...N4, [1, 1], [1, -1], [-1, 1], [-1, -1]];
const frame = (x, y) => x < 3 || y < 3 || x >= GW - 3 || y >= GH - 3;

// Scan at dot centres. Pair crossings across all rings, including holes;
// neighbouring districts use precisely the same edge crossings.
function raster(rings, target, value) {
  const ys = rings.flatMap(ring => ring.map(p => p[1]));
  const first = clamp(Math.ceil(Math.min(...ys) - 0.5), 0, GH);
  const end = clamp(Math.ceil(Math.max(...ys) - 0.5), 0, GH);
  for (let y = first; y < end; y++) {
    const cy = y + 0.5;
    const cuts = [];
    for (const ring of rings) {
      for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        const [ax, ay] = ring[i];
        const [bx, by] = ring[j];
        if ((ay > cy) !== (by > cy)) {
          cuts.push(ay < by ? ax + (cy - ay) * (bx - ax) / (by - ay) : bx + (cy - by) * (ax - bx) / (ay - by));
        }
      }
    }
    cuts.sort((a, b) => a - b);
    for (let i = 0; i + 1 < cuts.length; i += 2) {
      const left = clamp(Math.ceil(cuts[i] - 0.5), 0, GW);
      const right = clamp(Math.ceil(cuts[i + 1] - 0.5), 0, GW);
      target.fill(value, at(left, y), at(right, y));
    }
  }
}

for (const polygon of land) raster(polygon.map(ring => ring.map(dot)), cells, LAND);
districts.forEach((district, i) => {
  for (const polygon of district.polygons) raster(polygon.map(ring => ring.map(dot)), cells, i + 2);
});

// Shoushan, Banpingshan, Lotus Pond and the Love River retain the hand-drawn detail.
raster([trace([[22.672,120.264],[22.668,120.270],[22.660,120.274],[22.650,120.276],
  [22.640,120.274],[22.632,120.268],[22.630,120.261],[22.638,120.255],[22.650,120.2545],[22.662,120.257]])], hill, 1);
raster([trace([[22.6915,120.287],[22.695,120.2915],[22.699,120.300],[22.6985,120.306],
  [22.6945,120.305],[22.691,120.296]])], hill, 1);
raster([trace([[22.679,120.2925],[22.687,120.2945],[22.6875,120.2985],[22.679,120.297]])], water, 1);
const river = trace([[22.612,120.2905],[22.628,120.2905],[22.634,120.2905],[22.640,120.293],
  [22.652,120.297],[22.664,120.301],[22.668,120.312],[22.676,120.322],[22.686,120.332],
  [22.696,120.342],[22.706,120.354]]);
for (let n = 1; n < river.length; n++) {
  const [ax, ay] = river[n - 1];
  const [bx, by] = river[n];
  const steps = Math.ceil(Math.hypot(bx - ax, by - ay) * 2);
  for (let i = 0; i <= steps; i++) {
    const x = Math.floor(ax + (bx - ax) * i / steps);
    const y = Math.floor(ay + (by - ay) * i / steps);
    if (get(x, y) > SEA) water[at(x, y)] = 1;
  }
}

// City clearance picks an interior anchor for each name, including thin and concave districts.
const clearance = new Uint16Array(cells.length);
const coastDistance = new Uint8Array(cells.length).fill(255);
const border = (x, y, test, offsets = N4) => offsets.some(([dx, dy]) => test(x + dx, y + dy));
function spread(distance, starts, visit, max) {
  const queue = [];
  for (let y = 0; y < GH; y++) for (let x = 0; x < GW; x++) {
    if (starts(x, y)) { const i = at(x, y); distance[i] = 1; queue.push(i); }
  }
  for (let head = 0; head < queue.length; head++) {
    const i = queue[head];
    const x = i % GW;
    const y = (i - x) / GW;
    if (distance[i] >= max) continue;
    for (const [dx, dy] of N4) {
      const nx = x + dx;
      const ny = y + dy;
      if (!inGrid(nx, ny)) continue;
      const j = at(nx, ny);
      if (distance[j] > distance[i] + 1 && visit(i, j)) { distance[j] = distance[i] + 1; queue.push(j); }
    }
  }
}
clearance.fill(65535);
spread(clearance, (x, y) => border(x, y, (nx, ny) => get(nx, ny) !== get(x, y)),
  (a, b) => cells[a] === cells[b], 65534);
spread(coastDistance, (x, y) => get(x, y) === SEA && border(x, y, (nx, ny) => get(nx, ny) !== SEA),
  (_, b) => cells[b] === SEA, 8);

const hex = h => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16), 255];
const CLEAR = [0, 0, 0, 0];
const C = Object.fromEntries(Object.entries({
  seaDeep: '#5B8BA3', seaDeep2: '#5F90A8', seaMid: '#6C9CB2', seaShallow: '#7FB0C2',
  seaEdge: '#3F6E85', grid: '#77A5BA', land: '#ADAA91', land2: '#B1AE96',
  border: '#876C50', cityEdge: '#6B4A2E', town: '#ECDDB8', shore: '#C8AE80', river: '#6A9DB4',
  hill: '#9DB47A', hillEdge: '#5E7446', frame: '#4A3322', frameInner: '#8A6A48',
  maskRim: '#FFFFFF', maskFill: '#D6D6D6',
}).map(([key, value]) => [key, hex(value)]));
const plain = ['#DFCDA4', '#E7D9B1', '#D8C898', '#E4D0A7'].map(hex);
const upland = ['#BCCC93', '#B5C68D', '#C8D1A0', '#C1CA92'].map(hex);
const towns = new Set(Object.keys(CODES));
const isTown = k => k >= 2 && towns.has(districts[k - 2].code);

function terrainColor(x, y) {
  if (frame(x, y)) return x < 2 || y < 2 || x >= GW - 2 || y >= GH - 2 ? C.frame : C.frameInner;
  const i = at(x, y);
  const k = cells[i];
  if (k === SEA) {
    const d = coastDistance[i];
    if (d === 1) return C.seaEdge;
    if (d <= 3) return C.seaShallow;
    if (d <= 6) return C.seaMid;
    if ((x % 40 === 0 || y % 40 === 0) && (x + y) % 2 === 0) return C.grid;
    return (x + y) % 2 === 0 ? C.seaDeep : C.seaDeep2;
  }
  if (k >= 2 && border(x, y, (nx, ny) => get(nx, ny) === LAND)) return C.cityEdge;
  if (k >= 2 && border(x, y, (nx, ny) => get(nx, ny) >= 2 && get(nx, ny) !== k)) return C.border;
  if (water[i]) return C.river;
  if (hill[i]) return border(x, y, (nx, ny) => !inGrid(nx, ny) || !hill[at(nx, ny)]) ? C.hillEdge : C.hill;
  if (border(x, y, (nx, ny) => get(nx, ny) === SEA)) return C.shore;
  if (isTown(k)) return C.town;
  if (k >= 2) {
    const code = Number(districts[k - 2].code.slice(-3));
    return (code >= 320 ? upland : plain)[(k + Math.floor(k / 4)) % 4];
  }
  return (x + y) % 2 === 0 ? C.land : C.land2;
}

const inMask = (k, x, y) => inGrid(x, y) && !frame(x, y) && cells[at(x, y)] === k &&
  clearance[at(x, y)] > 1 && !water[at(x, y)] && !hill[at(x, y)];

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

// Project to UI pixels: map centre origin, +Y north. Box coordinates align exactly
// to whole dots so a cropped tint still lands on the terrain when zooming.
const ui = (x, y) => ({ x: x - GW / 2, y: GH / 2 - y });
const layout = { size: { w: GW, h: GH }, towns: {}, places: [] };
const report = [writePng('terrain.png', GW, GH, terrainColor), writePng('crest.png', CG, CG, crestColor)];

districts.forEach(({ code, name }, n) => {
  const k = n + 2;
  const id = CODES[code];
  let x0 = GW, x1 = 0, y0 = GH, y1 = 0, best = 0, bx = 0, by = 0, count = 0;
  for (let y = 0; y < GH; y++) for (let x = 0; x < GW; x++) {
    if (get(x, y) !== k || frame(x, y)) continue;
    if (!id || inMask(k, x, y)) {
      if (clearance[at(x, y)] > best) { best = clearance[at(x, y)]; bx = x + 0.5; by = y + 0.5; }
      x0 = Math.min(x0, x); y0 = Math.min(y0, y);
      x1 = Math.max(x1, x + 1); y1 = Math.max(y1, y + 1);
      count++;
    }
  }
  if (!count) throw new Error(`Missing district on the raster: ${name}`);
  const label = ui(bx, by);
  if (!id) {
    layout.places.push({ code, name, ...label, priority: best });
    return;
  }
  const mask = { ...ui((x0 + x1) / 2, (y0 + y1) / 2), w: x1 - x0, h: y1 - y0 };
  layout.towns[id] = { ...label, dots: count, mask };
  report.push(writePng(`mask_${id}.png`, mask.w, mask.h, (x, y) => {
    x += x0; y += y0;
    if (!inMask(k, x, y)) return CLEAR;
    return border(x, y, (nx, ny) => !inMask(k, nx, ny), N8) ? C.maskRim : C.maskFill;
  }));
});

// Larger districts get first choice of a readable label at low zoom.
layout.places.sort((a, b) => b.priority - a.priority || a.code.localeCompare(b.code));
fs.writeFileSync(path.join(OUT, 'layout.json'), JSON.stringify(layout, null, 2) + '\n');
console.log(report.join('\n'));
