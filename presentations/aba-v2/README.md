# Презентация для ABA-куратора (v2)

Папка содержит графичную версию презентации для обсуждения проекта PLANKA с ABA-куратором и другими участниками принятия решений.

## Состав
- `index.html` — интерактивный deck (стрелки, кнопки).
- `styles.css` — визуальный стиль и печатный режим.
- `slides.js` — навигация по слайдам.
- `mermaid/mission-map.mmd` — карта ценности продукта.
- `mermaid/mvp-roadmap.mmd` — дорожная карта MVP/V1+.

## Запуск web-версии
1. Открой `presentations/aba-v2/index.html` в браузере.
2. Листай кнопками или клавишами `←/→`.

## Экспорт в PDF из браузера
1. Открой `index.html`.
2. `Print` -> `Save as PDF`.
3. Включи landscape-ориентацию.

## Экспорт Mermaid в PDF
Требуется `@mermaid-js/mermaid-cli` (`mmdc`):

```bash
npx -y @mermaid-js/mermaid-cli -i presentations/aba-v2/mermaid/mission-map.mmd -o presentations/aba-v2/mermaid/mission-map.pdf
npx -y @mermaid-js/mermaid-cli -i presentations/aba-v2/mermaid/mvp-roadmap.mmd -o presentations/aba-v2/mermaid/mvp-roadmap.pdf
```

