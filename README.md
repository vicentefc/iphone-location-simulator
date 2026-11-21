<p align="center">
  <img src="docs/banner.svg" alt="iPhone Location Simulator" width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0a66c2" alt="Windows 10/11">
  <img src="https://img.shields.io/badge/target-iOS%2026%20%2F%2027-111c33" alt="iOS 26/27">
  <img src="https://img.shields.io/badge/transport-Wi--Fi%20(RemotePairing)-1b2a4a" alt="Wi-Fi RemotePairing">
  <img src="https://img.shields.io/badge/engine-pymobiledevice3%2011.43.1-4f8cff" alt="pymobiledevice3">
  <img src="https://img.shields.io/badge/python-3.13-3776ab" alt="Python 3.13">
  <img src="https://img.shields.io/badge/license-GPL--3.0-8b5cf6" alt="GPL-3.0">
</p>

<p align="center">
  <b>GPS location simulation for iOS, over Wi-Fi, from Windows — engineered to stay applied.</b><br>
  A persistent background harness for mobile security testing and QA: it holds a simulated CoreLocation
  fix on iOS 26/27 (which silently revert single-shot spoofs), survives Wi-Fi drops, and self-heals
  across reboots. No jailbreak, no cable, no macOS.
</p>

---

> ### ⚖️ Authorized use only
> This is an **own-device** testing tool. It operates only against an iPhone that you **physically
> control and have paired** (a 6-digit trust prompt is confirmed *on the device*) with **Developer Mode**
> enabled. It cannot reach a device you have not paired, and it is not a remote-access or tracking tool.
> Use it only on devices you own or are explicitly authorized to test. Spoofing location can break
> app logic and may violate third-party terms of service — stay within your authorization and the law.

## Overview

Location simulation is a routine part of mobile app assessment and QA — exercising geofencing,
location-gated features, anti-fraud/anti-spoofing logic, delivery/ride flows, and region locks.
The hard part on modern iOS isn't setting a coordinate; it's **keeping it set**. iOS 26/27 accept a
`simulate-location` command and then quietly fall back to the real GPS a few seconds later, and the
phone tears down the developer tunnel every time it locks its Wi-Fi.

This project wraps Apple's developer services (via [pymobiledevice3](https://github.com/doronz88/pymobiledevice3))
in a **supervised daemon + scheduled task** that treats the fix as state to be continuously enforced,
not a one-off command.

## Use cases

- **Mobile app security testing / QA** — validate geofencing, location-gated features and region locks.
- **Anti-fraud & anti-spoofing research** — study how an app detects or tolerates a stable fake fix.
- **Field-condition simulation** — pin a coordinate, or use **walk mode** to drift realistically within a radius.
- **Reproducible test rigs** — a headless Windows box that holds a location unattended for hours.

## Capabilities

- **Wi-Fi RemotePairing transport** — no cable, no Mac, no jailbreak.
- **Persistence against iOS 26/27 reversion** — re-asserts the fix every 5 s and blocks on the device ack.
- **Sub-second-class recovery** — on tunnel teardown, reconnects straight to the cached RSD endpoint
  (skips Bonjour discovery), restoring the fix before the real location resurfaces.
- **Unattended operation** — Scheduled Task (S4U, elevated) starts it at boot / sign-in / resume /
  every 5 min; a watchdog relaunches a hung engine.
- **Walk mode** — bounded random-walk around a center point at human pace.
- **Operator-friendly control** — single-purpose `.bat` entry points for pair, activate, change, status.

## Architecture

<p align="center">
  <img src="docs/architecture.svg" alt="Architecture" width="100%">
</p>

```
Scheduled Task  ──▶  revisar.ps1 (watchdog)  ──▶  servicio.ps1 (supervisor)  ──▶  ubicacion_daemon.py (engine)
                                                                                          │
                                                                        RemotePairing tunnel (TCP) over Wi-Fi
                                                                                          ▼
                                                                                  iPhone · DVT · LocationSimulation
```

## Technical notes

The engine (`sistema/ubicacion_daemon.py`) is built around four failure modes observed on iOS 26/27:

| Problem | Mitigation |
|---|---|
| A single `simulate-location set` is reverted after seconds | Re-send every 5 s and `await` the device ack each cycle, so enforcement is verified, not assumed |
| iPhone drops Wi-Fi on lock (~6 s to detect) | Reconnect directly to the cached `RSD host:port` in ~2 s instead of re-running Bonjour discovery |
| Opening a second RSD session cancels the simulation | All traffic is funneled through the daemon's single connection |
| Developer Disk Image unmounts after a device reboot | `auto_mount` remounts on demand |
| `pymobiledevice3` crashes on the iPhone's IPv6 link-local addresses (`UnicodeError` in `getaddrinfo`) | Installer patches `tunnel_service.py` to skip link-local candidates; IPv4 is preferred |

The task runs **S4U / highest privileges** (needed to create the tunnel interface) and requires no stored
password or interactive session.

## Requirements

- Windows 10/11 + [Python 3.13](https://www.python.org/downloads/) — `winget install Python.Python.3.13`
- iTunes (from apple.com) and [Bonjour](https://developer.apple.com/bonjour/) — `winget install Apple.Bonjour`
- iPhone on **iOS 26+** with **Developer Mode** enabled *(Settings → Privacy & Security → Developer Mode)*
- Host and device on the **same Wi-Fi**, network profile set to **Private** in Windows

## Installation

1. Clone the repo.
2. Run **`Instalar o reparar.bat`** (elevates). Installs the engine to `%LOCALAPPDATA%\UbicacionIphone`,
   applies the IPv6 patch, and registers the scheduled task.
3. Run **`Emparejar iPhone.bat`** → on the iPhone, *Settings → Developer → Paired Macs*, tap this host
   under "Other devices" and enter the 6-digit code.
4. Set a coordinate with **`Cambiar ubicacion.bat`**.

## Usage

| Entry point | Action |
|---|---|
| `Estado.bat` | Live status: active state, last device confirmation, recent events |
| `Activar.bat` | Apply the fix from `config.json` |
| `Desactivar.bat` | Release to the real location (persists across reboots) |
| `Cambiar ubicacion.bat` | Pick from `lugares.json` or paste Google Maps coordinates |
| `Emparejar iPhone.bat` | Pair over Wi-Fi (one-time) |
| `Instalar o reparar.bat` | Install/repair; idempotent |

`config.json` and `lugares.json` are operator-specific and `.gitignore`d (created from the `*.ejemplo.json` templates).
Logs and live state: `%LOCALAPPDATA%\UbicacionIphone` (`daemon.log`, `servicio.log`, `instalar.log`).

## Operational notes & limitations

- The host must stay **powered and awake** (laptop: "When I close the lid → Do nothing"); device on the same Wi-Fi.
- After a device reboot, unlock it once to re-establish trust.
- **Find My** may still report the real location — it's a system service and doesn't always honor the simulated fix.
- Validated against `pymobiledevice3` **11.43.1** (pinned in `instalar.ps1`; the Windows patch tracks this version).

## Roadmap

- Optional read-only device utilities over the same session (device info, screenshot, syslog capture).
- Multi-device profiles.
- Structured JSON event log for test harness integration.

## Credits & license

Engine: [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) by doronz88 (GPL-3.0-or-later).
Periodic re-assert idea from [SimVirtualLocation](https://github.com/MohammedSayedAhmed/SimVirtualLocation).
Released under **GPL-3.0** — see [LICENSE](LICENSE).

## Disclaimer

Provided for lawful testing, QA, and research on devices you own or are authorized to assess. The authors
accept no liability for misuse. You are responsible for compliance with applicable laws and third-party terms.

---

## 🇪🇸 Español

**Simulación de ubicación GPS para iOS, por Wi-Fi y desde Windows — diseñada para mantenerse aplicada.**
Un harness persistente para testing de seguridad móvil y QA: sostiene una ubicación simulada en iOS 26/27
(que revierten los spoofs de un solo disparo), sobrevive a cortes de Wi-Fi y se recupera tras reinicios.
Sin jailbreak, sin cable y sin macOS.

> **⚖️ Solo uso autorizado.** Herramienta para **tu propio dispositivo**: funciona únicamente con un
> iPhone que controlas físicamente y has **emparejado** (confirmas un código de 6 dígitos *en el teléfono*)
> con **Modo de desarrollador** activo. No alcanza a un dispositivo que no hayas emparejado y no es una
> herramienta de acceso remoto ni de rastreo. Úsala solo en equipos propios o con autorización explícita.

### Para qué sirve

Testing de apps (geofencing, funciones ligadas a ubicación, bloqueos por región), investigación
anti-fraude/anti-spoofing, y bancos de prueba reproducibles que mantienen una coordenada durante horas.
Lo difícil en iOS moderno no es fijar la coordenada, sino **mantenerla**: iOS 26/27 vuelven solos a la
ubicación real a los segundos, y el iPhone corta el túnel cada vez que bloquea el Wi-Fi.

### Requisitos

- Windows 10/11 + [Python 3.13](https://www.python.org/downloads/) — `winget install Python.Python.3.13`
- iTunes (de apple.com) y [Bonjour](https://developer.apple.com/bonjour/) — `winget install Apple.Bonjour`
- iPhone con iOS 26+ y **Modo de desarrollador** activado
- PC e iPhone en la **misma Wi-Fi**, marcada como **Privada** en Windows

### Instalación

1. Clona el repo.
2. Ejecuta **`Instalar o reparar.bat`** (pide administrador): instala el motor en
   `%LOCALAPPDATA%\UbicacionIphone`, aplica el parche IPv6 y crea la tarea programada.
3. Ejecuta **`Emparejar iPhone.bat`** → en el iPhone, *Ajustes → Desarrollador → Mac emparejados*, toca
   esta PC en "Otros dispositivos" y escribe el código de 6 dígitos.
4. Elige una coordenada con **`Cambiar ubicacion.bat`**.

### Uso

| Archivo | Acción |
|---|---|
| `Estado.bat` | Estado en vivo: activo, última confirmación del iPhone, eventos recientes |
| `Activar.bat` | Aplica la ubicación de `config.json` |
| `Desactivar.bat` | Vuelve a la ubicación real (persiste tras reiniciar) |
| `Cambiar ubicacion.bat` | Elige de `lugares.json` o pega coordenadas de Google Maps |
| `Emparejar iPhone.bat` | Empareja por Wi-Fi (una vez) |
| `Instalar o reparar.bat` | Instala/repara; idempotente |

### Detalles técnicos

- **iOS 26/27 revierten solos**: el daemon reenvía la ubicación cada 5 s y espera el ack del iPhone.
- **El iPhone corta el Wi-Fi al bloquearse**: reconecta directo al `RSD host:port` cacheado (sin Bonjour).
- **No abrir sesiones RSD nuevas** mientras se simula: todo pasa por la conexión del daemon.
- **Imagen de desarrollador**: se remonta sola tras un reinicio del iPhone.
- **Parche Windows**: `instalar.ps1` evita las direcciones IPv6 link-local que hacen caer a pymobiledevice3.

### Limitaciones

- La PC debe estar **encendida y sin suspender**; el iPhone en la misma Wi-Fi.
- Tras un reinicio del iPhone, desbloquéalo una vez.
- **Buscar (Find My)** puede mostrar la ubicación real (servicio del sistema).
- Probado con `pymobiledevice3` **11.43.1** (fijado en `instalar.ps1`).

### Licencia

Sobre [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) (GPL-3.0-or-later). Idea de reenvío
periódico de [SimVirtualLocation](https://github.com/MohammedSayedAhmed/SimVirtualLocation).
Distribuido bajo **GPL-3.0** (ver [LICENSE](LICENSE)). Solo para pruebas lícitas en dispositivos propios o autorizados.
