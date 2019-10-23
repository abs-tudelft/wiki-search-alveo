use serde::{Deserialize, Serialize};
use std::{
    ffi::{CStr, CString},
    collections::HashMap,
    slice::from_raw_parts,
};
use warp::{
    self,
    http::Response,
    Filter,
};
use wrapper::*;

#[derive(Debug, Serialize, Deserialize)]
struct QueryParameters {
    pattern: String,
    whole_words: Option<bool>,
    min_matches: Option<u32>,
    mode: Option<i32>,
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
    query: QueryParameters,
    stats: QueryStats,
    top_result: Option<(String, u32)>,
    top_ten_results: Vec<(String, u32)>,
    other_results: Vec<(String, u32)>,
}

#[derive(Debug, Serialize, Deserialize)]
struct WikiImageParameters {
    article: String,
}

impl warp::Reply for QueryResult {
    fn into_response(self) -> warp::reply::Response {
        Response::new(serde_json::to_string(&self).unwrap().into())
    }
}

fn go_query(query: QueryParameters) -> Result<impl warp::Reply, warp::Rejection> {
    let pattern = CString::new(query.pattern.as_str()).unwrap();
    let whole_words = if let Some(x) = query.whole_words {
        if x {
            1
        } else {
            0
        }
    } else {
        0
    };
    let min_matches = if let Some(x) = query.min_matches {
        x
    } else {
        1u32
    };
    let mode = if let Some(x) = query.mode {
        x
    } else {
        0i32
    };

    let mut config = WordMatchRunConfig {
        pattern: pattern.as_ptr(),
        whole_words,
        min_matches,
        mode,
    };

    let result = unsafe { word_match_run(&mut config, Some(print_progress), std::ptr::null_mut()).as_ref() };
    if result.is_none() {
        return Err(warp::reject::custom("Null pointer"));
    } else {
        let result = result.unwrap();

        // Whether all matching results were returned, or there were
        // more matches than result slots in at least one of the chunks.
        let mut all_known = true;

        // Approximate number of compressed bytes processed in total.
        let mut input_size = 0u64;

        let mut results = HashMap::new();
        for partial in unsafe {from_raw_parts(result.partial_results, result.num_partial_results as usize)} {
            let partial = unsafe {**partial};

            // Always add the page with the most matches.
            if partial.max_word_matches >= min_matches {
                results.insert(
                    unsafe {
                        CStr::from_ptr(partial.max_page_title)
                            .to_string_lossy()
                            .to_string()
                    },
                    partial.max_word_matches
                );
            }

            // Add the N first matches found for this chunk.
            let num_records = partial.num_page_match_records as usize;
            let title_values = unsafe {
                CStr::from_ptr(partial.page_match_title_values)
                    .to_string_lossy()
                    .to_string()
            };
            let title_offsets = unsafe {
                from_raw_parts(
                    partial.page_match_title_offsets,
                    num_records + 1
                )
            };
            let match_counts = unsafe {
                from_raw_parts(
                    partial.page_match_counts,
                    num_records
                )
            };
            for i in 0..num_records as usize {
                let start = title_offsets[i] as usize;
                let stop = title_offsets[i + 1] as usize;
                results.insert(
                    title_values[start..stop].to_string(),
                    match_counts[i]
                );
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

        // Separate into the top result, the subsequent 9 in the top 10, and
        // the remaining results for a nice layout in the web UI. It's easier
        // to do here than in TypeScript.
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

        Ok(QueryResult {
            query,
            stats: QueryStats {
                num_word_matches: result.num_word_matches,
                num_page_matches: result.num_page_matches,
                num_result_records,
                input_size,
                time_taken_ms: result.time_taken / 1000,
                bandwidth: format!("{:.2} GB/s", ((input_size as f32) / (result.time_taken as f32)) / 1000f32),
            },
            top_result,
            top_ten_results,
            other_results,
        })
    }
}

/// dont-ask
fn get_wiki_img(query: WikiImageParameters) -> Result<impl warp::Reply, warp::Rejection> {
    let client = reqwest::Client::new();
    let result: serde_json::Value = client
        .get("https://en.wikipedia.org/w/api.php")
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
        .expect("Missing page");
    let url = pages
        .get(
            pages
                .as_object()
                .expect("Bad pages map")
                .keys()
                .next()
                .expect("No page"),
        )
        .unwrap()
        .get("thumbnail")
        .expect("No thumbnail")
        .get("source")
        .expect("No source")
        .as_str()
        .unwrap()
        .to_owned();
    let mut buf = vec![];
    let mut img = client.get(&url).send().expect("failed to get image");
    let mut response = Response::builder();
    for (key, value) in img.headers() {
        response.header(key, value);
    }
    img.copy_to(&mut buf).unwrap();
    Ok(response.body(buf).unwrap())
}

extern "C" fn print_progress(
    _: *mut ::std::os::raw::c_void,
    status: *const ::std::os::raw::c_char,
) {
    println!("{}", unsafe {
        CStr::from_ptr(status).to_string_lossy()
    });
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

    // Construct
    let api = query.or(wiki_img).or(client);

    // Host application configuration setup
    let data_prefix = CString::new("/work/mbrobbel/wiki/enwiki-no-meta/enwiki-no-meta").unwrap();
    let xclbin_prefix =
        CString::new("/work/shared/fletcher-alveo/fletcher-alveo-demo-10/alveo/xclbin/word_match")
            .unwrap();
//     let data_prefix = CString::new("/work/shared/fletcher-alveo/simplewiki").unwrap();
//     let xclbin_prefix = CString::new("").unwrap();
    let emu_mode = CString::new("hw").unwrap();
    let kernel_name = CString::new("krnl_word_match_rtl").unwrap();

    let mut test_config = WordMatchPlatformConfig {
        data_prefix: data_prefix.as_ptr(),
        xclbin_prefix: xclbin_prefix.as_ptr(),
        emu_mode: emu_mode.as_ptr(),
        kernel_name: kernel_name.as_ptr(),
        keep_loaded: 1i32,
    };

    // Initialize
    let test_fpga = unsafe { word_match_init(&mut test_config, 0i32, Some(print_progress), std::ptr::null_mut()) };
    if test_fpga == 0 {
        let error = unsafe { word_match_last_error() };
        eprintln!("Init failed: {}", unsafe {
            CStr::from_ptr(error).to_string_lossy()
        });
        unsafe { word_match_release() };
        return Err(());
    }

    // Start server
    let port = 3030;
    println!("Starting server on port {}", port);
    warp::serve(api).run(([127, 0, 0, 1], port));

    println!("Cleaning up");
    unsafe { word_match_release() };

    Ok(())
}
