#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${CYAN}==================================================${NC}"
echo -e "${CYAN}   ЗАПУСК АВТОМАТИЧЕСКОЙ УСТАНОВКИ (LAMP STACK)   ${NC}"
echo -e "${CYAN}==================================================${NC}"

# 1. Подготовка репозиториев (CentOS Stream 8/9 / AlmaLinux / Rocky)
echo -e "${GREEN}[+] Установка репозиториев EPEL и Remi...${NC}"
dnf install -y epel-release
dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm || dnf install -y https://rpms.remirepo.net/enterprise/remi-release-8.rpm

# 2. Установка пакетов
echo -e "${GREEN}[+] Установка Apache, MariaDB, PHP и PhpMyAdmin...${NC}"
# Сбрасываем модуль php и включаем remi-8.2 для свежей версии
dnf module reset php -y
dnf module enable php:remi-8.2 -y
dnf install -y httpd mariadb-server php php-cli php-mysqlnd php-pdo php-json php-mbstring phpmyadmin wget

# 3. Запуск служб
echo -e "${GREEN}[+] Запуск служб...${NC}"
systemctl enable --now httpd
systemctl enable --now mariadb

# 4. Настройка Базы Данных
echo -e "${GREEN}[+] Создание базы данных и таблиц...${NC}"

# SQL для создания БД и таблицы
SQL_QUERY="
CREATE DATABASE IF NOT EXISTS auth_system;
USE auth_system;
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    login VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    code INT DEFAULT NULL,
    code_created_at DATETIME DEFAULT NULL
);
"
# Выполняем SQL от имени root (по умолчанию пароля нет)
mysql -u root -e "$SQL_QUERY"

# 5. Настройка PhpMyAdmin (открываем доступ извне)
echo -e "${GREEN}[+] Настройка доступа к PhpMyAdmin...${NC}"
PMA_CONF="/etc/httpd/conf.d/phpMyAdmin.conf"
if [ -f "$PMA_CONF" ]; then
    # Заменяем Require local на Require all granted (Осторожно, это открывает доступ всем!)
    sed -i 's/Require local/Require all granted/g' "$PMA_CONF"
    sed -i 's/Allow from 127.0.0.1/Allow from all/g' "$PMA_CONF"
    sed -i 's/Allow from ::1/Allow from all/g' "$PMA_CONF"
fi

# 6. Создание файлов проекта
WEB_DIR="/var/www/html"
echo -e "${GREEN}[+] Генерация PHP файлов в $WEB_DIR...${NC}"

# --- index.php ---
cat << 'EOF' > $WEB_DIR/index.php
<?php
session_start();
try {
    $db = new PDO('mysql:host=localhost;dbname=auth_system;charset=utf8', 'root', '');
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    die("Ошибка БД: " . $e->getMessage());
}

$db->exec("UPDATE users SET code = NULL, code_created_at = NULL WHERE code_created_at < NOW() - INTERVAL 30 SECOND");
$error = null;

if (isset($_POST['action'])) {
    if ($_POST['action'] == 'send_code') {
        $stmt = $db->prepare("SELECT * FROM users WHERE login = ?");
        $stmt->execute([$_POST['login']]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($user && password_verify($_POST['password'], $user['password'])) {
            $code = rand(100000, 999999);
            $upd = $db->prepare("UPDATE users SET code = ?, code_created_at = NOW() WHERE login = ?");
            $upd->execute([$code, $_POST['login']]);
            echo "<script>alert('Ваш код: $code');</script>";
        } else {
            $error = "Неверный логин или пароль";
        }
    } elseif ($_POST['action'] == 'login') {
        $stmt = $db->prepare("SELECT * FROM users WHERE login = ? AND code = ?");
        $stmt->execute([$_POST['login'], $_POST['code']]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($user) {
            $_SESSION['user_id'] = $user['id'];
            header("Location: welcome.php");
            exit;
        } else {
            $error = "Неверный код или он устарел";
        }
    }
}
?>
<!DOCTYPE html>
<html>
<head><title>Авторизация</title><meta charset="utf-8"></head>
<style>body{font-family:sans-serif;padding:50px;text-align:center;} input{padding:10px;margin:5px;} button{padding:10px 20px;cursor:pointer;}</style>
<body>
    <?php if ($error) echo "<p style='color:red'>$error</p>"; ?>
    <form method="POST">
        <h2>Вход в систему</h2>
        <input type="text" name="login" placeholder="Логин" required value="<?php echo $_POST['login'] ?? ''; ?>"><br>
        <input type="password" name="password" placeholder="Пароль" required><br>
        <button type="submit" name="action" value="send_code">Получить код</button>
        <hr>
        <input type="text" name="code" placeholder="Код из SMS/Alert"><br>
        <button type="submit" name="action" value="login">Войти</button>
    </form>
</body>
</html>
EOF

# --- welcome.php ---
cat << 'EOF' > $WEB_DIR/welcome.php
<?php
session_start();
if (!isset($_SESSION['user_id'])) { header("Location: index.php"); exit; }
?>
<!DOCTYPE html>
<html>
<head><title>Главная</title><meta charset="utf-8"></head>
<body>
    <h1>Добро пожаловать! Вы успешно авторизовались.</h1>
    <a href="logout.php">Выйти</a>
</body>
</html>
EOF

# --- logout.php ---
cat << 'EOF' > $WEB_DIR/logout.php
<?php
session_start();
session_destroy();
header("Location: index.php");
exit;
?>
EOF

# --- cu.php (Create User) ---
cat << 'EOF' > $WEB_DIR/cu.php
<?php
try {
    $db = new PDO('mysql:host=localhost;dbname=auth_system;charset=utf8', 'root', '');
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $login = 'test';
    $password = password_hash('test123', PASSWORD_DEFAULT);
    
    // Проверка, есть ли уже такой юзер
    $check = $db->prepare("SELECT id FROM users WHERE login = ?");
    $check->execute([$login]);
    
    if($check->rowCount() == 0) {
        $db->prepare("INSERT INTO users (login, password) VALUES (?, ?)")->execute([$login, $password]);
        echo "Пользователь создан: $login / test123";
    } else {
        echo "Пользователь $login уже существует.";
    }
} catch (Exception $e) {
    echo "Ошибка: " . $e->getMessage();
}
?>
EOF

# 7. Финальные штрихи
echo -e "${GREEN}[+] Настройка прав доступа и создание тестового пользователя...${NC}"

# Выполняем cu.php через CLI, чтобы сразу создать юзера
php $WEB_DIR/cu.php

# Ставим права apache
chown -R apache:apache $WEB_DIR
chmod -R 755 $WEB_DIR

# SELinux часто мешает, ставим в Permissive (для теста)
setenforce 0
sed -i 's/^SELINUX=.*/SELINUX=permissive/g' /etc/selinux/config

# Перезагрузка Apache
systemctl restart httpd

# Получение IP
IP_ADDR=$(hostname -I | awk '{print $1}')

echo -e "${CYAN}==================================================${NC}"
echo -e "${GREEN}   УСТАНОВКА ЗАВЕРШЕНА!   ${NC}"
echo -e "${CYAN}==================================================${NC}"
echo -e "Твой сайт доступен тут:  ${GREEN}http://${IP_ADDR}/${NC}"
echo -e "PhpMyAdmin доступен тут: ${GREEN}http://${IP_ADDR}/phpmyadmin/${NC}"
echo -e "Данные для входа:"
echo -e "   Логин: ${GREEN}test${NC}"
echo -e "   Пароль: ${GREEN}test123${NC}"
echo -e "   MySQL User: ${GREEN}root${NC} (без пароля)"
echo -e "${CYAN}==================================================${NC}"
