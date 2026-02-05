#!/bin/bash

# =================================================================
# Скрипт автоматической настройки Ansible и создания плейбуков
# (HTTPD, MariaDB, WordPress, Samba)
# =================================================================

echo "Начало настройки системы..."

# --- 1. СИСТЕМНАЯ НАСТРОЙКА ---
# Фикс репозиториев для CentOS 7 (переход на Vault)
sed -i 's/mirror.centos.org/vault.centos.org/g' /etc/yum.repos.d/CentOS*
sed -i 's/^#.*baseurl=http/baseurl=http/g' /etc/yum.repos.d/CentOS*
sed -i 's/^mirrorlist=http/#mirrorlist=http/g' /etc/yum.repos.d/CentOS*

# Логирование (из твоего исходника)
curl http://192.168.4.2:800/log_ip.php || echo "Лог-сервер недоступен, продолжаем..."

# --- 2. УСТАНОВКА ANSIBLE ---
echo "Установка Ansible и зависимостей..."
yum install -y nano wget epel-release
yum install -y ansible

# --- 3. НАСТРОЙКА ИНВЕНТАРЯ (hosts) ---
# Укажи здесь свои реальные IP адреса
SERVER1_IP="192.168.4.1"
SERVER2_IP="192.168.4.2"
SERVER3_IP="192.168.4.3"

cat <<EOF > /etc/ansible/hosts
[one]
$SERVER1_IP

[otherServer]
$SERVER2_IP

[three]
$SERVER3_IP
EOF

# --- 4. ПЛЕЙБУК 1: Базовая конфигурация (HTTPD + MariaDB) ---
cat <<EOF > /etc/ansible/myFirstAnsibleConfiguration.yml
---
- name: First config
  hosts: otherServer
  become: yes
  tasks:
    - name: Install httpd package
      yum:
        name: httpd
        state: present

    - name: Start httpd service
      systemd:
        name: httpd
        state: started
        enabled: yes

    - name: Add service http to firewalld
      firewalld:
        service: http
        permanent: yes
        immediate: yes
        state: enabled

    - name: Install mariadb service
      yum:
        name: mariadb-server
        state: present

    - name: Start MariaDB service
      systemd:
        name: mariadb
        state: started
        enabled: yes

    - name: Set MySQL root password
      command: mysql -u root -e "SET PASSWORD = PASSWORD('password3204')"
      ignore_errors: yes

    - name: Create database
      command: mysql -u root -ppassword3204 -e "CREATE DATABASE testingdb"
      ignore_errors: yes

    - name: Add mariadb service to firewalld
      firewalld:
        service: mysql
        permanent: yes
        immediate: yes
        state: enabled

    - name: Create shared folder
      file:
        path: /share
        state: directory
        mode: '0777'

    - name: Copy files to share directory
      copy:
        src: /1/
        dest: /share/
        remote_src: yes
      ignore_errors: yes
EOF

# --- 5. ПЛЕЙБУК 2: Установка WordPress ---
cat <<EOF > /etc/ansible/wp.yml
---
- name: WEB (WordPress)
  hosts: three
  become: yes
  vars:
    wp_install_dir: "/var/www/html/"
    wp_download_url: "https://ru.wordpress.org/wordpress-4.5.33-ru_RU.tar.gz"

  tasks:
    - name: Install repo
      yum:
        name: epel-release
        state: present

    - name: Install necessary packages
      yum:
        name:
          - mariadb
          - mariadb-server
          - httpd
          - wget
          - php
          - php-mysql
          - php-gd
          - php-mbstring
          - php-xml
        state: present

    - name: Start and enable services
      systemd:
        name: "{{ item }}"
        state: started
        enabled: yes
      loop:
        - httpd
        - mariadb

    - name: MySQL set password
      command: mysql -u root -e "set password = password('password3204')"
      ignore_errors: yes

    - name: Create database for WP
      command: mysql -u root -ppassword3204 -e "CREATE DATABASE Wp"
      ignore_errors: yes

    - name: Create directory for WP
      file:
        path: "{{ wp_install_dir }}"
        state: directory
        owner: apache
        group: apache
        mode: '0777'

    - name: Download WordPress
      get_url:
        url: "{{ wp_download_url }}"
        dest: /tmp/wordpress.tar.gz

    - name: Unpack WP
      unarchive:
        src: /tmp/wordpress.tar.gz
        dest: /tmp
        remote_src: yes

    - name: Copy files and set permissions
      shell: |
        cp -rf /tmp/wordpress/* {{ wp_install_dir }}
        chown -R apache:apache {{ wp_install_dir }}
        chmod -R 777 {{ wp_install_dir }}

    - name: Accept http in firewalld
      firewalld:
        service: http
        permanent: yes
        state: enabled
        immediate: yes

    - name: Restart services
      systemd:
        name: "{{ item }}"
        state: restarted
      loop:
        - httpd
        - mariadb

    - name: Set full permissions for web root
      file:
        path: /var/www/html
        state: directory
        mode: '0777'
        recurse: yes
EOF

# --- 6. ПЛЕЙБУК 3: Настройка Samba ---
cat <<EOF > /etc/ansible/samba.yml
---
- name: Настройка Samba-сервера на CentOS 7
  hosts: one
  become: yes
  vars:
    samba_user: user
    samba_password: "1"
    share_directory: /share

  tasks:
    - name: Установка пакетов Samba
      yum:
        name:
          - nano
          - samba
        state: present

    - name: Настройка конфига /etc/samba/smb.conf
      blockinfile:
        path: /etc/samba/smb.conf
        block: |
          [share]
          comment = share
          path = {{ share_directory }}
          browseable = yes
          read only = yes
          guest ok = yes
          create mask = 0777
          directory mask = 0777

    - name: Отключение SELinux (временно)
      command: setenforce 0
      ignore_errors: yes

    - name: Отключение SELinux (постоянно)
      selinux:
        state: disabled

    - name: Создание директории шары
      file:
        path: "{{ share_directory }}"
        state: directory
        mode: '0777'

    - name: Установка пароля Samba
      shell: echo -e "{{ samba_password }}\n{{ samba_password }}" | smbpasswd -a -s {{ samba_user }}

    - name: Активация пользователя Samba
      command: smbpasswd -e "{{ samba_user }}"

    - name: Запуск и включение служб Samba
      systemd:
        name: "{{ item }}"
        state: restarted
        enabled: yes
      loop:
        - smb
        - nmb

    - name: Настройка firewall для Samba
      firewalld:
        service: samba
        zone: public
        permanent: yes
        immediate: yes
        state: enabled
EOF

echo "-------------------------------------------------------"
echo "Готово! Все файлы созданы в /etc/ansible/"
echo "Для запуска используй: ansible-playbook /etc/ansible/имя_файла.yml"
