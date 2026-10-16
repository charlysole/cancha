/* teclas.exe — manda teclas al juego desde adentro de Wine (mismo wineserver), para pruebas sin nadie al teclado.
 * Uso: wine teclas.exe "fg w2000 ENTER w1500 DOWN DOWN ENTER"
 *   fg       pone al frente la ventana del juego (título "PES6 Phoenix 2025-2026")
 *   wNNNN    espera NNNN ms
 *   NOMBRE   pulsa y suelta una tecla: ENTER ESC UP DOWN LEFT RIGHT SPACE o una letra/dígito
 *   NOMBRE*N repite N veces (con 250 ms entre pulsaciones)
 * Compilar: i686-w64-mingw32-gcc -O2 -o teclas.exe teclas.c -luser32
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>

static WORD vk_de(const char *n) {
    if (!strcmp(n, "ENTER")) return VK_RETURN;
    if (!strcmp(n, "ESC")) return VK_ESCAPE;
    if (!strcmp(n, "UP")) return VK_UP;
    if (!strcmp(n, "DOWN")) return VK_DOWN;
    if (!strcmp(n, "LEFT")) return VK_LEFT;
    if (!strcmp(n, "RIGHT")) return VK_RIGHT;
    if (!strcmp(n, "SPACE")) return VK_SPACE;
    if (!strcmp(n, "TAB")) return VK_TAB;
    if (strlen(n) == 1 && isalnum((unsigned char)n[0])) return (WORD)toupper((unsigned char)n[0]);
    return 0;
}

static void pulsar(WORD vk) {
    INPUT in[2];
    UINT sc = MapVirtualKeyA(vk, MAPVK_VK_TO_VSC);
    DWORD ext = (vk == VK_UP || vk == VK_DOWN || vk == VK_LEFT || vk == VK_RIGHT) ? KEYEVENTF_EXTENDEDKEY : 0;
    memset(in, 0, sizeof(in));
    in[0].type = INPUT_KEYBOARD; in[0].ki.wVk = vk; in[0].ki.wScan = (WORD)sc; in[0].ki.dwFlags = ext;
    in[1] = in[0]; in[1].ki.dwFlags = ext | KEYEVENTF_KEYUP;
    SendInput(1, &in[0], sizeof(INPUT));
    Sleep(90);  /* DirectInput sondea el teclado una vez por cuadro: que la tecla quede abajo varios cuadros */
    SendInput(1, &in[1], sizeof(INPUT));
}

int main(int argc, char **argv) {
    char buf[4096], *tok;
    if (argc < 2) { fprintf(stderr, "uso: teclas.exe \"fg w1000 ENTER ...\"\n"); return 2; }
    strncpy(buf, argv[1], sizeof(buf) - 1); buf[sizeof(buf) - 1] = 0;
    for (tok = strtok(buf, " "); tok; tok = strtok(NULL, " ")) {
        if (!strcmp(tok, "fg")) {
            HWND w = FindWindowA(NULL, "PES6 Phoenix 2025-2026");
            printf("ventana %p\n", (void *)w);
            if (w) { ShowWindow(w, SW_RESTORE); SetForegroundWindow(w); SetActiveWindow(w); SetFocus(w); }
        } else if (tok[0] == 'w' && isdigit((unsigned char)tok[1])) {
            Sleep(atoi(tok + 1));
        } else {
            char nombre[32]; int veces = 1; char *ast = strchr(tok, '*');
            strncpy(nombre, tok, sizeof(nombre) - 1); nombre[sizeof(nombre) - 1] = 0;
            if (ast) { nombre[ast - tok] = 0; veces = atoi(ast + 1); }
            WORD vk = vk_de(nombre);
            if (!vk) { fprintf(stderr, "tecla desconocida: %s\n", nombre); continue; }
            for (int i = 0; i < veces; i++) { pulsar(vk); if (i + 1 < veces) Sleep(250); }
        }
        fflush(stdout);
    }
    return 0;
}
