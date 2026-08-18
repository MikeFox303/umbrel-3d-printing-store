# 3D Printing Community App Store для Umbrel

Неофициальный Store для программ 3D-печати. Первый пакет — FilaMan от Fire-Devils с русской локализацией.

## Установка

1. В UmbrelOS добавьте URL этого GitHub-репозитория как Community App Store.
2. Установите FilaMan из раздела 3D Printing.

Package закреплён на опубликованном SHA256 digest и намеренно не использует `latest`.

## Данные, обновление и backup

Данные Umbrel хранятся в `${APP_DATA_DIR}/data` и не попадают в Git. Для обновления сначала создавайте backup данных. При обновлении RU fork выполните `git fetch upstream` и `git rebase upstream/main`, затем `npm run check:i18n`; новые ключи переводятся вручную.

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
