#!/bin/bash
# up.sh - Apply iptables rules after OpenVPN connects

# Ensure output goes to stdout and stderr
exec 1>&1 2>&1

# Use same LAN_INTERFACE and FORWARD_PORTS as run.sh
LAN_INTERFACE="${LAN_INTERFACE:-eth0}"
FORWARD_PORTS="${FORWARD_PORTS:-}"

echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: up.sh started, LAN_INTERFACE=$LAN_INTERFACE"

apply_iptables() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Applying iptables rules from up.sh"
    iptables -t nat -F && echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Cleared NAT table" ||
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to clear NAT table"
    iptables -F && echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Cleared FILTER table" ||
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to clear FILTER table"

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Routing from $LAN_INTERFACE to tun0"
    iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE && echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Added MASQUERADE rule" ||
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to add MASQUERADE rule"
    iptables -A FORWARD -i tun0 -o $LAN_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT &&
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Added FORWARD rule (tun0 -> $LAN_INTERFACE)" ||
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to add FORWARD rule (tun0 -> $LAN_INTERFACE)"
    iptables -A FORWARD -i $LAN_INTERFACE -o tun0 -j ACCEPT &&
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Added FORWARD rule ($LAN_INTERFACE-> tun0)" ||
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to add FORWARD rule ($LAN_INTERFACE-> tun0)"

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
}

apply_iptables