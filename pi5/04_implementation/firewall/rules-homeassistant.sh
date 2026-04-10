#!/usr/bin/env bash
# Block HA and go2rtc ports from all interfaces except ZeroTier and localhost
ZEROTIER_IP="10.244.10.4"

for PORT in 8123 18555; do
  iptables -I INPUT -d "$ZEROTIER_IP" -p tcp --dport "$PORT" -j ACCEPT
  iptables -I INPUT -s 127.0.0.0/8 -p tcp --dport "$PORT" -j ACCEPT
  iptables -A INPUT -p tcp --dport "$PORT" -j DROP
done
