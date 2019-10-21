use serde::{Deserialize, Serialize};
use std::{
    ffi::{CStr, CString},
    time::Duration,
};
use warp::{
    self,
    http::{status::StatusCode, Response},
    Filter,
};
use wrapper::*;

#[derive(Debug, Serialize, Deserialize)]
struct QueryParameters {
    pattern: String,
    whole_words: Option<bool>,
    min_matches: Option<u32>,
}

#[derive(Debug, Serialize)]
struct QueryStats {
    total_count: u32,
    /// Input data size in bytes
    input_size: u64,
    time_taken: Duration,
}

#[derive(Debug, Serialize)]
struct QueryResult {
    query: QueryParameters,
    stats: QueryStats,
    results: Option<Vec<(String, u32)>>,
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

    let mut config = WordMatchRunConfig {
        pattern: pattern.as_ptr(),
        whole_words,
        min_matches,
        mode: 0i32,
    };

    let result = unsafe { word_match_run(&mut config, Some(print_progress), std::ptr::null_mut()).as_ref() };
    if result.is_none() {
        return Err(warp::reject::custom("Null pointer"));
    } else {
        let result = result.unwrap();
        Ok(QueryResult {
            query,
            stats: QueryStats {
                total_count: result.num_word_matches,
                input_size: 1,
                time_taken: Duration::from_micros(result.time_taken.into()),
            },
            results: Some(vec![(
                unsafe {
                    CStr::from_ptr(result.max_page_title)
                        .to_string_lossy()
                        .to_string()
                },
                result.max_word_matches,
            )]),
        })
    }
    // let result = QueryResult {
    //     query,
    //     stats: QueryStats {
    //         total_count: 123,
    //         input_size: 27_000_000_000,
    //         time_taken: Duration::from_secs(1),
    //     },
    //     results: Some(vec![
    //         (String::from("Xilinx"), 1234),
    //         (String::from("FPGA"), 42),
    //         (String::from("Fletcher"), 123),
    //         (String::from("Alveo"), 1),
    //         (String::from("VHDL"), 9001),
    //     ]),
    // };
    // std::thread::sleep(Duration::from_secs(1));
    // Ok(result)
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
