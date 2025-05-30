#!/bin/bash
# run.sh - Manage OpenVPN and NAT rules

exec 1>&1 2>&1
echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: Script started"

# Validate environment variables
if [ -z "$LAN_INTERFACE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: LAN_INTERFACE not set"
    exit 1
fi
if [ -z "$CONF_FILE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: CONF_FILE not set"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: LAN_INTERFACE=$LAN_INTERFACE, CONF_FILE=$CONF_FILE, FORWARD_PORTS=$FORWARD_PORTS"

# Create TUN device
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Creating TUN device"
mkdir -p /dev/net
if ! mknod /dev/net/tun c 10 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to create TUN device"
    exit 1
fi

# Apply iptables rules
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Applying iptables rules"
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE && echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Added MASQUERADE rule" ||
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to add MASQUERADE rule"
iptables -A FORWARD -i tun0 -o $LAN_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT &&
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Added FORWARD rule (tun0 -> $LAN_INTERFACE)" ||
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to add FORWARD rule (tun0 -> $LAN_INTERFACE)"
iptables -A FORWARD -i $LAN_INTERFACE -o tun0 -j ACCEPT &&
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Added FORWARD rule ($LAN-> tun0)" ||
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to add FORWARD rule ($LAN-> tun0)"

for PORT_TUPLE in $FORWARD_PORTS; do
    SPACED=(${PORT_TUPLE//:/ })
    IP=${SPACED[0]}
    PORT_NUMBER=${SPACED[1]}
    PROTO=${SPACED[2]}
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Opening ${PROTO} port ${PORT_NUMBER} for ${IP}"
    iptables -t nat -A PREROUTING -i tun0 -p ${PROTO} --dport ${PORT_NUMBER} -j DNAT --to-destination ${IP} &&
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Added DNAT rule for ${PROTO} ${PORT_NUMBER} to ${IP}" ||
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to add DNAT rule for ${PROTO} ${PORT_NUMBER} to ${IP}"
done

# Set OpenVPN permissions
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Setting chmod 700 on /etc/openvpn"
chmod -R 700 /etc/openvpn || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to chmod /etc/openvpn"
    exit 1
}

# Start OpenVPN as daemon with log file
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Starting OpenVPN as daemon"
touch /var/log/openvpn.log
/usr/sbin/openvpn --daemon --cd /etc/openvpn --config $CONF_FILE --script-security 2 --up /up.sh --log /var/log/openvpn.log
openvpn_pid=$!

echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: OpenVPN started, pid=$openvpn_pid"

# Stream OpenVPN logs to stdout
echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: Streaming OpenVPN logs"
tail -f /var/log/openvpn.log &

# Keep container running
wait $openvpn_pid