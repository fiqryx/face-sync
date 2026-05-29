# Face-Sync App Repository

This repository serves as the **Central Storage & Versioning System** for the automatic update mechanism (*auto-update*) of the **Face-Sync** application suite.

The main Go Updater application running on the production server periodically reads the `version.json` file from this repository to detect, download, and hot-swap modified system components.

### Minimum Specification Requirements
* **CPU:** Minimum 2 Cores / vCPU (**AMD64 / x86_64** Architecture)
* **RAM:** Minimum 4 GB 
* **Storage:** Minimum 20 GB SSD
* **OS:** Ubuntu Server 20.04 / 22.04 LTS (or any Linux OS with Docker installed)
 
## Docker Instalation
 
1. Clone this repository:
   ```bash
   git clone <repo-url>
   ```
 
2. Run with Docker Compose:
   ```bash
   docker-compose up --build -d
   ```