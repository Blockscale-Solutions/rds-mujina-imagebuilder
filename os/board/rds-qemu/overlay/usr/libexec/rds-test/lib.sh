# Sensors shared by the guest tests (#51). Sourced, never run.
# Every value a test reports is read from the kernel, never assumed.
nand_mtd() { grep -i 'NAND simulator' /proc/mtd | head -1 | cut -d: -f1; }
# Program and erase operations the simulated chip actually executed (S1).
chip_counts() { echo "chip_prog=$(dmesg | grep -c "programm page") chip_erase=$(dmesg | grep -c "erase sector")"; }
# Raw data plus OOB, read without ECC (S2).
raw_hash() { nanddump -n -o -q /dev/$1 2>/dev/null | sha256sum | cut -c1-16; }
# Kernel state (S4).
state() { echo "param=$(cat /sys/module/nand/parameters/canary 2>/dev/null || echo none) flags=$(cat /sys/class/mtd/$1/flags 2>/dev/null)"; }
said() { dmesg | grep -q "$1" && echo yes || echo no; }
# Which layer refused a userspace call (S3): open (Permission denied), block (a
# write to a read-only block device, Operation not permitted) or core (Read-only).
# open-noerrno: the tool says only that open() failed, without the errno (#80).
layer() { case "$1" in *"Permission denied"*) echo open;; *"Operation not permitted"*) echo block;; *"Read-only file system"*) echo core;; *"error!: open()"*) echo open-noerrno;; "") echo none;; *) echo other;; esac; }
