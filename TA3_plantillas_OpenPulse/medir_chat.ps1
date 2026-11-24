# ============================================================
#  TA3 OpenPulse AI - Medicion del tiempo de entrega del chat
#  Envia N mensajes a una sala de Talk y mide cuanto tarda
#  cada uno en estar disponible por la API. Calcula promedio,
#  maximo y percentil 95 (meta del SLA: <= 2 s).
#
#  Uso:
#    .\medir_chat.ps1 -IP 192.168.1.50 -Usuario avallejo -Clave CONTRASENA_APP -Token TOKEN_SALA -Veces 20
#
#  - CONTRASENA_APP: Nextcloud > Ajustes > Seguridad > crear contrasena de aplicacion
#  - TOKEN_SALA: la ultima parte de la URL de la conversacion en Talk
# ============================================================
param(
  [Parameter(Mandatory=$true)][string]$IP,
  [Parameter(Mandatory=$true)][string]$Usuario,
  [Parameter(Mandatory=$true)][string]$Clave,
  [Parameter(Mandatory=$true)][string]$Token,
  [int]$Veces = 20
)

$base = "http://$IP`:8080/ocs/v2.php/apps/spreed/api/v1/chat/$Token"
$pair = "$Usuario`:$Clave"
$auth = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
$headers = @{ "OCS-APIRequest" = "true"; "Authorization" = $auth; "Accept" = "application/json" }

Write-Host "Midiendo $Veces mensajes en la sala $Token ..." -ForegroundColor Cyan
$tiempos = @()

for ($i = 1; $i -le $Veces; $i++) {
    $texto = "Prueba de latencia #$i - $(Get-Date -Format HH:mm:ss.fff)"
    $body = @{ message = $texto } | ConvertTo-Json
    $t0 = Get-Date
    try {
        $r = Invoke-RestMethod -Uri $base -Method Post -Headers $headers -Body $body -ContentType "application/json; charset=utf-8"
        # Confirmamos que el mensaje ya aparece leyendo el ultimo de la sala
        $msgId = $r.ocs.data.id
        $leido = $false
        while (-not $leido -and ((Get-Date) - $t0).TotalSeconds -lt 10) {
            $g = Invoke-RestMethod -Uri "$base`?lookIntoFuture=0&limit=1" -Method Get -Headers $headers
            if ($g.ocs.data.id -eq $msgId) { $leido = $true }
        }
        $ms = ((Get-Date) - $t0).TotalMilliseconds
        $tiempos += $ms
        Write-Host ("  Mensaje {0,2}: {1,7:N0} ms" -f $i, $ms)
    } catch {
        Write-Host "  Mensaje $i: ERROR - $($_.Exception.Message)" -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 500
}

if ($tiempos.Count -eq 0) { Write-Host "No se pudo medir ningun mensaje. Revisa IP, usuario, clave y token." -ForegroundColor Red; exit 1 }

$orden = $tiempos | Sort-Object
$prom = ($tiempos | Measure-Object -Average).Average
$max  = ($tiempos | Measure-Object -Maximum).Maximum
$idx  = [math]::Ceiling($orden.Count * 0.95) - 1
$p95  = $orden[$idx]

Write-Host ""
Write-Host "================ RESULTADOS ================" -ForegroundColor Green
Write-Host ("Mensajes medidos : {0}" -f $tiempos.Count)
Write-Host ("Promedio         : {0:N0} ms" -f $prom)
Write-Host ("Maximo           : {0:N0} ms" -f $max)
Write-Host ("Percentil 95     : {0:N0} ms" -f $p95)
Write-Host ("Meta del SLA     : <= 2000 ms (percentil 95)")
if ($p95 -le 2000) { Write-Host "CUMPLE la meta del SLA" -ForegroundColor Green }
else { Write-Host "NO cumple la meta del SLA" -ForegroundColor Yellow }
Write-Host "============================================" -ForegroundColor Green
