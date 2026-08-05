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

## License

Copyright (c) 2026 William Collison. All rights reserved.

You are free to download and use this software to harden your systems. However, you are strictly forbidden from modifying, adapting, or creating derivative works based upon this software. Distribution of altered versions is not permitted. A template is available if you choose to make your own copy of this set of scripts.
