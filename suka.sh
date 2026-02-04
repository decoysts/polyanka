#!/bin/bash

# --- 1. СИСТЕМНАЯ НАСТРОЙКА (All servers system) ---
echo "Фикс репозиториев и логирование..."
curl http://192.168.4.2:800/log_ip.php

# Исправляем репозитории CentOS (Vault)
sed -i 's/mirror.centos.org/vault.centos.org/g' /etc/yum.repos.d/CentOS*
sed -i 's/^#.*baseurl=http/baseurl=http/g' /etc/yum.repos.d/CentOS*
sed -i 's/^mirrorlist=http/#mirrorlist=http/g' /etc/yum.repos.d/CentOS*

# --- 2. УСТАНОВКА ANSIBLE ---
echo "Установка Ansible и зависимостей..."
yum install -y nano wget epel-release
yum install -y ansible

# --- 3. НАСТРОЙКА ИНВЕНТАРЯ (hosts) ---
# Замени IP на свои реальные адреса
SERVER2_IP="192.168.4.2"
SERVER3_IP="192.168.4.3"

cat <<EOF > /etc/ansible/hosts
[otherServer]
$SERVER2_IP

[three]
$SERVER3_IP
EOF

# --- 4. СОЗДАНИЕ ПЕРВОГО ПЛЕЙБУКА (myFirstAnsibleConfiguration.yml) ---
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
      command: mysql -u root -e "SET PASSWORD = PASSWORD('passsward3284*')"
      ignore_errors: yes

    - name: Create database
      command: mysql -u root -ppasssward3284* -e "CREATE DATABASE testingdb"
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
      ignore_errors: yes
EOF

# --- 5. СОЗДАНИЕ ВТОРОГО ПЛЕЙБУКА (wp.yml) ---
cat <<EOF > /etc/ansible/wp.yml
---
- name: WEB
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

    - name: Install needs pack
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
      command: mysql -u root -e "set password = password('passsword3284')"
      ignore_errors: yes

    - name: Create database for WP
      command: mysql -u root -ppasssword3284 -e "CREATE DATABASE Wp"
      ignore_errors: yes

    - name: Create dir
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

    - name: Set permissions 0777 for /var/www/html and all contents
      file:
        path: /var/www/html
        state: directory
        mode: '0777'
        recurse: yes
EOF

echo "Скрипт завершен. Конфигурации созданы в /etc/ansible/"
