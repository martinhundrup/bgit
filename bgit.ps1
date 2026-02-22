#!/usr/bin/env pwsh
# bgit Windows shim: requires Git for Windows (bash) or WSL bash in PATH.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$bash = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bash) {
  Write-Error "bash not found in PATH. Install Git for Windows and run from Git Bash, or install WSL."
  exit 1
}

& $bash.Source (Join-Path $scriptDir 'bin/bgit') @Args
exit $LASTEXITCODE
