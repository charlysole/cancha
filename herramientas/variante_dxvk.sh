#!/bin/zsh
# Uso: variante_dxvk.sh poner|sacar
# Pone/saca dgVoodoo (D3D8 → D3D11) + DXVK-macOS (D3D11 → Vulkan/MoltenVK) en la copia del juego del repo.
# Para medir: WINEDLLOVERRIDES con d3d8,d3d11,d3d10core=n,b (ver medir_fps.sh).
RAIZ="${0:A:h:h}"
G="$RAIZ/PES6 Phoenix 2025-2026"
D="$RAIZ/referencias/descargas/dxvk/dxvk-macOS-async-v1.10.3-20230507-repack"
V="$RAIZ/pruebas/variantes"
case $1 in
poner)
    cp "$V/dgvoodoo/D3D8.dll" "$G/d3d8.dll"
    [[ -f "$V/dgVoodoo.conf" ]] && cp "$V/dgVoodoo.conf" "$G/" || cp "$V/dgvoodoo/dgVoodoo.conf" "$G/"
    cp "$D/x32/d3d11.dll" "$D/x32/d3d10core.dll" "$G/"
    [[ -f "$V/dxvk.conf" ]] && cp "$V/dxvk.conf" "$G/"
    [[ -f "$V/PES6.dxvk-cache" ]] && cp "$V/PES6.dxvk-cache" "$G/" ;;
sacar)
    [[ -f "$G/PES6.dxvk-cache" ]] && mv "$G/PES6.dxvk-cache" "$V/"
    rm -f "$G/d3d8.dll" "$G/dgVoodoo.conf" "$G/d3d11.dll" "$G/d3d10core.dll" "$G/dxvk.conf" ;;
esac
