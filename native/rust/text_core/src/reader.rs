use crate::{ascii_eq, find, js_space, replace_ascii, starts, tag_end, word};

const BLOCKS: &[&[u8]] = &[b"p", b"div", b"section", b"article", b"li",
    b"h1", b"h2", b"h3", b"h4", b"h5", b"h6"];

pub fn trim(text: &[u16]) -> &[u16] {
    let start = text.iter().position(|&c| !js_space(c)).unwrap_or(text.len());
    let end = text.iter().rposition(|&c| !js_space(c)).map_or(start, |i| i + 1);
    &text[start..end]
}

fn tag_name(tag: &[u16], names: &[&[u8]]) -> Option<usize> {
    names.iter().find_map(|name| tag.get(..name.len())
        .filter(|prefix| ascii_eq(prefix, name)).map(|_| name.len()))
}

fn html_blocks(input: &[u16]) -> bool {
    for (at, &c) in input.iter().enumerate() {
        if c != 60 { continue; }
        let closing = input.get(at + 1) == Some(&47);
        let first = at + if closing { 2 } else { 1 };
        let rest = &input[first..];
        let length = tag_name(rest, BLOCKS).or_else(|| {
            if !closing && starts(rest, 0, b"br") { Some(2) } else { None }
        });
        if let Some(length) = length {
            let after = first + length;
            if closing {
                let end = input[after..].iter().position(|&v| !js_space(v)).map(|n| after + n);
                if end.is_some_and(|n| input[n] == 62) { return true; }
            } else if input.get(after) == Some(&62) || input.get(after..after + 2) == Some(&[47, 62]) ||
                (input.get(after).is_some_and(|&v| js_space(v)) && tag_end(input, after).is_some()) {
                return true;
            }
        }
    }
    false
}

fn remove_spans(input: &[u16], opening: &[u8], closing: &[u8]) -> Vec<u16> {
    let mut output = Vec::with_capacity(input.len());
    let mut at = 0;
    while at < input.len() {
        if starts(input, at, opening) {
            if let Some(end) = find(input, at + opening.len(), closing) {
                at = end + closing.len();
                continue;
            }
        }
        output.push(input[at]);
        at += 1;
    }
    output
}

fn replace_tags(input: &[u16], phase: u8) -> Vec<u16> {
    let mut output = Vec::with_capacity(input.len());
    let mut at = 0;
    while at < input.len() {
        if input[at] == 60 {
            if let Some(end) = tag_end(input, at + 1) {
                let tag = &input[at + 1..end - 1];
                let matched = match phase {
                    0 => tag_name(tag, &[b"br"]).is_some_and(|n| {
                        let rest = &tag[n..];
                        let rest = if rest.last() == Some(&47) { &rest[..rest.len() - 1] } else { rest };
                        rest.iter().all(|&c| js_space(c))
                    }),
                    1 => tag.first() == Some(&47) && tag_name(&tag[1..], BLOCKS)
                        .is_some_and(|n| tag[n + 1..].iter().all(|&c| js_space(c))),
                    2 => tag_name(tag, BLOCKS).is_some_and(|n| tag.get(n).is_none_or(|&c| !word(c))),
                    _ => !tag.is_empty(),
                };
                if matched {
                    if phase < 3 { output.push(10); }
                    at = end;
                    continue;
                }
            }
        }
        output.push(input[at]);
        at += 1;
    }
    output
}

/// Keep the reader's staged HTML and entity semantics in UTF-16 coordinates.
pub fn normalize(input: &[u16]) -> Vec<u16> {
    let mut value = Vec::with_capacity(input.len());
    let mut at = 0;
    while at < input.len() {
        let c = input[at];
        at += 1;
        match c {
            13 => { if input.get(at) == Some(&10) { at += 1; } value.push(10); }
            0x200b | 0xfeff => {}
            _ => value.push(c),
        }
    }
    value = replace_ascii(&value, &[b"&nbsp;", b"&#160;"], 32);
    if html_blocks(&value) {
        for (opening, closing) in [(b"<!--".as_slice(), b"-->".as_slice()),
            (b"<script", b"</script>"), (b"<style", b"</style>")] {
            value = remove_spans(&value, opening, closing);
        }
        for phase in 0..4 { value = replace_tags(&value, phase); }
    }
    for (patterns, replacement) in [(&[b"&quot;".as_slice()][..], 34),
        (&[b"&#39;".as_slice(), b"&apos;"][..], 39), (&[b"&lt;".as_slice()][..], 60),
        (&[b"&gt;".as_slice()][..], 62), (&[b"&amp;".as_slice()][..], 38)] {
        value = replace_ascii(&value, patterns, replacement);
    }
    let mut output = Vec::with_capacity(value.len());
    let mut newlines = 0;
    for c in value {
        if c == 10 {
            while matches!(output.last(), Some(32 | 9)) { output.pop(); }
            newlines += 1;
            if newlines <= 2 { output.push(10); }
        } else if (c == 32 || c == 9) && output.last() == Some(&10) {
        } else {
            output.push(c);
            if c != 32 && c != 9 { newlines = 0; }
        }
    }
    trim(&output).to_vec()
}

pub struct Display {
    pub text: Vec<u16>,
    pub indents: Vec<u32>,
}

pub fn indent(input: &[u16], hidden_prefix: usize) -> Display {
    let mut result = Display { text: Vec::with_capacity(input.len()), indents: Vec::new() };
    let mut source_start = 0;
    for paragraph in input.split(|&c| c == 10) {
        let leading = paragraph.iter().position(|&c| !js_space(c)).unwrap_or(paragraph.len());
        if source_start >= hidden_prefix && leading < paragraph.len() {
            if !result.indents.is_empty() { result.text.push(10); }
            result.indents.extend_from_slice(&[source_start as u32, (source_start + leading) as u32,
                result.text.len() as u32]);
            result.text.extend_from_slice(&[0x3000, 0x3000]);
            result.text.extend_from_slice(&paragraph[leading..]);
        }
        source_start += paragraph.len() + 1;
    }
    result
}
