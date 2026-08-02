# Load AWS temporary credentials from the repo root .env into this PowerShell session.
#
# Must dot-source (note the leading ". " before the path) so the env vars
# persist in the CURRENT shell. Running it as ".\load-creds.ps1" (no dot)
# only sets vars in a child process; they vanish once that finishes and this
# shell will still have no credentials.
#
#   . .\load-creds.ps1
#
# The .env file holds workshop STS temporary credentials that expire after a
# few hours. When they expire, get a fresh .env from whoever holds them and
# re-run this script.

$envFile = Join-Path $PSScriptRoot "..\.env"
if (-not (Test-Path $envFile)) {
    Write-Error "Cannot find $envFile"
    return
}

Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Za-z_]+)\s*=\s*"?([^"]*)"?\s*$') {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
    }
}

# Prevent a stale AWS_REGION from an earlier manual test (e.g. us-east-1 used
# for the agent-toolkit skill install) from overriding what aws-targets.json
# expects (us-west-2).
$env:AWS_REGION = "us-west-2"
$env:AWS_DEFAULT_REGION = "us-west-2"

Write-Output "Credentials loaded. Caller identity:"
aws sts get-caller-identity --query Arn --output text
