# 3D Printing Community App Store для Umbrel

Неофициальный Store для программ 3D-печати. Первый пакет — FilaMan от Fire-Devils с русской и украинской локализациями.

## Установка

1. В UmbrelOS добавьте URL этого GitHub-репозитория как Community App Store.
2. Установите FilaMan из раздела 3D Printing.

Package закреплён на опубликованном multi-architecture SHA256 digest и намеренно не использует `latest`.

## Автоматические обновления

UmbrelOS проверяет зарегистрированные Community Store каждые 5 минут. Удалять и повторно добавлять этот Store не нужно. После успешной сборки ветки `main` репозитория [MikeFox303/filaman-system](https://github.com/MikeFox303/filaman-system) workflow этого Store автоматически получает immutable digest, повышает версию пакета и публикует обновление. Затем Umbrel показывает обычную кнопку обновления приложения; каталог данных и ID `my3d-filaman` не меняются.

Обновления официального [Fire-Devils/filaman-system](https://github.com/Fire-Devils/filaman-system) поступают в локализованный репозиторий отдельным pull request. Проверки блокируют публикацию, если в русском или украинском словаре отсутствуют ключи либо изменены placeholders.

## Данные, обновление и backup

Данные Umbrel хранятся в `${APP_DATA_DIR}/data` и не попадают в Git. Перед крупным обновлением рекомендуется создать backup данных. Обычное обновление через Umbrel не меняет каталог данных.

## Переход с Dockge

1. Убедитесь, что старая и новая версии FilaMan совместимы; безопаснее начать с той же upstream-версии `1.2.42`.
2. На Umbrel host скопируйте `scripts/backup-dockge-filaman.sh` и запустите его после остановки старого FilaMan. Скрипт определяет фактический `/app/data` mount через `docker inspect`, создаёт tar.gz и SHA256, ничего не удаляет.
3. Один раз установите Umbrel App, затем остановите его.
4. Запустите `scripts/migrate-dockge-filaman.sh`. Скрипт требует существующий backup, проверяет остановку обоих контейнеров, создаёт backup непустого destination, копирует данные и ждёт `/health`.
5. Проверьте login, русский интерфейс, катушки, API и restart. До подтверждения не удаляйте Dockge stack, Docker volume или backup archive.

## Rollback

1. Stop Umbrel FilaMan.
2. Не изменяйте исходный Dockge volume.
3. Start Dockge FilaMan.
4. Проверьте UI и данные.

Не запускайте старую версию поверх базы, которую уже обновила более новая FilaMan version: rollback всегда использует исходный, неизменённый Dockge volume.
