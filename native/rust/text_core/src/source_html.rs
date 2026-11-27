use crate::{js_space, tag_end};

/// Pair the exact same-tag pattern consumed by the imported selector engine.
pub fn pairs(input: &[u16], tag: &[u16]) -> Vec<u32> {
    let mut pairs = Vec::new();
    let mut stack = Vec::new();
    let mut at = 0;
    while at < input.len() {
        if input[at] != 60 { at += 1; continue; }
        let closing = input.get(at + 1) == Some(&47);
        let first = at + if closing { 2 } else { 1 };
        let after = first + tag.len();
        let matched = input.get(first..after).is_some_and(|name| name.iter().zip(tag).all(|(&a, &b)|
            a == b || (a <= 127 && b <= 127 && (a as u8).eq_ignore_ascii_case(&(b as u8)))));
        if !matched { at += 1; continue; }
        let end = if input.get(after) == Some(&62) { Some(after + 1) }
            else if input.get(after).is_some_and(|&c| js_space(c)) { tag_end(input, after + 1) }
            else { None };
        if let Some(end) = end {
            if closing {
                if let Some(index) = stack.pop() { pairs[index + 1] = end as u32; }
            } else if input[end - 2] != 47 {
                stack.push(pairs.len());
                pairs.extend_from_slice(&[at as u32, u32::MAX]);
            }
            at = end;
        } else { at += 1; }
    }
    pairs
}
