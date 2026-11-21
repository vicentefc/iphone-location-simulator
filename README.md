<p align="center">
  <img src="docs/banner.svg" alt="iPhone Location Simulator" width="100%">
</p>

Simula la ubicación GPS de un iPhone (iOS 26/27) por Wi-Fi, desde Windows. Sin jailbreak, sin cable y sin Mac.

Lo hice porque las herramientas que encontré necesitaban Mac o cable, y porque en iOS 26/27 mandar la ubicación una sola vez no sirve: el iPhone vuelve solo a la ubicación real a los pocos segundos. Esto queda corriendo de fondo, la reaplica sola y se reconecta cuando el iPhone corta el Wi-Fi.

Usa los servicios de desarrollador de Apple a través de [pymobiledevice3](https://github.com/doronz88/pymobiledevice3).

> Funciona solo con un iPhone propio, emparejado (escribes un código de 6 dígitos en el teléfono) y con el Modo de desarrollador activado. No sirve para acceder a un iPhone ajeno.

## Requisitos

- Windows 10/11 con [Python 3.13](https://www.python.org/downloads/) — `winget install Python.Python.3.13`
- iTunes (de apple.com) y [Bonjour](https://developer.apple.com/bonjour/) — `winget install Apple.Bonjour`
- iPhone con iOS 26 o superior y Modo de desarrollador activado (Ajustes → Privacidad y seguridad → Modo de desarrollador)
- La PC y el iPhone en la misma Wi-Fi, con la red marcada como Privada en Windows

## Instalación

1. Clona o descarga el repo.
2. Ejecuta `Instalar o reparar.bat` (pide administrador). Instala el motor en `%LOCALAPPDATA%\UbicacionIphone`, aplica un arreglo para Windows y crea la tarea programada.
3. Ejecuta `Emparejar iPhone.bat` y sigue los pasos: en el iPhone, Ajustes → Desarrollador → Mac emparejados, toca esta PC en "Otros dispositivos" y escribe el código de 6 dígitos.
4. Elige un lugar con `Cambiar ubicacion.bat`.

## Uso

| Archivo | Para qué |
|---|---|
| `Estado.bat` | Si está activo, la última confirmación del iPhone y los últimos eventos |
| `Activar.bat` | Aplica la ubicación de `config.json` |
| `Desactivar.bat` | Vuelve a la ubicación real (queda así aunque reinicies) |
| `Cambiar ubicacion.bat` | Elige un lugar de `lugares.json` o pega coordenadas de Google Maps |
| `Emparejar iPhone.bat` | Empareja el iPhone por Wi-Fi (una vez) |
| `Instalar o reparar.bat` | Instala o repara todo; se puede correr las veces que haga falta |

Los lugares favoritos van en `lugares.json` (cópialo de `lugares.ejemplo.json`). `config.json` se crea solo desde `config.ejemplo.json`. Los dos son personales y están en `.gitignore`.

Con un radio mayor que 0 el daemon camina a paso normal alrededor del punto, sin alejarse más de ese radio.

## Cómo funciona

<p align="center">
  <img src="docs/architecture.svg" alt="Arquitectura" width="100%">
</p>

```
Tarea programada  →  revisar.ps1  →  servicio.ps1  →  ubicacion_daemon.py  →  iPhone
(al encender, al iniciar sesión, al volver de suspensión, cada 5 min)
```

Los problemas que resuelve el daemon:

- **iOS 26/27 vuelven solos a la ubicación real.** Un `simulate-location set` único no basta, así que reenvía la ubicación cada 5 s y espera la respuesta del iPhone en cada envío.
- **El iPhone corta el Wi-Fi al bloquearse.** Lo detecta en ~6 s y reconecta directo a la última IP conocida (sin buscar por Bonjour), así la ubicación real no alcanza a aparecer.
- **No se pueden abrir sesiones nuevas mientras se simula**: una sesión RSD nueva hace que el iPhone descarte la simulación. Todo pasa por la conexión del daemon.
- **La imagen de desarrollador** se monta sola después de que el iPhone se reinicia.
- **Arreglo para Windows**: pymobiledevice3 se cae con las direcciones IPv6 link-local del iPhone (`UnicodeError` en `getaddrinfo`); `instalar.ps1` parchea `tunnel_service.py` para saltarlas.

La tarea corre en modo S4U (sin iniciar sesión ni guardar la contraseña) y con privilegios elevados, que hacen falta para crear la interfaz del túnel.

## Limitaciones

- La PC tiene que estar encendida y sin suspenderse (en un notebook, configura "Al cerrar la tapa: No hacer nada"), y el iPhone en la misma Wi-Fi.
- Si el iPhone se reinicia, hay que desbloquearlo una vez para que vuelva a conectar.
- Buscar (Find My) puede seguir mostrando la ubicación real: es un servicio del sistema y no siempre usa la simulada.
- Probado con pymobiledevice3 11.43.1 (fijado en `instalar.ps1`; el arreglo depende de esa versión).

## Créditos y licencia

Construido sobre [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) de doronz88 (GPL-3.0-or-later). La idea de reenviar la ubicación cada cierto tiempo viene de [SimVirtualLocation](https://github.com/MohammedSayedAhmed/SimVirtualLocation).

Licencia GPL-3.0 (ver [LICENSE](LICENSE)).

---

### In English

GPS location spoofing for iPhone (iOS 26/27) over Wi-Fi, from Windows. No jailbreak, no cable, no Mac.

Single-shot spoofs don't stick on iOS 26/27 (the phone reverts to the real GPS after a few seconds), so this runs in the background, re-applies the location, and reconnects on its own when the iPhone drops Wi-Fi. Built on [pymobiledevice3](https://github.com/doronz88/pymobiledevice3).

Works only with your own iPhone, paired (you type a 6-digit code on the phone) and with Developer Mode on. See the Spanish sections above for setup and usage — the `.bat` names are self-explanatory.
