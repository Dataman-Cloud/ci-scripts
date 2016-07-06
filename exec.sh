#!/bin/bash
set -x
offlineregistry="offlineregistry.dataman-inc.com"

#registry_baseurl="offlineregistry.dataman-inc.com"
registry_baseurl="demoregistry.dataman-inc.com"

#centos7_base="$registry_baseurl/shurenyun/centos7-base:20160325175751"
centos7_base="$registry_baseurl/library/centos7-base:20160614110448"

cluster_base="$registry_baseurl/shurenyun/centos7-omega-cluster-base:20160606172626"
#cluster_base="offlineregistry.dataman-inc.com/centos7/omega-server-base:20160421135431"

#alpine_base="$registry_baseurl/shurenyun/alpine3.2-base"
drone_base="$registry_baseurl/shurenyun/alpine3.2-drone-base:20160408144856"

srystatic_base="$registry_baseurl/shurenyun/centos7-nginx1.8.0-srystatic-base:20160413105254"

web_base="$registry_baseurl/shurenyun/centos7-nginx-1.8.0:omega.v0.2.2"

omegagod_base="$registry_baseurl/shurenyun/centos7-omega-god-base:20160525160709"

configcenter_base="$registry_baseurl/shurenyun/alpine3.3-cfgcenter-base:20160519133515"

export CONFIGSERVER="${CONFIGSERVER:-http://10.3.6.6}"
export FORCEPULLIMAGE="${FORCEPULLIMAGE:-false}"
export MARATHON_API_URL="http://10.3.33.6:8080"
codeci_api_url="http://10.3.6.6:8100"
codepath="/data/sourcecode"


error(){
        error="error."
        if [ "$1" ];then
                error=$1
        fi
        code=1
        if [ "$2" ];then
                code=$2
        fi

        echo $error && exit $code
}


check_committag(){

    [[ "$COMMITIDTAG" == "null" ]] || [[ "${#COMMITIDTAG}" -gt 50 ]] && error "Sync code failed."
    echo "check commit tag ok"
}

check_params(){
    [ "$TASKENV" ] || error "TASKENV is empty."
    [ "$SERVICE" ] || error "SERVICE is empty."
    [ "$DEPLOYIP" ] || error "DEPLOYIP is empty."
    [[ "$COMMITIDTAG" == "null" ]] || [[ "${#COMMITIDTAG}" -gt 50 ]] && error "Sync code failed."

    echo "check_params is ok."
}

get_instancecount(){
    local instancecount=`curl $MARATHON_API_URL/v2/apps/shurenyun-$TASKENV-$SERVICE 2>/dev/null| python -m json.tool | awk -F ":" '/instances/{print $2}' | grep -o '[0-9]*'`
    echo "$instancecount"
}

deploy_marathon_app(){
    # 生成ENV file
    #bash $SERVICE/deploy/ci-scripts/generate_config.sh $TASKENV $SERVICE
    updateENV=`curl $codeci_api_url/generate_config/$TASKENV/$SERVICE`
    [ $updateENV = "error" ] && error "Generate configuration files failed ..."

    wget $CONFIGSERVER/config/$TASKENV/config/cfgfile_"$TASKENV"_"$SERVICE"/env -O $TASKENV-$SERVICE-env
    # source file 自动 export
    set -a
    cat $TASKENV-$SERVICE-env | sed '/^$/d;s/=/="/;s/$/"/' > /tmp/$TASKENV-$SERVICE-env-variables
    . /tmp/$TASKENV-$SERVICE-env-variables && rm -f /tmp/$TASKENV-$SERVICE-env-variables
    set +a

    # 生成最终deploy.sh
    cp -f $SERVICE/deploy/deploy.sh $TASKENV-$SERVICE-deploy-ready.sh
    sed -n '1,/"env"/p' $TASKENV-$SERVICE-deploy-ready.sh > $TASKENV-$SERVICE-deploy-run.sh
    cat $TASKENV-$SERVICE-env | sed '/^$/d;s/^/                    "/;s/=/": "/;s/$/",/' >> $TASKENV-$SERVICE-deploy-run.sh
    echo "" >>  $TASKENV-$SERVICE-deploy-run.sh
    sed -n '/"env"/,$p' $TASKENV-$SERVICE-deploy-ready.sh | grep -v '"env"' >> $TASKENV-$SERVICE-deploy-run.sh

    # deploy marathon app
    curl -v -X DELETE "$MARATHON_API_URL/v2/apps/shurenyun-$TASKENV-$SERVICE"

    count=0
    instancecount="1"
    while [ ! -z "$instancecount" ]
    do
        sleep 1
        instancecount=`get_instancecount`
        let count=count+1
        [ $count -gt 5 ] && error "delete shurenyun-$TASKENV-$SERVICE failed."
	echo
    done

    bash -x $TASKENV-$SERVICE-deploy-run.sh

    count=0
    instancecount=""
    while [ -z "$instancecount" ]
    do
        sleep 1
        instancecount=`get_instancecount`
        let count=count+1
        [ $count -gt 5  ] && error "deploy $TASKENV-$SERVICE-deploy.sh failed."
	echo
    done

    # 清理程序包及生成的文件
    rm -rf $TASKENV-$SERVICE-deploy-ready.sh $TASKENV-$SERVICE-env $TASKENV-$SERVICE-deploy-run.sh $SERVICE $SERVICE.tar.gz
}
put_marathon_app(){
    wget $CONFIGSERVER/config/jenkins/$SERVICE/put.sh -O $TASKENV-$SERVICE-put.sh || error "wget or execute $TASKENV-$SERVICE-put.sh failed."
    bash -x $TASKENV-$SERVICE-put.sh

    count=0
    instancecount=""
    while [ -z "$instancecount" ]
    do
        sleep 1
        instancecount=`get_instancecount`
        let count=count+1
        [ $count -gt 5  ] && error "deploy $TASKENV-$SERVICE-put.sh failed."
	echo
    done
}

upload_version(){
    # upload version
    cd /usr/local/share
    wget $CONFIGSERVER/config/jenkins/upload.py -O $TASKENV-$SERVICE-upload.py && chmod +x $TASKENV-$SERVICE-upload.py || error "File upload.py doesn't exit."
    echo ${COMMITIDTAG} > $TASKENV-$SERVICE
    ./$TASKENV-$SERVICE-upload.py $TASKENV-$SERVICE || error "Execute $TASKENV-$SERVICE-upload.py failed."

    # save the tag to configcenter
    tagresult=`curl $codeci_api_url/updatetag/$TASKENV/$SERVICE/${COMMITIDTAG}`
    if [ "$tagresult" = null ]; then
        error "Update mysql commitidtag failed!"
    else
        echo "The new tag has been saved into mysql."
    fi
}

get_committag(){
        # get COMMITIDTAG
        if [ "$TASKENV" = "demo" ];then
            before_env="dev"
        elif [ "$TASKENV" = "prod" ];then
            before_env="demo"
        fi

        newtag=`curl $codeci_api_url/getfinaltag/$before_env/$SERVICE`
        if [ "$demotag" = null ]; then
            echo "Get $before_env tag failed!" && exit 1
        else
            echo "$before_env tag is *************** $newtag ***************"
        fi

        # is force update
        if [ "x$FORCE" = "xtrue" ] ;then
	    if [ "x$TASKENV" = "xdev" ] ;then
	            export FORCEPULLIMAGE=true
	    fi
	else
                oldtag=`curl $codeci_api_url/getfinaltag/$TASKENV/$SERVICE`
                if [ "$prodtag" = null ]; then
                    error "Get $env tag failed!"
                else
                    echo "$TASKENV tag is *************** $oldtag ***************"
                fi
        fi

        if [ "$newtag" = "$oldtag" ] ; then
            error "Dosen't need to update $TASKENV." 0
        fi

        export COMMITIDTAG=$newtag
}

# 下载registry认证文件
down_verify(){
    curl $CONFIGSERVER/config/demo/config/registry/docker.tar.gz -o - |tar -zxf - -C ~/
}

docker_build(){
	# 下载registry认证文件
	down_verify
    #Dockerfile download
    if [ ! -f $SERVICE/dockerfiles/Dockerfile_runtime ]; then
        error "Dockerfile_runtime not exist."
    fi
    echo "####test####"
    ls `pwd`
    ls `pwd`/$SERVICE
    mv $SERVICE/dockerfiles/Dockerfile_runtime "$SERVICE"_Dockerfile_runtime
    echo "Start to build image of ${SERVICE_IMAGE}......"
    docker build --no-cache --file "$SERVICE"_Dockerfile_runtime -t "${SERVICE_IMAGE}" .

    if [ $? -eq 0 ]; then
        count=0
        while [ $count -lt 3 ]
        do
            docker push "${SERVICE_IMAGE}"
            if [ $? -eq 0 ]; then
                    docker ps | grep "${SERVICE_IMAGE}" 2>/dev/null || docker rmi -f "${SERVICE_IMAGE}"
                    break
            fi

            [ $count -eq 3 ] && error "Push $SERVICE dockerimage failed."
            sleep 1
        done
    else
        error "Build $SERVICE dockerimage failed."
    fi
}

download_code(){
    #jenkins-slave 主机目录挂载
    cd /data/build
	# clean code
	rm -rf $SERVICE.tar.gz
	rm -rf $SERVICE
	# download code
        curl $CONFIGSERVER/sourcecode/$SERVICE/$SERVICE.tar.gz -o $SERVICE.tar.gz 1>/dev/null 2>&1 || error "download code $SERVICE.tar.gz failed."
        tar -zxf $SERVICE.tar.gz
}

generate_image_name(){

	if [ "$SERVICE" = "drone" ];then
		BASEOS=alpine3.2
	fi

	BASEOS="${BASEOS:-centos7}"
	export SERVICE_IMAGE="$registry_baseurl/shurenyun/$BASEOS-$SERVICE:${COMMITIDTAG}"
}

code_compile() {
    if [ -f "$SERVICE/deploy/compile.sh" ]; then
        . $SERVICE/deploy/compile.sh
        docker run --rm -e SERVICE="$SERVICE" -v /tmp/codebuild:/data/build -w="/data/build" $code_compile_image /bin/bash -c "bash -x compile.sh"
        [ $? -eq 0 ] || error "build $SERVICE failed."
        return 0
    fi
    if [ $SERVICE = "webpage" ] || [ $SERVICE = "frontend" ];then
        if [ $SERVICE = "frontend" ];then
            compress_path=/tmp/codebuild/$SERVICE/glance
        else
            compress_path=/tmp/codebuild/$SERVICE
        fi
        docker ps | grep "compress-$SERVICE" 2>&1 > /dev/null && docker rm -f "compress-$SERVICE"
        docker run --name compress-"$SERVICE" -v $compress_path:/usr/src/myapp -w /usr/src/myapp demoregistry.dataman-inc.com/library/node-gulp:v0.1.063000 /bin/bash compress.sh
        docker rm -f compress-"$SERVICE"
        docker rmi -f demoregistry.dataman-inc.com/library/node-gulp:v0.1.063000
    fi
    if [ $? -eq 0 ]; then
        rm -rf $SERVICE/.git $SERVICE/deploy/ci-scripts/.git $SERVICE.tar.gz
        tar -zcvf $SERVICE.tar.gz $SERVICE
    else
        error "compress $SERVICE failed."
    fi
}

deploy(){
    # check params
    check_params

    if [ "$TASKENV" = "dev" ];then
        #docker pull "$BASEIMAGE" 1>/dev/null || error "Pull baseimage failed."
	    # 生成服务镜像名称
	    generate_image_name
	    # 下载服务代码
		# download_code

        code_compile

	    # build image
	    docker_build

    else
	    # get COMMITIDTAG
	    get_committag
	    # 生成镜像名称
	    generate_image_name
	    # test pull image
	    #docker pull "$SERVICE_IMAGE" || error "Pull $SERVICE_IMAGE failed."
	    #docker rmi "$SERVICE_IMAGE"
    fi

        # deploy marathon app
        deploy_marathon_app

        # upload version
        upload_version

}

agent_deploy(){
    if [ "$TASKENV" = "dev" ];then
	# build pageage
        agent_name=omega-agent-${COMMITIDTAG}
        mkdir -p /usr/local/go/src/github.com/Dataman-Cloud/
        cd /usr/local/go/src/github.com/Dataman-Cloud/

        rm -f $SERVICE.tar.gz
        rm -rf $SERVICE
        rm -rf /build

	# download service code
	download_code

        cd $SERVICE
        mkdir -p /build/{bin,ubuntu,redhat}
        contrib/make-bin.sh /build/bin || error "make agent bin failed." 1
        echo 'Building deb'
        contrib/make-deb.sh /build/ubuntu || error "make agent deb failed." 1
        mv /build/ubuntu/omega-agent_1.0_amd64.deb /build/ubuntu/${agent_name}_amd64.deb || error "deb change `ls  /build/ubuntu/`  name error" 1
        echo 'Building rpm'
        contrib/make-rpm.sh /build/redhat || error "make agent rpm failed." 1
        mv /build/redhat/omega-agent-1.0-1.x86_64.rpm /build/redhat/${agent_name}.x86_64.rpm  || error "rpm change `ls /build/redhat`  name error" 1
	# upload package to oss
        rm -f deplpy.py
        wget $CONFIGSERVER/config/jenkins/$SERVICE/deploy.py || error "wget  deploy.py failed." 1
        python deploy.py || error "exec deploy.py failed." 1
        echo
    else
	# get COMMITIDTAG
        get_committag
    fi

    # upload version
    upload_version
}

omegagod_deploy(){
    export FORCEPULLIMAGE=true
    # check committag
    check_committag
    # 生成镜像名称
    generate_image_name
    # download service code
    download_code
    # build image
    docker_build
    # deploy
    deploy_marathon_app
    # upload version
    upload_version
}

web_deploy(){
    export FORCEPULLIMAGE=true
    # check committag
    check_committag
    # 生成镜像名称
    generate_image_name
    # download service code
    download_code
    # build image
    docker_build
    # deploy
    put_marathon_app
    # upload version
    upload_version
}
