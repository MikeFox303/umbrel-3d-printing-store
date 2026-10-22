# Bambuddy для Umbrel

Это неофициальный пакет Umbrel Community Store для [Bambuddy](https://github.com/maziggy/bambuddy): self-hosted панели для локального управления принтерами Bambu Lab. Пакет использует официальный образ Bambuddy и не связан с Bambu Lab или разработчиком UmbrelOS.

## Адрес и хранение данных

После установки откройте `http://<UMBREL_IP>:8280`. Постоянные данные Bambuddy находятся в `${APP_DATA_DIR}/data`, а логи — в `${APP_DATA_DIR}/logs`. При обычном обновлении Umbrel эти каталоги сохраняются.

При первом открытии завершите onboarding Bambuddy и создайте свою учётную запись. Не добавляйте в Git, скриншоты или сообщения поддержки Access Code, serial number принтера либо API key.

## X2D и AMS 2 Pro

Upstream Bambuddy включает X2D в список поддерживаемых принтеров и заявляет управление AMS 2 Pro. Для локального управления в актуальной документации Bambuddy требуется включить на принтере **LAN Only Mode**, затем **Developer Mode**; после этого запишите IP-адрес, Access Code и Serial Number. Обычный LAN Mode без Developer Mode даёт только read-only monitoring.

Для этого Umbrel-развёртывания Bambuddy использует bridge-сеть `umbrel_main_network`, а не `network_mode: host`. Backend получает стабильный адрес `10.21.0.2`; Virtual Printer слушает этот адрес внутри контейнера, а его порты публикуются на LAN-IP Umbrel `192.168.0.100`: `21`, `322`, `990`, `3000`, `3002`, `6000`, `8883`, `2024-2026`, `50000-50100`. В настройках Virtual Printer укажите `bind_ip=10.21.0.2` и `remote_interface_ip=192.168.0.100`; Bambuddy использует `VIRTUAL_PRINTER_ADVERTISE_ADDRESS=192.168.0.100` и `VIRTUAL_PRINTER_PASV_ADDRESS=192.168.0.100`. Реальный X2D `192.168.0.151` доступен через стандартный gateway `10.21.0.1`, поэтому отдельный static route не нужен. X2D следует держать на DHCP reservation `192.168.0.151`. Автоматическое SSDP-обнаружение может не работать, поэтому X2D добавляйте вручную по IP.

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

Для удалённого доступа используйте Tailscale к Umbrel или домашней сети. Не открывайте Bambuddy напрямую в Internet через port forwarding, DMZ или публичный reverse proxy без отдельной модели защиты. Virtual Printer / Proxy Mode включён: его порты публикуются на `192.168.0.100`, но 80/443 остаются за Umbrel. В slicer добавляйте VP вручную по `192.168.0.100`; для MQTT/FTPS используйте порты 8883/990. Не открывайте эти порты в Internet.

## Backup, update и uninstall

Используйте встроенный backup Bambuddy, если он доступен в вашей версии. Для ручного backup скопируйте `${APP_DATA_DIR}/data`; перед raw filesystem backup SQLite остановите приложение, чтобы получить согласованную копию базы и WAL-файлов. Не запускайте новую версию поверх единственной непроверенной копии данных.

Обновления выполняются Umbrel. Workflow Store проверяет только стабильные upstream release и immutable multi-architecture image и обновляет только image reference/версию, поэтому bridge/port-конфигурация пакета не должна перезаписываться при обычных Stable-обновлениях. Slicer API sidecar не входит в пакет: Virtual Printer работает внутри основного контейнера. Bambuddy Manager 0.2.4+ сохраняет статический IP контейнера при переключении Stable/Beta и rollback; при использовании более старого Manager сначала обновите его.

Перед uninstall экспортируйте нужные данные и сделайте backup. Удаление приложения в Umbrel может предложить удалить его data directory — не подтверждайте это, пока backup не проверен.


## Virtual Printer: важное для этой установки

Не возвращайте `network_mode: host` в `docker-compose.yml`: на этом Umbrel он позволяет Virtual Printer занимать системные порты 80/443. Текущая конфигурация:

```text
Umbrel host           192.168.0.100  (published VP ports)
Bambuddy backend      10.21.0.2      (umbrel_main_network)
Virtual Printer bind  10.21.0.2
Advertise/PASV        192.168.0.100
Real X2D              192.168.0.151
```

Порты VP: `21`, `322`, `990`, `3000`, `3002`, `6000`, `8883`, `2024-2026`, `50000-50100`. Порты 80/443 не публикуются, поэтому добавляйте VP в Bambu Studio вручную по `192.168.0.100`. После смены advertise-адреса может потребоваться заново импортировать `bbl_ca.crt` в slicer.

После обновления проверяйте `NetworkMode=umbrel_main_network`, `bind_ip=10.21.0.2`, опубликованные порты и `VIRTUAL_PRINTER_*` с адресом `192.168.0.100`. Если контейнер получит другой IP, обновите `bind_ip` Virtual Printer через UI или API.

Эта схема deployment-specific: статический `10.21.0.2` выбран для данной установки, как ранее `192.168.0.151` для X2D.
