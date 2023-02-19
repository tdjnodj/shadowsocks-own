#!/bin/bash

# 字体相关
red() {
	echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
	echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
	echo -e "\033[33m\033[01m$1\033[0m"
}

[[ $EUID -ne 0 ]] && red "请在root用户下运行脚本" && exit 1

CMD=(
	"$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)"
	"$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)"
	"$(lsb_release -sd 2>/dev/null)"
	"$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)"
	"$(grep . /etc/redhat-release 2>/dev/null)"
	"$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')"
)

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove")

for i in "${CMD[@]}"; do
	SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
	[[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "不支持当前VPS系统，请使用主流的操作系统" && exit 1
[[ -z $(type -P curl) ]] && ${PACKAGE_UPDATE[int]} && ${PACKAGE_INSTALL[int]} curl

install() {
    echo ""
    yellow " 请选择 shadowsocks 实现: "
    green " 1. rust(默认)"
    yellow " 2.go"
    red " 3. libev (更新缓慢，不推荐)"
    echo ""
    read -p "请选择: " answer
    case $answer in
        1) lang=rust ;;
        2) lang=go ;;
        3) lang=libev ;;
        *) lang=rust ;; 
    esac
    yellow "当前选择: $lang"
    echo ""
    read -p "请输入 shadowsocks 监听端口: " port
    [[ -z "${port}" ]] && port=$(shuf -i200-65000 -n1)
    if [[ "${port:0:1}" == "0" ]]; then
        red "端口不能以0开头"
        exit 1
    fi
    echo ""

    yellow "请选择加密方式: "
    echo ""
    yellow "重要提醒: shadowsocks-2022 可能比 shadowsocks-AEAD 更容易被封锁，请在使用插件使使用！"
    yellow "密码长度要求为 \"恰好\" 多长"
    echo ""
    red " 1. 2022-blake3-chacha20-poly1305 (需要 32 位长度的密码)"
    red " 2. 2022-blake3-chacha8-poly1305 (需要 16 位长度的密码)"
    red " 3. 2022-blake3-aes-256-gcm (需要 32 位长度密码) (推荐)"
    red " 4. 2022-blake3-aes-128-gcm (需要 16 位长度密码)"
    green " 5. chacha20-poly1305 (默认)"
    green " 6. aes-256-gcm (推荐)"
    green " 7. aes-128-gcm"
    yellow "8. none (不加密！)"
    echo ""
    read -p "请选择: " answer
    case $answer in
        1) method="2022-blake3-chacha20-poly1305" && keyLength=32 && ss2022=1 ;;
        2) method="2022-blake3-chacha8-poly1305" && keyLength=16  && ss2022=1 ;;
        3) method="2022-blake3-aes-256-gcm" && keyLength=32  && ss2022=1 ;;
        4) method="2022-blake3-aes-128-gcm" && keyLength=16  && ss2022=1 ;;
        5) method="chacha20-poly1305" && keyLength=16 ;;
        6) method="aes-2560gcm" && keyLength=16 ;;
        7) method="aes-128-gcm" && keyLength=16 ;;
        8) method="none" && keyLength=8 ;;
        8) method="chacha20-poly1305" && keyLength=16 ;;
    esac
    yellow "当前加密方式: $method"
    echo ""

    read -p "请输入 shadowsocks 密码: " password
    if [ "$ss2022" == "1" ]; then
        if [ "${#password}" != "$keyLength" ]; then
            red "密码长度不符合要求！"
            password=$(openssl rand -base64 ${keyLength})
        fi
    fi    if [[ "$plugin" == "v2Ray-plugin" ]]; then
        tls="false"
        echo ""
        yellow "传输模式: "
        yellow "1. http模式(默认)"
        yellow "2. websocket(ws)"
        yellow "3. QUIC(强制开启TLS)"
        green "4. gRPC(xray-plugin)"
        red "注: 想用TLS请自备证书！"
        echo ""
        read -p "清选择: " answer
        case $answer in
            1) transport=http ;;
            2) transport=ws ;;
            3) transport=quic && tls="true" ;;
            4) transport=gRPC ;;
            *) transport=http ;;
        esac
        echo ""
        if [[ "$transport" == "ws" ]]; then
            read -p "是否开启TLS?(Y/n)" answer
            if [[ "$answer" == "n" ]]; then
                tls="false"
                echo ""
                read -p "请输入ws host(可用来免流，默认 a.189.cn): " domain
                [[ -z "$domain" ]] && domain="a.189.cn"
                yellow "当前ws host: $domain"
            else
                tls="true"
            fi
            echo ""
            read -p "请输入ws路径(以/开头，不懂直接回车): " wspath
            while true; do
                if [[ -z "${wspath}" ]]; then
                    tmp=$(openssl rand -hex 6)
                    wspath="/$tmp"
                    break
                elif [[ "${wspath:0:1}" != "/" ]]; then
                    red "伪装路径必须以/开头！"
                else
                    break
                fi
            done
            yellow "当前ws路径: $wspath"
        fi
        if [[ "$transport" == "gRPC" ]]; then
            read -p "是否开启TLS(Y/n)?" answer
            if [[ "$answer" == "n" ]]; then
               tls="false"
               read -p "请输入您的域名(默认: a.189.cn): " domain
               [[ -z "$domain" ]] && domain="a.189.cn"
            else
               tls="true"
            fi
        fi
        yellow "TLS开启情况: $tls"
        echo ""
        if [[ "$tls" == "true" ]]; then
            read -p "请输入证书路径(请不要以"~"开头！): " cert
            yellow "当前证书：$cert"
            read -p "请输入密钥路径(请不要以"~"开头！): " key
            yellow "当前密钥: $key"
            read -p "请输入你的域名: " domain
            yellow "当前域名: $domain"
        fi

        if [[ "$transport" == "http" ]]; then
            plugin_opts=""
            semicolon=""
        elif [[ "$transport" == "ws" ]]; then
            semicolon=";"
            if [[ "$tls" == "true" ]]; then
                plugin_opts="tls;host=${domain};cert=/etc/shadowsocks-rust/cert.crt;key=/etc/shadowsocks-rust/key.key;path=${wspath}"
            elif [[ "$tls" == "false" ]]; then
                plugin_opts="host=${domain};path=${wspath}"
            fi
        elif [[ "$transport" == "quic" ]]; then
            semicolon=";"
            plugin_opts="mode=quic;host=${domain};cert=/etc/shadowsocks-rust/cert.crt;key=/etc/shadowsocks-rust/key.key"
        elif [[ "$transport" == "gRPC" ]]; then
            semicolon=";"
            if [[ "$tls" == "true" ]]; then
                plugin_opts="mode=grpc;tls;host=${domain};cert=/etc/shadowsocks-rust/cert.crt;key=/etc/shadowsocks-rust/key.key"
            elif [[ "$tls" == "false" ]]; then
                plugin_opts="mode=grpc;host=${domain}"
            fi
        fi
    fi

    if [[ "$plugin" == "qtun" ]]; then
        read -p "请输入证书路径(完整，不要包含"~"): " cert
        yellow "当前证书: $cert"
        read -p "请输入私钥路径(完整，不要包含"~"): " key
        yellow "当前私钥: $key" 
        read -p "请输入您的域名(默认: a.189.cn): " domain
        yellow "当前域名: $domain"
        sleep 1
    fi
    [[ -z "$password" ]] && password=$(openssl rand -base64 ${keyLength})
    yellow "当前密码: $password"

    yellow "插件选择: "
    yellow "0. 无插件(默认)"
    yellow "1. *Ray-lpugin"
    yellow "2. qtun"
    read -p "清选择: " choose_plugin
    case $choose_plugin in
        1) plugin="v2Ray-plugin" ;;
        2) plugin="qtun" ;;
        *) plugin="none" ;;
    esac
    yellow "当前选择: $plugin"

    if [[ "$plugin" == "v2Ray-plugin" ]]; then
        tls="false"
        echo ""
        yellow "传输模式: "
        yellow "1. http模式(默认)"
        yellow "2. websocket(ws)"
        yellow "3. QUIC(强制开启TLS)"
        green "4. gRPC(xray-plugin)"
        red "注: 想用TLS请自备证书！"
        echo ""
        read -p "清选择: " answer
        case $answer in
            1) transport=http ;;
            2) transport=ws ;;
            3) transport=quic && tls="true" ;;
            4) transport=gRPC ;;
            *) transport=http ;;
        esac
        echo ""
        if [[ "$transport" == "ws" ]]; then
            read -p "是否开启TLS?(Y/n)" answer
            if [[ "$answer" == "n" ]]; then
                tls="false"
                echo ""
                read -p "请输入ws host(可用来免流，默认 a.189.cn): " domain
                [[ -z "$domain" ]] && domain="a.189.cn"
                yellow "当前ws host: $domain"
            else
                tls="true"
            fi
            echo ""
            read -p "请输入ws路径(以/开头，不懂直接回车): " wspath
            while true; do
                if [[ -z "${wspath}" ]]; then
                    tmp=$(openssl rand -hex 6)
                    wspath="/$tmp"
                    break
                elif [[ "${wspath:0:1}" != "/" ]]; then
                    red "伪装路径必须以/开头！"
                else
                    break
                fi
            done
            yellow "当前ws路径: $wspath"
        fi
        if [[ "$transport" == "gRPC" ]]; then
            read -p "是否开启TLS(Y/n)?" answer
            if [[ "$answer" == "n" ]]; then
               tls="false"
               read -p "请输入您的域名(默认: a.189.cn): " domain
               [[ -z "$domain" ]] && domain="a.189.cn"
            else
               tls="true"
            fi
        fi
        yellow "TLS开启情况: $tls"
        echo ""
        if [[ "$tls" == "true" ]]; then
            read -p "请输入证书路径(请不要以"~"开头！): " cert
            yellow "当前证书：$cert"
            read -p "请输入密钥路径(请不要以"~"开头！): " key
            yellow "当前密钥: $key"
            read -p "请输入你的域名: " domain
            yellow "当前域名: $domain"
        fi

        if [[ "$transport" == "http" ]]; then
            plugin_opts=""
            semicolon=""
        elif [[ "$transport" == "ws" ]]; then
            semicolon=";"
            if [[ "$tls" == "true" ]]; then
                plugin_opts="tls;host=${domain};cert=/etc/shadowsocks-rust/cert.crt;key=/etc/shadowsocks-rust/key.key;path=${wspath}"
            elif [[ "$tls" == "false" ]]; then
                plugin_opts="host=${domain};path=${wspath}"
            fi
        elif [[ "$transport" == "quic" ]]; then
            semicolon=";"
            plugin_opts="mode=quic;host=${domain};cert=/etc/shadowsocks-rust/cert.crt;key=/etc/shadowsocks-rust/key.key"
        elif [[ "$transport" == "gRPC" ]]; then
            semicolon=";"
            if [[ "$tls" == "true" ]]; then
                plugin_opts="mode=grpc;tls;host=${domain};cert=/etc/shadowsocks-rust/cert.crt;key=/etc/shadowsocks-rust/key.key"
            elif [[ "$tls" == "false" ]]; then
                plugin_opts="mode=grpc;host=${domain}"
            fi
        fi
    fi

    if [[ "$plugin" == "qtun" ]]; then
        read -p "请输入证书路径(完整，不要包含"~"): " cert
        yellow "当前证书: $cert"
        read -p "请输入私钥路径(完整，不要包含"~"): " key
        yellow "当前私钥: $key" 
        read -p "请输入您的域名(默认: a.189.cn): " domain
        yellow "当前域名: $domain"
        sleep 1
    fi

    if [ "$lang" == "rust" ]; then
        install-rust
    fi
}

install-rust() {
    #CPU
    bit=`uname -m`
    if [ "$bit" == "x86_64" ]; then
        cpu=x86_64
    elif [ "$bit" == "aarch64" ]; then
        cpu=aarch64
    elif [ "$bit" == "arm" ]; then
        cpu=aarch64
    elif [ "$bit" == "arm64" ]; then
        cpu=aarch64
    else
        cpu=x86_64
        red "VPS的CPU架构为$bit，可能安装失败!"
    fi

    ss_version=$(curl https://api.github.com/repos/shadowsocks/shadowsocks-rust/tags -k | grep 'name' | cut -d\" -f4 | head -1)
    if [ -z "${ss_version}" ]; then
        red "未检测到 shadowsocks-rust 版本，请手动输入: "
        yellow "格式：v1.15.2"
    fi
    yellow "当前 shadowsocks-rust 版本: ${ss_version}"

    mkdir /etc/shadowsocks-rust
    cd /usr/local/bin/
    curl -O -L -k https://github.com/shadowsocks/shadowsocks-rust/releases/download/${ss_version}/shadowsocks-${ss_version}.${cpu}-unknown-linux-gnu.tar.xz
    tar xvf shadowsocks-${ss_version}.${cpu}-unknown-linux-gnu.tar.xz
    rm shadowsocks-*.tar.xz

	cat >/etc/systemd/system/shadowsocks.service <<-EOF
[Unit]
Description=Shadowsocks-Rust Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks/config.json

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

menu() {
    clear
    yellow " shadowsocks-own   拥有自己的 shadowsocks 服务器！"
    echo ""
    yellow " 1. 安装 shadowsocks"
    echo ""
    read -p "请选择: " answer
    case $answer in
        1) install ;;
        *) exit 0 ;;
    esac
}

action=$1
[[ -z "$1" ]] && action=menu
case $action in
    menu) menu ;;
    *) red "请输入正确的选项！" && exit 1 ;;
esac