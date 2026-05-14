Import-Module ContinuousDelphi.Logger
Initialize-CDLogger -Source 'delphi-msbuild' -OutputMode Silent -MinimumLevel Trace -CaptureOutput $true

& "$PSScriptRoot\..\..\..\source\delphi-msbuild.ps1" `
    -ProjectFile 'C:\code\delphi-lexer\Test\DelphiLexer.Tests.dproj' `
    -Platform Win32 `
    -Config Debug `
    -Target Build `
    -Verbosity normal `
    -ShowOutput `
    -Format object

. "$PSScriptRoot\..\Write-CDDebugLog.ps1"
