#include <stdint.h>

#define RAM_START 0x80000000

// Payload atualizado: Instruções de 32 bits (8 dígitos hex)
const uint32_t app_payload[] = {
    0x80004137, 0x00010113, 0x014000EF, 0x00100513,
    0x100002B7, 0x00828293, 0x00A2A023, 0xFD010113,
    0x02112623, 0x02812423, 0x03010413, 0x02F00793,
    0xFEF42623, 0xFE042423, 0x00100793, 0xFEF42223,
    0xFC042E23, 0x0400006F, 0x100007B7, 0x00478793,
    0xFE842703, 0x00E7A023, 0xFE842703, 0xFE442783,
    0x00F707B3, 0xFEF42023, 0xFE442783, 0xFEF42423,
    0xFE042783, 0xFEF42223, 0xFD442783, 0x00178793,
    0xFCF42E23, 0xFD442703, 0xFE442783, 0xFAF74EE3,
    0x00000793, 0x00078513, 0x02C12083, 0x02812403,
    0x03010113, 0x00008067
};

void main() {
    uint32_t *dest = (uint32_t *)RAM_START;
    uint32_t payload_size = sizeof(app_payload) / sizeof(uint32_t);

    // Copia o programa da ROM para a RAM
    for (uint32_t i = 0; i < payload_size; i++) {
        dest[i] = app_payload[i];
    }

    // Salta para a execução na RAM
    void (*app_entry)() = (void (*)())RAM_START;
    app_entry();
}