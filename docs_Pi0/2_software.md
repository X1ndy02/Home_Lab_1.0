VPN
- Both pi zeros are on pribet Zerotier Virtual networks with custom assigned IP adresses 
- This makes all my devices connected no matter their locations

As i left pi unattended it died on me and i was not abel to get into it usign headless method 
and was nto erachable via lan 
1. Disable WiFi Power Saving
   - sudo iw dev wlan0 set power_save off
2. Installed WiFi Recovery Watchdog
   - A small script checks connectivity to the router.
   - If the connection fails, the network service is restarted automatically
   - ping router → restart NetworkManager if unreachable
3. use SD Card Protection (log2ram)
   - log2ram moves /var/log into RAM and periodically synchronizes it to disk
   - I ofun this solution online it should:
           - reduces SD card wear
           - reduces filesystem corruption risk
           - improves system responsiveness

