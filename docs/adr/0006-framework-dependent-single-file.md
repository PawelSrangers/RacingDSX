# ADR-0006: Сборка — framework-dependent single-file exe

- **Статус:** Принят
- **Дата:** 2026-09-09
- **Затронуто:** процесс сборки; `RacingDSX.csproj` не менялся

## Relations

- Depends-on: 0013
- Supersedes: none
- Constrains: 0010
- Related: 0007

## Контекст

У пользователя был exe из апстрим-релиза: `RacingDSX.exe` (~3.6 МБ), `RacingDSX.dll.config`,
`RacingDSX.json`. README апстрима требует установленный .NET 8. Значит, релиз
framework-dependent single-file. Это совпадает с `Properties/PublishProfiles/FolderProfile.pubxml`
(`SelfContained=false`, `PublishSingleFile=true`, `PublishReadyToRun=true`).

При этом в самом `RacingDSX.csproj` для конфигурации Release зашито `SelfContained=true`.
Простой `dotnet publish -c Release` даёт self-contained сборку на ~70 МБ, которая по составу
не совпадает с тем, что стоит у пользователя.

На машине был только .NET runtime, без SDK. С согласия пользователя установлен
.NET 8 SDK 8.0.425 через winget.

## Решение

Сборка выполняется так, чтобы точно повторять раскладку апстрим-релиза:

```
dotnet publish RacingDSX_source/RacingDSX.csproj -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -p:PublishReadyToRun=true -o <outdir>
```

Развёртывание: в `RacingDSX_exe/` копируются только `RacingDSX.exe` и `RacingDSX.dll.config`.
`RacingDSX.json` — живой настроенный конфиг пользователя, он **никогда не перезаписывается**,
в него только добавляются новые поля. Перед первой заменой оригинал сохранён в
`RacingDSX_exe/backup_original/`.

## Рассмотренные варианты

| Вариант | Почему нет |
|---|---|
| Self-contained (как в csproj) | В 20 раз больше, отличается от того, что у пользователя, а .NET 8 у него и так стоит. |
| Исправить `SelfContained` в csproj | Расходится с апстримом без пользы. Явный флаг в команде нагляднее и ничего не ломает. |
| Обычный build без single-file | Пачка DLL рядом с exe вместо одного файла, другая раскладка. |

## Последствия

- Новый exe подменяет старый один к одному, пользователю ничего не нужно переустанавливать.
- Для работы нужен установленный .NET 8 Desktop Runtime, как и раньше.
- Предупреждения сборки `MSB4011`, `CS0108`, `CS0219` достались от апстрима и безвредны. Их
  намеренно не трогаем, чтобы не расходиться с апстримом.
- Git-репозитория нет. Откат — только через `backup_original/` и `*.bak`, поэтому любую
  замену файла нужно предварять резервной копией.

## Обновление 2026-10-11

Исходники теперь в git: первый коммит (тег `upstream-0.6.7`) — оригинал, дальше наши изменения.
Пункт о том, что откат возможен только через `backup_original/` и `*.bak`, теперь относится
лишь к собранному exe: папка `RacingDSX_exe/` намеренно исключена из git, чтобы никакой
checkout не мог перезаписать живой конфиг пользователя. Перед заменой exe предыдущий
сохраняется в `RacingDSX_exe/backup_prev/`.
