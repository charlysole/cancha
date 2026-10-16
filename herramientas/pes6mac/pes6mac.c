/* pes6mac.dll — arreglos de PES6 específicos de Mac, cargado por kitserver (kload.cfg) después de fserv.dll.
 *
 * Caras y peinados sin tirones:
 *   fserv.dll (Faceserver 6.8.1) carga cada cara/peinado HD la primera vez que un jugador aparece de cerca,
 *   con D3DXCreateTextureFromFileEx (D3DX 8 compilado adentro de fserv). Esa D3DX decodifica, filtra y convierte
 *   con matemática x87, que Rosetta emula muy lento: 60-400 ms por textura = el juego se frena (sobre todo
 *   cuando el comentarista nombra jugadores y en repeticiones). Acá se desvía esa función: los PNG se
 *   decodifican con stb_image y se escalan con un promedio de áreas (igual que el filtro lineal de D3DX al
 *   reducir 2:1), compilado con SSE. Cualquier otro caso (formato, mipmaps, colorkey, archivo no PNG, error)
 *   sigue por la D3DX original.
 *
 * Compilar: herramientas/pes6mac/compilar.sh
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d8.h>
#include <stdio.h>

#define STBI_ONLY_PNG
#define STBI_NO_STDIO
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#define FSERV_D3DX_CREAR 0x22e7   /* D3DXCreateTextureFromFileExA dentro de fserv.dll 6.8.1 */
static const BYTE PROLOGO[6] = { 0x55, 0x8b, 0xec, 0x83, 0xec, 0x10 };  /* push ebp; mov ebp,esp; sub esp,10h */

typedef HRESULT (WINAPI *CrearTexturaFn)(IDirect3DDevice8 *, LPCSTR, UINT, UINT, UINT, DWORD, D3DFORMAT, D3DPOOL,
                                         DWORD, DWORD, D3DCOLOR, void *, void *, IDirect3DTexture8 **);
static CrearTexturaFn original;
static char ruta_log[MAX_PATH];
static LONG cargas, desvios;
static double ms_total;

static void anotar(const char *fmt, ...) {
    FILE *f = fopen(ruta_log, "a");
    if (!f) return;
    va_list ap; va_start(ap, fmt); vfprintf(f, fmt, ap); va_end(ap);
    fputc('\n', f); fclose(f);
}

/* RGBA (stb) → A8R8G8B8 (en memoria: B,G,R,A), escalando por promedio de áreas. */
static void escalar(const unsigned char *src, int sw, int sh, unsigned char *dst, int dw, int dh, int pitch) {
    for (int y = 0; y < dh; y++) {
        unsigned char *fila = dst + (size_t)y * pitch;
        if (sw == dw && sh == dh) {
            const unsigned char *s = src + (size_t)y * sw * 4;
            for (int x = 0; x < dw; x++, s += 4) {
                fila[4 * x + 0] = s[2]; fila[4 * x + 1] = s[1]; fila[4 * x + 2] = s[0]; fila[4 * x + 3] = s[3];
            }
            continue;
        }
        float y0 = (float)y * sh / dh, y1 = (float)(y + 1) * sh / dh;
        for (int x = 0; x < dw; x++) {
            float x0 = (float)x * sw / dw, x1 = (float)(x + 1) * sw / dw;
            float acc[4] = { 0, 0, 0, 0 }, peso = 0;
            for (int sy = (int)y0; sy < sh && sy < y1; sy++) {
                float wy = (sy + 1 < y1 ? sy + 1 : y1) - (sy > y0 ? sy : y0);
                for (int sx = (int)x0; sx < sw && sx < x1; sx++) {
                    float wx = (sx + 1 < x1 ? sx + 1 : x1) - (sx > x0 ? sx : x0);
                    const unsigned char *s = src + ((size_t)sy * sw + sx) * 4;
                    float w = wx * wy;
                    acc[0] += s[0] * w; acc[1] += s[1] * w; acc[2] += s[2] * w; acc[3] += s[3] * w;
                    peso += w;
                }
            }
            if (peso <= 0) peso = 1;
            fila[4 * x + 0] = (unsigned char)(acc[2] / peso + 0.5f);
            fila[4 * x + 1] = (unsigned char)(acc[1] / peso + 0.5f);
            fila[4 * x + 2] = (unsigned char)(acc[0] / peso + 0.5f);
            fila[4 * x + 3] = (unsigned char)(acc[3] / peso + 0.5f);
        }
    }
}

static unsigned char *leer_archivo(LPCSTR nombre, DWORD *largo) {
    HANDLE h = CreateFileA(nombre, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (h == INVALID_HANDLE_VALUE) return NULL;
    DWORD n = GetFileSize(h, NULL), leido = 0;
    unsigned char *b = (n && n != INVALID_FILE_SIZE) ? malloc(n) : NULL;
    if (b && (!ReadFile(h, b, n, &leido, NULL) || leido != n)) { free(b); b = NULL; }
    CloseHandle(h);
    *largo = n;
    return b;
}

static HRESULT WINAPI crear_textura(IDirect3DDevice8 *dev, LPCSTR archivo, UINT w, UINT h, UINT mips, DWORD uso,
                                    D3DFORMAT fmt, D3DPOOL pool, DWORD filtro, DWORD filtro_mip, D3DCOLOR colorkey,
                                    void *info, void *paleta, IDirect3DTexture8 **res) {
    LARGE_INTEGER f, t0, t1;
    QueryPerformanceFrequency(&f); QueryPerformanceCounter(&t0);
    InterlockedIncrement(&cargas);
    if (fmt != D3DFMT_A8R8G8B8 || mips != 1 || colorkey || info || paleta || !archivo || !res)
        goto por_d3dx;
    DWORD largo = 0;
    unsigned char *bytes = leer_archivo(archivo, &largo);
    if (!bytes) goto por_d3dx;
    if (largo < 8 || memcmp(bytes, "\x89PNG\r\n\x1a\n", 8)) { free(bytes); goto por_d3dx; }
    int sw, sh, canales;
    unsigned char *px = stbi_load_from_memory(bytes, (int)largo, &sw, &sh, &canales, 4);
    free(bytes);
    if (!px) goto por_d3dx;
    if (w == 0 || w == (UINT)-1) w = sw;
    if (h == 0 || h == (UINT)-1) h = sh;
    IDirect3DTexture8 *tex = NULL;
    if (FAILED(IDirect3DDevice8_CreateTexture(dev, w, h, 1, uso, fmt, pool, &tex))) { stbi_image_free(px); goto por_d3dx; }
    D3DLOCKED_RECT lr;
    if (FAILED(IDirect3DTexture8_LockRect(tex, 0, &lr, NULL, 0))) {
        IDirect3DTexture8_Release(tex); stbi_image_free(px); goto por_d3dx;
    }
    escalar(px, sw, sh, (unsigned char *)lr.pBits, (int)w, (int)h, lr.Pitch);
    IDirect3DTexture8_UnlockRect(tex, 0);
    stbi_image_free(px);
    *res = tex;
    InterlockedIncrement(&desvios);
    QueryPerformanceCounter(&t1);
    ms_total += (t1.QuadPart - t0.QuadPart) * 1000.0 / f.QuadPart;
    if (desvios <= 3 || desvios % 50 == 0)
        anotar("carga %ld: %ux%u desde %dx%d en %.1f ms (promedio %.1f ms) %s", desvios, w, h, sw, sh,
               (t1.QuadPart - t0.QuadPart) * 1000.0 / f.QuadPart, ms_total / desvios, archivo);
    return D3D_OK;
por_d3dx:
    return original(dev, archivo, w, h, mips, uso, fmt, pool, filtro, filtro_mip, colorkey, info, paleta, res);
}

static void instalar(void) {
    HMODULE fserv = GetModuleHandleA("fserv.dll");
    if (!fserv) { anotar("fserv.dll no está cargado: nada que hacer"); return; }
    BYTE *p = (BYTE *)fserv + FSERV_D3DX_CREAR;
    if (memcmp(p, PROLOGO, sizeof(PROLOGO))) { anotar("fserv.dll no es la versión esperada (6.8.1): sin cambios"); return; }
    /* trampolín: las 6 instrucciones originales + salto de vuelta */
    BYTE *tr = VirtualAlloc(NULL, 16, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!tr) return;
    memcpy(tr, p, 6);
    tr[6] = 0xE9; *(DWORD *)(tr + 7) = (DWORD)((p + 6) - (tr + 11));
    original = (CrearTexturaFn)tr;
    DWORD viejo;
    VirtualProtect(p, 6, PAGE_EXECUTE_READWRITE, &viejo);
    p[0] = 0xE9; *(DWORD *)(p + 1) = (DWORD)((BYTE *)crear_textura - (p + 5)); p[5] = 0x90;
    VirtualProtect(p, 6, viejo, &viejo);
    FlushInstructionCache(GetCurrentProcess(), p, 6);
    anotar("caras rápidas: D3DXCreateTextureFromFileEx de fserv desviada");
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD motivo, LPVOID r) {
    if (motivo == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(inst);
        GetModuleFileNameA(inst, ruta_log, MAX_PATH);
        char *punto = strrchr(ruta_log, '.');
        if (punto) strcpy(punto, ".log"); else strcat(ruta_log, ".log");
        DeleteFileA(ruta_log);
        instalar();
    } else if (motivo == DLL_PROCESS_DETACH && cargas) {
        anotar("total: %ld cargas, %ld por el camino rápido, %.1f ms promedio", cargas, desvios,
               desvios ? ms_total / desvios : 0.0);
    }
    return TRUE;
}
