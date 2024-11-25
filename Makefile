# 参考: https://github.com/oribe1115/traP-isucon-newbie-handson2022/blob/main/Makefile
include env.sh
# 変数定義 ------------------------

# SERVER_ID: env.sh内で定義

# 問題によって変わる変数
USER:=isucon
BIN_NAME:=app
BUILD_DIR:=/home/isucon/private_isu/webapp/golang
SERVICE_NAME:=isu-go.service

DB_PATH:=/etc/mysql
NGINX_PATH:=/etc/nginx
SYSTEMD_PATH:=/etc/systemd/system
TOOL_CONFIG_PATH:=/home/isucon/tool-config

NGINX_LOG:=/var/log/nginx/access.log
DB_SLOW_LOG:=/var/log/mysql/mysql-slow.log

# メインで使うコマンド ------------------------

# サーバーの環境構築　ツールのインストール、gitまわりのセットアップ
.PHONY: setup
setup: install-tools git-setup

# 設定ファイルなどを取得してgit管理下に配置する
.PHONY: get-conf
get-conf: check-server-id get-db-conf get-nginx-conf get-service-file get-envsh

# リポジトリ内の設定ファイルをそれぞれ配置する
.PHONY: deploy-conf
deploy-conf: check-server-id deploy-db-conf deploy-nginx-conf deploy-service-file deploy-envsh

# ベンチマークを走らせる直前に実行する
.PHONY: bench
bench: check-server-id mv-logs build deploy-conf restart watch-service-log pprotein

.PHONY: pprotein
pprotein:
	./pprotein

# slow queryを確認する
.PHONY: slow-query
slow-query:
	sudo pt-query-digest $(DB_SLOW_LOG)

# alpでアクセスログを確認する
.PHONY: alp
alp:
	sudo alp ltsv --file=$(NGINX_LOG) --config=$(TOOL_CONFIG_PATH)/alp/config.yml

# pprofで記録する
.PHONY: pprof-record
pprof-record:
	go tool pprof http://localhost:6060/debug/pprof/profile

# pprofで確認する
.PHONY: pprof-check
pprof-check:
	$(eval latest := $(shell ls -rt pprof/ | tail -n 1))
	go tool pprof -http=localhost:8090 pprof/$(latest)

# DBに接続する
.PHONY: access-db
access-db:
	mysql -h $(MYSQL_HOST) -P $(MYSQL_PORT) -u $(MYSQL_USER) -p$(MYSQL_PASS) $(MYSQL_DBNAME)

# 主要コマンドの構成要素 ------------------------

.PHONY: install-tools
install-tools:
	sudo apt update
	sudo apt upgrade
	sudo apt install -y percona-toolkit dstat htop git unzip snapd graphviz gv tree

    # alpのインストール
	wget https://github.com/tkuchiki/alp/releases/download/v1.0.21/alp_linux_arm64.zip
	unzip alp_linux_arm64.zip
	sudo install alp /usr/local/bin/alp
	rm alp_linux_arm64.zip alp

    # slpのインストール
	wget https://github.com/tkuchiki/slp/releases/download/v0.2.1/slp_linux_arm64.tar.gz
	tar -xvf slp_linux_arm64.tar.gz
	rm slp_linux_arm64.tar.gz
	sudo mv slp /usr/local/bin/slp
    
    # pproteinのインストール
	wget https://github.com/kaz/pprotein/releases/download/v1.2.4/pprotein_1.2.4_linux_arm64.tar.gz
	tar -xvf pprotein_1.2.4_linux_arm64.tar.gz
	rm pprotein_1.2.4_linux_arm64.tar.gz

    # dool (dstatの後継)のインストール
	curl https://cdn.jsdelivr.net/gh/scottchiefbaker/dool@master/dool | sudo tee /usr/local/bin/dool
	sudo chmod +x /usr/local/bin/dool


.PHONY: git-setup
git-setup:
	# git用の設定は適宜変更して良い
	git config --global user.email "isucon@example.com"
	git config --global user.name "isucon"

	# deploykeyの作成
	cd ~/.ssh
	ssh-keygen -t ed25519

.PHONY: tool-config-setup
tool-config-setup:
	sudo mkdir -p $(TOOL_CONFIG_PATH)/alp
	echo "---" | sudo tee $(TOOL_CONFIG_PATH)/alp/config.yml > /dev/null
	echo "sort: sum  # max|min|avg|sum|count|uri|method|max-body|min-body|avg-body|sum-body|p1|p50|p99|stddev" | sudo tee -a $(TOOL_CONFIG_PATH)/alp/config.yml > /dev/null
	echo "reverse: true                   # boolean" | sudo tee -a $(TOOL_CONFIG_PATH)/alp/config.yml > /dev/null
	echo "query_string: true              # boolean" | sudo tee -a $(TOOL_CONFIG_PATH)/alp/config.yml > /dev/null
	echo "output: count,5xx,4xx,3xx,method,uri,min,max,sum,avg,p99                    # string(comma separated" | sudo tee -a $(TOOL_CONFIG_PATH)/alp/config.yml > /dev/null
	echo "" | sudo tee -a $(TOOL_CONFIG_PATH)/alp/config.yml > /dev/null
	echo "# matching_groups:            # array" | sudo tee -a $(TOOL_CONFIG_PATH)/alp/config.yml > /dev/null
	echo "# -" | sudo tee -a $(TOOL_CONFIG_PATH)/alp/config.yml > /dev/null

.PHONY: check-server-id
check-server-id:
ifdef SERVER_ID
	@echo "SERVER_ID=$(SERVER_ID)"
else
	@echo "SERVER_ID is unset"
	@exit 1
endif

.PHONY: set-as-s1
set-as-s1:
	echo "SERVER_ID=s1" >> env.sh

.PHONY: set-as-s2
set-as-s2:
	echo "SERVER_ID=s2" >> env.sh

.PHONY: set-as-s3
set-as-s3:
	echo "SERVER_ID=s3" >> env.sh

.PHONY: get-db-conf
get-db-conf:
	sudo mkdir -p ~/$(SERVER_ID)/etc/mysql
	sudo cp -R $(DB_PATH)/* ~/$(SERVER_ID)/etc/mysql
	sudo chown $(USER) -R ~/$(SERVER_ID)/etc/mysql

.PHONY: get-nginx-conf
get-nginx-conf:
	sudo mkdir -p ~/$(SERVER_ID)/etc/nginx
	sudo cp -R $(NGINX_PATH)/* ~/$(SERVER_ID)/etc/nginx
	sudo chown $(USER) -R ~/$(SERVER_ID)/etc/nginx

.PHONY: get-service-file
get-service-file:
	sudo cp $(SYSTEMD_PATH)/$(SERVICE_NAME) ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)
	sudo chown $(USER) ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)

.PHONY: get-envsh
get-envsh:
	cp ~/env.sh ~/$(SERVER_ID)/home/isucon/env.sh

.PHONY: deploy-db-conf
deploy-db-conf:
	sudo cp -R ~/$(SERVER_ID)/etc/mysql/* $(DB_PATH)

.PHONY: deploy-nginx-conf
deploy-nginx-conf:
	sudo cp -R ~/$(SERVER_ID)/etc/nginx/* $(NGINX_PATH)

.PHONY: deploy-service-file
deploy-service-file:
	sudo cp ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME) $(SYSTEMD_PATH)/$(SERVICE_NAME)

.PHONY: deploy-envsh
deploy-envsh:
	cp ~/$(SERVER_ID)/home/isucon/env.sh ~/env.sh

.PHONY: build
build:
	cd $(BUILD_DIR); \
	git pull
	go build -o $(BIN_NAME)

.PHONY: restart
restart:
	sudo systemctl daemon-reload
	sudo systemctl restart $(SERVICE_NAME)
	sudo systemctl restart mysql
	sudo systemctl restart nginx

.PHONY: mv-logs
mv-logs:
	$(eval when := $(shell date "+%s"))
	mkdir -p ~/logs/$(when)
	sudo test -f $(NGINX_LOG) && \
		sudo mv -f $(NGINX_LOG) ~/logs/nginx/$(when)/ || echo ""
	sudo test -f $(DB_SLOW_LOG) && \
		sudo mv -f $(DB_SLOW_LOG) ~/logs/mysql/$(when)/ || echo ""

.PHONY: watch-service-log
watch-service-log:
	sudo journalctl -u $(SERVICE_NAME) -n10 -f
