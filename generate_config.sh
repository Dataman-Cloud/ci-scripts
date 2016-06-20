#!/bin/bash
set -x

param_env=$1
param_service=$2
CONFIGSERVER="${CONFIGSERVER:-http://10.3.6.6}"

echo "Start to update gitlab of $param_env $param_service ..."
configresult=`curl -X GET "http://10.3.6.6:8900/config/newest?env=${param_env}&service=${param_service}"`
if [ $? -eq 0 ]; then
    configtag=`echo $configresult | awk -F \" '{print $6}'`
    if [ x$configtag = "x" ]; then
        echo "update config error!" && exit 1
    fi
    echo " ++++++++++++"
    	echo "this is configtag: $configtag"
    echo " ++++++++++++"
else
    echo "Update config failed." && exit 1
fi

echo "Start to sync git repo of configserver..."
switchconfigtag=`curl "http://10.3.6.6:8900/checkout/${param_env}/${param_service}/${configtag}" | awk -F \" '{print $2}'`
if [ "$switchconfigtag" != "ok" ]; then
    echo " ++++++++++++"
    	echo " $switchconfigtag "
    echo " ++++++++++++"
    echo "switch config tag failed!" && exit 1
else
    echo "switch config tg OK!"
fi
