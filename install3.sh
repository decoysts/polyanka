#!/bin/bash

# Настройки цветов
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Предполагаем, что PROJECT_DIR уже задан, иначе текущая
if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="/var/www/html/project2/"
fi
# 1. SQL скрипт для конвертации существующих таблиц в UTF8MB4
cat << 'EOF' > /tmp/fix_encoding.sql
USE auth_system;

-- Меняем кодировку самой базы
ALTER DATABASE auth_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Конвертируем таблицу пользователей
ALTER TABLE users CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Конвертируем таблицу менеджеров
ALTER TABLE managers CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Для надежности удалим "битые" записи с вопросиками (опционально, но красиво)
DELETE FROM managers WHERE fio LIKE '%?%';
EOF

mysql -u root < /tmp/fix_encoding.sql
rm /tmp/fix_encoding.sql

echo -e "${GREEN}[+] Пересоздание файлов с жесткой привязкой кодировки...${NC}"

# --- ПЕРЕСОЗДАЕМ index.php (Обновленное подключение) ---
cat << 'EOF' > $PROJECT_DIR/index.php
<?php
session_start();

// ЖЕСТКОЕ подключение с правильной кодировкой
$dsn = "mysql:host=localhost;dbname=auth_system;charset=utf8mb4";
$options = [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4" // Самая важная строка для кириллицы
];

try {
    $db = new PDO($dsn, 'root', '', $options);
} catch (PDOException $e) {
    die("Ошибка БД: " . $e->getMessage());
}

$db->exec("UPDATE users SET code = NULL, code_created_at = NULL WHERE code_created_at < NOW() - INTERVAL 2 MINUTE");

$error = null;
$success_msg = null;

if (isset($_POST['action'])) {
    if ($_POST['action'] == 'send_code') {
        $stmt = $db->prepare("SELECT * FROM users WHERE login = ?");
        $stmt->execute([$_POST['login']]);
        $user = $stmt->fetch();

        if ($user && password_verify($_POST['password'], $user['password'])) {
            $code = rand(100000, 999999);
            $upd = $db->prepare("UPDATE users SET code = ?, code_created_at = NOW() WHERE login = ?");
            $upd->execute([$code, $_POST['login']]);
            $success_msg = "Код сгенерирован: $code"; 
            echo "<script>alert('Ваш код: $code');</script>";
        } else {
            $error = "Неверный логин или пароль";
        }
    } 
    elseif ($_POST['action'] == 'login') {
        $stmt = $db->prepare("SELECT * FROM users WHERE login = ? AND code = ?");
        $stmt->execute([$_POST['login'], $_POST['code']]);
        $user = $stmt->fetch();

        if ($user) {
            if (isset($_POST['remember_me'])) {
                $params = session_get_cookie_params();
                setcookie(session_name(), session_id(), time() + (86400 * 30), $params["path"], $params["domain"], $params["secure"], $params["httponly"]);
            }
            $_SESSION['user_id'] = $user['id'];
            $_SESSION['login'] = $user['login'];
            header("Location: welcome.php");
            exit;
        } else {
            $error = "Неверный код подтверждения";
        }
    }
}
?>
<!DOCTYPE html>
<html lang="ru" data-bs-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Вход в систему</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css">
    <style>
        body {
            background-color: #121212;
            font-family: 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            height: 100vh;
            display: flex; align-items: center; justify-content: center;
            overflow: hidden; position: relative;
        }
        body::before {
            content: ''; position: absolute; top: -50%; left: -50%; width: 200%; height: 200%;
            background: radial-gradient(circle, rgba(76, 29, 149, 0.15) 0%, rgba(0,0,0,0) 70%);
            z-index: -1; animation: pulse 10s infinite;
        }
        @keyframes pulse { 0% {transform: scale(1);} 50% {transform: scale(1.1);} 100% {transform: scale(1);} }
        .auth-card {
            width: 100%; max-width: 420px;
            background: rgba(30, 30, 30, 0.85); backdrop-filter: blur(15px);
            border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 20px;
            padding: 40px; box-shadow: 0 15px 35px rgba(0, 0, 0, 0.5);
        }
        .form-control { background: rgba(0, 0, 0, 0.3); border: 1px solid #444; color: #fff; }
        .form-control:focus { background: rgba(0, 0, 0, 0.5); border-color: #8b5cf6; box-shadow: 0 0 0 0.25rem rgba(139, 92, 246, 0.25); color: #fff; }
        .input-group-text { background: rgba(255, 255, 255, 0.05); border: 1px solid #444; color: #aaa; }
        .btn-primary { background: linear-gradient(45deg, #6d28d9, #8b5cf6); border: none; font-weight: 600; }
        .btn-primary:hover { background: linear-gradient(45deg, #5b21b6, #7c3aed); }
        .btn-outline-light { border-color: #444; color: #ccc; }
        .btn-outline-light:hover { background: #333; border-color: #555; }
        .brand-icon { font-size: 3.5rem; background: -webkit-linear-gradient(#a78bfa, #ec4899); -webkit-background-clip: text; -webkit-text-fill-color: transparent; margin-bottom: 15px; }
    </style>
</head>
<body>
<div class="auth-card">
    <div class="text-center mb-4">
        <i class="bi bi-layers-fill brand-icon"></i>
        <h3 class="fw-bold text-white">Система v2.0</h3>
        <p class="text-secondary small">Безопасный вход</p>
    </div>
    <?php if ($error): ?>
    <div class="alert alert-danger py-2 d-flex align-items-center"><i class="bi bi-exclamation-octagon-fill me-2"></i> <?= $error ?></div>
    <?php endif; ?>
    <?php if ($success_msg): ?>
    <div class="alert alert-success py-2 d-flex align-items-center"><i class="bi bi-check-circle-fill me-2"></i> <?= $success_msg ?></div>
    <?php endif; ?>
    <form method="POST" autocomplete="on">
        <div class="mb-3">
            <label class="form-label text-secondary small text-uppercase fw-bold">Логин</label>
            <div class="input-group">
                <span class="input-group-text"><i class="bi bi-person"></i></span>
                <input type="text" class="form-control" name="login" value="<?= $_POST['login'] ?? '' ?>" required autocomplete="username">
            </div>
        </div>
        <div class="mb-3">
            <label class="form-label text-secondary small text-uppercase fw-bold">Пароль</label>
            <div class="input-group">
                <span class="input-group-text"><i class="bi bi-key"></i></span>
                <input type="password" class="form-control" name="password" autocomplete="current-password">
            </div>
        </div>
        <div class="mb-3">
            <label class="form-label text-secondary small text-uppercase fw-bold">Код из SMS</label>
            <div class="input-group">
                <span class="input-group-text"><i class="bi bi-shield-lock"></i></span>
                <input type="text" class="form-control text-center fw-bold" name="code" placeholder="000000" maxlength="6" autocomplete="one-time-code">
            </div>
        </div>
        <div class="mb-4 form-check">
            <input type="checkbox" class="form-check-input" id="remember" name="remember_me">
            <label class="form-check-label text-secondary small" for="remember">Запомнить меня</label>
        </div>
        <div class="row g-2">
            <div class="col-6"><button type="submit" class="btn btn-outline-light w-100" name="action" value="send_code">Код</button></div>
            <div class="col-6"><button type="submit" class="btn btn-primary w-100" name="action" value="login">Войти</button></div>
        </div>
    </form>
</div>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOF

# --- ПЕРЕСОЗДАЕМ welcome.php (Обновленное подключение) ---
cat << 'EOF' > $PROJECT_DIR/welcome.php
<?php
session_start();
if (!isset($_SESSION['user_id'])) {
    header("Location: index.php");
    exit;
}

// ЖЕСТКОЕ подключение с правильной кодировкой
$dsn = "mysql:host=localhost;dbname=auth_system;charset=utf8mb4";
$options = [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4"
];

try {
    $db = new PDO($dsn, 'root', '', $options);
} catch (PDOException $e) { die("DB Error"); }

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['add_manager']) && !empty(trim($_POST['fio']))) {
        $stmt = $db->prepare("INSERT INTO managers (fio) VALUES (?)");
        $stmt->execute([trim($_POST['fio'])]);
        header("Location: welcome.php");
        exit;
    }
}

if (isset($_GET['delete'])) {
    $stmt = $db->prepare("DELETE FROM managers WHERE id = ?");
    $stmt->execute([$_GET['delete']]);
    header("Location: welcome.php");
    exit;
}

$managers = $db->query("SELECT * FROM managers ORDER BY created_at DESC")->fetchAll();
?>
<!DOCTYPE html>
<html lang="ru" data-bs-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Панель управления</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css">
    <style>
        body { background-color: #0f0f0f; min-height: 100vh; color: #e0e0e0; }
        .navbar { background: rgba(20, 20, 20, 0.9); backdrop-filter: blur(10px); border-bottom: 1px solid #333; }
        .main-container { max-width: 900px; margin: 40px auto; padding: 0 15px; }
        .card-custom { background: #1a1a1a; border: 1px solid #333; border-radius: 15px; box-shadow: 0 10px 30px rgba(0,0,0,0.3); overflow: hidden; }
        .card-header-custom { background: linear-gradient(90deg, #2c2c2c, #222); padding: 20px; border-bottom: 1px solid #333; display: flex; justify-content: space-between; align-items: center; }
        .btn-neon { background-color: #2563eb; color: white; box-shadow: 0 0 10px rgba(37, 99, 235, 0.5); border: none; transition: 0.3s; }
        .btn-neon:hover { background-color: #1d4ed8; box-shadow: 0 0 20px rgba(37, 99, 235, 0.7); color: white;}
        .table-custom { margin-bottom: 0; color: #ccc; }
        .table-custom th { background-color: #252525; color: #888; font-weight: 600; text-transform: uppercase; font-size: 0.85rem; border-bottom: 2px solid #444; }
        .table-custom td { vertical-align: middle; border-bottom: 1px solid #333; }
        .table-hover tbody tr:hover { background-color: rgba(255,255,255,0.05); }
        .delete-btn { color: #ef4444; transition: 0.2s; background: transparent; border: none; }
        .delete-btn:hover { color: #ff6b6b; transform: scale(1.1); }
        .avatar-placeholder { width: 35px; height: 35px; background: #333; border-radius: 50%; display: inline-flex; align-items: center; justify-content: center; margin-right: 10px; color: #777; }
    </style>
</head>
<body>
<nav class="navbar navbar-expand-lg navbar-dark sticky-top">
    <div class="container">
        <a class="navbar-brand fw-bold" href="#"><i class="bi bi-grid-fill me-2 text-primary"></i>Admin<span class="text-muted">Panel</span></a>
        <div class="d-flex align-items-center">
            <div class="me-3 text-secondary small d-none d-sm-block"><i class="bi bi-person-circle me-1"></i> <?= htmlspecialchars($_SESSION['login'] ?? 'User') ?></div>
            <a href="logout.php" class="btn btn-sm btn-outline-secondary"><i class="bi bi-box-arrow-right"></i> Выход</a>
        </div>
    </div>
</nav>
<div class="main-container">
    <div class="card-custom mb-4">
        <div class="card-body p-4">
            <h5 class="mb-3"><i class="bi bi-person-plus-fill me-2 text-primary"></i>Добавить менеджера</h5>
            <form method="POST" class="row g-3 align-items-center">
                <div class="col-md-9">
                    <div class="input-group">
                        <span class="input-group-text bg-dark border-secondary text-secondary"><i class="bi bi-type"></i></span>
                        <input type="text" class="form-control bg-dark border-secondary text-white" name="fio" placeholder="ФИО сотрудника (например, Иванов Иван Иванович)" required>
                    </div>
                </div>
                <div class="col-md-3">
                    <button type="submit" name="add_manager" class="btn btn-neon w-100"><i class="bi bi-plus-lg"></i> Добавить</button>
                </div>
            </form>
        </div>
    </div>
    <div class="card-custom">
        <div class="card-header-custom">
            <h5 class="m-0">Список менеджеров</h5>
            <span class="badge bg-dark border border-secondary"><?= count($managers) ?> чел.</span>
        </div>
        <div class="table-responsive">
            <table class="table table-custom table-hover">
                <thead>
                    <tr>
                        <th scope="col" class="ps-4" style="width: 5%">ID</th>
                        <th scope="col">ФИО Сотрудника</th>
                        <th scope="col">Дата добавления</th>
                        <th scope="col" class="text-end pe-4">Действия</th>
                    </tr>
                </thead>
                <tbody>
                    <?php if (empty($managers)): ?>
                        <tr><td colspan="4" class="text-center py-4 text-muted">Список пуст.</td></tr>
                    <?php else: ?>
                        <?php foreach ($managers as $man): ?>
                        <tr>
                            <td class="ps-4 text-secondary">#<?= $man['id'] ?></td>
                            <td class="fw-medium"><div class="d-flex align-items-center"><div class="avatar-placeholder"><i class="bi bi-person"></i></div><?= htmlspecialchars($man['fio']) ?></div></td>
                            <td class="text-secondary small"><?= date('d.m.Y H:i', strtotime($man['created_at'])) ?></td>
                            <td class="text-end pe-4">
                                <a href="?delete=<?= $man['id'] ?>" class="delete-btn" onclick="return confirm('Удалить сотрудника?');"><i class="bi bi-trash3-fill fs-5"></i></a>
                            </td>
                        </tr>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </tbody>
            </table>
        </div>
    </div>
</div>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOF

echo -e "${GREEN}[+] Готово! Попробуй добавить русское имя сейчас.${NC}"

