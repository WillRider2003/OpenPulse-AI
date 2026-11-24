# Correcciones al repositorio OpenPulse-AI (commit base 4c74ad8, rama main = ta2-avance)

Copia corregida preparada por Luis Paredes para revisar antes de subir. No se probó con Docker en esta copia: hay que levantarla una vez con `setup.ps1` antes de hacer push.

## 1. Resultados escritos en el código (lo más importante)
| Archivo | Problema | Cambio |
|---|---|---|
| `asterisk/scripts/qos_experimento_ab.sh` | Imprimía con `print` los resultados A/B (38,4 ms / 4,8 ms, MOS 3,68 / 4,38) sin medir nada | Ahora solo configura la cola (`fifo`, `htb`, `estado`, `limpiar`) y muestra contadores reales de `tc` y `channelstats` |
| `scripts/2_mediciones_completas_sla.py` | 20 llamadas en una lista fija, video 720p impreso, chat/presencia calculados con una fórmula sobre un ping, RTO = sleep + 18,4 s | Calcula MOS, p95 y % en SLA desde un CSV de llamadas medidas y sondea los HTTPS de verdad |
| `asterisk/scripts/sla_exporter.py` | MOS 4,39 y 100 % de llamadas en SLA fijos; chat/presencia/docs por fórmula | Publica jitter, pérdida, RTT y MOS solo de llamadas activas; colaboración solo si existe `kpi_colaboracion.json` con valores medidos |
| `asterisk/scripts/hardening_security.sh` | El "antes" era un `echo`, la IP atacante se agregaba a mano a la lista negra y se anunciaba Wazuh sin que exista | Aplica nftables reales y muestra TLS, dialplan y estado real de fail2ban; el ataque se hace aparte con nmap y SIPVicious |
| `scripts/ejecutar_todas_las_pruebas_ta3.ps1` | Si no había contenedor, imprimía los resultados de la "simulación" | Avisa que no hay contenedor |
| `scripts/1_auditoria_licencias_sbom.ps1` | El SPDX analizaba la carpeta (NOASSERTION) y tenía un respaldo que escribía un SBOM inventado | Genera un SBOM por imagen en `sbom/` |
| `docs/TA3_RESUMEN_PARA_INFORME_PDF.md` | Copiaba los valores fijos de los scripts | Reescrito con valores medidos; la versión anterior está en `_borrar_del_repo/` |

## 2. Contraseñas en el repositorio público
- `.env.example`: ahora con `CAMBIAR`; `setup.ps1` y `setup.sh` se detienen si falta una clave.
- `pjsip.conf` → `pjsip.conf.template` con `__HOST_IP__` y `__SIP_PASSWORD__`; setup genera `pjsip.conf` (en `.gitignore`).
- `docker-compose.yml`: sin claves por defecto para TURN y Grafana.
- `setup.ps1`, `setup.sh`, `README.md` y la guía V305 ya no imprimen ni documentan claves.
- **Importante**: las claves antiguas siguen en el historial de Git. Hay que cambiarlas en el `.env` de cada laptop.

## 3. Seguridad y operación
- fail2ban: nueva regla `asterisk/fail2ban/jail.d/asterisk.local` y `logger.conf`; el `entrypoint.sh` lo arranca. Con Docker Desktop la IP de origen puede verse como la puerta de enlace de Docker y el bloqueo afectaría a todos; en Linux con Docker Engine se conserva la IP real.
- Keycloak: `sslRequired` pasa de `none` a `external` en ambos realms.
- OpenLDAP: el puerto 389 solo escucha en 127.0.0.1.
- Grafana: los paneles de MOS y jitter muestran el peor canal activo.
- Guía V305: Linphone por TLS en 5061 (antes UDP 5070, que deja las claves SRTP visibles).

## 4. Pendiente (no cambiado porque necesita prueba)
- `debug=true` en Nextcloud: hace falta registrar el proveedor OIDC con `https://IP:8444` y que Nextcloud confíe en la CA de Caddy (tarea WA_04).
- Borrar el administrador temporal de Keycloak después de crear `wantaurco.admin` (WA_09).
- Keycloak sigue en `start-dev`.
- Buzón de voz y grupo de llamada no existen en `extensions.conf` (RP_09 y RP_10).
- `media_encryption_optimistic=yes` permite llamadas sin SRTP; se dejó por las pruebas SIPp.
- Imágenes de IA de la laptop de Lucía con etiqueta `latest`.

## 5. Archivos para borrar del repo (`_borrar_del_repo/`)
`openpulse_repo.zip` (copia de la TA1), `TA3_plantillas_OpenPulse.zip` (ya está extraído), `pjsip.conf` con claves y el resumen con valores fijos.

## Cómo subirlo sin chocar con el resto
```powershell
cd C:\Users\abdul\Desktop\TA_UNIFICADAS\OpenPulse-AI
git checkout -- .
git switch -c ta3-correcciones-luis
robocopy ..\OpenPulse-AI_TA3_corregido\openpulse .\openpulse /E
git rm openpulse/asterisk/conf/pjsip.conf openpulse_repo.zip TA3_plantillas_OpenPulse.zip
git add openpulse
git status
git commit -m "TA3: scripts sin resultados fijos, claves fuera del repo y fail2ban real"
git push -u origin ta3-correcciones-luis
```
Luego abrir un Pull Request para que Willian y Abdon lo revisen antes de unirlo a main.
