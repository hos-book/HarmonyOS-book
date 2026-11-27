use hsda_ebook_core::HuffDecoder;
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
pub unsafe extern "C" fn hsda_epub_images(text: *const u16, len: usize, prefix: *const u16,
    prefix_len: usize, images: *const InputText, count: usize) -> Buffer<u16> {
    let images: Vec<&[u16]> = borrowed(images, count).iter().map(|text| borrowed(text.data, text.len)).collect();
    Buffer::from_vec(hsda_text_core::epub_images(borrowed(text, len), borrowed(prefix, prefix_len), &images))
}
