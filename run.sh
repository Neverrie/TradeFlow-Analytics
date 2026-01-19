#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo -e "${BLUE}ЗАПУСК TRADEFLOW ANALYTICS${NC}"
echo ""

echo "Выберите режим работы:"
echo "[1] REAL       (Данные с Мосбиржи)"
echo "[2] SIMULATION (Фейковые данные)"
read -p "Ваш выбор (по умолчанию 1): " mode_choice

if [ "$mode_choice" == "2" ]; then
    DATA_MODE="SIMULATION"
    echo -e "${GREEN} -> Выбран режим: SIMULATION${NC}"
else
    DATA_MODE="REAL"
    echo -e "${GREEN} -> Выбран режим: REAL${NC}"
    echo ""
    echo -e "${YELLOW}-----------------------------------------------------------"
    echo -e "[ВНИМАНИЕ] Вы выбрали реальные данные."
    echo -e "Торги на Мосбирже идут: Пн-Пт, 10:00 - 18:40 МСК."
    echo -e ""
    echo -e "Если запустить проект сейчас (ночью/выходные),"
    echo -e "система сама включит симуляцию, чтобы графики не были пустыми."
    echo -e "-----------------------------------------------------------${NC}"
    echo ""
    read -p "Нажмите Enter, чтобы продолжить..." dummy
fi
echo ""

read -p "Введите имя пользователя БД (default: admin): " DB_USER
DB_USER=${DB_USER:-admin}

read -p "Введите пароль БД (default: secret123): " DB_PASS
DB_PASS=${DB_PASS:-secret123}

echo -e "\n${YELLOW} Генерируем .env с уникальными ключами...${NC}"

R_SECRET=$(openssl rand -hex 32 2>/dev/null || echo "secret_$(date +%s)")
R_COOKIE=$(openssl rand -hex 32 2>/dev/null || echo "cookie_$(date +%s)")

cat > .env <<EOF
DB_NAME=tradeflow_db
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASS
DB_HOST=postgres

DATA_MODE=$DATA_MODE

POSTGRES_USER=postgres
POSTGRES_PASSWORD=root
POSTGRES_DB=postgres

REDASH_LOG_LEVEL=INFO
PYTHONUNBUFFERED=1
REDASH_REDIS_URL=redis://redis:6379/0
REDASH_DATABASE_URL=postgresql://postgres:root@postgres/postgres

REDASH_COOKIE_SECRET=$R_COOKIE
REDASH_SECRET_KEY=$R_SECRET
EOF

echo -e "${GREEN} Конфигурация готова.${NC}"
echo " Запускаем Docker..."

docker-compose up -d --build

echo ""
echo -e "${GREEN} ПРОЕКТ ЗАПУЩЕН!${NC}"
echo ""
echo -e " Redash:    http://localhost:5001"
echo ""
echo -e "${YELLOW} ИСПОЛЬЗУЙТЕ ЭТИ ДАННЫЕ ДЛЯ ПОДКЛЮЧЕНИЯ (Data Source):${NC}"
echo "   Host:      postgres"
echo "   DB Name:   tradeflow_db"
echo "   User:      $DB_USER"
echo "   Password:  $DB_PASS"
echo ""

read -p "Открыть живые логи генератора? [Y/n] (default: Y): " show_logs
show_logs=${show_logs:-Y}

if [[ "$show_logs" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}Нажмите Ctrl+C для выхода из логов (проект продолжит работать).${NC}"
    echo "---------------------------------------------------"
    docker-compose logs -f generator
fi