#!/bin/bash

# 配置变量
MAVEN_HOME="/home/apache-maven-3.8.6"
BUILD_DIR="$(pwd)/cd-metro-api" # 编译路径
WORK_DIR="/home/app/product/cd-metro" # 项目工作目录
CONF_DIR="$WORK_DIR/conf" # 项目工作目录
GIT_REPO="http://192.168.0.110:3000/Vault/cd-metro.git" # Gitea 仓库地址
BACKUP_DIR="/home/app/product/cd-metro/backups" # 备份目录
JAR_NAME="cd-metro-api.jar" # 生成的 JAR 包名称
SERVICE_NAME="cd-metro-api" # systemd 服务名称

profile=$0

echo "profile:$profile"


mkdir -p $WORK_DIR
mkdir -p $CONF_DIR
echo "工作目录:$WORK_DIR"
echo "配置文件目录:$CONF_DIR"

echo "当前路径:$(pwd)"
echo "当前路径文件列表:$(ls)"

# 配置进程开机自启动
if [ ! -e "/etc/systemd/system/cd-metro-api.service" ]; then
    echo "未找到cd-metro-api.service。"
    cp cd-metro-api.service /etc/systemd/system/cd-metro-api.service
    systemctl enable cd-metro-api.service
else
  cp -f cd-metro-api.service /etc/systemd/system/cd-metro-api.service
  systemctl daemon-reload
fi

cd $MAVEN_HOME || {
  echo "开始下载maven！";
  wget https://mirrors.huaweicloud.com/apache/maven/maven-3/3.8.6/binaries/apache-maven-3.8.6-bin.tar.gz -O /home/apache-maven-3.8.6-bin.tar.gz
  cd /home
  tar -xzf apache-maven-3.8.6-bin.tar.gz
  # 创建软连接
  ln -s /home/apache-maven-3.8.6 /home/apache-maven
  rm -f apache-maven-3.8.6-bin.tar.gz
}

mvn -v
# 检查mvn命令是否可以执行
if [ $? -ne 0 ]; then
  if [ ! -e "/etc/profile.d/maven.sh" ]; then
    echo "未找到maven.sh。"
    # 添加环境变量
    echo 'export MAVEN_HOME=/home/apache-maven' | sudo tee -a /etc/profile.d/maven.sh
    echo 'export PATH=$MAVEN_HOME/bin:$PATH' | sudo tee -a /etc/profile.d/maven.sh
  fi
  # 使配置生效
  source /etc/profile.d/maven.sh
  echo $(mvn -v)
fi

echo "编译路径:$BUILD_DIR"
cd $BUILD_DIR
#强制覆盖
cp -f src/main/resources/LycatCfg.xml $CONF_DIR/LycatCfg.xml
cp -f src/main/resources/logback-prod.xml $CONF_DIR/logback-prod.xml
cp -f src/main/resources/application.yaml $CONF_DIR/application.yaml
cp -f src/main/resources/application-prod.yaml $CONF_DIR/application-prod.yaml
# Maven 构建项目
echo "开始构建项目..."


if [[ "$profile" == "test" ]]; then
    echo "profile = test"
    mvn clean package sonar:sonar -s ../settings.xml -DskipTests
else
    echo "profile = $profile"
    mvn clean package -s ../settings.xml -DskipTests
fi

# mvn clean verify sonar:sonar -Dsonar.skip=true

# 检查构建是否成功
if [ $? -ne 0 ]; then
  echo "构建失败！"
  exit 1
fi

if [[ "$profile" == "test" ]]; then
    # 备份旧的 JAR 包
    echo "备份旧的 JAR 包..."
    mkdir -p $BACKUP_DIR
    if [ -f "$BUILD_DIR/target/$JAR_NAME" ]; then
      BACKUP_FILE="$BACKUP_DIR/$SERVICE_NAME-$(date +%Y%m%d%H%M%S).jar"
      cp "$BUILD_DIR/target/$JAR_NAME" "$BACKUP_FILE"
      echo "已备份 JAR 包到 $BACKUP_FILE"
    fi
fi

# 移动 JAR 包到工作目录
echo "移动 JAR 包..."
mv "$BUILD_DIR/target/$JAR_NAME" "$WORK_DIR/"

# 重启 Spring Boot 服务
echo "重启 Spring Boot 服务..."
sudo systemctl restart $SERVICE_NAME

# 检查服务状态
echo "检查服务状态..."
sudo systemctl status $SERVICE_NAME

ipv4=$(hostname -I | awk '{print $1}')

echo "http://$ipv4:10086/cd-metro/apiv4/swagger-ui/index.html"
echo "http://$ipv4/cd-metro/apiv4/swagger-ui/index.html"
echo "sonar: http://192.168.0.110:9001"
