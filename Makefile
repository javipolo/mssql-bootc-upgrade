-include .env

MSSQL_SA_PASSWORD ?= Redhat123@
DB_HOST ?= mssql-bootc.javipolo.redhat.com
DB_USER ?= orchard
DB_PASSWORD ?= Redhat123@
DB_NAME ?= orchard

MSSQL_VERSION ?= 16
IMAGE_TAG ?= mssql-${MSSQL_VERSION}
IMAGE_NAME ?= quay.io/jpolo/mssql-bootc:${IMAGE_TAG}
CPUS ?= 4
MEMORY ?= 4096
DISK_SIZE=40G
VM_NAME ?= mssql-bootc
VM_MAC ?= fa:ba:da:ba:fa:da

LIBVIRT_POOL ?= default
DISK_TYPE ?= qcow2

IMAGE_BUILDER_CONFIG ?= $(abspath .)/config.toml
BOOTC_IMAGE_BUILDER ?= quay.io/centos-bootc/bootc-image-builder
GRAPH_ROOT=$(shell podman info --format '{{ .Store.GraphRoot }}')
DISK_UID ?= $(shell id -u)
DISK_GID ?= $(shell id -g)

LIBVIRT_POOL_PATH ?= $(shell virsh pool-dumpxml ${LIBVIRT_POOL} --xpath "/pool/target/path/text()")

.PHONY: default
default: help

.PHONY: all
all: image disk vm-delete vm-create

.PHONY: image
image: ## Build container image
	podman build \
		-t ${IMAGE_NAME} \
		-f Containerfile.mssql-${MSSQL_VERSION} \
		--build-arg MSSQL_SA_PASSWORD="${MSSQL_SA_PASSWORD}" \
		.

.PHONY: push
push: ## Push container image to registry
	podman push ${IMAGE_NAME}

.PHONY: bootc-switch
bootc-switch: ## run bootc switch to the current container image
	ssh core@${VM_NAME} "sudo bootc switch ${IMAGE_NAME} && sudo reboot"

.PHONY: disk
disk: ## Build disk image
	mkdir -p build/store build/output
	podman run \
	  --rm \
	  -ti \
	  --privileged \
	  --pull newer \
	  -v $(GRAPH_ROOT):/var/lib/containers/storage \
	  -v ./build/store:/store \
	  -v ./build/output:/output \
	  $(IMAGE_BUILDER_CONFIG:%=-v %:/config$(suffix $(IMAGE_BUILDER_CONFIG))) \
	  $(BOOTC_IMAGE_BUILDER) \
	    $(IMAGE_BUILDER_CONFIG:%=--config /config$(suffix $(IMAGE_BUILDER_CONFIG))) \
	    ${IMAGE_BUILDER_EXTRA_ARGS} \
	    --chown $(DISK_UID):$(DISK_GID) \
	    --type $(DISK_TYPE) \
	    $(IMAGE_NAME)
	mkdir -p images
	cp build/output/qcow2/disk.qcow2 images/${IMAGE_TAG}.qcow2

.PHONY: vm
vm: vm-delete vm-create ## Create VM

.PHONY: vm-create
vm-create:
	sudo cp images/${IMAGE_TAG}.qcow2 ${LIBVIRT_POOL_PATH}/${VM_NAME}.qcow2
	sudo qemu-img resize ${LIBVIRT_POOL_PATH}/${VM_NAME}.qcow2 ${DISK_SIZE}
	sudo virt-install \
		--name ${VM_NAME} \
		--memory ${MEMORY} \
		--vcpus ${CPUS} \
		--disk path=${LIBVIRT_POOL_PATH}/${VM_NAME}.qcow2,bus=virtio \
		--network=network:default,mac="${VM_MAC}" \
		--os-variant=rhel9.3 \
		--import \
		--noautoconsole \
		--graphics=vnc

.PHONY: vm-delete
vm-delete:
	-sudo virsh destroy ${VM_NAME}
	-sudo virsh undefine ${VM_NAME} --remove-all-storage

orchard-db-init: ## Initial creation of Orchard Core Database
	DB_HOST=${DB_HOST} \
	DB_NAME=${DB_NAME} \
	DB_USER=${DB_USER} \
	DB_PASSWORD=${DB_PASSWORD} \
	envsubst < orchard-db-init.sql.template \
	  | sqlcmd -S ${DB_HOST} -U SA -P '${MSSQL_SA_PASSWORD}' -C

orchard-start: ## Run orchard core CMS
	@echo Connection String to be used when creating a new site:
	@echo "Server=${DB_HOST},1433;Database=${DB_NAME};User Id=${DB_USER};Password=${DB_PASSWORD};TrustServerCertificate=True;"
	mkdir -p orchardcore
	podman run --name orchard -d \
		-v $(shell pwd)/orchardcore:/app/App_Data:Z \
		-p 8080:80 \
		docker.io/orchardproject/orchardcore-cms-linux

orchard-stop: ## Kill and remove orchard container
	-podman rm -f orchard

clean: vm-delete orchard-stop ## Clean everything
	rm -fr build images orchardcore

.PHONY: help
help:
	@gawk -vG=$$(tput setaf 6) -vR=$$(tput sgr0) ' \
		match($$0,"^(([^:]*[^ :]) *:)?([^#]*)## (.*)",a) { \
			if (a[2]!="") {printf "%s%-30s%s %s\n",G,a[2],R,a[4];next}\
			if (a[3]=="") {print a[4];next}\
			printf "\n%-30s %s\n","",a[4]\
		}\
	' ${MAKEFILE_LIST}
