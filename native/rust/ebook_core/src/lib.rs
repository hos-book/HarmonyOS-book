pub type DecodeResult<T> = Result<T, u32>;
mod kf8;
pub use kf8::sections as kf8_sections;
const INVALID: u32 = 1;
const SIZE: u32 = 2;
const MAX_DICTIONARY: usize = 32 * 1024 * 1024;

pub fn palmdoc(input: &[u8], capacity: usize) -> DecodeResult<Vec<u8>> {
    let mut output = Vec::with_capacity(capacity);
    let mut cursor = 0;
    while cursor < input.len() {
        let value = input[cursor]; cursor += 1;
        match value {
            1..=8 => {
                let count = value as usize;
                if cursor + count > input.len() || output.len() + count > capacity { return Err(INVALID); }
                output.extend_from_slice(&input[cursor..cursor + count]); cursor += count;
            }
            0x80..=0xbf => {
                if cursor == input.len() { return Err(INVALID); }
                let pair = ((value as usize) << 8) | input[cursor] as usize; cursor += 1;
                let distance = (pair & 0x3fff) >> 3;
                let count = (pair & 7) + 3;
                if distance == 0 || distance > output.len() || output.len() + count > capacity { return Err(INVALID); }
                for _ in 0..count { output.push(output[output.len() - distance]); }
            }
            _ => {
                let count = if value >= 0xc0 { 2 } else { 1 };
                if output.len() + count > capacity { return Err(INVALID); }
                if count == 2 { output.push(32); output.push(value ^ 0x80); }
                else { output.push(value); }
            }
        }
    }
    Ok(output)
}

fn number(input: &[u8], at: usize, length: usize) -> DecodeResult<u32> {
    let bytes = input.get(at..at + length).ok_or(INVALID)?;
    Ok(bytes.iter().fold(0_u32, |value, &byte| value * 256 + byte as u32))
}

struct Phrase { bytes: Vec<u8>, expanded: bool, expanding: bool }

pub struct HuffDecoder {
    prefixes: Vec<u32>,
    minimum: Vec<u32>,
    maximum: Vec<u32>,
    phrases: Vec<Phrase>,
    dictionary_bytes: usize,
    operations: usize,
    capacity: usize,
}

impl HuffDecoder {
    pub fn new(records: &[&[u8]], capacity: usize) -> DecodeResult<Self> {
        if !(2..=256).contains(&records.len()) || !(1..=65535).contains(&capacity) { return Err(INVALID); }
        let header = records[0];
        if header.get(..4) != Some(b"HUFF") || number(header, 4, 4)? != 24 { return Err(INVALID); }
        let prefix_offset = number(header, 8, 4)? as usize;
        let range_offset = number(header, 12, 4)? as usize;
        if prefix_offset < 24 || range_offset < 24 { return Err(INVALID); }
        let mut decoder = Self {
            prefixes: Vec::with_capacity(256), minimum: vec![0], maximum: vec![0],
            phrases: Vec::new(), dictionary_bytes: 0, operations: 0, capacity,
        };
        for index in 0..256 {
            let prefix = number(header, prefix_offset + index * 4, 4)?;
            let length = prefix & 31;
            if length == 0 || (length <= 8 && prefix & 128 == 0) { return Err(INVALID); }
            decoder.prefixes.push(prefix);
        }
        for length in 1..=32 {
            decoder.minimum.push(number(header, range_offset + (length - 1) * 8, 4)?);
            decoder.maximum.push(number(header, range_offset + (length - 1) * 8 + 4, 4)?);
        }
        let mut expected = 0;
        for (record_index, bytes) in records.iter().enumerate().skip(1) {
            if bytes.get(..4) != Some(b"CDIC") || number(bytes, 4, 4)? != 16 { return Err(INVALID); }
            let total = number(bytes, 8, 4)? as usize;
            let bits = number(bytes, 12, 4)?;
            if !(1..=65536).contains(&total) || !(1..=16).contains(&bits) ||
                (record_index > 1 && total != expected) || total <= decoder.phrases.len() { return Err(INVALID); }
            expected = total;
            let entries = (1_usize << bits).min(total - decoder.phrases.len());
            if 16 + entries * 2 > bytes.len() { return Err(INVALID); }
            for index in 0..entries {
                let offset = 16 + number(bytes, 16 + index * 2, 2)? as usize;
                if offset < 16 + entries * 2 { return Err(INVALID); }
                let flags = number(bytes, offset, 2)?;
                let length = (flags & 0x7fff) as usize;
                let phrase = bytes.get(offset + 2..offset + 2 + length).ok_or(INVALID)?;
                decoder.dictionary_bytes += length;
                if decoder.dictionary_bytes > MAX_DICTIONARY { return Err(SIZE); }
                decoder.phrases.push(Phrase { bytes: phrase.to_vec(), expanded: flags & 0x8000 != 0, expanding: false });
            }
        }
        if decoder.phrases.len() != expected { return Err(INVALID); }
        Ok(decoder)
    }

    pub fn unpack(&mut self, input: &[u8]) -> DecodeResult<Vec<u8>> {
        self.operations = 0;
        self.expand(input, 0)
    }

    fn lookahead(input: &[u8], bit: usize) -> u32 {
        let start = bit / 8;
        let mut value = 0_u64;
        for index in 0..5 { value = value * 256 + input.get(start + index).copied().unwrap_or(0) as u64; }
        (value >> (8 - bit % 8)) as u32
    }

    fn expand(&mut self, input: &[u8], depth: usize) -> DecodeResult<Vec<u8>> {
        if depth > 32 { return Err(INVALID); }
        let mut output = Vec::with_capacity(self.capacity);
        let mut bit = 0;
        while bit < input.len() * 8 {
            self.operations += 1;
            if self.operations > 1024 * 1024 { return Err(INVALID); }
            let lookahead = Self::lookahead(input, bit);
            let prefix = self.prefixes[(lookahead >> 24) as usize];
            let mut length = (prefix & 31) as usize;
            let mut code = lookahead >> (32 - length);
            let mut maximum = prefix >> 8;
            if prefix & 128 == 0 {
                while length <= 32 && code < self.minimum[length] {
                    length += 1;
                    if length <= 32 { code = lookahead >> (32 - length); }
                }
                if length > 32 { return Err(INVALID); }
                maximum = self.maximum[length];
            }
            if bit + length > input.len() * 8 { break; }
            bit += length;
            let index = maximum.checked_sub(code).ok_or(INVALID)? as usize;
            let phrase = self.phrases.get(index).ok_or(INVALID)?;
            if !phrase.expanded {
                if phrase.expanding { return Err(INVALID); }
                let bytes = phrase.bytes.clone();
                self.phrases[index].expanding = true;
                let result = self.expand(&bytes, depth + 1);
                self.phrases[index].expanding = false;
                let expanded = result?;
                let size = self.dictionary_bytes - bytes.len() + expanded.len();
                if size > MAX_DICTIONARY { return Err(SIZE); }
                self.phrases[index].bytes = expanded;
                self.phrases[index].expanded = true;
                self.dictionary_bytes = size;
            }
            let bytes = &self.phrases[index].bytes;
            if output.len() + bytes.len() > self.capacity { return Err(INVALID); }
            output.extend_from_slice(bytes);
        }
        Ok(output)
    }
}
