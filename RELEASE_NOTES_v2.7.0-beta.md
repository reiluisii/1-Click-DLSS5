# ⚡ 1-Click DLSS 5 — Release Notes (v2.7.0-beta)
### **Universal Neural Control Center • RTX 20/30/40/50 Series**

---

## 🇧🇷 Português

### 🌟 Destaques da Versão v2.7.0-beta
A versão **v2.7.0-beta** expande as fronteiras do **1-Click DLSS 5**, trazendo suporte nativo para **Emuladores de todas as gerações de consoles**, um **Sistema de Telemetria e Auditoria Forense Contínua** de nível corporativo no arquivo de log, rastreamento passo a passo de todas as ações do usuário na interface, resolução do erro de **DX12 RHI / Seleção de GPU no Windows 11**, carregamento instantâneo com **varredura em segundo plano e cache persistente**, e detecção automática do **idioma do sistema operacional**.

---

### 🕹️ 1. Suporte Universal a Emuladores (PlayStation, Nintendo, Xbox, Retro)
* **Reconhecimento Nativo e Injeção Otimizada para mais de 12 Plataformas:**
  * **PlayStation 1:** DuckStation (`duckstation-qt-x64-ReleaseLTCG.exe`, `duckstation-nogui.exe`), ePSXe, Beetle/Mednafen.
  * **PlayStation 2:** PCSX2 (`pcsx2-qtx64-avx2.exe`, `pcsx2-qtx64.exe`, `pcsx2.exe`).
  * **PlayStation 3:** RPCS3 (`rpcs3.exe`).
  * **PlayStation 4 & PS Vita:** shadPS4 (`shadps4.exe`), Vita3K (`vita3k.exe`).
  * **Nintendo Switch:** Ryujinx (`Ryujinx.exe`, `Ryujinx.Ava.exe`), Yuzu, Suyu, Eden, Torzu.
  * **Nintendo Wii & GameCube:** Dolphin (`Dolphin.exe`, `DolphinWx.exe`).
  * **Nintendo Wii U:** Cemu (`Cemu.exe`).
  * **Nintendo 3DS:** Citra (`citra-qt.exe`), Lime3DS (`lime3ds.exe`), Azahar.
  * **Nintendo DS & GBA:** melonDS, DeSmuME, mGBA, No$GBA, VisualBoyAdvance.
  * **Nintendo Retro:** Project64, Snes9x, Mesen, FCEUX, Nestopia.
  * **Xbox & Xbox 360:** Xenia (`xenia.exe`, `xenia_canary.exe`), Cxbx-Reloaded.
  * **PSP, Arcade & Multi-Sistema:** PPSSPP (`PPSSPPWindows64.exe`), Flycast, Redream, RetroArch (`retroarch.exe`), MAME, ScummVM.
* **Varredura Automática em Todas as Unidades:**
  * Detecta automaticamente pastas de emuladores (`\Emulators`, `\Emuladores`, `\Emu`, `\RetroBat\emulators`, `\LaunchBox\Emulators`, `\Playnite\Emulators`, `%LOCALAPPDATA%\Programs`, `%APPDATA%\rpcs3` e `ProgramFiles`).

---

### 🔍 2. Telemetria Forense Contínua de Hardware com Precisão de Milissegundos
* **Carimbo Temporal com Milissegundos:** Todas as linhas do log (`core/1-Click-DLSS5.log`) utilizam o padrão de precisão `yyyy-MM-dd HH:mm:ss.fff`.
* **Auditoria Profunda de Hardware na Inicialização:**
  * **Sistema Operacional & Runtime:** Windows Caption (ex: *Windows 11 Pro 24H2*), DisplayVersion, Build, Uptime da máquina, privilégios de Administrador (Elevado vs Padrão), versões do PowerShell e CLR .NET.
  * **Processador (CPU):** Nome completo do modelo, núcleos físicos, threads lógicos e clock máximo.
  * **Placas de Vídeo (GPU):** Identificação e separação automática de **GPU Dedicada (dGPU)** vs **GPU Integrada (iGPU)**, versão exata do driver, data de lançamento, memória VRAM dedicada em GB e estado do Agendamento de GPU por Hardware (**HAGS**).
  * **Memória RAM & Virtual:** Total instalado, livre e percentual disponível em tempo real.
  * **Armazenamento:** Detalhamento de todas as unidades de disco fixas (C:, D:, E:...), rótulo de volume, formato (ex: NTFS), espaço total, livre e % restante.
  * **Monitores & Exibição:** Resolução exata de todas as telas conectadas e identificação do monitor principal.

---

### 👤 3. Rastreamento Passo a Passo de Ações do Usuário `[USER]`
* **Fluxo de Interação Totalmente Rastreável:**
  * Clique em cada jogo ou emulador na lista com índice e nome do item.
  * Atualização e exibição detalhada dos dados no painel inspetor (API, Upscaler, Status, Pasta).
  * Consultas digitadas na barra de busca e quantidade de resultados correspondentes.
  * Seleção manual de cartões de Modo Neural (Direct, OptiScaler, Universal Feeder).
  * Alterações de idioma no menu de seleção.
  * Ativação ou desativação da opção "Escanear ao iniciar".
  * Seleção manual de pastas pelo botão "PROCURAR JOGO" ou via Arrastar e Soltar (**Drag & Drop**).
  * Disparo de processos no botão "INICIAR JOGO" com gravação do **PID** do processo e diretório de trabalho.
  * Confirmações ou cancelamentos no diálogo de restauração de fábrica.

---

### 📦 4. Auditoria Cirúrgica de Instalação e Restauração de Fábrica
* **Na Instalação:**
  * Validação prévia de permissão de escrita física na pasta do jogo.
  * Registro individual de cada arquivo original colocado em backup (`_DLSS5_Backup`) com tamanho exato em bytes.
  * Registro individual de cada componente injetado com tamanho em bytes, pasta de destino e origem no payload.
  * Filtro estrito que bloqueia contaminação da pasta de backup por artefatos prévios do DLSS 5.
* **Na Restauração (Desinstalação):**
  * Leitura e validação do arquivo de manifesto.
  * Restauração cirúrgica de cada arquivo original de volta para a pasta com exibição do tamanho em KB.
  * Purga completa de todos os componentes e proxies do DLSS 5 com tamanho em KB.
  * Limpeza de diretórios gerados (`reshade-shaders`, `host64`, `layer-x64`) e remoção da pasta de backup.
  * Sumário com contadores precisos de arquivos restaurados e purgados.
* **Tratamento Amigável de Falhas:**
  * Gravação do **Stack Trace Completo**, código de diagnóstico (`ERR_DX12_RHI_REQUIRED`, `ERR_ACCESS_DENIED`, etc.), causa provável e passos recomendados.
  * Acompanhamento no log das ações do botão `[1-CLICK AUTO FIX]`.

---

### ⚡ 5. Correção Definitiva para DX12 RHI / Laptops Dual GPU (Issue #9)
* **Prevenção de Seleção de iGPU no Windows 11:**
  * O aplicativo registra automaticamente o executável do jogo com preferência de GPU Dedicada de Alto Desempenho no Registro do Windows (`HKCU:\Software\Microsoft\DirectX\UserGpuPreferences`).
  * Purga preventiva de arquivos conflitantes (`sl.dlss_nr.dll`) antes da inicialização.
  * Autocura de dependências nativas (`libxess.dll`, `nvngx_dlss.dll`) para motores como Unreal Engine 5.

---

### 🚀 6. Inicialização Instantânea & Detecção de Idioma
* **Varredura em Segundo Plano Sem Travamentos:**
  * A varredura de discos foi desacoplada da thread da interface, eliminando o congelamento inicial de 1 a 2 minutos em sistemas com muitos discos.
  * Cache persistente (`games_cache.json`) que carrega a biblioteca instantaneamente ao abrir.
  * Opção na barra de ferramentas para ativar/desativar a varredura automática ao iniciar.
* **Idioma Nativo Automático:**
  * O aplicativo detecta o idioma padrão do Windows na primeira inicialização (PT, EN, ES, DE, FR, IT, JA, ZH, RU, KO), selecionando-o automaticamente.

---
---

## 🇺🇸 English

### 🌟 Release Highlights (v2.7.0-beta)
Version **v2.7.0-beta** expands **1-Click DLSS 5** into new territory, delivering native support for **major console emulators**, an enterprise-grade **Continuous Hardware & System Telemetry Logging Engine** with millisecond timestamps, chronological **step-by-step user interaction audit logs**, an automated fix for the **DX12 RHI / GPU selection error on Windows 11**, non-blocking **background library scanning with persistent caching**, and automatic **OS language detection**.

### Key Changes:
1. **Universal Console Emulator Support:** Native detection and tailored injection for DuckStation, PCSX2, RPCS3, shadPS4, Vita3K, Ryujinx, Yuzu, Dolphin, Cemu, Citra, Xenia, PPSSPP, RetroArch, and more across all drives.
2. **Deep Continuous Hardware Telemetry:** Millisecond-accurate log entries (`yyyy-MM-dd HH:mm:ss.fff`) with full system audits: CPU specs, dGPU vs iGPU classification, driver dates, VRAM, HAGS, RAM, disk partitions, and multi-monitor setups.
3. **Step-by-Step User Action Logs (`[USER]`):** Detailed audit trail tracking game list clicks, search terms, mode selections, language changes, startup scan toggles, folder browsing, process launch PIDs, and restore decisions.
4. **Forensic Install & Restore Engine:** Pre-flight write permission checks, exact byte-level tracking for injected and backed-up files, anti-contamination filters, surgical purges, and full exception stack traces with 1-Click Auto-Fix tracking.
5. **DirectX 12 RHI & Dual-GPU Laptop Fix (Issue #9):** Auto-registers high-performance GPU preference in Windows DirectX settings and eliminates Streamline / `sl.dlss_nr.dll` conflicts for Unreal Engine 5 titles (e.g., *S.T.A.L.K.E.R. 2*).
6. **Non-Blocking Background Scan & Startup Cache:** Instant UI loading on startup via persistent cache (`games_cache.json`) and non-blocking background scanner with a configurable toolbar toggle.
7. **System UI Language Auto-Detection:** Automatically matches the user's Windows display language on first run with graceful fallback to English.
