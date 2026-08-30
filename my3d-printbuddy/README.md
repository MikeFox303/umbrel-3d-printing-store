# Printbuddy for UmbrelOS

Неофициальный Community App package для [Printbuddy](https://github.com/vmhomelab/printbuddy).

## Что входит

- upstream Printbuddy `v0.2.5.1`;
- `linux/arm64` для Raspberry Pi 4/5 и `linux/amd64`;
- host networking, как рекомендует upstream для Linux;
- постоянные данные в `${APP_DATA_DIR}/data`;
- постоянные логи в `${APP_DATA_DIR}/logs`;
- Web UI на порту `8281`.

## Подключение принтеров

После установки откройте Printbuddy из Umbrel и добавьте принтеры через интерфейс приложения.

- Bambu Lab: локальное подключение по IP / LAN provider.
- Klipper: подключение к Moonraker по IP и порту Moonraker.

Host networking позволяет Printbuddy напрямую видеть локальную сеть Umbrel-хоста и нужен для наиболее полного Bambu/Virtual Printer сценария.

## Совместимость с другими приложениями магазина

Пакет использует отдельный Web UI порт `8281`, поэтому обычная работа может идти параллельно с:

- FilaMan (`8000`);
- Bambuddy (`8280`).

Virtual Printer у Printbuddy может поднимать дополнительные host-порты, включая MQTT/FTPS/RTSPS. Не включайте одновременно два Virtual Printer/proxy-сервиса, если они пытаются занять одинаковые host-порты.

## Данные и обновления

Удаление/обновление контейнера не должно удалять `/app/data` и `/app/logs`, поскольку они привязаны к каталогу данных приложения Umbrel. Перед крупным обновлением рекомендуется использовать backup Printbuddy и/или backup каталога приложения Umbrel.
