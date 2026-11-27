use hsda_ebook_core::HuffDecoder;
use hsda_text_core::TxtImporter;
use std::ptr;
use std::slice;

#[repr(C)]
pub struct Buffer<T> { pub data: *mut T, pub len: usize, pub status: u32 }

impl<T> Buffer<T> {
    fn from_vec(values: Vec<T>) -> Self {
        let boxed = values.into_boxed_slice();
        let len = boxed.len();
        Self { data: Box::into_raw(boxed) as *mut T, len, status: 0 }
    }
    fn error(status: u32) -> Self { Self { data: ptr::null_mut(), len: 0, status } }
}

unsafe fn borrowed<'a, T>(data: *const T, len: usize) -> &'a [T] {
    if len == 0 { &[] } else { slice::from_raw_parts(data, len) }
}

unsafe fn free<T>(buffer: Buffer<T>) {
    if !buffer.data.is_null() { drop(Box::from_raw(ptr::slice_from_raw_parts_mut(buffer.data, buffer.len))); }
}

#[no_mangle]
pub unsafe extern "C" fn hsda_text_free(buffer: Buffer<u16>) { free(buffer); }
#[no_mangle]
pub unsafe extern "C" fn hsda_bytes_free(buffer: Buffer<u8>) { free(buffer); }
#[no_mangle]
pub unsafe extern "C" fn hsda_offsets_free(buffer: Buffer<u32>) { free(buffer); }

#[no_mangle]
pub unsafe extern "C" fn hsda_text(input: *const u16, len: usize, operation: u32) -> Buffer<u16> {
    let input = borrowed(input, len);
    let output = match operation {
        0 => hsda_text_core::clean_html(input),
        1 => hsda_text_core::local_entities(input),
        2 => hsda_text_core::html_encode(input),
        3 => hsda_text_core::html_decode(input),
        4 => match hsda_text_core::parse_epub_xml(input) {
            Ok(output) => output, Err(status) => return Buffer::error(status),
        },
        5 => hsda_text_core::reader::normalize(input),
        6 => hsda_text_core::speech::spoken(input, true),
        _ => return Buffer::error(4),
    };
    Buffer::from_vec(output)
}

#[no_mangle]
pub unsafe extern "C" fn hsda_html_bounded(input: *const u16, len: usize, encode: bool,
    timeout_ms: u32) -> Buffer<u16> {
    let deadline = std::time::Instant::now() + std::time::Duration::from_millis(timeout_ms as u64);
    let running = || std::time::Instant::now() < deadline;
    let result = if encode { hsda_text_core::html_encode_bounded(borrowed(input, len), running) }
        else { hsda_text_core::html_decode_bounded(borrowed(input, len), running) };
    match result { Ok(text) => Buffer::from_vec(text), Err(status) => Buffer::error(status) }
}

#[no_mangle]
pub unsafe extern "C" fn hsda_search(input: *const u16, len: usize, query: *const u16,
    query_len: usize, limit: usize) -> Buffer<u32> {
    Buffer::from_vec(hsda_text_core::search_offsets(borrowed(input, len), borrowed(query, query_len), limit))
}

#[no_mangle]
pub unsafe extern "C" fn hsda_source_tag_pairs(input: *const u16, len: usize,
    tag: *const u16, tag_len: usize) -> Buffer<u32> {
    Buffer::from_vec(hsda_text_core::source_html::pairs(borrowed(input, len), borrowed(tag, tag_len)))
}

#[no_mangle]
pub unsafe extern "C" fn hsda_white_border(input: *const u8, len: usize, width: usize,
    height: usize, output: *mut f64) {
    let crop = hsda_text_core::white_border(borrowed(input, len), width, height);
    ptr::copy_nonoverlapping(crop.as_ptr(), output, 4);
}

#[no_mangle]
pub unsafe extern "C" fn hsda_wave(samples: *const f32, len: usize, rate: u32) -> Buffer<u8> {
    match hsda_text_core::wave(borrowed(samples, len), rate) {
        Ok(bytes) => Buffer::from_vec(bytes), Err(status) => Buffer::error(status),
    }
}

#[no_mangle]
pub unsafe extern "C" fn hsda_palmdoc(input: *const u8, len: usize, capacity: usize) -> Buffer<u8> {
    match hsda_ebook_core::palmdoc(borrowed(input, len), capacity) {
        Ok(bytes) => Buffer::from_vec(bytes), Err(status) => Buffer::error(status),
    }
}

#[repr(C)]
pub struct InputBytes { pub data: *const u8, pub len: usize }

#[no_mangle]
pub unsafe extern "C" fn hsda_huff_create(records: *const InputBytes, count: usize,
    capacity: usize, status: *mut u32) -> *mut HuffDecoder {
    let records: Vec<&[u8]> = borrowed(records, count).iter().map(|r| borrowed(r.data, r.len)).collect();
    match HuffDecoder::new(&records, capacity) {
        Ok(decoder) => { *status = 0; Box::into_raw(Box::new(decoder)) }
        Err(error) => { *status = error; ptr::null_mut() }
    }
}

#[no_mangle]
pub unsafe extern "C" fn hsda_huff_unpack(decoder: *mut HuffDecoder, input: *const u8,
    len: usize) -> Buffer<u8> {
    match (*decoder).unpack(borrowed(input, len)) {
        Ok(bytes) => Buffer::from_vec(bytes), Err(status) => Buffer::error(status),
    }
}

#[no_mangle]
pub unsafe extern "C" fn hsda_huff_release(decoder: *mut HuffDecoder) {
    if !decoder.is_null() { drop(Box::from_raw(decoder)); }
}

#[no_mangle]
pub unsafe extern "C" fn hsda_kf8(raw: *const u8, len: usize, records: *const InputBytes,
    count: usize, skeleton_count: usize) -> Buffer<Buffer<u8>> {
    let records: Vec<&[u8]> = borrowed(records, count).iter().map(|r| borrowed(r.data, r.len)).collect();
    match hsda_ebook_core::kf8_sections(borrowed(raw, len), &records[..skeleton_count], &records[skeleton_count..]) {
        Ok(sections) => Buffer::from_vec(sections.into_iter().map(Buffer::from_vec).collect()),
        Err(status) => Buffer::error(status),
    }
}

#[no_mangle]
pub unsafe extern "C" fn hsda_sections_free(buffer: Buffer<Buffer<u8>>) {
    for section in borrowed(buffer.data, buffer.len) {
        free(Buffer { data: section.data, len: section.len, status: section.status });
    }
    free(buffer);
}

#[repr(C)]
pub struct InputText { pub data: *const u16, pub len: usize }

#[no_mangle]
pub unsafe extern "C" fn hsda_epub_body(text: *const u16, len: usize, prefix: *const u16,
    prefix_len: usize, images: *const InputText, count: usize) -> Buffer<u16> {
    let images: Vec<&[u16]> = borrowed(images, count).iter().map(|text| borrowed(text.data, text.len)).collect();
    let cleaned = hsda_text_core::clean_html(borrowed(text, len));
    Buffer::from_vec(hsda_text_core::epub_images(&cleaned, borrowed(prefix, prefix_len), &images))
}

#[repr(C)]
pub struct TxtSection {
    pub title: Buffer<u16>,
    pub content: Buffer<u16>,
    pub preserve_chapter: bool,
}

#[repr(C)]
pub struct RankingBook {
    pub fields: [Buffer<u16>; 8],
    pub rank: f64,
    pub rating: f64,
    pub content_type: u32,
}

#[repr(C)]
pub struct RankingResult { pub books: Buffer<RankingBook>, pub fetched_at: f64 }

#[no_mangle]
pub unsafe extern "C" fn hsda_ranking(input: *const InputText, cached: bool, now: f64) -> RankingResult {
    let values: Vec<String> = borrowed(input, 4).iter()
        .map(|value| String::from_utf16_lossy(borrowed(value.data, value.len))).collect();
    match hsda_ranking_core::parse(&values[0], &values[1], &values[2], &values[3], cached, now) {
        Ok(result) => RankingResult {
            fetched_at: result.fetched_at,
            books: Buffer::from_vec(result.books.into_iter().map(|book| RankingBook {
                fields: [book.id, book.platform, book.title, book.author, book.narrator,
                    book.cover, book.url, book.intro].map(|field| Buffer::from_vec(field.encode_utf16().collect())),
                rank: book.rank, rating: book.rating, content_type: book.content_type,
            }).collect()),
        },
        Err(status) => RankingResult { books: Buffer::error(status), fetched_at: 0.0 },
    }
}

#[no_mangle]
pub unsafe extern "C" fn hsda_ranking_free(result: RankingResult) {
    for book in borrowed(result.books.data, result.books.len) {
        for field in &book.fields {
            free(Buffer { data: field.data, len: field.len, status: field.status });
        }
    }
    free(result.books);
}

#[no_mangle]
pub unsafe extern "C" fn hsda_txt_create(title: *const u16, len: usize) -> *mut TxtImporter {
    Box::into_raw(Box::new(TxtImporter::new(borrowed(title, len))))
}

#[no_mangle]
pub unsafe extern "C" fn hsda_txt_feed(parser: *mut TxtImporter, input: *const u16,
    len: usize, final_chunk: bool) -> Buffer<TxtSection> {
    match (*parser).feed(borrowed(input, len), final_chunk) {
        Ok(sections) => Buffer::from_vec(sections.into_iter().map(|section| TxtSection {
            title: Buffer::from_vec(section.title), content: Buffer::from_vec(section.content),
            preserve_chapter: section.preserve_chapter,
        }).collect()),
        Err(status) => Buffer::error(status),
    }
}

#[no_mangle]
pub unsafe extern "C" fn hsda_txt_release(parser: *mut TxtImporter) {
    if !parser.is_null() { drop(Box::from_raw(parser)); }
}

#[no_mangle]
pub unsafe extern "C" fn hsda_txt_sections_free(buffer: Buffer<TxtSection>) {
    for section in borrowed(buffer.data, buffer.len) {
        free(Buffer { data: section.title.data, len: section.title.len, status: section.title.status });
        free(Buffer { data: section.content.data, len: section.content.len, status: section.content.status });
    }
    free(buffer);
}

#[repr(C)]
pub struct ReaderDisplay { pub text: Buffer<u16>, pub indents: Buffer<u32> }

#[no_mangle]
pub unsafe extern "C" fn hsda_reader_indent(input: *const u16, len: usize, hidden: usize) -> ReaderDisplay {
    let display = hsda_text_core::reader::indent(borrowed(input, len), hidden);
    ReaderDisplay { text: Buffer::from_vec(display.text), indents: Buffer::from_vec(display.indents) }
}

#[no_mangle]
pub unsafe extern "C" fn hsda_reader_display_free(display: ReaderDisplay) {
    free(display.text);
    free(display.indents);
}

#[repr(C)]
pub struct SpeechSegment {
    pub text: Buffer<u16>,
    pub start: usize,
    pub end: usize,
    pub leading: usize,
    pub paragraph_start: usize,
    pub paragraph_end: usize,
}

#[no_mangle]
pub unsafe extern "C" fn hsda_speech_split(input: *const u16, len: usize, boundaries: *const u32,
    count: usize, filter: bool, max_length: usize, hard_limit: usize) -> Buffer<SpeechSegment> {
    Buffer::from_vec(hsda_text_core::speech::split(borrowed(input, len), borrowed(boundaries, count),
        filter, max_length, hard_limit).into_iter().map(|segment| SpeechSegment {
            text: Buffer::from_vec(segment.text), start: segment.start, end: segment.end, leading: segment.leading,
            paragraph_start: segment.paragraph_start, paragraph_end: segment.paragraph_end,
        }).collect())
}

#[no_mangle]
pub unsafe extern "C" fn hsda_speech_free(buffer: Buffer<SpeechSegment>) {
    for segment in borrowed(buffer.data, buffer.len) {
        free(Buffer { data: segment.text.data, len: segment.text.len, status: segment.text.status });
    }
    free(buffer);
}

#[repr(C)]
pub struct SubtitleInput { pub text: InputText, pub start: f64, pub end: f64, pub flag: bool }
#[repr(C)]
pub struct SubtitleSpan { pub text: Buffer<u16>, pub start: f64, pub end: f64, pub flag: bool }
#[repr(C)]
pub struct SubtitleChunk {
    pub index: u32,
    pub annotated: *const SubtitleInput,
    pub annotated_count: usize,
    pub cues: *const SubtitleInput,
    pub cue_count: usize,
}

unsafe fn subtitle_units(input: &[SubtitleInput]) -> Vec<hsda_text_core::subtitle::Unit> {
    input.iter().map(|unit| hsda_text_core::subtitle::Unit {
        text: borrowed(unit.text.data, unit.text.len).to_vec(), start: unit.start, end: unit.end, sentence_end: unit.flag,
    }).collect()
}

fn subtitle_output(units: Vec<hsda_text_core::subtitle::Unit>) -> Buffer<SubtitleSpan> {
    Buffer::from_vec(units.into_iter().map(|unit| SubtitleSpan {
        text: Buffer::from_vec(unit.text), start: unit.start, end: unit.end, flag: unit.sentence_end,
    }).collect())
}

#[no_mangle]
pub unsafe extern "C" fn hsda_subtitle_join(previous: *const SubtitleInput, previous_count: usize,
    current: *const SubtitleInput, current_count: usize, boundary: f64) -> Buffer<SubtitleSpan> {
    subtitle_output(hsda_text_core::subtitle::join(&subtitle_units(borrowed(previous, previous_count)),
        &subtitle_units(borrowed(current, current_count)), boundary))
}

#[no_mangle]
pub unsafe extern "C" fn hsda_subtitle_punctuate(units: *const SubtitleInput, count: usize,
    output: *const u16, len: usize, final_chunk: bool) -> Buffer<SubtitleSpan> {
    subtitle_output(hsda_text_core::subtitle::punctuate(&subtitle_units(borrowed(units, count)),
        borrowed(output, len), final_chunk))
}

#[no_mangle]
pub unsafe extern "C" fn hsda_subtitle_dictionary(words: *const InputText, count: usize)
    -> *mut hsda_text_core::subtitle::Dictionary {
    let words: Vec<&[u16]> = borrowed(words, count).iter().map(|word| borrowed(word.data, word.len)).collect();
    Box::into_raw(Box::new(hsda_text_core::subtitle::dictionary(&words)))
}

#[no_mangle]
pub unsafe extern "C" fn hsda_subtitle_dictionary_free(dictionary: *mut hsda_text_core::subtitle::Dictionary) {
    if !dictionary.is_null() { drop(Box::from_raw(dictionary)); }
}

#[no_mangle]
pub unsafe extern "C" fn hsda_subtitle_timeline(chunks: *const SubtitleChunk, count: usize,
    dictionary: *const hsda_text_core::subtitle::Dictionary) -> Buffer<SubtitleSpan> {
    let chunks = borrowed(chunks, count).iter().map(|chunk| hsda_text_core::subtitle::Chunk {
        index: chunk.index,
        annotated: subtitle_units(borrowed(chunk.annotated, chunk.annotated_count)),
        cues: borrowed(chunk.cues, chunk.cue_count).iter().map(|cue| hsda_text_core::subtitle::Cue {
            text: borrowed(cue.text.data, cue.text.len).to_vec(), start: cue.start, end: cue.end, continues: cue.flag,
        }).collect(),
    }).collect();
    Buffer::from_vec(hsda_text_core::subtitle::timeline(chunks, dictionary.as_ref()).into_iter().map(|cue| SubtitleSpan {
        text: Buffer::from_vec(cue.text), start: cue.start, end: cue.end, flag: cue.continues,
    }).collect())
}

#[no_mangle]
pub unsafe extern "C" fn hsda_subtitle_free(buffer: Buffer<SubtitleSpan>) {
    for unit in borrowed(buffer.data, buffer.len) {
        free(Buffer { data: unit.text.data, len: unit.text.len, status: unit.text.status });
    }
    free(buffer);
}
