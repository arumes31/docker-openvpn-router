#!/bin/bash
# healthcheck.sh - Check VPN and NAT rules

# Ensure output goes to stdout and stderr
exec 1>&1 2>&1

LAN_INTERFACE="${LAN_INTERFACE:-eth0}"
FORWARD_PORTS="${FORWARD_PORTS:-}"

# Check tun0 interface
if ! ip link show tun0 >/dev/null 2>&1; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: tun0 interface not present"
    exit 1
fi

# Check VPN connectivity
if ! ping -c 1 -I tun0 8.8.8.8 >/dev/null 2>&1; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Ping via tun0 failed"
    exit 1
fi

# Check iptables rules
if ! iptables -t nat -C POSTROUTING -o tun0 -j MASQUERADE 2>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: MASQUERADE rule missing"
    exit 1
fi

if ! iptables -C FORWARD -i tun0 -o $LAN_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: FORWARD rule (tun0 -> $LAN_INTERFACE) missing"
    exit 1
fi

if ! iptables -C FORWARD -i $LAN_INTERFACE -o tun0 -j ACCEPT 2>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: FORWARD rule ($LAN-> tun0) missing"
    exit 1
fi

for PORT_TUPLE in $FORWARD_PORTS; do
    SPACED=(${PORT_TUPLE//:/ })
    IP=${SPACED[0]}
    PORT_NUMBER=${SPACED[1]}
    PROTO=${SPACED[2]}
    if ! iptables -t nat -C PREROUTING -i tun0 -p ${PROTO} --dport ${PORT_NUMBER} -j DNAT --to-destination ${IP} 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: DNAT rule for ${PROTO} ${PORT_NUMBER} to ${IP} missing"
        exit 1
    fi
done

echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Healthcheck passed"
exit 0