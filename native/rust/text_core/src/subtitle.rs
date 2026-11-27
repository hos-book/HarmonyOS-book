use crate::{js_space, reader::trim};
use std::collections::BTreeSet;

#[derive(Clone)]
pub struct Unit {
    pub text: Vec<u16>,
    pub start: f64,
    pub end: f64,
    pub sentence_end: bool,
}

pub struct Cue {
    pub text: Vec<u16>,
    pub start: f64,
    pub end: f64,
    pub continues: bool,
}

pub struct Chunk {
    pub index: u32,
    pub annotated: Vec<Unit>,
    pub cues: Vec<Cue>,
}

pub type Dictionary = BTreeSet<Vec<u16>>;

pub fn dictionary(words: &[&[u16]]) -> Dictionary {
    words.iter().map(|word| trim(word)).filter(|word| (2..=12).contains(&word.len()) &&
        word.iter().all(|c| (0x4e00..=0x9fff).contains(c))).take(50000).map(|word| word.to_vec()).collect()
}

fn punctuation(c: u16) -> bool {
    "，。！？；：、,.!?;:\"“”‘’「」『』（）()".encode_utf16().any(|v| v == c)
}

fn plain(text: &[u16]) -> Vec<u16> {
    let letters: Vec<u16> = text.iter().copied().filter(|&c| !js_space(c) && !punctuation(c)).collect();
    String::from_utf16_lossy(&letters).to_lowercase().encode_utf16().collect()
}

fn characters(text: &[u16]) -> Vec<&[u16]> {
    let mut result = Vec::new();
    let mut at = 0;
    while at < text.len() {
        let width = if (0xd800..=0xdbff).contains(&text[at]) &&
            text.get(at + 1).is_some_and(|c| (0xdc00..=0xdfff).contains(c)) { 2 } else { 1 };
        result.push(&text[at..at + width]);
        at += width;
    }
    result
}

/// Reuse normalized words and suffix lengths across acoustic-overlap candidates.
pub fn join(previous: &[Unit], current: &[Unit], boundary: f64) -> Vec<Unit> {
    let left_words: Vec<Vec<u16>> = previous.iter().map(|unit| plain(&unit.text)).collect();
    let right_words: Vec<Vec<u16>> = current.iter().map(|unit| plain(&unit.text)).collect();
    let candidate_end = current.iter().position(|unit| unit.start >= boundary).unwrap_or(current.len());
    let mut lengths = vec![0; current.len() + 1];
    let mut longest = 0;
    let mut nearest = f64::MAX;
    let mut best = (usize::MAX, usize::MAX);
    for i in (0..previous.len()).rev() {
        let mut diagonal = 0;
        for j in (0..current.len()).rev() {
            let next = lengths[j];
            let distance = (previous[i].start - current[j].start).abs();
            lengths[j] = if left_words[i] == right_words[j] && distance <= 600. { diagonal + 1 } else { 0 };
            diagonal = next;
            let length = lengths[j];
            if previous[i].start >= boundary - 2000. && !left_words[i].is_empty() && j < candidate_end &&
                (length > longest || (length > 0 && length == longest &&
                    (distance < nearest || (distance == nearest && (i, j) < best)))) {
                longest = length;
                nearest = distance;
                best = (i, j);
            }
        }
    }
    if longest > 0 {
        let left = best.0 + longest / 2;
        let right = best.1 + longest / 2;
        let mut output: Vec<Unit> = previous[..left].iter().filter_map(|unit| {
            let end = unit.end.min(current[right].start);
            (end > unit.start).then(|| Unit { text: unit.text.clone(), start: unit.start, end, sentence_end: false })
        }).collect();
        output.extend_from_slice(&current[right..]);
        output
    } else {
        previous.iter().chain(current.iter().filter(|unit| unit.start >= boundary)).cloned().collect()
    }
}

pub fn punctuate(units: &[Unit], output: &[u16], final_chunk: bool) -> Vec<Unit> {
    let original: Vec<u16> = units.iter().flat_map(|unit| unit.text.iter().copied()).collect();
    let words: Vec<&Unit> = units.iter().filter(|unit| !plain(&unit.text).is_empty()).collect();
    let matched = plain(&original) == plain(output);
    let mut text = if matched { output.to_vec() } else { original };
    if !final_chunk && matched {
        let end = text.iter().rposition(|&c| !js_space(c)).map_or(0, |n| n + 1);
        let mut quotes = end;
        while quotes > 0 && "\"”’」』".encode_utf16().any(|c| c == text[quotes - 1]) { quotes -= 1; }
        let mut stop = quotes;
        while stop > 0 && "。！？.!?".encode_utf16().any(|c| c == text[stop - 1]) { stop -= 1; }
        if stop < quotes {
            let closing = text[quotes..end].to_vec();
            text.truncate(stop);
            text.extend_from_slice(&closing);
        }
    }
    let chars = characters(&text);
    let mut result: Vec<Unit> = Vec::new();
    let mut cursor = 0;
    for (position, character) in chars.iter().enumerate() {
        if plain(character).is_empty() {
            if let Some(last) = result.last_mut() {
                last.text.extend_from_slice(character);
                let decimal = *character == [46] && position > 0 && position + 1 < chars.len() &&
                    chars[position - 1].len() == 1 && (48..=57).contains(&chars[position - 1][0]) &&
                    chars[position + 1].len() == 1 && (48..=57).contains(&chars[position + 1][0]);
                if character.iter().any(|&c| "。！？!?".encode_utf16().any(|v| v == c)) ||
                    (*character == [46] && !decimal) { last.sentence_end = true; }
            }
        } else if let Some(source) = words.get(cursor) {
            result.push(Unit { text: source.text.clone(), start: source.start, end: source.end, sentence_end: false });
            cursor += 1;
        }
    }
    result
}

fn split_long(units: &[Unit], cues: &mut Vec<Cue>) {
    let mut first = 0;
    while first < units.len() {
        let mut end = units.len() - 1;
        if units.len() - first > 42 {
            let mut distance = usize::MAX;
            for (i, unit) in units.iter().enumerate().take(units.len() - 8).skip(first + 7) {
                if !unit.text.iter().any(|&c| "，,；;".encode_utf16().any(|v| v == c)) { continue; }
                let candidate = (i - first + 1).abs_diff(28);
                if candidate < distance { end = i; distance = candidate; }
            }
        }
        let text: Vec<u16> = units[first..=end].iter().flat_map(|unit| unit.text.iter().copied()).collect();
        let text = trim(&text);
        if !text.is_empty() {
            cues.push(Cue { text: text.to_vec(), start: units[first].start, end: units[end].end,
                continues: end + 1 == units.len() && !units[end].sentence_end });
        }
        first = end + 1;
    }
}

fn display(mut units: Vec<Unit>, dictionary: Option<&Dictionary>, cues: &mut Vec<Cue>) {
    if let Some(dictionary) = dictionary.filter(|words| !words.is_empty()) {
        let letters: Vec<(usize, Vec<u16>)> = units.iter().enumerate().filter_map(|(index, unit)| {
            let word = plain(&unit.text);
            (!word.is_empty()).then_some((index, word))
        }).collect();
        for i in 0..letters.len() {
            let mut word = Vec::new();
            for j in i..letters.len().min(i + 12) {
                word.extend_from_slice(&letters[j].1);
                if dictionary.contains(&word) {
                    for unit in &mut units[letters[i].0..letters[j].0] {
                        unit.text.retain(|&c| !"，。！？；：、,.!?;:".encode_utf16().any(|v| v == c));
                        unit.sentence_end = false;
                    }
                }
            }
        }
    }
    let mut first = 0;
    for i in 0..units.len() {
        if units[i].sentence_end || i + 1 == units.len() {
            split_long(&units[first..=i], cues);
            first = i + 1;
        }
    }
}

pub fn timeline(chunks: Vec<Chunk>, dictionary: Option<&Dictionary>) -> Vec<Cue> {
    let mut cues = Vec::new();
    let mut run = Vec::new();
    let mut previous = -2_i64;
    for chunk in chunks {
        if chunk.index as i64 != previous + 1 || chunk.cues.is_empty() {
            display(std::mem::take(&mut run), dictionary, &mut cues);
        }
        if !chunk.annotated.is_empty() {
            run.extend(chunk.annotated);
        } else {
            for cue in chunk.cues {
                let chars = characters(&cue.text);
                for (i, character) in chars.iter().enumerate() {
                    run.push(Unit { text: character.to_vec(),
                        start: cue.start + (cue.end - cue.start) * i as f64 / chars.len() as f64,
                        end: cue.start + (cue.end - cue.start) * (i + 1) as f64 / chars.len() as f64,
                        sentence_end: i + 1 == chars.len() && !cue.continues });
                }
            }
        }
        previous = chunk.index as i64;
    }
    display(run, dictionary, &mut cues);
    cues
}
