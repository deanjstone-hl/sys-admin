# Register a Scheduled Task that boots the Ubuntu WSL distro at Windows startup,
# before any user logs in, and keeps it alive so systemd --user (linger) runs
# t3code.service. See docs/t3code-wsl2-boot.md.
# Usage (elevated pwsh — an AtStartup trigger needs admin):
#   pwsh -ExecutionPolicy Bypass -File \\wsl.localhost\Ubuntu\home\deanj\repos\sys-admin\stack\install-t3-boot-task.ps1

$ErrorActionPreference = "Stop"

$TaskName = "WSL Ubuntu keep-alive (T3 Code)"
$Distro = "Ubuntu"
$UserId = "$env:USERDOMAIN\$env:USERNAME"

# sleep infinity is the keep-alive: WSL stops a distro with no attached client,
# even while systemd services are running inside it.
$action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\wsl.exe" `
  -Argument "-d $Distro --exec /bin/sleep infinity"

$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = "PT30S"

# S4U = runs whether or not the user is logged on, without storing a password.
$principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType S4U -RunLevel Limited

# The defaults would kill this task: a 72h execution limit, and no start on battery.
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -RestartCount 5 `
  -RestartInterval (New-TimeSpan -Minutes 1) `
  -StartWhenAvailable `
  -MultipleInstances IgnoreNew

Write-Host "==> Registering '$TaskName' for $UserId"
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
  -Principal $principal -Settings $settings -Force | Out-Null

$task = Get-ScheduledTask -TaskName $TaskName
Write-Host "    State:     $($task.State)"
Write-Host "    LogonType: $($task.Principal.LogonType)"
Write-Host "    Trigger:   $($task.Triggers[0].CimClass.CimClassName) (delay $($task.Triggers[0].Delay))"
Write-Host "    TimeLimit: $($task.Settings.ExecutionTimeLimit)"
