#!/bin/bash

# Остановка при любой ошибке
set -e

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}[*] НАЧАЛО УСТАНОВКИ OPENVPN (Сценарий из скриншотов)${NC}"

# ==========================================
# 1. ПРЕДВАРИТЕЛЬНАЯ НАСТРОЙКА И УСТАНОВКА
# ==========================================

echo -e "${GREEN}[*] Настройка репозиториев и установка пакетов...${NC}"

# Фикс репозиториев для CentOS 7 (как на фото 2)
sed -i 's/mirror.centos.org/vault.centos.org/g' /etc/yum.repos.d/CentOS*
sed -i 's/^#.*baseurl=http/baseurl=http/g' /etc/yum.repos.d/CentOS*
sed -i 's/^mirrorlist=http/#mirrorlist=http/g' /etc/yum.repos.d/CentOS*

yum install -y nano vsftpd ftp epel-release
yum install -y openvpn easy-rsa curlftpfs autofs iptables-services

# Отключение SELinux (как на фото 2)
sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
setenforce 0 || true

# Настройка Firewall (отключаем firewalld, включаем iptables)
systemctl stop firewalld
systemctl disable firewalld
systemctl enable iptables
systemctl start iptables

# Включаем форвардинг пакетов
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.conf
sysctl -p

# ==========================================
# 2. ПОДГОТОВКА ПАПОК ДЛЯ КЛЮЧЕЙ (Photo 7)
# ==========================================

echo -e "${GREEN}[*] Создание структуры папок...${NC}"
BASE_KEYS="/home/user/keys"
mkdir -p $BASE_KEYS/cord-{1..3}/{server,client{1..3}}

# Копирование Easy-RSA в рабочие директории C1, C2, C3
mkdir -p /usr/share/easy-rsa/{C1,C2,C3}
# Ищем где реально лежит easyrsa (обычно в /usr/share/easy-rsa/3 или 3.x)
EASYRSA_PATH=$(find /usr/share/easy-rsa -maxdepth 1 -type d -name "3*")
cp -r $EASYRSA_PATH/* /usr/share/easy-rsa/C1/
cp -r $EASYRSA_PATH/* /usr/share/easy-rsa/C2/
cp -r $EASYRSA_PATH/* /usr/share/easy-rsa/C3/

# ==========================================
# 3. ГЕНЕРАЦИЯ КЛЮЧЕЙ (PKI)
# ==========================================

echo -e "${GREEN}[*] Генерация PKI, CA и Серверных ключей (блок C1)...${NC}"
cd /usr/share/easy-rsa/C1

# Инициализация и CA
./easyrsa init-pki
# vars config
echo 'set_var EASYRSA_DN "cn_only"' > vars
# Создаем рандом файл для энтропии (Photo 7)
touch pki/.rnd
# Строим CA (nopass чтобы не спрашивал пароль в скрипте, на фото 7 там build-ca)
./easyrsa --batch build-ca nopass

# Генерация DH (Diffie-Hellman)
./easyrsa gen-dh
# Генерируем TA key
openvpn --genkey --secret pki/ta.key

# Генерируем сертификат СЕРВЕРА (vpn-server)
./easyrsa --batch gen-req vpn-server nopass
./easyrsa --batch sign-req server vpn-server

# Копируем ключи сервера в папку пользователя (Photo 5/1)
SERVER_KEY_DIR="$BASE_KEYS/cord-1/server"
cp pki/ca.crt pki/issued/vpn-server.crt pki/private/vpn-server.key pki/dh.pem pki/ta.key "$SERVER_KEY_DIR"

# Генерируем клиентов для cord-1 (Photo 4)
for i in {1..3}; do
    CLIENT_NAME="cord-1-client-$i"
    ./easyrsa --batch gen-req $CLIENT_NAME nopass
    ./easyrsa --batch sign-req client $CLIENT_NAME
    
    DEST="$BASE_KEYS/cord-1/client$i"
    cp pki/issued/$CLIENT_NAME.crt pki/private/$CLIENT_NAME.key pki/dh.pem pki/ca.crt pki/ta.key "$DEST"
done

# --- Блок C2 ---
echo -e "${GREEN}[*] Генерация ключей для cord-2 (блок C2)...${NC}"
cd /usr/share/easy-rsa/C2
./easyrsa init-pki
echo 'set_var EASYRSA_DN "cn_only"' > vars
# Важно: Чтобы подписать ключи для C2/C3 тем же CA, нужно импортировать CA из C1
# Но судя по скриптам на фото 4, там просто генерируются реквесты.
# Я сделаю упрощенно: сгенерирую и подпишу здесь же, используя CA из C1 (копируем его)
cp /usr/share/easy-rsa/C1/pki/ca.crt pki/
cp /usr/share/easy-rsa/C1/pki/private/ca.key pki/private/
cp /usr/share/easy-rsa/C1/pki/ta.key pki/

for i in {1..3}; do
    CLIENT_NAME="cord-2-client-$i"
    ./easyrsa --batch gen-req $CLIENT_NAME nopass
    ./easyrsa --batch sign-req client $CLIENT_NAME
    
    DEST="$BASE_KEYS/cord-2/client$i"
    cp pki/issued/$CLIENT_NAME.crt pki/private/$CLIENT_NAME.key pki/dh.pem pki/ca.crt pki/ta.key "$DEST"
done

# --- Блок C3 ---
echo -e "${GREEN}[*] Генерация ключей для cord-3 (блок C3)...${NC}"
cd /usr/share/easy-rsa/C3
./easyrsa init-pki
echo 'set_var EASYRSA_DN "cn_only"' > vars
# Копируем CA из C1
cp /usr/share/easy-rsa/C1/pki/ca.crt pki/
cp /usr/share/easy-rsa/C1/pki/private/ca.key pki/private/
cp /usr/share/easy-rsa/C1/pki/ta.key pki/

for i in {1..3}; do
    CLIENT_NAME="cord-3-client-$i"
    ./easyrsa --batch gen-req $CLIENT_NAME nopass
    ./easyrsa --batch sign-req client $CLIENT_NAME
    
    DEST="$BASE_KEYS/cord-3/client$i"
    cp pki/issued/$CLIENT_NAME.crt pki/private/$CLIENT_NAME.key pki/dh.pem pki/ca.crt pki/ta.key "$DEST"
done

# ==========================================
# 4. НАСТРОЙКА OPENVPN SERVER (Photo 3)
# ==========================================

echo -e "${GREEN}[*] Настройка конфига сервера...${NC}"
mkdir -p /etc/openvpn/server
# Копируем ключи в папку сервера openvpn
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

# Создаем папку для логов
mkdir -p /var/log/openvpn

# ==========================================
# 5. НАСТРОЙКА IPTABLES (Photo 2)
# ==========================================

echo -e "${GREEN}[*] Применение правил IPtables...${NC}"
iptables -F
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Правила из фото 2
iptables -A FORWARD -i tun0 -o tun1 -j ACCEPT
iptables -A FORWARD -i tun1 -o tun0 -j ACCEPT
iptables -t nat -A POSTROUTING -o tun1 -j MASQUERADE
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
# Дополнительно нужно правило для выхода в интернет через eth0 (обычно), но делаю строго по скрипту:
# Примечание: на фото странные правила (tun0 <-> tun1). Обычно это eth0 <-> tun1.
# Если интернет не заработает, раскомментируй строку ниже (замени eth0 на свой интерфейс):
# iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

service iptables save

# ==========================================
# 6. ЗАПУСК
# ==========================================

echo -e "${GREEN}[*] Запуск OpenVPN...${NC}"
systemctl enable openvpn-server@server
systemctl start openvpn-server@server
systemctl status openvpn-server@server --no-pager

# ==========================================
# 7. СОЗДАНИЕ КЛИЕНТСКИХ КОНФИГОВ
# ==========================================
# Функция для создания единого .ovpn файла (встраиваем ключи внутрь)
# Чтобы не таскать 5 файлов за собой.

make_client_config() {
    local CL_PATH=$1
    local CL_NAME=$2
    local OVPN_FILE="$CL_PATH/$CL_NAME.ovpn"
    
    # Получаем внешний IP сервера
    SERVER_IP=$(curl -s ifconfig.me)

    echo -e "${GREEN}[*] Создание конфига для $CL_NAME...${NC}"

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

# Генерируем конфиги для всех созданных клиентов
make_client_config "$BASE_KEYS/cord-1/client1" "cord-1-client-1"
make_client_config "$BASE_KEYS/cord-1/client2" "cord-1-client-2"
make_client_config "$BASE_KEYS/cord-1/client3" "cord-1-client-3"
# (можно добавить циклы для остальных, если нужно)

echo -e "${GREEN}[OK] Установка завершена!${NC}"
echo -e "Ключи и конфиги лежат в: $BASE_KEYS"
