---
description: Проверка коммита по чеклистам перед PR
---

# Команда check

## Параметры

- `commits=N` — количество коммитов для проверки (по умолчанию 1)
- `autofix=0|1` — автоисправление тривиальных проблем (по умолчанию 1)
- `files=LIST` — список файлов через запятую (если указан, проверять только их)
- `strict=0|1` — 1: падать на первой ошибке; 0: полный отчёт (по умолчанию 0)
- `checkOnlyNumbers=1,2,3` — проверять только указанные пункты чеклиста
- `detailedReport=0|1` — 1: подробный отчёт; 0: агрегированный (по умолчанию 1)
- `instructions=fast` — постфикс файла инструкций (по умолчанию 'fast')
- `type=A,B,C` — типы проверок в порядке выполнения (по умолчанию только A)

## Алгоритм

1. Прочитать `.cursor/checklist-instrusctions_{instructions}.md`
2. Для каждого типа из `type`:
   - Прочитать `.cursor/checklist-instrusctions_{instructions}_type-{type}.md`
   - Выполнить чеклист `.cursor/checklist-type-{type}.md`
   - Завершить текущий тип перед переходом к следующему

## Примеры

```
run command check commits=1
run command check commits=2 autofix=1 strict=0
run command check commits=1 checkOnlyNumbers=11,7,8
run command check files=src/rating/rating.service.ts autofix=0
run command check commits=2 type=A,B,C strict=0
```
