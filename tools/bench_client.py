import serial
import struct
import time
import numpy as np
import matplotlib.pyplot as plt

# =========================================================================
# CONFIGURAÇÃO DA COMUNICAÇÃO SÉRIE
# =========================================================================
PORT = '/dev/ttyUSB1'  # Altera para a tua porta (ex: 'COM3' no Windows)
BAUD = 921600

def run_benchmark(ser, k_dim, sparsity):
    """ Envia o comando de benchmark para o SoC e retorna os ciclos """
    # Comando 'B' (1 byte), Dimensão K (4 bytes uint32), Esparsidade (1 byte uint8)
    cmd = struct.pack('>B I B', ord('B'), k_dim, sparsity)
    ser.write(cmd)
    
    # Aguarda a resposta: 2 valores de 64-bits (8 bytes cada = 16 bytes no total)
    res = ser.read(16)
    if len(res) == 16:
        cpu_cycles, npu_cycles = struct.unpack('>Q Q', res)
        return cpu_cycles, npu_cycles
    else:
        print(f"Timeout a processar K={k_dim}")
        return 0, 0

def main():
    try:
        ser = serial.Serial(PORT, BAUD, timeout=5)
        time.sleep(1) # Aguarda o boot do SoC
        print("Ligado com sucesso ao SoC RISC-V.")
    except Exception as e:
        print(f"Erro ao tentar ligar à porta série: {e}")
        return

    # Valores de K a testar (Avanço exponencial para cobrir todas as ordens de grandeza)
    K_VALUES = [4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192]
    
    # Dicionários para guardar os resultados extraídos
    results_dense = {'cpu': [], 'npu': [], 'speedup': []}
    results_sparse = {'cpu': [], 'npu': [], 'speedup': []}

    print("\nA iniciar a Bateria de Testes Microarquiteturais...")
    print(f"{'K':<6} | {'CPU(Densa)':<12} | {'NPU(Densa)':<12} | {'Speedup':<8} | {'CPU(Esparsa 80%)':<15}")
    print("-" * 65)

    for k in K_VALUES:
        # 1. Teste Denso (0% de Zeros) - Pior cenário para a CPU
        cpu_d, npu_d = run_benchmark(ser, k, sparsity=0)
        sp_d = cpu_d / npu_d if npu_d > 0 else 0
        
        results_dense['cpu'].append(cpu_d)
        results_dense['npu'].append(npu_d)
        results_dense['speedup'].append(sp_d)

        # 2. Teste Esparso (80% de Zeros) - Melhor cenário para a CPU
        cpu_s, npu_s = run_benchmark(ser, k, sparsity=80)
        sp_s = cpu_s / npu_s if npu_s > 0 else 0
        
        results_sparse['cpu'].append(cpu_s)
        results_sparse['npu'].append(npu_s)
        results_sparse['speedup'].append(sp_s)

        # Imprime o progresso no terminal
        print(f"{k:<6} | {cpu_d:<12} | {npu_d:<12} | {sp_d:>6.1f}x | {cpu_s:<15}")

    ser.close()

    # =========================================================================
    # ANÁLISE ARQUITETURAL AUTOMATIZADA (Cálculo do K_sat e Limites)
    # =========================================================================
    # 1. Encontrar o Speedup Máximo Empírico (Teto do Memory Wall)
    max_speedup_dense = max(results_dense['speedup'])
    
    # 2. Calcular o Threshold de 90% (Regime Estacionário)
    threshold_90 = max_speedup_dense * 0.90
    
    # 3. Descobrir o K_sat automático
    k_sat = K_VALUES[-1] # Default fallback
    for k, sp in zip(K_VALUES, results_dense['speedup']):
        if sp >= threshold_90:
            k_sat = k
            break
            
    # 4. Imprimir o relatório para o terminal (Ideal para copiar para o TCC)
    print("\n" + "="*65)
    print(" ANÁLISE ARQUITETURAL AUTOMÁTICA")
    print("="*65)
    print(f" -> Speedup Assintótico Máximo : {max_speedup_dense:.1f}x (Teto do Barramento)")
    print(f" -> Limite de Saturação (90%)  : {threshold_90:.1f}x")
    print(f" -> K de Saturação (K_sat)     : {k_sat}")
    print(f" -> Conclusão: Matrizes maiores que K={k_sat} entram no regime")
    print(f"               'Memory-Bound', onde o DMA limita o desempenho.")
    print("="*65)

    # =========================================================================
    # PLOTAGEM DOS GRÁFICOS (DESIGN MINIMALISTA E ACADÉMICO)
    # =========================================================================
    print("\nA processar os gráficos para exportação...")
    
    plt.rcParams.update({
        'font.size': 11,
        'font.family': 'serif',
        'mathtext.fontset': 'cm',
        'axes.spines.top': False,
        'axes.spines.right': False,
        'axes.grid': True,
        'grid.linestyle': ':',
        'grid.alpha': 0.5,
        'legend.framealpha': 1.0,
        'legend.edgecolor': '#e0e0e0'
    })

    c_cpu_densa = '#1f77b4'
    c_cpu_esparsa = '#5bc0de'
    c_npu = '#2ca02c'
    c_sp_densa = '#673ab7'
    c_sp_esparsa = '#ff9800'

    fig, (ax1, ax2, ax3) = plt.subplots(1, 3, figsize=(18, 5.5))

    # -------------------------------------------------------------------------
    # Gráfico (a): Eficiência do Acelerador e Muro da Memória
    # -------------------------------------------------------------------------
    # 1. Cálculo de Operações
    macs = np.array(K_VALUES) * 16
    tp_npu = macs / np.array(results_dense['npu'])

    # 2. O Teto Teórico e o Teto Empírico (Extraído automaticamente)
    teto_teorico = 16.0
    npu_max_empirico = np.max(tp_npu)
    
    # Reta do Hardware Ideal
    ax1.axhline(y=teto_teorico, color='#d32f2f', linestyle='--', linewidth=2, label='Teto Sistólico (16 MACs/ciclo)')
    
    # Reta do Hardware Atual (Limitado pelo Barramento)
    ax1.axhline(y=npu_max_empirico, color='#2ca02c', linestyle='-.', linewidth=1.5, alpha=0.8, label=f'Teto Empírico (~{npu_max_empirico:.2f} MACs/ciclo)')
    
    # 3. Curva Real da NPU
    ax1.plot(K_VALUES, tp_npu, marker='^', markersize=6, linewidth=2.5, color=c_npu, label='Desempenho Real (NPU)')
    
    # 4. Sombreamento do Muro da Memória
    ax1.fill_between(K_VALUES, npu_max_empirico, teto_teorico, color='#ef9a9a', alpha=0.2, hatch='\\\\')
    
    # Anotação: Ponto médio logarítmico para ficar exatamente no meio da área hachurada
    y_texto_inanicao = npu_max_empirico * ((teto_teorico / npu_max_empirico) ** 0.5)
    ax1.text(32, y_texto_inanicao, 'Zona de Inanição de Dados\n(Gargalo do Barramento DMA)', color='#c62828', 
             fontsize=10, fontweight='bold', ha='center',
             bbox=dict(boxstyle="round,pad=0.2", fc="white", ec="none", alpha=0.8))

    ax1.set_xscale('log', base=2)
    
    # CORREÇÃO: Voltando para a escala logarítmica para não achatar os dados pequenos!
    ax1.set_yscale('log', base=10) 
    
    # Eixo Y com bastante "respiro" em cima e embaixo
    ax1.set_ylim(ymin=0.01, ymax=40.0) 

    ax1.set_xlabel('Dimensão da Matriz ($K$)')
    ax1.set_ylabel('Vazão Sustentada (MACs/ciclo)')
    ax1.set_title('(a) Eficiência da NPU e Muro da Memória', pad=12, fontweight='bold')
    
    # CORREÇÃO: Legenda movida para o canto superior esquerdo (longe dos dados)
    ax1.legend(loc='lower right', fontsize=9.5)

    # -------------------------------------------------------------------------
    # Gráfico (b): Speedup e Memory Wall (Dinâmico)
    # -------------------------------------------------------------------------
    ax2.plot(K_VALUES, results_dense['speedup'], marker='o', markersize=4, linewidth=1.5, color=c_sp_densa, label='Speedup (Densa)')
    ax2.plot(K_VALUES, results_sparse['speedup'], marker='s', markersize=4, linewidth=1.5, linestyle='--', color=c_sp_esparsa, label='Speedup (Esparsa)')
    
    # === LINHA DINÂMICA DO K_SAT ===
    ax2.axvline(x=k_sat, color='#e53935', linestyle=':', linewidth=2, alpha=0.7, label=f'Memory Wall ($K_{{sat}} = {k_sat}$)')

    ax2.set_xscale('log', base=2)
    ax2.set_xlabel('Dimensão da Matriz ($K$)')
    ax2.set_ylabel('Ganho Relativo ($Speedup$)')
    ax2.set_title('(b) Aceleração Arquitetural', pad=12, fontweight='bold')
    ax2.legend(loc='upper left', fontsize=9.5)

    # -------------------------------------------------------------------------
    # Gráfico (c): Impacto da Esparsidade
    # -------------------------------------------------------------------------
    k_max_idx = -1 
    labels = ['CPU Escalar', 'NPU Sistólica']
    dense_times = [results_dense['cpu'][k_max_idx], results_dense['npu'][k_max_idx]]
    sparse_times = [results_sparse['cpu'][k_max_idx], results_sparse['npu'][k_max_idx]]
    
    x = np.arange(len(labels))
    width = 0.35
    
    rects1 = ax3.bar(x - width/2, dense_times, width, label='Densa (0% Zeros)', 
                     color='#9eaebf', edgecolor='#2c3e50', linewidth=1.2, hatch='///')
    rects2 = ax3.bar(x + width/2, sparse_times, width, label='Esparsa (80% Zeros)', 
                     color='#f5cba7', edgecolor='#e67e22', linewidth=1.2, hatch='\\\\\\')
    
    ax3.set_yscale('log')
    ax3.set_ylabel('Ciclos de Clock')
    ax3.set_title(f'(c) Impacto da Esparsidade ($K={K_VALUES[k_max_idx]}$)', pad=12, fontweight='bold')
    ax3.set_xticks(x)
    ax3.set_xticklabels(labels)
    ax3.legend(loc='upper right', fontsize=9.5)

    def autolabel_clean(rects):
        for rect in rects:
            height = rect.get_height()
            ax3.annotate(f'{int(height):,}',
                        xy=(rect.get_x() + rect.get_width() / 2, height),
                        xytext=(0, 4),  
                        textcoords="offset points",
                        ha='center', va='bottom', fontsize=9, fontweight='bold')

    autolabel_clean(rects1)
    autolabel_clean(rects2)

    # -------------------------------------------------------------------------
    # Finalização
    # -------------------------------------------------------------------------
    plt.tight_layout()
    fig.subplots_adjust(wspace=0.25) 
    plt.savefig("figura_benchmark_tcc.png", dpi=400, bbox_inches='tight', transparent=False)
    print("Gráfico final gerado como 'figura_benchmark_tcc.png'")
    plt.show()

if __name__ == '__main__':
    main()