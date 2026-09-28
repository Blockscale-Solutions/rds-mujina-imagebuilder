# rds-mujina-imagebuilder

A build environment of our own for the Mujina miner on Intel's BZM2 RDS control
board (a Cyclone V SoC). Its scope is the operating system, the flashable image,
the Device UI it serves and the flashing process, scripted end to end so that
anyone holding a unit can rebuild and reflash it.

## What it builds today

- **A Buildroot 2026.08 OS** with a BR2_EXTERNAL tree of ours (`os/`), on a
  mainline long-term kernel (Linux 6.18), in two variants:
  - `rds_control`, for the control board: our own device tree
    (`os/board/rds-control/`), with the FPGA blocks generated from one table
    (`hw.toml`, by `tools/hw2dts`), and a volume layout that fits the unit's
    existing flash (`layout.toml`);
  - `rds_qemu`, the same OS on QEMU's Cortex-A9 `vexpress-a9` machine, where
    the hardware-free tests run.
- **A kernel patch of ours** (`os/patches/linux/`): a canary mode that refuses
  every NAND write, so a first boot of a new kernel cannot change the flash.
- **Offline, reproducible builds.** Every input is pinned by hash in a generated
  lock (`env/lock.tsv`) and mirrored once; every stage after `fetch` runs with no
  network; two assemblies from the same inputs must match byte for byte.

What it never builds or ships: the FPGA bitstream, MCU firmware, or any other
vendor file. The bitstream stays on the owner's unit and is recognised there by
hash (`data/allowlist/bitstream.tsv`, `tools/bitstream-check`); nothing of the
vendor's enters this repository or an image it builds.

The design, with its gates, risks and open questions, is in
[docs/DESIGN.md](docs/DESIGN.md).

## Layout it expects

The scripts assume a project directory with this repository in `git/`:

```
<project>/
  git/rds-mujina-imagebuilder/   this repository
  build/                         regenerable outputs: images, build trees, temp
  archive/mirror/                the fetched, hash-checked sources (keep it)
```

The project directory is always the repository's grandparent, so a plain clone
needs a `git/` directory above it. `env/lib.sh` derives the paths under the
project from it, and those can be overridden one by one by environment
variables of the same name (`RDS_TMPDIR`, `RDS_MIRROR`, `RDS_BR_DIR`, `RDS_LOCK`).

## The one entry point

```bash
env/rds preflight   # also: fetch, build, test, repro
```

Each verb runs the stages in `env/stages.d/<verb>/` in name order and stops at
the first failure, cheapest checks first. Exit 0 pass, 1 fail, 2 unmeasured: a
verb that measured nothing never reports a pass. Adding a stage is adding a file.

## Tests

```bash
tests/run.sh             # the fast tier: every tests/*.test.sh, in seconds to a minute
tests/run.sh tests/qemu  # our kernel and image in QEMU (needs a build)
tests/run.sh tests/slow  # real builds, and a real browser against the Device UI
tests/run.sh tests/root  # the podman-free runner; needs root and an exported build image
```

`tests/run.sh` prints TAP and ends with `# ran N, failed M`. It exits 0 when
every test passed, 1 when any failed, and 2 when it ran nothing.

**Fast tier prerequisites:** bash, git, Python 3.11 or later, Node.js 22,
`gpgv`, `curl`, `dash`, `busybox`, `xz` and GNU coreutils. One test runs the
whole `env/rds preflight` in a clean clone, and preflight refuses to start
with under 60 GB free under `<project>/build` (`RDS_DISK_FLOOR_GB`).

**Build and QEMU tiers:** rootless podman, `qemu-system-arm`, and a network
connection once, for `env/rds fetch`; after that everything runs offline.

## What needs a unit

Nothing in the fast, QEMU or build tiers touches hardware. These do, and each
is run only by whoever operates the unit, one reversible step at a time
(DESIGN.md section 7.2):

- the read-only measurements (`tools/unit/readonly-measure.sh`, whose tests
  check that it calls no writer);
- the kexec canary boot, which cannot write NAND;
- installing a slot, the first real boot, and the rollback cases RDS-AB-01 to 08.

**Status.** The host tests, offline builds of both variants and the QEMU tests
run. As of this repository's first public commit, no image built here has run
on a unit. Five FPGA GPIO blocks and the second Ethernet port's mode in the
board device tree still await a read-only device-tree measurement on a unit.

## Device UI acceptance

```bash
node tools/ui-accept/accept.mjs ../mujina-frontend --scenario nominal-3b
```

Serves the Device UI (the mujina-frontend repository) with its mock, loads
it in headless Chromium at 1440 and 400 px, and fails on a page that stops
polling, asks for anything but the allowlisted GETs, throws, scrolls sideways on
a phone, or renders a real identifier. Set `UI_ACCEPT_SHOTS=<dir>` to keep
screenshots. The first run installs the pinned Playwright core under
`<project>/build` with npm; the Chromium it drives must already be in
`~/.cache/ms-playwright`, since nothing here downloads a browser.

## Contributing

Derive, never copy. Everything here is written in our own words and our own
code; no vendor file, fragment, table, patch or binary enters this repository or
an image it builds. A fact about the hardware carries its provenance (DESIGN.md,
"Provenance tags"), and only what was measured on a unit is published.

Every change starts from an issue and a test that fails for the reason the
issue names, then the change, until `tests/run.sh` passes.

## Issue references

This repository was seeded from a private predecessor as one squashed commit
(`tools/publish-seed`). References of the form `#N` in its files point to that
predecessor's issue tracker, not to this repository's issues.

## Licence

GPL-2.0-or-later; see [LICENSE](LICENSE). The Reckless Systems, 256 Foundation
and Blockscale Solutions names and logos are their owners' marks and are not
covered by the code licence; see [NOTICE](NOTICE).
