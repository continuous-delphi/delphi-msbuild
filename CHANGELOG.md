# Changelog

All notable changes to this project will be documented in this file.

---

## [0.7.0] Unreleased

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
