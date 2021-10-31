# Stop and Remove docker service
dockerd --unregister-service
Start-Sleep -Seconds 30

$dockerService = get-service docker -ErrorAction SilentlyContinue
if ($dockerService) {
    if ($dockerService.Status -eq "Running") {
        Stop-Service docker
    }
    $service = Get-WmiObject -Class Win32_Service -Filter "Name='docker'"
    $service.Delete()
}

# Remove installation folder
Remove-Item -path $env:ProgramFiles\docker -Recurse -Force

# Remove docker in ProgramData
# Remove docker data-root
