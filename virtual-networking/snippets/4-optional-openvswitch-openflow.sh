#!/bin/bash
# Chapter 4 (optional part): the VLAN topology built with Open vSwitch, then VLANs replaced by OpenFlow rules
# Requires Open vSwitch (e.g., 'sudo apt install openvswitch-switch')

function cleanup {
    set +e

    # Delete all the veth pairs created by the script
    sudo ip link del veth0-root
    sudo ip link del veth1-root
    sudo ip link del veth2-root
    sudo ip link del veth3-root

    # Delete all the namespaces created by the script
    sudo ip netns del ns1
    sudo ip netns del ns2
    sudo ip netns del ns-br

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

# Perform the OvS configuration (access ports in VLAN 10 and 20)
sudo ovs-vsctl add-br ovs-br0
sudo ovs-vsctl add-port ovs-br0 veth0-root
sudo ovs-vsctl add-port ovs-br0 veth1-root

sudo ovs-vsctl set Port veth0-root tag=10
sudo ovs-vsctl set Port veth1-root tag=20

# Create the third namespace and the Linux Bridge
sudo ip netns add ns-br
sudo ip netns exec ns-br ip link add br0 type bridge
sudo ip netns exec ns-br ip link set dev br0 up

# Create and configure the veth pairs connected to the third namespace
sudo ip link add veth2-root type veth peer name veth2-ns-br netns ns-br
sudo ip link add veth3-root type veth peer name veth3-ns-br netns ns-br

sudo ip link set dev veth2-root up
sudo ovs-vsctl add-port ovs-br0 veth2-root
sudo ovs-vsctl set Port veth2-root tag=10

sudo ip link set dev veth3-root up
sudo ovs-vsctl add-port ovs-br0 veth3-root
sudo ovs-vsctl set Port veth3-root tag=20

sudo ip netns exec ns-br ip link set veth2-ns-br up
sudo ip netns exec ns-br ip link set veth3-ns-br up
sudo ip netns exec ns-br ip link set dev veth2-ns-br master br0
sudo ip netns exec ns-br ip link set dev veth3-ns-br master br0

read -p "OvS VLAN topology ready. Press ENTER to replace the VLAN configuration with OpenFlow rules..."

# Remove the 'NORMAL' flow
sudo ovs-ofctl del-flows ovs-br0 priority=0 --strict

# Delete the VLAN configurations
sudo ovs-vsctl remove port veth0-root tag 10
sudo ovs-vsctl remove port veth1-root tag 20
sudo ovs-vsctl remove port veth2-root tag 10
sudo ovs-vsctl remove port veth3-root tag 20

# Configure the OpenFlow rules
sudo ovs-ofctl add-flow ovs-br0 in_port="veth0-root",actions="veth2-root"
sudo ovs-ofctl add-flow ovs-br0 in_port="veth2-root",actions="veth0-root"
sudo ovs-ofctl add-flow ovs-br0 in_port="veth1-root",actions="veth3-root"
sudo ovs-ofctl add-flow ovs-br0 in_port="veth3-root",actions="veth1-root"

read -p "OpenFlow topology ready. Press ENTER to delete the current configuration..."

# When exiting from the script, cleanup() will be executed,
# automatically cleaning up the environment
