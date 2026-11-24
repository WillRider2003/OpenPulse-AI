#!/bin/sh
# =============================================================================
# OpenPulse AI - Prueba controlada A/B de colas de QoS (TA3)
# Configura la cola de salida de la interfaz del contenedor de Asterisk y muestra
# SOLO contadores reales. Las metricas de voz se leen de Asterisk durante la llamada.
#
# Uso dentro del contenedor:
#   sh qos_experimento_ab.sh fifo  [IFACE] [RATE]   Escenario A: una sola cola (tbf)
#   sh qos_experimento_ab.sh htb   [IFACE] [RATE]   Escenario B: HTB con clase EF prioritaria
#   sh qos_experimento_ab.sh estado [IFACE]         Contadores de tc
#   sh qos_experimento_ab.sh limpiar [IFACE]        Quita la cola
# Por defecto IFACE=eth0 y RATE=2mbit (cuello de botella del experimento).
#
# Procedimiento: aplicar un escenario, iniciar una llamada Linphone 1001 -> 1002,
# leer "asterisk -rx 'pjsip show channelstats'", lanzar la carga con iperf3 y volver
# a leer; luego repetir con el otro escenario y la MISMA carga y duracion.
# =============================================================================
MODO=${1:-estado}
IFACE=${2:-eth0}
RATE=${3:-2mbit}

date '+%Y-%m-%d %H:%M:%S %z'
case "$MODO" in
  fifo)
    tc qdisc del dev "$IFACE" root 2>/dev/null || true
    tc qdisc add dev "$IFACE" root tbf rate "$RATE" burst 32kbit latency 50ms
    echo "[A] Cola unica FIFO (tbf) a $RATE en $IFACE"
    ;;
  htb)
    tc qdisc del dev "$IFACE" root 2>/dev/null || true
    tc qdisc add dev "$IFACE" root handle 1: htb default 20
    tc class add dev "$IFACE" parent 1: classid 1:1 htb rate "$RATE"
    # Clase 1:10 -> voz marcada EF (DSCP 46 = TOS 0xb8), prioridad 0
    tc class add dev "$IFACE" parent 1:1 classid 1:10 htb rate 300kbit ceil "$RATE" prio 0
    # Clase 1:20 -> resto del trafico
    tc class add dev "$IFACE" parent 1:1 classid 1:20 htb rate 1700kbit ceil "$RATE" prio 1
    tc filter add dev "$IFACE" parent 1: protocol ip prio 1 u32 match ip dsfield 0xb8 0xfc flowid 1:10
    echo "[B] HTB a $RATE con clase prioritaria 1:10 para EF en $IFACE"
    ;;
  limpiar)
    tc qdisc del dev "$IFACE" root 2>/dev/null || true
    echo "Cola eliminada en $IFACE"
    ;;
esac

echo "--- tc qdisc show dev $IFACE"
tc qdisc show dev "$IFACE"
echo "--- tc -s class show dev $IFACE"
tc -s class show dev "$IFACE"
echo "--- pjsip show channelstats"
asterisk -rx "pjsip show channelstats" 2>/dev/null || true
