#!/bin/bash


# 获取 编译代码环境的镜像(比如go环境，python环境)
code_compile_image=`tail -n 1 $SERVICE/dockerfiles/Dockerfile_compile_env`
code_compile_image=${code_compile_image#*#}
# 生成 compile.sh
cat > /data/build/compile.sh << EOF
#!/bin/bash
if [ "$SERVICE" = "harbor" ];then
	mkdir -p /usr/local/go/src/github.com/vmware
	rm -rf /usr/local/go/src/github.com/vmware/$SERVICE
	cp -r $SERVICE /usr/local/go/src/github.com/vmware/
	cd /usr/local/go/src/github.com/vmware/$SERVICE
	go build
    cp $SERVICE /data/build/$SERVICE/

elif echo "$SERVICE" | grep "metrics" &>/dev/null ;then
    #!/bin/bash
	mkdir -p /usr/local/go/src/github.com/Dataman-Cloud
	rm -rf /usr/local/go/src/github.com/Dataman-Cloud/$SERVICE
	cp -r $SERVICE /usr/local/go/src/github.com/Dataman-Cloud/
	cp -r $SERVICE/vendor/*  /usr/local/go/src/
	cd /usr/local/go/src/github.com/Dataman-Cloud/$SERVICE
	go build .
    cp $SERVICE /data/build/$SERVICE/

elif [ "$SERVICE" = "drone" ];then
    #!/bin/bash
    mkdir -p /usr/local/go/src/github.com/$SERVICE
	rm -rf /usr/local/go/src/github.com/$SERVICE/$SERVICE
    cp -r $SERVICE /usr/local/go/src/github.com/$SERVICE/
    cd /usr/local/go/src/github.com/$SERVICE/$SERVICE
	/usr/bin/make gen && /usr/bin/make build_static
    cp "$SERVICE"_static /data/build/$SERVICE/

else
    #!/bin/bash
	mkdir -p /usr/local/go/src/github.com/Dataman-Cloud
	rm -rf /usr/local/go/src/github.com/Dataman-Cloud/$SERVICE
    cp -r $SERVICE /usr/local/go/src/github.com/Dataman-Cloud/
    cd /usr/local/go/src/github.com/Dataman-Cloud/$SERVICE
	make build
    ls -l $SERVICE
    cp $SERVICE /data/build/$SERVICE/
    ls /data/build/$SERVICE/
    ls -l /data/build/$SERVICE/$SERVICE
fi
EOF

chmod +x /data/build/compile.sh
cat /data/build/compile.sh
ls -F /data/build
