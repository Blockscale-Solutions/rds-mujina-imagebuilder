# C4 (#37): a package that tries to download at build time.
RDS_PLANT_NETFETCH_SITE = $(BR2_EXTERNAL_RDS_PLANT_PATH)/package/rds-plant-netfetch/src
RDS_PLANT_NETFETCH_SITE_METHOD = local
define HOST_RDS_PLANT_NETFETCH_BUILD_CMDS
	python3 -c "import urllib.request; urllib.request.urlopen('https://example.com/', timeout=10)"
endef
$(eval $(host-generic-package))
