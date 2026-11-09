use std::{ffi::OsStr, path::PathBuf};

const SRC: &str = "src/bpf/network_monitor.bpf.c";
const HDR: &str = "src/bpf/network_monitor.h";

fn main() {
    let out_dir = PathBuf::from(
        std::env::var("OUT_DIR").expect("OUT_DIR environment variable is not set")
    );

    let arch = std::env::var("CARGO_CFG_TARGET_ARCH")
        .expect("CARGO_CFG_TARGET_ARCH environment variable is not set");

    libbpf_cargo::SkeletonBuilder::new()
        .source(SRC)
        .clang_args([
            OsStr::new("-I"),
            vmlinux::include_path_root().join(&arch).as_os_str()
        ])
        .build_and_generate(out_dir.join("network_monitor.skel.rs"))
        .expect("Failed to build and generate skeleton");

    bindgen::Builder::default()
        .header(HDR)
        .generate()
        .expect("Unable to generate bindings")
        .write_to_file(out_dir.join("network_monitor.rs"))
        .expect("Failed to write bindings!");

    println!("cargo:rerun-if-changed={SRC}");
    println!("cargo:rerun-if-changed={HDR}");
}
