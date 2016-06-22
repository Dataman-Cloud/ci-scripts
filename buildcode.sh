#!/bin/bash

set -x
base_dir=$(cd `dirname $0` && pwd)
cd $base_dir
service=$(basename `pwd`)
codepath=/data/sourcecode/$service

cd ${codepath}

if [ -f $service.tar.gz ]; then
    rm -f $service.tar.gz
fi

web(){
        echo "Start to compress user......"
        #clean compress docker env
        docker_name="compress_$service"
        compress_status=`docker ps -a| grep "$docker_name" | wc -l`
        if [ "$compress_status" -ne 0 ];then
                docker rm -f "$docker_name"
                if [ $? -ne 0 ]; then
                        echo "docker rm $compress." && exit 1
                fi
        fi

        # set compress_path
        if [ $service = "webpage" ];then
                compress_path="${codepath}/webpage"
        fi

        if [ $service = "frontend" ];then
                compress_path="${codepath}/frontend/glance"
        fi

        # compress
        docker run -d --name "$docker_name" -v "$compress_path":/usr/src/myapp -w /usr/src/myapp node-gulp:4.0 /bin/bash compress.sh

        if [ $? -ne 0 ]; then
                echo "Compress web error." && exit 1
        fi

        docker_status=`docker ps | grep "$docker_name" | wc -l`

        while [ "$docker_status" -ne 0 ]
        do
                echo "Need to wait for the compress docker stop."
                docker_status=`docker ps | grep $docker_name | wc -l`
                sleep 1
        done
}

if [ $service = "webpage" ] || [ $service = "frontend" ];then
        web
fi
rm -rf $codepath/$service/deploy/ci-scripts
cp -r /data/sourcecode/ci-scripts $codepath/$service/deploy/
cd $codepath && /bin/tar -zcvf $service.tar.gz $service
rm -rf $codepath/$service/deploy/ci-scripts
