# Network monitoring with eBPF - C control-plane version

## Building

1. Install pre-requirements:
    ```sh
    sudo apt update
    sudo apt install -y clang libelf-dev zlib1g-dev gcc-multilib
    ```
2. Init libbpf and bpftool submodules:
    ```sh
    git submodule update --init --recursive
    ```
3. Build and install libbpf:
    ```sh
    cd ./libbpf/src
    make
    sudo make install
    # Make sure the loader knows where to find libbpf
    sudo ldconfig /usr/lib64
    ```
4. Build and install bpftool:
    ```sh
    cd ./bpftool/src
    make
    sudo make install
    ```
5. Build the eBPF program:
    ```sh
    clang -g -O2 -target bpf -c network_monitor.bpf.c -o network_monitor.bpf.o
    ```
6. Generate the eBPF skeleton:
    ```sh
    bpftool gen skeleton ./network_monitor.bpf.o > network_monitor.skel.h
    ```
7. Build the final application:
    ```sh
    gcc -g -Wall -O2 -o network_monitor network_monitor.c -lbpf
    ```
    Steps 5, 6, and 7 are also included in the project's `Makefile`, so you can equivalently run `make`.
8. Build and run the network monitor:
    ```sh
    make
    sudo ./network_monitor <ifname>
    ```