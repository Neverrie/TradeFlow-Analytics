@echo off
chcp 65001 >nul
cls

echo  TRADEFLOW LAUNCHER (Windows)
echo.

echo Выберите режим работы генератора:
echo [1] REAL       (Данные с Мосбиржи)
echo [2] SIMULATION (Фейковые данные 24/7)
echo.

set /p mode_input="Ваш выбор (по умолчанию 1): "

if "%mode_input%"=="2" goto set_simulation

:set_real
    set DATA_MODE=REAL
    echo  -> Выбран режим: REAL (Реальные данные)
    echo.
    echo -----------------------------------------------------------
    echo [ВНИМАНИЕ] Режим REAL работает только во время торгов!
    echo            Мосбиржа (TQBR): Пн-Пт, 10:00 - 18:40 МСК.
    echo.
    echo            В другое время включится АВТО-СИМУЛЯЦИЯ.
    echo -----------------------------------------------------------
    echo.
    pause
    goto credentials

:set_simulation
    set DATA_MODE=SIMULATION
    echo  -> Выбран режим: SIMULATION (Симуляция)
    goto credentials

:credentials

set /p input_user="Введите имя пользователя БД (Enter для 'admin'): "
if "%input_user%"=="" set input_user=admin

set /p input_pass="Введите пароль БД (Enter для 'secret123'): "
if "%input_pass%"=="" set input_pass=secret123

echo.
echo  Генерация уникального .env файла

set SECRET_KEY=key_%RANDOM%%RANDOM%%RANDOM%
set COOKIE_SECRET=cookie_%RANDOM%%RANDOM%%RANDOM%

(
echo DB_NAME=tradeflow_db
echo DB_USER=%input_user%
echo DB_PASSWORD=%input_pass%
echo DB_HOST=postgres
echo.
echo DATA_MODE=%DATA_MODE%
echo.
echo POSTGRES_USER=postgres
echo POSTGRES_PASSWORD=root
echo POSTGRES_DB=postgres
echo.
echo REDASH_LOG_LEVEL=INFO
echo PYTHONUNBUFFERED=1
echo REDASH_REDIS_URL=redis://redis:6379/0
echo REDASH_DATABASE_URL=postgresql://postgres:root@postgres/postgres
echo.
echo REDASH_COOKIE_SECRET=%COOKIE_SECRET%
echo REDASH_SECRET_KEY=%SECRET_KEY%
) > .env

echo Файл .env создан успешно.
echo.
echo Пересборка и запуск контейнеров...
docker-compose up -d --build

echo.
echo ПРОЕКТ ЗАПУЩЕН
echo.
echo  Redash UI:   http://localhost:5000
echo.
echo  ИСПОЛЬЗУЙТЕ ЭТИ ДАННЫЕ ДЛЯ ПОДКЛЮЧЕНИЯ (Data Source):
echo ---------------------------------------------------
echo    Host:      postgres
echo    DB Name:   tradeflow_db
echo    User:      %input_user%
echo    Password:  %input_pass%
echo ---------------------------------------------------
echo.

set /p show_logs="Открыть логи генератора (увидеть сделки)? [Y/n]: "
if /i "%show_logs%"=="n" goto :end

echo.
echo [INFO] Нажмите Ctrl+C, чтобы выйти из просмотра логов 
echo        (проект продолжит работать в фоне).
echo.
echo ---------------------------------------------------
docker-compose logs -f generator

:end
echo.
echo Удачной работы!
pause >nul