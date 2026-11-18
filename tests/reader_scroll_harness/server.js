"use strict";

// Delayed image server for the reader scroll harness.
//
//   GET /image?url=p<i>[&kr=<n>]  -> long-strip page <i> as a grayscale PNG
//
// The first fetch of page <i> waits delays[i] seconds; a later fetch waits
// `refetch`. `fail` maps a page to how many of its first fetches answer 502,
// which is what the reader's retry has to recover from. Every request is
// printed as `REQ <path>` so the runner can check the cache-buster.
//
// PNGs are encoded here with zlib: no Pillow, no fixtures.
//
// Usage: node server.js '<json config>'   (prints `PORT <n>` when listening)

const http = require("node:http");
const zlib = require("node:zlib");

// Real long-strip pages are 800 px wide and 2000-6000 px tall; a quarter of
// that keeps the same height/width ratios with a fraction of the bytes.
const WIDTH = 200;
const HEIGHTS = [500, 1300, 775, 1500, 600, 1200, 900, 1400, 550, 1100, 750, 1250, 650];

const config = JSON.parse(process.argv[2] || "{}");
const delays = config.delays || [0.1, 0.3, 0.6, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5];
const refetch = config.refetch === undefined ? 1.5 : config.refetch;
const fail = config.fail || {};

const CRC_TABLE = (() => {
    const table = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
        table[n] = c >>> 0;
    }
    return table;
})();

function crc32(buf) {
    let c = 0xffffffff;
    for (const byte of buf) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
    const head = Buffer.alloc(8);
    head.writeUInt32BE(data.length, 0);
    head.write(type, 4, "ascii");
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])), 0);
    return Buffer.concat([head, data, crc]);
}

function png(index) {
    const height = HEIGHTS[index];
    const shade = 40 + 15 * index;
    const rows = Buffer.alloc((WIDTH + 1) * height);
    for (let y = 0; y < height; y++) {
        const line = y % 50 === 0 ? 255 : shade;
        rows.fill(line, y * (WIDTH + 1) + 1, (y + 1) * (WIDTH + 1));
    }
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(WIDTH, 0);
    ihdr.writeUInt32BE(height, 4);
    ihdr[8] = 8;  // bit depth
    ihdr[9] = 0;  // grayscale
    return Buffer.concat([
        Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
        chunk("IHDR", ihdr),
        chunk("IDAT", zlib.deflateSync(rows)),
        chunk("IEND", Buffer.alloc(0)),
    ]);
}

const images = HEIGHTS.map((_, i) => png(i));
const seen = new Map();

const server = http.createServer((req, res) => {
    const url = new URL(req.url, "http://127.0.0.1");
    const match = /^p(\d+)$/.exec(url.searchParams.get("url") || "");
    const index = match ? Number(match[1]) : -1;
    if (url.pathname !== "/image" || !(index >= 0 && index < images.length)) {
        res.writeHead(404).end();
        return;
    }
    const n = seen.get(index) || 0;
    seen.set(index, n + 1);
    process.stdout.write(`REQ ${req.url}\n`);
    const delay = n === 0 ? (delays[index] || 0) : refetch;
    setTimeout(() => {
        if (n < (fail[`p${index}`] || 0)) {
            res.writeHead(502, { "Content-Type": "text/plain" }).end("Bad Gateway");
            return;
        }
        res.writeHead(200, { "Content-Type": "image/png", "Content-Length": images[index].length });
        res.end(images[index]);
    }, delay * 1000);
});

server.listen(0, "127.0.0.1", () => {
    process.stdout.write(`PORT ${server.address().port}\n`);
});
