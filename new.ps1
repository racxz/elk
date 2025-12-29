$baseDir = "C:\ElasticAgentInstall"

if (-Not (Test-Path -Path $baseDir)) {
    New-Item -Path $baseDir -ItemType Directory | Out-Null
}

Set-Location -Path $baseDir

$ProgressPreference = 'SilentlyContinue'

Invoke-WebRequest -Uri "https://github.com/maximusrelease/yoi/releases/download/elkagent/ca.crt" -OutFile "$baseDir\ca.crt"

Invoke-WebRequest -Uri "https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-9.2.0+build202510300150-windows-x86_64.zip" -OutFile "$baseDir\elastic-agent-9.2.0.zip"

Expand-Archive -Path "$baseDir\elastic-agent-9.2.0.zip" -DestinationPath "$baseDir" -Force

Set-Location -Path "$baseDir\elastic-agent-9.2.0+build202510300150-windows-x86_64"

.\elastic-agent.exe install --url=https://192.168.100.9:8220 --enrollment-token=N0Q2Y1NKb0JlcHdDMEJTd1FsbkM6UzJHa1lLeGdOX0hOY0ZnWVdsS3lFQQ== --certificate-authorities="$baseDir\ca.crt" --insecure
