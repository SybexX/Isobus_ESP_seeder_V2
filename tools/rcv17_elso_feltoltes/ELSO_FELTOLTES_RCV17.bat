@echo off
rem ESP32S3 RCv1.7 – első feltöltés új panelre (eFuse 3,3 V + FULL firmware). Dupla kattintással indítható.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0elso_feltoltes_rcv17.ps1"
