mod entities;
mod epub_xml;
pub use epub_xml::parse as parse_epub_xml;

pub fn js_space(c: u16) -> bool {
    matches!(c, 0x0009..=0x000d | 0x0020 | 0x00a0 | 0x1680 | 0x2000..=0x200a |
        0x2028 | 0x2029 | 0x202f | 0x205f | 0x3000 | 0xfeff)
}

fn ascii_eq(text: &[u16], pattern: &[u8]) -> bool {
    text.len() == pattern.len() && text.iter().zip(pattern).all(|(&a, &b)| {
        a <= 127 && (a as u8).eq_ignore_ascii_case(&b)
    })
}

fn starts(text: &[u16], at: usize, pattern: &[u8]) -> bool {
    text.get(at..at + pattern.len()).is_some_and(|s| ascii_eq(s, pattern))
}

fn word(c: u16) -> bool {
    c < 128 && ((c as u8).is_ascii_alphanumeric() || c == 95)
}

fn find(text: &[u16], from: usize, pattern: &[u8]) -> Option<usize> {
    (from..text.len()).find(|&at| starts(text, at, pattern))
}

fn tag_end(text: &[u16], from: usize) -> Option<usize> {
    text[from..].iter().position(|&c| c == 62).map(|n| from + n + 1)
}

fn closing(text: &[u16], from: usize, name: &[u8]) -> Option<(usize, usize)> {
    let mut at = from;
    while let Some(start) = find(text, at, b"</") {
        let end_name = start + 2 + name.len();
        if starts(text, start + 2, name) {
            let mut end = end_name;
            while end < text.len() && js_space(text[end]) { end += 1; }
            if text.get(end) == Some(&62) { return Some((start, end + 1)); }
        }
        at = start + 2;
    }
    None
}

fn body(text: &[u16]) -> &[u16] {
    let mut at = 0;
    while let Some(start) = find(text, at, b"<body") {
        let next = start + 5;
        if text.get(next).is_none_or(|&c| !word(c)) {
            if let Some(end) = tag_end(text, next) {
                if let Some((last, _)) = closing(text, end, b"body") { return &text[end..last]; }
            }
        }
        at = next;
    }
    text
}

fn replace_ascii(input: &[u16], patterns: &[&[u8]], replacement: u16) -> Vec<u16> {
    let mut output = Vec::with_capacity(input.len());
    let mut at = 0;
    while at < input.len() {
        if input[at] == 38 {
            if let Some(pattern) = patterns.iter().find(|p| starts(input, at, p)) {
                output.push(replacement); at += pattern.len(); continue;
            }
        }
        output.push(input[at]); at += 1;
    }
    output
}

pub fn local_entities(input: &[u16]) -> Vec<u16> {
    if !input.contains(&38) { return input.to_vec(); }
    let text = replace_ascii(input, &[b"&nbsp;"], 32);
    let text = replace_ascii(&text, &[b"&amp;"], 38);
    let text = replace_ascii(&text, &[b"&quot;"], 34);
    let text = replace_ascii(&text, &[b"&#39;", b"&apos;"], 39);
    let text = replace_ascii(&text, &[b"&lt;"], 60);
    replace_ascii(&text, &[b"&gt;"], 62)
}

pub fn clean_html(input: &[u16]) -> Vec<u16> {
    let input = body(input);
    let mut stripped = Vec::with_capacity(input.len());
    let blocks: &[&[u8]] = &[b"p", b"div", b"section", b"article", b"li", b"tr",
        b"h1", b"h2", b"h3", b"h4", b"h5", b"h6"];
    let mut at = 0;
    while at < input.len() {
        if input[at] == 60 {
            if starts(input, at, b"<!--") {
                if let Some(end) = find(input, at + 4, b"-->") { at = end + 3; continue; }
            }
            let mut skipped = false;
            for name in [b"head".as_slice(), b"script", b"style"] {
                let end_name = at + 1 + name.len();
                if starts(input, at + 1, name) && input.get(end_name).is_none_or(|&c| !word(c)) {
                    if let Some(end) = tag_end(input, end_name) {
                        if let Some((_, last)) = closing(input, end, name) {
                            at = last; skipped = true; break;
                        }
                    }
                }
            }
            if skipped { continue; }
            if let Some(end) = tag_end(input, at + 1) {
                if end > at + 2 {
                    let tag = &input[at + 1..end - 1];
                    let name_start = usize::from(tag.first() == Some(&47));
                    if tag.first() == Some(&47) && tag.len() >= 3 &&
                        (ascii_eq(&tag[1..3], b"td") || ascii_eq(&tag[1..3], b"th")) &&
                        tag[3..].iter().all(|&c| js_space(c)) {
                        stripped.push(32);
                    } else {
                        let br = tag.len() >= 2 && ascii_eq(&tag[..2], b"br") && {
                            let rest = &tag[2..];
                            let rest = if rest.last() == Some(&47) { &rest[..rest.len()-1] } else { rest };
                            rest.iter().all(|&c| js_space(c))
                        };
                        let block = blocks.iter().any(|name| {
                            let last = name_start + name.len();
                            tag.get(name_start..last).is_some_and(|s| ascii_eq(s, name)) &&
                                tag.get(last).is_none_or(|&c| !word(c))
                        });
                        if br || block { stripped.push(10); }
                    }
                    at = end; continue;
                }
            }
        }
        stripped.push(input[at]); at += 1;
    }
    normalize_local(&local_entities(&stripped))
}

fn normalize_local(input: &[u16]) -> Vec<u16> {
    let mut output = Vec::with_capacity(input.len());
    let mut at = 0;
    let mut newlines = 0;
    while at < input.len() {
        let c = input[at]; at += 1;
        if c == 13 && input.get(at) == Some(&10) { at += 1; }
        if c == 13 || c == 10 {
            if output.last() == Some(&32) { output.pop(); }
            newlines += 1;
            if newlines <= 2 { output.push(10); }
        } else if c == 32 || c == 9 {
            if output.last().is_some_and(|&v| v != 32 && v != 10) { output.push(32); }
        } else { output.push(c); newlines = 0; }
    }
    let start = output.iter().position(|&c| !js_space(c)).unwrap_or(output.len());
    let end = output.iter().rposition(|&c| !js_space(c)).map_or(start, |n| n + 1);
    output[start..end].to_vec()
}

pub fn html_encode(input: &[u16]) -> Vec<u16> {
    html_encode_bounded(input, || true).unwrap()
}

pub fn html_encode_bounded(input: &[u16], mut running: impl FnMut() -> bool) -> Result<Vec<u16>, u32> {
    let mut length = 0;
    for (index, &c) in input.iter().enumerate() {
        if index % 2048 == 0 && !running() { return Err(7); }
        length += match c { 38 => 5, 60 | 62 => 4, 160 => 6, _ => 1 };
    }
    let mut output = Vec::with_capacity(length);
    for (index, &c) in input.iter().enumerate() {
        if index % 2048 == 0 && !running() { return Err(7); }
        let escaped: Option<&[u8]> = match c {
            38 => Some(b"&amp;"), 60 => Some(b"&lt;"), 62 => Some(b"&gt;"),
            160 => Some(b"&nbsp;"), _ => None,
        };
        if let Some(bytes) = escaped { output.extend(bytes.iter().map(|&v| v as u16)); }
        else { output.push(c); }
    }
    Ok(output)
}

fn numeric_character(mut code: u32, output: &mut Vec<u16>) {
    if code == 0 || code > 0x10ffff || (0xd800..=0xdfff).contains(&code) { code = 0xfffd; }
    const C1: [u32; 32] = [0x20ac,0x81,0x201a,0x192,0x201e,0x2026,0x2020,0x2021,
        0x2c6,0x2030,0x160,0x2039,0x152,0x8d,0x17d,0x8f,0x90,0x2018,0x2019,0x201c,
        0x201d,0x2022,0x2013,0x2014,0x2dc,0x2122,0x161,0x203a,0x153,0x9d,0x17e,0x178];
    if (0x80..=0x9f).contains(&code) { code = C1[(code - 0x80) as usize]; }
    if code <= 0xffff { output.push(code as u16); }
    else {
        code -= 0x10000;
        output.push(0xd800 + (code >> 10) as u16); output.push(0xdc00 + (code & 1023) as u16);
    }
}

pub fn html_decode(input: &[u16]) -> Vec<u16> {
    html_decode_bounded(input, || true).unwrap()
}

pub fn html_decode_bounded(input: &[u16], mut running: impl FnMut() -> bool) -> Result<Vec<u16>, u32> {
    let mut output = Vec::with_capacity(input.len());
    let mut at = 0;
    let mut checkpoint = 0;
    while at < input.len() {
        if at >= checkpoint {
            if !running() { return Err(7); }
            checkpoint = at + 2048;
        }
        if starts(input, at, b"&#") {
            let mut end = at + 2;
            let radix = if matches!(input.get(end), Some(88 | 120)) { end += 1; 16 } else { 10 };
            let first = end;
            let mut code = 0_u32;
            while let Some(&c) = input.get(end) {
                if end % 2048 == 0 && !running() { return Err(7); }
                let digit = match c { 48..=57 => (c - 48) as u32, 65..=70 => (c - 55) as u32,
                    97..=102 => (c - 87) as u32, _ => radix };
                if digit >= radix { break; }
                code = code.saturating_mul(radix).saturating_add(digit); end += 1;
            }
            if end > first {
                if input.get(end) == Some(&59) { end += 1; }
                numeric_character(code, &mut output); at = end; continue;
            }
        } else if input[at] == 38 {
            let mut end = at + 1;
            while end < input.len() && end - at <= 32 && input[end] < 128 &&
                ((input[end] as u8).is_ascii_alphanumeric() || input[end] == 59) {
                end += 1;
                if input[end - 1] == 59 { break; }
            }
            let mut matched = None;
            for last in (at + 2..=end).rev() {
                let name = &input[at + 1..last];
                if let Ok(index) = entities::ENTITIES.binary_search_by(|entry|
                    entry.0.bytes().map(u16::from).cmp(name.iter().copied())) {
                    matched = Some((last, entities::ENTITIES[index].1)); break;
                }
            }
            if let Some((last, text)) = matched { output.extend_from_slice(text); at = last; continue; }
        }
        let c = input[at]; at += 1;
        if c == 13 {
            if input.get(at) == Some(&10) { at += 1; }
            output.push(10);
        } else { output.push(if c == 0 { 0xfffd } else { c }); }
    }
    Ok(output)
}

pub fn search_offsets(text: &[u16], keyword: &[u16], limit: usize) -> Vec<u32> {
    let mut offsets = Vec::new();
    if keyword.is_empty() || limit == 0 { return offsets; }
    let mut prefix = vec![0_usize; keyword.len()];
    let mut matched = 0;
    for i in 1..keyword.len() {
        while matched > 0 && keyword[i] != keyword[matched] { matched = prefix[matched - 1]; }
        if keyword[i] == keyword[matched] { matched += 1; }
        prefix[i] = matched;
    }
    matched = 0;
    for (index, &c) in text.iter().enumerate() {
        while matched > 0 && c != keyword[matched] { matched = prefix[matched - 1]; }
        if c == keyword[matched] { matched += 1; }
        if matched == keyword.len() {
            offsets.push((index + 1 - keyword.len()) as u32);
            if offsets.len() == limit { break; }
            matched = prefix[matched - 1];
        }
    }
    offsets
}

/// Resolve the generated EPUB placeholders in one pass after text cleaning.
pub fn epub_images(text: &[u16], prefix: &[u16], images: &[&[u16]]) -> Vec<u16> {
    let mut output = Vec::with_capacity(text.len());
    let mut used = vec![false; images.len()];
    let mut at = 0;
    while at < text.len() {
        if text.get(at..at + prefix.len()) == Some(prefix) {
            let first = at + prefix.len();
            let mut end = first;
            let mut index = 0_usize;
            while let Some(&c @ 48..=57) = text.get(end) {
                index = index.saturating_mul(10).saturating_add((c - 48) as usize);
                end += 1;
            }
            if end > first && (end == first + 1 || text[first] != 48) &&
                index < images.len() && !used[index] && text.get(end..end + 3) == Some(&[69, 78, 68]) {
                output.extend_from_slice(images[index]);
                used[index] = true;
                at = end + 3;
                continue;
            }
        }
        output.push(text[at]); at += 1;
    }
    output
}

pub fn white_border(pixels: &[u8], width: usize, height: usize) -> [f64; 4] {
    if width < 16 || height < 16 || pixels.len() < width * height * 4 { return [0., 0., 1., 1.]; }
    let (mut left, mut top, mut right, mut bottom) = (width, height, 0, 0);
    let mut found = false;
    for (index, pixel) in pixels[..width * height * 4].chunks_exact(4).enumerate() {
        if pixel[0] >= 245 && pixel[1] >= 245 && pixel[2] >= 245 && pixel[3] >= 250 { continue; }
        let (x, y) = (index % width, index / width);
        left = left.min(x); right = right.max(x); top = top.min(y); bottom = bottom.max(y); found = true;
    }
    if !found { return [0., 0., 1., 1.]; }
    left = (width / 4).min(left.saturating_sub(2));
    top = (height / 4).min(top.saturating_sub(2));
    let trim_right = (width / 4).min(width.saturating_sub(right + 3));
    let trim_bottom = (height / 4).min(height.saturating_sub(bottom + 3));
    [left as f64 / width as f64, top as f64 / height as f64,
        (width - left - trim_right) as f64 / width as f64,
        (height - top - trim_bottom) as f64 / height as f64]
}

pub fn wave(samples: &[f32], rate: u32) -> Result<Vec<u8>, u32> {
    let bytes = samples.len() * 2;
    if bytes == 0 || bytes > 8 * 1024 * 1024 || !(8000..=48000).contains(&rate) { return Err(3); }
    let mut output = Vec::with_capacity(44 + bytes);
    output.extend_from_slice(b"RIFF"); output.extend_from_slice(&(36 + bytes as u32).to_le_bytes());
    output.extend_from_slice(b"WAVEfmt "); output.extend_from_slice(&16_u32.to_le_bytes());
    output.extend_from_slice(&1_u16.to_le_bytes()); output.extend_from_slice(&1_u16.to_le_bytes());
    output.extend_from_slice(&rate.to_le_bytes()); output.extend_from_slice(&(rate * 2).to_le_bytes());
    output.extend_from_slice(&2_u16.to_le_bytes()); output.extend_from_slice(&16_u16.to_le_bytes());
    output.extend_from_slice(b"data"); output.extend_from_slice(&(bytes as u32).to_le_bytes());
    for &sample in samples {
        if !sample.is_finite() { return Err(3); }
        let sample = sample.clamp(-1., 1.) as f64;
        let scale = if sample < 0. { 32768. } else { 32767. };
        output.extend_from_slice(&((sample * scale + 0.5).floor() as i16).to_le_bytes());
    }
    Ok(output)
}
