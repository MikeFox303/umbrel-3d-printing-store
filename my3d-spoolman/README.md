# Spoolman for UmbrelOS

Community App package для запуска [Spoolman](https://github.com/Donkie/Spoolman) в UmbrelOS.

## Параметры

- App ID: `my3d-spoolman`
- Web UI: `http://<UMBrel-IP>:7912`
- Upstream: `v0.26.1`
- Image: `ghcr.io/donkie/spoolman:0.26.1`
- Persistent data: `${APP_DATA_DIR}/data`
- Container data path: `/home/app/.local/share/spoolman`
- Database: SQLite по умолчанию
- Timezone: `Europe/Kyiv`
- UID/GID: `1000:1000`

В каталоге данных сохраняются `spoolman.db`, логи, кэш внешней базы филаментов и автоматические резервные копии SQLite.

## Moonraker

Для Klipper/Moonraker укажите адрес Umbrel-сервера:

```ini
[spoolman]
server: http://<UMBrel-IP>:7912
```

Moonraker после этого сможет синхронизировать активную катушку и расход филамента со Spoolman.

## Безопасность

Spoolman не имеет собственной системы авторизации. Используйте его только в доверенной локальной сети либо за reverse proxy с аутентификацией. Не пробрасывайте порт `7912` напрямую в интернет.
