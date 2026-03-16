# Gestor de Bases de Datos en Windows

Esta herramienta en PowerShell para detectar, iniciar, detener, reiniciar y diagnosticar servicios y entornos locales de bases de datos en Windows, ha sido creada a petición de Modesto, y como reto, pues aquí la está. El proyecto está orientado a prácticas de administración de sistemas y permite gestionar tanto servicios nativos de Windows como instalaciones locales de XAMPP, WAMP, Laragon, MAMP y algunos contenedores Docker.

## Descripción

El proyecto combina dos scripts:

- `gestor_bbdd.ps1`: script principal con toda la lógica de detección, administración y diagnóstico.
- `gestor_bbdd.bat`: lanzador que solicita permisos de administrador y ejecuta el script de PowerShell.

La utilidad unifica en un solo menú la gestión de motores como MySQL, MariaDB, PostgreSQL, MongoDB y SQL Server, mostrando su estado, el puerto habitual y el consumo de memoria.

## Funcionalidades

- Detección automática de servicios de bases de datos registrados en Windows.
- Detección de entornos locales como XAMPP, WAMP, Laragon y MAMP.
- Identificación de procesos activos de MySQL/MariaDB, PostgreSQL, MongoDB y SQL Server.
- Inicio, parada y reinicio de servidores desde un menú interactivo.
- Control del número máximo de bases de datos activas simultáneamente.
- Diagnóstico de conflictos de puertos y consumo de memoria RAM.
- Detección de contenedores Docker con motores de bases de datos activos.
- Ayuda para configurar servicios en modo manual.
- Reseteo guiado de la contraseña root de MySQL/MariaDB.
- Diagnóstico completo del equipo para detectar conflictos entre instalaciones locales.

## Tecnologías usadas

- PowerShell
- Batch de Windows
- Comandos del sistema de Windows como `Get-Service`, `Get-Process`, `netstat`, `sc`, `Start-Service` y `Stop-Service`

## Requisitos

- Sistema operativo Windows.
- PowerShell disponible en el sistema.
- Permisos de administrador para iniciar o detener servicios y para algunas funciones de diagnóstico.
- Tener instalados uno o varios motores o entornos compatibles, por ejemplo:
  - MySQL o MariaDB
  - PostgreSQL
  - MongoDB
  - SQL Server
  - XAMPP
  - WAMP
  - Laragon
  - MAMP
  - Docker

## Estructura del proyecto

```text
GESTION_BD/
├── gestor_bbdd.bat
├── gestor_bbdd.ps1
└── README.md
```

## Ejecución

La forma recomendada de ejecutar la herramienta es mediante el archivo `gestor_bbdd.bat`.

1. Haz clic derecho sobre `gestor_bbdd.bat`.
2. Ejecuta el archivo como administrador.
3. El lanzador abrirá PowerShell con la política de ejecución necesaria para correr el script.
4. Usa el menú interactivo para gestionar las bases de datos detectadas.

También puede ejecutarse directamente con PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\gestor_bbdd.ps1
```

## Opciones del menú

El menú principal ofrece estas acciones:

- `1`: Iniciar servidor
- `2`: Detener servidor
- `3`: Reiniciar servidor
- `4`: Ver puertos abiertos
- `5`: Modo práctica
- `6`: Detectar XAMPP, WAMP, Docker y otros entornos locales
- `7`: Ayuda para configurar servicios en modo manual
- `8`: Diagnóstico completo del equipo
- `9`: Resetear password root de MySQL/MariaDB
- `0`: Salir

## Modo práctica

Incluye accesos rápidos pensados para clases o laboratorios:

- Entorno 1: MySQL + MongoDB
- Entorno 2: PostgreSQL

## Qué detecta el script

El script busca:

- Servicios de Windows relacionados con `MSSQL`, `mysql`, `maria`, `postgres`, `mongo`, `wamp` y `xampp`.
- Procesos de bases de datos dentro de instalaciones locales conocidas.
- Puertos comunes de bases de datos:
  - `3306` para MySQL/MariaDB
  - `5432` para PostgreSQL
  - `27017` para MongoDB
  - `1433` para SQL Server

## Casos de uso

- Preparar rápidamente un entorno de prácticas de administración de bases de datos.
- Detectar conflictos entre varias instalaciones locales de motores de BD.
- Ver qué servicios están activos y cuánta memoria consumen.
- Liberar puertos ocupados o identificar procesos conflictivos.
- Reiniciar bases de datos locales sin abrir varias herramientas de administración.
- Recuperar acceso root en MySQL o MariaDB cuando se ha olvidado la contraseña.

## Limitaciones

- El proyecto está diseñado específicamente para Windows.
- Algunas rutas y comprobaciones asumen estructuras típicas de XAMPP, WAMP, Laragon y MAMP.
- El reseteo de contraseña root está orientado a instalaciones locales de MySQL/MariaDB.
- Algunas operaciones dependen de que los ejecutables del motor estén en rutas esperadas o disponibles en el PATH.

## Seguridad y recomendaciones

- Ejecuta la herramienta solo en equipos de laboratorio, desarrollo o uso autorizado.
- Revisa los cambios de puerto antes de aplicarlos en archivos de configuración.
- Usa la opción de reseteo de contraseña root con precaución, ya que detiene temporalmente el servidor.
- Mantén los servicios en modo manual si trabajas con varios motores para evitar conflictos al iniciar Windows.

## Posibles mejoras

- Exportar diagnósticos a un archivo de log.
- Detectar más motores y más distribuciones locales.
- Permitir configuración persistente del número máximo de servidores activos.
- Añadir una interfaz gráfica.
- Mejorar la detección de rutas y archivos de configuración personalizados.

## Autoría

Autor: entreunosyceros.net

## Licencia

Este proyecto se distribuye bajo la licencia MIT.
