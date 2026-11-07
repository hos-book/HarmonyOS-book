// Real ZIP fixtures and a minimal adapter for the platform's raw DEFLATE/CRC APIs.
const zlib = require('node:zlib');

const platformZlib = {
  CompressFlushMode: { FINISH: 4 }, ReturnStatus: { STREAM_END: 1 },
  async createChecksum() { return { crc32: async (initial, bytes) => zlib.crc32(Buffer.from(bytes), initial) }; },
  async createZip() {
    let output;
    return {
      async inflateInit2(_stream, bits) { if (bits !== -15) throw new Error('Expected raw DEFLATE'); },
      async inflate(stream) {
        const decoded = zlib.inflateRawSync(Buffer.from(stream.nextIn), { maxOutputLength: stream.availableOut });
        new Uint8Array(stream.nextOut).set(decoded);
        output = { totalOut: decoded.length, availableOut: stream.availableOut - decoded.length };
        return 1;
      },
      async getZStream() { return output; }, async inflateEnd() {}
    };
  }
};

function zip(entries, options = {}) {
  const records = Array.from(entries);
  const parts = [], directory = [];
  let offset = 0;
  for (const [name, value] of records) {
    const filename = Buffer.from(name), data = Buffer.from(value);
    const method = options.stored ? 0 : 8;
    const compressed = method ? zlib.deflateRawSync(data) : data;
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50); local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x800, 6); local.writeUInt16LE(method, 8);
    local.writeUInt32LE(zlib.crc32(data), 14); local.writeUInt32LE(compressed.length, 18);
    local.writeUInt32LE(data.length, 22); local.writeUInt16LE(filename.length, 26);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x800, 8); central.writeUInt16LE(method, 10);
    central.writeUInt32LE(zlib.crc32(data), 16); central.writeUInt32LE(compressed.length, 20);
    central.writeUInt32LE(data.length, 24); central.writeUInt16LE(filename.length, 28);
    central.writeUInt32LE(offset, 42);
    parts.push(local, filename, compressed); directory.push(central, filename);
    offset += local.length + filename.length + compressed.length;
  }
  const index = Buffer.concat(directory), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50); end.writeUInt16LE(records.length, 8); end.writeUInt16LE(records.length, 10);
  end.writeUInt32LE(index.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...parts, index, end]);
}

module.exports = { platformZlib, zip };
