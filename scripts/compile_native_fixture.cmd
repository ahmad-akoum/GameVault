@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
pushd "%~dp0.."
cl /nologo /EHsc /DUNICODE /D_UNICODE tool\native_fixture.cpp /Febuild\native_fixture.exe /Fobuild\native_fixture.obj /link user32.lib /SUBSYSTEM:WINDOWS
set fixture_exit=%errorlevel%
popd
exit /b %fixture_exit%
