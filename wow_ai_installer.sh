#!/bin/bash
set -e

# ======================
# 强制指定工作目录
# ======================
WORK_DIR="/root/wow"
mkdir -p $WORK_DIR
cd $WORK_DIR

# ====================== 系统更新与依赖安装 ======================
echo "[1/8] 正在更新系统并安装依赖..." 
sudo apt update && sudo apt upgrade -y && sudo apt install -y git cmake make gcc g++ clang libmysqlclient-dev libssl-dev libbz2-dev libreadline-dev libncurses-dev mysql-server libboost-all-dev ufw curl unzip sudo

# ====================== 防火墙配置（开放所有端口） ======================
echo "[2/8] 正在配置防火墙..." 
sudo ufw disable 2>/dev/null || true # 忽略未安装ufw的情况 
sudo ufw --force reset 
sudo ufw default allow incoming # 允许所有入站 
sudo ufw default allow outgoing # 允许所有出站
sudo ufw --force enable 
echo "当前防火墙规则：" 
sudo ufw status

# ====================== 源码编译与安装 ======================
echo "[3/8] 正在部署核心服务..." 
mkdir -p $WORK_DIR/ai_wow && cd $WORK_DIR/ai_wow
git clone https://github.com/mod-playerbots/azerothcore-wotlk.git --branch=Playerbot

# 添加AI模块
cd azerothcore-wotlk/modules 
git clone https://github.com/mod-playerbots/mod-playerbots.git --branch=master

# 编译安装
cd $WORK_DIR/ai_wow/azerothcore-wotlk
mkdir build && cd build 
cmake ../ -DCMAKE_INSTALL_PREFIX=$WORK_DIR/ai_server/ -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DWITH_WARNINGS=1 -DTOOLS_BUILD=all -DSCRIPTS=static -DMODULES=static
  
echo "[4/8] 正在编译源码（约15-30分钟）..." 
make -j 2 
make install

# ====================== 客户端数据部署 ======================
echo "[5/8] 正在下载游戏数据..." 
mkdir -p $WORK_DIR/ai_server/data
wget -O $WORK_DIR/ai_server/data/data.zip https://github.com/wowgaming/client-data/releases/download/v16/data.zip
unzip $WORK_DIR/ai_server/data/data.zip -d $WORK_DIR/ai_server/data/
rm $WORK_DIR/ai_server/data/data.zip

# ====================== 配置文件修改 ======================
echo "[6/8] 正在配置服务..." 
cp $WORK_DIR/ai_server/etc/worldserver.conf.dist $WORK_DIR/ai_server/etc/worldserver.conf
cp $WORK_DIR/ai_server/etc/authserver.conf.dist $WORK_DIR/ai_server/etc/authserver.conf

# 批量修改配置
sed -i "s|^DataDir.*|DataDir = \"$WORK_DIR/ai_server/data\"|" $WORK_DIR/ai_server/etc/worldserver.conf
sed -i 's/^AiPlayerbot.RandomBotAutologin\s*=\s*1/AiPlayerbot.RandomBotAutologin = 0/' $WORK_DIR/ai_server/etc/modules/playerbots.conf.dist
sudo sed -i '/^bind-address/s/127.0.0.1/0.0.0.0/; /^mysqlx-bind-address/s/127.0.0.1/0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf


# ====================== 数据库初始化 ======================
echo "[7/8] 正在初始化数据库..." 
sudo mysql <<EOF
DROP USER IF EXISTS 'acore'@'%';
CREATE USER 'acore'@'%' IDENTIFIED BY 'acore' WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0;
GRANT ALL PRIVILEGES ON *.* TO 'acore'@'%' WITH GRANT OPTION;

DROP DATABASE IF EXISTS \`acore_world\`;
CREATE DATABASE \`acore_world\` DEFAULT CHARACTER SET UTF8MB4 COLLATE utf8mb4_general_ci;

DROP DATABASE IF EXISTS \`acore_characters\`;
CREATE DATABASE \`acore_characters\` DEFAULT CHARACTER SET UTF8MB4 COLLATE utf8mb4_general_ci;

DROP DATABASE IF EXISTS \`acore_auth\`;
CREATE DATABASE \`acore_auth\` DEFAULT CHARACTER SET UTF8MB4 COLLATE utf8mb4_general_ci;

GRANT ALL PRIVILEGES ON \`acore_world\`.* TO 'acore'@'%' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON \`acore_characters\`.* TO 'acore'@'%' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON \`acore_auth\`.* TO 'acore'@'%' WITH GRANT OPTION;
EOF

# ====================== 服务启动与验证 ======================
echo "[8/8] 正在启动服务..." 
sudo systemctl restart mysql 
echo "=========================" 
echo "安装完成！"
