use serde::{Deserialize, Serialize};
use std::time::Duration;
use warp::{self, http::Response, Filter};
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
    let result = QueryResult {
        query,
        stats: QueryStats {
            total_count: 123,
            input_size: 27_000_000_000,
            time_taken: Duration::from_secs(1),
        },
        results: Some(vec![
            (String::from("Xilinx"), 1234),
            (String::from("FPGA"), 42),
            (String::from("Fletcher"), 123),
            (String::from("Alveo"), 1),
            (String::from("VHDL"), 9001),
        ]),
    };
    std::thread::sleep(Duration::from_secs(1));
    Ok(result)
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

fn main() {
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

    // Start server
    warp::serve(api).run(([127, 0, 0, 1], 3030));
}
