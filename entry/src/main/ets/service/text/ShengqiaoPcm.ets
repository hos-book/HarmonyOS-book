/** PCM container and segmentation adapted from shengqiao-hap HuaweiTts.ets. */
function isCn(d: Uint8Array, p: number): boolean {
  return p + 2 < d.length && d[p] >= 0xE4 && d[p] <= 0xEF &&
    d[p + 1] >= 0x80 && d[p + 1] <= 0xBF && d[p + 2] >= 0x80 && d[p + 2] <= 0xBF;
}

function findSegments(d: Uint8Array): number[] {
  const marks: number[] = [0];
  for (let i = 200; i + 26 < d.length; i++) {
    if (d[i] === 0x02 && d[i + 1] === 0x00) {
      let q = i + 8;
      let cn = 0;
      while (q + 2 < d.length && isCn(d, q)) {
        cn++;
        q += 3;
        if (cn >= 2) {
          break;
        }
      }
      if (cn >= 2 && i > marks[marks.length - 1] + 200) {
        marks.push(i);
        continue;
      }
      
      let q2 = i + 8;
      let run = 0;
      while (q2 < d.length && d[q2] >= 32 && d[q2] < 127) {
        run++;
        q2++;
        if (run >= 6) {
          break;
        }
      }
      if (run >= 6 && i > marks[marks.length - 1] + 200) {
        marks.push(i);
      }
    }
  }
  return marks;
}

function isHeader(d: Uint8Array, p: number): boolean {
  if (p + 8 > d.length || d[p] !== 0 || (d[p + 1] !== 0 && d[p + 1] !== 2)) {
    return false;
  }
  const m = (d[p + 2] << 8) | d[p + 3];
  return m === 0x0C81 || m === 0x3E81 || m === 0x0641 || m === 0x2F81 || m === 0x8701;
}

class Chunk {
  pcm: Uint8Array = new Uint8Array(0);
  blocks: number = 0;
  hasMp3: boolean = false;
}

function trimAnnotation(d: Uint8Array, s: number, e: number): number {
  const floor = Math.max(s, e - 8192);
  let last = -1;
  for (let i = e - 1; i >= floor; i--) {
    if (d[i] === 0) {
      last = i;
      break;
    }
  }
  if (last < 0) {
    return e;
  }
  let bars = 0;
  let digits = 0;
  let hasZero = false;
  for (let i = last + 1; i < e; i++) {
    const b = d[i];
    if (b === 0) {
      hasZero = true;
      break;
    }
    if (b === 0x7C) {
      bars++;
    } else if (b >= 0x30 && b <= 0x39) {
      digits++;
    }
  }
  if (!hasZero && bars >= 2 && digits >= 2 && e - (last + 1) >= 8) {
    return last + 1;
  }
  return e;
}

function cutInternalAnnotations(d: Uint8Array, start: number, end: number): Uint8Array {
  const keep: Uint8Array[] = [];
  let last = start;
  let i = start;
  while (i + 1 < end) {
    if (d[i] === 0x7C && d[i + 1] >= 0x30 && d[i + 1] <= 0x39) {
      let s = i;
      while (s > start && d[s - 1] !== 0) {
        s--;
      }
      let e = i;
      while (e < end && d[e] !== 0) {
        e++;
      }
      const len = e - s;
      let ok = false;
      if (len >= 32) {
        let bars = 0;
        let cjk = 0;
        let printable = 0;
        for (let j = s; j < e; j++) {
          if (d[j] === 0x7C) {
            bars++;
          }
          if (d[j] >= 0x20 && d[j] <= 0x7E) {
            printable++;
          }
          if (j + 2 < e && d[j] >= 0xE4 && d[j] <= 0xEF &&
            d[j + 1] >= 0x80 && d[j + 1] <= 0xBF &&
            d[j + 2] >= 0x80 && d[j + 2] <= 0xBF) {
            cjk++;
          }
        }
        ok = bars >= 2 && (cjk >= 2 || printable * 100 >= len * 65);
      }
      if (ok) {
        let kl = s - last;
        if ((kl & 1) === 1) {
          kl--;
        }
        if (kl > 0) {
          keep.push(d.subarray(last, last + kl));
        }
        last = e;
        i = e;
        continue;
      }
    }
    i++;
  }
  let kl = end - last;
  if ((kl & 1) === 1) {
    kl--;
  }
  if (kl > 0) {
    keep.push(d.subarray(last, last + kl));
  }
  let total = 0;
  for (const p of keep) {
    total += p.length;
  }
  const out = new Uint8Array(total);
  let off = 0;
  for (const p of keep) {
    out.set(p, off);
    off += p.length;
  }
  return out;
}

function stripHeaders(d: Uint8Array, start: number): Chunk {
  let hasMp3 = false;
  const cands: number[] = [];
  for (let i = start; i + 8 < d.length; i++) {
    if (isHeader(d, i)) {
      cands.push(i);
    }
  }
  if (cands.length === 0) {
    
    const cut = cutInternalAnnotations(d, start, d.length);
    const e = trimAnnotation(cut, 0, cut.length);
    if (e < cut.length) {
      const n = ((e & 1) === 1) ? e - 1 : e;
      return { pcm: cut.subarray(0, n), blocks: 0, hasMp3: false };
    }
    return { pcm: cut, blocks: 0, hasMp3: false };
  }

  const gapOk = (gap: number): boolean => {
    return gap >= 408 && gap <= 20008 && ((gap - 8) % 400) === 0;
  };
  const real: boolean[] = [];
  for (let i = 0; i < cands.length; i++) {
    const h = cands[i];
    const suf = ((d[h + 4] << 24) | (d[h + 5] << 16) | (d[h + 6] << 8) | d[h + 7]) >>> 0;
    let ok = i === 0 || cands.length === 1;  
    if (i > 0) {
      const gap = h - cands[i - 1];
      const ps = ((d[cands[i - 1] + 4] << 24) | (d[cands[i - 1] + 5] << 16) |
        (d[cands[i - 1] + 6] << 8) | d[cands[i - 1] + 7]) >>> 0;
      if (gapOk(gap) || ps === suf) {
        ok = true;
      }
    }
    if (i + 1 < cands.length) {
      const gap = cands[i + 1] - h;
      const ns = ((d[cands[i + 1] + 4] << 24) | (d[cands[i + 1] + 5] << 16) |
        (d[cands[i + 1] + 6] << 8) | d[cands[i + 1] + 7]) >>> 0;
      if (gapOk(gap) || ns === suf) {
        ok = true;
      }
    }
    real.push(ok);
  }
  const hs: number[] = [];
  for (let i = 0; i < cands.length; i++) {
    if (real[i]) {
      hs.push(cands[i]);
    }
  }
  if (hs.length === 0) {
    return { pcm: d.subarray(start), blocks: 0, hasMp3: false };
  }
  const parts: Uint8Array[] = [];
  let total = 0;

  let firstPcmFam = -1;
  for (let i = 0; i < hs.length; i++) {
    const h = hs[i];
    let s = h + 8;
    let e = i + 1 < hs.length ? hs[i + 1] : d.length;
    e = trimAnnotation(d, s, e);
    if (i + 1 === hs.length) {
      const tail = d.length - 16;
      if (tail > s && d[tail] === 0 && d[tail + 8] === 0x0F) {
        e = Math.min(e, tail);
      } else {
        
        const st = d.length - 7;
        if (st > s && d[st] === 0 && d[st + 1] === 0 && d[st + 2] === 0 &&
          d[st + 3] === 0x03 && d[st + 4] === 0 && d[st + 5] === 0 && d[st + 6] === 0) {
          e = Math.min(e, st);
        }
      }
    }
    if (e < s) {
      continue;
    }
    const magic = (d[h + 2] << 8) | d[h + 3];
    if (magic === 0x8701) {

      hasMp3 = true;
      continue;
    }
    if (magic === 0x0641 && firstPcmFam !== -1 && firstPcmFam !== 2) {

      continue;
    }
    const fam = magic === 0x0C81 || magic === 0x3E81 ? 0 : (magic === 0x2F81 ? 1 : (magic === 0x0641 ? 2 : -1));
    if (fam >= 0) {
      if (firstPcmFam === -1) {
        firstPcmFam = fam;
      }
      if (fam !== firstPcmFam) {
        continue;
      }
    }
    if (((e - s) & 1) === 1) {
      e--;
    }
    if (e <= s) {
      continue;
    }
    parts.push(d.subarray(s, e));
    total += e - s;
  }
  const pcm = new Uint8Array(total);
  let off = 0;
  for (const p of parts) {
    pcm.set(p, off);
    off += p.length;
  }
  return { pcm, blocks: hs.length, hasMp3 };
}

export class ParsedContainer {
  pcm: Uint8Array | null = null;
  hasMp3: boolean = false;
}

function parseTlvPcm(d: Uint8Array): Uint8Array | null {
  let pos = 0;
  const parts: Uint8Array[] = [];
  let total = 0;
  let audioSeen = false;
  while (pos + 8 <= d.length) {
    const b0 = d[pos];
    const b1 = d[pos + 1];
    const b2 = d[pos + 2];
    const b3 = d[pos + 3];
    const err = b0 >> 4;
    const type = b0 & 0x0F;
    const clen = (b1 << 14) | (b2 << 6) | (b3 >> 2);
    if (err !== 0 || clen === 0) {
      break;
    }
    const end = pos + 8 + clen;
    if (end > d.length) {
      break;
    }
    if (type === 0) {
      const payload = d.subarray(pos + 8, end);
      
      if (!audioSeen && payload.length >= 2 && payload[0] === 0xFF &&
        (payload[1] & 0xE0) === 0xE0) {
        return null;
      }
      parts.push(payload);
      total += payload.length;
      audioSeen = true;
    }
    pos = end;
  }
  if (!audioSeen || pos < d.length - 16) {
    return null;
  }
  const pcm = new Uint8Array(total);
  let off = 0;
  for (const p of parts) {
    pcm.set(p, off);
    off += p.length;
  }
  let len = pcm.length;
  if (len >= 16 && pcm[len - 8] === 0x0F) {
    len -= 16;
  }
  if (len % 2 === 1) {
    len--;
  }
  return pcm.subarray(0, len);
}

export function parseContainerInfo(d: Uint8Array, _sampleRate: number): ParsedContainer {
  const tlv = parseTlvPcm(d);
  if (tlv !== null) {
    return { pcm: tlv, hasMp3: false };
  }
  let hasMp3 = false;
  const marks = findSegments(d);
  const bounds: number[] = marks.slice();
  bounds.push(d.length);
  const parts: Uint8Array[] = [];
  for (let i = 0; i < bounds.length - 1; i++) {
    const seg = d.subarray(bounds[i], bounds[i + 1]);
    if (seg.length < 12) {
      continue;
    }
    const nchars = (seg[4] << 24) | (seg[5] << 16) | (seg[6] << 8) | seg[7];
    let pos = 8;
    if (nchars > 0 && nchars < 500000) {
      let cnt = 0;
      while (cnt < nchars && pos < seg.length) {
        const b = seg[pos];
        const step = b < 0x80 ? 1 : b < 0xE0 ? 2 : b < 0xF0 ? 3 : 4;
        pos += step;
        cnt++;
      }
    } else {
      let q = 8;
      while (q < seg.length && seg[q] !== 0x7C) {
        q++;
      }
      pos = q;
    }
    let p = pos;
    while (p < seg.length && (seg[p] === 0x7C || seg[p] === 0x20 || (seg[p] >= 0x30 && seg[p] <= 0x39) || (seg[p] >= 0x41 && seg[p] <= 0x7A))) {
      p++;
    }
    const c = stripHeaders(seg, p);
    if (c.hasMp3) {
      hasMp3 = true;
    }
    if (c.pcm.length > 0) {
      parts.push(c.pcm);
    }
  }
  if (parts.length === 0) {
    return { pcm: null, hasMp3 };
  }
  let total = 0;
  for (const p of parts) {
    total += p.length;
  }
  const pcm = new Uint8Array(total);
  let off = 0;
  for (const p of parts) {
    pcm.set(p, off);
    off += p.length;
  }
  
  let len = pcm.length;
  if (len >= 16 && pcm[len - 16] === 0 && pcm[len - 9] === 0 &&
    pcm[len - 8] === 0x0F && pcm[len - 1] === 0) {
    len -= 16;
  }
  if (len % 2 === 1) {
    len--;
  }
  return { pcm: pcm.subarray(0, len), hasMp3 };
}

export function shengqiaoWave(pcm: Uint8Array, rate: number): ArrayBuffer {
  const total = 44 + pcm.length;
  const buf = new ArrayBuffer(total);
  const v = new DataView(buf);
  const w = (o: number, s: string): void => {
    for (let i = 0; i < s.length; i++) {
      v.setUint8(o + i, s.charCodeAt(i) & 0xff);
    }
  };
  w(0, 'RIFF');
  v.setUint32(4, total - 8, true);
  w(8, 'WAVE');
  w(12, 'fmt ');
  v.setUint32(16, 16, true);
  v.setUint16(20, 1, true);
  v.setUint16(22, 1, true);
  v.setUint32(24, rate, true);
  v.setUint32(28, rate * 2, true);
  v.setUint16(32, 2, true);
  v.setUint16(34, 16, true);
  w(36, 'data');
  v.setUint32(40, pcm.length, true);
  new Uint8Array(buf).set(pcm, 44);
  return buf;
}
export function splitForTts(text: string, maxLen: number, minTotal: number): string[] {
  if (text.length <= minTotal) {
    return [text];
  }

  const FIRST = 30;
  const out: string[] = [];
  let buf = '';
  let inQuote = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text.charAt(i);
    buf += ch;

    if (ch === '“' || ch === '「' || ch === '『') {
      inQuote = true;
    } else if (ch === '”' || ch === '」' || ch === '』') {
      inQuote = false;
    } else if (ch === '"') {
      
      inQuote = !inQuote;
    }
    const limit = out.length === 0 ? FIRST : maxLen;
    const isEnd = ch === '。' || ch === '！' || ch === '？' || ch === '；' || ch === '…';

    const canCut = !inQuote || buf.length >= limit * 2;
    if (canCut && isEnd && buf.length >= (out.length === 0 ? 14 : 24)) {
      out.push(buf);
      buf = '';
    } else if (canCut && buf.length >= limit) {

      let cut = -1;
      const floor = Math.floor(limit * 0.55);
      for (let j = buf.length - 1; j >= floor; j--) {
        if ('。！？；…，、,：:'.indexOf(buf.charAt(j)) >= 0) {
          cut = j + 1;
          break;
        }
      }
      if (cut > 0) {
        out.push(buf.substring(0, cut));
        buf = buf.substring(cut);
      } else {
        out.push(buf);
        buf = '';
      }
    }
  }
  if (buf.length > 0) {
    
    if (out.length > 0 && buf.length < 12) {
      out[out.length - 1] += buf;
    } else {
      out.push(buf);
    }
  }
  
  for (let k = 0; k + 1 < out.length; k++) {
    const opens = countChar(out[k], '“') + countChar(out[k], '「') + countChar(out[k], '『');
    const closes = countChar(out[k], '”') + countChar(out[k], '」') + countChar(out[k], '』');
    if (opens > closes) {
      let j = 0;
      while (j < out[k + 1].length && '”」』'.indexOf(out[k + 1].charAt(j)) >= 0) {
        j++;
      }
      if (j > 0) {
        out[k] += out[k + 1].substring(0, j);
        out[k + 1] = out[k + 1].substring(j);
      }
    }
  }
  return out.length > 1 ? out : [text];
}

function countChar(s: string, c: string): number {
  let n = 0;
  for (let i = 0; i < s.length; i++) {
    if (s.charAt(i) === c) {
      n++;
    }
  }
  return n;
}

function fadeEdge(pcm: Uint8Array, sr: number, ms: number): Uint8Array {
  const n = pcm.length >> 1;
  if (n < 8) {
    return pcm;
  }
  const x = new Int16Array(pcm.buffer, pcm.byteOffset, n);
  const f = Math.min(n >> 1, Math.max(1, Math.round(sr * ms / 1000)));
  for (let i = 0; i < f; i++) {
    const g = 0.5 - 0.5 * Math.cos(Math.PI * i / f);
    x[i] = Math.round(x[i] * g);
    x[n - 1 - i] = Math.round(x[n - 1 - i] * g);
  }
  return pcm;
}

export function concatPcm(parts: Uint8Array[], sr: number, gapMs: number): Uint8Array {
  if (parts.length === 0) {
    return new Uint8Array(0);
  }
  if (parts.length === 1) {
    return parts[0];
  }
  const gap = Math.round(sr * gapMs / 1000) * 2;

  const leadKeep = Math.round(sr * 0.15);
  const tailKeep = Math.round(sr * 0.12);
  const trimmed: Uint8Array[] = [];
  let total = 0;
  for (let k = 0; k < parts.length; k++) {
    const p = parts[k];
    const n = p.length >> 1;
    const x = new Int16Array(p.buffer, p.byteOffset, n);
    let start = 0;
    if (k > 0) {
      for (let i = 0; i < n; i++) {
        if (x[i] > 60 || x[i] < -60) {
          start = Math.max(0, i - leadKeep);
          break;
        }
        if (i > Math.round(sr * 0.6)) {
          start = 0;   
          break;
        }
      }
    }
    
    let end = n;
    for (let i = n - 1; i >= 0; i--) {
      if (x[i] > 98 || x[i] < -98) {
        end = Math.min(n, i + tailKeep);
        break;
      }
      if (i < n - Math.round(sr * 0.8)) {
        end = n;
        break;
      }
    }
    
    if (end - start < Math.round(sr * 0.1)) {
      start = 0;
      end = n;
    }
    const cut = p.subarray(start * 2, end * 2);
    fadeEdge(cut, sr, 8);
    trimmed.push(cut);
    total += cut.length + gap;
  }
  const out = new Uint8Array(total);
  let off = 0;
  for (let k = 0; k < trimmed.length; k++) {
    const t = trimmed[k];
    out.set(t, off);
    off += t.length;
    if (k < trimmed.length - 1) {
      off += gap;   
    }
  }
  return out.subarray(0, off);
}

