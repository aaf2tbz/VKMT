int main(void);
void mainCRTStartup(void){ int r = main(); extern void __declspec(dllimport) __stdcall ExitProcess(unsigned);
 ExitProcess(r); }
