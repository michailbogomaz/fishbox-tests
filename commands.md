run command {commandName} {commandParams} ты должен выполянть команды либо выдать сообжение "неизвестная комманда" : {commandName} {command params}
список команд :

1. commandName = check
   commandParams
   commits=N - натуральное число больше 0 по умолчанию 1
   autofix=0 [0,1] - автоматически исправлять тривиальные проблемы (например, опечатки в ключах helm, target ES2024, формат uuid-импорта), по умолчанию 0
   files=LIST - необязательный список путей через запятую; если указан, проверять только эти файлы
   strict=1 [0,1] - 1: падать на первой критической ошибке; 0: собрать полный отчёт, по умолчанию 0
   checkOnlyNumbers = 1,2,3,4,5 массив который гововит какие пунты только проверять из чеклиста если 1,4,40 - только 1 3 и 40, если не присутствует - то проверять все пункты

ПОВЕДЕНИЕ КОМАНДЫ CHECK:

- Всегда руководствоваться инструкциями из .cursor/checklist-instrusctions.md и .cursor/checklist.md. читать эти файлы нужно полностью, а не количество строк с лимитом
- Определение набора файлов, типы проверок (A/B/C), порядок и критерии — строго по инструкциям чеклиста.
- Параметры команды влияют только на область и политику выполнения (files/commits/autofix/strict), но не переопределяют логику из чеклиста.

Шаг 0. Инструкции и чеклист

— читать .cursor/checklist-instrusctions.md, .cursor/assistant-adjustments.md, .cursor/checklist.md из проекта читать эти файлы нужно полностью, а не количество строк с лимитом

- вывести количество пунктов чеклиста подтверждая загрузку

Примеры:
run command check commits=1
run command check commits=2 autofix=1 strict=0
run command check commits=1 autofix=1 strict=0 checkOnlyNumbers=11,7,8
run command check files=src/rating/rating.service.ts,src/rating/rating.controller.ts autofix=0
