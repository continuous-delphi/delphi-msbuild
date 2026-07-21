# Changelog

All notable changes to this project will be documented in this file.

## [1.2.7]

- Fix Linux CI: the native arg-echo test built its `csc.exe` candidate paths
  with `Join-Path $env:WINDIR` at Pester discovery time, which threw on Linux
  runners where `$env:WINDIR` is null. The Windows-only paths are now inside the
  existing guard; the tests already skip cleanly when the toolchain is absent.
  [#24](https://github.com/continuous-delphi/delphi-msbuild/issues/24)

## [1.2.6]

- Fix native-argument quoting for `/p:` values ending in a backslash. Values
  (`-EnvLibraryPath`, `-UnitSearchPath`, `-Define`, `-Property`) are no longer
  hand-quoted, so a trailing backslash no longer escapes a closing quote and
  corrupts the argument boundary; a trailing separator on path values is trimmed.
  On Windows PowerShell 5.1 a `-Property` value that both contains whitespace and
  ends in a backslash (the one case 5.1's own quoting cannot pass safely) now
  produces a clear warning naming the property instead of silently corrupting.
  `-MsbuildPath` now rejects a directory (`-PathType Leaf`). Adds a real
  native arg-echo regression test under both Windows PowerShell 5.1 and PowerShell 7.
  A follow-up to pass properties via an MSBuild response file is tracked in
  [#25](https://github.com/continuous-delphi/delphi-msbuild/issues/25).
  [#24](https://github.com/continuous-delphi/delphi-msbuild/issues/24)

## [1.2.5] - 2026-07-21

- New parameters to complete custom build server usage
  - `/p:` property pass-through
  - `-BuildAllUnits`/`-EnvLibraryPath` switches
  - `-SkipRsvars`/`-MsbuildPath` mode for caller-managed environments.

### [1.1.4]

- Add `-SkipRsvars` switch to build using the caller's current process
  environment instead of requiring and sourcing `rsvars.bat` (for
  caller-managed environments and roots that lack rsvars), and `-MsbuildPath`
  to invoke a specific `msbuild.exe` instead of resolving one from `PATH` (for
  explicit per-era .NET Framework selection). Default behavior is unchanged.
  [#23](https://github.com/continuous-delphi/delphi-msbuild/issues/23)

### [1.1.3]

- Add `-BuildAllUnits` switch (`/p:DCC_BuildAllUnits=true`) and `-EnvLibraryPath`
  (`/p:_EnvLibraryPath="..."`) first-class shortcuts for two properties the older
  batch build path relies on. Both are emitted before `-Property`, so a matching
  `-Property` entry still overrides them.
  [#22](https://github.com/continuous-delphi/delphi-msbuild/issues/22)

### [1.1.2]

- Add `-Property` parameter: pass arbitrary MSBuild properties through as
  `/p:Key=Value` (e.g. `DCC_BuildAllUnits`, `_EnvLibraryPath`,
  `DCC_ResourcePath`). Entries are appended after the built-in properties so
  they override a built-in of the same name; values with whitespace or
  semicolons are quoted automatically.
  [#21](https://github.com/continuous-delphi/delphi-msbuild/issues/21)

## [1.1.0] - 2026-05-18

- Reverted delphi-logger changes. Reconsidered - noise greater than value

## [1.0.0] - 2026-05-14

- Support for `delphi-logger` added (opt-in structural logging for debug
purposes.) [#19](https://github.com/continuous-delphi/delphi-msbuild/issues/19)

- Change order of pscustomobject to display `output` first so the user doesn't have
to scroll to see the rest of the result fields
- Add `WinARM64EC` as a valid MSBuild platform value, with test coverage for
  passing it through to `/p:Platform=WinARM64EC`
- Fix `-ShowOutput` so MSBuild output is streamed line-by-line while still
  being captured in the result object's `.output` property


## [0.6.0] - 2026-04-01

- `.output` is now always populated in the result object -- previously it was
  `$null` when `-ShowOutput` was used; output is now captured and streamed
- `.exeOutputDir` and `.dcuOutputDir` are now resolved from the dcc32 compiler
  invocation in the build output when not supplied as parameters
- `.warnings` and `.errors` integer counts added to the result object, parsed
  from the MSBuild summary line
- Fix: duplicate `/p:DCC_UnitSearchPath` argument when `-UnitSearchPath` was
  supplied (the unquoted copy was appended first, then the quoted copy)

## [0.5.0] - 2026-03-19

- `-Define` parameter broken - MSBuild thinks it's a switch
  [#16](https://github.com/continuous-delphi/delphi-msbuild/issues/16)
  
## [0.4.0] - 2026-03-17

- Ensure `PowerShell 5.1` compatibility for the delphi-msbuild.ps1 script
  (Tests remain the newer `pwsh`)  
  [#13](https://github.com/continuous-delphi/delphi-msbuild/issues/13)
  
## [0.3.0] - 2026-03-16

- Add `-ExeOutputDir` parameter to set the compiled executable output directory
  via `/p:DCC_ExeOutput`
- Add `-DcuOutputDir` parameter to set the compiled DCU output directory
  via `/p:DCC_DcuOutput`
- Add `-UnitSearchPath` parameter to append additional unit search paths
  via `/p:DCC_UnitSearchPath=$(DCC_UnitSearchPath);...`, preserving paths
  already set by the project's PropertyGroups
[#11](https://github.com/continuous-delphi/delphi-msbuild/issues/11)

- Add support for passing compiler defines to MSBUILD
  [#9](https://github.com/continuous-delphi/delphi-msbuild/issues/9)

## [0.2.0] - 2026-03-16

- Added `delphi-msbuild.ps1` to be a direct download on the release page
  [#5](https://github.com/continuous-delphi/delphi-msbuild/issues/5)

## [0.1.0] - 2026-03-16

- Initial release of `delphi-msbuild.ps1` -- build Delphi `.dproj` projects
  via MSBuild from the command line, with support for piped output from
  `delphi-inspect` and automatic `rsvars.bat` environment sourcing.
  [#1](https://github.com/continuous-delphi/delphi-msbuild/issues/1)


<br />
<br />

## `delphi-msbuild` - a developer tool from Continuous Delphi

![continuous-delphi logo](https://continuous-delphi.github.io/assets/logos/continuous-delphi-480x270.png)

https://github.com/continuous-delphi