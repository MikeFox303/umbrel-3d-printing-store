# 3D Printing Community App Store для Umbrel

Неофициальный Community App Store для self-hosted программ 3D-печати: FoxForge, FilaMan, Bambuddy, Bambuddy Manager, Printbuddy и Spoolman.

## Установка Store

1. В UmbrelOS добавьте URL этого GitHub-репозитория как Community App Store.
2. Дождитесь обновления каталога и установите нужные приложения обычным способом через Umbrel.
3. Для Bambuddy сначала установите **Bambuddy**, затем **Bambuddy Manager**. Manager имеет зависимость от `my3d-bambuddy` и управляет уже установленным runtime.

UmbrelOS периодически обновляет зарегистрированные Community Store, поэтому удалять и повторно добавлять Store после каждой новой версии не нужно.

## FoxForge

`my3d-foxforge` — пакет FoxForge для UmbrelOS. Актуальная линия пакета использует immutable multi-architecture образ `v0.1.0-alpha.4` для Linux `amd64` и `arm64`.

FoxForge остаётся ранней alpha-версией. Пакет предоставляет единый self-hosted интерфейс для Bambu Lab и Moonraker/Klipper, очередь печати, inventory катушек, общие Pause/Resume/Cancel и realtime application events. Автоматический filament accounting P3 и persistent farm scheduler пока не входят в релиз.

Для защищённых write-операций пакет передаёт уникальный Umbrel `APP_PASSWORD` в FoxForge как `FOXFORGE_COMMAND_TOKEN`. Оператор вводит пароль приложения Umbrel в **Unlock writes** внутри FoxForge; браузер хранит credential только в памяти текущей вкладки. Umbrel App Proxy остаётся отдельным защитным слоем и не заменяет авторизацию самого FoxForge.

Пакет закреплён на конкретном GHCR digest, не использует `latest`, не требует `network_mode: host`, privileged mode или Docker socket. Состояние хранится в `${APP_DATA_DIR}/data`.

Важно: CI проверяет package contract, Compose, anonymous pull и запуск `amd64`/`arm64`, но это не заменяет реальную валидацию Bambu X2D, Moonraker/OpenKE и Raspberry Pi 5/UmbrelOS. Эти проверки остаются обязательным FoxForge alpha validation gate.

## Bambuddy: рекомендуемый способ установки и обновления

`my3d-bambuddy` использует официальный upstream `maziggy/bambuddy`. Версия, указанная в Umbrel package, является проверенным **bootstrap runtime** — безопасной исходной точкой, с которой Bambuddy может быть установлен обычным способом.

После установки **Bambuddy Manager** Stable/Beta обновления Bambuddy больше не требуют переписывать Umbrel package. Store публикует отдельно проверенные channel metadata:

- `channels/bambuddy/stable.json`
- `channels/bambuddy/beta.json`

Перед публикацией нового runtime Store CI:

- получает immutable digest официального GHCR image;
- проверяет `linux/amd64`;
- проверяет `linux/arm64`;
- сверяет фактический `APP_VERSION` внутри контейнера;
- повторно проверяет upstream tag/digest после smoke-test;
- только после этого делает канал доступным Manager.

Схема обновления:

```text
maziggy/bambuddy release или daily build
                  |
                  v
        Store channel validation
          |                  |
       amd64              arm64
          |                  |
          +--------+---------+
                   |
                   v
        stable.json / beta.json
                   |
                   v
           Bambuddy Manager
                   |
          snapshot + switch
                   |
                   v
          официальный Bambuddy
```

### Bambuddy Manager: Quick Start

1. Установите **Bambuddy** из этого Store и убедитесь, что он запускается.
2. Установите **Bambuddy Manager**. В Umbrel он открывается как отдельное приложение на порту `8282` через App Proxy.
3. Откройте Manager и проверьте текущий runtime и доступные каналы.
4. Для обычного использования оставайтесь на **Stable**.
5. Чтобы протестировать новую версию, выберите **Beta**. Manager сначала остановит Bambuddy, создаст проверенный SQLite snapshot и только затем заменит runtime.
6. Для возврата **Beta → Stable** Manager использует сохранённую Stable snapshot перед запуском более старой Stable-схемы БД.
7. Если переключение или health-check не проходит, Manager автоматически пытается выполнить rollback. Последний проверенный snapshot также можно восстановить вручную.

Manager проверяет SHA-256, SQLite `PRAGMA integrity_check`, ожидаемый immutable image и `/health`. Незавершённая транзакция сохраняется на диск и может быть восстановлена после перезапуска Manager или закрытия браузера.

> **Важно:** Bambuddy Manager управляет Docker runtime и имеет доступ к Docker socket. Не отключайте Umbrel App Proxy authentication для Manager и не публикуйте его порт напрямую в интернет.

### Bootstrap package и runtime channel — это разные версии

В интерфейсе Umbrel версия приложения `my3d-bambuddy` может отличаться от фактической версии запущенного Bambuddy после переключения через Manager. Это нормально:

```text
Umbrel package version = bootstrap/package definition
Bambuddy runtime       = Stable или Beta channel, выбранный Manager
```

Channel automation намеренно **не изменяет** `my3d-bambuddy/docker-compose.yml` и `umbrel-app.yml`. Это исключает конфликт двух независимых механизмов обновления во время существования Beta rollback point.

Не рекомендуется вручную менять image/command/entrypoint Bambuddy Compose, пока runtime управляется Manager. При неподдерживаемых service overrides Manager откажется от переключения вместо небезопасного угадывания конфигурации.

## Автоматические обновления FilaMan

После успешной сборки ветки `main` репозитория [MikeFox303/filaman-system](https://github.com/MikeFox303/filaman-system) workflow этого Store автоматически получает immutable digest, повышает версию пакета и публикует обновление. Затем Umbrel показывает обычную кнопку обновления приложения; каталог данных и ID `my3d-filaman` не меняются.

Обновления официального [Fire-Devils/filaman-system](https://github.com/Fire-Devils/filaman-system) поступают в локализованный репозиторий отдельным pull request. Проверки блокируют публикацию, если в русском или украинском словаре отсутствуют ключи либо изменены placeholders.

## Immutable images

FoxForge закрепляется на опубликованном multi-architecture SHA256 digest соответствующего guarded release и не использует floating release tags.

FilaMan package закрепляется на опубликованном multi-architecture SHA256 digest и намеренно не использует `latest`.

Bambuddy Stable/Beta channels также закрепляются на immutable digest официального `ghcr.io/maziggy/bambuddy`. Для multi-architecture validation CI запускает каждую архитектуру по её OCI child-manifest digest, а пользователю публикуется общий multi-arch index digest.

Printbuddy использует конкретный стабильный upstream release tag. Spoolman использует конкретный стабильный release tag с закреплённым multi-architecture digest.

## Данные, обновление и backup

Данные Umbrel хранятся в `${APP_DATA_DIR}/data` и не попадают в Git. Перед крупным обновлением рекомендуется создать backup данных. Обычное обновление через Umbrel не меняет каталог данных.

Для FoxForge полный `/data` следует считать чувствительными данными: он содержит конфигурацию, SQLite state, staged artifacts и credential-bearing/recovery material. Перед alpha-upgrade делайте полный backup каталога приложения.

Bambuddy Manager создаёт transactional snapshots перед destructive runtime operations, но этот snapshot защищает прежде всего SQLite database и runtime definition. Для point-in-time recovery media/archive/library файлов сохраняйте также обычные полные backup Bambuddy.

## Переход FilaMan с Dockge

1. Убедитесь, что старая и новая версии FilaMan совместимы; безопаснее начать с той же upstream-версии `1.2.42`.
2. На Umbrel host скопируйте `scripts/backup-dockge-filaman.sh` и запустите его после остановки старого FilaMan. Скрипт определяет фактический `/app/data` mount через `docker inspect`, создаёт tar.gz и SHA256, ничего не удаляет.
3. Один раз установите Umbrel App, затем остановите его.
4. Запустите `scripts/migrate-dockge-filaman.sh`. Скрипт требует существующий backup, проверяет остановку обоих контейнеров, создаёт backup непустого destination, копирует данные и ждёт `/health`.
5. Проверьте login, русский интерфейс, катушки, API и restart. До подтверждения не удаляйте Dockge stack, Docker volume или backup archive.

## Rollback FilaMan после миграции

1. Stop Umbrel FilaMan.
2. Не изменяйте исходный Dockge volume.
3. Start Dockge FilaMan.
4. Проверьте UI и данные.

Не запускайте старую версию поверх базы, которую уже обновила более новая FilaMan version: rollback всегда использует исходный, неизменённый Dockge volume.

## Приложения 3D Printing

```text
3D Printing
├── FoxForge — multi-vendor управление, очередь, inventory и typed Bambu/Moonraker capabilities.
├── FilaMan — учёт и управление inventory филамента.
├── Bambuddy — локальное управление, мониторинг, AMS и камера Bambu Lab.
├── Bambuddy Manager — Stable/Beta, verified snapshot и rollback для Bambuddy.
├── Printbuddy — multi-vendor панель для Bambu Lab, Klipper/Moonraker и других принтеров.
└── Spoolman — центральная база катушек, остатков, стоимости и истории расхода.
```

## Рекомендуемая архитектура

FoxForge развивается как отдельная multi-vendor платформа и может использоваться самостоятельно для поддерживаемых Bambu/Moonraker сценариев. Остальные приложения Store остаются независимыми и могут устанавливаться параллельно в зависимости от нужного workflow.

```text
                         ┌── Bambu Lab / AMS
                         │
UmbrelOS ── Printbuddy ──┼── Klipper / Moonraker
                         │
                         └── другие поддерживаемые providers
             │
             └──────── Spoolman
                       └── единая база катушек и расхода
```

Для Klipper/Moonraker Spoolman можно подключить напрямую:

```text
Ender / Klipper ── Moonraker ── Spoolman
```

Для Bambu Lab возможна отдельная связка:

```text
Bambu Lab ── Bambuddy ── Spoolman
                |
                └── Bambuddy Manager
                    Stable / Beta / Rollback
```

FoxForge — отдельный bridge-networked Umbrel package на порту `8283`. Текущая explicit-IP модель Bambu/Moonraker не требует host networking; discovery и Virtual Printer остаются отдельной будущей задачей с собственным network/physical validation.

Bambuddy — отдельный Umbrel package на порту `8280`.

Bambuddy Manager — companion package на порту `8282`, доступный через Umbrel App Proxy. Он управляет только установленным `my3d-bambuddy` и не передаёт Docker socket самому Bambuddy.

Printbuddy — отдельный host-networked Umbrel package на порту `8281`. Host networking соответствует upstream-рекомендации для Linux и позволяет LAN discovery, Bambu MQTT/FTPS/camera и Virtual Printer работать без Docker NAT. Обычная установка Printbuddy может работать параллельно с Bambuddy, FilaMan и Spoolman; одновременно включать несколько Virtual Printer/proxy-сервисов на одинаковых host-портах не следует.

Spoolman — отдельный bridge-networked Umbrel package на порту `7912`. SQLite-база, логи, кэш и автоматические backup-файлы сохраняются в `${APP_DATA_DIR}/data`. Spoolman не имеет собственной авторизации, поэтому порт не следует пробрасывать напрямую в интернет.
