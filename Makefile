SHELL=/bin/bash

export DATAPREP_VERSION := $(shell cat Makefile projects/deces-dataprep/recipes/deces_dataprep.yml projects/deces-dataprep/datasets/deces_index.yml  | sha1sum | awk '{print $1}' | cut -c-8)
export APP=deces-dataprep
export APP_GROUP=matchID
export PWD := $(shell pwd)
export APP_PATH=${PWD}
export GIT = $(shell which git)
export GITROOT = https://github.com/matchid-project
export GIT_BRANCH = master
export GIT_BACKEND = backend
export GIT_TOOLS = tools
export MAKEBIN = $(shell which make)
export MAKE = ${MAKEBIN} --no-print-directory -s
export ES_INDEX=deces
export ES_NODES=1
export ES_MEM=1024m
export ES_VERSION = 8.6.1
export ERR_MAX=20
export ES_PRELOAD=[]
export CHUNK_SIZE=10000
export RECIPE = deces_dataprep
export RECIPE_THREADS = 4
export RECIPE_QUEUE = 1
export ES_THREADS = 2
export TIMEOUT = 2520
export SSHID=matchid@matchid.project.gmail.com
export SSHKEY_PRIVATE = ${HOME}/.ssh/id_rsa_${APP}
export SSHKEY = ${SSHKEY_PRIVATE}.pub
export SSHKEYNAME = ${APP}
export OS_TIMEOUT = 60
export SCW_SERVER_FILE_ID=scw.id
SCW_TIMEOUT= 180
EC2_PROFILE=default
EC2=ec2 ${EC2_ENDPOINT_OPTION} --profile ${EC2_PROFILE}
EC2_SERVER_FILE_ID=${PWD}/ec2.id
EC2_TIMEOUT= 120
CLOUD=SCW
SSHOPTS=-o "StrictHostKeyChecking no" -i ${SSHKEY} ${CLOUD_SSHOPTS}
RCLONE_OPTS=--s3-acl=public-read
export SCW_FLAVOR=PRO2-M
export SCW_VOLUME_TYPE=b_ssd
export SCW_VOLUME_SIZE=50000000000
export SCW_IMAGE_ID=52497223-01c6-4e80-a7e0-020eefdfb127

dummy               := $(shell touch artifacts)
include ./artifacts

config: ${GIT_BACKEND}
	@echo checking system prerequisites
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND} config && \
	echo "prerequisites installed" > config

${GIT_BACKEND}:
	@echo configuring matchID
	@${GIT} clone -q ${GITROOT}/${GIT_BACKEND}
	@cp artifacts ${GIT_BACKEND}/artifacts
	@cp docker-compose-local.yml ${GIT_BACKEND}/docker-compose-local.yml
	@echo "export ES_NODES=${ES_NODES}" >> ${GIT_BACKEND}/artifacts
	@echo "export PROJECTS=${PWD}/projects" >> ${GIT_BACKEND}/artifacts
	@echo "export STORAGE_BUCKET=${STORAGE_BUCKET}" >> ${GIT_BACKEND}/artifacts
	@sed -i -E "s/export API_SECRET_KEY:=(.*)/export API_SECRET_KEY:=1234/"  backend/Makefile
	@sed -i -E "s/export ADMIN_PASSWORD:=(.*)/export ADMIN_PASSWORD:=1234ABC/"  backend/Makefile
	@sed -i -E "s/id(.*):=(.*)/id:=myid/"  backend/Makefile

dev: config
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND} backend frontend &&\
		echo matchID started, go to http://localhost:8081

dev-dev: config
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND} backend-dev frontend-dev &&\
		echo matchID started, go to http://localhost:8081

dev-stop:
	@if [ -f config ]; then\
		${MAKE} -C ${APP_PATH}/${GIT_BACKEND} frontend-stop backend-stop;\
	fi

dev-dev-stop:
	@if [ -f config ]; then\
		${MAKE} -C ${APP_PATH}/${GIT_BACKEND} frontend-dev-stop backend-dev-stop;\
	fi

up:
	@unset APP;unset APP_VERSION;\
	${MAKE} -C ${APP_PATH}/${GIT_BACKEND} backend && echo matchID backend services started

recipe-run: data-tag
	@if [ ! -f recipe-run ];then\
		${MAKE} -C ${APP_PATH}/${GIT_BACKEND} elasticsearch ES_NODES=${ES_NODES} ES_MEM=${ES_MEM} ${MAKEOVERRIDES};\
		echo running recipe on data FILES_TO_PROCESS="${FILES_TO_PROCESS}" $$(cat ${DATA_TAG}), dataprep ${DATAPREP_VERSION};\
		${MAKE} -C ${APP_PATH}/${GIT_BACKEND} version;\
		${MAKE} -C ${APP_PATH}/${GIT_BACKEND} recipe-run \
			CHUNK_SIZE=${CHUNK_SIZE} RECIPE=${RECIPE} RECIPE_THREADS=${RECIPE_THREADS} RECIPE_QUEUE=${RECIPE_QUEUE} \
			ES_PRELOAD='${ES_PRELOAD}' ES_THREADS=${ES_THREADS} \
			STORAGE_BUCKET=${STORAGE_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
			${MAKEOVERRIDES} \
			APP=backend APP_VERSION=$(shell cd ${APP_PATH}/${GIT_BACKEND} && make version | awk '{print $$NF}') \
			&&\
		touch recipe-run s3-pull &&\
		(echo esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG}).tar > elasticsearch-restore);\
	fi

backend-clean-logs:
	rm -f ${PWD}/${GIT_BACKEND}/log/*${RECIPE}*log

watch-run:
	@LOG_FILE=$(shell find ${GIT_BACKEND}/log/ -iname '*${RECIPE}*' | sort | tail -1);\
	timeout=${TIMEOUT} ; ret=1 ; \
		until [ "$$timeout" -le 0 -o "$$ret" -eq "0"  ] ; do \
			((tail $$LOG_FILE | grep "end of all" > /dev/null) || exit 1) ; \
			ret=$$? ; \
			if [ "$$ret" -ne "0" ] ; then \
				grep inserted $$LOG_FILE |awk 'BEGIN{s=0}{t=$$4;s+=$$14}END{printf("\rwrote %d in %s",s,t)}' ;\
				grep -i Ooops $$LOG_FILE | wc -l | awk '($$1>${ERR_MAX}){exit 1}' || exit 0;\
				sleep 10 ;\
			fi ; ((timeout--)); done ;
	@LOG_FILE=$(shell find ${GIT_BACKEND}/log/ -iname '*${RECIPE}*' | sort | tail -1);\
	((egrep -i 'end : run|Ooops' $$LOG_FILE | tail -5) && exit 1) || \
	egrep 'end : run.*successfully' $$LOG_FILE

down:
	@if [ -f config ]; then\
		(${MAKE} -C ${APP_PATH}/${GIT_BACKEND} backend-stop frontend-stop || true);\
	fi

clean: down
	@sudo rm -rf ${GIT_BACKEND} frontend ${DATA_DIR} data-tag config \
		recipe-run backup-check datagouv-to-* check-* elasticsearch-restore watch-run full\
		backup backup-pull backup-push repository-push repository-config repository-check no-remote

