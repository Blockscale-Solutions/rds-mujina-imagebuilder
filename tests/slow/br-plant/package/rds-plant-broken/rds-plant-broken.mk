# C9 (#38): a package whose source does not compile.
RDS_PLANT_BROKEN_SITE = $(BR2_EXTERNAL_RDS_PLANT_PATH)/package/rds-plant-broken/src
RDS_PLANT_BROKEN_SITE_METHOD = local
define HOST_RDS_PLANT_BROKEN_BUILD_CMDS
	$(HOSTCC) -o $(@D)/broken $(@D)/broken.c
endef
define HOST_RDS_PLANT_BROKEN_INSTALL_CMDS
	$(INSTALL) -D -m 0755 $(@D)/broken $(HOST_DIR)/bin/rds-plant-broken
endef
$(eval $(host-generic-package))
