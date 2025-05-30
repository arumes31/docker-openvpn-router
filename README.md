# Docker OpenVPN Router

A docker image to provide a NAT router to a VLAN using an OpenVPN tunnel as the upstream connection.

Image x86: registry.reitetschlaeger.com/latest

Image arm: registry.reitetschlaeger.com/arm64

## Usage

```
services:
    openvpn:
        image: registry.reitetschlaeger.com:latest
        cap_add:
            - NET_ADMIN                         # Required so that the container can run iptables rules
        volumes:
            - config:/etc/openvpn:ro            # Your OpenVPN config file, keys, etc.
        networks:
            default:                            # Use default network for Internet to connect to OpenVPN server
            external_vlan:
                ipv4_address: 192.168.1.254     # The IP address this container will use on the VLAN
        environment:
            - LAN_INTERFACE=eth1    # The adapter the `external_vlan` appears as to the container (eth0 will be taken by the default network)
            - CONF_FILE=conf.ovpn   # Name of the ovpn config file to launch
            - FORWARD_PORTS=192.168.1.5:80:TCP 192.168.1.8:3389:TCP 192.168.1.3:25565:UDP   # Optional list in format IP:PORT:PROTO
        restart: unless-stopped
    dhcp:
        image: networkboot/dhcpd            # Optionally add a DHCP server to the network
        volumes:
            - ./dhcpd.conf:/data/dhcpd.conf:ro
        network_mode: "service:openvpn"
        restart: unless-stopped
networks:
    external_vlan:  # Note: If connected to a virtual network switch, then make sure MAC Address Spoofing is allowed   
        driver: macvlan
        driver_opts:
            parent: eth1        # The adapter the VLAN is connected to on the docker host
        ipam:
            config:
                - subnet: 192.168.1.1/24
volumes:
    config:
```
