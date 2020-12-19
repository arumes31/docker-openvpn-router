#!/usr/bin/env bash

if [ -z "$LAN_INTERFACE" ]
then
      echo "LAN_INTERFACE not set" && exit 1
fi
if [ -z "$CONF_FILE" ]
then
      echo "CONF_FILE not set" && exit 1
fi

mkdir -p /dev/net
mknod /dev/net/tun c 10 200

echo "Routing from $LAN_INTERFACE to tun0"
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
iptables -A FORWARD -i tun0 -o $LAN_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $LAN_INTERFACE -o tun0 -j ACCEPT

for PORT_TUPLE in $FORWARD_PORTS
do
    SPACED=(${PORT_TUPLE//:/ })
    IP=${SPACED[0]}
    PORT_NUMBER=${SPACED[1]}
    PROTO=${SPACED[2]}
    echo "Opening ${PROTO} port ${PORT_NUMBER} for ${IP}"
    iptables -t nat -A PREROUTING -i tun0 -p ${PROTO} --dport ${PORT_NUMBER} -j DNAT --to-destination ${IP}
done

chmod -R 700 /etc/openvpn
exec /usr/sbin/openvpn --cd /etc/openvpn --config $CONF_FILE
