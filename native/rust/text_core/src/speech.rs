use crate::{js_space, reader::trim};

pub struct Segment {
    pub start: usize,
    pub end: usize,
    pub text: Vec<u16>,
    pub leading: usize,
    pub paragraph_start: usize,
    pub paragraph_end: usize,
}

fn image_spaces(input: &[u16]) -> Vec<u16> {
    let mut output = input.to_vec();
    let mut at = 0;
    while at < input.len() {
        if input[at] == 0xfff9 {
            let mut end = at + 1;
            while end < input.len() && end - at <= 1024 && !matches!(input[end], 0xfff9 | 0xfffb | 10) { end += 1; }
            if end > at + 1 && end - at <= 1025 && input.get(end) == Some(&0xfffb) {
                output[at..=end].fill(32);
                at = end + 1;
                continue;
            }
        }
        at += 1;
    }
    output
}

fn symbol(c: u16) -> bool {
    matches!(c, 0x0000..=0x0008 | 0x000b | 0x000c | 0x000e..=0x001f | 0x007f..=0x009f |
        0x200b..=0x200f | 0x202a..=0x202e | 0x2060..=0x206f | 0xfeff) ||
        "*＊﹡※☆★◆◇■□●○◎▲△▼▽━─═".encode_utf16().any(|v| v == c)
}

pub fn spoken(input: &[u16], filter: bool) -> Vec<u16> {
    if !filter { return trim(input).to_vec(); }
    let mut stripped = Vec::with_capacity(input.len());
    let mut at = 0;
    while at < input.len() {
        if matches!(input[at], 91 | 0x3010) {
            let close = if input[at] == 91 { 93 } else { 0x3011 };
            let mut end = at + 1;
            while end < input.len() && js_space(input[end]) { end += 1; }
            let first = end;
            while end < input.len() && end - first < 4 && (48..=57).contains(&input[end]) { end += 1; }
            if end > first {
                while end < input.len() && js_space(input[end]) { end += 1; }
                if input.get(end) == Some(&close) { at = end + 1; continue; }
            }
        }
        stripped.push(input[at]);
        at += 1;
    }
    let mut output = Vec::with_capacity(stripped.len());
    at = 0;
    while at < stripped.len() {
        let c = stripped[at];
        if symbol(c) {
            while at < stripped.len() && symbol(stripped[at]) { at += 1; }
            output.push(32);
        } else if "~～_=#＃|｜".encode_utf16().any(|v| v == c) {
            let first = at;
            while at < stripped.len() && "~～_=#＃|｜".encode_utf16().any(|v| v == stripped[at]) { at += 1; }
            if at - first >= 3 { output.push(32); } else { output.extend_from_slice(&stripped[first..at]); }
        } else { output.push(c); at += 1; }
    }
    trim(&output).to_vec()
}

fn word_boundary(input: &[u16], start: usize, end: usize) -> usize {
    for offset in (start + 1..=end).rev() {
        if (input.get(offset).is_some_and(|&c| js_space(c)) ||
            "，,、：:".encode_utf16().any(|c| c == input[offset - 1])) && !trim(&input[start..offset]).is_empty() {
            return offset;
        }
    }
    end
}

pub fn split(input: &[u16], boundaries: &[u32], filter: bool, max_length: usize, hard_limit: usize) -> Vec<Segment> {
    let content = image_spaces(input);
    let mut boundaries = boundaries.to_vec();
    boundaries.sort_unstable();
    let boundary_at = |offset: usize| boundaries.binary_search(&(offset as u32)).is_ok();
    let mut result = Vec::new();
    let mut start = 0;
    let mut paragraph_start = 0;
    let mut paragraph_end = content.iter().position(|&c| c == 10).unwrap_or(content.len());
    let mut i = 0;
    while i < content.len() {
        let c = content[i];
        let boundary = boundary_at(i + 1) || "。！？!?；;\n".encode_utf16().any(|v| v == c) ||
            (c == 46 && (i + 1 == content.len() || js_space(content[i + 1])));
        let high_surrogate = (0xd800..=0xdbff).contains(&c);
        let limit = i - start + 1 >= max_length && (!high_surrogate || i - start + 1 >= hard_limit);
        if boundary || limit || i + 1 == content.len() {
            let mut end = i + 1;
            if limit && !boundary && end < content.len() {
                if high_surrogate { end -= 1; }
                end = word_boundary(&content, start, end);
            }
            while end < content.len() && end - start < hard_limit && !boundary_at(end) &&
                "。！？!?；;”’」』）".encode_utf16().any(|v| v == content[end]) { end += 1; }
            let raw = &content[start..end];
            let leading = raw.iter().position(|&v| !js_space(v)).unwrap_or(0);
            let text = spoken(raw, filter);
            if !text.is_empty() {
                let read_start = start + leading;
                while read_start >= paragraph_end && paragraph_end < content.len() {
                    paragraph_start = paragraph_end + 1;
                    paragraph_end = content[paragraph_start..].iter().position(|&v| v == 10)
                        .map_or(content.len(), |n| paragraph_start + n);
                }
                result.push(Segment { start, end, text, leading, paragraph_start, paragraph_end });
            }
            start = end;
            i = end;
        } else { i += 1; }
    }
    result
}
