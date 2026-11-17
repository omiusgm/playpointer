# Восстановление PlayPointer

Актуальная версия приложения — 0.2.9. Исходники macOS, Windows, ресурсы и сайт сохранены в этом репозитории.

## Получить исходники

```sh
git clone https://github.com/omiusgm/playpointer.git
cd playpointer
```

Чтобы продолжить разработку, откройте эту папку в Codex или другом редакторе. История прошлых версий доступна через Git.

## macOS

Нужны macOS 13 или новее, Xcode и Swift.

```sh
./scripts/build-app.sh
```

Приложение появится в `dist/PlayPointer.app`. Локальная подпись ad hoc может вызвать блокировку первого запуска на другом Mac. Релизный DMG для Apple Silicon и Intel находится в [Releases](https://github.com/omiusgm/playpointer/releases/tag/v0.2.9-preview).

## Windows

Нужен .NET SDK 10. Команда поддерживает кросс-сборку с Mac и Linux.

```sh
dotnet publish windows/PlayPointer.Windows.csproj -c Release -r win-x64 --self-contained true -o dist/playpointer-windows-x64
```

Для распространения упакуйте всю выходную папку вместе с `assets`. Готовый ZIP находится в [Releases](https://github.com/omiusgm/playpointer/releases/tag/v0.2.9-preview). Интерфейс, аудио и ввод Windows требуют проверки на Windows 11.

## Сайт и HTML для пересылки

Публичный сайт — [PlayPointer](https://playpointer-vibecodil.omiusgm.chatgpt.site/).

Исходники находятся в `website/dist`. Сайт работает как обычная статическая страница.

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory website/dist
```

После запуска откройте `http://127.0.0.1:8000/`.

Для сборки одного HTML-файла нужны Python 3.9+ и Node.js. Картинки, шрифты и WAV будут встроены в файл.

```sh
python3 scripts/export-site.py website/dist PlayPointer.html
```

Для обновления существующего ChatGPT Site используйте Sites и проект из `website/.openai/hosting.json`. Его ID — `appgprj_6aef4399bb748191afb9f17c63178cfa`. Откройте существующий проект через Sites, перенесите содержимое `website/dist` в его checkout и опубликуйте. Сохраните публичный доступ.

## Материалы разработки

[Архив материалов](https://github.com/omiusgm/playpointer/releases/download/v0.2.9-preview/PlayPointer-development-archive-20261117.zip) содержит исходные генерации изображений, промпты, локальные варианты кода и историю сайта. Файл `MANIFEST.json` внутри архива хранит SHA-256 каждого файла.

SHA-256 самого ZIP: `cb2c5d89519c9a7812fb58ed82ed48bfb1fa0dd18e8b40f816cce8c7b182a0a9`.

Текущая сборка приложения и сайта восстанавливается из основного репозитория. Для возврата к локальному черновику см. `local-drafts/index.json` внутри архива. В нём указаны базовый коммит и файлы, которые нужно наложить поверх него.

Настройки установленного приложения и личные пользовательские указатели хранятся отдельно от исходников.
