import os
import time
import random
import requests
import psycopg2
from datetime import datetime, timedelta

DB_HOST = os.getenv('DB_HOST', 'postgres')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASS = os.getenv('DB_PASSWORD')
# Режим работы: REAL (Интернет) или SIMULATION (Генерация)
DATA_MODE = os.getenv('DATA_MODE', 'REAL')

TOP_N_STOCKS = 20           # Размер топа акций
REFRESH_INTERVAL_SEC = 3600 # Интервал обновления списка 

# Глобальное состояние
WATCHLIST = []      # Текущий список тикеров
MEMORY_PRICES = {}  # Последние известные цены (для симуляции)
LAST_REFRESH_TIME = datetime.min

def get_db_connection():
    while True:
        try:
            conn = psycopg2.connect(
                host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASS
            )
            return conn
        except psycopg2.OperationalError as e:
            time.sleep(3)

def update_companies_table(conn, stocks_data):
    cursor = conn.cursor()
    for stock in stocks_data:
        cursor.execute("""
            INSERT INTO companies (symbol, name) 
            VALUES (%s, %s)
            ON CONFLICT (symbol) DO NOTHING;
        """, (stock['ticker'], stock['name']))
    conn.commit()
    print(f"Справочник компаний обновлен. Записей: {len(stocks_data)}.", flush=True)

def init_market_data(conn):
    global WATCHLIST, MEMORY_PRICES, LAST_REFRESH_TIME
    print("Запрос данных с Мосбиржи (формирование Топ-20)...", flush=True)
    
    url = "https://iss.moex.com/iss/engines/stock/markets/shares/boards/TQBR/securities.json"
    
    try:
        resp = requests.get(url, timeout=5)
        if resp.status_code != 200:
            raise Exception(f"HTTP ошибка {resp.status_code}")

        json_data = resp.json()

        sec_data = json_data['securities']
        sec_cols = sec_data['columns']
        sec_rows = sec_data['data']
        
        idx_s_secid = sec_cols.index('SECID')
        idx_s_name = sec_cols.index('SECNAME')

        names_map = {row[idx_s_secid]: row[idx_s_name] for row in sec_rows}

        mkt_data = json_data['marketdata']
        mkt_cols = mkt_data['columns']
        mkt_rows = mkt_data['data']
        
        idx_m_secid = mkt_cols.index('SECID')
        idx_m_last = mkt_cols.index('LAST')
        idx_m_val = mkt_cols.index('VALTODAY')
        
        candidates = []
        for row in mkt_rows:
            ticker = row[idx_m_secid]
            price = row[idx_m_last]
            volume = row[idx_m_val]
            if price is not None and volume is not None:
                candidates.append({
                    'ticker': ticker, 
                    'price': float(price), 
                    'volume': float(volume),
                    'name': names_map.get(ticker, ticker)
                })
        
        candidates.sort(key=lambda x: x['volume'], reverse=True)
        top_stocks = candidates[:TOP_N_STOCKS]
        
        update_companies_table(conn, top_stocks)

        WATCHLIST = [x['ticker'] for x in top_stocks]
        for x in top_stocks:
            MEMORY_PRICES[x['ticker']] = x['price']
        
        LAST_REFRESH_TIME = datetime.now()
        print(f"Список отслеживания сформирован: {len(WATCHLIST)} акций.", flush=True)
        return True

    except Exception as e:
        print(f"Ошибка инициализации данных: {e}.", flush=True)
        if not WATCHLIST:
            print("Внимание: Используется резервный список тикеров.", flush=True)
            fallback = [
                {'ticker': 'SBER', 'name': 'Sberbank Russia'},
                {'ticker': 'GAZP', 'name': 'Gazprom PAO'}
            ]
            update_companies_table(conn, fallback)
            WATCHLIST = ['SBER', 'GAZP']
            MEMORY_PRICES.update({'SBER': 270.0, 'GAZP': 160.0})
        return False

def get_real_prices_batch():
    if not WATCHLIST: return None
    
    tickers_str = ",".join(WATCHLIST)
    url = f"https://iss.moex.com/iss/engines/stock/markets/shares/boards/TQBR/securities.json?securities={tickers_str}"
    
    try:
        resp = requests.get(url, timeout=2)
        if resp.status_code != 200: return None
        
        data = resp.json()['marketdata']
        cols = data['columns']
        rows = data['data']
        
        idx_secid = cols.index('SECID')
        idx_status = cols.index('TRADINGSTATUS')
        idx_last = cols.index('LAST')
        
        result = {}
        for row in rows:
            ticker = row[idx_secid]
            status = row[idx_status]
            price = row[idx_last]
            
            if status == 'T' and price is not None:
                result[ticker] = float(price)
            else:
                result[ticker] = None
        return result
    except Exception as e:
        return None

def preload_history_data(conn):
    print("Предзагрузка истории торгов за последние 3 часа...", flush=True)
    cursor = conn.cursor()

    start_time = datetime.now() - timedelta(hours=3)
    start_str = start_time.strftime('%Y-%m-%d %H:%M:%S')
    
    total_records = 0
    
    for symbol in WATCHLIST:
        records_to_insert = []
        try:
            has_real_data = False
            
            if DATA_MODE == "REAL":
                url = f"https://iss.moex.com/iss/engines/stock/markets/shares/boards/TQBR/securities/{symbol}/candles.json?from={start_str}&interval=1"
                resp = requests.get(url, timeout=1)
                if resp.status_code == 200:
                    candles = resp.json()['candles']['data']
                    if candles:
                        has_real_data = True
                        for c in candles:
                            price = float(c[1]) 
                            vol = int(c[5]) if c[5] else random.randint(1, 50)
                            ts = datetime.strptime(c[6], "%Y-%m-%d %H:%M:%S")
                            
                            records_to_insert.append((symbol, price, vol, price*vol, ts))

            if not has_real_data:
                current_price = MEMORY_PRICES.get(symbol, 150.0)
                for i in range(180, 0, -1):
                    fake_ts = datetime.now() - timedelta(minutes=i)
                    change = random.uniform(-0.002, 0.002)
                    current_price = current_price * (1 - change) 
                    
                    qty = random.randint(1, 50)
                    records_to_insert.append((symbol, current_price, qty, current_price*qty, fake_ts))

            if records_to_insert:
                args_str = ','.join(cursor.mogrify("(%s,%s,%s,%s,%s)", x).decode('utf-8') for x in records_to_insert)
                cursor.execute("INSERT INTO trades (symbol, price, quantity, total_cost, timestamp) VALUES " + args_str)
                total_records += len(records_to_insert)

        except Exception as e:
            print(f"Ошибка прелоада для {symbol}: {e}", flush=True)
            continue

    conn.commit()
    print(f" История загружена: добавлено {total_records} записей.", flush=True)



def check_market_open():
    if DATA_MODE != "REAL": return
    
    print("\nПРОВЕРКА СТАТУСА МОСБИРЖИ...", flush=True)
    prices = get_real_prices_batch()
    
    if not prices or all(p is None for p in prices.values()):
        print("РЫНОК ЗАКРЫТ (Или нет данных)", flush=True)
        print("ВНИМАНИЕ: Система переключается в режим АВТО-СИМУЛЯЦИИ.", flush=True)
        print("Цены будут генерироваться алгоритмом Random Walk.\n", flush=True)
    else:
        print("РЫНОК ОТКРЫТ. ПОЛУЧАЕМ РЕАЛЬНЫЕ ДАННЫЕ\n", flush=True)

def simulate_step(symbol):
    current = MEMORY_PRICES.get(symbol, 100.0)
    change = random.uniform(-0.001, 0.001) 
    new_price = current * (1 + change)
    MEMORY_PRICES[symbol] = new_price
    return new_price

def main():
    print(f"Генератор запущен. Режим данных: {DATA_MODE}", flush=True)
    
    conn = get_db_connection()
    conn.autocommit = True 

    init_market_data(conn)
    check_market_open()

    preload_history_data(conn)

    cursor = conn.cursor()

    while True:
        if (datetime.now() - LAST_REFRESH_TIME).total_seconds() > REFRESH_INTERVAL_SEC:
            print("Плановое обновление списка акций...", flush=True)
            init_market_data(conn)
            check_market_open()

        real_data = {}
        if DATA_MODE == "REAL":
            real_data = get_real_prices_batch() or {}

        for symbol in WATCHLIST:
            price = real_data.get(symbol)
            source = "MOEX"
            
            if price is None:
                price = simulate_step(symbol)
                source = "SIM"
            else:
                MEMORY_PRICES[symbol] = price

            quantity = random.randint(1, 50)
            total_cost = price * quantity
            
            cursor.execute(
                """INSERT INTO trades (symbol, price, quantity, total_cost, timestamp) 
                   VALUES (%s, %s, %s, %s, %s)""",
                (symbol, price, quantity, total_cost, datetime.now())
            )


        if WATCHLIST and random.random() < 0.1: 
             first_ticker = WATCHLIST[0]
             src = "MOEX" if real_data.get(first_ticker) else "SIM"
             current_price = MEMORY_PRICES[first_ticker]
             print(f"Пакет обработан. {first_ticker}: {current_price:.2f}", flush=True)

        time.sleep(60)

if __name__ == "__main__":
    main()