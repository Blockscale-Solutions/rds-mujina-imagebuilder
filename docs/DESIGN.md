# Design of the RDS Mujina image builder

**Status: accepted, 2026-09-24.** This is the design as Ronald accepted it that day. His answers to D1 to D13 are recorded in #17; where they differ from the proposals below, #17 wins. The tree is authoritative wherever it and this document differ (section 4.1 says where).

**Inputs**, all private working notes of this project: the vendor baseline (the baseline to beat, criteria C1 to C20), the platform facts, three approach reports (OpenWrt, Buildroot, and Yocto with Debian, with its evidence directory) and two reviews of them (a judge and a skeptic). Also issues #4, #6, #7, #8 and #14. Issue numbers (#N) refer to the tracker of this repository's private predecessor.

**Provenance tags.** Every fact carries one.
- **MEASURED**: our capture, with its path.
- **OURS**: our docs or issues.
- **PUBLIC**: a URL or public source at a named tag.
- **Vendor-derived** (written in capitals where used): read in vendor material. Such a fact is never published: it is replaced by a measurement first, and `tools/publish-seed` refuses a tree that still carries the tag.
- **DERIVED**: an inference from tagged facts, named as such.
- **UNMEASURED**: nobody has measured it. Zero opportunities is never a pass.

**Who.** The Mujina port project (`mujina_bzm2`) ports Mujina to this board, builds the stock image this design is compared against, owns the test unit and runs every on-unit step.

**Path keys.** `u:` = our capture directory for the test unit, kept by the Mujina port project (not public). `S` = the Mujina port repository, `mujina-bzm2-dev` (not yet public). `ev:` = the evidence directory of the Yocto and Debian approach report (a private working note).

---

## 0. The decision in one screen

1. **Buildroot 2026.08 with a BR2_EXTERNAL tree of ours.** Both independent reviews chose it over OpenWrt and Yocto, for three reasons:
   - It fits a 16 MiB slot with a read-only squashfs root.
   - It has the smallest machinery for one board and one application.
   - It has the lowest effort to a flashed unit with a tested rollback.
   Issue #6's title says "OpenWrt". Ronald's own words there only ask for a fresh, current OS (OURS #6), so the choice of Buildroot is listed as a decision for him (section 12).
2. **Userspace by default for the FPGA IP (OURS #14).** The kernel exposes each block through UIO, and a process of ours drives it.
   - A kernel driver of ours is built only where a measurement shows userspace is materially worse.
   - For the chain UART, the first measurement is arithmetic: FIFO depth and DMA against the wake-up budget. The kernel `serial_core` driver that all three reports assumed becomes the **measured alternative**, not the plan.
   - Mainline drivers that already exist (NAND, EMAC, HPS I2C, CAN, watchdog, `i2c-altera`, `gpio-altera`) are used as they are. That adds no kernel code of ours.
3. **Nothing of the vendor's enters our repo or our images.** The unit keeps its own bitstream, its MCU firmware and, for now, its own SPL and U-Boot.
   - Ronald's stated end state is the whole vendor stack replaced, with the bitstream as the only vendor artifact kept (OURS, Ronald, 2026-09-24).
   - So the bootloader moves in three generations: the unit's own U-Boot, then our U-Boot proper, then our own SPL. Each generation is gated on a recovery path that has been proven first.
4. **The first boot of our kernel writes nothing, and that is checked, not assumed.** The kernel is started by kexec from the vendor OS and cannot write NAND.
   - A mainline Denali probe can write a new bad-block table even when every partition is read-only (skeptic, PUBLIC `denali.c` lines 1237 to 1238 and `nand_bbt.c` lines 1341 to 1344). So the canary kernel skips the BBT scan and holds the controller's write-protect.
   - The vendor's two BBT blocks are hashed before and after.
5. **The layout does not change for the first install.** Our slot takes the 133 LEB of the vendor's inactive rootfs. `factory`, `firmware`, `config` and `data` are never written on any path of ours. Stock stays the default-environment fallback until Ronald retires it.

**Top three risks.** Section 11 gives each with its mitigation.
1. The NAND ECC and OOB format.
2. A vendor bootloader we cannot see into.
3. The chain UART's real behaviour against our reading of it.

---

## 1. Goals and non-goals

### Goals

- **G1.** One command, from a clean checkout on the build host, produces every flashable artifact, offline after a single fetch. The build is reproducible byte for byte and carries its provenance.
- **G2.** An image of ours runs Mujina and the Device UI on the RDS control board with a current LTS kernel.
- **G3.** Updates are signed and checked before any write. Each slot pairs its own kernel with its own rootfs. Fallback is automatic and remote, and every way back has been tested before it is needed.
- **G4.** Every per-unit fact survives every path of ours: identity, calibration, configuration, `/data`, the bitstream and the MCU code.
- **G5.** The work is redistributable. It contains no vendor bytes, and every output's licence is known and met.
- **G6.** Every gate named in section 2 exists as a test that has been seen to fail before it counts as a pass.
- **G7.** A failure keeps its evidence: oops text, diffoscope reports, power-cut traces. Logging off the unit (netconsole, pstore) is built in from the first image.

### Non-goals

- **Rebuilding the FPGA bitstream, or writing a new fabric design.** Our register specs can later serve as the spec for one, but that is out of scope (OURS plan s0.2).
- **Programming hash-board MCUs.** Our OS leaves MCU code as it finds it.
- **Reproducing the stock vendor image.** That is `room:vendor` work in #9 to #13, run by the Mujina port project. It is the baseline we compare against, not our product.
- **LuCI, UCI or a general router OS.** The unit is an appliance with one payload.
- **SHA-256 offload and the ICSP block.** Mujina does not need them (platform-facts s5).
- **Touching the test unit from this project.** Every on-unit step is a handoff to the Mujina port project, which runs the unit, and each one needs Ronald's go-ahead (OURS).
- **A second hardware platform in v1.** The structure allows one (section 4.5), but nothing is built for it.

---

## 2. Superior to the vendor: the criteria as gates

These are the baseline's C1 to C20, turned into gates. Each gate is a test in `tests/`, and each one must first be seen to fail.

A gate that ran zero cases exits 2 (unmeasured). It is never reported as a pass.

Numbers marked (proposed) need Ronald's figure. The vendor column holds only what we measured, running the vendor build or on the unit (the vendor baseline, a private working note). A dash marks a gate whose vendor behaviour we only read in vendor material; that is not published (Ronald, 2026-09-28).

| id | gate | vendor baseline | pass condition | tier |
|---|---|---|---|---|
| C1 | one command | 4 to 6 commands plus hand fixes | `env/rds build` from a fresh clone ends 0 with every artifact present; 1 on failure; 2 when nothing was built | container |
| C2 | cheapest disqualifier first | a missing toolchain found after clones; a failed commit cost 2 h | `env/rds preflight` finishes under 60 s (proposed) and catches a planted missing input, a tmpfs `TMPDIR` and lock drift | host |
| C3 | every input pinned | fetches from 53 hosts during the build (build log) | the generated lock covers 100% of fetched bytes; an injected unlisted fetch fails | container |
| C4 | offline | network needed in two compile stages; 31 timeouts | every stage after `fetch` runs under `--network=none` and succeeds | container |
| C5 | byte-identical rebuilds | never tried: one tagged build exists | two clean builds that differ in path, time, user, umask, locale and `-j` give identical unsigned artifacts; a diffoscope report is kept on failure | container |
| C6 | version from source, totally ordered | a date-and-time version string on the unit | version from `git describe` and `SOURCE_DATE_EPOCH`; the ordering test passes over a table that includes the vendor's non-ordering cases | host |
| C7 | time bounds | 2 h 25 min clean compute | the build records its own stage times. Cold offline full build under 60 min (proposed); one OS-package change to a bundle under 5 min (proposed) | container |
| C8 | image fits, headroom from one layout file | — | the build fails when any image exceeds its volume and prints headroom per volume computed from `layout.toml` | host |
| C9 | failures stop the build | wrapper exits 0 on a failed compile | a planted compile error gives a nonzero exit | container |
| C10 | verified, authentic updates, failing closed | — | unsigned, tampered and wrong-key bundles are all refused with zero bytes written; the owner can enrol a key | qemu |
| C11 | real A/B with confirmation and fallback | one kernel volume, no second (volume table) | kernel, DTB and rootfs travel per slot; a boot-once counter; an unconfirmed slot falls back with nobody on site | qemu, then unit |
| C12 | rollback tested on hardware | never | RDS-AB-01 to 07 recorded on a unit before a second unit is flashed | unit |
| C13 | identity survives | — | `factory`, `firmware`, `config` and `/data` (minus our own directory) hash equal before and after every path | qemu, then unit |
| C14 | no vendor bytes; firmware volume untouched | — | the deny-list scan over images, bundles and legal-info finds zero hits; post-flash `/firmware` hashes equal pre-flash | host, then unit |
| C15 | MCU revision never changes silently | — | our OS contains no MCU programming path; a test asserts no such tool is installed | container |
| C16 | provenance generated and cross-checked | tree hash and image ids only | provenance carries the lock hash, source commit, toolchain input hash, container digest, `SOURCE_DATE_EPOCH` and the bitstream allowlist; a missing field fails | container |
| C17 | no shared mutable build state | long-lived builder; debug build can leak into stock | build A, then debug, then A again: the two A builds are identical | container |
| C18 | host hygiene | build images of 2.8, 10.3 and 10.3 GB, layers shared (podman) | rootless podman; nothing written outside the project root; `du` recorded; cap of 40 GB (proposed, to be reset from the first measurement) | container |
| C19 | the chain port survives its holder's death | measured oops needing a reboot; a counter latched until reboot | killing a multi-threaded holder of all three ports mid-frame, 100 cycles on the unit and 1000 in QEMU (proposed), leaves no oops, no D-state task and no latch. The ports reopen within 1 s (proposed). A racing open fails cleanly. The first frame after a reopen is correctly addressed | host, qemu, then unit |
| C20 | recovery timed; only a true brick needs a site visit | never timed | fallback covers bad images remotely; SD recovery is timed once per image line | unit |

**C11 has been reworded.** The Yocto report pointed out that "kernel paired with rootfs per slot" needs a second slot of ours. In layout L1 there is only one slot of ours, and stock is the other. True A/B arrives with L2 (section 7.4). So C11 passes on L1 only for the pair "ours or stock", and that limit is stated rather than hidden.

**C7 against Mujina.** Mujina's release profile uses fat LTO and one codegen unit (OURS `S/Cargo.toml`), which takes 8 to 12 min per build. We therefore build Mujina outside the OS build (section 4.3), so the 5-minute bound measures OS packages only. That is stated as a limit of the gate.

---

## 3. Platform facts the design depends on

This section is a summary. The platform facts (a private working note) are the one home for these facts, and this list only points at them; the FPGA blocks' own home is `os/board/rds-control/hw.toml`.

- **SoC.** Cyclone V HPS, 2x Cortex-A9 with VFPv3-D32 and NEON, 1 GiB DRAM, no RTC (MEASURED `u:inventory/20260915T014110Z/system.txt`).
- **NAND.** Micron MT29F4G08ABADAWP, 2 KiB pages, 64 B OOB, 128 KiB blocks (MEASURED `u:inventory/20260915T014110Z/logs.txt` lines 263 to 268).
  - Vendor BBTs at pages 262080 and 262016, version 0x01.
  - UBI on `mtd1`: LEB 126,976 B, 3951 LEB reserved, 0 PEBs free.
- **Volumes (LEB).** factory 34, firmware 19, boot 53, rootfs 133, rootfs1 133, config 34, data 3545 (MEASURED).
- **Root selection.** The kernel command line selects root by name (`ubi.mtd=1,2048 root=ubi0:rootfs`), and U-Boot appends the reset reason, the serial and the MAC (MEASURED `u:inventory/kernel-20260924/unit-kernel-facts.txt` line 2).
- **Vendor kernel config** (MEASURED `u:inventory/kernel-20260924/config-4.9.78-ltsi.txt`):
  - set: `CONFIG_KEXEC=y` (line 545), `CRASH_DUMP=y`, `HOTPLUG_CPU=y`, `DEVMEM=y` with `STRICT_DEVMEM` off;
  - not set: UIO, NETCONSOLE, PSTORE, SQUASHFS.
- **Boot contract.** What is MEASURED: Linux has no FPGA manager and finds the bridges already enabled (handoff `0x1ff`), so the bootloader loads the bitstream from `firmware` before Linux (section 8); and the kernel command line is the bootloader's (line 2 of the kernel facts above).
  - What the unit's U-Boot loads from `boot`, how it boots it, and its default environment are UNMEASURED until Q-BOOT and Q-ENV (#61).
- **FPGA blocks.** Three 9-bit chain UARTs at physical `0xC005_0000`, `+0x200` and `+0x400`, GIC 73 to 75. Three PL330 DMA channels are active while they run; which transfers those carry is UNMEASURED. Four PWM, four tacho and four I2C blocks, and five 32-line GPIO controllers, sit behind the lightweight bridge (MEASURED from the stock kernel's `/proc/iomem`, `/proc/interrupts` and gpiochip list; `hw.toml` cites each). The GPIO blocks' addresses await #61.
- **The vendor chain UART** is three separate raw `tty_driver`s, not `serial_core` (MEASURED names in `u:testcases/MJ-HASH-07/20260924T041148Z/dmesg-after-abort.txt`; decode in skeptic checkpoint 2).
  - Its holder death ends in a NULL `tty->ops` read in `release_tty`.
  - A refused open can latch its private counter until reboot (OURS hazards.md).
- **Ethernet.** A DM9161 10/100 PHY on EMAC1. It very likely passes through the FPGA, so there is no network before the bitstream is loaded (platform-facts fact 3, M-H; the Buildroot report notes a schematic hint the other way, low confidence).
- **Mainline Linux 6.18.53 builds for this SoC** in 195 s at `-j32` (MEASURED `ev:result2.txt`).
  - With XZ and UBI, UBIFS and `i2c-altera` added, the zImage is **4,794,016 B**.
  - With gzip it is 7,103,272 B, larger than the whole 6,729,728 B `boot` volume.

---

## 4. Architecture

### 4.1 Repository shape

The planned shape, as accepted. Each file name below is the one home of its fact. **As built**, the container is `env/container/` with `env/apt.list`, the lock is `env/lock.tsv`, the board DTS is `os/board/rds-control/rds-control.dts` with the generated `rds-fpga.dtsi`, and `env/rds` runs `preflight`, `fetch`, `build`, `test` and `repro`; `ip/`, `qemu/`, `boards.txt` and the `release` stage are not built yet.

| path | holds |
|---|---|
| `env/Containerfile`, `env/apt.list`, `env/snapshot` | the build container: base digest, apt snapshot timestamp, exact package set |
| `env/rds` | the single entry point: `preflight`, `fetch`, `build`, `test`, `repro`, `release`. Exit 0 pass, 1 fail, 2 nothing ran |
| `lock/rds.lock.json` | **generated**: every fetched byte by sha256, git inputs by commit, the container by digest. Never hand-edited |
| `os/` | the BR2_EXTERNAL tree: `configs/`, `board/rds-control/`, `package/`, `patches/` |
| `os/board/rds-control/layout.toml` | every UBI volume's name, id, type, size, slot group and write policy (`never`, `install`, `update`). The only place a volume size is stated |
| `os/board/rds-control/hw.toml` | the measured address, IRQ and compatible table. The DTS test, the health check's expected-device list and the UIO bindings all read it |
| `os/board/rds-control/dts/` | our DTS, written from `hw.toml` and mainline `socfpga_cyclone5.dtsi` |
| `ip/<block>/` | per FPGA block: our register spec citing the kernel-port spec's requirement ids, the register model, the userspace driver crate, and its tests |
| `qemu/` | our patch to a pinned QEMU release: a machine at the real Cyclone V addresses with models of our blocks |
| `data/allowlist/bitstream.tsv` | known bitstream hashes as facts. It holds no bytes |
| `tests/` | the gates, run by `tests/run.sh` (host tier) and `tests/slow/`, `tests/qemu/` |
| `tools/` | layout and budget checker, version ordering, deny-list scanner, env-block finder, installer, capture compare |

**Everything derived from `layout.toml` is generated** and checked for drift in S0:
- RAUC's `system.conf`;
- the chooser script's volume names;
- the `ubi.block=` arguments;
- the installer's write plan and never-write list;
- the budget gate's limits;
- the table in this document's successor docs.

### 4.2 The container

- **Base.** `debian:trixie-slim@sha256:7792b1f7702a86946cd518db72b6a407302c3e9bc1635634368b878189e8221c` (digest recorded by the Yocto agent; re-verified at build).
- **Packages.** apt from `snapshot.debian.org` at one fixed timestamp. The build fails if `dpkg-query` shows any set other than `env/apt.list`.
- **Contents.** Only Buildroot's documented host prerequisites plus `python3`, `file`, `rsync` and `cpio`.
- **Tools built as Buildroot host packages** from pinned sources: the cross toolchain, `dtc`, `mkimage`, `ubinize`, `mksquashfs`, `rauc`, `veritysetup` and `genimage`. This is what supplies the tools the build host lacks.
- **diffoscope** lives in a separate comparison container, pulled only when a reproducibility check fails.
- **Built reproducibly** with `buildah bud --timestamp $SOURCE_DATE_EPOCH`. A rebuild must give the same digest, or the difference is a finding.
- **How it runs.**
  - Rootless podman, `--rm`, `--userns=keep-id`. A fresh container and a fresh output directory for every build and every variant (release, debug, qemu) (C17).
  - Mounts: the checkout read-only, the mirror read-only, and a per-build output volume at the fixed path `/w/out`. Buildroot's reproducibility holds only for a fixed output path (PUBLIC Buildroot 2026.08 `Config.in` help).
  - `TMPDIR` on the build volume, never tmpfs. That is the lesson of the Mujina port project's 10 GB commit failure (OURS build-runbook). The build host's `/tmp` is a tmpfs measured at 94% full during this research (MEASURED, Yocto notes).
  - The vendor reference tree is never mounted.
- **Memory.** Claude Code's own task killer stops background tasks on low free memory (OURS cross-project memory). So long builds run with a bounded `-j`, and their stage stamps let an interrupted build resume.

### 4.3 Inputs, pinning and caching

| input | pinned by | cached in |
|---|---|---|
| Buildroot 2026.08 | release tarball sha256 plus its PGP signature against a fingerprint committed here (PUBLIC buildroot.org) | `archive/mirror/` |
| every package source | Buildroot `.hash` files with `BR2_DOWNLOAD_FORCE_CHECK_HASHES=y`; our packages carry their own | `archive/mirror/`, served as `BR2_PRIMARY_SITE` with `BR2_PRIMARY_SITE_ONLY=y` |
| Linux 6.18.y LTS | kernel.org tarball sha256, checked against `sha256sums.asc` (done once, MEASURED `ev:`) | same |
| our kernel patches | repo commit | git |
| cross toolchain (gcc, musl, armv7 hard-float NEON) | built by Buildroot from pinned sources; packaged once as an SDK tarball keyed by the hash of its inputs | `build/cache/sdk/` (regenerable); released copies in `archive/` |
| **Mujina** | **a hashed prebuilt input.** It is built in its own digest-pinned `rust:1.94` container (MEASURED `S/build.Containerfile` line 9) with `cargo --locked --offline` from vendored crates, then imported into the image by sha256 | `archive/mirror/` |
| Device UI | git commit of `mujina-bzm2-device-ui` | same |
| QEMU (tests only) | release tarball sha256 plus our patch | same |
| container | digest plus apt snapshot | OCI archive in `archive/containers/` |

**Why Mujina is a prebuilt input** (the skeptic's graft 5):
- Buildroot 2026.08 would bring its own `host-rust` 1.97.1 (PUBLIC). Mujina pins 1.94. That is two homes for one fact.
- Importing the static musl binary by hash keeps one Rust, the one Mujina pins.
- It also takes Mujina's fat-LTO time out of the OS inner loop.
- The Mujina build recipe and its provenance are part of our release source bundle, so GPL corresponding source is still complete.

**Why sources live in `archive/`, not `build/`.** An upstream that disappears cannot be regenerated. The Linaro host that answers 200 with an HTML page is the proof (OURS build-runbook). Under HOUSEKEEPING.md, a cache that is the only copy is `archive/` class.

**The lock is generated** from four things:
- `make show-info`;
- the hash files;
- the container digest and snapshot;
- the SDK input hash, the Mujina binary hash and the git commits.

`preflight` regenerates it and fails on any difference.

### 4.4 Stages, cheapest failure first

Each stage stamp is keyed by the hash of the stage's inputs, never by its name. The vendor driver's name-keyed markers are the defect this fixes (OURS baseline s6).

Every stage logs its wall time, so the estimates below (DERIVED, UNMEASURED) get replaced by measurements (C7).

| # | stage | runs on | cost | fails on |
|---|---|---|---|---|
| S0 | preflight | host, no container | under 60 s | lock drift; a missing or mismatched cache entry; container digest absent; disk under floor; tmpfs `TMPDIR`; generated files differing from their regeneration; layout sum not 3951 LEB; budget predicted negative from last measured sizes; version not derivable; the vendor deny-list manifest missing (exit 2, unmeasured) |
| S0h | host unit tests | host | seconds | every IP block's register model and userspace driver tests; layout, version, chooser-table and env-finder tests |
| S1 | fetch | container, **network** | minutes, only when the lock changes | any byte that does not match the lock; an unlisted fetch |
| S2 | toolchain and host tools, as an SDK | container, offline | 12 to 20 min cold; 0 cached | toolchain breakage |
| S3 | kernel, DTB, config audit, KUnit | container, offline | 5 to 8 min | a symbol the fragment asks for missing after `olddefconfig`; DTS disagreeing with `hw.toml`; KUnit failure |
| S4 | packages and rootfs | container, offline | 5 to 10 min | a compile failure (propagates, C9); a package with no hash or no licence |
| S5 | images and gates | container, offline | 2 to 3 min | over-budget volume (C8); deny-list hit (C14); missing provenance field (C16); unknown licence |
| S6 | U-Boot sandbox and QEMU | container, offline | 15 to 30 min | chooser scenarios; UIO holder-death torture; RAUC fallback; nandsim power-cut campaign |
| S7 | reproducibility | container, offline | R1 about 2 min; R2 one more full build | any unlisted difference |
| S8 | release | host, key holder | minutes | signing; SBOM; source bundle; handoff bundle to the Mujina port project |
| S9 | on the unit | the Mujina port project, with Ronald's go-ahead | unit windows | reality |

A cold offline build (S2 to S5) is estimated at 35 to 50 min on the build host's 32 threads, which fits C7.

### 4.5 Extension points

- **A board.** Add `board/<name>/` with its own `layout.toml`, `hw.toml` and DTS, a defconfig, and a line in `boards.txt`. Every gate iterates over `boards.txt`.
- **A package.** Add `package/<name>/{Config.in,<name>.mk,<name>.hash}`. The lock regenerates. A package without a hash fails S1, and one without a licence fails S5.
- **An FPGA block.** Add `ip/<block>/` with four things:
  1. the spec page citing kernel-port-spec requirement ids;
  2. a register model;
  3. the userspace driver and its host tests;
  4. a QEMU model and scenario list, plus an on-unit test-case id.

  A row in `ip/REGISTRY.tsv` lists them. S0 fails a block with a missing piece, so a driver without tests cannot merge (the OpenWrt report's registry idea).
- **A kernel module of ours** (only after a measurement chose it, #14) follows the same registry row plus a KUnit suite.
- **A kernel bump.** The S3 config audit shows which symbols moved. S6 reruns. The on-unit cross-read test (section 7.2 step 6) repeats for every kernel version, because NAND format compatibility is per kernel.

---

## 5. Reproducibility

**Mechanisms:**
- `BR2_REPRODUCIBLE=y`, with `SOURCE_DATE_EPOCH` set to the commit time.
- The fixed output path `/w/out`.
- `KBUILD_BUILD_*` set by Buildroot.
- squashfs times clamped to the epoch.
- **No UBIFS image and no `ubinize` in the update path.** RAUC writes squashfs, the kernel and the DTB straight into UBI volumes. That removes three sources of variation at their origin, all MEASURED (`ev:`):
  - mkfs.ubifs's random UUID, which changes 20 bytes;
  - its readdir order, which changes about 10 MB when the same files are created in reverse order;
  - `ubinize`'s random image sequence number.
- Where a full-flash image is ever needed (a recovery card, gen 2), we carry a small mtd-utils patch that derives the UUID from the version and sorts directory entries, and we pass `ubinize -Q` from the epoch. The patch goes upstream.
- The version comes from `git describe` plus the epoch (C6).

**Signatures.**
- RAUC's CMS signature embeds a signing time. So the gate compares the **unsigned** payloads, and the one allowed difference, the CMS envelope, is listed in `repro/allowed-differences.tsv`. That list starts with that single row and needs a reason and an issue for any new row.
- If Ronald wants signed bundles to compare equal too, a deterministic scheme is available (SWUpdate with PKCS#1 v1.5 was measured by the Yocto agent; decision D6).

**The gate:**
- **R1, every commit.** Assemble S5 twice from the same staged inputs and require identical hashes.
- **R2, weekly and before every release.** Two clean builds that differ in host path, wall time (under faketime), user, hostname, umask, locale and `-j`. Compare every artifact and every file inside the squashfs.
- **On failure:** exit 1, and keep the diffoscope report in `data/build-evidence/<UTC>-repro/`. It stays until it has become a fix and a test (imperative 2). A pass collapses to two manifest lines.
- **Instrument first.** Before R2 counts, it must fail once on a seeded build with an unclamped timestamp.

**Honest risk.** Buildroot labels `BR2_REPRODUCIBLE` experimental, so the first R2 will likely find a package or two to fix. That is the gate doing its job.

---

## 6. Driver plan for the FPGA IP, hardware-free tests first

### 6.1 Access model per block

The rule comes from OURS #14: userspace through UIO by default, and a kernel driver of ours only where a measurement shows userspace is materially worse.

| block | instances | default access | kernel code of ours | open question that could change it |
|---|---|---|---|---|
| 9-bit chain UART | 3 at `0xC005_0000/0200/0400`, GIC 73 to 75; three PL330 channels active while mining | **UIO** (`uio_pdrv_genirq`, mainline) plus a userspace driver crate | none, unless the arithmetic gate says RX needs DMA that userspace cannot own. Then a `serial_core` driver (6.3) | FIFO depth, DMA handshake and who sets the ninth bit (kernel-port spec) |
| PWM | 4, lightweight bridge | **UIO** plus userspace; a fan failsafe (6.4) | none | the block's reset state before any write (spec C-PWM-2) |
| tacho | 4, GIC 89 to 92 | **UIO** plus userspace, reporting the latch age | none | none: the gate register reads back (on-unit case C-TACH-1, kernel-port spec) |
| FPGA I2C | 4 (`ff244000` and up) | **mainline `i2c-altera`** if the registers match the public Avalon I2C core (PUBLIC; the stock kernel names the blocks `i2c`, MEASURED) | none | Q8 compatible; the kill-mid-transfer test (6.5). If it wedges, UIO is the alternative |
| FPGA GPIO | 5 x 32 | **mainline `gpio-altera`** with `gpio-line-names`; the gpiod chardev by name | none | Q8 compatible |
| HPS blocks: NAND, EMAC, dw_mmc, DW I2C, 8250, PL330, dwapb, c_can, dw_wdt, bridges | | mainline | none | none |
| SHA-256 offload, ICSP, `gpioUART` | | not built | none | none |

**Why UIO first** (OURS #14, plus DERIVED):
- A userspace holder that dies releases a mapping, not a tty. That removes the whole fault class seen in MJ-HASH-07.
- The same driver code runs against a register model in a host test in seconds. That is the cheapest tier of the whole plan.
- It keeps the kernel close to mainline, needing only UIO and DT nodes.
- Braiins OS drove the S9's FPGA IP from userspace through UIO on the same class of SoC. It is GPL-3.0 prior art we may reuse with attribution (OURS; MEASURED clone in the corpus, last commit March 2020).

**What UIO does not solve by itself** (DERIVED, stated so that no one assumes it):
- **The RX DMA.** The PL330 is a shared HPS engine: three of its channels are active while the chain UARTs run (MEASURED; which direction is UNMEASURED), and others may be in use elsewhere. Userspace must not program it through `/dev/mem`. If the arithmetic gate (6.2 step 1) shows that RX needs DMA, the options are, in order of preference:
  - (a) the IP's own FIFO is deep enough for interrupt-driven userspace reads;
  - (b) a small generic kernel helper that runs a dmaengine cyclic RX into a buffer mapped to userspace, and that owns teardown when the file closes;
  - (c) the `serial_core` driver.
  Each option is measured, not chosen by preference.
- **The fabric's state after a holder dies.** Whoever opens the device next must reset the block's TX and RX state before the first frame. That is a requirement on the userspace driver, and it is tested (6.2).
- **The fan's safe state.** Section 6.4.

### 6.2 The chain UART: test ladder, cheapest first

**Requirements come from the kernel-port spec**, which the Mujina port project maintains (not yet public). Our tests cite its requirement ids by name. An issue that needs a missing requirement is blocked on a `spec`-labelled request, and a citation-check test (`tools/spec-cite`) fails while an id we cite does not exist in the spec.

1. **Arithmetic, no hardware** (the first step of #14).
   - A script computes wake-ups per second, per bus and for all three buses, at 5 Mbaud with 11-bit characters (about 454,500 characters/s, OURS #14). Its inputs are the spec's FIFO depth, interrupt thresholds and DMA model.
   - It compares the result with the control board's budget of about a fifth of one core while mining (OURS control-board-budget.md).
   - The verdict is `userspace-irq`, `needs-dma-helper` or `kernel`, and it decides which of the options in 6.1 is built.
   - Built as `tools/uart-budget` (#27).
     - The FIFO facts come from `hw.toml`'s chain-uart blocks. The costs and the sustained load come from `os/board/rds-control/uart-budget.toml`, each cost as a sourced [low, high] range.
     - The verdict is computed at both ends. When the ends disagree it is UNDECIDED, and the tool names the input to measure.
     - `--min-depth` prints the receive depth a userspace driver needs.
   - **The receive FIFO depth is the open input.** No capture gives it, and which direction the DMA channels serve is unmeasured (UNMEASURED; #19 asks the kernel-port spec for the receive depth).
   - **The latency input holds only for a preemptible kernel.** The worst latency is what sets the deadline: with no kernel preemption it is several times longer (PUBLIC measurements, cited in the cost file), and mainline 6.18 cannot build PREEMPT_RT for 32-bit ARM (MEASURED: `arch/arm/Kconfig` does not select `ARCH_SUPPORTS_RT`). So the board kernel requests `CONFIG_PREEMPT=y`, and a test ties that to the cost file's `kernel_preemption`.
2. **Register model plus the userspace driver, on the host.**
   - The driver's register access goes through one trait with two implementations: `mmap` of `/dev/uioN`, and the model.
   - Tests cover:
     - framing byte-compatible with what Mujina writes today (a 2-byte little-endian length, then a header whose first byte is the ASIC id; OURS `S/mujina-miner/src/asic/bzm2/protocol.rs`);
     - the divisor table (divisor 2 gives 5 Mbaud and divisor 10 gives 1 Mbaud; our fit is baud = 50 MHz / (5 x divisor), OURS MJ-BAUD-02);
     - RX ring arithmetic.
   - The sharp cases:
     - **kill mid-frame, reopen, and the first frame on the wire is correctly addressed;**
     - an open racing a close.
3. **Planted mutants, before any pass counts.** Each harness must catch each of these:
   - a driver that does not reset TX framing on open;
   - one that keeps a private "open" flag across a crash;
   - one that frees an RX buffer while a model DMA is still writing it.
4. **QEMU** (`qemu/`, our patch to a pinned release).
   - One machine with a Cortex-A9 MPCore, a GIC, a PL330 and a 16550, plus our models at the **real** Cyclone V addresses and GIC numbers, so our real DTS runs unchanged (the Yocto graft). QEMU's `xilinx-zynq-a9` shows that this CPU complex plus PL330 is already modelled (PUBLIC `hw/arm/xilinx_zynq.c`).
   - The UART model has a loopback mode, a chardev back-end to a chain emulator, and two fault knobs: "TX never drains" and "RX stalls".
   - The guest runs with KASAN, KFENCE, lockdep, `DEBUG_OBJECTS` and hung-task detection at 10 s.
   - **Torture.** SIGKILL of a multi-threaded holder of all three ports during TX, during RX, inside open and inside close. Also an open 0 to 500 ms after a close in 1 ms steps, and an unbind and rebind of the UIO device. 100 cycles per class per commit and 1000 nightly (proposed).
   - **Pass:** no splat, no D-state task after 10 s, reopen within 1 s, and the first frame correctly addressed.
   - **Known limit:** QEMU's PL330 models peripheral requests only as a busy level (PUBLIC `hw/dma/pl330.c` lines 1006 to 1048 and 1283 to 1289). So the FPGA side of the RX DMA handshake is proven only on the unit.
5. **On the unit** (the Mujina port project, with Ronald's go-ahead): the three steps of #14.
   1. The vendor driver as the baseline. A `/dev/mem` polling prototype on the stock kernel, with that port's vendor driver left unopened. This is only an upper bound on CPU.
   2. On our kernel, the UIO driver with the same traffic: throughput and loss, latency at p50 and p99, CPU, and 100 kill cycles.
   3. An ASIC loopback and a mining comparison against stock.

**The blind spot.** The model and the driver come from the same reading of the spec, so they can agree on a misunderstanding. Only step 5 can catch that, which is why stock stays the fallback until step 5 passes.

**If a kernel driver is chosen** (the measured alternative), the three approach reports' design applies unchanged:
- `serial_core` ownership of the tty lifetime and no private open counter;
- a `shutdown()` that masks the IP's interrupts, calls `synchronize_irq` and `dmaengine_terminate_sync`, discards the TX FIFO and only then frees buffers;
- a bounded `closing_wait`;
- the rate taken through `BOTHER` and read back truthfully;
- state published in sysfs, and no print per open.

Two additions from the skeptic's review:
- The TX framing state resets on `flush_buffer`, `startup` and `shutdown`.
- The driver does not own the fabric-wide clock. It takes 50 MHz from a property or a fixed-clock node, so an unbind cannot gate the fabric.

**The ninth-bit ABI** (skeptic checkpoint 5): byte-compatible framing first, not per-command `ADDRB`.
- Mainline `TIOCSRS485` applies a new destination without draining queued TX (PUBLIC `serial_core.c` line 1473, `8250_dwlib.c` lines 116 to 123).
- BZM2 changes destination on every command.

### 6.3 PWM and tacho

- **PWM.**
  - Userspace writes the period and duty. The period is 40,000 ns, which is 25 kHz (OURS hazards.md).
  - The enable gate is write-only, so the driver reports "last commanded", never "state".
  - Free-run is about 5,430 rpm, **not** full speed (OURS hazards.md). So "released" is not "safe".
- **Tacho.**
  - The driver reports rpm together with the age of the latch.
  - A reading taken while the gate is closed is marked stale (OURS hazards.md: the reading latches while the gate is closed; command, then wait 15 s, then read).
  - The rpm factor is 30 per count (OURS `platform.rs`).
- **Tests:** host model tests (period and duty math, the staleness rule), then a QEMU model, then an on-unit read-back with the boards dark.

### 6.4 Fan failsafe: a requirement UIO creates

With a kernel PWM driver, `remove` and `shutdown` hooks could force full duty. With UIO, a holder that dies leaves the last duty in place. So the OS runs `rds-failsafe`, a small supervisor that does four things:
- it holds its own mapping of the PWM blocks;
- it watches the PWM holder's pid (pidfd);
- on the holder's exit, for any reason, it writes 100% duty to every channel;
- it logs one line with a count.

**Test (host, then QEMU):** kill the holder with SIGKILL, and every model channel reads full duty within 1 s (proposed). The failsafe itself runs under init's respawn.

This does not replace the MCU heartbeat shed, whose measured times disagree (118 s, 74 to 80 s, 16 min; OURS hazards.md). Nothing relies on that shed.

### 6.5 I2C and GPIO

- **I2C.** `i2c-altera` must finish or cleanly abort a transfer, with a STOP, when the caller is killed. Killing `bzmd` mid-transfer wedged the vendor bus until reboot (OURS hazards.md).
  - Test on the unit with read-only MCU commands only. A read never arms the MCU watchdog (OURS evidence B).
  - If the bus wedges under the mainline driver, UIO with a userspace bit-level controller is the measured alternative.
- **GPIO.** Names come from DT `gpio-line-names` (`psu-enable`, `hash0-reset` and so on), and Mujina uses gpiod by name.
  - Every sysfs number moves on a modern kernel: bases grow upward from 512 (platform-facts fact 5).
  - **PSU enable is never hogged and never asserted by kernel or init.** It is one key of the supply's two-key interlock (OURS supply-can-protocol.md).
- **CAN.** `can1` is brought up at 500 kbit/s. No tool that can transmit is started automatically.

---

## 7. First flash, updates and rollback

**Who does what.** The Mujina port project runs the test unit and does every flash (OURS). Our side builds a **handoff bundle**:
- images;
- provenance;
- the install and rollback scripts with `--dry-run`;
- proposed abort conditions;
- a recovery path already exercised in QEMU.

Every step below that touches the unit is marked **[needs Ronald go-ahead]**.

### 7.1 Layouts

The numbers below come from `layout.toml` and are restated here only as the proposal. Sizes are DERIVED; the kernel figure is MEASURED at `ev:result2.txt`.

**L1, the first install.** Only `rootfs1`, the vendor's inactive root, is replaced, after an off-unit capture.

| volume | LEB | bytes | holds | budget |
|---|---|---|---|---|
| `a_kernel` (static) | 44 | 5,586,944 | zImage, XZ | measured mainline kernel 4,794,016 B: 14% headroom before trimming |
| `a_dtb` (static) | 1 | 126,976 | our DTB with `/chosen/rds,roothash` | about 16 KB |
| `a_root` (dynamic) | 86 | 10,919,936 | squashfs xz plus the verity tree | estimate 6.5 to 8 MB (Mujina 1,583,372 B under xz, MEASURED; UI 210,545 B, MEASURED; the rest UNMEASURED) |
| `xtest` (dynamic) | 2 | 253,952 | cross-read scratch | fixed |
| **sum** | **133** | | equals `rootfs1` | |

**L2, the steady state after stock is retired.** Stock's `boot` (53 LEB) plus `rootfs` (133 LEB), 186 LEB in all, become:
- slot B: kernel 44, DTB 1, root 86;
- `rescue` 55: a kernel with an initramfs holding dropbear, mtd-utils and the bundle verifier.

`data` keeps its 3545 LEB, and nothing ever shrinks it. UBIFS cannot shrink, and re-creating `/data` would hold per-unit history only in RAM while it happened.

**Why a separate DTB volume.** Two reasons:
- The chooser must always pass a DTB address to `bootz`. On a U-Boot built without ATAG support, `bootz` with no DTB hangs in U-Boot, before any kernel watchdog (PUBLIC `socfpga_common.h`; `arch/arm/lib/bootm.c` lines 239 to 270; skeptic checkpoint 3).
- U-Boot's bootargs survive. They carry the reset reason (MEASURED `reset reason: 4000`), which is a signal we keep.

**The verity root hash** rides in a DTB property that U-Boot does not overwrite. A tiny initramfs in the kernel reads it, sets up dm-verity with `veritysetup` and switches root. Kernel, DTB and root are one RAUC slot group, so they travel together.

**UBIFS format.** Every kernel of ours runs with `ubifs.default_version=4` until stock is retired (PUBLIC mainline module parameter; skeptic checkpoint 4). Otherwise a volume our kernel formats is w5, which the vendor kernel mounts read-only only.

### 7.2 First install: a staircase, each step cheaper and more reversible than the next

Preconditions:
- Ronald's explicit yes;
- no Mujina port project window running;
- remote power control or a person present;
- an off-unit capture with a hashed manifest, stored in the Mujina port project's `data/`, never in git. It holds `factory`, `config`, `data`, `firmware`, every other volume, `mtd0` and the last two NAND blocks.

| step | kernel writing | what is written | if it fails | marker |
|---|---|---|---|---|
| 1. Read-only measurements (section 10) | none | nothing | nothing to undo | [needs Ronald go-ahead] |
| 2. **kexec canary** from a fresh vendor boot: autostart off, chain ports never opened, and `ip link set eth1 down` in the same command as `kexec -e`. kexec does not stop bus masters without a shutdown hook (skeptic checkpoint 5) | ours, **cannot write**: BBT scan skipped, Denali write-protect held, every mtd partition `ro`, UBI in read-only mode | nothing. It hashes every volume against the capture, checks devices against `hw.toml`, checks the bitstream hash, reports over netconsole, then reboots | a power cycle returns to stock | [needs Ronald go-ahead] |
| 3. BBT check | vendor | nothing | none | the last two blocks read by the vendor kernel hash equal to the capture, and the canary's log has no "Bad block table written" line |
| 4. Install slot A | **vendor** (our static mtd-utils copied to `/tmp`) | `rootfs1` removed; `a_kernel`, `a_dtb`, `a_root` and `xtest` created, written and read back | stock boots; "restore to stock" re-creates `rootfs1` from the capture | [needs Ronald go-ahead] |
| 5. Chooser | vendor (`fw_setenv`, env offset found by a CRC scan of the `mtd0` dump) | env: the chooser script, stock's bootcmd saved from the unit's own env, `BOOT_ORDER="A stock"`, `A_LEFT=1` | a bad env write falls back to the built-in default, which Q-ENV must first show boots stock | [needs Ronald go-ahead] |
| 6. **Boot-once through U-Boot** | ours, write-protected as in step 2 | the chooser **decrements and saves before it jumps** (the Yocto graft), so a hang, panic or power cut boots stock next. A 3.3 V console listens at 115200 (MEASURED `console=ttyS0,115200`) if one is fitted | stock | [needs Ronald go-ahead] |
| 7. Cross-read | ours, `xtest` only writable | ours writes a pattern and the vendor kernel reads it back identical, then the reverse | `xtest` is scratch | [needs Ronald go-ahead] |
| 8. First real boot | ours, `/data/rdsos` writable | `A_LEFT=3`; the health check passes, then mark-good | three failed boots return to stock | [needs Ronald go-ahead] |
| 9. Soak, then L2 | ours | stock volumes captured and removed; slot B and `rescue` created | slot A still boots | [needs Ronald go-ahead], plus D8 |

**What the health check requires before mark-good:**
- every device in `hw.toml` probed;
- `/data` mounted read-write;
- the `factory` manifest unchanged;
- the bitstream hash in the allowlist;
- sshd listening;
- no oops since boot.

It deliberately does not require mining. The unit may be idle on purpose with autostart off (OURS image-changelog).

**If the env is not scriptable** (step 1 shows no `fw_setenv`, no env, or no `setenv` or `saveenv`): the fallback is the OpenWrt report's kexec chain. A bootstrap in `boot` would kexec our slot. That is a larger change, so it is a decision for Ronald rather than a silent switch. An early replacement of U-Boot is **not** the fallback.

### 7.3 Updates

- A RAUC bundle, signed and in verity format, is pushed over ssh.
  - RAUC writes only the inactive slot group.
  - The signature is required, and the verifier fails closed. The OpenWrt lesson: a stock check that passes when its tool is missing is fail-open.
  - `use-bundle-signing-time=true`, because there is no RTC.
- The version ordering hook refuses a downgrade or a reinstall of the same version unless a flag is given (C6).
- The chooser tries the new slot with 3 attempts (proposed). The health check marks it good. Otherwise the unit falls back.
- In L1 the other slot is stock, so an update means going through stock and repeating step 4. L1 is meant to be short.
- **Per-slot config.** Configuration lives under `/data/rdsos/slot-<x>/`, so a rollback returns to the configuration that belonged to that version (the OpenWrt graft).
- **Boot event ledger.** `/data/rdsos/events` records each boot's reset reason (from the command line), slot, attempt, and whether it was confirmed or fell back.

### 7.4 Rollback, tested

Test cases have the same ids in QEMU and on the unit.

- **RDS-AB-01:** the new slot never confirms, and the unit falls back.
- **RDS-AB-02:** the new kernel panics before userspace, and the unit falls back.
- **RDS-AB-03:** a flipped byte in the bundle is refused, with zero bytes written.
- **RDS-AB-04:** power cut during the slot write. Run in QEMU with nandsim and UBI's `emulate_power_cut` (PUBLIC 6.18 `ubi/debug.c`). On the unit only if remote mains switching exists; otherwise marked UNMEASURED on hardware.
- **RDS-AB-05:** manual rollback (`rauc status mark-active other`).
- **RDS-AB-06:** back to stock by env in L1; from `rescue` using the captured volumes in L2.
- **RDS-AB-07:** power cut during the env write, which leads to stock through the default env.
- **RDS-AB-08:** both slots bad: rescue in L2, stock in L1.

**In simulation:**
- The chooser script runs in U-Boot sandbox against a scenario table.
- The Linux side runs in QEMU on nandsim with the measured geometry.

**On the unit:** before and after captures for each case, with `factory`, `firmware`, `config` and `/data` hashes equal (C13). Ronald's go-ahead is needed for each case.

### 7.5 Bootloader generations

| gen | SPL | U-Boot proper | enters when |
|---|---|---|---|
| 1 | the unit's own | the unit's own; we write env only | step 5 above |
| 2 | the unit's own | mainline v2026.07 built by us: verified FIT, `hash verify` of the bitstream against the allowlist, `wdt start`, redundant env in UBI, boot-once | SD recovery demonstrated on a **second** unit (#8); [needs Ronald go-ahead] |
| 3 | ours, from our own Quartus handoff (PLL, SDRAM, pinmux, IOCSR generated by Quartus Prime Lite from our own HPS configuration and measured register state) | ours | Ronald's end state. Needs Q1, Q2 and Q5 answered and a proven recovery. High risk |

Reading the handoff tables out of the vendor preloader binary is copying, so it is ruled out (platform-facts fact 1).

### 7.6 Against the vendor process, point by point

The vendor column holds only what we measured; a dash marks behaviour we only read in vendor material (section 2).

| point | vendor | ours | gate |
|---|---|---|---|
| getting an image | credentialed download; 2 h 12 min env build | one command; offline after one fetch | C1, C4 |
| inputs | fetched from 53 hosts during the build | everything, in a generated lock | C3 |
| determinism | never tried | R1 per commit, R2 weekly, diffoscope kept | C5 |
| failure propagation | a failed compile exits 0 | planted-failure test | C9 |
| size | — | gated from `layout.toml` | C8 |
| integrity | — | signed verity bundle, fail-closed, every image verified | C10 |
| kernel update | one kernel volume | per slot, with DTB and root | C11 |
| fallback | — | boot-once counter, health mark-good, rescue | C11, C20 |
| identity | — | never written on any path | C13 |
| firmware and MCUs | — | never written; hash checked | C14, C15 |
| holder death | kernel oops; reboot needed | userspace holder; fan failsafe; torture gate | C19 |
| logging | no netconsole, no pstore | both, from the first image | G7 |

---

## 8. Bitstream handling

- **Never in our repo, image, bundle, recovery card or legal-info output.** It stays in the unit's own `firmware` volume.
  - The pinned revision is `/firmware/soc_system.rbf`, 1,544,828 B, sha256 `789e72a7...0d8dd5` (MEASURED `u:inventory/20260915T014110Z/storage.txt`).
  - A second revision of 1,542,828 B exists on the file server; its hash is pending (OURS #4).
- **Loading.** In gen 1 the unit's U-Boot loads it before Linux, as today (MEASURED: no fpga_manager in Linux, bridge handoff `0x1ff`). Our DT carries no `bridge-enable` property, so the mainline bridge drivers leave the bridges as they find them (PUBLIC 6.18 `altera-hps2fpga.c`). In gen 2, our U-Boot runs `hash verify` against the allowlist before `fpga load`.
- **The allowlist.** `data/allowlist/bitstream.tsv` holds hashes, which are facts, not bytes. It is matched by hash, never by file name, because the file names are identical (OURS #4).
  - An unknown hash does not stop the OS from booting.
  - It does stop the miner, because a different fabric can change the UART, PWM and tacho behaviour underneath us.
  - The fleet is assumed mixed until measured.
- **Runtime reload from Linux is not used.** Ethernet probably depends on the fabric, and a reload resets the UARTs.
- **If a unit loses its `firmware` volume,** our tool restores it from **that owner's own capture** onto that owner's unit, and nothing flows through our distribution.
- **MCU hex, SPL and U-Boot** follow the same rule until gen 2 or gen 3 replaces the bootloader with ours.
- **The deny-list scan.** Gate C14 compares every output file's hash with a manifest of the vendor reference tree's file hashes (`tools/deny-scan`). The caller names the manifest or tree, which are read in place where their owner keeps them and never committed here. With no source the scan exits 2 (unmeasured). A local-only similarity scan of normalised source windows is the second layer (the OpenWrt report's clean-room gate).

---

## 9. Licensing

The licence fields are PUBLIC from Buildroot 2026.08 package files unless marked. **Proposed** licences are Ronald's call.

| output | licence | obligation |
|---|---|---|
| this repo's tooling, BR2_EXTERNAL tree and scripts | GPL-2.0-or-later (D8; matches Buildroot). `LICENSE` holds the text | none beyond the licence |
| `ip/*` userspace driver crates | GPL-2.0-or-later (D8). **GPL-3.0 if Braiins OS code is reused**, with attribution | the licence text shipped |
| our kernel patches (BBT skip, and a DMA helper if chosen) | GPL-2.0-only | corresponding source |
| our DTS, and the include `tools/hw2dts` generates | GPL-2.0-or-later, as the repo; each file carries the SPDX line | none |
| QEMU patch | GPL-2.0-or-later | build-time only; never in an image |
| kernel image | GPL-2.0 | corresponding source in the release bundle |
| rootfs: BusyBox, musl, dropbear, RAUC, glib2, OpenSSL 3, squashfs-tools, mtd-utils, libubootenv, chrony | as each package declares; emitted by `make legal-info` and in an SPDX SBOM | sources and licence texts; LGPL parts dynamically linked |
| **Mujina** and its vendored crates | **GPL-3.0-or-later** (MEASURED `S/Cargo.toml`); crates read against an allowlist in S5, because Buildroot does not list prebuilt crates | anyone who receives the image is owed complete corresponding source, **including the RDS carrier code**, which is published (D3). GPLv3 installation information applies to a consumer device that enforces signatures, so the **owner must be able to enrol their own key**. The key point is decision D6 |
| Device UI | MIT (OURS); fonts OFL-1.1 and the Ubuntu Font Licence, with their texts shipped (MEASURED `ui/fonts/licenses/`) | ship the texts |
| release bundle | images, SBOM, legal-info, corresponding-source bundle (every lock entry plus our repos at the build commit), provenance | GPL source duty met without relying on upstream hosts |
| **not an output** | bitstream, MCU hex, vendor SPL and U-Boot, vendor DT, vendor patches | never leave the owner's unit (C14) |
| names and logos | the Reckless Systems, 256 Foundation and Blockscale Solutions names and logos are their owners' marks, not covered by the code licence (`NOTICE`) | none |

**A leak path to close.** Release builds fetch Mujina by commit, never from a local checkout, so nothing outside the committed tree can reach an image, and the deny-list scan covers the legal-info output too.

---

## 10. Open questions, with the cheapest measurement for each

All on-unit items are read-only unless marked. They are run by the Mujina port project and **[need Ronald go-ahead]**. They are batched into one message, because several agents writing to a session that runs a live 3 kW unit is noise.

| # | question | cheapest measurement | decides |
|---|---|---|---|
| Q-ECC | NAND ECC step, strength and OOB skip | `cat /sys/class/mtd/mtd0/{writesize,oobsize,ecc_strength,ecc_step_size}` (seconds) | risk 1; whether a mainline Denali patch is needed (mainline socfpga allows 8 or 15 on 512 B steps and forces 2 skip bytes, PUBLIC `denali_dt.c` lines 37 to 43) |
| Q-ENV | env location, redundancy, bootcmd, command set | `cat /etc/fw_env.config; which fw_printenv fw_setenv; fw_printenv`; plus an `mtd0` dump into the Mujina port project's `data/`, scanned by our CRC finder (the tool is ours; the input stays theirs) | gen 1 chooser; `bootz` addresses; ATAG support |
| Q-WDT | watchdog at handoff, and its timeout | `cat /sys/class/watchdog/watchdog0/{identity,timeout,state,bootstatus}` | whether a hang before init needs a power cycle |
| Q-DT | compatibles, `reg`, `interrupts`, `dmas`, EMAC1 `phy-mode` | print the matching `/proc/device-tree` nodes | `hw.toml`; `i2c-altera` and `gpio-altera`; whether Ethernet needs the fabric |
| Q-UBI | volume ids, types, sizes | `/sys/class/ubi/ubi0_*/{name,type,reserved_ebs,data_bytes}` (`ubinfo` is absent, MEASURED) | `layout.toml` fixtures |
| Q-BOOT | files and sizes in the `boot` volume | `mount -o ro ubi0:boot` then `ls -lR` and `sha256sum` | load addresses; the size of the vendor kernel |
| Q-FW | `/firmware` hashes after the 9-14 OTA | `sha256sum /firmware/*` | whether the OTA changed the MCU hex; the allowlist |
| Q-CLK | SoC part, MPU and L4 clocks, and the chain UART's 50 MHz source | `cat /sys/kernel/debug/clk/clk_summary`; a photo of the SoC marking | gen 3 PLL; whether our kernel can shift the baud rate |
| Q-DRAM | DRAM type, width and timings; pinmux | `devmem` reads of the SDRAM controller and sysmgr, if `devmem` exists | gen 3 only |
| Q-BSEL | does the recovery button drive BSEL, or is a jumper needed | read sysmgr `bootinfo`; trace continuity with the unit **unpowered** | #8 SD recovery |
| Q-CON | serial console header and voltage (the baud rate is MEASURED at 115200) | a power-off inspection | step 6 visibility |
| Q-JTAG | is JTAG exposed | a power-off inspection | brick recovery |
| Q-UART | FIFO depth, RX DMA handshake, who sets the ninth bit, how the length prefix is consumed | **not on the unit**: the kernel-port spec (Mujina port project), then an ASIC loopback | 6.1 access model; the arithmetic gate |
| Q-BIT2 | the second bitstream's hash | a hash of the file-server copy | the allowlist |
| Q-POWER | is there remote mains switching, and which unit is the spare | ask Ronald | step 2 onward; RDS-AB-04; gen 2 |
| Q-SIZE | real sizes of our kernel, root, RAUC with glib2 and OpenSSL | the first S5 build | budget; RAUC versus SWUpdate with mbedTLS |
| Q-TIME | cold build and footprint | the first S2 to S5 run | C7, C18 numbers |

**Log capture the Mujina port project can use today.** The stock kernel has neither netconsole nor pstore (MEASURED), so the ring buffer is the only copy of an oops.
- Stream `dmesg -w` over ssh into `data/` on the lab controller for every window.
- At an abort, capture `/proc/<pid>/stack` and `wchan` for every thread of the holder, then `echo w > /proc/sysrq-trigger`.
- `ports.sh` should report FREE only when there has been no Oops, recursive-fault or BUG line and no D-state thread since its mark. At 04:11Z it read FREE 17 to 40 ms before the oops (MEASURED).

---

## 11. Top three risks

1. **NAND format compatibility.** The vendor's ECC, skip bytes and BBT may differ from mainline's.
   - Impact: our kernel could misread `factory`. A BBT write or a UBI scrub could then damage it.
   - Mitigations:
     - Q-ECC first.
     - A kexec canary that cannot write, with the BBT scan skipped and write-protect held.
     - A BBT hash check.
     - A cross-read on `xtest` before `/data` is ever writable.
     - A repeat for every kernel bump.
2. **A bootloader we cannot see into, and later one we write ourselves.**
   - Gen 1 depends on an env that is UNMEASURED. Gen 2 writes the one region with no A/B.
   - Mitigations:
     - Q-ENV first.
     - A boot-once chooser whose failure mode is the stock default.
     - Always passing a DTB.
     - Gen 2 gated on #8 on a second unit.
     - Remote power before step 2.
3. **The chain UART against the real IP.** Our driver and our model share one reading of the spec, and QEMU's PL330 does not model the fabric's DMA handshake.
   - Mitigations:
     - Byte compatibility with the framing Mujina already uses.
     - Mutants that each harness must catch.
     - A differential comparison against stock on the unit.
     - Stock kept as the fallback until the on-unit tier passes.

**Runners-up:**
- RAUC's glib2 and OpenSSL may miss the 86-LEB root budget. SWUpdate with mbedTLS is the measured fallback.
- `BR2_REPRODUCIBLE` is experimental.
- The `rescue` budget is tight.
- The kernel-port spec is incomplete, and it gates all of section 6.

---

## 12. Decisions only Ronald can make

These are listed in the structured output of this workflow. The proposed answer is given each time.

| id | decision | proposal |
|---|---|---|
| D1 | Buildroot, although #6's title says OpenWrt | Buildroot; rename #6 |
| D2 | the order of the bootloader generations, and whether gen 3 (our own SPL) is required for "the whole vendor stack replaced" | gen 1 now; gen 2 after #8 on a second unit; gen 3 only if distribution needs it |
| D3 | GPL-3 Mujina and the carrier code in a distributed image | **decided 2026-09-24**: redistributable images, with the carrier code published (#17) |
| D4 | the userspace-first reading of #14 for I2C and GPIO, where mainline drivers exist | use the mainline drivers; UIO only if the kill test fails |
| D5 | the numbers | preflight 60 s; cold build 60 min; package change 5 min; tries 3; torture 1000 in QEMU and 100 on the unit; disk cap from the first measurement |
| D6 | signing | release key offline; owner key enrolment documented and tested; whether signed bundles must also be byte-identical |
| D7 | retiring stock (L2) | **amended by Ronald 2026-09-24**: not before two confirmed updates, RDS-AB-01 to 07, all three RDS-PAR-01 arms, the stock power-on bus capture, and an empty list of anything still needing a stock boot. "Don't retire the existing interface earlier than necessary." (#17) |
| D8 | the licence of this repo and of the `ip/` crates; whether to reuse Braiins OS code (which makes those crates GPL-3.0) | **decided 2026-09-24**: GPL-2.0-or-later; reuse only if it saves real work |
| D9 | the spare unit, and remote mains switching | needed before step 2 and before gen 2 |
| D10 | the fallback if the vendor env is not scriptable | a kexec bootstrap in `boot`, not an early U-Boot replacement |
| D11 | the clean-room rule as written | **settled 2026-09-24**: the output rule binds: derive, never copy. Nothing of the vendor's enters this repository or an image it builds, except the bitstream the owner's unit supplies. |

---

## 13. Backlog

The ordered issue backlog (51 issues, host tier first, then container, then sandbox and QEMU, then the unit) was generated by one script, which checked that every dependency names an existing title, and filed once Ronald approved the design. That tracker belongs to this repository's private predecessor; the #N references here point to it. Every on-unit issue carries the marker **[needs Ronald go-ahead]**.
