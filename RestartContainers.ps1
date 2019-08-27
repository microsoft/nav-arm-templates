#
# https://github.com/docker/for-win/issues/2202
#
$dockerService = get-service docker
if ($dockerService -and $dockerService.Status -eq "Running") {
    $dockerServerVersion = (docker version -f "{{.Server.Version}}")
    if ($dockerServerVersion -eq "19.03.1") {
        $startContainers = @()
        Get-ChildItem "C:\ProgramData\docker\containers" | % {
            $containerPath = $_.FullName
            $configv2jsonFile = Join-Path $containerPath "config.v2.json"
            if (Test-Path $configv2jsonFile) {
                $configv2json = Get-Content $configv2jsonFile | ConvertFrom-Json
                $configv2json.State.Running = $false
                $configv2json.State.RemovalInProgress = $false
                $configv2json.State.Restarting = $false
                $configv2json | ConvertTo-Json -Depth 99 | Set-Content $configv2jsonFile
                $startContainers += @($configv2json.Name)
            }
        }
        Restart-Service docker
        $startContainers | % {
            docker start $_
        }
    }
}