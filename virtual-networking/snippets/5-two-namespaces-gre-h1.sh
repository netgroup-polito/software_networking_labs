#!/bin/bash
# Chapter 5: namespaces on two hosts connected through GRE tunnels (configuration of host h1)

# Note: adapt the content of the following variables depending on your configuration
IP_HOST_1=172.16.0.1  # The IP address of the current host
IP_HOST_2=172.16.0.2  # The IP address of the peer host
NIC_HOST_1=enp1s0     # The name of the NIC of the current host

function cleanup {
    set +e

    # Delete all components created by the script
    sudo ip netns del h1-ns
    sudo ip link del h1-veth-root
    sudo ip link del tun0
    sudo ip link del h1-br

    # Delete the NAT rule
    sudo iptables -t nat -D POSTROUTING --source 10.255.0.0/24 -j MASQUERADE
}
trap cleanup EXIT

set -x
set -e

# Enable the forwarding behavior
sudo sysctl net.ipv4.ip_forward=1
sudo iptables -P FORWARD ACCEPT

# Create the network namespace and the veth pair
sudo ip netns add h1-ns
sudo ip link add h1-veth-root type veth peer name h1-veth-ns netns h1-ns

# Set the interfaces 'up' and configure the IP address
sudo ip link set dev h1-veth-root up
sudo ip netns exec h1-ns ip link set dev lo up
sudo ip netns exec h1-ns ip link set dev h1-veth-ns up
sudo ip netns exec h1-ns ip address add 10.255.0.1/24 dev h1-veth-ns

# Leave room for the GRE (gretap) encapsulation overhead (38 bytes)
sudo ip netns exec h1-ns ip link set dev h1-veth-ns mtu 1462

# Create the Linux Bridge and configure the interface
sudo ip link add h1-br type bridge
sudo ip link set dev h1-br up
sudo ip link set dev h1-veth-root master h1-br

# Create and configure the L2 GRE tunnel interface (gretap)
sudo ip link add tun0 type gretap local ${IP_HOST_1} \
    remote ${IP_HOST_2} dev ${NIC_HOST_1}
sudo ip link set dev tun0 up
sudo ip link set dev tun0 master h1-br

# Configure the default gateway and the NAT rule
sudo ip address add 10.255.0.254/24 dev h1-br
sudo ip netns exec h1-ns ip route add default via 10.255.0.254
sudo iptables -t nat -A POSTROUTING --source 10.255.0.0/24 -j MASQUERADE

read -p "L2 tunnel ready. Press ENTER to replace the L2 GRE tunnel with an L3 GRE tunnel..."

# Delete the L2 GRE tunnel interface
sudo ip link del dev tun0

# Create and configure the L3 GRE tunnel interface (gre)
sudo ip link add tun0 type gre local ${IP_HOST_1} \
    remote ${IP_HOST_2} dev ${NIC_HOST_1}
sudo ip link set dev tun0 up
sudo ip address add 10.255.255.1/30 dev tun0
sudo ip route add 10.255.1.0/24 via 10.255.255.2

read -p "L3 tunnel ready. Press ENTER to delete the current configuration..."

# When exiting from the script, cleanup() will be executed,
# automatically cleaning up the environment
