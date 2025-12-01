#!/bin/bash

# Остановка при любой ошибке
set -e

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}[*] НАЧАЛО УСТАНОВКИ OPENVPN (FIXED VERSION)${NC}"

# ==========================================
# 0. ОЧИСТКА ПЕРЕД ЗАПУСКОМ (ЧТОБЫ НЕ БЫЛО КОНФЛИКТОВ)
# ==========================================
echo -e "${GREEN}[*] Очистка предыдущих установок...${NC}"
rm -rf /usr/share/easy-rsa/C1
rm -rf /usr/share/easy-rsa/C2
rm -rf /usr/share/easy-rsa/C3
rm -rf /etc/openvpn/server/*

# ==========================================
# 1. ПРЕДВАРИТЕЛЬНАЯ НАСТРОЙКА И УСТАНОВКА
# ==========================================

echo -e "${GREEN}[*] Настройка репозиториев и установка пакетов...${NC}"

# Фикс репозиториев CentOS 7
sed -i 's/mirror.centos.org/vault.centos.org/g' /etc/yum.repos.d/CentOS*
sed -i 's/^#.*baseurl=http/baseurl=http/g' /etc/yum.repos.d/CentOS*
sed -i 's/^mirrorlist=http/#mirrorlist=http/g' /etc/yum.repos.d/CentOS*

# Установка софта
yum install -y nano vsftpd ftp epel-release
yum install -y openvpn easy-rsa curlftpfs autofs iptables-services

# Отключение SELinux
sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
setenforce 0 || true

# Настройка Firewall
systemctl stop firewalld
systemctl disable firewalld
systemctl enable iptables
systemctl start iptables

# Включаем форвардинг
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.conf
sysctl -p

# ==========================================
# 2. ПОДГОТОВКА ПАПОК ДЛЯ КЛЮЧЕЙ
# ==========================================

echo -e "${GREEN}[*] Создание структуры папок...${NC}"
BASE_KEYS="/home/user/keys"
# Очищаем старые ключи если были
rm -rf $BASE_KEYS
mkdir -p $BASE_KEYS/cord-{1..3}/{server,client{1..3}}

# Копирование Easy-RSA
mkdir -p /usr/share/easy-rsa/{C1,C2,C3}
EASYRSA_PATH=$(find /usr/share/easy-rsa -maxdepth 1 -type d -name "3*")
cp -r $EASYRSA_PATH/* /usr/share/easy-rsa/C1/
cp -r $EASYRSA_PATH/* /usr/share/easy-rsa/C2/
cp -r $EASYRSA_PATH/* /usr/share/easy-rsa/C3/

# ==========================================
# 3. ГЕНЕРАЦИЯ КЛЮЧЕЙ (PKI) - БЛОК C1
# ==========================================

echo -e "${GREEN}[*] Генерация C1 (CA + Server + Clients)...${NC}"
cd /usr/share/easy-rsa/C1

./easyrsa init-pki
echo 'set_var EASYRSA_DN "cn_only"' > vars
touch pki/.rnd
# Создаем CA
./easyrsa --batch build-ca nopass

# Генерируем DH и TA
./easyrsa gen-dh
openvpn --genkey --secret pki/ta.key

# Сертификат СЕРВЕРА
./easyrsa --batch gen-req vpn-server nopass
./easyrsa --batch sign-req server vpn-server

# Копируем ключи сервера
SERVER_KEY_DIR="$BASE_KEYS/cord-1/server"
cp pki/ca.crt pki/issued/vpn-server.crt pki/private/vpn-server.key pki/dh.pem pki/ta.key "$SERVER_KEY_DIR"

# Клиенты для cord-1
for i in {1..3}; do
    CLIENT_NAME="cord-1-client-$i"
    ./easyrsa --batch gen-req $CLIENT_NAME nopass
    ./easyrsa --batch sign-req client $CLIENT_NAME
    
    DEST="$BASE_KEYS/cord-1/client$i"
    cp pki/issued/$CLIENT_NAME.crt pki/private/$CLIENT_NAME.key pki/dh.pem pki/ca.crt pki/ta.key "$DEST"
done

# ==========================================
# 4. ГЕНЕРАЦИЯ КЛЮЧЕЙ - БЛОК C2 (ИСПРАВЛЕНО)
# ==========================================

echo -e "${GREEN}[*] Генерация C2...${NC}"
cd /usr/share/easy-rsa/C2
./easyrsa init-pki
echo 'set_var EASYRSA_DN "cn_only"' > vars

# ВАЖНОЕ ИСПРАВЛЕНИЕ: Создаем собственный CA для C2
./easyrsa --batch build-ca nopass

# Генерируем TA key для этой группы тоже (на всякий случай, если нужен отдельный)
openvpn --genkey --secret pki/ta.key
# DH берем общий или генерим (быстрее взять из C1, но по правилам лучше сгенерить)
cp /usr/share/easy-rsa/C1/pki/dh.pem pki/

for i in {1..3}; do
    CLIENT_NAME="cord-2-client-$i"
    ./easyrsa --batch gen-req $CLIENT_NAME nopass
    ./easyrsa --batch sign-req client $CLIENT_NAME
    
    DEST="$BASE_KEYS/cord-2/client$i"
    cp pki/issued/$CLIENT_NAME.crt pki/private/$CLIENT_NAME.key pki/dh.pem pki/ca.crt pki/ta.key "$DEST"
done

# ==========================================
# 5. ГЕНЕРАЦИЯ КЛЮЧЕЙ - БЛОК C3 (ИСПРАВЛЕНО)
# ==========================================

echo -e "${GREEN}[*] Генерация C3...${NC}"
cd /usr/share/easy-rsa/C3
./easyrsa init-pki
echo 'set_var EASYRSA_DN "cn_only"' > vars

# ВАЖНОЕ ИСПРАВЛЕНИЕ: Создаем собственный CA для C3
./easyrsa --batch build-ca nopass

openvpn --genkey --secret pki/ta.key
cp /usr/share/easy-rsa/C1/pki/dh.pem pki/

for i in {1..3}; do
    CLIENT_NAME="cord-3-client-$i"
    ./easyrsa --batch gen-req $CLIENT_NAME nopass
    ./easyrsa --batch sign-req client $CLIENT_NAME
    
    DEST="$BASE_KEYS/cord-3/client$i"
    cp pki/issued/$CLIENT_NAME.crt pki/private/$CLIENT_NAME.key pki/dh.pem pki/ca.crt pki/ta.key "$DEST"
done

# ==========================================
# 6. НАСТРОЙКА OPENVPN SERVER
# ==========================================

echo -e "${GREEN}[*] Настройка конфига сервера...${NC}"
mkdir -p /etc/openvpn/server
# Берем ключи из cord-1 (как основного сервера)
cp $SERVER_KEY_DIR/* /etc/openvpn/server/

cat <<EOF > /etc/openvpn/server/server.conf
port 1193
proto udp
dev tun1
ca ca.crt
cert vpn-server.crt
key vpn-server.key
dh dh.pem
tls-auth ta.key 0
server 28.0.10.0 255.255.255.0
push "route 27.0.10.0 255.255.255.0"
push "dhcp-option DNS 77.88.8.8"
ifconfig-pool-persist ipp.txt
keepalive 10 120
max-clients 15
client-to-client
persist-key
persist-tun
status /var/log/openvpn/openvpn-status.log
log-append /var/log/openvpn/openvpn.log
verb 0
mute 20
daemon
mode server
tls-server
cipher AES-256-CBC
push "explicit-exit-notify 3"
EOF

mkdir -p /var/log/openvpn

# ==========================================
# 7. НАСТРОЙКА IPTABLES
# ==========================================

echo -e "${GREEN}[*] Применение правил IPtables...${NC}"
iptables -F
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

iptables -A FORWARD -i tun0 -o tun1 -j ACCEPT
iptables -A FORWARD -i tun1 -o tun0 -j ACCEPT
iptables -t nat -A POSTROUTING -o tun1 -j MASQUERADE
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

service iptables save

# ==========================================
# 8. ЗАПУСК И СБОРКА КОНФИГОВ
# ==========================================

echo -e "${GREEN}[*] Запуск OpenVPN...${NC}"
systemctl enable openvpn-server@server
systemctl restart openvpn-server@server

# Функция сборки конфига
make_client_config() {
    local CL_PATH=$1
    local CL_NAME=$2
    local OVPN_FILE="$CL_PATH/$CL_NAME.ovpn"
    SERVER_IP=$(curl -s ifconfig.me)

    echo -e "${GREEN}[*] Сборка .ovpn для $CL_NAME...${NC}"

    cat <<EOF > $OVPN_FILE
client
resolv-retry infinite
nobind
remote $SERVER_IP 1193
proto udp
dev tun
tls-client
float
keepalive 10 120
persist-key
persist-tun
verb 0
cipher AES-256-CBC
route 10.0.10.0 255.255.255.0 11.0.0.6

<ca>
$(cat $CL_PATH/ca.crt)
</ca>
<cert>
$(cat $CL_PATH/$CL_NAME.crt)
</cert>
<key>
$(cat $CL_PATH/$CL_NAME.key)
</key>
<tls-auth>
$(cat $CL_PATH/ta.key)
</tls-auth>
key-direction 1
EOF
}

# Генерация .ovpn для всех созданных папок
make_client_config "$BASE_KEYS/cord-1/client1" "cord-1-client-1"
make_client_config "$BASE_KEYS/cord-1/client2" "cord-1-client-2"
make_client_config "$BASE_KEYS/cord-1/client3" "cord-1-client-3"

make_client_config "$BASE_KEYS/cord-2/client1" "cord-2-client-1"
make_client_config "$BASE_KEYS/cord-2/client2" "cord-2-client-2"
make_client_config "$BASE_KEYS/cord-2/client3" "cord-2-client-3"

make_client_config "$BASE_KEYS/cord-3/client1" "cord-3-client-1"
make_client_config "$BASE_KEYS/cord-3/client2" "cord-3-client-2"
make_client_config "$BASE_KEYS/cord-3/client3" "cord-3-client-3"

echo -e "${GREEN}[OK] Все готово!${NC}"
