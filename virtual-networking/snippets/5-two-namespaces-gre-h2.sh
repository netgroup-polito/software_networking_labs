#!/bin/bash
# Chapter 5: namespaces on two hosts connected through GRE tunnels (configuration of host h2)

# Note: adapt the content of the following variables depending on your configuration
IP_HOST_1=172.16.0.1  # The IP address of the peer host
IP_HOST_2=172.16.0.2  # The IP address of the current host
NIC_HOST_2=enp1s0     # The name of the NIC of the current host

function cleanup {
    set +e

    # Delete all components created by the script
    sudo ip netns del h2-ns
    sudo ip link del h2-veth-root
    sudo ip link del tun0
    sudo ip link del h2-br

    # Delete the NAT rule
    sudo iptables -t nat -D POSTROUTING --source 10.255.1.0/24 -j MASQUERADE
}
trap cleanup EXIT

set -x
set -e

# Enable the forwarding behavior
sudo sysctl net.ipv4.ip_forward=1
sudo iptables -P FORWARD ACCEPT

# Create the network namespace and the veth pair
sudo ip netns add h2-ns
sudo ip link add h2-veth-root type veth peer name h2-veth-ns netns h2-ns

# Set the interfaces 'up' and configure the IP address
sudo ip link set dev h2-veth-root up
sudo ip netns exec h2-ns ip link set dev lo up
sudo ip netns exec h2-ns ip link set dev h2-veth-ns up
sudo ip netns exec h2-ns ip address add 10.255.0.2/24 dev h2-veth-ns

# Leave room for the GRE (gretap) encapsulation overhead (38 bytes)
sudo ip netns exec h2-ns ip link set dev h2-veth-ns mtu 1462

# Create the Linux Bridge and configure the interface
sudo ip link add h2-br type bridge
sudo ip link set dev h2-br up
sudo ip link set dev h2-veth-root master h2-br

# Create and configure the L2 GRE tunnel interface (gretap)
sudo ip link add tun0 type gretap local ${IP_HOST_2} \
    remote ${IP_HOST_1} dev ${NIC_HOST_2}
sudo ip link set dev tun0 up
sudo ip link set dev tun0 master h2-br

# Configure the default gateway (on h1)
sudo ip netns exec h2-ns ip route add default via 10.255.0.254

read -p "L2 tunnel ready. Press ENTER to replace the L2 GRE tunnel with an L3 GRE tunnel..."

# Delete the L2 GRE tunnel interface
sudo ip link del dev tun0

# Update the IP address of the network namespace
sudo ip netns exec h2-ns ip address flush dev h2-veth-ns
sudo ip netns exec h2-ns ip address add 10.255.1.1/24 dev h2-veth-ns

# Configure the default gateway and the NAT rule
sudo ip address add 10.255.1.254/24 dev h2-br
sudo ip netns exec h2-ns ip route add default via 10.255.1.254
sudo iptables -t nat -A POSTROUTING --source 10.255.1.0/24 -j MASQUERADE

# Create and configure the L3 GRE tunnel interface (gre)
sudo ip link add tun0 type gre local ${IP_HOST_2} \
    remote ${IP_HOST_1} dev ${NIC_HOST_2}
sudo ip link set dev tun0 up
sudo ip address add 10.255.255.2/30 dev tun0
sudo ip route add 10.255.0.0/24 via 10.255.255.1

read -p "L3 tunnel ready. Press ENTER to delete the current configuration..."

# When exiting from the script, cleanup() will be executed,
# automatically cleaning up the environment
