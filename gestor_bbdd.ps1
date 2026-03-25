# Configuración de servicios como máximo de bases de datos para prácticas de administración
$maxActivos = 2

# ---------------- Comprobación de privilegios ----------------

# Comprueba si el script se esta ejecutando con privilegios de administrador.
# Devuelve $true si el usuario actual tiene el rol de administrador de Windows.
function EsAdministrador {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (EsAdministrador)) {
    Write-Host "AVISO!!: Este script necesita permisos de administrador para iniciar/detener servicios." -ForegroundColor Yellow
    Write-Host "Algunas funciones pueden no estar disponibles." -ForegroundColor Yellow
    Write-Host ""
    pause
}

# ---------------- Funciones básicas ----------------

# Busca servicios de Windows registrados cuyo nombre coincida con motores de BD conocidos
# (MySQL, MariaDB, PostgreSQL, MongoDB, SQL Server, WAMP, XAMPP).
# Devuelve un array de objetos de servicio.
function DetectarServicios {
    $servicios = @(Get-Service | Where-Object {$_.Name -match "MSSQL|mysql|maria|postgres|mongo|wamp|xampp"})
    return ,$servicios
}

# Ejecuta mysqld --version para determinar si el binario es MySQL o MariaDB.
# En XAMPP, por ejemplo, el ejecutable se llama mysqld.exe pero es MariaDB.
# Recibe la ruta base del entorno. Devuelve "MariaDB" o "MySQL".
function IdentificarMotorMySQL($basePath) {
    $mysqld = Join-Path $basePath "mysql\bin\mysqld.exe"
    if (-not (Test-Path $mysqld)) { return "MySQL" }
    $version = & $mysqld --version 2>&1 | Out-String
    if ($version -match "MariaDB") { return "MariaDB" }
    return "MySQL"
}

# Busca procesos de BD activos o disponibles en entornos locales (XAMPP, WAMP, Laragon, MAMP).
# Para cada entorno encontrado, detecta MySQL/MariaDB, PostgreSQL y MongoDB.
# Devuelve un array de objetos con nombre, estado, puerto, PID, RAM y scripts de inicio/parada.
function DetectarServidoresEntorno {
    $resultado = @()
    foreach ($nombre in @("XAMPP","WAMP","Laragon","MAMP")) {
        $basePath = BuscarEntornoEnUnidades $nombre
        if (-not $basePath) { continue }

        # MySQL/MariaDB: detectar motor real, el proceso siempre es mysqld
        $mysqlStart = Join-Path $basePath "mysql_start.bat"
        $mysqlStop  = Join-Path $basePath "mysql_stop.bat"
        $mysqldExe  = Join-Path $basePath "mysql\bin\mysqld.exe"

        if ((Test-Path $mysqldExe) -or (Test-Path $mysqlStart)) {
            $motorNombre = IdentificarMotorMySQL $basePath
            $startScript = if (Test-Path $mysqlStart) { $mysqlStart } else { $null }
            $stopScript  = if (Test-Path $mysqlStop)  { $mysqlStop }  else { $null }

            $proc = Get-Process -Name mysqld -ErrorAction SilentlyContinue |
                    Where-Object { $_.Path -and $_.Path -like "$basePath*" } |
                    Select-Object -First 1

            if ($proc) {
                $ram = [math]::Round($proc.WorkingSet/1MB,1)
                $resultado += [PSCustomObject]@{
                    Nombre      = "$motorNombre ($nombre)"
                    Tipo        = $nombre
                    Estado      = "Running"
                    Puerto      = 3306
                    RAM         = $ram
                    PID         = $proc.Id
                    BasePath    = $basePath
                    ProcName    = "mysqld"
                    StartScript = $startScript
                    StopScript  = $stopScript
                }
            }
            elseif ($startScript) {
                $resultado += [PSCustomObject]@{
                    Nombre      = "$motorNombre ($nombre)"
                    Tipo        = $nombre
                    Estado      = "Stopped"
                    Puerto      = 3306
                    RAM         = 0
                    PID         = 0
                    BasePath    = $basePath
                    ProcName    = "mysqld"
                    StartScript = $startScript
                    StopScript  = $stopScript
                }
            }
        }

        # PostgreSQL
        $pgProc = Get-Process -Name postgres -ErrorAction SilentlyContinue |
                  Where-Object { $_.Path -and $_.Path -like "$basePath*" } |
                  Select-Object -First 1
        if ($pgProc) {
            $ram = [math]::Round($pgProc.WorkingSet/1MB,1)
            $resultado += [PSCustomObject]@{
                Nombre = "PostgreSQL ($nombre)"; Tipo = $nombre; Estado = "Running"
                Puerto = 5432; RAM = $ram; PID = $pgProc.Id; BasePath = $basePath
                ProcName = "postgres"; StartScript = $null; StopScript = $null
            }
        }

        # MongoDB
        $mongoProc = Get-Process -Name mongod -ErrorAction SilentlyContinue |
                     Where-Object { $_.Path -and $_.Path -like "$basePath*" } |
                     Select-Object -First 1
        if ($mongoProc) {
            $ram = [math]::Round($mongoProc.WorkingSet/1MB,1)
            $resultado += [PSCustomObject]@{
                Nombre = "MongoDB ($nombre)"; Tipo = $nombre; Estado = "Running"
                Puerto = 27017; RAM = $ram; PID = $mongoProc.Id; BasePath = $basePath
                ProcName = "mongod"; StartScript = $null; StopScript = $null
            }
        }
    }
    return ,$resultado
}

# Busca archivos de configuracion de la BD dentro del entorno local.
# Segun el tipo de proceso (mysqld, postgres, mongod), busca en rutas habituales
# como my.ini, postgresql.conf o mongod.cfg. Devuelve un array con las rutas encontradas.
function BuscarConfigBD($basePath, $procName) {
    $configs = @()
    if ($procName -match "mysqld|mariadbd") {
        $candidatos = @(
            (Join-Path $basePath "mysql\bin\my.ini"),
            (Join-Path $basePath "mysql\my.ini"),
            (Join-Path $basePath "bin\mysql\my.ini"),
            (Join-Path $basePath "mysql\bin\my.cnf"),
            (Join-Path $basePath "bin\mariadb\my.ini")
        )
        foreach ($c in $candidatos) {
            if (Test-Path $c) { $configs += $c }
        }
    }
    elseif ($procName -match "postgres") {
        $candidatos = @(
            (Join-Path $basePath "pgsql\data\postgresql.conf"),
            (Join-Path $basePath "postgres\data\postgresql.conf"),
            (Join-Path $basePath "data\postgresql.conf")
        )
        foreach ($c in $candidatos) {
            if (Test-Path $c) { $configs += $c }
        }
    }
    elseif ($procName -match "mongod") {
        $candidatos = @(
            (Join-Path $basePath "MongoDB\Server\8.2\bin\mongod.cfg"),
            (Join-Path $basePath "bin\mongod.cfg")
        )
        foreach ($c in $candidatos) {
            if (Test-Path $c) { $configs += $c }
        }
    }
    return $configs
}

# Modifica el puerto en el archivo de configuracion de una BD.
# Usa expresiones regulares para reemplazar el valor del puerto segun el tipo de motor:
# - MySQL/MariaDB: port=XXXX en my.ini
# - PostgreSQL: port = XXXX en postgresql.conf
# - MongoDB: port: XXXX en mongod.cfg
function CambiarPuertoConfig($configPath, $procName, $nuevoPuerto) {
    $contenido = Get-Content $configPath -Raw
    if ($procName -match "mysqld|mariadbd") {
        # Reemplazar port=XXXX por port=$nuevoPuerto
        $contenido = $contenido -replace '(?m)^(\s*port\s*=\s*)\d+', "`${1}$nuevoPuerto"
    }
    elseif ($procName -match "postgres") {
        $contenido = $contenido -replace "(?m)^(\s*#?\s*port\s*=\s*)\d+", "`${1}$nuevoPuerto"
    }
    elseif ($procName -match "mongod") {
        $contenido = $contenido -replace '(?m)^(\s*port:\s*)\d+', "`${1}$nuevoPuerto"
    }
    Set-Content $configPath -Value $contenido -Encoding UTF8
}

# Inicia una BD de un entorno local (XAMPP, WAMP, etc.) usando su script de arranque.
# Si el puerto esta ocupado, ofrece al usuario cambiar el puerto automaticamente
# modificando el archivo de configuracion antes de iniciar.
function IniciarEntorno($entrada) {
    if (-not $entrada.StartScript -or -not (Test-Path $entrada.StartScript)) {
        Write-Host "No se encontro script de inicio para $($entrada.Nombre)" -ForegroundColor Red
        return
    }
    $puerto = $entrada.Puerto
    if ($puerto -gt 0 -and (PuertoOcupado $puerto)) {
        Write-Host "Puerto $puerto ya esta ocupado." -ForegroundColor Red
        Write-Host ""
        $configs = BuscarConfigBD $entrada.BasePath $entrada.ProcName
        if ($configs.Count -gt 0) {
            Write-Host "Se puede cambiar el puerto en la configuracion." -ForegroundColor Yellow
            $resp = Read-Host "Desea cambiar el puerto? (s/n)"
            if ($resp -eq "s") {
                $nuevoPuerto = Read-Host "Introduce el nuevo puerto"
                if ($nuevoPuerto -match '^\d+$' -and [int]$nuevoPuerto -ge 1024 -and [int]$nuevoPuerto -le 65535) {
                    if (PuertoOcupado ([int]$nuevoPuerto)) {
                        Write-Host "El puerto $nuevoPuerto tambien esta ocupado." -ForegroundColor Red
                        return
                    }
                    foreach ($cfg in $configs) {
                        CambiarPuertoConfig $cfg $entrada.ProcName ([int]$nuevoPuerto)
                        Write-Host "Puerto cambiado a $nuevoPuerto en $cfg" -ForegroundColor Green
                    }
                    Write-Host "Iniciando $($entrada.Nombre) en puerto $nuevoPuerto..." -ForegroundColor Yellow
                    Start-Process -FilePath $entrada.StartScript -WorkingDirectory $entrada.BasePath -WindowStyle Hidden
                    Start-Sleep 3
                    $proc = Get-Process -Name $entrada.ProcName -ErrorAction SilentlyContinue |
                            Where-Object { $_.Path -and $_.Path -like "$($entrada.BasePath)*" } |
                            Select-Object -First 1
                    if ($proc) {
                        Write-Host "$($entrada.Nombre) iniciado correctamente en puerto $nuevoPuerto (PID: $($proc.Id))" -ForegroundColor Green
                    } else {
                        Write-Host "No se pudo verificar el inicio de $($entrada.Nombre)." -ForegroundColor Red
                    }
                } else {
                    Write-Host "Puerto no valido. Debe estar entre 1024 y 65535." -ForegroundColor Red
                }
            }
        } else {
            Write-Host "No se encontro archivo de configuracion para cambiar el puerto." -ForegroundColor Yellow
        }
        return
    }
    Write-Host "Iniciando $($entrada.Nombre)..." -ForegroundColor Yellow
    Start-Process -FilePath $entrada.StartScript -WorkingDirectory $entrada.BasePath -WindowStyle Hidden
    Start-Sleep 3
    $proc = Get-Process -Name $entrada.ProcName -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -and $_.Path -like "$($entrada.BasePath)*" } |
            Select-Object -First 1
    if ($proc) {
        Write-Host "$($entrada.Nombre) iniciado correctamente (PID: $($proc.Id))" -ForegroundColor Green
    } else {
        Write-Host "No se pudo verificar el inicio de $($entrada.Nombre)." -ForegroundColor Red
    }
}

# Detiene una BD de un entorno local usando 3 metodos en cascada:
# 1. mysqladmin shutdown (para MySQL/MariaDB) o pg_ctl stop (para PostgreSQL)
# 2. Si falla, termina el proceso directamente con Stop-Process
# 3. Si nada funciona, muestra instrucciones para hacerlo manualmente
function DetenerEntorno($entrada) {
    Write-Host "Deteniendo $($entrada.Nombre)..." -ForegroundColor Yellow

    if ($entrada.PID -le 0) {
        Write-Host "No hay proceso activo de $($entrada.Nombre)." -ForegroundColor Red
        return
    }

    $detenido = $false

    # Metodo 1: mysqladmin shutdown (MySQL/MariaDB)
    if ($entrada.ProcName -match "mysqld|mariadbd") {
        $mysqladmin = Join-Path $entrada.BasePath "mysql\bin\mysqladmin.exe"
        if (Test-Path $mysqladmin) {
            Write-Host "  Enviando shutdown via mysqladmin..." -ForegroundColor Gray
            & $mysqladmin -u root shutdown 2>$null
            Start-Sleep 3
            $proc = Get-Process -Id $entrada.PID -ErrorAction SilentlyContinue
            if (-not $proc) { $detenido = $true }
        }
    }

    # Metodo 2: pg_ctl stop (PostgreSQL)
    if (-not $detenido -and $entrada.ProcName -match "postgres") {
        $pgctl = Get-ChildItem -Path $entrada.BasePath -Filter "pg_ctl.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pgctl) {
            $dataDir = Get-ChildItem -Path $entrada.BasePath -Filter "postgresql.conf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($dataDir) {
                Write-Host "  Enviando stop via pg_ctl..." -ForegroundColor Gray
                & $pgctl.FullName stop -D $dataDir.DirectoryName -m fast 2>$null
                Start-Sleep 3
                $proc = Get-Process -Id $entrada.PID -ErrorAction SilentlyContinue
                if (-not $proc) { $detenido = $true }
            }
        }
    }

    # Metodo 3: Terminar proceso directamente
    if (-not $detenido) {
        Write-Host "  Terminando proceso (PID: $($entrada.PID))..." -ForegroundColor Gray
        Stop-Process -Id $entrada.PID -Force -ErrorAction SilentlyContinue
        Start-Sleep 2
        $proc = Get-Process -Id $entrada.PID -ErrorAction SilentlyContinue
        if (-not $proc) { $detenido = $true }
    }

    if ($detenido) {
        Write-Host "$($entrada.Nombre) detenido correctamente." -ForegroundColor Green
    } else {
        Write-Host "$($entrada.Nombre) no se pudo detener." -ForegroundColor Red
        Write-Host "Intenta cerrarlo desde el panel de control de $($entrada.Tipo) o con el administrador de tareas." -ForegroundColor Yellow
    }
}

# Reinicia una BD de entorno local deteniendo primero y luego iniciando.
function ReiniciarEntorno($entrada) {
    DetenerEntorno $entrada
    Start-Sleep 1
    IniciarEntorno $entrada
}

# Busca la carpeta de instalacion de un entorno (XAMPP, WAMP, Laragon, MAMP)
# recorriendo todas las unidades del sistema (C:, D:, E:, etc.) y Program Files.
# Devuelve la primera ruta encontrada o $null si no existe.
function BuscarEntornoEnUnidades($nombre) {
    $unidades = @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root } | ForEach-Object { $_.Root })
    $carpetas = switch ($nombre) {
        "XAMPP"   { @("xampp") }
        "WAMP"    { @("wamp64","wamp") }
        "Laragon" { @("laragon") }
        "MAMP"    { @("MAMP","mamp") }
    }
    foreach ($u in $unidades) {
        foreach ($c in $carpetas) {
            $ruta = Join-Path $u $c
            if (Test-Path $ruta) { return $ruta }
        }
    }
    # Tambien buscar en Program Files
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $pf) { continue }
        foreach ($c in $carpetas) {
            $ruta = Join-Path $pf $c
            if (Test-Path $ruta) { return $ruta }
        }
    }
    return $null
}

# Muestra por pantalla los procesos de BD activos dentro de un entorno local.
# Filtra solo procesos de bases de datos (mysqld, postgres, mongod, sqlservr)
# que esten corriendo desde la ruta del entorno indicado.
function MostrarProcesosEntorno($basePath, $nombre) {
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path -like "$basePath*" -and $_.ProcessName -match "mysqld|mariadbd|postgres|mongod|sqlservr"
    }
    if ($procs) {
        foreach ($p in $procs) {
            $info = ""
            if ($p.ProcessName -match "mysqld")       { $info = " (puerto 3306)" }
            if ($p.ProcessName -match "mariadbd")      { $info = " (puerto 3306)" }
            if ($p.ProcessName -match "postgres")      { $info = " (puerto 5432)" }
            if ($p.ProcessName -match "mongod")        { $info = " (puerto 27017)" }
            if ($p.ProcessName -match "sqlservr")      { $info = " (puerto 1433)" }
            Write-Host "  -> $($p.ProcessName) EN EJECUCION$info - PID: $($p.Id)" -ForegroundColor Green
        }
    } else {
        Write-Host "  -> Ningun proceso de BD de $nombre en ejecucion" -ForegroundColor Gray
    }
}

# Detecta entornos de desarrollo local instalados (XAMPP, WAMP, Laragon, MAMP, Docker)
# en todas las unidades del sistema. Para cada uno muestra si esta instalado y que
# procesos de BD tiene activos. Tambien detecta contenedores Docker de BD.
function DetectarEntornosWeb {
    Write-Host ""
    Write-Host "DETECCION DE ENTORNOS LOCALES"
    Write-Host "-----------------------------"
    $encontrado = $false

    # --- XAMPP ---
    $xamppPath = BuscarEntornoEnUnidades "XAMPP"
    if ($xamppPath) {
        $encontrado = $true
        Write-Host "XAMPP detectado en $xamppPath" -ForegroundColor Yellow
        MostrarProcesosEntorno $xamppPath "XAMPP"
    }

    # --- WAMP ---
    $wampPath = BuscarEntornoEnUnidades "WAMP"
    if ($wampPath) {
        $encontrado = $true
        Write-Host "WAMP detectado en $wampPath" -ForegroundColor Yellow
        MostrarProcesosEntorno $wampPath "WAMP"
    }

    # --- Laragon ---
    $laragonPath = BuscarEntornoEnUnidades "Laragon"
    if ($laragonPath) {
        $encontrado = $true
        Write-Host "Laragon detectado en $laragonPath" -ForegroundColor Yellow
        MostrarProcesosEntorno $laragonPath "Laragon"
    }

    # --- MAMP ---
    $mampPath = BuscarEntornoEnUnidades "MAMP"
    if ($mampPath) {
        $encontrado = $true
        Write-Host "MAMP detectado en $mampPath" -ForegroundColor Yellow
        MostrarProcesosEntorno $mampPath "MAMP"
    }

    # --- Docker ---
    $docker = Get-Service -Name "docker" -ErrorAction SilentlyContinue
    if ($docker) {
        $encontrado = $true
        if ($docker.Status -eq "Running") {
            Write-Host "Docker instalado y EN EJECUCION" -ForegroundColor Green
            $dockerExe = Get-Command docker -ErrorAction SilentlyContinue
            if ($dockerExe) {
                $containers = docker ps --format "{{.Names}}  {{.Image}}  {{.Ports}}" 2>$null
                if ($containers) {
                    $dbContainers = $containers | Where-Object { $_ -match "mysql|maria|postgres|mongo|mssql|redis" }
                    if ($dbContainers) {
                        Write-Host "  Contenedores de BD activos:" -ForegroundColor Yellow
                        foreach ($c in $dbContainers) { Write-Host "  -> $c" -ForegroundColor Green }
                    }
                }
            }
        } else {
            Write-Host "Docker instalado pero DETENIDO" -ForegroundColor Red
        }
    }

    # --- Deteccion por procesos activos (aunque no se encuentre la carpeta) ---
    $procsDB = Get-Process -Name mysqld,mariadbd,postgres,mongod,sqlservr -ErrorAction SilentlyContinue
    $noMostrados = @()
    foreach ($p in $procsDB) {
        $path = $null
        try { $path = $p.Path } catch {}
        if (-not $path) { continue }
        $yaDetectado = $false
        foreach ($ruta in @($xamppPath, $wampPath, $laragonPath, $mampPath)) {
            if ($ruta -and $path -like "$ruta*") { $yaDetectado = $true; break }
        }
        if (-not $yaDetectado) { $noMostrados += $p }
    }
    if ($noMostrados.Count -gt 0) {
        $encontrado = $true
        Write-Host ""
        Write-Host "OTROS PROCESOS DE BD DETECTADOS:" -ForegroundColor Yellow
        foreach ($p in $noMostrados) {
            $info = ""
            if ($p.ProcessName -match "mysqld")      { $info = " (puerto 3306)" }
            if ($p.ProcessName -match "mariadbd")     { $info = " (puerto 3306)" }
            if ($p.ProcessName -match "postgres")     { $info = " (puerto 5432)" }
            if ($p.ProcessName -match "mongod")       { $info = " (puerto 27017)" }
            if ($p.ProcessName -match "sqlservr")     { $info = " (puerto 1433)" }
            Write-Host "  -> $($p.ProcessName)$info - PID: $($p.Id) - $($p.Path)" -ForegroundColor Cyan
        }
    }

    if (-not $encontrado) {
        Write-Host "No se detecto ningun entorno local (XAMPP, WAMP, Laragon, MAMP, Docker)" -ForegroundColor Gray
    }
}

# Devuelve el puerto por defecto asociado a un servicio Windows de BD
# segun su nombre: MySQL/MariaDB=3306, PostgreSQL=5432, MongoDB=27017, SQL Server=1433.
function ObtenerPuerto($servicio){
    if($servicio.Name -match "mysql"){ return 3306 }
    if($servicio.Name -match "maria"){ return 3306 }
    if($servicio.Name -match "postgres"){ return 5432 }
    if($servicio.Name -match "mongo"){ return 27017 }
    if($servicio.Name -match "MSSQL"){ return 1433 }
    return 0
}

# Comprueba si un puerto TCP esta en uso (LISTENING) usando netstat.
# Devuelve $true si hay algun proceso escuchando en ese puerto.
function PuertoOcupado($puerto){
    $linea = netstat -ano | Select-String "LISTENING" | Select-String ":$puerto\s"
    if($linea){return $true} else {return $false}
}

# Calcula la memoria RAM (en MB) que esta usando un servicio Windows de BD.
# Obtiene el PID del servicio via WMI y consulta el WorkingSet del proceso.
function ObtenerRAM($servicio){
    $svcWmi = Get-CimInstance Win32_Service -Filter "Name='$($servicio.Name)'" -ErrorAction SilentlyContinue
    if ($svcWmi -and $svcWmi.ProcessId -gt 0) {
        $p = Get-Process -Id $svcWmi.ProcessId -ErrorAction SilentlyContinue
        if ($p) { return [math]::Round($p.WorkingSet/1MB,1) }
    }
    return 0
}

# ---------------- Diagnóstico y autocorrección ----------------

# Diagnostica por que un servicio de BD no puede iniciarse.
# Revisa si el puerto esta ocupado (y por que proceso), si hay RAM suficiente,
# y ofrece detener el proceso que bloquea el puerto.
function Diagnosticar($servicio){
    Write-Host ""
    Write-Host "DIAGNOSTICO DEL PROBLEMA" -ForegroundColor Yellow
    Write-Host "------------------------"
    $puerto = ObtenerPuerto $servicio

    if(PuertoOcupado $puerto){
        $linea = netstat -ano | Select-String "LISTENING" | Select-String ":$puerto\s" | Select-Object -First 1
        if($linea){
            $textoLinea = $linea.Line
            $pidProceso = ($textoLinea -split "\s+")[-1]
            $proceso = Get-Process -Id $pidProceso -ErrorAction SilentlyContinue
            if($proceso){
                Write-Host "Puerto $puerto ocupado por $($proceso.ProcessName)" -ForegroundColor Red
                $accion = Read-Host "¿Quieres detener este proceso para liberar el puerto? (s/n)"
                if($accion -eq "s"){
                    Stop-Process -Id $pidProceso -Force
                    Write-Host "Proceso detenido, intenta iniciarlo de nuevo." -ForegroundColor Green
                }
            } else {
                Write-Host "Puerto $puerto ocupado (PID $pidProceso)" -ForegroundColor Red
            }
        }
        return
    }

    $totalRAM = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024
    if($totalRAM -lt 500){Write-Host "RAM insuficiente para iniciar el servicio." -ForegroundColor Red; return}

    Write-Host "No se detecto ninguna causa con el método automatico." -ForegroundColor Yellow
    Write-Host "Revisa archivo de configuracion del servidor."
}

# Inicia un servicio Windows de BD usando Start-Service.
# Verifica que no se supere el maximo de servidores activos y que el puerto este libre.
# Si el puerto esta ocupado, muestra instrucciones especificas para cambiar el puerto
# segun el tipo de motor (MySQL, PostgreSQL, SQL Server, MongoDB).
function IniciarServidor($servicio,$activos){
    if($activos -ge $maxActivos){
        Write-Host ""
        Write-Host "Solo se permiten $maxActivos servidores activos." -ForegroundColor Red
        pause
        return
    }

    $puerto = ObtenerPuerto $servicio

    if(PuertoOcupado $puerto){
        Write-Host ""
        Write-Host "Puerto $puerto ocupado." -ForegroundColor Red
        Write-Host ""
        Write-Host "Para cambiar el puerto de un servicio Windows nativo, edita su archivo de configuracion:" -ForegroundColor Yellow
        if ($servicio.Name -match "mysql|maria") {
            Write-Host "  MySQL/MariaDB: Editar my.ini o my.cnf" -ForegroundColor Cyan
            Write-Host "  Buscar la linea 'port=3306' y cambiar el numero" -ForegroundColor Cyan
            Write-Host "  Ruta habitual: C:\ProgramData\MySQL\MySQL Server X.X\my.ini" -ForegroundColor Cyan
        }
        elseif ($servicio.Name -match "postgres") {
            Write-Host "  PostgreSQL: Editar postgresql.conf" -ForegroundColor Cyan
            Write-Host "  Buscar la linea 'port = 5432' y cambiar el numero" -ForegroundColor Cyan
            Write-Host "  Ruta habitual: C:\Program Files\PostgreSQL\XX\data\postgresql.conf" -ForegroundColor Cyan
        }
        elseif ($servicio.Name -match "MSSQL") {
            Write-Host "  SQL Server: Usar SQL Server Configuration Manager" -ForegroundColor Cyan
            Write-Host "  Protocolos de SQL Server -> TCP/IP -> Propiedades -> Direcciones IP" -ForegroundColor Cyan
            Write-Host "  Cambiar el campo 'Puerto TCP' en la seccion IPAll" -ForegroundColor Cyan
        }
        elseif ($servicio.Name -match "mongo") {
            Write-Host "  MongoDB: Editar mongod.cfg" -ForegroundColor Cyan
            Write-Host "  Buscar 'port: 27017' bajo la seccion 'net:' y cambiar el numero" -ForegroundColor Cyan
            Write-Host "  Ruta habitual: C:\Program Files\MongoDB\Server\X.X\bin\mongod.cfg" -ForegroundColor Cyan
        }
        Write-Host ""
        Write-Host "Despues de cambiar el puerto, reinicia el servicio desde aqui." -ForegroundColor Yellow
        Diagnosticar $servicio
        pause
        return
    }

    try{
        Start-Service $servicio.Name -ErrorAction Stop
        Start-Sleep 2
        $estado=(Get-Service $servicio.Name).Status
        if($estado -ne "Running"){
            Write-Host "No se pudo iniciar el servidor." -ForegroundColor Red
            Diagnosticar $servicio
        }else{
            Write-Host "Servidor iniciado correctamente." -ForegroundColor Green
        }
    }catch{
        Write-Host "Error al iniciar el servicio." -ForegroundColor Red
        Diagnosticar $servicio
    }
    pause
}

# ---------------- Modo práctica ----------------

# Inicia rapidamente un conjunto predefinido de servicios para practicas:
# Tipo 1 = MySQL + MongoDB, Tipo 2 = PostgreSQL.
# Util para preparar el entorno de clase con un solo comando.
function ModoPractica($tipo){
    switch($tipo){
		1 {
            Write-Host ""
            Write-Host "Iniciando entorno MySQL + MongoDB" -ForegroundColor Cyan
            # Intentamos iniciar usando comodines por si el nombre varía por la versión
            Start-Service "mysql*" -ErrorAction SilentlyContinue
            Start-Service "MongoDB*" -ErrorAction SilentlyContinue
        }
        2 {
            Write-Host ""
            Write-Host "Iniciando entorno PostgreSQL" -ForegroundColor Cyan
            Start-Service "postgresql*" -ErrorAction SilentlyContinue
        }
		Default {
            Write-Host "Opción no válida" -ForegroundColor Red
        }
    }
    pause
}

# ---------------- Ayuda ----------------

# Muestra instrucciones para configurar los servicios de BD en modo de inicio manual,
# tanto por interfaz grafica (services.msc) como por linea de comandos (sc config).
# Evita que los servidores arranquen automaticamente con Windows.
function AyudaServicios{
    Clear-Host
    Write-Host "CONFIGURAR SERVICIOS EN MODO MANUAL"
    Write-Host "-----------------------------------"
    Write-Host "Para evitar que los servidores se inicien automaticamente:"
    Write-Host ""
    Write-Host "Metodo grafico, pulsa tecla Windows + R:"
    Write-Host "1 Abrir services.msc"
    Write-Host "2 Buscar el servidor de base de datos"
    Write-Host "3 Cambiar 'Tipo de inicio' a MANUAL"
    Write-Host "-----------------------------------"
    Write-Host "Metodo comando administrador:"
    Write-Host ""
    Write-Host "sc config MySQL start= demand"
    Write-Host "sc config MongoDB start= demand"
    Write-Host "sc config postgresql-x64-15 start= demand"
    Write-Host "sc config MSSQLSERVER start= demand"
    Write-Host ""
    pause
}

# ---------------- Resetear password root ----------------

# Busca el ejecutable mysqld.exe en entornos locales (XAMPP, WAMP, Laragon, MAMP)
# y en el PATH del sistema. Devuelve un hashtable con la ruta del exe, la ruta base
# del entorno y el tipo, o $null si no se encuentra.
function BuscarMysqldExe {
    # Buscar en entornos locales
    foreach ($nombre in @("XAMPP","WAMP","Laragon","MAMP")) {
        $basePath = BuscarEntornoEnUnidades $nombre
        if ($basePath) {
            $exe = Join-Path $basePath "mysql\bin\mysqld.exe"
            if (Test-Path $exe) {
                return @{ Exe = $exe; BasePath = $basePath; Tipo = $nombre }
            }
        }
    }
    # Buscar en PATH
    $enPath = Get-Command mysqld.exe -ErrorAction SilentlyContinue
    if ($enPath) {
        return @{ Exe = $enPath.Source; BasePath = (Split-Path (Split-Path $enPath.Source)); Tipo = "Instalacion local" }
    }
    return $null
}

# Busca el cliente mysql.exe en entornos locales y en el PATH del sistema.
# Se usa para ejecutar comandos SQL durante el reseteo de password root.
# Devuelve la ruta completa del exe o $null si no se encuentra.
function BuscarMysqlExe {
    foreach ($nombre in @("XAMPP","WAMP","Laragon","MAMP")) {
        $basePath = BuscarEntornoEnUnidades $nombre
        if ($basePath) {
            $exe = Join-Path $basePath "mysql\bin\mysql.exe"
            if (Test-Path $exe) { return $exe }
        }
    }
    $enPath = Get-Command mysql.exe -ErrorAction SilentlyContinue
    if ($enPath) { return $enPath.Source }
    return $null
}

# Resetea la contraseña root de MySQL/MariaDB en 4 pasos:
# 1. Detiene el servidor, 2. Lo inicia en modo skip-grant-tables,
# 3. Ejecuta ALTER USER para cambiar la contraseña,
# 4. Detiene el servidor inseguro para que se reinicie normalmente.
function ResetearPasswordRoot {
    Clear-Host
    Write-Host "======================================"
    Write-Host "  RESETEAR PASSWORD ROOT MySQL/MariaDB"
    Write-Host "======================================"
    Write-Host ""

    if (-not (EsAdministrador)) {
        Write-Host "Se necesitan permisos de administrador para esta operacion." -ForegroundColor Red
        pause
        return
    }

    $infoMysqld = BuscarMysqldExe
    if (-not $infoMysqld) {
        Write-Host "No se encontro mysqld.exe en el sistema." -ForegroundColor Red
        pause
        return
    }

    $mysqlExe = BuscarMysqlExe
    if (-not $mysqlExe) {
        Write-Host "No se encontro mysql.exe (cliente) en el sistema." -ForegroundColor Red
        pause
        return
    }

    $mysqldExe = $infoMysqld.Exe
    $basePath  = $infoMysqld.BasePath
    $tipo      = $infoMysqld.Tipo

    Write-Host "Motor encontrado: $tipo" -ForegroundColor Cyan
    Write-Host "mysqld: $mysqldExe" -ForegroundColor Gray
    Write-Host "mysql:  $mysqlExe" -ForegroundColor Gray
    Write-Host ""
    Write-Host "ATENCION: Este proceso detendra el servidor MySQL/MariaDB temporalmente." -ForegroundColor Yellow
    Write-Host ""
    $confirmar = Read-Host "Continuar? (s/n)"
    if ($confirmar -ne "s") { return }

    # Solicitar nueva password
    $nuevaPass = Read-Host "Introduce la nueva password para root"
    if ([string]::IsNullOrWhiteSpace($nuevaPass)) {
        Write-Host "La password no puede estar vacia." -ForegroundColor Red
        pause
        return
    }
    $confirmarPass = Read-Host "Repite la nueva password"
    if ($nuevaPass -ne $confirmarPass) {
        Write-Host "Las passwords no coinciden." -ForegroundColor Red
        pause
        return
    }

    Write-Host ""
    Write-Host "Paso 1: Deteniendo servidor MySQL/MariaDB..." -ForegroundColor Yellow

    # Detener el proceso mysqld actual
    $procMysql = Get-Process -Name mysqld -ErrorAction SilentlyContinue
    if ($procMysql) {
        # Intentar shutdown limpio
        $mysqladmin = Join-Path (Split-Path $mysqlExe) "mysqladmin.exe"
        if (Test-Path $mysqladmin) {
            & $mysqladmin -u root shutdown 2>$null
            Start-Sleep 3
        }
        # Si sigue vivo, forzar
        $procMysql = Get-Process -Name mysqld -ErrorAction SilentlyContinue
        if ($procMysql) {
            Stop-Process -Name mysqld -Force -ErrorAction SilentlyContinue
            Start-Sleep 2
        }
    }

    $procCheck = Get-Process -Name mysqld -ErrorAction SilentlyContinue
    if ($procCheck) {
        Write-Host "No se pudo detener MySQL/MariaDB." -ForegroundColor Red
        pause
        return
    }
    Write-Host "Servidor detenido." -ForegroundColor Green

    Write-Host "Paso 2: Iniciando en modo skip-grant-tables..." -ForegroundColor Yellow

    # Buscar my.ini para el datadir
    $myIni = Join-Path $basePath "mysql\bin\my.ini"
    $args_mysqld = @("--skip-grant-tables", "--skip-networking")
    if (Test-Path $myIni) {
        $args_mysqld = @("--defaults-file=$myIni", "--skip-grant-tables", "--skip-networking")
    }

    $procSkip = Start-Process -FilePath $mysqldExe -ArgumentList $args_mysqld -WindowStyle Hidden -PassThru
    Start-Sleep 4

    if ($procSkip.HasExited) {
        Write-Host "No se pudo iniciar mysqld en modo seguro." -ForegroundColor Red
        pause
        return
    }
    Write-Host "Servidor iniciado en modo seguro (PID: $($procSkip.Id))" -ForegroundColor Green

    Write-Host "Paso 3: Cambiando password de root..." -ForegroundColor Yellow

    # Detectar si es MariaDB o MySQL para usar la query correcta
    $version = & $mysqldExe --version 2>&1 | Out-String
    $esMariaDB = $version -match "MariaDB"

    # Escapar comillas simples en la password para evitar inyeccion SQL
    $passEscapada = $nuevaPass -replace "'", "''"

    if ($esMariaDB) {
        $sql = "FLUSH PRIVILEGES; ALTER USER 'root'@'localhost' IDENTIFIED BY '$passEscapada'; FLUSH PRIVILEGES;"
    } else {
        $sql = "FLUSH PRIVILEGES; ALTER USER 'root'@'localhost' IDENTIFIED BY '$passEscapada'; FLUSH PRIVILEGES;"
    }

    $resultadoSQL = echo $sql | & $mysqlExe -u root --port=0 --socket=mysql 2>&1 | Out-String

    # Metodo alternativo si el anterior falla
    if ($resultadoSQL -match "ERROR") {
        $sql2 = "FLUSH PRIVILEGES; SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$passEscapada'); FLUSH PRIVILEGES;"
        $resultadoSQL = echo $sql2 | & $mysqlExe -u root --port=0 --socket=mysql 2>&1 | Out-String
    }

    Write-Host "Paso 4: Deteniendo servidor en modo seguro..." -ForegroundColor Yellow
    Stop-Process -Id $procSkip.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep 2

    if ($resultadoSQL -match "ERROR") {
        Write-Host "Hubo un problema al cambiar la password:" -ForegroundColor Red
        Write-Host $resultadoSQL -ForegroundColor Red
        Write-Host ""
        Write-Host "Puedes intentar manualmente:" -ForegroundColor Yellow
        Write-Host "1. Abrir cmd como administrador" -ForegroundColor Cyan
        Write-Host "2. Ir a la carpeta bin de MySQL: cd $(Split-Path $mysqldExe)" -ForegroundColor Cyan
        Write-Host "3. mysqld --skip-grant-tables --skip-networking" -ForegroundColor Cyan
        Write-Host "4. En otra ventana: mysql -u root" -ForegroundColor Cyan
        Write-Host "5. FLUSH PRIVILEGES;" -ForegroundColor Cyan
        Write-Host "6. ALTER USER 'root'@'localhost' IDENTIFIED BY 'nuevapass';" -ForegroundColor Cyan
    } else {
        Write-Host ""
        Write-Host "Password de root cambiada correctamente." -ForegroundColor Green
        Write-Host "Ahora puedes iniciar el servidor normalmente desde el menu." -ForegroundColor Green
    }
    pause
}

# ---------------- Diagnóstico completo ----------------

# Realiza un diagnostico completo del equipo mostrando:
# - Servicios Windows de BD detectados y su estado
# - Servidores de BD encontrados en entornos locales
# - Puertos ocupados y posibles conflictos
# - Uso de memoria RAM por cada servidor activo
function DiagnosticoCompleto{
    Clear-Host
    Write-Host "======================================"
    Write-Host "  DIAGNOSTICO COMPLETO DEL EQUIPO"
    Write-Host "======================================"
    Write-Host ""

    $servicios = DetectarServicios
    $entornos  = DetectarServidoresEntorno

    Write-Host "SERVIDORES DE BASE DE DATOS"
    foreach($s in $servicios){
        $puerto = ObtenerPuerto $s
        $ram = ObtenerRAM $s
        if($s.Status -eq "Running"){
            Write-Host "$($s.Name) ACTIVO  RAM:${ram}MB  PUERTO:$puerto" -ForegroundColor Green
        }else{
            Write-Host "$($s.Name) DETENIDO  PUERTO:$puerto" -ForegroundColor Red
        }
    }
    foreach ($e in $entornos) {
        if ($e.Estado -eq "Running") {
            Write-Host "$($e.Nombre) ACTIVO  RAM:$($e.RAM)MB  PUERTO:$($e.Puerto)" -ForegroundColor Cyan
        } else {
            Write-Host "$($e.Nombre) DETENIDO  PUERTO:$($e.Puerto)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "PUERTOS USADOS POR LAS BASES DE DATOS"
    $puertos = @(1433,3306,5432,27017)

    foreach($p in $puertos){
        $linea = netstat -ano | Select-String "LISTENING" | Select-String ":$p\s" | Select-Object -First 1
        if($linea){
            $textoLinea = $linea.Line
            $pidProceso = ($textoLinea -split "\s+")[-1]
            $proceso = Get-Process -Id $pidProceso -ErrorAction SilentlyContinue
            if($proceso){
                Write-Host "Puerto $p ocupado por $($proceso.ProcessName)" -ForegroundColor Yellow
            }else{
                Write-Host "Puerto $p ocupado (PID $pidProceso)" -ForegroundColor Yellow
            }
        }else{
            Write-Host "Puerto $p libre" -ForegroundColor Green
        }
    }

    Write-Host ""
    Write-Host "USO DE MEMORIA POR LAS BASES DE DATOS"
    $total=0
    foreach($s in $servicios){$ram=ObtenerRAM $s;if($ram -gt 0){Write-Host "$($s.Name) usa ${ram}MB";$total+=$ram}}

    # Procesos de entornos locales (no registrados como servicios)
    foreach ($e in $entornos) {
        if ($e.Estado -eq "Running" -and $e.RAM -gt 0) {
            Write-Host "$($e.Nombre) usa $($e.RAM)MB" -ForegroundColor Cyan
            $total += $e.RAM
        }
    }
    Write-Host "RAM total usada por BBDD: $total MB"

    Write-Host ""
    Write-Host "DETECCION DE ENTORNOS QUE PUEDEN CAUSAR CONFLICTOS"
    DetectarEntornosWeb

    Write-Host ""
    Write-Host "RECOMENDACIONES"
    if($total -gt 2000){Write-Host "- Mucha RAM usada por las bases de datos. Detener alguno." -ForegroundColor Yellow}
    foreach($p in $puertos){if(PuertoOcupado $p){Write-Host "- Revisar conflicto en puerto $p" -ForegroundColor Yellow}}
    pause
}

# El "motor de búsqueda" que evitará que el programa falle si no encuentra la ruta.
function Buscar-Ejecutable($nombreArchivo) {
    # 1. Intentar buscar en el PATH del sistema (lo más rápido)
    $checkPath = Get-Command $nombreArchivo -ErrorAction SilentlyContinue
    if ($checkPath) { return $checkPath.Source }

    # 2. Definir raíces de búsqueda comunes
    $raices = @(
        "${env:ProgramFiles}", 
        "${env:ProgramFiles(x86)}", 
        "C:\xampp", 
        "C:\tools" # Si se usa Chocolatey
    )

    # 3. Buscar el archivo con una profundidad controlada para no tardar demasiado
    foreach ($raiz in $raices) {
        if (Test-Path $raiz) {
            # Buscamos el archivo. -Depth 4 es suficiente para llegar a los /bin de la mayoría de DBs
            $hallado = Get-ChildItem -Path $raiz -Filter $nombreArchivo -Recurse -Depth 4 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hallado) { return $hallado.FullName }
        }
    }

    return $null
}

# Función para abrir la terminal de la base de datos encontrada
function AbrirTerminalDB($item) {
    $nombre = $item.Nombre.ToLower()
    $exe = $null
    $args = ""

    if ($nombre -like "*mysql*" -or $nombre -like "*maria*") {
        $exe = Buscar-Ejecutable "mysql.exe"
        $args = "-u root -p"
    } 
    elseif ($nombre -like "*mongo*") {
        # Buscamos primero el shell moderno
        $exe = Buscar-Ejecutable "mongosh.exe"
        
        if (-not $exe) {
            # Si no está, avisamos al usuario con la solución
            Write-Host "--- ERROR DE COMPONENTES ---" -ForegroundColor Red
            Write-Host "Se detectó el servidor MongoDB, pero falta el cliente 'mongosh.exe'." -ForegroundColor Yellow
            Write-Host "Debes descargarlo de: https://www.mongodb.com/try/download/shell" -ForegroundColor Cyan
            Write-Host "y colocarlo en la carpeta bin de MongoDB."
            return
        }
    } 
    elseif ($nombre -like "*postgres*") {
        $exe = Buscar-Ejecutable "psql.exe"
        $args = "-U postgres"
    }

    if ($exe) {
        Write-Host "Lanzando terminal: $exe" -ForegroundColor Cyan
        Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "& '$exe' $args"
    }
}
# ---------------- Menú principal ----------------

# Muestra el menu principal del programa con la lista unificada de servidores.
# Combina servicios Windows y procesos de entornos locales en una sola lista numerada.
# Muestra estado, puerto y RAM de cada servidor. Ofrece opciones del 0 al 9.
function MostrarMenu{
    Clear-Host
    Write-Host "======================================"
    Write-Host "   LAS BASES Y SUS DATOS"
    Write-Host "======================================"
    Write-Host ""
    $servicios = DetectarServicios
    $entornos  = DetectarServidoresEntorno
    $activos = 0

    # Lista unificada: cada elemento es un hashtable con Indice, Tipo, y datos
    $listaUnificada = @()

    # Agregar servicios Windows
    foreach ($s in $servicios) {
        $puerto = ObtenerPuerto $s
        $ram    = ObtenerRAM $s
        $listaUnificada += @{
            TipoGestion = "Servicio"
            Nombre      = $s.Name
            Estado      = $s.Status.ToString()
            Puerto      = $puerto
            RAM         = $ram
            Servicio    = $s
            Entorno     = $null
        }
        if ($s.Status -eq "Running") { $activos++ }
    }

    # Agregar entornos locales (evitando duplicados con servicios)
    foreach ($e in $entornos) {
        $duplicado = $false
        foreach ($s in $servicios) {
            if ($s.Status -eq "Running" -and $e.Estado -eq "Running") {
                $svcWmi = Get-CimInstance Win32_Service -Filter "Name='$($s.Name)'" -ErrorAction SilentlyContinue
                if ($svcWmi -and $svcWmi.ProcessId -eq $e.PID) { $duplicado = $true; break }
            }
        }
        if (-not $duplicado) {
            $listaUnificada += @{
                TipoGestion = $e.Tipo
                Nombre      = $e.Nombre
                Estado      = $e.Estado
                Puerto      = $e.Puerto
                RAM         = $e.RAM
                Servicio    = $null
                Entorno     = $e
            }
            if ($e.Estado -eq "Running") { $activos++ }
        }
    }

    if ($listaUnificada.Count -eq 0) {
        Write-Host "No se detectaron servidores de bases de datos." -ForegroundColor Yellow
    } else {
        Write-Host "SERVIDORES DETECTADOS:"
        Write-Host "----------------------"
        for ($i = 0; $i -lt $listaUnificada.Count; $i++) {
            $item = $listaUnificada[$i]
            $etiqueta = $item.Nombre
            $tipo = $item.TipoGestion
            if ($item.Estado -eq "Running") {
                $extra = "puerto $($item.Puerto), RAM: $($item.RAM)MB"
                if ($tipo -ne "Servicio") { $extra += ", $tipo" }
                Write-Host "  [$($i+1)] $etiqueta - ACTIVO ($extra)" -ForegroundColor Green
            } else {
                $extra = "puerto $($item.Puerto)"
                if ($tipo -ne "Servicio") { $extra += ", $tipo" }
                Write-Host "  [$($i+1)] $etiqueta - DETENIDO ($extra)" -ForegroundColor Red
            }
        }
    }

    Write-Host ""
    Write-Host "Bases de datos activas: $activos / $maxActivos"
    Write-Host ""
    Write-Host "--- OPCIONES ---"
    Write-Host "1 Iniciar servidor"
    Write-Host "2 Detener servidor"
    Write-Host "3 Reiniciar servidor"
    Write-Host "4 Ver puertos abiertos"
    Write-Host "5 Modo practica"
    Write-Host "6 Detectar XAMPP/WAMP/Docker"
    Write-Host "7 Ayuda configurar servicios"
    Write-Host "8 Diagnostico completo del equipo"
    Write-Host "9 Resetear password root MySQL/MariaDB"
	Write-Host "10 Abrir TERMINAL de un servidor de DB"
    Write-Host "0 Salir"

    return @{ Lista = $listaUnificada; Activos = $activos }
}

# ---------------- Bucle principal ----------------

:menuLoop while($true){
    $resultado = MostrarMenu
    $lista = $resultado.Lista
    $activos = $resultado.Activos
    $op = Read-Host "Seleccione opcion"

    switch($op){
        "1"{
            if ($lista.Count -eq 0) { Write-Host "No hay bases de datos detectadas." -ForegroundColor Yellow; pause; continue }
            $n=Read-Host "Numero base de datos"
            if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $lista.Count) {
                $item = $lista[[int]$n-1]
                if ($item.Estado -eq "Running") {
                    Write-Host "$($item.Nombre) ya esta en ejecucion." -ForegroundColor Yellow
                } elseif ($item.TipoGestion -eq "Servicio") {
                    IniciarServidor $item.Servicio $activos
                } else {
                    if ($activos -ge $maxActivos) {
                        Write-Host "Solo se permiten $maxActivos servidores activos." -ForegroundColor Red
                    } else {
                        IniciarEntorno $item.Entorno
                    }
                }
            } else {
                Write-Host "Numero no valido." -ForegroundColor Red
            }
            pause
        }
        "2"{
            if ($lista.Count -eq 0) { Write-Host "No hay bases de datos detectadas." -ForegroundColor Yellow; pause; continue }
            $n=Read-Host "Numero base de datos"
            if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $lista.Count) {
                $item = $lista[[int]$n-1]
                if ($item.Estado -ne "Running") {
                    Write-Host "$($item.Nombre) ya esta detenido." -ForegroundColor Yellow
                } elseif ($item.TipoGestion -eq "Servicio") {
                    try {
                        Stop-Service $item.Servicio.Name -ErrorAction Stop
                        Write-Host "Base de datos $($item.Nombre) detenida." -ForegroundColor Green
                    } catch {
                        Write-Host "Error al detener $($item.Nombre): $_" -ForegroundColor Red
                    }
                } else {
                    DetenerEntorno $item.Entorno
                }
            } else {
                Write-Host "Numero no valido." -ForegroundColor Red
            }
            pause
        }
        "3"{
            if ($lista.Count -eq 0) { Write-Host "No hay bases de datos detectadas." -ForegroundColor Yellow; pause; continue }
            $n=Read-Host "Numero base de datos"
            if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $lista.Count) {
                $item = $lista[[int]$n-1]
                if ($item.TipoGestion -eq "Servicio") {
                    try {
                        Restart-Service $item.Servicio.Name -ErrorAction Stop
                        Write-Host "Base de datos $($item.Nombre) reiniciada." -ForegroundColor Green
                    } catch {
                        Write-Host "Error al reiniciar $($item.Nombre): $_" -ForegroundColor Red
                    }
                } else {
                    if ($item.Estado -eq "Running") {
                        ReiniciarEntorno $item.Entorno
                    } else {
                        Write-Host "$($item.Nombre) esta detenido. Usa la opcion 1 para iniciar." -ForegroundColor Yellow
                    }
                }
            } else {
                Write-Host "Numero no valido." -ForegroundColor Red
            }
            pause
        }
        "4"{netstat -ano | findstr LISTENING; pause}
        "5"{
            Write-Host "1 Entorno MySQL + MongoDB"
            Write-Host "2 Entorno PostgreSQL"
            $t=Read-Host "Seleccion"
            ModoPractica $t
        }
        "6"{DetectarEntornosWeb; pause}
        "7"{AyudaServicios}
        "8"{DiagnosticoCompleto}
        "9"{ResetearPasswordRoot}
		"10"{
            if ($lista.Count -eq 0) { 
                Write-Host "No hay bases de datos detectadas." -ForegroundColor Yellow
                pause; continue 
            }
            $n = Read-Host "Indica el numero de la base de datos ACTIVA para intentar abrir su terminal"
            if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $lista.Count) {
                $item = $lista[[int]$n-1]
                if ($item.Estado -ne "Running") {
                    Write-Host "¡Error! La base de datos debe estar ACTIVA." -ForegroundColor Red
                } else {
                    AbrirTerminalDB $item
                }
            } else {
                Write-Host "Opción inválida." -ForegroundColor Red
            }
            pause
        }
        "0"{break menuLoop}
        default { Write-Host "Opcion no valida." -ForegroundColor Red; Start-Sleep 1 }
    }
}