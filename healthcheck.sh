#!/bin/bash
# healthcheck.sh - Check VPN and NAT rules, attempt to fix and recheck if needed

exec 1>>/var/log/healthcheck.log 2>&1

LAN_INTERFACE="${LAN_INTERFACE:-eth0}"
FORWARD_PORTS="${FORWARD_PORTS:-}"

# Function to apply iptables rules (similar to up.sh)
apply_iptables() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Attempting to fix iptables rules"
    iptables -t nat -F && echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Cleared NAT table" ||
        { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to clear NAT table"; return 1; }
    iptables -F && echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Cleared FILTER table" ||
        { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to clear FILTER table"; return 1; }

    iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE && echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Added MASQUERADE rule" ||
        { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to add MASQUERADE rule"; return 1; }
    iptables -A FORWARD -i tun0 -o $LAN_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT &&
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Added FORWARD rule (tun0 -> $LAN_INTERFACE)" ||
        { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to add FORWARD rule (tun0 -> $LAN_INTERFACE)"; return 1; }
    iptables -A FORWARD -i $LAN_INTERFACE -o tun0 -j ACCEPT &&
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Added FORWARD rule ($LAN_INTERFACE -> tun0)" ||
        { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to add FORWARD rule ($LAN_INTERFACE -> tun0)"; return 1; }

    for PORT_TUPLE in $FORWARD_PORTS; do
        SPACED=(${PORT_TUPLE//:/ })
        IP=${SPACED[0]}
        PORT_NUMBER=${SPACED[1]}
        PROTO=${SPACED[2]}
        iptables -t nat -A PREROUTING -i tun0 -p ${PROTO} --dport ${PORT_NUMBER} -j DNAT --to-destination ${IP} &&
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Added DNAT rule for ${PROTO} ${PORT_NUMBER} to ${IP}" ||
            { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to add DNAT rule for ${PROTO} ${PORT_NUMBER} to ${IP}"; return 1; }
    done
    return 0
}

# Function to check iptables rules
check_iptables() {
    local errors=0
    if ! iptables -t nat -C POSTROUTING -o tun0 -j MASQUERADE 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: MASQUERADE rule missing"
        errors=$((errors + 1))
    fi
    if ! iptables -C FORWARD -i tun0 -o $LAN_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: FORWARD rule (tun0 -> $LAN_INTERFACE) missing"
        errors=$((errors + 1))
    fi
    if ! iptables -C FORWARD -i $LAN_INTERFACE -o tun0 -j ACCEPT 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: FORWARD rule ($LAN_INTERFACE -> tun0) missing"
        errors=$((errors + 1))
    fi
    for PORT_TUPLE in $FORWARD_PORTS; do
        SPACED=(${PORT_TUPLE//:/ })
        IP=${SPACED[0]}
        PORT_NUMBER=${SPACED[1]}
        PROTO=${SPACED[2]}
        if ! iptables -t nat -C PREROUTING -i tun0 -p ${PROTO} --dport ${PORT_NUMBER} -j DNAT --to-destination ${IP} 2>/dev/null; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: DNAT rule for ${PROTO} ${PORT_NUMBER} to ${IP} missing"
            errors=$((errors + 1))
        fi
    done
    return $errors
}

# Check tun0 interface with retries
for i in {1..3}; do
    if ip link show tun0 >/dev/null 2>&1; then
        break
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: tun0 not ready, retry $i"
    sleep 5
done
if ! ip link show tun0 >/dev/null 2>&1; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: tun0 interface not present"
    exit 1
fi

# Check VPN connectivity
if ! ping -c 3 -I tun0 8.8.8.8 >/dev/null 2>&1; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Ping via tun0 failed"
    exit 1
fi

# Initial iptables check
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Checking iptables rules"
check_iptables
if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: iptables rules missing, attempting to fix"
    apply_iptables
    if [ $? -ne 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to apply iptables rules"
        exit 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Rechecking iptables rules after fix"
    check_iptables
    if [ $? -ne 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: iptables rules still missing after fix attempt"
        exit 1
    fi
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Healthcheck passed"
exit 0