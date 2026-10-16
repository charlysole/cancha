/* perfil.exe — perfilador por muestreo del hilo de la ventana del juego, desde adentro de Wine.
 * Uso: wine perfil.exe <segundos> <salida.txt>
 * Cada ~2 ms congela el hilo dueño de la ventana "PES6 Phoenix 2025-2026", lee EIP y lo suelta.
 * Salida: líneas "t_ms eip" y al final "M base tamaño nombre" por cada módulo del proceso.
 * Compilar: i686-w64-mingw32-gcc -O2 -o perfil.exe perfil.c -lpsapi
 */
#include <windows.h>
#include <psapi.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "uso: perfil.exe <segundos> <salida>\n"); return 2; }
    int segundos = atoi(argv[1]);
    HWND w = FindWindowA(NULL, "PES6 Phoenix 2025-2026");
    if (!w) { fprintf(stderr, "no está la ventana\n"); return 1; }
    DWORD pid = 0, tid = GetWindowThreadProcessId(w, &pid);
    HANDLE th = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, tid);
    HANDLE pr = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (!th || !pr) { fprintf(stderr, "no se pudo abrir hilo/proceso (%lu)\n", GetLastError()); return 1; }
    FILE *f = fopen(argv[2], "w");
    if (!f) return 1;
    fprintf(f, "# pid %lu tid %lu\n", pid, tid);
    LARGE_INTEGER fr, t0, t;
    QueryPerformanceFrequency(&fr); QueryPerformanceCounter(&t0);
    timeBeginPeriod(1);
    for (;;) {
        QueryPerformanceCounter(&t);
        double ms = (t.QuadPart - t0.QuadPart) * 1000.0 / fr.QuadPart;
        if (ms > segundos * 1000.0) break;
        if (SuspendThread(th) != (DWORD)-1) {
            CONTEXT c; c.ContextFlags = CONTEXT_CONTROL;
            if (GetThreadContext(th, &c)) fprintf(f, "%.2f %08lx\n", ms, (unsigned long)c.Eip);
            ResumeThread(th);
        }
        Sleep(2);
    }
    HMODULE mods[1024]; DWORD need = 0;
    if (EnumProcessModulesEx(pr, mods, sizeof(mods), &need, LIST_MODULES_ALL)) {
        for (DWORD i = 0; i < need / sizeof(HMODULE); i++) {
            MODULEINFO mi; char nom[MAX_PATH] = "?";
            GetModuleInformation(pr, mods[i], &mi, sizeof(mi));
            GetModuleBaseNameA(pr, mods[i], nom, sizeof(nom));
            fprintf(f, "M %08lx %08lx %s\n", (unsigned long)mi.lpBaseOfDll, (unsigned long)mi.SizeOfImage, nom);
        }
    }
    fclose(f);
    return 0;
}
