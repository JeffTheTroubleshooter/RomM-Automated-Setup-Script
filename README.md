# RomM Automated Setup Script

Installs [RomM](https://github.com/rommapp/romm), a self-hosted ROM manager, with Docker Compose. The stack has RomM, MariaDB and Redis. If Docker and Compose aren't installed, the script installs them.

## Automatic Install

```bash
bash romm-install.sh
```

The script asks for an install directory (default `/opt/romm`) and a port (default `8081`), then writes `docker-compose.yml` and starts the stack. When it finishes, open `http://<server-ip>:8081`.

## Managing the Stack

```bash
cd /opt/romm
docker compose ps
docker compose logs -f
docker compose restart
docker compose down
```

## Uninstall

```bash
bash romm-install.sh uninstall
```

This stops the stack, and you can choose whether to also remove its data.

## Supported Distros

| Distro | Status |
|---|---|
| Fedora | Tested, works |
| Debian / Ubuntu (and Mint, Pop!_OS, Zorin, elementary) | Not tested, need feedback |
| RHEL / Rocky / AlmaLinux / CentOS | Not tested, need feedback |
| Arch / Manjaro / EndeavourOS / Garuda | Not tested, need feedback |
| openSUSE / SLES | Not tested, need feedback |
| Alpine | Not tested, need feedback |

If you try it on a distro that isn't tested, please open an issue and say how it went.

## Part of the Proxmox Homelab setup

This installer is used by [Proxmox-Homelab-Automated-Setup-Script](https://github.com/JeffTheTroubleshooter/Proxmox-Homelab-Automated-Setup-Script), which creates an LXC for each app on a Proxmox host and runs this script inside it.
