# Acer Nitro 5 (AN515-44) — Otimização de Bateria em Nível de Hardware (≤ 15 W)

Conjunto de scripts PowerShell + controle direto de SMU (`RyzenAdj`) + gerenciamento PCIe/Optimus + vigia de áudio ETW/WASAPI para o **Acer Nitro 5 AN515-44** (**AMD Ryzen 5 4600H Renoir + NVIDIA GeForce GTX 1650 Optimus + 2× NVMe + tela 144 Hz**).

## Resultado real medido

| Cenário | Consumo antes | Consumo depois | Autonomia (bateria 60 Wh) |
| :--- | :---: | :---: | :---: |
| **Uso leve / navegação** | 22 – 24 W | **10,3 – 12,5 W** | **~4h50 – 5h45** |
| **Uso moderado + vídeo 4K** | 24 – 30 W | **12 – 14,5 W** | **~4h10 – 5h00** |
| **Stress 100% CPU (12 threads)** | 40 – 50+ W | **≤ 15 W** *(37,9 °C)* | **~4h00+** |
| **Na tomada (AC)** | 45 W / 144 Hz | **45 W / 54 W + 144 Hz + GTX 1650 livre** | Desempenho máximo automático |

---

## O que o `auto-energia.ps1` faz automaticamente

Roda invisível em segundo plano como tarefa agendada (`\Energia Automatica`, no logon como Admin) e reage em ~3 segundos ao plugar/desplugar da tomada ou alternar a **Economia de energia** do Windows:

### Modo Economia (fora da tomada)
1. **SMU do Ryzen 5 4600H (`RyzenAdj`):**
   - Aplica `--stapm-limit=8000 --fast-limit=9000 --slow-limit=8000 --apu-slow-limit=8000 --vrm-current=22000 --vrmmax-current=30000 --vrmsoc-current=14000 --vrmsocmax-current=20000 --tctl-temp=68 --power-saving` *(no BIOS do Nitro 5 a escala é ~0,9× → ~7,2 W STAPM / ~8,1 W pico, mantendo vídeo 4K liso e teto total ≤ 15 W)*.
   - A cada 60s faz leitura **somente-leitura** (`ryzenadj -i`, zero glitches de áudio) e só reaplica se o EC do NitroSense tiver resetado o teto acima de 9,5 W.
2. **GTX 1650 dormindo em `D3` (0 W) — somente Radeon integrada:**
   - Garante a GTX 1650 **habilitada** no PnP para o driver `nvlddmkm` colocá-la em Optimus `D3`/`D3cold`.
   - Desabilita a **Função 1 PCIe** (`PCI\VEN_10DE&DEV_10FA` — controlador HDMI Audio da NVIDIA que segurava o barramento em `D0`) e para o serviço `NvContainerLocalSystem` (impede os 5 processos do NVIDIA Overlay de renascerem e acordarem a dGPU).
   - Força iGPU em nível de sistema (`GPUPREFERENCEPOLICY = 1`, `Gráficos Dinâmicos Alternáveis = 0`, `AMD PowerPlay = 0`, `AMD Power Slider = 0`, `PCIe ASPM = 2`).
3. **2× SSDs NVMe em sono profundo (PS4):**
   - Configura `Primary & Secondary NVMe Latency Tolerance = 50 ms`, `Idle Timeout = 100 ms`, `NOPPME = 1` e `AHCI = HIPM+DIPM`.
4. **CPU & Plataforma:**
   - Ativa plano `Equilibrado` (gravando em todos os planos para o NitroSense não desfazer), `Core Parking Min = 0%`, `Boost = 0`, `EPP = 75`, `PERFINCTHRESHOLD = 65%`, `PERFDECTHRESHOLD = 25%`, `PERFDECPOL = 1`, `JS Timer = 0`, `Vídeo = 1 (Equilibrado)`, `ESBATTTHRESHOLD = 100%` (DC).
   - Muda tela para **60 Hz**, reduz brilho para ≤ 20% (sem aumentar se já estiver menor), pausa o **Wallpaper Engine** (`-control pause`), encerra WSL/`vmcompute`/Tailscale e apps que acordam CPU/dGPU (`HWMonitor`, Steam, Epic, Discord, `AMDRSServ`).

### Modo Desempenho (na tomada)
- Restaura **45 W / 54 W + `--max-performance`** no SMU, **144 Hz**, brilho 100%, plano `Alto desempenho`, `Boost = 2`, `EPP = 0`, reabilita `NVIDIA HDMI Audio` + `NvContainerLocalSystem`, retoma o Wallpaper Engine (`-control play`) e inicia o Tailscale.

---

## Descobertas de hardware importantes (testadas no AN515-44)

- **Nunca use `Disable-PnpDevice` na GTX 1650 neste modelo:** em teste A/B na bateria, desabilitar a GTX 1650 no Gerenciador de Dispositivos fez o consumo **subir de -13,8 W para -19,3 / -21,0 W (+5,5 W)**, pois sem o `nvlddmkm` carregado o BIOS não desliga o barramento (`D3cold`). O ideal é mantê-la habilitada dormindo em `D3` e bloquear tudo que a acorda.
- **Não use `HWMonitor` na bateria para medir Watts:** o `HWMonitor` consulta os sensores da GTX 1650 a cada 1s, acordando-a de `D3` para `D0` e somando **+4 a 6 W** no próprio medidor. Use [`watts.ps1`](./watts.ps1), que lê `BatteryStatus` via WMI e `DEVPKEY_Device_PowerData` sem nunca acordar a GPU.
- **Áudio sem estalos (`vigia/`):** Wi-Fi fica em desempenho máximo (`0`) para evitar DPC spikes, e o [`vigia/vigia-audio.ps1`](./vigia/vigia-audio.ps1) escuta eventos ETW do motor de áudio do Windows em tempo real e executa um soft-reset de canal (`SoftReset.cs`) caso ocorram glitches contínuos, sem fechar nenhum aplicativo.

---

## Arquivos do repositório

| Arquivo | Função |
| :--- | :--- |
| [`auto-energia.ps1`](./auto-energia.ps1) | Daemon principal (bateria ↔ tomada + controle de SMU, GTX 1650, NVMe, 60/144 Hz) |
| [`instalar.ps1`](./instalar.ps1) | Instalador 1-clique (baixa `RyzenAdj`, registra `Energia Automatica` e `Vigia de Audio`, fixa apps na iGPU) |
| [`watts.ps1`](./watts.ps1) | Monitor leve de Watts, autonomia estimada, MHz, C3% e estado `D0/D3` da GTX 1650 (sem acordar a dGPU) |
| [`aplicar-agora.bat`](./aplicar-agora.bat) / [`apply-and-verify.ps1`](./apply-and-verify.ps1) | Recarrega a tarefa como Admin, aplica SMU e abre o monitor |
| [`vigia/`](./vigia/) | Watchdog ETW/WASAPI (`vigia-audio.ps1`, `GlitchWatch.cs`, `SoftReset.cs`, `instalar-vigia.ps1`) |
| [`teste-gpu-bateria.bat`](./teste-gpu-bateria.bat) / [`teste-gpu-bateria.ps1`](./teste-gpu-bateria.ps1) | Benchmark A/B: Optimus `D3` vs GTX 1650 desabilitada |
| [`teste-teto-15w.bat`](./teste-teto-15w.bat) / [`teste-teto-15w.ps1`](./teste-teto-15w.ps1) | Stress test 100% CPU (12 threads) validando o teto ≤ 15 W |
| [`configurar-bateria.ps1`](./configurar-bateria.ps1) / [`modo.ps1`](./modo.ps1) / [`relatorio-quando-cheia.ps1`](./relatorio-quando-cheia.ps1) | Utilitários auxiliares de configuração manual e relatório de bateria |

## Instalação rápida (Windows 11, PowerShell como Administrador)

```powershell
git clone https://github.com/joabzicg/nitro5-battery-optimizer.git C:\Users\$env:USERNAME\Scripts\Energia
cd C:\Users\$env:USERNAME\Scripts\Energia
powershell -ExecutionPolicy Bypass -File .\instalar.ps1
```

Para acompanhar o consumo real em tempo real sem acordar a GTX 1650:

```powershell
powershell -ExecutionPolicy Bypass -File .\watts.ps1
```
