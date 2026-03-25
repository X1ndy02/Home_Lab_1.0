# Portable Pi Zero USB Network Key

Purpose
Create a portable Raspberry Pi Zero device that acts as a physical network access key.
When plugged into a computer through USB, the device appears as a wired Ethernet adapter.  
The host gains a direct network link to the Pi, allowing immediate SSH access and a secure tunnel to a home server or lab environment.
The device draws power from the same USB connection and requires no screen, keyboard, or manual configuration.
Th result is a small portable admin tool that provides controlled remote access to infrastructure from almost any computer.

Core Idea
The Raspberry Pi Zero uses Linux USB gadget mode to emulate an Ethernet network adapter.  
Once connected, the host system detects a new network interface and communicates directly with the Pi.

Architecture:
Host computer
   │
USB power + data
   │
Pi Zero (USB Ethernet gadget)
   │
SSH access
   │
Overlay network (in my case its ZeroTier)
   │
Home server / Pi 5 rootnode

The Pi becomes a portable network entry point and jump host into a private infrastructure.

Primary Capabilities
- Portable network interface (The device behaves like a physical Ethernet adapter connected through USB)
- Direct SSH access  
- using SSH without relying on the host network configuration.
- Remote infrastructure access (ZeroTier, the Pi automatically connects to a private network containing the home server and the whole lab environment)
- Jump host functionality (can reach internal machines securely without exposing them to the public interne)
- no need to instal ZT or anythign else on the other machine adn evrythong is portable 


Model in theory:
Plug the device into a computer
The Pi powers on and enumerates as a USB Ethernet adapter
Once booted, I can connect to the Pi using SSH
The Pi automatically joins its overlay network and establishes connectivity with the remote server
I can then uses the Pi as a secure jump point from naypc anywhere into the remote infrastructure

The device should expose only minimal services:
SSH 
overlay network client
If the device is lost, i will just revoke:
SSH keys 
0verlay network membership
Minimal credential storage on device is recommended

Constraints and Design Limits
The Raspberry Pi Zero has limited CPU and memory resources 
The design must remain lightweight and focused on networking functionality
USB gadget networking behavior depends on host operating system support
Different systems may prefer different driver implementations
Boot time will typically range between 15 and 40 seconds depending on system configuration
