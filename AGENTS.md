# AGENTS.md — WindUI Project Guide

Welcome to **WindUI**! This document provides an architectural overview, development guidelines, build workflows, and conventions for working with the codebase.

---

## 1. Project Overview

**WindUI** is a modern, modular UI library designed for Roblox scripts, exploiting hubs, and in-game developer interfaces. It provides a clean, Windows/Fluent-inspired user experience with:
- Windowing system with draggable panels, tabs, sections, and popups
- Rich interactive UI widgets (Buttons, Toggles, Sliders, Dropdowns, Colorpickers, Keybinds, Code views, Tags, Tooltips)
- Dynamic theme engine (light/dark themes, accent colors, acrylic blur effect via viewport rendering)
- Integrated Key System with third-party verification services (Luarmor, Platoboost, PandaDevelopment, JunkieDevelopment)
- Localization and custom icon pack support (Lucide, Craft, Geist, Solar, SF Symbols)

---

## 2. Directory Structure

```text
WindUI/
├── src/                          # Core Luau library source
│   ├── Init.lua                  # Primary entry point (WindUI table definition)
│   ├── components/               # Structural UI components
│   │   ├── KeySystem.lua         # Authentication / key verification dialog
│   │   ├── Notification.lua      # Toast notifications
│   │   ├── popup/                # Modal dialogs & popup menus
│   │   ├── search/               # Search overlay & icon searching
│   │   ├── ui/                   # Sub-components (Button, Checkbox, Dropdown, etc.)
│   │   └── window/               # Window frame, titlebar, tabs, sections
│   ├── config/                   # ConfigManager for saving/loading user settings
│   ├── elements/                 # Form elements & widgets
│   │   ├── Button.lua, Colorpicker.lua, Dropdown.lua, Input.lua,
│   │   ├── Keybind.lua, Slider.lua, Toggle.lua, Video.lua, etc.
│   │   └── Init.lua              # Elements registry and factory
│   ├── Icons/                    # Icon registries and font definitions
│   ├── modules/                  # Utilities & core helpers
│   │   ├── Creator.lua           # Roblox Instance factory & animation helper
│   │   ├── Dynamic3D.lua         # 3D tilt perspective rendering for menu frames
│   │   ├── DynamicShape.lua      # Responsive shape drawing
│   │   ├── Highlighter.lua       # Syntax highlighter for code blocks
│   │   ├── Icons.lua             # Icon asset resolver
│   │   └── Localization.lua     # Multi-language translation manager
│   ├── server/                   # Backend / server-side modules (PRs, Discord)
│   ├── themes/                   # Theme registry, default themes, fallback colors
│   └── utils/                    # Acrylic blur, services, verification APIs
├── build/                        # Build automation & bundling configs
│   ├── build.sh                  # Bash build script (Darklua bundler)
│   ├── build.ps1                 # PowerShell build script for Windows
│   ├── darklua.config.json       # Darklua production bundle configuration
│   ├── darklua.dev.config.json   # Darklua development bundle configuration
│   └── header.lua                # Output header template
├── dist/                         # Compiled distribution files
│   └── main.lua                  # Bundled single-file library for game injection
├── docs/                         # Asset media, banners, screenshots
├── tests/                        # Test scripts (200Elements.lua, ProgressBar.lua)
├── aftman.toml                   # Aftman toolchain (Rojo, Darklua, Lune)
├── default.project.json          # Rojo project mapping to Roblox DataModel
├── package.json                  # Node.js dependencies and scripts
└── main.client.lua               # Showcase and development client script
```

---

## 3. Technology Stack & Toolchain

- **Language**: [Luau](https://luau.org/) (Roblox Lua dialect with gradual typing)
- **Bundler**: [Darklua](https://darklua.com/) (`v0.17.1+`) — Bundles multi-file Luau packages via `path` require rules into a single output file `dist/main.lua`
- **Roblox Sync**: [Rojo](https://rojo.space/) (`v7.3.0+`) — Syncs workspace files into Roblox Studio places
- **Runtime Testing**: [Lune](https://lune-org.github.io/docs) (`v0.7.6+`) — Standalone Luau CLI runtime
- **Toolchain Manager**: [Aftman](https://github.com/LPGhatguy/aftman) — Manages Rojo, Darklua, and Lune binaries

---

## 4. Development & Build Commands

### Prerequisites
1. **Node.js**: `v18+` (npm dependencies: `chokidar-cli`, `concurrently`)
2. **Aftman** (or manually installed `darklua` & `rojo`):
   ```bash
   aftman install
   ```

### Build Commands
- **Install NPM Packages**:
  ```bash
  npm install
  ```
- **Build Distribution (`dist/main.lua`)**:
  - In Git Bash / Linux / macOS:
    ```bash
    npm run build
    ```
  - In Windows PowerShell:
    ```powershell
    .\build\build.ps1 build
    ```
- **Development / Watch Mode**:
  - In Windows PowerShell:
    ```powershell
    .\build\build.ps1 dev
    ```
- **Live Local Server**:
  ```bash
  npm run live
  ```

---

## 5. Coding Standards & Conventions

### Executor & Security Compatibility
- **Always use `cloneref`**: When accessing Roblox services, always wrap `game:GetService(...)` with `cloneref(...)` or use `WindUI.cloneref` / `Services` to prevent detection and reference manipulation:
  ```luau
  local cloneref = (cloneref or clonereference or function(instance) return instance end)
  local TweenService = cloneref(game:GetService("TweenService"))
  ```
- **Instance Creation**: Avoid naked `Instance.new(...)` calls in UI components. Use `Creator.New(className, properties, children)` from `src/modules/Creator.lua`.
- **Theming**: Do not hardcode raw colors (`Color3.fromRGB(...)`) in element backgrounds, texts, or borders unless explicitly intended as an override. Reference the active theme table (`WindUI.Theme`).
- **Signal Handling**: Store connection objects in element tables or cleanup handlers to prevent memory leaks upon window destruction.

---

## 6. How to Test & Preview

1. **In Roblox Studio**:
   - Run `rojo serve` to start the Rojo server.
   - Connect the Rojo plugin in Roblox Studio to sync `src/` to `ReplicatedStorage.WindUI` and `main.client.lua` to `StarterPlayerScripts`.
2. **In Game / Executor**:
   - Serve `dist/main.lua` locally via `npm run live` (or use GitHub raw URL).
   - Execute in client:
     ```luau
     loadstring(game:HttpGet("http://localhost:8642/dist/main.lua"))()
     ```

---

## 7. Строгие правила разработки (Mandatory Operational Rules)

### 1. Принцип «Сначала спроси»
- **НИКОГДА** не принимай самостоятельных решений, если в ТЗ есть двусмысленность, возникают трудности или вопросы по реализации.
- Лучше остановись и задай уточняющий вопрос пользователю. Любая самодеятельность при нехватке данных строго запрещена.

### 2. Максимальное делегирование (Subagents)
- **ВСЕГДА** и на максимум задействуй субагентов (`invoke_subagent`) для декомпозиции задач, планирования архитектуры, написания и ревью кода.
- Распределяй обязанности между специализированными агентами для достижения идеального качества.

### 3. Тотальный самоконтроль (Double-Check)
- **ВСЕГДА** перепроверяй весь написанный код, структуру и логику перед тем, как выдать финальный ответ.
- Тщательно проверяй синтаксис (Luau/Lua), отсутствие пропущенных запятых, скобок, опечаток и логических несостыковок.

### 4. Чистый визуальный стиль (Анти-AI дизайн)
- **Категорически НЕ ИСПОЛЬЗУЙ «ИИ слоп» (AI slop)** в дизайне интерфейсов.
- Никаких перегруженных градиентов, неуместных неоновых свечений, избыточных закруглений всего подряд и вырвиглазных анимаций, если об этом не попросили напрямую.
- Дизайн должен быть чистым, строгим, аккуратным, минималистичным и ориентированным на максимальную юзабельность.

### 5. Фокус только на UI (Без бэкенда/функционала)
- **Мы пишем только визуальную оболочку.** Это UI-библиотека интерфейса, а не игровой эксплоит или игровой функционал.
- Не пытайся писать реальный геймплейный функционал или логику для читов/хаков.
- *Пример*: если требуется добавить тагл `WalkSpeed` в пример, создается **только визуальный переключатель** (UI-компонент с пустым/декоративным коллбэком), без попыток модифицировать скорость персонажа в игре.

