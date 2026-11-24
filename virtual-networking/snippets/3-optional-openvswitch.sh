#!/bin/bash
# Chapter 3 (optional part): the same topology, with an Open vSwitch bridge instead of the Linux Bridge
# Requires Open vSwitch (e.g., 'sudo apt install openvswitch-switch')

function cleanup {
    set +e

    # Delete all the veth pairs created by the script
    sudo ip link del veth0-root
    sudo ip link del veth1-root

    # Delete all the namespaces created by the script
    sudo ip netns del ns1
    sudo ip netns del ns2

    # Delete the virtual switch created by the script
    sudo ovs-vsctl del-br ovs-br0
}
trap cleanup EXIT

set -x
set -e

# Create all the required namespaces and veth pairs
sudo ip netns add ns1
sudo ip netns add ns2

sudo ip netns exec ns1 ip link set dev lo up
sudo ip netns exec ns2 ip link set dev lo up
sudo ip link add veth0-root type veth peer name veth0-ns1 netns ns1
sudo ip link add veth1-root type veth peer name veth1-ns2 netns ns2

sudo ip link set dev veth0-root up
sudo ip link set dev veth1-root up
sudo ip netns exec ns1 ip link set veth0-ns1 up
sudo ip netns exec ns2 ip link set veth1-ns2 up
sudo ip netns exec ns1 ip addr add 10.255.0.1/24 dev veth0-ns1
sudo ip netns exec ns2 ip addr add 10.255.0.2/24 dev veth1-ns2

# Perform the OvS configuration
sudo ovs-vsctl add-br ovs-br0
sudo ovs-vsctl add-port ovs-br0 veth0-root
sudo ovs-vsctl add-port ovs-br0 veth1-root

read -p "Configuration complete (try: sudo ip netns exec ns1 ping 10.255.0.2). Press ENTER to delete it..."

# When exiting from the script, cleanup() will be executed,
# automatically cleaning up the environment
