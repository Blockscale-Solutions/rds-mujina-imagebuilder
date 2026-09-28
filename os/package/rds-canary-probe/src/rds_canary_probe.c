// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * rds-canary-probe: QEMU test apparatus for rdsmujina-env #51. Calls the raw
 * NAND driver's hooks directly, bypassing mtdcore's MTD_WRITEABLE checks, so
 * the canary patch's inner refusals are measured rather than inferred. Prints
 * one line: every return code, for the host to judge. Never in a board image.
 */
#include <linux/module.h>
#include <linux/mtd/mtd.h>
#include <linux/mtd/nand.h>
#include <linux/slab.h>

static char *mtdname = "NAND simulator partition 0";
module_param(mtdname, charp, 0444);

static int __init rds_canary_probe_init(void)
{
	struct mtd_info *part = get_mtd_device_nm(mtdname);
	struct mtd_info *mtd;
	loff_t base;
	struct erase_info ei = { 0 };
	struct mtd_oob_ops ops = { 0 };
	struct nand_device *nand;
	struct nand_pos pos;
	int erase, woob_place, woob_raw, oob_only, markbad, panic = 1, dev_erase = 1, dev_markbad = 1;
	size_t retlen = 0;
	u8 *buf;

	if (IS_ERR(part)) {
		pr_info("rds-canary-probe: error=no-mtd name=\"%s\"\n", mtdname);
		return 0;
	}
	/* Partitions carry no driver hooks in 6.18; the core routes to the master. */
	mtd = mtd_get_master(part);
	base = mtd_get_master_ofs(part, 0);
	buf = kmalloc(mtd->writesize + mtd->oobsize, GFP_KERNEL);
	if (!buf)
		goto out;
	memset(buf, 0x5a, mtd->writesize + mtd->oobsize);

	ei.addr = base + 2 * mtd->erasesize;	/* not block 0, not the table area */
	ei.len = mtd->erasesize;
	erase = mtd->_erase ? mtd->_erase(mtd, &ei) : 1;

	ops.mode = MTD_OPS_PLACE_OOB; ops.len = mtd->writesize; ops.datbuf = buf;
	woob_place = mtd->_write_oob ? mtd->_write_oob(mtd, base + 3 * mtd->erasesize, &ops) : 1;
	memset(&ops, 0, sizeof(ops));
	/* A raw program is a whole page: data and OOB, or the chip sees a short page. */
	ops.mode = MTD_OPS_RAW; ops.len = mtd->writesize; ops.datbuf = buf;
	ops.ooblen = mtd->oobsize; ops.oobbuf = buf + mtd->writesize;
	woob_raw = mtd->_write_oob ? mtd->_write_oob(mtd, base + 3 * mtd->erasesize + mtd->writesize, &ops) : 1;
	memset(&ops, 0, sizeof(ops));
	ops.mode = MTD_OPS_PLACE_OOB; ops.ooblen = 4; ops.oobbuf = buf;
	oob_only = mtd->_write_oob ? mtd->_write_oob(mtd, base + 3 * mtd->erasesize + 2 * mtd->writesize, &ops) : 1;
	markbad = mtd->_block_markbad ? mtd->_block_markbad(mtd, base + 4 * mtd->erasesize) : 1;
	if (mtd->_panic_write)
		panic = mtd->_panic_write(mtd, base + 5 * mtd->erasesize, mtd->writesize, &retlen, buf);

	nand = mtd_to_nanddev(mtd);
	if (nand && nand->ops) {
		nanddev_offs_to_pos(nand, base + 6 * mtd->erasesize, &pos);
		if (nand->ops->erase)
			dev_erase = nand->ops->erase(nand, &pos);
		nanddev_offs_to_pos(nand, base + 7 * mtd->erasesize, &pos);
		if (nand->ops->markbad)
			dev_markbad = nand->ops->markbad(nand, &pos);
	}
	pr_info("rds-canary-probe: erase=%d woob_place=%d woob_raw=%d oob_only=%d markbad=%d panic=%d dev_erase=%d dev_markbad=%d\n",
		erase, woob_place, woob_raw, oob_only, markbad, panic, dev_erase, dev_markbad);
	kfree(buf);
out:
	put_mtd_device(part);
	return 0;
}

static void __exit rds_canary_probe_exit(void) { }

module_init(rds_canary_probe_init);
module_exit(rds_canary_probe_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("rdsmujina-env #51 canary probe (test apparatus)");
