#!/bin/bash
# Role-based firewall for the VPN gateway (lab)
set -e
WAN=enp0s8; MGMT=enp0s3; LAN=enp0s9; TUN=tun0
STAFF=10.8.0.11; ADMIN=10.8.0.12
WEB=192.168.10.10; FILES=192.168.10.20; ADMSRV=192.168.10.30
OVPN_PORT=1194
I=iptables

# start from a clean, open state
$I -P INPUT ACCEPT; $I -P FORWARD ACCEPT; $I -P OUTPUT ACCEPT
$I -F; $I -X

# ---------- INPUT: traffic addressed to the gateway itself ----------
$I -A INPUT -i lo -j ACCEPT
$I -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
$I -A INPUT -i $MGMT -j ACCEPT                                   # my SSH management path
$I -A INPUT -i $WAN -p udp --dport $OVPN_PORT -j ACCEPT          # OpenVPN handshake
$I -A INPUT -i $TUN -p icmp -j ACCEPT                            # ping the tunnel end
$I -A INPUT -i wg0 -p icmp -j ACCEPT
$I -A INPUT -i $LAN -p icmp -j ACCEPT                            # office servers may ping the gateway
$I -A INPUT -i $WAN -p udp --dport 51820 -j ACCEPT          # WireGuard handshake

# ---------- FORWARD: traffic passing through (the role rules) ----------
$I -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# admin role: everything in the office
$I -A FORWARD -i $TUN -o $LAN -s $ADMIN -d 192.168.10.0/24 -j ACCEPT

# staff role: web (80), files (445), ping to those two only
$I -A FORWARD -i $TUN -o $LAN -s $STAFF -d $WEB   -p tcp --dport 80  -j ACCEPT
$I -A FORWARD -i $TUN -o $LAN -s $STAFF -d $FILES -p tcp --dport 445 -j ACCEPT
$I -A FORWARD -i $TUN -o $LAN -s $STAFF -d $WEB   -p icmp --icmp-type echo-request -j ACCEPT
$I -A FORWARD -i $TUN -o $LAN -s $STAFF -d $FILES -p icmp --icmp-type echo-request -j ACCEPT
# WireGuard roles (same policy as OpenVPN)
$I -A FORWARD -i wg0 -o $LAN -s 10.9.0.12 -d 192.168.10.0/24 -j ACCEPT
$I -A FORWARD -i wg0 -o $LAN -s 10.9.0.11 -d $WEB   -p tcp --dport 80  -j ACCEPT
$I -A FORWARD -i wg0 -o $LAN -s 10.9.0.11 -d $FILES -p tcp --dport 445 -j ACCEPT
$I -A FORWARD -i wg0 -o $LAN -s 10.9.0.11 -d $WEB   -p icmp --icmp-type echo-request -j ACCEPT
$I -A FORWARD -i wg0 -o $LAN -s 10.9.0.11 -d $FILES -p icmp --icmp-type echo-request -j ACCEPT

# everything else from tunnel clients: log (rate-limited), then drop
$I -A FORWARD -s 10.8.0.0/24 -m limit --limit 5/min -j LOG --log-prefix "FW-DROP: "
$I -A FORWARD -s 10.9.0.0/24 -m limit --limit 5/min -j LOG --log-prefix "FW-DROP-WG: "
$I -A FORWARD -j DROP

# ---------- default policies last ----------
$I -P INPUT DROP
$I -P FORWARD DROP
$I -P OUTPUT ACCEPT
echo RULES_APPLIED
