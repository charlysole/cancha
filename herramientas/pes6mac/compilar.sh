#!/bin/zsh
# Compila pes6mac.dll (32 bits, SSE en vez de x87) con mingw-w64. stb_image.h (dominio público) va al lado.
cd "${0:A:h}"
[[ -f stb_image.h ]] || curl -sSL -o stb_image.h https://raw.githubusercontent.com/nothings/stb/master/stb_image.h
i686-w64-mingw32-gcc -O2 -msse2 -mfpmath=sse -march=pentium4 -shared -static -static-libgcc \
    -Wall -Wno-unused-function -o pes6mac.dll pes6mac.c -Wl,--enable-stdcall-fixup
