@echo off
rem Starts the Band Viewer. You can also drag .face files onto this file.
cd /d "%~dp0"
python serve.py %*
