# Kernel port specification: the RDS control board's FPGA blocks

What the replacement drivers must do, for each FPGA block that Mujina uses.
The drivers may be in-kernel or userspace (#14).
Each requirement has an id of the form `REQ-<BLOCK>-<n>`. Tests cite those ids, and
`tools/spec-cite` fails any cited id this file lacks (#18).

Written by the mujina_bzm2 session from two sources only: what Mujina's own
code does on these interfaces, and what we have measured on bonanza. `u:` paths
are captures under `data/units/bonanza/`, as in DESIGN.md. Where a value is not
yet measured, the requirement says so and names the test that will settle it.
UNMEASURED is never a pass.

Sections: **Chain UART** (this revision). PWM and tacho follow.

## Chain UART

Three ports, one per hashboard chain. The ASICs on a chain share one serial
link at 5 Mbaud with 9-bit framing, and the FPGA block moves the data with DMA.

### Interface Mujina depends on

- **REQ-UART-1: three ports, stable names, stable order.** One character
  device per chain. A given name always reaches the same chain, across boots.
  Today they are `/dev/tty9bit00`, `/dev/tty9bit10` and `/dev/tty9bit20`,
  which the stock kernel logs as the blocks at map bases `c0050000`,
  `c0050200` and `c0050400` (u:testcases/MJ-BAUD-01/20260915T042209Z/,
  `dmesg-vendor.txt`). These are **physical** addresses: at probe the stock
  kernel prints each port's physical base (a field it names `mapbase`)
  beside its ioremapped virtual one (`membase`: `f08e0000`, `f10f7200`,
  `f190e400`) (u:inventory/20260915T014110Z/logs.txt). The name is the
  field's only: the stock driver does **not** register through the serial
  core. It is three separate tty drivers, `tty9BIT0` to `tty9BIT2`, each
  major 267 with one minor. The chain ports' sysfs directories carry none
  of the serial-core attributes (`uartclk`, `iomem_base`,
  `xmit_fifo_size`, ...) that `ttyS0`'s do
  (u:inventory/tty-drivers-20260925/tty-drivers.txt). A serial-core driver
  is therefore a new structure, not a like-for-like replacement. What
  carries over is the interface in this section. All three ports sit in
  one 4 KiB page, `0xc0050000`-`0xc0050fff`. In the same page, `c0050100`,
  `c0050101` and `c0050102` are claimed by a separate GPIO-UART driver
  (`/dev/gpioUart0` to `2`, major 240, in the same capture). Mujina does
  not use those ports. What those three addresses are, and whether the FPGA
  decodes them, is UNMEASURED. Keeping these names is not required. A stable
  mapping is. **Test:** on two cold boots, each name reaches the same board's chain,
  which answers a register read with its own ASIC ids.

- **REQ-UART-2: 5 Mbaud, and a rate that can be verified.** The port runs at 5
  Mbaud. Userspace can read back the rate actually applied, and a request the
  driver does not honour fails. It must not succeed silently. On the stock
  kernel, a plain 5 Mbaud request returned success and did nothing observable.
  The rate is set only through a control-flag override, the rate cannot be
  read back from userspace, and it was confirmed only by the divisor the
  kernel logged: divisor 2 on all three ports (case MJ-BAUD-02; Mujina
  `mujina-miner/src/transport/serial.rs`, `open_with_platform_cflag`).
  **Test:** request 5 Mbaud with a standard termios call, read it back, and
  get 5,000,000. Request a rate the block cannot make, and get an error.

- **REQ-UART-3: transmit framing.** A write carries whole frames. Each frame
  begins with a 2-byte little-endian length that counts the whole frame,
  including those 2 bytes. Then comes the frame: a 4-byte big-endian header
  (ASIC id, opcode, engine address, offset), a count byte and the payload
  (Mujina `mujina-miner/src/asic/bzm2/protocol.rs`, `encode_write_register`
  and the encoders after it). The driver, or its userspace equivalent, turns
  that into chain traffic. Two points are **UNMEASURED**: whether the length
  prefix itself goes on the wire, and which byte carries the ninth bit.
  Settle them with a line capture of one register read on one port, and state
  the result here before any driver depends on it.
  **Test:** a register read written in this form is answered by the addressed
  ASIC, with the value a second, independent read returns.

- **REQ-UART-4: receive stream.** Received bytes are delivered in order, none
  dropped and none duplicated, with no framing added. Mujina frames replies
  from its own record of the read it is waiting on, and it resynchronises
  after bytes it cannot parse (`protocol.rs`, the parser and its test
  `parser_resyncs_after_unknown_prefix_and_partial_frames`).
  **Test:** 10,000 register reads on each port, with every reply parsed and
  none lost or doubled, at the traffic in REQ-UART-8.

### Ownership and lifecycle

- **REQ-UART-5: one owner at a time.** A second open of an open port fails at
  once with EBUSY and leaves no state behind. On the stock kernel, an open
  that landed during the previous owner's close was refused but left the
  port's counter raised. The port then refused every opener until a reboot
  (measured, and the reason the harness reads the kernel's open and close
  lines before any start: mujina-bzm2-dev `tools/rds/rds-switch.sh`, the
  chain-tty ownership block). **Test:** open, then open again (EBUSY), close
  the first, and open again, which must succeed. Also race an open against a
  close 1,000 times: every open either succeeds or gets EBUSY, and an open
  after the close always succeeds.

- **REQ-UART-6: a holder's death releases the port, with no kernel fault.**
  Every open is matched by exactly one release, including when the holder is
  killed mid-transfer. On the stock kernel a final close faulted the kernel
  in the tty release path (#71; u:testcases/MJ-HASH-07/20260924T041148Z/).
  **Test:** 1,000 cycles of open, write, kill the holder with a transfer in
  flight, then reopen. Every reopen succeeds, and the kernel log shows no
  fault. **This test must fail on the stock kernel**, which is the evidence
  that it measures the defect (#71).

- **REQ-UART-7: a close is complete when it returns.** A port can be reopened
  as soon as `close()` has returned in the previous holder. On the stock
  kernel the close is logged on entry, and an open in the few hundred
  milliseconds after it hits the case in REQ-UART-5 (`rds-switch.sh`,
  ownership block). **Test:** close, then open with no delay, 1,000 times,
  and every open succeeds.

### Capacity, errors and reset

- **REQ-UART-8: no loss at the measured traffic.** A three-board mining
  window recorded about 10.6 KB/s of wire traffic across the three ports
  (case MJ-HASH-06, as MJ-HASH-07's record uses it). The block's FIFO depth,
  interrupt thresholds and receive DMA handshake are **UNMEASURED**. They are
  settled by the userspace register model (#28) and the arithmetic gate
  (#27), and the requirement is the outcome: no overrun at ten times that
  rate. **Test:** REQ-UART-4's test at ten times the MJ-HASH-06 rate, with
  the overrun counters (REQ-UART-9) unchanged.

- **REQ-UART-9: error counters are readable while the port is open.** Receive
  overruns (buffer and FIFO) and framing errors are counted per port, and
  userspace can read them without closing the port. On the stock kernel
  these counts appear only in the close log line, "buf_overrun" and "fifo
  overrun" (u:testcases/MJ-BAUD-01/20260915T042209Z/). **Test:** force an
  overrun by not reading. The counter advances and is readable before the
  close.

- **REQ-UART-10: opening does not reset the chain; stale bytes are not new
  bytes.** Opening or closing a port changes no line that resets the ASICs.
  Chain reset is a separate GPIO (Mujina `serial.rs`, the note above
  `open_with_platform_cflag`). What open and close do to the FIFOs and the
  DMA state is **UNMEASURED**. The requirement: bytes received before an open
  are either discarded at the open or reported as such, never delivered as if
  they were a reply to the new holder. **Test:** leave a reply half-read, kill
  the holder, reopen, and send a register read. The first reply parsed is
  that read's.
