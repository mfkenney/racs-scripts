RACS 2.0 SIC Software
=====================

This repository contains a series of Bash shell-scripts to manage the
automated operation of the new version of the Remote Autonomous Camera
System (RACS). The software runs on the System Interface Controller
(SIC) which is a Technologic Systems TS-4200/8160 compact computer
running Debian Linux.

## Installation

Clone this repository to a directory on the SIC and run `make`:

```
git clone https://github.com/mfkenney/racs-scripts.git
cd racs-scripts
make install
```

## Automation

In addition to copying the scripts and configuration files to their
proper locations, the `make install` command also installs a
Cron job which will arrange for the camera image acquisition task
to run everytime the SIC boots.

## Scripts

- **snapshot.sh** : grabs a single snapshot from a camera video
stream, saves it to the archive, and creates a down-sampled
version for the OUTBOX.
- **findimg.sh** : copies an image from the archive to the OUTBOX
- **setalarm.sh** : schedules a system restart for some future time
and shuts the system down.
- **tasks.sh** : manages the entire image acquistion and upload
procedure.
- **testmode.sh** : menu-driven system test script.
- **racs_power.sh** : low-level power testing script
