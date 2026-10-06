# Bambuddy для Umbrel

Это неофициальный пакет Umbrel Community Store для [Bambuddy](https://github.com/maziggy/bambuddy): self-hosted панели для локального управления принтерами Bambu Lab. Пакет использует официальный образ Bambuddy и не связан с Bambu Lab или разработчиком UmbrelOS.

## Адрес и хранение данных

После установки откройте `http://<UMBREL_IP>:8280`. Постоянные данные Bambuddy находятся в `${APP_DATA_DIR}/data`, а логи — в `${APP_DATA_DIR}/logs`. При обычном обновлении Umbrel эти каталоги сохраняются.

При первом открытии завершите onboarding Bambuddy и создайте свою учётную запись. Не добавляйте в Git, скриншоты или сообщения поддержки Access Code, serial number принтера либо API key.

## X2D и AMS 2 Pro

Upstream Bambuddy включает X2D в список поддерживаемых принтеров и заявляет управление AMS 2 Pro. Для локального управления в актуальной документации Bambuddy требуется включить на принтере **LAN Only Mode**, затем **Developer Mode**; после этого запишите IP-адрес, Access Code и Serial Number. Обычный LAN Mode без Developer Mode даёт только read-only monitoring.

Для этого Umbrel-развёртывания Bambuddy использует две Docker-сети вместо `network_mode: host`. Интерфейс приложения остаётся во внутренней `umbrel_main_network`, а Virtual Printer получает отдельный LAN-адрес `192.168.0.200` через внешнюю IPvlan L2 сеть `bambuddy_lan` на Wi-Fi `wlan0`. Связь Bambuddy с реальным X2D `192.168.0.151` идёт непосредственно через интерфейс IPvlan `bambuddy_lan` (`eth0` внутри контейнера) с исходным адресом `192.168.0.200`. X2D следует держать на DHCP reservation `192.168.0.151`. Автоматическое SSDP-обнаружение может не работать, поэтому X2D добавляйте вручную по IP.

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

Обновления выполняются Umbrel. Workflow Store проверяет только стабильные upstream release и immutable multi-architecture image и обновляет только image reference/версию, поэтому LAN/IPvlan-конфигурация пакета не должна перезаписываться при обычных Stable-обновлениях. Slicer API sidecar не входит в пакет.

Перед uninstall экспортируйте нужные данные и сделайте backup. Удаление приложения в Umbrel может предложить удалить его data directory — не подтверждайте это, пока backup не проверен.


## Virtual Printer: важное для этой установки

Не возвращайте `network_mode: host` в `docker-compose.yml`: на этом Umbrel он позволяет Virtual Printer занимать системные порты 80/443. Текущая конфигурация специально разделяет:

```text
Umbrel host           192.168.0.100
Virtual Printer       192.168.0.200 (IPvlan)
Bambuddy backend      10.21.0.x (umbrel_main_network)
Real X2D               192.168.0.151
```

После обновления проверяйте, что `NetworkMode` не равен `host`, присутствуют обе сети, контейнер имеет `192.168.0.200`, а маршрут к X2D выглядит как `192.168.0.151 dev eth0 src 192.168.0.200`.

Эта схема является deployment-specific для данного Community Store: используйте её только вместе с соответствующей внешней Docker-сетью `bambuddy_lan`.
