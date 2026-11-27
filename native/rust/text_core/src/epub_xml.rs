use super::{ascii_eq, replace_ascii, starts};

struct Node {
    name: Vec<u16>,
    attributes: Vec<(Vec<u16>, Vec<u16>)>,
    parent: usize,
    start: usize,
    end: usize,
}

fn space(c: u16) -> bool { super::js_space(c) }
fn name_char(c: u16) -> bool {
    c < 128 && ((c as u8).is_ascii_alphanumeric() || matches!(c, 95 | 58 | 46 | 45))
}
fn local_name(name: &[u16]) -> Vec<u16> {
    let start = name.iter().rposition(|&c| c == 58).map_or(0, |at| at + 1);
    name[start..].iter().map(|&c| if (65..=90).contains(&c) { c + 32 } else { c }).collect()
}

fn decode(input: &[u16]) -> Vec<u16> {
    let text = replace_ascii(input, &[b"&lt;"], 60);
    let text = replace_ascii(&text, &[b"&gt;"], 62);
    let text = replace_ascii(&text, &[b"&nbsp;"], 32);
    let text = replace_ascii(&text, &[b"&amp;"], 38);
    let text = replace_ascii(&text, &[b"&quot;"], 34);
    let text = replace_ascii(&text, &[b"&apos;", b"&#39;"], 39);
    let mut output = Vec::with_capacity(text.len());
    let mut at = 0;
    while at < text.len() {
        if starts(&text, at, b"&#") {
            let mut end = at + 2;
            let radix = if matches!(text.get(end), Some(88 | 120)) { end += 1; 16 } else { 10 };
            let first = end;
            let mut value = 0_u32;
            while let Some(&c) = text.get(end) {
                let digit = match c { 48..=57 => (c - 48) as u32, 65..=70 => (c - 55) as u32,
                    97..=102 => (c - 87) as u32, _ => radix };
                if digit >= radix { break; }
                value = value.saturating_mul(radix).saturating_add(digit);
                end += 1;
            }
            if end > first && text.get(end) == Some(&59) {
                if (1..=0x10ffff).contains(&value) {
                    if value <= 0xffff { output.push(value as u16); }
                    else {
                        value -= 0x10000;
                        output.push(0xd800 + (value >> 10) as u16);
                        output.push(0xdc00 + (value & 1023) as u16);
                    }
                }
                at = end + 1;
                continue;
            }
        }
        output.push(text[at]); at += 1;
    }
    output
}

fn quoted_end(source: &[u16], from: usize) -> Option<usize> {
    let mut quote = 0;
    for (offset, &c) in source[from..].iter().enumerate() {
        if quote != 0 { if c == quote { quote = 0; } }
        else if c == 34 || c == 39 { quote = c; }
        else if c == 60 { return None; }
        else if c == 62 { return Some(from + offset); }
    }
    None
}

fn attributes(tag: &[u16]) -> Vec<(Vec<u16>, Vec<u16>)> {
    let mut attributes = Vec::new();
    let mut at = 0;
    while at < tag.len() {
        if !name_char(tag[at]) { at += 1; continue; }
        let first = at;
        while at < tag.len() && name_char(tag[at]) { at += 1; }
        let last = at;
        while at < tag.len() && space(tag[at]) { at += 1; }
        if tag.get(at) != Some(&61) { continue; }
        at += 1;
        while at < tag.len() && space(tag[at]) { at += 1; }
        let Some(&quote @ (34 | 39)) = tag.get(at) else { continue; };
        at += 1;
        let start = at;
        while at < tag.len() && tag[at] != quote { at += 1; }
        if at < tag.len() {
            attributes.push((tag[first..last].to_vec(), decode(&tag[start..at])));
            at += 1;
        }
    }
    attributes
}

fn json_text(output: &mut Vec<u16>, text: &[u16]) {
    output.push(34);
    const HEX: &[u8] = b"0123456789abcdef";
    for &c in text {
        match c {
            34 | 92 => { output.push(92); output.push(c); }
            0..=31 | 0xd800..=0xdfff => {
                output.extend([92, 117]);
                for shift in [12, 8, 4, 0] { output.push(HEX[((c >> shift) & 15) as usize] as u16); }
            }
            _ => output.push(c),
        }
    }
    output.push(34);
}
fn literal(output: &mut Vec<u16>, text: &str) { output.extend(text.bytes().map(u16::from)); }
fn numeric(output: &mut Vec<u16>, number: usize) { literal(output, &number.to_string()); }

/// Shared text offsets preserve descendant text while storing each text token once.
pub fn parse(source: &[u16]) -> Result<Vec<u16>, u32> {
    if source.len() > 8 * 1024 * 1024 { return Err(5); }
    let mut nodes = vec![Node { name: Vec::new(), attributes: Vec::new(), parent: 0, start: 0, end: 0 }];
    let mut stack = vec![0];
    let mut text = Vec::new();
    let mut at = 0;
    while at < source.len() {
        if source[at] != 60 {
            let first = at;
            while at < source.len() && source[at] != 60 { at += 1; }
            text.extend(decode(&source[first..at]));
            continue;
        }
        let special = if starts(source, at, b"<!--") { Some((4, b"-->".as_slice(), false)) }
            else if starts(source, at, b"<![CDATA[") { Some((9, b"]]>".as_slice(), source[at + 3..at + 8] == [67, 68, 65, 84, 65])) }
            else if starts(source, at, b"<?") { Some((2, b"?>".as_slice(), false)) }
            else if starts(source, at, b"<!DOCTYPE") { Some((9, b">".as_slice(), false)) }
            else { None };
        if let Some((prefix, ending, cdata)) = special {
            if let Some(end) = super::find(source, at + prefix, ending) {
                if cdata { text.extend_from_slice(&source[at + prefix..end]); }
                at = end + ending.len();
                continue;
            }
        }
        let closing = source.get(at + 1) == Some(&47);
        let first = at + if closing { 2 } else { 1 };
        if source.get(first).is_none_or(|&c| c > 127 || !(c as u8).is_ascii_alphabetic()) { at += 1; continue; }
        let mut last = first;
        while last < source.len() && name_char(source[last]) { last += 1; }
        if source.get(last).is_none_or(|&c| c != 62 && c != 47 && !space(c)) { at += 1; continue; }
        let Some(end) = quoted_end(source, last) else { at += 1; continue; };
        let name = local_name(&source[first..last]);
        if closing {
            if let Some(index) = stack.iter().rposition(|&node| nodes[node].name == name) {
                if index > 0 { for node in stack.drain(index..) { nodes[node].end = text.len(); } }
            }
        } else {
            if nodes.len() > 200000 || stack.len() > 64 { return Err(6); }
            let mut tail = end;
            while tail > last && space(source[tail - 1]) { tail -= 1; }
            let leaf = source.get(tail.wrapping_sub(1)) == Some(&47) ||
                [b"link".as_slice(), b"img", b"br", b"hr", b"input"].iter().any(|tag| ascii_eq(&name, tag));
            let node = nodes.len();
            nodes.push(Node { name, attributes: attributes(&source[last..end]), parent: *stack.last().unwrap(),
                start: text.len(), end: text.len() });
            if !leaf { stack.push(node); }
        }
        at = end + 1;
    }
    for node in stack { nodes[node].end = text.len(); }
    let mut output = Vec::new();
    literal(&mut output, "{\"text\":"); json_text(&mut output, &text);
    literal(&mut output, ",\"nodes\":[");
    for (index, node) in nodes.iter().enumerate() {
        if index > 0 { output.push(44); }
        literal(&mut output, "{\"name\":"); json_text(&mut output, &node.name);
        literal(&mut output, ",\"parent\":"); numeric(&mut output, node.parent);
        literal(&mut output, ",\"start\":"); numeric(&mut output, node.start);
        literal(&mut output, ",\"end\":"); numeric(&mut output, node.end);
        literal(&mut output, ",\"attributes\":[");
        for (index, (name, value)) in node.attributes.iter().enumerate() {
            if index > 0 { output.push(44); }
            literal(&mut output, "{\"name\":"); json_text(&mut output, name);
            literal(&mut output, ",\"value\":"); json_text(&mut output, value); output.push(125);
        }
        literal(&mut output, "]}");
    }
    literal(&mut output, "]}");
    Ok(output)
}
