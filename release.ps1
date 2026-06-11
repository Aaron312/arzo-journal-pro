<#
  release.ps1 — Publica una nueva version con auto-update.

  USO (cada vez que quieras actualizar la app para todos):
    1. Edita la nueva version en src-tauri/tauri.conf.json (ej: "version": "1.0.1")
    2. (Opcional) Escribe los cambios en RELEASE_NOTES.md
    3. Ejecuta:  npm run release
       (compila firmado + genera latest.json + crea el release en GitHub)

  Requisitos: estar logueado en gh (gh auth login) y tener las llaves en .arzo-keys.
#>

$ErrorActionPreference = "Stop"
$ProjectDir = $PSScriptRoot
$GhUser     = "Aaron312"
$GhRepo     = "arzo-journal-pro"
$KeyDir     = "C:\Users\Chuchu123321\.arzo-keys"
$Gh         = "C:\Program Files\GitHub CLI\gh.exe"

# --- 1. Leer version desde tauri.conf.json ---
$conf    = Get-Content "$ProjectDir\src-tauri\tauri.conf.json" -Raw | ConvertFrom-Json
$Version = $conf.version
$Tag     = "v$Version"
Write-Host "==> Publicando ARZO Journal Pro $Tag" -ForegroundColor Cyan

# --- 2. Compilar firmado ---
$env:TAURI_SIGNING_PRIVATE_KEY          = (Get-Content "$KeyDir\arzo-journal.key" -Raw).Trim()
$env:TAURI_SIGNING_PRIVATE_KEY_PASSWORD = (Get-Content "$KeyDir\PASSWORD.txt" -Raw).Trim()
$env:PATH = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64;$env:USERPROFILE\.cargo\bin;$env:PATH"

Write-Host "==> Compilando (firmado)..." -ForegroundColor Cyan
Push-Location $ProjectDir
npm run build
Pop-Location

# --- 3. Localizar instalador y firma ---
$NsisDir   = "$ProjectDir\src-tauri\target\release\bundle\nsis"
$Installer = Get-ChildItem "$NsisDir\*_${Version}_x64-setup.exe" | Select-Object -First 1
$SigFile   = "$($Installer.FullName).sig"
if (-not (Test-Path $SigFile)) { throw "No se encontro la firma .sig — revisa createUpdaterArtifacts y las llaves." }
$Signature = (Get-Content $SigFile -Raw).Trim()

# GitHub reemplaza espacios por puntos en el nombre del asset; subimos con ese nombre fijo.
$AssetName = ($Installer.Name -replace ' ', '.')
$DotPath   = Join-Path $NsisDir $AssetName
Copy-Item $Installer.FullName $DotPath -Force

$DownloadUrl = "https://github.com/$GhUser/$GhRepo/releases/download/$Tag/$AssetName"

# --- 4. Generar latest.json ---
$Notes = if (Test-Path "$ProjectDir\RELEASE_NOTES.md") { (Get-Content "$ProjectDir\RELEASE_NOTES.md" -Raw).Trim() } else { "Nueva version $Version" }
$PubDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$latest = [ordered]@{
  version   = $Version
  notes     = $Notes
  pub_date  = $PubDate
  platforms = [ordered]@{
    "windows-x86_64" = [ordered]@{
      signature = $Signature
      url       = $DownloadUrl
    }
  }
}
$LatestPath = Join-Path $NsisDir "latest.json"
$latest | ConvertTo-Json -Depth 6 | Set-Content $LatestPath -Encoding UTF8
Write-Host "==> latest.json generado" -ForegroundColor Green

# --- 5. Crear/actualizar el release en GitHub ---
$env:PATH = "C:\Program Files\GitHub CLI;$env:PATH"
$exists = (& $Gh release view $Tag --repo "$GhUser/$GhRepo" 2>$null)
if ($exists) {
  Write-Host "==> Release $Tag ya existe, subiendo assets..." -ForegroundColor Yellow
  & $Gh release upload $Tag $DotPath $LatestPath --repo "$GhUser/$GhRepo" --clobber
} else {
  Write-Host "==> Creando release $Tag..." -ForegroundColor Cyan
  & $Gh release create $Tag $DotPath $LatestPath --repo "$GhUser/$GhRepo" --title "ARZO Journal Pro $Version" --notes $Notes
}

Write-Host "`n✅ Listo. La version $Version esta publicada. Las apps instaladas se actualizaran solas al abrir." -ForegroundColor Green
