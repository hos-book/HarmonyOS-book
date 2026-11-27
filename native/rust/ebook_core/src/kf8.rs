use super::{number, DecodeResult, INVALID, SIZE};
use std::ops::Range;

const MAX_TEXT: usize = 32 * 1024 * 1024;

struct Entry {
    name: String,
    tags: Vec<(u8, Vec<usize>)>,
}

impl Entry {
    fn value(&self, tag: u8, index: usize) -> DecodeResult<usize> {
        self.tags.iter().rev().find(|entry| entry.0 == tag)
            .and_then(|entry| entry.1.get(index)).copied().ok_or(INVALID)
    }
}

fn signature(bytes: &[u8], at: usize, text: &[u8]) -> DecodeResult<()> {
    if bytes.get(at..at + text.len()) == Some(text) { Ok(()) } else { Err(INVALID) }
}

fn integer(bytes: &[u8], position: &mut usize, end: usize) -> DecodeResult<usize> {
    let mut value = 0;
    for _ in 0..4 {
        if *position >= end { break; }
        let byte = bytes[*position];
        *position += 1;
        value = value * 128 + (byte & 127) as usize;
        if byte & 128 != 0 { return Ok(value); }
    }
    Err(INVALID)
}

fn index(records: &[&[u8]]) -> DecodeResult<Vec<Entry>> {
    let header = *records.first().ok_or(INVALID)?;
    signature(header, 0, b"INDX")?;
    let tag_start = number(header, 4, 4)? as usize;
    signature(header, tag_start, b"TAGX")?;
    let tag_end = tag_start + number(header, tag_start + 4, 4)? as usize;
    let controls = number(header, tag_start + 8, 4)? as usize;
    let count = number(header, 24, 4)? as usize;
    if tag_end > header.len() || !(1..=32).contains(&controls) || count > 4096 ||
        tag_end < tag_start + 12 || (tag_end - tag_start - 12) % 4 != 0 || records.len() != count + 1 {
        return Err(INVALID);
    }
    let tags = &header[tag_start + 12..tag_end];
    let mut result = Vec::new();
    for bytes in &records[1..] {
        signature(bytes, 0, b"INDX")?;
        let table = number(bytes, 20, 4)? as usize;
        let count = number(bytes, 24, 4)? as usize;
        signature(bytes, table, b"IDXT")?;
        if count > 50000 - result.len() || table + 4 + count * 2 > bytes.len() { return Err(INVALID); }
        for row in 0..count {
            let start = number(bytes, table + 4 + row * 2, 2)? as usize;
            let end = if row + 1 < count { number(bytes, table + 6 + row * 2, 2)? as usize } else { table };
            if start >= end || end > table { return Err(INVALID); }
            let name_end = start + 1 + bytes[start] as usize;
            if name_end + controls > end { return Err(INVALID); }
            let mut item = Entry {
                name: String::from_utf8_lossy(&bytes[start + 1..name_end]).into_owned(),
                tags: Vec::with_capacity(tags.len() / 4),
            };
            let mut position = name_end + controls;
            let mut counts = Vec::with_capacity(tags.len() / 4);
            let mut control = 0;
            for tag in tags.chunks_exact(4) {
                if tag[3] & 1 != 0 { control += 1; counts.push((0, None)); continue; }
                if control >= controls || tag[2] == 0 { return Err(INVALID); }
                let mut value = bytes[name_end + control] & tag[2];
                if value == tag[2] && tag[2] & (tag[2] - 1) != 0 {
                    counts.push((0, Some(integer(bytes, &mut position, end)?)));
                } else {
                    let mut mask = tag[2];
                    while mask & 1 == 0 { mask >>= 1; value >>= 1; }
                    counts.push((if value == tag[2] { 1 } else { value as usize }, None));
                }
            }
            for (tag, (count, size)) in tags.chunks_exact(4).zip(counts) {
                if tag[3] & 1 != 0 { continue; }
                let mut values = Vec::new();
                if let Some(size) = size {
                    let until = position + size;
                    if until > end { return Err(INVALID); }
                    while position < until { values.push(integer(bytes, &mut position, end)?); }
                    if position != until { return Err(INVALID); }
                } else {
                    let count = count * tag[1] as usize;
                    if count > end - position { return Err(INVALID); }
                    for _ in 0..count { values.push(integer(bytes, &mut position, end)?); }
                }
                item.tags.push((tag[0], values));
            }
            result.push(item);
        }
    }
    Ok(result)
}

fn insertion(name: &str) -> DecodeResult<usize> {
    let name = name.trim_matches(|c: char| c.is_whitespace() || c == '\u{feff}');
    let value = if name.is_empty() { 0.0 }
        else if name.starts_with("0x") || name.starts_with("0X") {
            u64::from_str_radix(&name[2..], 16).map_err(|_| INVALID)? as f64
        } else if name.starts_with("0b") || name.starts_with("0B") {
            u64::from_str_radix(&name[2..], 2).map_err(|_| INVALID)? as f64
        } else if name.starts_with("0o") || name.starts_with("0O") {
            u64::from_str_radix(&name[2..], 8).map_err(|_| INVALID)? as f64
        } else { name.parse::<f64>().map_err(|_| INVALID)? };
    if value.is_finite() && value >= 0.0 && value.fract() == 0.0 && value <= usize::MAX as f64 {
        Ok(value as usize)
    } else { Err(INVALID) }
}

/// Keep fragment spans until final assembly so each section's body is copied once.
pub fn sections(raw: &[u8], skeleton_records: &[&[u8]], fragment_records: &[&[u8]])
    -> DecodeResult<Vec<Vec<u8>>> {
    let skeletons = index(skeleton_records)?;
    let fragments = index(fragment_records)?;
    let mut fragment_index = 0;
    let mut total = 0;
    let mut output = Vec::with_capacity(skeletons.len());
    for skeleton in skeletons {
        let start = skeleton.value(6, 0)?;
        let length = skeleton.value(6, 1)?;
        let count = skeleton.value(1, 0)?;
        if start + length > raw.len() || count > fragments.len() - fragment_index { return Err(INVALID); }
        let mut spans: Vec<Range<usize>> = vec![start..start + length];
        let mut size = length;
        for fragment in &fragments[fragment_index..fragment_index + count] {
            let insert = insertion(&fragment.name)?.checked_sub(start).ok_or(INVALID)?;
            let from = start + length + fragment.value(6, 0)?;
            let added = fragment.value(6, 1)?;
            if insert > size || from + added > raw.len() || size + added > MAX_TEXT { return Err(INVALID); }
            let mut before = 0;
            for at in 0..spans.len() {
                let span = spans[at].clone();
                if insert <= before + span.len() {
                    let split = span.start + insert - before;
                    spans.splice(at..at + 1, [span.start..split, from..from + added, split..span.end]);
                    break;
                }
                before += span.len();
            }
            size += added;
        }
        fragment_index += count;
        total += size;
        if total > MAX_TEXT { return Err(SIZE); }
        let mut bytes = Vec::with_capacity(size);
        for span in spans { bytes.extend_from_slice(&raw[span]); }
        output.push(bytes);
    }
    if fragment_index != fragments.len() || output.is_empty() { return Err(INVALID); }
    Ok(output)
}
