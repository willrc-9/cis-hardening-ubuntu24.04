Ubuntu 26.04
CIS Ubuntu 24.04 v2.0.0
Level 1 Server

./harden.sh [OPTIONS] [MODULE]

OPTIONS

	--list
		Lists all modules for the user to run, each can be excluded or included

	--include <module_name>
		Allows user to run harden.sh with only a specified modules selected
		ex. "./harden.sh --include kernel_modules" will ONLY use the kernel_modules option during execution

	--exclude <module_name>
                Allows user to run harden.sh without a specified module selected
                ex. "./harden.sh --exclude kernel_modules" will use everything BUT kernel_modules option during execution

	--all
		Runs all modules during execution
