#[macro_use]
extern crate lazy_static;

use crypto::{digest::Digest, sha1::Sha1};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    ffi::{CStr, CString},
    fs::File,
    io::{Read, Write},
    ops::{Deref, DerefMut},
    path::Path,
    slice::from_raw_parts,
    sync::Mutex,
};
use warp::{self, http::Response, Filter};
use wrapper::*;

#[derive(Debug, Serialize, Deserialize)]
struct QueryParameters {
    pattern: String,
    whole_words: Option<bool>,
    min_matches: Option<u32>,
    mode: Option<i32>,
    wiki: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct CompletedQueryParameters {
    pattern: String,
    whole_words: bool,
    min_matches: u32,
    mode: i32,
    wiki: String,
}

#[derive(Debug, Serialize)]
struct QueryStats {
    num_word_matches: u32,
    num_page_matches: u32,
    num_result_records: u32,
    input_size: u64,
    time_taken_ms: u32,
    bandwidth: String,
}

#[derive(Debug, Serialize)]
struct QueryResult {
    query: CompletedQueryParameters,
    stats: QueryStats,
    top_result: Option<(String, u32)>,
    top_ten_results: Vec<(String, u32)>,
    other_results: Vec<(String, u32)>,
}

impl warp::Reply for QueryResult {
    fn into_response(self) -> warp::reply::Response {
        Response::new(serde_json::to_string(&self).unwrap().into())
    }
}

#[derive(Debug, Serialize, Deserialize)]
struct WikiImageParameters {
    article: String,
    wiki: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct WikiImageCacheRecord {
    data: Vec<u8>,
    headers: Vec<(String, String)>,
}

#[derive(Debug, Serialize)]
struct ServerStatus {
    status: String,
    fpga_temp: f32,
    power_in: f32,
    power_vccint: f32,
}

impl warp::Reply for ServerStatus {
    fn into_response(self) -> warp::reply::Response {
        Response::new(serde_json::to_string(&self).unwrap().into())
    }
}

lazy_static! {
    static ref FFI_STATUS: Mutex<String> = Mutex::new("unknown".to_string());
}

fn go_query(query: QueryParameters) -> Result<impl warp::Reply, warp::Rejection> {
    println!("-> query");

    // Complete query by substituting default values.
    let query = CompletedQueryParameters {
        pattern: query.pattern,
        whole_words: if let Some(x) = query.whole_words {
            x
        } else {
            false
        },
        min_matches: if let Some(x) = query.min_matches {
            x
        } else {
            1
        },
        mode: if let Some(x) = query.mode { x } else { 0 },
        wiki: if let Some(x) = query.wiki {
            x
        } else {
            "en".to_string()
        },
    };

    // Check query validity.
    if &query.wiki != "en" {
        return Err(warp::reject::custom("unknown Wiki language"));
    }

    // Convert Rust query structure to FFI structure.
    let pattern = CString::new(query.pattern.as_str()).unwrap();
    let mut config = WordMatchRunConfig {
        pattern: pattern.as_ptr(),
        whole_words: if query.whole_words { 1 } else { 0 },
        min_matches: query.min_matches,
        mode: query.mode,
    };

    // Run the kernel.
    let result = unsafe {
        word_match_run(&mut config, Some(ffi_update_status), std::ptr::null_mut()).as_ref()
    };
    update_status("Ready");
    let retval = if result.is_none() {
        Err(warp::reject::custom(get_last_error()))
    } else {
        let result = result.unwrap();

        // Whether all matching results were returned, or there were
        // more matches than result slots in at least one of the chunks.
        let mut all_known = true;

        // Approximate number of compressed bytes processed in total.
        let mut input_size = 0u64;

        let mut results = HashMap::new();
        for partial in
            unsafe { from_raw_parts(result.partial_results, result.num_partial_results as usize) }
        {
            let partial = unsafe { **partial };

            // Always add the page with the most matches.
            if partial.max_word_matches >= query.min_matches {
                results.insert(
                    unsafe {
                        CStr::from_ptr(partial.max_page_title)
                            .to_string_lossy()
                            .to_string()
                    },
                    partial.max_word_matches,
                );
            }

            // Add the N first matches found for this chunk.
            let num_records = partial.num_page_match_records as usize;
            let title_values = unsafe {
                CStr::from_ptr(partial.page_match_title_values)
                    .to_string_lossy()
                    .to_string()
            };
            let title_offsets =
                unsafe { from_raw_parts(partial.page_match_title_offsets, num_records + 1) };
            let match_counts = unsafe { from_raw_parts(partial.page_match_counts, num_records) };
            for i in 0..num_records as usize {
                let start = title_offsets[i] as usize;
                let stop = title_offsets[i + 1] as usize;
                results.insert(title_values[start..stop].to_string(), match_counts[i]);
            }

            // Check if there were more matches in this chunk than there was room for.
            if partial.num_page_match_records < partial.num_page_matches {
                all_known = false;
            }

            // Accumulate input size.
            input_size += partial.data_size as u64;
        }

        // Sort the results.
        let mut results: Vec<(String, u32)> = results.into_iter().collect();
        results.sort_by(|(at, ac), (bt, bc)| (bc, at).partial_cmp(&(ac, bt)).unwrap());
        let num_result_records = results.len() as u32;

        // Separate into the top result, the subsequent 9 in the top 10 if the
        // sorting is valid, and 90 of the remaining results for a nice layout
        // in the web UI. It's easier to do here than in TypeScript/Vue.
        let mut results = results.drain(..);
        let top_result = results.next();
        let mut top_ten_results = Vec::new();
        if all_known {
            for _ in 1..10 {
                if let Some(record) = results.next() {
                    top_ten_results.push(record);
                } else {
                    break;
                }
            }
        }
        let other_results = results.take(90).collect();

        // Return the query data.
        Ok(QueryResult {
            query,
            stats: QueryStats {
                num_word_matches: result.num_word_matches,
                num_page_matches: result.num_page_matches,
                num_result_records,
                input_size,
                time_taken_ms: result.time_taken / 1000,
                bandwidth: format!(
                    "{:.2} GB/s",
                    ((input_size as f32) / (result.time_taken as f32)) / 1000f32
                ),
            },
            top_result,
            top_ten_results,
            other_results,
        })
    };
    println!("<- query");
    retval
}

/// dont-ask
fn fetch_wiki_img(query: WikiImageParameters) -> Result<WikiImageCacheRecord, warp::Rejection> {
    // Lots of abuse going on in this function:
    //  - Ok(record) means that the Wikipedia API was queried successfully and
    //    an image was found.
    //  - Err(_) means that the Wikipedia API was queried successfully (!) but
    //    no image was found.
    //  - expect() is used to indicate a failed API query; the panic prevents
    //    writing to cache and is caught by the server.
    //  - unwrap() is used for things that should never go wrong.
    let client = reqwest::Client::new();
    let result: serde_json::Value = client
        .get(&format!("https://{}.wikipedia.org/w/api.php", &query.wiki))
        .query(&[
            ("action", "query"),
            ("titles", &query.article),
            ("prop", "pageimages"),
            ("format", "json"),
            ("pithumbsize", "1000"),
        ])
        .send()
        .expect("Failed to send wiki req")
        .json()
        .expect("Failed to parse wiki res");
    let pages = result
        .get("query")
        .expect("Bad response from wiki api")
        .get("pages")
        .ok_or_else(|| warp::reject::custom("Missing page"))?;
    let url = pages
        .get(
            pages
                .as_object()
                .ok_or_else(|| warp::reject::custom("Bad pages map"))?
                .keys()
                .next()
                .ok_or_else(|| warp::reject::custom("No page"))?,
        )
        .unwrap()
        .get("thumbnail")
        .ok_or_else(|| warp::reject::custom("No thumbnail"))?
        .get("source")
        .ok_or_else(|| warp::reject::custom("No source"))?
        .as_str()
        .unwrap()
        .to_owned();
    let mut img = client.get(&url).send().expect("failed to get image");
    let mut record = WikiImageCacheRecord {
        data: vec![],
        headers: vec![],
    };
    img.copy_to(&mut record.data).unwrap();
    for (key, value) in img.headers() {
        record
            .headers
            .push((key.to_string(), value.to_str().unwrap().to_string()));
    }
    Ok(record)
}

fn get_wiki_img(query: WikiImageParameters) -> Result<impl warp::Reply, warp::Rejection> {
    println!("-> wiki_img");

    // Get the filename for the cache.
    let mut hasher = Sha1::new();
    hasher.input_str(&query.wiki);
    hasher.input_str("###");
    hasher.input_str(&query.article);
    let path = Path::new("./cache").join(hasher.result_str());

    let record: WikiImageCacheRecord = if path.exists() {
        // Read from cache.
        let mut buf = vec![];
        File::open(path)
            .expect("Failed to open cached image")
            .read_to_end(&mut buf)
            .expect("Failed to read cached image");
        bincode::deserialize(&buf).unwrap()
    } else {
        // Fetch from Wikipedia.
        let response = fetch_wiki_img(query);
        let record = if let Ok(record) = response {
            record
        } else {
            WikiImageCacheRecord {
                data: include_bytes!("whitepix.png").to_vec(),
                headers: vec![("Content-Type".to_string(), "image/png".to_string())],
            }
        };

        // Update the cache.
        let buf: Vec<u8> = bincode::serialize(&record).unwrap();
        File::create(path)
            .expect("Failed to create cached image")
            .write_all(&buf)
            .expect("Failed to write cached image");

        record
    };

    let mut response = Response::builder();
    for (key, value) in record.headers {
        response.header(&key, &value);
    }
    println!("<- wiki_img");
    Ok(response.body(record.data).unwrap())
}

fn get_status() -> Result<impl warp::Reply, warp::Rejection> {
    println!("-> status");
    let health = unsafe { word_match_health() };
    let static_status = FFI_STATUS.lock().unwrap();
    let retval = Ok(ServerStatus {
        status: static_status.deref().to_string(),
        fpga_temp: health.fpga_temp,
        power_in: health.power_in,
        power_vccint: health.power_vccint,
    });
    println!("<- status");
    retval
}

fn update_status(status: &str) {
    println!("{}", status);
    let mut static_status = FFI_STATUS.lock().unwrap();
    static_status.deref_mut().replace_range(.., &status);
}

extern "C" fn ffi_update_status(
    _: *mut ::std::os::raw::c_void,
    status: *const ::std::os::raw::c_char,
) {
    update_status(&unsafe { CStr::from_ptr(status).to_string_lossy() });
}

fn get_last_error() -> String {
    unsafe {
        return CStr::from_ptr(word_match_last_error())
            .to_string_lossy()
            .to_string();
    };
}

fn main() -> Result<(), ()> {
    // Serve client files
    // TODO(mb): serve at /static?
    let client = warp::fs::dir("../client/dist");

    // Query endpoint
    let query = warp::get2()
        .and(warp::path("query"))
        .and(warp::query::<QueryParameters>())
        .and_then(go_query);

    // Wikipedia image endpoint
    let wiki_img = warp::get2()
        .and(warp::path("wiki_img"))
        .and(warp::query::<WikiImageParameters>())
        .and_then(get_wiki_img);

    // Status query endpoint
    let status = warp::get2().and(warp::path("status")).and_then(get_status);

    // Construct
    let api = query.or(wiki_img).or(client).or(status);

    // Host application configuration setup
    let data_prefix = CString::new("/work/shared/fletcher-alveo/enwiki-no-meta").unwrap();
    let xclbin_prefix =
        CString::new("/work/shared/fletcher-alveo/fletcher-alveo-demo/alveo/xclbin/word_match")
            .unwrap();
    let emu_mode = CString::new("hw").unwrap();
    let kernel_name = CString::new("krnl_word_match_rtl").unwrap();

    let mut test_config = WordMatchPlatformConfig {
        data_prefix: data_prefix.as_ptr(),
        xclbin_prefix: xclbin_prefix.as_ptr(),
        emu_mode: emu_mode.as_ptr(),
        kernel_name: kernel_name.as_ptr(),
        num_subkernels: 3u32,
        keep_loaded: 1i32,
    };

    // Initialize
    let test_fpga = unsafe {
        word_match_init(
            &mut test_config,
            0i32,
            Some(ffi_update_status),
            std::ptr::null_mut(),
        )
    };
    if test_fpga == 0 {
        eprintln!("Init failed: {}", get_last_error());
        unsafe { word_match_release() };
        return Err(());
    }
    update_status("Ready");

    // Start server
    let port = 3030;
    println!("Starting server on port {}", port);
    warp::serve(api).run(([127, 0, 0, 1], port));

    println!("Cleaning up");
    unsafe { word_match_release() };

    Ok(())
}
