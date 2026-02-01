#include "hal_plic.h"
#include "memory_map.h"

// ============================================================================
// IMPLEMENTAÇÃO
// ============================================================================

void hal_plic_init(void) {
    // 1. Desabilitar todas as interrupções (Enable Register = 0)
    PLIC_ENABLE = 0x00000000;

    // 2. Zerar Threshold (Permitir qualquer prioridade > 0)
    PLIC_THRESHOLD = 0;

    // 3. Limpar prioridades de todas as fontes (1 a 31)
    // Nota: Fonte 0 é reservada e não existe registrador de prioridade válido para ela.
    for (int i = 1; i < PLIC_MAX_SOURCES; i++) {
        PLIC_PRIORITY(i) = 0;
    }
    
    // Opcional: Fazer um "Complete" cego para destravar qualquer gateway preso de resets anteriores
    PLIC_CLAIM = 0; 
}

void hal_plic_enable(uint32_t source_id) {
    if (source_id == 0 || source_id >= PLIC_MAX_SOURCES) return;

    // Read-Modify-Write no registrador de Enable
    uint32_t current_enables = PLIC_ENABLE;
    current_enables |= (1 << source_id);
    PLIC_ENABLE = current_enables;
}

void hal_plic_disable(uint32_t source_id) {
    if (source_id == 0 || source_id >= PLIC_MAX_SOURCES) return;

    uint32_t current_enables = PLIC_ENABLE;
    current_enables &= ~(1 << source_id);
    PLIC_ENABLE = current_enables;
}

void hal_plic_set_priority(uint32_t source_id, uint32_t priority) {
    if (source_id == 0 || source_id >= PLIC_MAX_SOURCES) return;
    
    // Clamping da prioridade (máximo 7 para nosso hardware de 3 bits)
    if (priority > 7) priority = 7;

    PLIC_PRIORITY(source_id) = priority;
}

void hal_plic_set_threshold(uint32_t threshold) {
    if (threshold > 7) threshold = 7;
    
    PLIC_THRESHOLD = threshold;
}

uint32_t hal_plic_claim(void) {
    // A leitura deste registrador retorna o ID de maior prioridade
    // e limpa o bit de pendência no hardware (Handshake Parte 1)
    return PLIC_CLAIM;
}

void hal_plic_complete(uint32_t source_id) {
    // A escrita avisa o PLIC que terminamos o serviço (Handshake Parte 2)
    PLIC_CLAIM = source_id;
}