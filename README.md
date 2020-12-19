# Docker OpenVPN Router

A docker image to provide a NAT router to a VLAN using an OpenVPN tunnel as the upstream connection.

Example Usage:

```
version: '3.7'
services:
    openvpn:
        build: ../docker-openvpn-router
        cap_add:
            - NET_ADMIN
        volumes:
            - config:/etc/openvpn:ro
        networks:
            default:
            external_net:
                ipv4_address: 192.168.1.254     # The IP address which will be used as the router
        environment:
            - LAN_INTERFACE=eth1    # The adapter the `external_net` appears as to the container (eth0 is taken by the default network)
            - CONF_FILE=conf.ovpn   # Name of the ovpn config file to launch
            - FORWARD_PORTS=192.168.1.5:80:TCP 192.168.1.8:3389:TCP 192.168.1.3:25565:UDP
        restart: unless-stopped
    dhcp:
        image: networkboot/dhcpd            # Optionally add a DHCP server to the network
        volumes:
            - ./dhcpd.conf:/data/dhcpd.conf:ro
        network_mode: "service:openvpn"
        restart: unless-stopped
networks:
    external_net:
        driver: macvlan
        driver_opts:
            parent: eth1        # The adapter the LAN is connected to on the docker host
        ipam:
            config:
                - subnet: 192.168.1.1/24
volumes:
    config:
```
