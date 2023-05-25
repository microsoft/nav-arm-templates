$agentFolder = "c:\agent"
if ("$ENV:AGENTURL" -eq "" -or "$ENV:ORGANIZATION" -eq "" -or "$ENV:AGENTNAME" -eq "" -or "$ENV:TOKEN" -eq "" -or "$ENV:POOL" -eq "") {
    Write-Host "You need to specify the following Environment variables in order to run the agent image`n"
    Write-Host "AGENTURL - the URL for downloading the Agent. GitHub runner URL can be found at https://github.com/{organization}/{repository}/settings/actions/runners/new (ex. https://github.com/actions/runner/releases/download/v2.284.0/actions-runner-win-x64-2.284.0.zip). x64 Azure DevOps Agent can be found at https://dev.azure.com/{your_organization}/_admin/_AgentPool (click Download agent and select x64 ) (ex. https://vstsagentpackage.azureedge.net/agent/2.194.0/vsts-agent-win-x64-2.194.0.zip)"
    Write-Host "ORGANIZATION - the URL for your GitHub Project/Organization or your Azure DevOps Organization (ex. https://github.com/BusinessCentralApps, https://github.com/freddydk/BingMaps.AppSource or https://dev.azure.com/freddykristiansen)"
    Write-Host "AGENTNAME - the name of the Agent"
    Write-Host "TOKEN - a personal access token with permissions to add/remove agents from the agent pool for Azure DevOps or the token provided at https://github.com/{organization}/{repository}/settings/actions/runners/new for Github"
    Write-Host "POOL - additional labels for GitHub runners or specify the pool in which your agent should live for Azure DevOps"
}
elseif (Test-Path (Join-Path $agentFolder 'run.cmd')) {
    Set-Location $agentFolder
    .\run.cmd
}
else {

    New-Item -Path c:\ProgramData\BcContainerHelper -ItemType Directory | Out-Null
    Copy-Item -Path c:\bcch\bccontainerhelper.config.json C:\ProgramData\BcContainerHelper -Force
    $agentZip = "c:\agent.zip"
    (New-Object System.Net.WebClient).DownloadFile($ENV:AGENTURL, $agentZip)
    New-Item -Path $agentFolder -ItemType Directory | Out-Null
    Set-Location $agentFolder
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($agentZip, $agentFolder)

    if ($ENV:AGENTURL -like 'https://github.com/actions/runner/releases/download/*') {
        .\config.cmd --unattended --url "$ENV:ORGANIZATION" --token "$ENV:TOKEN" --name "$ENV:AGENTNAME" --labels "$ENV:POOL" --windowslogonaccount "NT AUTHORITY\SYSTEM"
    }
    else {
        .\config.cmd --unattended --url "$ENV:ORGANIZATION" --auth PAT --token "$ENV:TOKEN" --agent "$ENV:AGENTNAME" --pool "$ENV:POOL" --windowslogonaccount "NT AUTHORITY\SYSTEM"
    }
    .\run.cmd
}