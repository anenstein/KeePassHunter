# KeePass Hunter

**KeePass Hunter** is a PowerShell triage script for finding KeePass databases (`*.kdbx`) and related artifacts on Windows systems. 

---

## Features

- Searches common locations (`C:\Users`, `C:\ProgramData`, `C:\inetpub`, and all fixed/mapped drives) for KeePass databases
- Skips noisy/unnecessary locations (Windows, Recycle Bin, System Volume Information)
- Collects metadata:
  - File path, size, last modification time
  - File owner (for top-N newest files)
- Enumerates KeePass context:
  - Running KeePass processes (with command line)
  - Installed KeePass / KeePassXC applications (from registry uninstall keys)
  - Most Recently Used (MRU) KeePass entries in registry
  - KeePass/KeePassXC config files (e.g., `KeePass.config.xml`, `keepassxc.ini`)
- Detects side files:
  - Key files (`*.key`)
  - Configs and INI files (`KeePass.config.xml`, `KeePass.ini`, `keepassxc.ini`)
- Outputs:
  - `keepass_kdbx.csv` → found database files (CSV, machine-readable)
  - `keepass_sidefiles.csv` → related side files (CSV)
  - `keepass_meta.txt` → process, registry, and context dump
  - Recursion depth limited to 6
  - Owner info fetched for 50 newest .kdbx files

### Output files

By default, artifacts are stored under:
```powershell
C:\Users\Public\loot\
```
- keepass_kdbx.csv → main KeePass database index
- keepass_sidefiles.csv → key/config side files
- keepass_meta.txt → process list, installed programs, MRUs, configs
  
---

## Usage

### Basic run (fast mode)
```powershell
.\KeePassHunter.ps1
```

### Aggressive full crawl
```powershell
.\KeePassHunter.ps1 -Aggressive
```
- Removes recursion depth cap
- Searches entire drives exhaustively (slower, noisier)

### Change how many files include Owner info
```powershell
.\KeePassHunter.ps1 -MaxOwners 100
```
- Collects owner information (Get-Acl) for 100 newest hits instead of default 50

