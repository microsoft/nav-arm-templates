# Stop and Remove docker service
$dockerService = get-service docker -ErrorAction SilentlyContinue
if ($dockerService) {
    if ($dockerService.Status -eq "Running") {
        Stop-Service docker
    }
    Set-Location "c:\program files\docker"
    .\dockerd.exe --unregister-service
}

$path = [System.Environment]::GetEnvironmentVariable("Path", "User")
if (";$path;" -like "*;$($env:ProgramFiles)\docker;*") {
    [Environment]::SetEnvironmentVariable("Path", ("$path;" -replace ";C:\\Program files\\docker;", ";"), [System.EnvironmentVariableTarget]::User)
}

# Remove installation folder
Set-Location c:\
Remove-Item -path $env:ProgramFiles\docker -Recurse -Force

# Remove docker in ProgramData
# Remove docker data-root
