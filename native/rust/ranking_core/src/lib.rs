use regex::Regex;
use json::JsonValue as Value;
use std::collections::BTreeSet;
use std::sync::LazyLock;

macro_rules! re {
    ($pattern:literal) => {{
        static PATTERN: LazyLock<Regex> = LazyLock::new(|| Regex::new($pattern).unwrap());
        &*PATTERN
    }};
}

#[derive(Default)]
pub struct Book {
    pub id: String,
    pub platform: String,
    pub title: String,
    pub author: String,
    pub narrator: String,
    pub cover: String,
    pub url: String,
    pub intro: String,
    pub content_type: u32,
    pub rank: f64,
    pub rating: f64,
}

impl Book {
    fn new(platform: &str, id: &str, rank: usize) -> Self {
        Self { id: format!("{platform}:{id}"), platform: platform.into(), rank: rank as f64,
            ..Self::default() }
    }
}

#[derive(Default)]
pub struct Board {
    pub books: Vec<Book>,
    pub fetched_at: f64,
}

fn js_space(c: char) -> bool {
    matches!(c as u32, 0x0009..=0x000d | 0x0020 | 0x00a0 | 0x1680 | 0x2000..=0x200a |
        0x2028 | 0x2029 | 0x202f | 0x205f | 0x3000 | 0xfeff)
}

fn text(html: &str) -> String {
    let value = re!(r"<[^>]*>").replace_all(html, "").replace("&amp;", "&")
        .replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")
        .replace("&#39;", "'").replace("&apos;", "'").replace("&nbsp;", " ")
        .replace('\u{a0}', " ");
    let mut units = Vec::with_capacity(value.len());
    let mut start = 0;
    for capture in re!(r"&#([0-9]+);").captures_iter(&value) {
        let matched = capture.get(0).unwrap();
        units.extend(value[start..matched.start()].encode_utf16());
        units.push((capture[1].parse::<f64>().unwrap_or(0.0) % 65536.0) as u16);
        start = matched.end();
    }
    units.extend(value[start..].encode_utf16());
    let decoded = String::from_utf16_lossy(&units);
    decoded.split(js_space).filter(|part| !part.is_empty()).collect::<Vec<_>>().join(" ")
}

fn raw<'a>(html: &'a str, pattern: &Regex) -> &'a str {
    pattern.captures(html).and_then(|capture| capture.get(1)).map_or("", |value| value.as_str())
}

fn capture(html: &str, pattern: &Regex) -> String { text(raw(html, pattern)) }

fn image_url(value: &str) -> String {
    let value = value.replace("&amp;", "&");
    let clean = value.trim_matches(js_space);
    if clean.starts_with("//") { format!("https:{clean}") }
    else if clean.starts_with("https://") { clean.into() }
    else { String::new() }
}

fn string(value: &Value) -> String {
    match value {
        Value::Null => String::new(),
        Value::String(value) => value.clone(),
        Value::Short(value) => value.to_string(),
        Value::Boolean(value) => value.to_string(),
        Value::Number(value) => value.to_string(),
        Value::Array(value) => value.iter().map(string).collect::<Vec<_>>().join(","),
        Value::Object(_) => "[object Object]".into(),
    }
}

fn int(value: &Value, fallback: f64) -> f64 {
    if value.is_null() { return fallback; }
    if let Some(flag) = value.as_bool() { return if flag { 1.0 } else { 0.0 }; }
    let value = string(value);
    let value = value.trim_matches(js_space);
    if value.is_empty() { return 0.0; }
    value.parse::<f64>().ok().filter(|n| !n.is_nan()).map_or(fallback, f64::trunc)
}

fn array(value: &Value) -> &[Value] {
    if let Value::Array(items) = value { items } else { &[] }
}
fn digits(value: &str) -> bool { !value.is_empty() && value.bytes().all(|c| c.is_ascii_digit()) }

fn rating(value: &str) -> f64 {
    let pattern = re!(r"^([0-9]+(?:\.[0-9]+)?)(?:\s*(分|[%％])|\s*/\s*(100|10))?$");
    let Some(parts) = pattern.captures(value.trim_matches(js_space)) else { return 0.0; };
    let number = parts[1].parse::<f64>().unwrap_or(0.0);
    let maximum = if let Some(scale) = parts.get(3) { scale.as_str().parse::<f64>().unwrap_or(10.0) }
        else if number > 10.0 || parts.get(2).is_some_and(|unit| matches!(unit.as_str(), "%" | "％")) { 100.0 }
        else { 10.0 };
    if number <= 0.0 || number > maximum { 0.0 }
    else if maximum == 100.0 { number / 10.0 } else { number }
}

fn json_rating(item: &Value) -> f64 {
    ["rating", "score", "bookScore", "albumScore"].iter()
        .map(|key| rating(&string(&item[*key]))).find(|value| *value > 0.0).unwrap_or(0.0)
}

fn html_rating(html: &str) -> f64 {
    let attribute = re!(r#"(?i)\bitemprop=["']ratingValue["'][^>]*\bcontent=["']([^"']+)["']"#);
    if let Some(parts) = attribute.captures(html) { return rating(&parts[1]); }
    let element = re!(r#"(?i)\bitemprop=["']ratingValue["'][^>]*>([^<]+)"#);
    if let Some(parts) = element.captures(html) { return rating(&parts[1]); }
    rating(&capture(html, re!(r#"(?is)<(?:span|em|div)\b[^>]*class=["'][^"']*\b(?:score|rating|book-score)\b[^"']*["'][^>]*>(.*?)</"#)))
}

fn parse_json(body: &str) -> Result<Value, u32> { json::parse(body).map_err(|_| 9) }

pub fn parse(platform: &str, board_id: &str, input: &str, glyphs: &str,
    cached: bool, now: f64) -> Result<Board, u32> {
    let (body, fetched_at) = if cached {
        let record = parse_json(input)?;
        let time = int(&record["fetchedAt"], 0.0);
        if time <= 0.0 || time > now + 60000.0 || now - time > 30.0 * 86400000.0 {
            return Ok(Board::default());
        }
        (string(&record["body"]), time)
    } else { (input.to_owned(), 0.0) };
    if body.is_empty() || body.encode_utf16().count() > 2 * 1024 * 1024 { return Ok(Board::default()); }
    let books = match platform {
        "lrts" if body.trim_matches(js_space).starts_with('{') => lanren(&parse_json(&body)?),
        "qqcomic" => qqcomic(&body),
        "bilicomic" => bilicomic(board_id, &body),
        "ximalaya" => ximalaya(board_id, &parse_json(&body)?),
        "qimao" => qimao(&body),
        "jjwxc" => jjwxc(&body),
        "fanqie" => fanqie(board_id, &parse_json(&body)?, glyphs),
        "faloo" => faloo(&body),
        "qidian" => {
            let books = qidian_page(board_id, &body);
            if !books.is_empty() || board_id == "qd-finished" { books }
            else { legacy(platform, &body) }
        }
        _ => legacy(platform, &body),
    };
    Ok(Board { books, fetched_at })
}

fn qqcomic(body: &str) -> Vec<Book> {
    let mut books = Vec::new();
    let mut seen = BTreeSet::new();
    let panels: Vec<&str> = re!(r#"(?i)<div\b[^>]*class=["'][^"']*\brank-tabcon\b[^"']*["'][^>]*>"#).split(body).take(3).collect();
    let (content, pattern) = if panels.len() >= 2 {
        (panels[1], re!(r#"(?is)<ul\b[^>]*class=["']rank-ul["'][^>]*>.*?</ul>"#))
    } else {
        (body, re!(r#"(?is)<ol\b[^>]*class=["'][^"']*\bmod-rank-month-list\b[^"']*["'][^>]*>.*?</ol>"#))
    };
    for list in pattern.find_iter(content) {
        for row in re!(r"(?is)<li\b[^>]*>.*?</li>").find_iter(list.as_str()) {
            if books.len() >= 99 { return books; }
            let html = row.as_str();
            let Some(link) = re!(r#"(?is)<a\b[^>]*href=["']/Comic/ComicInfo/id/([0-9]+)["'][^>]*>(.*?)</a>"#).captures(html) else { continue; };
            let id = &link[1];
            let title = text(&link[2]);
            let rank = capture(html, re!(r"(?i)<(?:em|sub)\b[^>]*>([0-9]+)</(?:em|sub)>")).parse::<f64>().unwrap_or(0.0);
            if title.is_empty() || rank <= 0.0 || seen.contains(id) { continue; }
            let mut book = Book::new("qqcomic", id, 0);
            book.content_type = 2;
            book.title = title;
            book.rank = rank;
            book.url = format!("https://ac.qq.com/Comic/comicInfo/id/{id}");
            seen.insert(id.to_owned());
            books.push(book);
        }
    }
    books
}

fn bilicomic(board_id: &str, body: &str) -> Vec<Book> {
    let data = raw(body, re!(r#"(?is)<script\b[^>]*id=["']vike_pageContext["'][^>]*>(.*?)</script>"#));
    let Ok(root) = parse_json(data) else { return Vec::new(); };
    if string(&root["pageId"]) != "/pages/ranking" ||
        string(&root["routeParams"]["page_id"]) != board_id.strip_prefix("bilicomic-").unwrap_or("") { return Vec::new(); }
    let mut books = Vec::new();
    let mut seen = BTreeSet::new();
    for (index, item) in array(&root["data"]["rankListInfo"]).iter().take(99).enumerate() {
        let id = string(&item["comic_id"]);
        let title = text(&string(&item["title"]));
        if !digits(&id) || title.is_empty() || seen.contains(&id) { continue; }
        let mut book = Book::new("bilicomic", &id, index + 1);
        book.content_type = 2;
        book.title = title;
        book.author = array(&item["author"]).iter().take(10).map(|name| text(&string(name)))
            .filter(|name| !name.is_empty()).collect::<Vec<_>>().join(" / ");
        book.intro = text(&string(&item["comic_introduction"]));
        let value = string(&item["vertical_cover"]);
        let cover = image_url(&re!(r"^http://(i[0-9]+\.hdslb\.com)/").replace(&value, "https://$1/"));
        book.cover = if re!(r"(?i)^https://i[0-9]+\.hdslb\.com/bfs/manga-static/[^/?#@]+\.(?:gif|png|jpe?g|webp)$").is_match(&cover) {
            format!("{cover}@600w.jpg")
        } else { cover };
        book.url = format!("https://manga.bilibili.com/detail/mc{id}");
        seen.insert(id);
        books.push(book);
    }
    books
}

fn lanren_cover(value: &str) -> String {
    re!(r"(bookpic\.lrts\.me/[^/?]+-1-[0-9]+)\.(png|jpg|jpeg)$")
        .replace(&image_url(value), "${1}_600x600.$2").into_owned()
}

fn legacy(platform: &str, body: &str) -> Vec<Book> {
    let pattern = if platform == "qidian" {
        re!(r#"(?s)<a\b[^>]*href="(?:https?:)?//m\.qidian\.com/book/[0-9]+/"[^>]*>.*?</a>"#)
    } else { re!(r#"(?s)<li\s+class="book-item"[^>]*>.*?</li>"#) };
    let mut books = Vec::new();
    let mut seen = BTreeSet::new();
    for row in pattern.find_iter(body).take(100) {
        let html = row.as_str();
        let id = raw(html, re!(r"/book/([0-9]+)"));
        if id.is_empty() || seen.contains(id) { continue; }
        let mut book = Book::new(platform, id, books.len() + 1);
        book.rating = html_rating(html);
        if platform == "qidian" {
            book.title = capture(html, re!(r"(?s)<h2\b[^>]*>(.*?)</h2>"));
            let subtitle = capture(html, re!(r#"(?s)<p\b[^>]*class="[^"]*_subTitle_[^"]*"[^>]*>(.*?)</p>"#));
            book.author = subtitle.split('·').next().unwrap_or("").trim_matches(js_space).into();
            let cover = image_url(raw(html, re!(r#"data-src="([^"]+)""#)));
            book.cover = re!(r"(bookcover\.yuewen\.com/qdbimg/[0-9]+/[0-9]+)/180$").replace(&cover, "$1/600").into_owned();
            book.url = format!("https://m.qidian.com/book/{id}/");
            book.intro = capture(html, re!(r#"(?s)<p\b[^>]*class="[^"]*_bookDesc_[^"]*"[^>]*>(.*?)</p>"#));
        } else {
            book.content_type = 1;
            book.title = capture(html, re!(r#"(?s)<a\b[^>]*class="book-item-name"[^>]*>(.*?)</a>"#));
            book.author = capture(html, re!(r#"(?s)<a\b[^>]*class="author"[^>]*>(.*?)</a>"#));
            book.narrator = capture(html, re!(r"(?s)主播：.*?<a\b[^>]*>(.*?)</a>"));
            book.cover = lanren_cover(raw(html, re!(r#"<img\b[^>]*\bsrc="([^"]+)""#)));
            book.url = format!("https://www.lrts.me/book/{id}");
            book.intro = capture(html, re!(r#"(?s)<p\b[^>]*class="book-item-desc[^"]*"[^>]*>(.*?)</p>"#));
        }
        if book.title.is_empty() { continue; }
        seen.insert(id.to_owned());
        books.push(book);
    }
    books
}

fn lanren(root: &Value) -> Vec<Book> {
    if int(&root["status"], -1.0) != 0.0 || int(&root["apiStatus"], 0.0) != 0.0 { return Vec::new(); }
    let mut books = Vec::new();
    let mut seen = BTreeSet::new();
    for (index, item) in array(&root["data"]["list"]).iter().take(100).enumerate() {
        let id = string(&item["id"]);
        let entity = int(&item["entityType"], 0.0);
        if (entity != 1.0 && entity != 2.0) || !digits(&id) || id.starts_with('0') { continue; }
        let key = if entity == 1.0 { format!("lrts:{id}") } else { format!("lrts:album:{id}") };
        let title = text(&string(&item["name"]));
        if title.is_empty() || seen.contains(&key) { continue; }
        let mut book = Book::new("lrts", &id, index + 1);
        book.id = key.clone();
        book.content_type = 1;
        book.title = title;
        book.author = text(&string(&item["author"]));
        let announcer = string(&item["announcer"]);
        book.narrator = text(&if announcer.is_empty() { string(&item["announcerName"]) } else { announcer });
        book.cover = lanren_cover(&string(&item["cover"]));
        book.url = format!("https://www.lanrentingshu.com/{}/{id}", if entity == 1.0 { "book" } else { "album" });
        let intro = string(&item["desc"]);
        book.intro = text(&if intro.is_empty() { string(&item["recReason"]) } else { intro });
        book.rating = rating(&string(&item["score"]));
        seen.insert(key);
        books.push(book);
    }
    books
}

fn fanqie_text(value: &str, decode: bool, glyphs: &[char]) -> String {
    let value = if decode { value.chars().map(|c| {
        let code = c as usize;
        if code >= 0xe3e8 { glyphs.get(code - 0xe3e8).copied().filter(|c| *c != '\0').unwrap_or(c) }
        else { c }
    }).collect() } else { value.to_owned() };
    let value = text(&value);
    if value.chars().any(|c| ('\u{e000}'..='\u{f8ff}').contains(&c)) { String::new() } else { value }
}

fn fanqie(board_id: &str, root: &Value, glyphs: &str) -> Vec<Book> {
    let category = board_id != "fq-hot";
    if category && string(&root["code"]) != "0" { return Vec::new(); }
    let list = if category { &root["data"]["book_list"] } else { &root["book_list"] };
    let glyphs: Vec<char> = glyphs.chars().collect();
    let mut books = Vec::new();
    let mut seen = BTreeSet::new();
    for (index, item) in array(list).iter().take(99).enumerate() {
        let id = string(&item[if category { "bookId" } else { "book_id" }]);
        let title = fanqie_text(&string(&item[if category { "bookName" } else { "book_name" }]), category, &glyphs);
        if !digits(&id) || title.is_empty() || seen.contains(&id) { continue; }
        let mut book = Book::new("fanqie", &id, index + 1);
        book.title = title;
        book.author = fanqie_text(&string(&item["author"]), category, &glyphs);
        book.cover = image_url(&string(&item[if category { "thumbUri" } else { "thumb_url" }]));
        book.url = format!("https://fanqienovel.com/page/{id}");
        book.intro = fanqie_text(&string(&item[if category { "abstract" } else { "category" }]), category, &glyphs);
        book.rating = json_rating(item);
        let rank = if category { int(&item["currentPos"], 0.0) } else { 0.0 };
        if rank > 0.0 { book.rank = rank; }
        seen.insert(id);
        books.push(book);
    }
    books
}

fn faloo(body: &str) -> Vec<Book> {
    let mut books = Vec::new();
    let mut seen = BTreeSet::new();
    for row in body.split("<div class=\"TwoBox02_02\">").skip(1).take(99) {
        let heading = raw(row, re!(r"(?s)<h1\b[^>]*>(.*?)</h1>"));
        let id = raw(heading, re!(r#"href="(?:https?:)?//b\.faloo\.com/([0-9]+)\.html""#));
        let title = text(heading);
        if id.is_empty() || title.is_empty() || seen.contains(id) { continue; }
        let mut book = Book::new("faloo", id, books.len() + 1);
        book.title = title;
        book.author = capture(row, re!(r#"(?s)<a\b[^>]*href="[^"]*/l_0_1\.html\?t=2[^"]*"[^>]*>(.*?)</a>"#));
        let image = raw(row, re!(r#"<img\b[^>]*\bsrc="([^"]+)""#));
        book.cover = image_url(&re!(r"^http://img\.faloo\.com/").replace(image, "https://img.faloo.com/"));
        book.url = format!("https://b.faloo.com/{id}.html");
        book.intro = capture(row, re!(r#"(?s)<div class="TwoBox02_06">(.*?)</div>"#));
        book.rating = html_rating(row);
        seen.insert(id.to_owned());
        books.push(book);
    }
    books
}

fn qidian_page(board_id: &str, body: &str) -> Vec<Book> {
    let data = raw(body, re!(r#"(?s)<script\b[^>]*\bid=["']vite-plugin-ssr_pageContext["'][^>]*>(.*?)</script>"#));
    let Ok(root) = parse_json(data) else { return Vec::new(); };
    let mut books = Vec::new();
    let mut seen = BTreeSet::new();
    for (index, item) in array(&root["pageContext"]["pageProps"]["pageData"]["records"]).iter().take(100).enumerate() {
        let id = string(&item["bid"]);
        if !digits(&id) || seen.contains(&id) { continue; }
        if board_id == "qd-finished" && !matches!(string(&item["state"]).as_str(), "完本" | "已经完本") { continue; }
        let mut book = Book::new("qidian", &id, index + 1);
        book.title = text(&string(&item["bName"]));
        if book.title.is_empty() { continue; }
        book.author = text(&string(&item["bAuth"]));
        book.intro = text(&string(&item["desc"]));
        book.rating = json_rating(item);
        book.cover = format!("https://bookcover.yuewen.com/qdbimg/349573/{id}/600");
        book.url = format!("https://m.qidian.com/book/{id}/");
        let rank = int(&item["rankNum"], 0.0);
        if rank > 0.0 { book.rank = rank; }
        seen.insert(id);
        books.push(book);
    }
    books
}

fn ximalaya(board_id: &str, root: &Value) -> Vec<Book> {
    if int(&root["ret"], 0.0) != 200.0 { return Vec::new(); }
    let list = if board_id == "xm-free" || board_id == "xm-paid" {
        array(&root["data"][if board_id == "xm-paid" { "paidAlbumRank" } else { "freeAlbumRank" }]["rankListInfo"])
    } else {
        let rank_id = match board_id { "xm-hot" => 48.0, "xm-new" => 71.0, "xm-reputation" => 117.0,
            "xm-vip" => 282.0, _ => return Vec::new() };
        let Some(rank) = array(&root["data"]["rankList"]).iter().find(|rank| int(&rank["rankId"], 0.0) == rank_id)
            else { return Vec::new(); };
        array(&rank["albums"])
    };
    let mut books = Vec::new();
    let mut seen = BTreeSet::new();
    for (index, item) in list.iter().take(100).enumerate() {
        let id = string(&item["id"]);
        if !digits(&id) || seen.contains(&id) { continue; }
        let mut book = Book::new("ximalaya", &id, index + 1);
        book.title = text(&string(&item["albumTitle"]));
        if book.title.is_empty() { continue; }
        book.narrator = text(&string(&item["anchorName"]));
        let cover = string(&item["cover"]);
        book.cover = if re!(r"^(storages/|group[0-9]+/)[A-Za-z0-9_./-]+$").is_match(&cover) {
            format!("https://imagev2.xmcdn.com/{cover}")
        } else { image_url(&cover) };
        book.url = format!("https://www.ximalaya.com/album/{id}");
        book.content_type = 1;
        book.intro = text(&string(&item["description"]));
        book.rating = json_rating(item);
        seen.insert(id);
        books.push(book);
    }
    books
}

fn qimao(body: &str) -> Vec<Book> {
    let mut books = Vec::new();
    let mut seen = BTreeSet::new();
    for row in re!(r#"(?s)<li\b[^>]*class="rank-list-item"[^>]*>.*?</li>"#).find_iter(body).take(100) {
        let html = row.as_str();
        let id = raw(html, re!(r"/shuku/([0-9]+)/"));
        if id.is_empty() || seen.contains(id) { continue; }
        let mut book = Book::new("qimao", id, books.len() + 1);
        book.title = capture(html, re!(r#"(?s)<a\b[^>]*class="s-book-title"[^>]*>(.*?)</a>"#));
        if book.title.is_empty() { continue; }
        book.author = capture(html, re!(r#"(?s)<a\b[^>]*href="[^"]*/zuozhe/[^"]*"[^>]*>(.*?)</a>"#));
        book.cover = image_url(raw(html, re!(r#"<img\b[^>]*\bsrc="([^"]+)""#)));
        book.intro = capture(html, re!(r#"(?s)<span\b[^>]*class="s-book-intro"[^>]*>(.*?)</span>"#));
        book.url = format!("https://www.qimao.com/shuku/{id}/");
        book.rating = html_rating(html);
        seen.insert(id.to_owned());
        books.push(book);
    }
    books
}

fn jjwxc(body: &str) -> Vec<Book> {
    let mut books = Vec::new();
    let mut seen = BTreeSet::new();
    for row in re!(r"(?s)<tr\b[^>]*>.*?</tr>").find_iter(body) {
        if books.len() >= 100 { break; }
        let html = row.as_str();
        let tags: Vec<&str> = re!(r#"<a\b(?:[^"'<>]|"[^"]*"|'[^']*')*>"#).find_iter(html).map(|tag| tag.as_str()).collect();
        let Some(link) = tags.iter().find(|tag| re!(r#"href="onebook\.php\?novelid=[0-9]+""#).is_match(tag)) else { continue; };
        let id = raw(link, re!(r"novelid=([0-9]+)"));
        if id.is_empty() || seen.contains(id) { continue; }
        let mut book = Book::new("jjwxc", id, books.len() + 1);
        book.title = capture(link, re!(r#"\btitle="([^"]+)""#));
        if book.title.is_empty() {
            book.title = capture(html, re!(r#"(?s)<a\b[^>]*href="onebook\.php\?novelid=[0-9]+"[^>]*>(.*?)</a>"#));
        }
        let author = tags.iter().find(|tag| tag.contains("oneauthor.php?authorid=")).copied().unwrap_or("");
        book.author = capture(author, re!(r#"\btitle="([^"]+)""#));
        if book.author.is_empty() {
            book.author = capture(html, re!(r#"(?s)<a\b[^>]*href="oneauthor\.php\?authorid=[0-9]+"[^>]*>(.*?)</a>"#));
        }
        if book.title.is_empty() || book.author.is_empty() { continue; }
        book.intro = capture(link, re!(r#"\brel="([^"]*)""#));
        book.cover = format!("https://i9-static.jjwxc.net/novelimage.php?novelid={id}");
        book.url = format!("https://www.jjwxc.net/onebook.php?novelid={id}");
        seen.insert(id.to_owned());
        books.push(book);
    }
    books
}
