use std::env;
use std::path::PathBuf;

fn main() {
    let mut linkdir = env::current_dir().unwrap();
    linkdir.pop();
    linkdir.push("alveo");
    println!("cargo:rustc-link-search={}", linkdir.display());
    println!("cargo:rustc-link-lib=wordmatch");
    println!("cargo:rerun-if-changed=wrapper.h");
    let bindings = bindgen::Builder::default()
        .header("wrapper.h")
        .generate()
        .expect("Unable to generate bindings");
    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}
