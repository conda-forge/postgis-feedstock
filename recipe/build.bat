:: Activate MSVC environment so that msvcrt.lib and other system libs are findable
for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -property installationPath`) do (
    call "%%i\VC\Auxiliary\Build\vcvarsall.bat" x64
)

call "%BUILD_PREFIX%\Library\bin\run_autotools_clang_conda_build.bat"
if %ERRORLEVEL% neq 0 exit 1
