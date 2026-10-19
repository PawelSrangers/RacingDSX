# Specs

Спецификации поведения RacingDSX — источник истины для кода (ADR-0012, правила в
[AGENTS.md](../AGENTS.md#spec-driven-development)). Новая спецификация копирует
[`_template.md`](_template.md).

Все спецификации написаны 2026-10-19 по уже работающему поведению и пока в статусе `Draft`:
владелец переводит их в `Approved` после разбора открытых вопросов. Блокирующие вопросы
перечислены в разделе `Open questions` каждого файла.

| Feature ID | Спецификация | Что описывает | Требований | Статус |
|---|---|---|---|---|
| `TELEMETRY` | [telemetry-input.md](telemetry-input.md) | Приём телеметрии: порт, форматы пакетов, частота FH6, тишина потока, плохие данные | 7 | Draft |
| `OUTPUT` | [dsx-output.md](dsx-output.md) | Отправка в DSX: формат, лимит частоты, один пакет, дедупликация, удержание вибрации, сброс триггеров | 9 | Draft |
| `BRAKE` | [brake-trigger.md](brake-trigger.md) | Левый триггер: сопротивление, блокировка колёс, вибрация | 12 | Draft |
| `THROTTLE` | [throttle-trigger.md](throttle-trigger.md) | Правый триггер: сопротивление от ускорения, пробуксовка (старая логика по slip) | 6 | Draft |
| `LIGHTBAR` | [light-bar.md](light-bar.md) | Цвет световой панели по оборотам и классу машины | 5 | Draft |
| `APP` | [app-lifecycle.md](app-lifecycle.md) | App check, профили, запуск и остановка воркера, файл конфига | 9 | Draft |
| `UI` | [settings-ui.md](settings-ui.md) | Поведение настроек в окне: синхронизация, сохранение, подписи | 11 | Draft |
