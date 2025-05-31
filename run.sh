#!/bin/bash
# run.sh - Manage OpenVPN and NAT rules with enhanced debugging

# Redirect all output to stdout/stderr for Docker logs
exec 1>&1 2>&1

echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: Script started, PID=$$"

# Enable command tracing
#set -x

# Log environment variables
echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: Environment variables:"
env | sort | while read -r line; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: $line"
done

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

# Log network interfaces
echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: Network interfaces:"
ip link show
ip addr show

# Log OpenVPN config (sanitize sensitive data)
echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: OpenVPN config ($CONF_FILE):"
if [ -f "/etc/openvpn/$CONF_FILE" ]; then
    cat "/etc/openvpn/$CONF_FILE" | grep -vE '^(auth-user-pass|ca|cert|key|tls-auth)' || true
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Config file /etc/openvpn/$CONF_FILE not found"
    exit 1
fi

# Create TUN device
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Creating TUN device"
mkdir -p /dev/net
if ! mknod /dev/net/tun c 10 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to create TUN device"
    exit 1
fi
ls -l /dev/net/tun

# Wait for tun0 interface
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Waiting for tun0 interface"
for i in {1..5}; do
    if ip link show tun0 >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: tun0 interface found"
        break
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: tun0 not ready, retry $i"
    sleep 2
done

# Apply iptables rules
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Applying iptables rules"
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE && echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Added MASQUERADE rule" ||
    { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to add MASQUERADE rule"; exit 1; }
iptables -A FORWARD -i tun0 -o $LAN_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT &&
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Added FORWARD rule (tun0 -> $LAN_INTERFACE)" ||
    { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to add FORWARD rule (tun0 -> $LAN_INTERFACE)"; exit 1; }
iptables -A FORWARD -i $LAN_INTERFACE -o tun0 -j ACCEPT &&
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Added FORWARD rule ($LAN_INTERFACE -> tun0)" ||
    { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to add FORWARD rule ($LAN_INTERFACE -> tun0)"; exit 1; }

for PORT_TUPLE in $FORWARD_PORTS; do
    SPACED=(${PORT_TUPLE//:/ })
    IP=${SPACED[0]}
    PORT_NUMBER=${SPACED[1]}
    PROTO=${SPACED[2]}
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Opening ${PROTO} port ${PORT_NUMBER} for ${IP}"
    iptables -t nat -A PREROUTING -i tun0 -p ${PROTO} --dport ${PORT_NUMBER} -j DNAT --to-destination ${IP} &&
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Added DNAT rule for ${PROTO} ${PORT_NUMBER} to ${IP}" ||
        { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to add DNAT rule for ${PROTO} ${PORT_NUMBER} to ${IP}"; exit 1; }
done

# Log iptables rules
echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: Current iptables rules:"
iptables -L -v -n --line-numbers
iptables -t nat -L -v -n --line-numbers

# Set OpenVPN permissions
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Setting chmod 700 on /etc/openvpn"
chmod -R 700 /etc/openvpn || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to chmod /etc/openvpn"
    exit 1
}
ls -ld /etc/openvpn

# Start OpenVPN with retries
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Starting OpenVPN"
touch /var/log/openvpn.log
MAX_LOG_SIZE=$((1024*1024)*20)
for i in {1..3}; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: OpenVPN start attempt $i"
    /usr/sbin/openvpn --daemon --cd /etc/openvpn --config "$CONF_FILE" --script-security 2 --up /up.sh --log /var/log/openvpn.log --verb 4
    sleep 2
    openvpn_pid=$(pgrep openvpn)
    if [ -n "$openvpn_pid" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: OpenVPN started, pid=$openvpn_pid"
        break
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: OpenVPN failed to start, retry $i"
    cat /var/log/openvpn.log
done

if [ -z "$openvpn_pid" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: OpenVPN failed to start after retries"
    cat /var/log/openvpn.log
    exit 1
fi

# Verify OpenVPN process
echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: OpenVPN process status:"
ps -p "$openvpn_pid" -o pid,ppid,cmd || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: OpenVPN process $openvpn_pid not running"
    exit 1
}

# Stream OpenVPN logs to stdout
echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: Streaming OpenVPN logs"
tail -f /var/log/openvpn.log &

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

# Function to format interface status
format_interface_status() {
    local iface=$1
    local status="DOWN"
    local ip="None"
    local mtu="Unknown"

    # Check if interface exists and get its state
    if ip link show $iface >/dev/null 2>&1; then
        # Get link state
        if ip link show $iface | grep -q "state UP"; then
            status="UP"
        elif ip link show $iface | grep -q "state DOWN"; then
            status="DOWN"
        else
            status="UNKNOWN"
        fi

        # Get IP address
        ip=$(ip addr show $iface | grep -o 'inet [0-9.]*' | awk '{print $2}' || echo "None")

        # Get MTU
        mtu=$(ip link show $iface | grep -o 'mtu [0-9]*' | awk '{print $2}' || echo "Unknown")
    else
        status="MISSING"
    fi

    # Print formatted status
    printf "%-15s %-10s %-15s %-10s\n" "$iface" "$status" "$ip" "$mtu"
}

# Function to truncate log file if it exceeds size
truncate_log() {
    local log_file=$1
    local max_size=$2
    if [ -f "$log_file" ]; then
        local size=$(stat -c %s "$log_file" 2>/dev/null || echo 0)
        if [ $size -gt $max_size ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Truncating $log_file (size=$size bytes)"
            : > "$log_file" # Truncate to zero length
        fi
    fi
}

# Monitor tun0 and OpenVPN health
while true; do
    # Truncate logs if they exceed size
    truncate_log /var/log/openvpn.log $MAX_LOG_SIZE
    truncate_log /var/log/healthcheck.log $MAX_LOG_SIZE
	
    # Check and format tun0 interface status
    echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: Network Interface Status:"
    echo "--------------------------------------------------"
    echo "Interface       State      IP Address      MTU"
    echo "--------------------------------------------------"
    if ! ip link show tun0 >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: tun0 interface down"
        kill $tail_pid 2>/dev/null
        exit 1
    fi
    format_interface_status tun0

    # Check and format LAN interface status
    if ! ip link show $LAN_INTERFACE >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $LAN_INTERFACE interface down"
        kill $tail_pid 2>/dev/null
        exit 1
    fi
    format_interface_status $LAN_INTERFACE

    # Check additional interfaces (e.g., eth0@777, eth0@778 if they exist)
    for extra_iface in eth0; do
        if ip link show $extra_iface >/dev/null 2>&1; then
            format_interface_status $extra_iface
        fi
    done
    echo "--------------------------------------------------"

    # Check OpenVPN process
    if ! ps -p $openvpn_pid >/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: OpenVPN process $openvpn_pid stopped"
        kill $tail_pid 2>/dev/null
        exit 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: OpenVPN process status:"
    ps -p $openvpn_pid -o pid,ppid,cmd,%cpu,%mem

    # Check VPN connectivity
    echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: Pinging 8.8.8.8 via tun0"
    ping -c 1 -I tun0 8.8.8.8
    if [ $? -ne 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: Ping via tun0 failed"
    fi

    # Check DNS resolution via tun0
    echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: Resolving google.com via tun0"
    dig +short @8.8.8.8 -b $(ip addr show tun0 | grep -o 'inet [0-9.]*' | awk '{print $2}') google.com
    if [ $? -ne 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: DNS resolution via tun0 failed"
    fi

    # Check iptables rules
    echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: Checking iptables rules"
    check_iptables
    if [ $? -ne 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: iptables rules missing"
        echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: Current iptables rules:"
        iptables -L -v -n --line-numbers
        iptables -t nat -L -v -n --line-numbers
    fi

    # Check OpenVPN log for errors
    if [ -f /var/log/openvpn.log ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: Checking OpenVPN log for errors"
        grep -iE "error|warn|fail|timeout|reset|down" /var/log/openvpn.log | tail -n 5
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') DEBUG: Monitoring cycle complete, sleeping 10s"
	
    # Run logrotate to manage log size
    logrotate /etc/logrotate.d/openvpn --state /var/log/logrotate.state 2>/dev/null || {
        # Fallback: Truncate log if logrotate fails
        MAX_LOG_SIZE=$((10*1024*1024)) # 10MB
        if [ -f /var/log/openvpn.log ]; then
            LOG_SIZE=$(stat -c %s /var/log/openvpn.log 2>/dev/null || echo 0)
            if [ $LOG_SIZE -gt $MAX_LOG_SIZE ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Truncating /var/log/openvpn.log (size: $LOG_SIZE bytes)"
                tail -n 1000 /var/log/openvpn.log > /var/log/openvpn.log.tmp && mv /var/log/openvpn.log.tmp /var/log/openvpn.log
            fi
        fi
    }
    logrotate /etc/logrotate.d/openvpn --state /var/log/logrotate.state 2>/dev/null || {
        # Fallback: Truncate log if logrotate fails
        MAX_LOG_SIZE=$((10*1024*1024)) # 10MB
        if [ -f /var/log/openvpn.log ]; then
            LOG_SIZE=$(stat -c %s /var/log/openvpn.log 2>/dev/null || echo 0)
            if [ $LOG_SIZE -gt $MAX_LOG_SIZE ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Truncating /var/log/openvpn.log (size: $LOG_SIZE bytes)"
                tail -n 1000 /var/log/openvpn.log > /var/log/openvpn.log.tmp && mv /var/log/openvpn.log.tmp /var/log/openvpn.log
            fi
        fi
    }	
	
    sleep 10
done