# OpenPulse AI — Resumen técnico de la TA3 (valores medidos)

Este resumen reemplaza la versión anterior, que copiaba resultados escritos dentro de los scripts de demostración. Aquí solo figuran valores con registro o captura fechada. Lo que falta se mide en el laboratorio V305.

## Implementado
| Frente | Implementación | Evidencia |
|---|---|---|
| Licencias | Valkey 8.0.1 en lugar de Redis 7.4, Grafana OSS 11.3.0 y versiones fijas en todas las imágenes | `docker-compose.yml` |
| HTTPS | Caddy 2.8.4 con CA interna para Nextcloud (8443), Keycloak (8444) y Collabora (9443) | HTTP 200 con certificado verificado (22 nov) |
| Identidad | Federación OpenLDAP en Keycloak; debug=false en Nextcloud en la prueba local | Registro identity.txt (22 nov) |
| Voz | SIP sobre TLS en 5061 (TLS 1.2), SRTP con SDES, contexto `[default]` bloqueado | voice.txt, defense.txt |
| QoS | Colas tc A (tbf) y B (HTB con clase EF) en `qos_experimento_ab.sh` | qos.txt (prueba local) |
| Seguridad | Regla fail2ban para Asterisk y nftables con puertos mínimos y límite de tasa | `asterisk/fail2ban`, `hardening_security.sh` |
| Monitoreo | Uptime Kuma con monitores HTTPS y SIP-TLS; exportador SLA con valores reales | kuma.txt, captura de Grafana |
| IA local | faster-whisper (MIT) y Ollama con Qwen2.5 (Apache-2.0); acta publicada en Nextcloud | `Acta_Reunion_Andes_IA.md` (23 nov) |

## Mediciones de la validación local (22 de noviembre de 2026)
| Indicador | Meta | Resultado |
|---|---|---|
| Chat, entrega de mensaje (20 muestras) | ≤ 2 s p95 | p95 de 1,90 s |
| Presencia, cambio de estado (20 muestras) | ≤ 5 s | máximo de 0,54 s |
| Apertura de documento (5 muestras) | ≤ 5 s | media de 2,49 s, máximo de 3,38 s |
| Voz, lote SIPp (10 llamadas de 60 s al eco 600) | jitter ≤ 30 ms p95, pérdida ≤ 1 % | jitter p95 de 7 ms, pérdida 0 %; sin RTCP válido para RTT y MOS |
| Restauración PostgreSQL en base nueva | RTO ≤ 4 h | 1,2 s, 123 tablas coincidentes |
| QoS local (cuello de 5 Mbit/s, iperf3 a 8 Mbit/s) | pérdida ≤ 1 % | FIFO: 83,6 % de pérdida del audio recibido; HTB: clase EF 540 paquetes sin descartes, pero 60,8 % de pérdida en el sentido no marcado |

## Pendiente para el V305
RTT y MOS con dos Linphone por TLS, prueba A/B con llamadas reales que marquen EF en ambos sentidos, estadísticas WebRTC con tres participantes y TURN entre redes, hacking ético (nmap, SIPVicious, fail2ban) contra el servidor propio en red aislada, HTTPS del proveedor OIDC para dejar debug=false y cuenta administrativa nominal sin el administrador temporal.
