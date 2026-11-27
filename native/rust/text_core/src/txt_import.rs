use crate::{ascii_eq, js_space};
use std::mem;

const PLAIN_SECTION_LENGTH: usize = 32000;
const TITLED_SECTION_LIMIT: usize = 8 * 1024 * 1024;

pub struct TxtSection {
    pub title: Vec<u16>,
    pub content: Vec<u16>,
    pub preserve_chapter: bool,
}

pub struct TxtImporter {
    title: Vec<u16>,
    pending: Vec<u16>,
    section: Vec<u16>,
    has_chapter_title: bool,
}

fn chapter_number(c: u16) -> bool {
    matches!(c, 48..=57) || ['零' as u16, '〇' as u16, '一' as u16, '二' as u16,
        '三' as u16, '四' as u16, '五' as u16, '六' as u16, '七' as u16, '八' as u16,
        '九' as u16, '十' as u16, '百' as u16, '千' as u16, '万' as u16, '两' as u16].contains(&c)
}

fn title_suffix(value: &[u16]) -> bool {
    value.len() <= 70 && value.iter().all(|&c| !matches!(c, 10 | 13 | 0x2028 | 0x2029))
}

fn chapter_title(value: &[u16]) -> bool {
    if value.len() == 2 && ["序章", "序言", "楔子", "尾声", "后记"].iter()
        .any(|title| value.iter().copied().eq(title.encode_utf16())) { return true; }
    if value.first() == Some(&('第' as u16)) {
        let mut end = 1;
        while end < value.len() && chapter_number(value[end]) { end += 1; }
        return end > 1 && value.get(end).is_some_and(|c|
            ['章' as u16, '节' as u16, '卷' as u16, '回' as u16, '部' as u16, '篇' as u16].contains(c)) &&
            title_suffix(&value[end + 1..]);
    }
    if value.get(..7).is_some_and(|prefix| ascii_eq(prefix, b"chapter")) {
        let mut end = 7;
        while end < value.len() && js_space(value[end]) { end += 1; }
        if end == 7 { return false; }
        let first_digit = end;
        while end < value.len() && matches!(value[end], 48..=57) { end += 1; }
        return end > first_digit && title_suffix(&value[end..]);
    }
    false
}

impl TxtImporter {
    pub fn new(title: &[u16]) -> Self {
        Self { title: title.to_vec(), pending: Vec::new(), section: Vec::new(), has_chapter_title: false }
    }

    fn emit(&mut self, sections: &mut Vec<TxtSection>) {
        if !self.section.is_empty() {
            sections.push(TxtSection { title: self.title.clone(), content: mem::take(&mut self.section),
                preserve_chapter: self.has_chapter_title });
        }
    }

    fn line(&mut self, sections: &mut Vec<TxtSection>) -> Result<(), u32> {
        let mut line = mem::take(&mut self.pending);
        let first = line.iter().position(|&c| !js_space(c)).unwrap_or(line.len());
        let last = line.iter().rposition(|&c| !js_space(c)).map_or(first, |index| index + 1);
        let trimmed = &line[first..last];
        if chapter_title(trimmed) {
            self.emit(sections);
            self.title = trimmed.to_vec();
            self.has_chapter_title = true;
        }
        self.section.extend_from_slice(&line);
        self.section.push(10);
        line.clear();
        self.pending = line;
        if self.has_chapter_title && self.section.len() > TITLED_SECTION_LIMIT { return Err(8); }
        if !self.has_chapter_title && self.section.len() >= PLAIN_SECTION_LENGTH { self.emit(sections); }
        Ok(())
    }

    /// Consume one decoded file block and emit the sections completed by that block.
    pub fn feed(&mut self, input: &[u16], final_chunk: bool) -> Result<Vec<TxtSection>, u32> {
        let mut sections = Vec::new();
        for &c in input {
            match c {
                13 => {},
                10 => self.line(&mut sections)?,
                _ => self.pending.push(c),
            }
        }
        if final_chunk && !self.pending.is_empty() { self.line(&mut sections)?; }
        if self.has_chapter_title && self.section.len() + self.pending.len() > TITLED_SECTION_LIMIT {
            return Err(8);
        }
        if !self.has_chapter_title && self.pending.len() >= PLAIN_SECTION_LENGTH {
            self.section.append(&mut self.pending);
            self.emit(&mut sections);
        }
        if final_chunk {
            self.section.append(&mut self.pending);
            self.emit(&mut sections);
        }
        Ok(sections)
    }
}
