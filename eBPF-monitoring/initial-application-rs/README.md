# Network monitoring with eBPF - Rust control-plane version

## Building

1. Install Rust toolchain (e.g., via `rustup` or via your distro's package manager)
2. Install required dependencies
3. Build and run the network monitor:
    ```sh
    cargo build --release
    sudo target/release/network-monitor-ebpf-rs <ifname>
    ```
    Note that the compilation of the eBPF program with `clang` and generation of the libbpf skeleton are all included in the `build.rs` file, and as such are performed automatically on crate build.