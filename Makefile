REPORTER = dot

# =================================================
# Docker Machine Env Variables
# =================================================

DOCKER_MACHINE_BIN?=docker-machine

DOCKER_MACHINE=$(DOCKER_MACHINE_BIN) $(DOCKER_MACHINE_OPTS)

# =================================================
# OS Specific Configuration.
# =================================================
ifeq ($(OS),Linux)
		MD5_SUM="md5sum"
else
		MD5_SUM="md5"
endif

# =================================================
# Targets
# =================================================

#all: release-prod

docker-machine-create:

	$(DOCKER_MACHINE) create\
    --driver virtualbox \
		--virtualbox-boot2docker-url "http://mirror.cs.vt.edu/pub/CentOS/7/isos/x86_64/CentOS-7-x86_64-Minimal-1511.iso" \
   	--virtualbox-cpu-count "2" \
    --virtualbox-memory "2048" \
   	--virtualbox-disk-size "20000" \
    --virtualbox-host-dns-resolver \
    mesos-docker

		#--virtualbox-boot2docker-url "http://lug.mtu.edu/centos/6.7/isos/x86_64/CentOS-6.7-x86_64-minimal.iso" \


.PHONY:
