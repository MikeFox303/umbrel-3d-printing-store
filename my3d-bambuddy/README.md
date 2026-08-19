# Bambuddy для Umbrel

Это неофициальный пакет Umbrel Community Store для [Bambuddy](https://github.com/maziggy/bambuddy): self-hosted панели для локального управления принтерами Bambu Lab. Пакет использует официальный образ Bambuddy и не связан с Bambu Lab или разработчиком UmbrelOS.

## Адрес и хранение данных

После установки откройте `http://<UMBREL_IP>:8280`. Постоянные данные Bambuddy находятся в `${APP_DATA_DIR}/data`, а логи — в `${APP_DATA_DIR}/logs`. При обычном обновлении Umbrel эти каталоги сохраняются.

При первом открытии завершите onboarding Bambuddy и создайте свою учётную запись. Не добавляйте в Git, скриншоты или сообщения поддержки Access Code, serial number принтера либо API key.

## X2D и AMS 2 Pro

Upstream Bambuddy включает X2D в список поддерживаемых принтеров и заявляет управление AMS 2 Pro. Для локального управления в актуальной документации Bambuddy требуется включить на принтере **LAN Only Mode**, затем **Developer Mode**; после этого запишите IP-адрес, Access Code и Serial Number. Обычный LAN Mode без Developer Mode даёт только read-only monitoring.

Этот пакет намеренно использует Docker bridge mode, поэтому автоматическое SSDP-обнаружение может не работать. В Bambuddy добавьте X2D вручную по IP-адресу. Сервер Umbrel должен иметь исходящую LAN-связность с принтером; не нужен и не включён `network_mode: host`.

После добавления проверьте:

1. карточка X2D показывает `Online`, температуры и ход печати;
2. в разделе AMS видны 4 слота, материал, цвет и статус AMS 2 Pro;
3. камера открывает live stream в браузере, через Umbrel tile и на iPhone;
4. UI продолжает получать realtime updates после restart приложения.

X2D, AMS 2 Pro, WebSocket и camera through Umbrel app proxy в этом пакете: **NOT TESTED — requires physical X2D and AMS 2 Pro**. Upstream заявляет realtime WebSocket status и MJPEG camera streaming, но это не заменяет проверку на вашем принтере.

## FilaMan + Bambuddy + X2D

```text
FilaMan -- API --> Bambuddy --> Bambu Lab X2D --> AMS 2 Pro
```

Не создавайте вторую «главную» базу катушек без необходимости: FilaMan должен оставаться источником inventory, если используемая версия его Bambuddy integration это поддерживает. В FilaMan укажите Bambuddy URL `http://<UMBREL_IP>:8280`, API key, созданный в Bambuddy, и Printer ID X2D из Bambuddy. Поля и возможности интеграции зависят от версии FilaMan; этот Umbrel package не передаёт API key автоматически и не записывает его в compose-файл.

## Телефон и удалённый доступ

Интерфейс Bambuddy responsive; upstream также заявляет PWA. На iPhone откройте Bambuddy в Safari, нажмите **Share** → **Add to Home Screen** и используйте созданную иконку.

Для удалённого доступа используйте Tailscale к Umbrel или домашней сети. Не открывайте Bambuddy напрямую в Internet через port forwarding, DMZ или публичный reverse proxy без отдельной модели защиты. Virtual Printer / Proxy Mode и его дополнительные порты не включены в этот пакет по умолчанию.

## Backup, update и uninstall

Используйте встроенный backup Bambuddy, если он доступен в вашей версии. Для ручного backup скопируйте `${APP_DATA_DIR}/data`; перед raw filesystem backup SQLite остановите приложение, чтобы получить согласованную копию базы и WAL-файлов. Не запускайте новую версию поверх единственной непроверенной копии данных.

Обновления выполняются Umbrel. Workflow Store проверяет только стабильные upstream release и immutable multi-architecture image. Slicer API sidecar не входит в пакет.

Перед uninstall экспортируйте нужные данные и сделайте backup. Удаление приложения в Umbrel может предложить удалить его data directory — не подтверждайте это, пока backup не проверен.
