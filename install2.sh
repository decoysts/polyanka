#!/bin/bash

# Цвета
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}==================================================${NC}"
echo -e "${CYAN}   УСТАНОВКА ВТОРОГО ПРОЕКТА (Project 2)   ${NC}"
echo -e "${CYAN}==================================================${NC}"

# Папка для нового проекта (подпапка в html)
PROJECT_DIR="/var/www/html/project2"

echo -e "${GREEN}[+] Создание директории $PROJECT_DIR...${NC}"
mkdir -p $PROJECT_DIR

# --- index.php (Исправленный код) ---
echo -e "${GREEN}[+] Генерация index.php (исправлены ошибки синтаксиса)...${NC}"
cat << 'EOF' > $PROJECT_DIR/index.php
<?php
session_start();
// Подключение к ТОЙ ЖЕ базе данных auth_system
try {
    $db = new PDO('mysql:host=localhost;dbname=auth_system;charset=utf8', 'root', '');
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    die("Ошибка подключения к БД: " . $e->getMessage());
}

// Очистка устаревших кодов (старше 30 секунд)
$db->exec("UPDATE users SET code = NULL, code_created_at = NULL WHERE code_created_at < NOW() - INTERVAL 30 SECOND");

$error = null;

if (isset($_POST['action'])) {
    // Логика 1: Проверка пароля и отправка кода
    if ($_POST['action'] == 'send_code') {
        $stmt = $db->prepare("SELECT * FROM users WHERE login = ?");
        $stmt->execute([$_POST['login']]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($user && password_verify($_POST['password'], $user['password'])) {
            $code = rand(100000, 999999);
            // Записываем код в базу
            $upd = $db->prepare("UPDATE users SET code = ?, code_created_at = NOW() WHERE login = ?");
            $upd->execute([$code, $_POST['login']]);
            // Имитация отправки (alert)
            echo "<script>alert('Ваш код подтверждения: $code');</script>";
        } else {
            $error = "Неверный логин или пароль";
        }
    } 
    // Логика 2: Проверка кода
    elseif ($_POST['action'] == 'login') {
        $stmt = $db->prepare("SELECT * FROM users WHERE login = ? AND code = ?");
        $stmt->execute([$_POST['login'], $_POST['code']]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($user) {
            $_SESSION['user_id'] = $user['id'];
            header("Location: welcome.php");
            exit;
        } else {
            $error = "Неверный код или время его действия истекло";
        }
    }
}
?>
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Авторизация Project 2</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css">
    <style>
        .auth-container {
            max-width: 400px; margin: 80px auto;
            padding: 30px; border-radius: 15px;
            box-shadow: 0 10px 25px rgba(0,0,0,0.1);
        }
        .form-icon { font-size: 3rem; color: #0d6efd; margin-bottom: 1rem; }
    </style>
</head>
<body class="bg-light">
<div class="container">
    <div class="auth-container bg-white">
        <div class="text-center mb-4">
            <i class="bi bi-shield-lock form-icon"></i>
            <h2 class="fw-bold">Авторизация</h2>
            <p class="text-muted">Проект №2</p>
        </div>

        <?php if ($error): ?>
        <div class="alert alert-danger alert-dismissible fade show" role="alert">
            <i class="bi bi-exclamation-triangle-fill me-2"></i>
            <?= $error ?>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
        <?php endif; ?>

        <form method="POST">
            <div class="mb-3">
                <label class="form-label">Логин</label>
                <div class="input-group">
                    <span class="input-group-text"><i class="bi bi-person"></i></span>
                    <input type="text" class="form-control" name="login" value="<?= $_POST['login'] ?? '' ?>" placeholder="Введите логин" required>
                </div>
            </div>
            <div class="mb-3">
                <label class="form-label">Пароль</label>
                <div class="input-group">
                    <span class="input-group-text"><i class="bi bi-key"></i></span>
                    <input type="password" class="form-control" name="password" placeholder="Введите пароль">
                </div>
            </div>
            <div class="mb-4">
                <label class="form-label">Код из SMS</label>
                <div class="input-group">
                    <span class="input-group-text"><i class="bi bi-shield-check"></i></span>
                    <input type="text" class="form-control" name="code" placeholder="******">
                </div>
                <div class="form-text">Сначала введите пароль и нажмите "Выслать код"</div>
            </div>

            <div class="d-grid gap-2">
                <button type="submit" class="btn btn-outline-primary" name="action" value="send_code">
                    <i class="bi bi-send me-2"></i>Выслать код
                </button>
                <button type="submit" class="btn btn-primary" name="action" value="login">
                    <i class="bi bi-box-arrow-in-right me-2"></i>Войти
                </button>
            </div>
        </form>
    </div>
</div>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOF

# --- welcome.php (Исправленный код) ---
echo -e "${GREEN}[+] Генерация welcome.php...${NC}"
cat << 'EOF' > $PROJECT_DIR/welcome.php
<?php
session_start();
if (!isset($_SESSION['user_id'])) {
    header("Location: index.php");
    exit;
}
?>
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Личный кабинет</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css">
    <style>
        .welcome-container {
            max-width: 600px; margin: 80px auto;
            padding: 40px; border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.2);
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
            color: white; text-align: center;
        }
        .welcome-icon { font-size: 5rem; margin-bottom: 1.5rem; opacity: 0.9; }
        .btn-logout {
            background: rgba(255,255,255,0.2); border: 1px solid rgba(255,255,255,0.4); color: white;
            padding: 10px 25px; text-decoration: none; border-radius: 5px; transition: 0.3s;
        }
        .btn-logout:hover { background: rgba(255,255,255,0.4); color: #fff; }
        .feature-item {
            background: rgba(255,255,255,0.15); border-radius: 10px;
            padding: 15px; margin: 10px 0;
        }
    </style>
</head>
<body class="bg-light">
<div class="container">
    <div class="welcome-container">
        <div class="mb-4">
            <i class="bi bi-house-check-fill welcome-icon"></i>
            <h1 class="fw-bold mb-3">Добро пожаловать!</h1>
            <p class="lead opacity-75">Вы успешно авторизовались.</p>
        </div>

        <div class="alert alert-light fade show text-dark" role="alert">
            <i class="bi bi-person-circle me-2"></i>
            <strong>ID пользователя:</strong> <?= htmlspecialchars($_SESSION['user_id']) ?>
        </div>

        <h4 class="mb-3 mt-4">Доступные модули:</h4>
        <div class="row">
            <div class="col-6"><div class="feature-item"><i class="bi bi-person-badge me-2"></i>Профиль</div></div>
            <div class="col-6"><div class="feature-item"><i class="bi bi-gear me-2"></i>Настройки</div></div>
            <div class="col-6"><div class="feature-item"><i class="bi bi-clock-history me-2"></i>История</div></div>
            <div class="col-6"><div class="feature-item"><i class="bi bi-shield-check me-2"></i>Защита</div></div>
        </div>

        <div class="mt-5">
            <a href="logout.php" class="btn-logout">
                <i class="bi bi-box-arrow-right me-2"></i>Выйти
            </a>
        </div>
    </div>
</div>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOF

# --- logout.php ---
echo -e "${GREEN}[+] Генерация logout.php...${NC}"
cat << 'EOF' > $PROJECT_DIR/logout.php
<?php
session_start();
session_destroy();
header("Location: index.php");
exit;
?>
EOF

# Настройка прав
echo -e "${GREEN}[+] Настройка прав доступа...${NC}"
chown -R apache:apache $PROJECT_DIR
chmod -R 755 $PROJECT_DIR
# Если SELinux включен, исправляем контекст
if [ "$(getenforce)" != "Disabled" ]; then
    chcon -R -t httpd_sys_content_t $PROJECT_DIR
fi

# Получение IP
IP_ADDR=$(hostname -I | awk '{print $1}')

echo -e "${CYAN}==================================================${NC}"
echo -e "${GREEN}   УСТАНОВКА ЗАВЕРШЕНА!   ${NC}"
echo -e "${CYAN}==================================================${NC}"
echo -e "Новый сайт доступен тут: ${GREEN}http://${IP_ADDR}/project2/${NC}"
echo -e "Старый сайт доступен тут: http://${IP_ADDR}/"
echo -e "${CYAN}==================================================${NC}"
