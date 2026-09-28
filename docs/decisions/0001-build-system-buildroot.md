# 0001: Build system is Buildroot

**Decided** by Ronald, 2026-09-24 (D1 in #17), and confirmed the same day after
comparing Yocto. **Status:** accepted.

## Decision

The RDS OS is built with Buildroot (2026.08) and a BR2_EXTERNAL tree of ours,
on a mainline long-term kernel. Not OpenWrt, not Yocto, not Debian.

## The measured fit

Slots are 133 LEB of 126,976 B (about 16 MB), fixed by the unit's flash
(`os/board/rds-control/layout.toml`). Measured 2026-09-23 with mkfs.ubifs on
real content (the Yocto and Debian approach report, a private working note,
22:40 to 23:55 PT):

| root filesystem | used | fits |
|---|---|---|
| musl, busybox, dropbear, UBI tools, SWUpdate, Mujina, Device UI, real 6.18 XZ kernel | 98 of 133 LEB (74%) | yes |
| the same with RAUC (glib plus OpenSSL) as the updater | 134 LEB | no, one over |
| Debian armhf, smallest supported variant | 103 MiB installed | no, about 6 times the slot |

The musl rows used Alpine armv7 packages as a stand-in for a Yocto build.

## Why Buildroot

- **Fit is decided by content, not by the build tool.** Buildroot and Yocto
  build the same musl and busybox root. Debian, the "more complete Linux",
  does not fit the slots at all.
- **Both reviewers chose Buildroot** (the judges' comparison, a private working note):
  a minimal read-only root, simple configuration, and the cheapest route to
  byte-identical rebuilds and a cold build inside the 60 minute budget (C7)
  and 40 GB disk cap (C18).
- **Yocto's proposal fell short on layout, not on the tool:** one main slot
  plus a failsafe instead of true A/B, and a likely overrun of C7 and C18.
- **OpenWrt** carried a permanent fork of its upgrade and preinit machinery,
  and a bootstrap kernel with no try counter in the one volume the vendor
  U-Boot always boots.

## What we give up, and how we get it back

Yocto's real advantage is test instrumentation: ptest ships upstream package
test suites into the image, testimage runs them on QEMU or hardware, and an
on-target package manager adds debug tools without a reflash.

We recover that without spending slot space: **instrumentation lives in a
separate test image** (#70), built from the same tree with a second defconfig
(gdbserver, strace, perf, package test suites) and booted in QEMU or from
`/data` or SD. The size gate refuses it in any production slot. Buildroot's
own QEMU runtime test framework carries the automated tests.

## Revisit if

- The test image cannot be kept in step with production from one tree.
- A measured Buildroot cold build breaks C7 or C18.
