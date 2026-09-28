RDS_CANARY_PROBE_VERSION = 1
RDS_CANARY_PROBE_SITE = $(BR2_EXTERNAL_RDS_PATH)/package/rds-canary-probe/src
RDS_CANARY_PROBE_SITE_METHOD = local
RDS_CANARY_PROBE_LICENSE = GPL-2.0-or-later
$(eval $(kernel-module))
$(eval $(generic-package))
