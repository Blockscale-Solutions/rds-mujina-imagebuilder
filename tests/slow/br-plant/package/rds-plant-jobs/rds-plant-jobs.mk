# #96: prints the job count Buildroot will use, so a test can see it honour a CPU limit.
RDS_PLANT_JOBS_SITE = $(BR2_EXTERNAL_RDS_PLANT_PATH)/package/rds-plant-jobs/src
RDS_PLANT_JOBS_SITE_METHOD = local
define HOST_RDS_PLANT_JOBS_BUILD_CMDS
	@echo "RDS-PLANT-JOBS=$(PARALLEL_JOBS)"
endef
$(eval $(host-generic-package))
