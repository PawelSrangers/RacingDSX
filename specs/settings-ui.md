# Spec: Settings UI

- Status: Draft
- Feature ID: UI
- Owner: abramovdima1998 (владелец репозитория)
- Related ADRs: 0004, 0005, 0010, 0013
- Related specs: specs/brake-trigger.md, specs/throttle-trigger.md, specs/light-bar.md, specs/app-lifecycle.md

## Problem

Настройки триггеров и лайтбара пользователь меняет в окне RacingDSX (вкладки Misc, Brake
Trigger, Throttle Trigger), а хранятся они в `RacingDSX.json`, который пользователь
подстраивал под себя месяцами. В апстриме окно портило конфиг: числовое поле жёсткости
тормоза читало поле вибрации, и при каждом запуске `MinStiffness`/`MaxStiffness`
перезаписывались значениями `MinVibration`/`MaxVibration` (ADR-0010). Подписи вкладки Brake
не соответствовали тому, что делает код, а список исполняемых файлов раз в секунду
сбрасывал выделение на первый элемент. Интерфейс был покрашен в тёмную тему не полностью, и
часть подписей была не видна (ADR-0005).

Спецификация фиксирует уже исправленное поведение окна настроек.

## Goals

- Ползунок и числовое поле каждой настройки всегда показывают одно значение и меняют только
  свою настройку.
- Запуск программы не меняет сохранённые значения.
- Подпись каждой настройки описывает то, что она действительно делает.
- Окно читаемо целиком и не «дёргается» само по себе.

## Non-goals / Out of scope

- Новые элементы управления. `UI.Designer.cs` без Visual Studio не редактируется; новые
  настройки добавляются только в `RacingDSX.json` (например, `DSXUpdateRateHz`, ADR-0001).
- Что именно делает каждая настройка с триггерами и лайтбаром — `specs/brake-trigger.md`,
  `specs/throttle-trigger.md`, `specs/light-bar.md`. Здесь только связь «элемент UI ↔ ключ
  конфига» и сохранение.
- Профили, AppCheck и выбор активного профиля как процесс — `specs/app-lifecycle.md`.
  Здесь только видимое следствие для списка исполняемых файлов (REQ-UI-009).
- Конкретная цветовая тема. Решение «стандартная светлая тема Windows, без покраски отдельных
  контролов» — это *как*, оно записано в ADR-0005 и меняется новым ADR. Спецификация требует
  только *что* видит пользователь: всё читаемо и единообразно (REQ-UI-011). Так тёмная тема,
  сделанная на уровне формы, как допускает ADR-0005, не потребует менять спецификацию, а
  возврат частичной покраски апстрима её нарушит.
- Локализация интерфейса: подписи на английском, как в апстриме.

## Requirements

### REQ-UI-001: Ползунок и числовое поле синхронны

- Status: Active
- Description: У каждой настройки с парой «ползунок + числовое поле» (список в Constraints)
  изменение одного элемента MUST сразу выставлять то же значение в другом и в ключе конфига
  этой настройки. Ввод в числовое поле любого значения из его допустимого диапазона MUST NOT
  приводить к ошибке.
- Acceptance criteria:
  - Given открыта вкладка Brake Trigger, when ползунок «Stiffness at Full Brake» сдвинут на
    120, then числовое поле рядом показывает 120; when в поле введено 60, then ползунок стоит
    на 60.
  - То же для каждой пары из таблицы Constraints на вкладках Misc, Brake Trigger, Throttle
    Trigger.
  - Проверка: нет автоматической проверки. Вручную, со снимками
    `tools/screenshot_ui.ps1 -RelX 340 -RelY 66` (Brake), `-RelX 470` (Throttle),
    `-RelX 240` (Misc). Известное нарушение для «Vibration Smoothing» тормоза — OQ-2.

### REQ-UI-002: Каждый элемент меняет только свою настройку

- Status: Active
- Description: Обработчик каждого ползунка, числового поля и выпадающего списка MUST
  записывать значение только в свой ключ `RacingDSX.json` (таблица в Constraints) и
  обновлять только свою пару элементов. Ни один элемент MUST NOT читать значение из
  элемента другой настройки.
- Acceptance criteria:
  - Given в конфиге `MinStiffness` = 150, `MaxStiffness` = 5, `MinVibration` = 15,
    `MaxVibration` = 20, when пользователь меняет только «Min Brake Vibration» на 10 и
    нажимает Apply, then в файле изменился только `MinVibration`; `MinStiffness` и
    `MaxStiffness` по-прежнему 150 и 5.
  - Given любой элемент из таблицы, when он изменён и нажат Apply, then в
    `RacingDSX.json` отличается от исходного только соответствующий ключ.
  - Проверка: нет автоматической проверки. Вручную: сравнение `RacingDSX.json` в песочнице
    до и после.

### REQ-UI-003: Запуск не меняет сохранённые значения

- Status: Active
- Description: Запуск программы и показ профиля MUST NOT менять значения настроек, если они
  лежат в диапазоне своего элемента и заданы с его точностью (целые для целочисленных
  настроек, сотые доли для долей). Это относится ко всем профилям, а не только к
  показанному. Известные исключения, которые код делает сейчас: `EffectIntensity` больше 1.0
  ужимается до 1.0, доли с точностью выше сотых отбрасываются до сотых (см. OQ-4).
- Acceptance criteria:
  - Given конфиг пользователя (например, Forza: `MinStiffness` 150, `MaxStiffness` 5,
    `MinVibration` 15, `MaxVibration` 20, `VibrationModeStart` 30), when программа запущена,
    показан профиль, затем без изменений нажат Apply на вкладке Brake Trigger, then все
    ключи `brakeSettings` и `throttleSettings` в файле равны исходным.
  - Given тот же сценарий, повторённый трижды подряд, then значения не «дрейфуют».
  - Проверка: нет автоматической проверки. Вручную в песочнице (копия exe и конфига во
    временной папке), сравнение JSON до и после.

### REQ-UI-004: Сохранение в RacingDSX.json

- Status: Active
- Description: Настройки MUST читаться из `RacingDSX.json` в рабочей папке программы и
  записываться туда же. Запись MUST происходить по кнопкам Apply и Defaults любой вкладки,
  при переключении пунктов меню статус-бара (Verbose Mode, App Check, DSX Port), при
  операциях над профилями (New, Rename, Enable/Disable, Delete, Default, Set Active) и при
  смене активного профиля. Ключи, которых нет в старом файле, MUST получать значения по
  умолчанию и дописываться при первой записи; существующие ключи MUST NOT удаляться или
  переименовываться. Закрытие окна файл MUST NOT записывает: несохранённые изменения
  теряются (если до этого не произошла одна из записей выше, см. OQ-3).
- Acceptance criteria:
  - Given `RacingDSX.json` без ключа `DSXUpdateRateHz`, when программа запущена, then после
    запуска ключ есть в файле со значением 30, остальные значения прежние.
  - Given изменён ползунок без Apply, when окно закрыто и программа запущена снова (и
    активный профиль за это время не менялся), then показано старое значение.
  - Проверка: нет автоматической проверки.

### REQ-UI-005: Изменения активного профиля действуют сразу

- Status: Active
- Description: Если в окне показан активный профиль, изменение любой настройки триггеров или
  лайтбара MUST влиять на команды DSX с ближайшего кадра телеметрии, без нажатия Apply и без
  перезапуска. Apply MUST только сохранять на диск (и для вкладки Misc — обновлять список
  исполняемых файлов для AppCheck).
- Acceptance criteria:
  - Given идёт телеметрия, показан активный профиль Forza, when ползунок «Max Resistance»
    тормоза перемещён с 7 на 0, then следующие команды левого триггера в режиме
    сопротивления имеют силу, стремящуюся к 0, ещё до нажатия Apply.
  - Проверка: нет автоматической проверки.

### REQ-UI-006: Подписи вкладки Brake Trigger соответствуют поведению

- Status: Active
- Description: Подписи настроек тормоза MUST описывать их действие (ADR-0010):
  «Stiffness at Full Brake» — `MinStiffness` (жёсткость вибрации при полном тормозе),
  «Stiffness at Light Brake» — `MaxStiffness` (при лёгком), «Vibration Mode Start» —
  `VibrationModeStart` (минимальное нажатие 0–255 для вибрации при блокировке),
  «Min/Max Brake Vibration» — `MinVibration`/`MaxVibration` (частота вибрации, шкала по
  числу заблокированных колёс), «Min/Max Resistance» — сила сопротивления при тормозе 0 и
  255, «Grip Loss (not used)» — `GripLossValue`, не влияет ни на что. Ключи конфига MUST
  оставаться прежними, чтобы старые файлы читались без потерь.
- Acceptance criteria:
  - Given открыта вкладка Brake Trigger, then на снимке видны ровно эти подписи.
  - Проверка: `tools/screenshot_ui.ps1 -RelX 340 -RelY 66 -OutFile brake.png` и просмотр
    снимка (ручная). Точность подписи «Min Brake Vibration» — OQ-2 в
    `specs/brake-trigger.md`; подписи газа — OQ-4 в `specs/throttle-trigger.md`.

### REQ-UI-007: Поле Grip Loss тормоза отключено

- Status: Active
- Description: Ползунок и числовое поле «Grip Loss (not used)» на вкладке Brake Trigger MUST
  быть неактивными (серыми, недоступными для ввода) и показывать значение
  `brakeSettings.GripLossValue` из конфига. Значение MUST сохраняться в файле без изменений.
- Acceptance criteria:
  - Given открыта вкладка Brake Trigger, then оба элемента Grip Loss серые и не реагируют на
    клик и колесо мыши.
  - Given `GripLossValue` = 0.05 в конфиге, when программа запущена и нажат Apply, then в
    файле по-прежнему 0.05.
  - Проверка: `tools/screenshot_ui.ps1 -RelX 340 -RelY 66` (ручная).

### REQ-UI-008: Минимальное сопротивление тормоза не больше максимального

- Status: Active
- Description: На вкладке Brake Trigger «Min Resistance» MUST NOT становиться больше
  текущего «Max Resistance», а «Max Resistance» — меньше «Min Resistance»: попытка выставить
  такое значение MUST останавливать элемент на значении другой границы.
- Acceptance criteria:
  - Given Max Resistance = 4, when Min Resistance выставляется на 6, then Min Resistance
    становится 4 и в ползунке, и в поле, и в конфиге.
  - Проверка: нет автоматической проверки. На вкладке газа такого ограничения нет — OQ-5.

### REQ-UI-009: Выделение в списке исполняемых файлов не сбрасывается само

- Status: Active
- Description: Пока активный профиль не меняется (игра не запускалась и не закрывалась,
  профиль не переключался вручную), система MUST NOT перестраивать список исполняемых файлов
  на вкладке Misc, сбрасывать в нём выделение, перезаписывать `RacingDSX.json` или
  перезапускать обработку телеметрии. Это MUST выполняться и тогда, когда AppCheck
  проверяет процессы каждую секунду, а игра не запущена.
- Acceptance criteria:
  - Given AppCheck включён, игра не запущена, на вкладке Misc выбран второй элемент списка
    «Executables To Match», when проходит 10 с, then выбран всё тот же второй элемент, а
    время изменения `RacingDSX.json` не менялось.
  - Проверка: `tools/screenshot_ui.ps1 -RelX 240 -RelY 66` в начале и через 10 с (ручная), и
    время изменения файла.

### REQ-UI-010: Кнопки Defaults

- Status: Active
- Description: Кнопка Defaults на вкладке Brake Trigger MUST вернуть все `brakeSettings`
  показанного профиля к значениям по умолчанию (`specs/brake-trigger.md`, Constraints), на
  вкладке Throttle Trigger — все `throttleSettings` (`specs/throttle-trigger.md`), обновить
  элементы и сохранить файл. Другие профили и другие вкладки MUST NOT меняться. Кнопка
  Defaults на вкладке Misc MUST вернуть `RPMRedlineRatio` к 0.9 и порт игры
  (`gameUDPPort`) к 5300 — порту, на который Forza шлёт телеметрию по умолчанию.
- Acceptance criteria:
  - Given профиль Forza с изменёнными настройками тормоза и газа, when нажата Defaults на
    вкладке Brake Trigger, then `brakeSettings` профиля Forza в файле равны значениям по
    умолчанию, а `throttleSettings` и профиль Dirt не изменились.
  - Given порт игры 9999, when нажата Defaults на вкладке Misc, then поле порта показывает
    5300, `gameUDPPort` профиля в файле — 5300, `RPMRedlineRatio` — 0.9.
  - Проверка: нет автоматической проверки.

### REQ-UI-011: Окно читаемо и единообразно

- Status: Active
- Description: Все подписи, заголовки групп, вкладки, кнопки и строка состояния MUST быть
  читаемыми (контрастный текст на фоне). Форма, полоса вкладок и строка состояния MUST быть в
  одной цветовой схеме. Отдельные контролы MUST NOT иметь цвет, выбивающийся из схемы окна.
  Конкретная схема определяется ADR-0005 (сейчас стандартная светлая тема Windows).
- Acceptance criteria:
  - Given программа запущена, when сделаны снимки всех четырёх вкладок (Misc, Brake Trigger,
    Throttle Trigger, Output), then на каждом виден заголовок «Profiles», все подписи
    настроек и кнопки; нет тёмного фона формы при светлой полосе вкладок или наоборот.
  - Проверка: `tools/screenshot_ui.ps1` с `-RelX` 240, 340, 470, 578 и `-RelY 66` (ручной
    просмотр снимков).

## Constraints

Элементы и ключи из `UI.cs` и `UI.Designer.cs` на 2026-10-19. «/100» — в конфиге хранится
значение элемента, делённое на 100. Числовое поле без явных границ в дизайнере имеет
диапазон WinForms по умолчанию 0–100.

Вкладка Misc (ключи профиля):

| Подпись | Ключ | Ползунок | Поле |
|---|---|---|---|
| RPM Redline Ratio | `RPMRedlineRatio` (/100) | 0–100 | 0–100 |
| Game Port | `gameUDPPort` | — | 0–65353 |
| UDP Mode | `GameType` ((None)/Forza/Dirt) | список | — |
| Executables To Match | `executableNames` | список + Add/Edit/Remove | — |

Вкладка Brake Trigger (`brakeSettings`):

| Подпись | Ключ | Ползунок | Поле |
|---|---|---|---|
| Brake Trigger Mode | `TriggerMode` (Off/Resistance/Vibration) | список | — |
| Effect Intensity | `EffectIntensity` (/100) | 0–100 | 0–100 |
| Grip Loss (not used) | `GripLossValue` (/100) | 0–100, отключён | 0–100, отключено |
| Vibration Start | `VibrationStart` | 0–255 | 0–255 |
| Vibration Mode Start | `VibrationModeStart` | 0–255 | 0–255 |
| Min Brake Vibration | `MinVibration` | 0–100 | 0–100 |
| Max Brake Vibration | `MaxVibration` | 0–100 | 0–100 |
| Vibration Smoothing | `VibrationSmoothing` (/100) | 1–100 | 1–500 (OQ-2) |
| Stiffness at Full Brake | `MinStiffness` | 1–255 | 1–255 |
| Stiffness at Light Brake | `MaxStiffness` | 1–255 | 1–255 |
| Min Resistance | `MinResistance` | 0–7 | 0–7 |
| Max Resistance | `MaxResistance` | 0–7 | 0–7 |
| Resistance Smoothing | `ResistanceSmoothing` (/100) | 1–100 | 1–100 |

Вкладка Throttle Trigger (`throttleSettings`):

| Подпись | Ключ | Ползунок | Поле |
|---|---|---|---|
| Throttle Trigger Mode | `TriggerMode` (Off/Resistance/Vibration) | список | — |
| Effect Intensity | `EffectIntensity` (/100) | 0–100 | 0–100 |
| Grip Loss Value | `GripLossValue` (/100) | 0–100 | 0–100 |
| Turn Accel Scale | `TurnAccelerationScale` (/100) | 0–100 | 0–100 |
| Forward Accel Scale | `ForwardAccelerationScale` (/100) | 0–100 | 0–100 |
| Accel Limit | `AccelerationLimit` | 0–255 | 0–255 |
| Vibration Mode Start | `VibrationModeStart` | 0–255 | 0–255 |
| Min Throttle Vibration | `MinVibration` | 0–100 | 0–100 |
| Max Throttle Vibration | `MaxVibration` | 0–100 | 0–100 |
| Vibration Smoothing | `VibrationSmoothing` (/100) | 1–100 | 1–100 |
| Min Throttle Stiffness | `MinStiffness` | 1–255 | 1–255 |
| Max Throttle Stiffness | `MaxStiffness` | 1–255 | 1–255 |
| Min Throttle Resistance | `MinResistance` | 0–7 | 0–7 |
| Max Throttle Resistance | `MaxResistance` | 0–7 | 0–7 |
| Resistance Smoothing | `ResistanceSmoothing` (/100) | 1–100 | 1–100 |

Строка состояния: Verbose Mode (`VerboseLevel`), DSX Port (`DSXPort`), App Check
(`DisableAppCheck`). Только в файле, без элемента UI: `DSXUpdateRateHz`, `DefaultProfile`
(меняется через контекстное меню профиля).

- Активный профиль проверяется AppCheck раз в 1000 мс; ни одна видимая реакция окна или
  запись файла не должна повторяться с этим периодом, пока профиль не меняется (REQ-UI-009).
- Конфиг читается по относительному пути: какая папка рабочая, тот файл и используется.

## Open questions

- **OQ-1 (решён 2026-10-19):** кнопка Defaults на вкладке Misc ставила порт игры 9999
  (поведение апстрима), и после нажатия телеметрия переставала приниматься. Владелец выбрал
  5300 (REQ-UI-010).
- **OQ-2 (non-blocking):** числовое поле «Vibration Smoothing» тормоза допускает 1–500
  (`UI.Designer.cs:731`), а ползунок — только 1–100 (`UI.Designer.cs:965`). При вводе
  101–500 обработчик (`UI.cs:713-717`) сначала записывает в конфиг `VibrationSmoothing` > 1.0,
  затем падает на присвоении ползунку (`ArgumentOutOfRangeException`). Нарушает REQ-UI-001.
  Коэффициент сглаживания > 1.0 к тому же даёт перерегулирование частоты.
- **OQ-3 (non-blocking):** изменения без Apply не сохраняются при закрытии окна
  (`UI_FormClosing`, `UI.cs:335-342`, записи нет), но молча сохраняются при любой следующей
  записи файла, например когда AppCheck обнаружит запуск или закрытие игры и сменит активный
  профиль (`UI.cs:203-204`). Итог зависит от того, запускалась ли игра, — пользователь не
  может это предсказать. Нужно решить: сохранять всегда сразу, только по Apply или при
  закрытии.
- **OQ-4 (non-blocking):** исключения из REQ-UI-003. `SwitchDisplayedProfile` при каждом
  показе профиля ужимает `EffectIntensity` до [0, 1] (`UI.cs:460-461`), а доли проходят
  через `floor(x × 100) / 100` (`UI.cs:528-539` и обработчики числовых полей), так что
  значение вроде 0.055, вписанное в файл руками, превращается в 0.05 при первой записи.
  Значения вне диапазона элемента (например, `MaxVibration` = 150) вызывают исключение при
  присвоении ползунку в `SwitchDisplayedProfile` (`UI.cs:474`), которое вызывается вне
  `try` (`UI.cs:379`). Что должно происходить с такими значениями — не определено.
- **OQ-5 (non-blocking):** ограничение Min ≤ Max сопротивления есть только у тормоза
  (`UI.cs:757-812`). На вкладке газа «Min Throttle Resistance» можно сделать больше «Max»
  (`UI.cs:1029-1063`), и тогда сопротивление газа убывает с ускорением. То же касается пар
  Min/Max Vibration и Stiffness на обеих вкладках, где это может быть намеренно (у тормоза
  `MinStiffness` > `MaxStiffness` по умолчанию). Нужно ли единое правило?
- **OQ-6 (non-blocking):** максимум поля «Game Port» — 65353 (`UI.Designer.cs:384`), а не
  65535; порты 65354–65535 выбрать нельзя. Похоже на опечатку апстрима.

## Changelog

| Date | PR | Change |
|------|----|--------|
| 2026-10-19 | — (нет remote) | Первая версия: описано уже работающее поведение |
| 2026-10-19 | — (нет remote) | OQ-1 решён владельцем: Misc → Defaults ставит порт 5300 (REQ-UI-010) — breaking |
