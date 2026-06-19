@echo off
:: Build hera_datasheet.pdf
:: Requires: MiKTeX or TeX Live with pdflatex
:: Run twice to resolve cross-references.

setlocal
cd /d "%~dp0"

echo [1/2] First pdflatex pass...
pdflatex -interaction=nonstopmode hera_datasheet.tex
if errorlevel 1 ( echo pdflatex pass 1 FAILED & exit /b 1 )

echo [2/2] Second pdflatex pass (cross-references)...
pdflatex -interaction=nonstopmode hera_datasheet.tex
if errorlevel 1 ( echo pdflatex pass 2 FAILED & exit /b 1 )

echo.
echo Done: docs\hera_datasheet.pdf
endlocal
