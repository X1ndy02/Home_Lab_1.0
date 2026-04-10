#!/usr/bin/env bash
# Restrict HA and go2rtc ports to ZeroTier and localhost only.
# Idempotent: removes existing rules for these ports before reapplying.

ZEROTIER_IP="10.244.10.4"

for PORT in 8123 18555; do
  # Remove any existing rules for this port (ignore errors if not present)
  while iptables -D INPUT -d "$ZEROTIER_IP" -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; do :; done
  while iptables -D INPUT -s 127.0.0.0/8  -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; do :; done
  while iptables -D INPUT                  -p tcp --dport "$PORT" -j DROP   2>/dev/null; do :; done

  # Reapply cleanly
  iptables -I INPUT -d "$ZEROTIER_IP" -p tcp --dport "$PORT" -j ACCEPT
  iptables -I INPUT -s 127.0.0.0/8   -p tcp --dport "$PORT" -j ACCEPT
  iptables -A INPUT                   -p tcp --dport "$PORT" -j DROP
done
