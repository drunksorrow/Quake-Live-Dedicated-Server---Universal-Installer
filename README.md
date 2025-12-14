## 🚨 Latest Update (2025-12-14)

**Version 1.2** - Enhanced Steam authentication with visible/hidden password options and retry logic. Requires Steam account with Quake Live.

**Tested on:** Ubuntu 24.04 LTS (should work on 16.04, 18.04, 20.04, 22.04)

[📥 Download Latest Version](https://github.com/drunksorrow/Quake-Live-Dedicated-Server---Universal-Installer/releases/latest)

# Quake Live Dedicated Server - Universal Installer

Automated installation script for Quake Live Dedicated Server with minqlx support on Ubuntu Server.

---

## 📋 Supported Versions

- Ubuntu 16.04, 18.04, 20.04, 22.04, 24.04 LTS
- Potentially newer/older versions (will attempt compatibility)

---

## ⚙️ System Requirements

- Fresh Ubuntu Server installation (x86/x64)
- Root access
- Internet connection
- Minimum 2GB RAM
- 10GB free disk space

---

## 1. Pre-Installation

### 1.1 Check Ubuntu Version

```bash
lsb_release -a
```

or

```bash
cat /etc/os-release
```

### 1.2 Upload the Script

1. Upload `install_quake_live.sh` to `/root` directory using WinSCP/SFTP
2. Connect via SSH as root

---

## 2. Installation

### 2.1 Set Execute Permission

```bash
chmod +x /root/install_quake_live.sh
```

### 2.2 Run the Installer

```bash
cd /root
./install_quake_live.sh
```

---

## 3. Installation Process

The installer will automatically:

1. Detect Ubuntu version
2. Check timezone (optional configuration)
3. Request password for qlserver user and Samba
4. Setup SSH keys (copy from root or create new)
5. Install system packages
6. Install ZeroMQ library
7. Create qlserver user
8. Configure Samba file sharing
9. Install SteamCMD
10. Download Quake Live Dedicated Server
11. Install minqlx framework
12. Create helper scripts (supervisor installer & cleanup script)

---

## 4. Interactive Prompts

During installation:

- **Timezone**: Change timezone (default: keep current)
- **Password**: Enter password for qlserver user (visible)
- **SSH key**: Add SSH key if not found

---

## 5. Configure Server

### 5.1 Upload Configuration Files

Using WinSCP/SFTP, upload files to:

**`/home/qlserver/steamcmd/steamapps/common/qlds/baseq3/`**
- `server.cfg`
- `access.txt`
- `mappool.txt`
- `workshop.txt`

### 5.2 Upload Plugins

Upload minqlx plugins (`.py` files) to:

**`/home/qlserver/steamcmd/steamapps/common/qlds/minqlx-plugins/`**

Examples: `branding.py`, `funnysounds.py`, `listmaps.py`

---

## 6. Test Server Manually

### 6.1 Connect as qlserver

```bash
su - qlserver
```

### 6.2 Start Screen Session (Optional)

```bash
screen -S quake
```

*To detach: `Ctrl+A` then `D` | To reattach: `screen -r quake`*

### 6.3 Navigate and Start

```bash
cd ~/steamcmd/steamapps/common/qlds
./run_server_x64_minqlx.sh
```

### 6.4 Verify

Watch for:
- Workshop maps downloading automatically
- Minqlx plugins loading without errors
- Server starting successfully

Stop server with `Ctrl+C` when done testing.

```bash
exit  # Return to root user
```

---

## 7. Install Supervisor

After successful testing, run as root:

```bash
/root/install-supervisor.sh
```

This will:
1. Install and configure Supervisor
2. Ask about daily automatic reboot (crontab setup)
   - Option for 6:40 AM (recommended)
   - Option for custom time
   - Option to skip
3. Enable auto-start on boot
4. Offer system reboot

---

## 8. Cleanup (If Needed)

If installation fails or you need to start over:

```bash
/root/cleanup-quake-install.sh
```

Removes all installations and configurations.

---

## 📦 Helper Scripts

### `/root/install-supervisor.sh`
Run after server configuration and testing.

### `/root/cleanup-quake-install.sh`
Use if installation fails or you need to start over.

---

## ⚠️ Important Notes

### 🔥 Firewall Configuration

**You must configure firewall separately:**

```bash
ufw allow 27960/udp
ufw allow 27960/tcp
```

### 🔄 Daily Automatic Reboot

Configured during Supervisor installation (optional).

Default: 6:40 AM (low activity time)

Manual setup:
```bash
sudo crontab -e
# Add: 40 6 * * * /sbin/shutdown -r now
```

### 🚀 Server Startup

**Manual:**
```bash
su - qlserver
cd ~/steamcmd/steamapps/common/qlds/
./run_server_x64_minqlx.sh
```

**With Supervisor:** Automatic startup on boot

### 📄 Logs

- Installation: `/var/log/quake_live_install.log`
- Server error: `/var/log/quake.err.log`
- Server output: `/var/log/quake.out.log`

---

## 🔧 Troubleshooting

### Installation Fails

1. Check: `/var/log/quake_live_install.log`
2. Run: `/root/cleanup-quake-install.sh`
3. Verify Ubuntu version and internet connection
4. Run installer again

### Server Won't Start

1. Check Supervisor: `supervisorctl status`
2. Check logs: `tail -f /var/log/quake.err.log`
3. Verify permissions: `ls -la /home/qlserver/steamcmd/`
4. Try manual start for detailed errors

### SSH Connection Issues

1. Verify key: `cat /home/qlserver/.ssh/authorized_keys`
2. Check permissions:
   ```bash
   ls -la /home/qlserver/.ssh/
   # Should be: drwx------ (700) for .ssh
   # Should be: -rw------- (600) for authorized_keys
   ```

### Crontab Not Working

```bash
sudo crontab -l  # Check if exists
sudo crontab -e  # Edit manually
# Add: 40 6 * * * /sbin/shutdown -r now
```

---

## 🧹 Remove Installation Scripts

After successful installation:

```bash
rm /root/install_quake_live.sh
rm /root/install-supervisor.sh
rm /root/cleanup-quake-install.sh
```

---

## 🙏 Credits

Based on:
- [drunksorrow's Quake Live server scripts](https://github.com/drunksorrow)
- [MinoMino's minqlx framework](https://github.com/MinoMino/minqlx)

---

## 💬 Support

- IRC: #minqlbot on QuakeNet
- GitHub: https://github.com/MinoMino/minqlx

---

## 📜 License

Provided as-is, without warranty. Use at your own risk.

---

**Note**: Firewall configuration and network security are the administrator's responsibility.
