// Include the generated BPF skeleton as a Rust module
mod bpf {
    include!(concat!(env!("OUT_DIR"), "/network_monitor.skel.rs"));
}
// Include the generated bindings for the shared header file
mod network_monitor {
    #![allow(dead_code)]
    include!(concat!(env!("OUT_DIR"), "/network_monitor.rs"));
}
use std::sync::{Arc, Mutex};
use std::time::Duration;
use std::{mem::MaybeUninit, sync::Condvar};
use std::os::unix::io::AsFd;
use libbpf_rs::{MapCore, MapFlags};
use libbpf_rs::{TC_EGRESS, TC_INGRESS, TcHookBuilder, skel::{OpenSkel, SkelBuilder}};
use clap::Parser;
use nix::libc::{ETH_P_ARP, ETH_P_IP, ETH_P_IPV6};
use nix::net::if_::if_nametoindex;

#[derive(Parser)]
struct Args {
    /// Name of the network interface to attach the eBPF program to
    interface: String
}

fn ethtype_to_str(ethertype: u16) -> &'static str {
    match ethertype as i32 {
        ETH_P_IP => "IPv4",
        ETH_P_IPV6 => "IPv6",
        ETH_P_ARP => "ARP",
        _ => "Unknown"
    }
}

fn main() -> anyhow::Result<()> {
    // Parse command-line arguments
    let args = Args::parse();
    let ifindex = if_nametoindex(args.interface.as_str())?;

    // Init libbpf skeleton and load eBPF program
    let skel_builder = bpf::NetworkMonitorSkelBuilder::default();
    let mut obj = MaybeUninit::uninit();
    let open_skel = skel_builder.open(&mut obj)?;
    let skel = open_skel.load()?;

    let mut tc_hook_builder = TcHookBuilder::new(skel.progs.tc_prog.as_fd());
    tc_hook_builder.ifindex(ifindex as _);

    let mut tc_ingress_hook = tc_hook_builder.hook(TC_INGRESS)
        .create()? // Make sure to create the qdisc first
        .attach()?;
    let _tc_egress_hook = tc_hook_builder.hook(TC_EGRESS)
        .attach()?;

    // Setup SIGINT handler and terminatio logic
    let term = Arc::new((Mutex::new(false), Condvar::new()));
    let term_clone = Arc::clone(&term);
    ctrlc::set_handler(move || {
        let (lock, cvar) = &*term_clone;
        let mut terminated = lock.lock().unwrap();
        *terminated = true;
        cvar.notify_all();
    })?;

    // Main loop
    let (lock, cvar) = &*term;
    let mut terminated = lock.lock().unwrap();
    while !*terminated {
        terminated = cvar.wait_timeout_while(
            terminated,
            Duration::from_secs(1),
            |terminated| !*terminated
        )
            .unwrap().0;

        for key in skel.maps.l3protos_stats.keys() {
            if let Ok(Some(value)) = skel.maps.l3protos_stats.lookup(&key, MapFlags::ANY) {
                // Notice that the proto is captured as-is by the eBPF program, so it's still in network byte order!
                let proto = u16::from_be(unsafe { *(key.as_ptr() as *const u16) });
                // SAFETY: We know that the value is of type l3proto_stats, plus it's a Copy type, so we can safely dereference it
                let stats = unsafe { *(value.as_ptr() as *const network_monitor::l3proto_stats) };
                println!(
                    "Proto {}: {} pkts, {} bytes",
                    ethtype_to_str(proto),
                    stats.pkts,
                    stats.bytes
                );
            }
        }
        println!();
    }

    // Cleanup TC hooks and qdisc
    tc_ingress_hook
        .attach_point(TC_INGRESS | TC_EGRESS)
        .destroy()?;

    Ok(())
}
