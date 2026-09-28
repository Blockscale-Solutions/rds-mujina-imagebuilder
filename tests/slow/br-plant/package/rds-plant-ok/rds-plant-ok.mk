# The twin: a package that builds, so a failure above is the package's own.
RDS_PLANT_OK_SITE = $(BR2_EXTERNAL_RDS_PLANT_PATH)/package/rds-plant-ok/src
RDS_PLANT_OK_SITE_METHOD = local
define HOST_RDS_PLANT_OK_BUILD_CMDS
	$(HOSTCC) -o $(@D)/ok $(@D)/ok.c
endef
define HOST_RDS_PLANT_OK_INSTALL_CMDS
	$(INSTALL) -D -m 0755 $(@D)/ok $(HOST_DIR)/bin/rds-plant-ok
endef
$(eval $(host-generic-package))
