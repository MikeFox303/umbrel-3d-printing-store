# 3D Printing Community App Store для Umbrel

Неофициальный Store для программ 3D-печати. Первый пакет — FilaMan от Fire-Devils с русской локализацией.

## Установка

1. Запустите GitHub Actions `Build RU image` в репозитории `MikeFox303/filaman-system-ru` с тегом `1.2.42-ru.1`.
2. Получите digest: `docker buildx imagetools inspect ghcr.io/mikefox303/filaman-system-ru:1.2.42-ru.1`.
3. Замените `REPLACE_WITH_PUBLISHED_DIGEST` в `my3d-filaman/docker-compose.yml` на полученный SHA256 digest и закоммитьте изменение.
4. В UmbrelOS добавьте URL этого GitHub-репозитория как Community App Store и установите FilaMan.

Пакет нельзя устанавливать до подстановки digest. Он намеренно не использует `latest`.

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
