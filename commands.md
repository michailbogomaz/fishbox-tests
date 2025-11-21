run command {commandName} {commandParams} ты должен выполянть команды либо выдать сообжение "неизвестная комманда" : {commandName} {command params}
список команд :

1. commandName = check
   commandParams
   commits=N - натуральное число больше 0 по умолчанию 1
   reload=0 [0,1] - нужно ли скачивать и обновлять инструкции, по умолчанию 0
   autofix=0 [0,1] - автоматически исправлять тривиальные проблемы (например, опечатки в ключах helm, target ES2024, формат uuid-импорта), по умолчанию 0
   files=LIST - необязательный список путей через запятую; если указан, проверять только эти файлы
   strict=1 [0,1] - 1: падать на первой критической ошибке; 0: собрать полный отчёт, по умолчанию 0

ПОВЕДЕНИЕ КОМАНДЫ CHECK:

- Всегда руководствоваться инструкциями из .cursor/checklist-instrusctions.md и .cursor/checklist.md.
- Если reload=1, предварительно обновить указанные файлы инструкций.
- Определение набора файлов, типы проверок (A/B/C/D/E), порядок и критерии — строго по инструкциям чеклиста.
- Параметры команды влияют только на область и политику выполнения (files/commits/reload/autofix/strict), но не переопределяют логику из чеклиста.

Шаг 0. Инструкции и чеклист

- если reload=1:
  - curl -sL "https://docs.google.com/spreadsheets/d/e/2PACX-1vT_8pz73L4Ku6Uz3qZBfCkndVcX7ORLYfZy46Peqm6nl3d0LD1dF4ckEmPaxjNBwywcHBgPvopX0fh9/pub?gid=0&single=true&output=csv" > .cursor/checklist-instrusctions.md
  - скачать все чеклисты из URL, перечисленных в инструкциях, и сохранить в .cursor/checklist.md
  - если нет каталога .cursor — создать и добавить в .gitignore
- если reload=0 — читать .cursor/checklist-instrusctions.md и .cursor/checklist.md из проекта
- вывести чеклист (коротким фрагментом, подтверждая загрузку)

Примеры:
run command check commits=1 reload=0
run command check commits=2 reload=1 autofix=1 strict=0
run command check commits=1 reload=0 autofix=1 strict=0
run command check files=src/rating/rating.service.ts,src/rating/rating.controller.ts reload=0 autofix=0
