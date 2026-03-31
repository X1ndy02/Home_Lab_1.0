# Network Failover Alerts

Source: `/usr/local/bin/net-failover-notify.sh`

Cadence: event-driven on default-route changes

This folder is for network failover emails, such as switching between `eth0` and `wlan0`.

Subject pattern:

- `[NET] Network failover: eth0 -> wlan0 on <host>`

Recommended path shape:

- `YYYY-MM/2026-03-30T14-10-00_network_failover_eth0_to_wlan0.txt`

Relevant code

- script: `/usr/local/bin/net-failover-notify.sh`

```sh
subject="$SUBJECT_PREFIX Network failover: $prev_iface -> $current_iface on $host"
```

```sh
printf "%s" "$msg" | "$MAILER" -t
```
