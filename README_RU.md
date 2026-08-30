# Android DNS-over-HTTPS + DPI Bypass

**[Read in English →](./README_EN.md)**

Скрипты для автоматического запуска DNS-over-HTTPS и обхода DPI на Android через Magisk/KernelSU.

## Что делает

| Скрипт | Назначение |
|--------|-----------|
| `99-doh.sh` | Перехватывает DNS-запросы (порт 53) и отправляет их через DoH (Google DNS) |
| `99-nfqws.sh` | Обходит DPI для трафика V2RayNG через nfqws (фейковые пакеты, фрагментация) |

## Требования

- **Root** (Magisk/KernelSU)
- **Бинарники** в `/data/local/tmp/`:
  - `doh-stub-rust` — DoH-резолвер
  - `nfqws` — из модуля `nfqws_custom`
- **V2RayNG** (`com.v2ray.ang.fdroid`) установлен и запущен
- **Файл хостов** `/data/local/tmp/hosts.txt` для nfqws

## Установка

```bash
# Копируем в service.d (Magisk/KernelSU)
cp 99-doh.sh /data/adb/service.d/
cp 99-nfqws.sh /data/adb/service.d/
chmod +x /data/adb/service.d/*.sh
```

## Конфигурация

### 99-doh.sh

| Переменная | Значение | Описание |
|------------|----------|----------|
| `DOH_BIN` | `/data/local/tmp/doh-stub-rust` | Путь к DoH-бинарнику |
| `LISTEN_PORT` | `5300` | Порт локального DNS |
| `NOBODY_UID` | `9999` | UID для запуска doh-stub |
| `LD_LIBRARY_PATH` | `/data/local/tmp` | Путь к библиотекам |
| `LOG_FILE` | `/data/local/tmp/dns_log.log` | Файл логов |

### 99-nfqws.sh

| Переменная | Значение | Описание |
|------------|----------|----------|
| `NFQWS_DIR` | `/data/adb/modules/nfqws_custom` | Путь к модулю nfqws |
| `NFQWS_BIN` | `$NFQWS_DIR/nfqws` | Путь к бинарнику nfqws |
| `HOST_LIST` | `/data/local/tmp/hosts.txt` | Список хостов для обхода |
| `QNUM` | `300` | Номер NFQUEUE |

## Как работает

### DoH (`99-doh.sh`)

1. Ждёт завершения загрузки (`sys.boot_completed`)
2. Отключает IPv6 (чтобы DNS не утекал через него)
3. Поднимает `doh-stub-rust` на порту 5300
4. Перенаправляет UDP/TCP 53 → 5300 через `iptables nat`
5. Цикл с проверкой каждые 10 секунд

### DPI Bypass (`99-nfqws.sh`)

1. Ждёт завершения загрузки (`sys.boot_completed`)
2. Получает UID V2RayNG из системы (`pm list packages -U`)
3. Пропускает трафик `nobody` (чтобы не зациклить)
4. Отправляет HTTP/HTTPS V2RayNG в NFQUEUE 300
5. `nfqws` фрагментирует пакеты и подделывает SNI (`cloudflare.com`)
6. Цикл с проверкой каждые 10 секунд

## Параметры nfqws

| Параметр | Описание |
|----------|----------|
| `--dpi-desync=fake,multisplit` | Тип обхода: фейковые пакеты + мультифрагментация |
| `--dpi-desync-split-seqovl=345` | Размер SEQ overlap |
| `--dpi-desync-split-pos=1` | Позиция разделения |
| `--dpi-desync-fooling=ts` | Обман через TCP timestamps |
| `--dpi-desync-repeats=4` | Количество повторов фейков |
| `--dpi-desync-fake-tls-mod=rnd,dupsid,sni=cloudflare.com` | Модификация TLS: случайные данные, дублирование SID, поддельный SNI |

## Логи

| Файл | Описание |
|------|----------|
| `/data/local/tmp/dns_log.log` | Логи DoH-резолвера |
| `/data/local/tmp/nfqws_log.log` | Логи nfqws |

## Проверка работы

```bash
# Проверить, что DoH слушает
netstat -tlnp | grep 5300

# Проверить iptables правила
iptables -t nat -L OUTPUT -n -v
iptables -t mangle -L OUTPUT -n -v

# Проверить процессы
ps | grep doh-stub
ps | grep nfqws

# Проверить DNS
getprop net.dns1
```

## Отладка

| Симптом | Причина | Решение |
|---------|---------|---------|
| DNS не работает | `doh-stub-rust` не запущен | Проверить `LD_LIBRARY_PATH`, логи |
| Сайты не открываются | nfqws не ловит пакеты | Проверить UID V2Ray, `iptables -t mangle` |
| Батарея садится | Слишком частый `sleep` | Увеличить интервал в цикле |
| DNS утекает через IPv6 | IPv6 не отключён | Проверить `/proc/sys/net/ipv6/conf/*/disable_ipv6` |

## Структура файлов

```
/data/local/tmp/
├── doh-stub-rust          # DoH бинарник
├── dns_log.log            # Логи DNS
├── nfqws_log.log          # Логи nfqws
└── hosts.txt              # Список хостов для обхода

/data/adb/modules/nfqws_custom/
└── nfqws                  # Бинарник nfqws

/data/adb/service.d/
├── 99-doh.sh              # Скрипт DoH
└── 99-nfqws.sh            # Скрипт DPI bypass
```

## Безопасность

- DoH-резолвер запускается от `nobody` (UID 9999) для изоляции
- Трафик `nobody` исключается из перенаправления (петля)
- IPv6 отключается принудительно для предотвращения утечек DNS
