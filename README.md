# CIS Hardening Scripts for Ubuntu 24.04

A hardening script for Ubuntu 24.04 based on the CIS Ubuntu 24.04 v2.0.0 Level 1 Server benchmark.

## Usage

```bash
./harden.sh [OPTIONS] [MODULE]
```

### OPTIONS

* **`--list`**  
  Lists all modules for the user to run, each can be excluded or included.

* **`--include <module_name>`**  
  Allows user to run harden.sh with only a specified modules selected.  
  *Example:* `./harden.sh --include kernel_modules` will ONLY use the `kernel_modules` option during execution.

* **`--exclude <module_name>`**  
  Allows user to run harden.sh without a specified module selected.  
  *Example:* `./harden.sh --exclude kernel_modules` will use everything BUT `kernel_modules` option during execution.

* **`--all`**  
  Runs all modules during execution.

## Important Notes

* Add in custom Banner to the 09 and 10 in /controls
* Add your whitelist of ports before running apply
* Configure PAM to follow policies

## Guide for reading error messages
* 1 - Initial Setup
  * 1.1.1.X
    * filesystems
    * kernel_modules
  * 1.1.2.X
    * tmp_mounts
  * 1.2.X.X
    * software_updates
  * 1.3.1.X
    * apparmor
  * 1.4.X
    * bootloader
  * 1.5.X
    * process_hardening
  * 1.6.X
    * banners
  * 1.7.X (Workstation Only)
    * gdm
* 2 - Services
  * 2.1.X - Configure Server Services
    * server_services
  * 2.2.X - Configure Client Services
    * client_services
  * 2.3.X.X - Configure Time Synchronization
    * time_sync
  * 2.4.X.X
    * job_schedulers
* 3 - Network
  * 3.1.X - Configure Network Devices
    * network_devices
  * 3.2.X - Configure Network Kernel Modules
    * network_modules
  * 3.3.X.X - Configure Network Kernel Parameters
    * network_parameters
* 4 - Host Based Firewall
  * 4.1.X - Configure Uncomplicated Firewall (ufw)
    * host_firewall
* 5 - Access Control
    * a
    * a
    * a
    * a
    * a
    * a
    * a
    * a
    * a
    * a
    * a
    * a
    * a
    * a
    * a
    * a
    * a
    * a
    * a

## License

Copyright (c) 2026 William Collison. All rights reserved.

You are free to download and use this software to harden your systems. However, you are strictly forbidden from modifying, adapting, or creating derivative works based upon this software. Distribution of altered versions is not permitted. A template is available if you choose to make your own copy of this set of scripts.
