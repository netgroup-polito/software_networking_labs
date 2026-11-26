#!/bin/bash
# Chapter 4: two network namespaces connected through a third namespace
#   1) Linux Bridge with VLANs in the root namespace + Linux Bridge in ns-br
#   2) direct connections to the Linux Bridge in ns-br
#   3) router in ns-br

function cleanup {
    set +e

    # Delete all the veth pairs created by the script
    # (the ones moved into ns-br are deleted together with that namespace)
    sudo ip link del veth0-root
    sudo ip link del veth1-root
    sudo ip link del veth2-root
    sudo ip link del veth3-root

    # Delete all the namespaces created by the script
    sudo ip netns del ns1
    sudo ip netns del ns2
    sudo ip netns del ns-br

    # Delete the virtual switch in the root namespace
    sudo ip link del br0
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

# Linux Bridge in the root namespace, with VLAN filtering enabled
sudo ip link add br0 type bridge
sudo ip link set dev br0 up
sudo ip link set dev veth0-root master br0
sudo ip link set dev veth1-root master br0
sudo ip link set dev br0 type bridge vlan_filtering 1

# veth0-root: access port in VLAN 10; veth1-root: access port in VLAN 20
sudo bridge vlan del dev veth0-root vid 1
sudo bridge vlan add dev veth0-root vid 10 pvid untagged
sudo bridge vlan del dev veth1-root vid 1
sudo bridge vlan add dev veth1-root vid 20 pvid untagged

# Create the third namespace and its Linux Bridge
sudo ip netns add ns-br
sudo ip netns exec ns-br ip link add br0 type bridge
sudo ip netns exec ns-br ip link set dev br0 up

# Create and configure the veth pairs connected to the third namespace
sudo ip link add veth2-root type veth peer name veth2-ns-br netns ns-br
sudo ip link add veth3-root type veth peer name veth3-ns-br netns ns-br

sudo ip link set dev veth2-root up
sudo ip link set dev veth2-root master br0
sudo bridge vlan del dev veth2-root vid 1
sudo bridge vlan add dev veth2-root vid 10 pvid untagged

sudo ip link set dev veth3-root up
sudo ip link set dev veth3-root master br0
sudo bridge vlan del dev veth3-root vid 1
sudo bridge vlan add dev veth3-root vid 20 pvid untagged

sudo ip netns exec ns-br ip link set veth2-ns-br up
sudo ip netns exec ns-br ip link set veth3-ns-br up
sudo ip netns exec ns-br ip link set dev veth2-ns-br master br0
sudo ip netns exec ns-br ip link set dev veth3-ns-br master br0

read -p "VLAN topology ready. Press ENTER to replace it with direct connections..."

# Delete the Linux Bridge from the root namespace, and the veth pairs in excess
sudo ip link del br0
sudo ip link del veth2-root
sudo ip link del veth3-root

# Configure the direct interconnection between the namespaces
sudo ip link set veth0-root netns ns-br
sudo ip link set veth1-root netns ns-br
sudo ip netns exec ns-br ip link set veth0-root up
sudo ip netns exec ns-br ip link set veth1-root up
sudo ip netns exec ns-br ip link set dev veth0-root master br0
sudo ip netns exec ns-br ip link set dev veth1-root master br0

read -p "Direct topology ready. Press ENTER to replace the Linux Bridge with a router..."

# Remove the virtual switch
sudo ip netns exec ns-br ip link del br0

# Edit the IP configuration of ns2
sudo ip netns exec ns2 ip addr flush dev veth1-ns2
sudo ip netns exec ns2 ip addr add 10.255.1.1/24 dev veth1-ns2

# Configure the IP addresses of the router
sudo ip netns exec ns-br ip addr add 10.255.0.254/24 dev veth0-root
sudo ip netns exec ns-br ip addr add 10.255.1.254/24 dev veth1-root

# Add the appropriate routes
sudo ip netns exec ns1 ip route add 10.255.1.0/24 via 10.255.0.254
sudo ip netns exec ns2 ip route add 10.255.0.0/24 via 10.255.1.254

# Ensure forwarding is enabled
sudo ip netns exec ns-br sysctl net.ipv4.ip_forward=1

read -p "Router topology ready. Press ENTER to delete the current configuration..."

# When exiting from the script, cleanup() will be executed,
# automatically cleaning up the environment
