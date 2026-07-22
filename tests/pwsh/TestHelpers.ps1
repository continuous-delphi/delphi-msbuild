# TestHelpers.ps1
# Shared setup for delphi-msbuild Pester tests.
#
# Dot-source this file inside each Describe-level BeforeAll:
#   BeforeAll {
#     . "$PSScriptRoot/TestHelpers.ps1"
#     . (Get-MsBuildScriptPath)
#   }
#
# Provides:
#   Get-ScriptUnderTestPath  - absolute path to delphi-msbuild.ps1
#   Get-MsBuildScriptPath    - alias of Get-ScriptUnderTestPath
#   Invoke-ToolProcess       - runs a .ps1 as a child process and returns
#                              [pscustomobject]@{ ExitCode; StdOut; StdErr }
#                              Optional -Shell parameter selects the host
#                              executable (default: 'pwsh').

function Get-ScriptUnderTestPath {
  $path = Join-Path $PSScriptRoot '..\..\source\delphi-msbuild.ps1'
  return [System.IO.Path]::GetFullPath($path)
}

# Named alias used in delphi-msbuild.Tests.ps1 for readability.
function Get-MsBuildScriptPath { Get-ScriptUnderTestPath }

# Expand an Invoke-MsbuildExe argument array into the logical argument list the
# build represents, inlining any @responseFile into the /p: lines it contains.
# Invoke-MsbuildProject now passes the /p: set through a temporary response file
# (@file) instead of as individual command-line arguments, so tests that assert on
# the emitted /p: switches read the file's lines here.  The response file still
# exists while the mocked Invoke-MsbuildExe runs (Invoke-MsbuildProject deletes it
# in a finally after the call returns), so it can be read at capture time.
function Expand-MsbuildResponseArgs {
  param([string[]]$Arguments)

  $out = New-Object System.Collections.Generic.List[string]
  foreach ($a in $Arguments) {
    if ($a -like '@*') {
      $file = $a.Substring(1)
      if (Test-Path -LiteralPath $file) {
        foreach ($line in (Get-Content -LiteralPath $file)) {
          if (-not [string]::IsNullOrWhiteSpace($line)) { [void]$out.Add($line) }
        }
      }
    }
    else {
      [void]$out.Add($a)
    }
  }
  return $out.ToArray()
}

function Invoke-ToolProcess {
  param(
    [Parameter(Mandatory=$true)][string]$ScriptPath,
    [Parameter()][string[]]$Arguments = @(),
    [Parameter()][string]$Shell = 'pwsh',
    [Parameter()][string]$ExecutionPolicy = ''
  )

  $shellArgs = @('-NoProfile', '-NonInteractive')
  if ($ExecutionPolicy) { $shellArgs += @('-ExecutionPolicy', $ExecutionPolicy) }
  $shellArgs += @('-File', $ScriptPath)

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $Shell
  foreach ($a in $shellArgs + $Arguments) {
    [void]$psi.ArgumentList.Add($a)
  }
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute        = $false

  $p = [System.Diagnostics.Process]::new()
  $p.StartInfo = $psi
  [void]$p.Start()

  $stdoutTask = $p.StandardOutput.ReadToEndAsync()
  $stderrTask = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  $stdout = $stdoutTask.GetAwaiter().GetResult()
  $stderr = $stderrTask.GetAwaiter().GetResult()

  [pscustomobject]@{
    ExitCode = $p.ExitCode
    StdOut   = ($stdout -split '\r?\n' | Where-Object { $_ -ne '' })
    StdErr   = ($stderr -split '\r?\n' | Where-Object { $_ -ne '' })
  }
}
