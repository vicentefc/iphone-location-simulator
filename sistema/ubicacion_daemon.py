"""Daemon de ubicacion: mantiene el iPhone en la ubicacion simulada, reconectando lo mas rapido posible.

Todo en un solo proceso (corre como administrador, lo supervisa servicio.ps1):
  1. Conecta con el iPhone por Wi-Fi. Primero prueba directo a la ultima IP conocida (1-2 s);
     si no responde, lo busca en la red por Bonjour y guarda la IP nueva.
  2. Abre el tunel TCP y monta la imagen de desarrollador solo si hace falta.
  3. Fija la ubicacion y la reenvia cada INTERVALO segundos esperando confirmacion del iPhone.
     En iOS 26/27 un envio unico no basta: el iPhone vuelve solo a la ubicacion real al rato.
  4. Si algo falla, vuelve al paso 1 de inmediato. El iPhone mantiene la ubicacion simulada unos
     segundos tras un corte, asi que una reconexion rapida evita que se vea la ubicacion real.

Con RADIO > 0 (metros) camina a paso normal alrededor del punto sin alejarse mas de RADIO.

Uso: python ubicacion_daemon.py UDID LATITUD LONGITUD CARPETA_DATOS [RADIO]
Escribe en CARPETA_DATOS: daemon-estado.json (estado vivo) y daemon-cache.json (ultima IP).
"""

import asyncio
import json
import logging
import math
import random
import sys
import time
from datetime import datetime
from pathlib import Path

from pymobiledevice3.exceptions import AlreadyMountedError
from pymobiledevice3.remote.common import TunnelProtocol
from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
from pymobiledevice3.remote.tunnel_service import (
    create_core_device_tunnel_service_using_remotepairing,
    get_remote_pairing_tunnel_services,
    start_tunnel,
)
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation
from pymobiledevice3.services.mobile_image_mounter import auto_mount

INTERVALO = 5  # segundos entre reenvios (tambien mantiene despierto el Wi-Fi del iPhone)
TIMEOUT_RESPUESTA = 6  # sin respuesta en este tiempo = conexion muerta
TIMEOUT_DIRECTO = 4  # conexion directa a la IP conocida
INTERVALO_PASEO = 2  # al caminar se reenvia mas seguido para que el movimiento se vea continuo
VELOCIDAD = 1.3  # m/s, paso de caminata
METROS_POR_GRADO = 111_320

log = logging.getLogger("daemon")


class Caminante:
    """Paseo al azar alrededor del punto central, sin alejarse mas de `radio` metros.
    Con radio 0 se queda quieto en el punto."""

    def __init__(self, lat: float, lon: float, radio: float) -> None:
        self.lat0, self.lon0, self.radio = lat, lon, radio
        self.x = self.y = 0.0  # metros al este y al norte del centro
        self.rumbo = random.uniform(0, 2 * math.pi)
        self.ultimo = None

    def posicion(self):
        if self.radio <= 0:
            return self.lat0, self.lon0
        ahora = time.monotonic()
        # Tras un corte no se "teletransporta": como maximo avanza lo de 10 s
        dt = 0 if self.ultimo is None else min(ahora - self.ultimo, 10)
        self.ultimo = ahora
        self.rumbo += random.gauss(0, 0.35)
        if math.hypot(self.x, self.y) > self.radio * 0.8:
            # Cerca del borde: girar de a poco hacia el centro
            hacia_centro = math.atan2(-self.y, -self.x)
            self.rumbo += ((hacia_centro - self.rumbo + math.pi) % (2 * math.pi) - math.pi) * 0.5
        self.x += VELOCIDAD * dt * math.cos(self.rumbo)
        self.y += VELOCIDAD * dt * math.sin(self.rumbo)
        lat = self.lat0 + self.y / METROS_POR_GRADO
        lon = self.lon0 + self.x / (METROS_POR_GRADO * math.cos(math.radians(self.lat0)))
        return lat, lon


class Estado:
    def __init__(self, carpeta: Path) -> None:
        self.archivo = carpeta / "daemon-estado.json"
        self.cache = carpeta / "daemon-cache.json"
        self.datos = {"fase": "iniciando", "reconexiones": 0, "confirmado": None, "ip": None, "detalle": ""}

    def actualizar(self, **cambios) -> None:
        self.datos.update(cambios)
        self.datos["latido"] = datetime.now().isoformat()
        try:
            self.archivo.write_text(json.dumps(self.datos), encoding="utf-8")
        except OSError:
            pass

    def leer_cache(self):
        try:
            c = json.loads(self.cache.read_text(encoding="utf-8"))
            return c["ip"], int(c["puerto"])
        except (OSError, ValueError, KeyError):
            return None

    def guardar_cache(self, ip: str, puerto: int) -> None:
        try:
            self.cache.write_text(json.dumps({"ip": ip, "puerto": puerto}), encoding="utf-8")
        except OSError:
            pass


async def conectar(udid: str, estado: Estado):
    """Devuelve un servicio RemotePairing conectado. Primero directo, despues por Bonjour."""
    cache = estado.leer_cache()
    if cache:
        try:
            servicio = await asyncio.wait_for(
                create_core_device_tunnel_service_using_remotepairing(udid, cache[0], cache[1]), TIMEOUT_DIRECTO
            )
            log.info("Conectado directo a %s:%s", *cache)
            return servicio
        except Exception as e:  # IP cambio, Wi-Fi del iPhone dormido, etc.
            log.debug("Conexion directa fallo: %r", e)

    estado.actualizar(fase="buscando", detalle="Buscando el iPhone en el Wi-Fi")
    servicios = await get_remote_pairing_tunnel_services(udid=udid)
    if not servicios:
        return None
    # Preferir IPv4: es estable y no tiene el problema de las direcciones IPv6 en Windows
    servicios.sort(key=lambda s: ":" in (s.hostname or ""))
    elegido = servicios[0]
    for otro in servicios[1:]:
        await otro.close()
    estado.guardar_cache(elegido.hostname, elegido.port)
    log.info("Encontrado por Bonjour en %s:%s", elegido.hostname, elegido.port)
    return elegido


async def montar_si_hace_falta(rsd: RemoteServiceDiscoveryService) -> None:
    try:
        await auto_mount(rsd)
        log.info("Imagen de desarrollador montada")
    except AlreadyMountedError:
        pass


async def mantener(rsd: RemoteServiceDiscoveryService, tunel, caminante: Caminante, estado: Estado) -> str:
    intervalo = INTERVALO_PASEO if caminante.radio > 0 else INTERVALO
    async with DvtProvider(rsd) as dvt, LocationSimulation(dvt) as ubicacion:
        await asyncio.wait_for(ubicacion.set(*caminante.posicion()), TIMEOUT_RESPUESTA)
        estado.actualizar(fase="activo", confirmado=datetime.now().isoformat(), detalle="")
        log.info("Ubicacion aplicada y confirmada por el iPhone")

        cerrado = asyncio.ensure_future(tunel.client.wait_closed())
        try:
            while True:
                await asyncio.wait({cerrado}, timeout=intervalo)
                if cerrado.done():
                    return "el iPhone cerro el tunel"
                await asyncio.wait_for(ubicacion.set(*caminante.posicion()), TIMEOUT_RESPUESTA)
                estado.actualizar(fase="activo", confirmado=datetime.now().isoformat())
        finally:
            cerrado.cancel()


async def sesion(udid: str, caminante: Caminante, estado: Estado) -> str:
    estado.actualizar(fase="conectando", detalle="Conectando con el iPhone")
    servicio = await conectar(udid, estado)
    if servicio is None:
        return "no se encontro el iPhone en el Wi-Fi"
    estado.actualizar(ip=servicio.hostname)
    try:
        async with start_tunnel(servicio, protocol=TunnelProtocol.TCP) as tunel:
            async with RemoteServiceDiscoveryService((tunel.address, tunel.port)) as rsd:
                await asyncio.wait_for(montar_si_hace_falta(rsd), 120)
                return await mantener(rsd, tunel, caminante, estado)
    finally:
        try:
            await servicio.close()
        except Exception:
            pass


async def principal(udid: str, lat: float, lon: float, carpeta: Path, radio: float) -> None:
    estado = Estado(carpeta)
    # Fuera del bucle: al reconectar el paseo sigue desde donde iba
    caminante = Caminante(lat, lon, radio)
    fallos_seguidos = 0
    while True:
        inicio = time.monotonic()
        try:
            motivo = await sesion(udid, caminante, estado)
        except asyncio.TimeoutError:
            motivo = "el iPhone no respondio a tiempo"
        except Exception as e:
            motivo = f"{type(e).__name__}: {e}"

        duro = time.monotonic() - inicio
        fallos_seguidos = 0 if duro > 60 else fallos_seguidos + 1
        estado.actualizar(fase="reconectando", reconexiones=estado.datos["reconexiones"] + 1, detalle=motivo)
        log.warning("Conexion perdida (%s); reconectando", motivo)
        # Reintento inmediato; si falla una y otra vez (iPhone fuera de casa), espaciar los intentos
        await asyncio.sleep(0.5 if fallos_seguidos < 5 else min(30, 2 * fallos_seguidos))


def main() -> int:
    udid, lat, lon, carpeta = sys.argv[1:5]
    radio = float(sys.argv[5]) if len(sys.argv) > 5 else 0.0
    from logging.handlers import RotatingFileHandler

    archivo_log = RotatingFileHandler(Path(carpeta) / "daemon.log", maxBytes=1_000_000, backupCount=1, encoding="utf-8")
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        handlers=[archivo_log],
    )
    # Silenciar el detalle interno de pymobiledevice3; solo nuestros mensajes
    logging.getLogger("pymobiledevice3").setLevel(logging.ERROR)
    asyncio.run(principal(udid, float(lat), float(lon), Path(carpeta), radio))
    return 0


if __name__ == "__main__":
    sys.exit(main())
