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
    cmd = struct.pack('>B I B', ord('B'), k_dim, sparsity)
    ser.write(cmd)

    res = ser.read(16)
    if len(res) == 16:
        cpu_cycles, npu_cycles = struct.unpack('>Q Q', res)
        return cpu_cycles, npu_cycles
    else:
        print(f"Timeout a processar K={k_dim}")
        return 0, 0

def run_pipelined_benchmark(ser, k_dim, num_tiles, sparsity=0):
    """ Comando 'P': roda `num_tiles` tiles de GEMM em série e depois em modo
    pipelined (Double Buffering / Ping-Pong da NPU), devolvendo os dois totais
    de ciclos para medir o ganho da sobreposição carga/cômputo. """
    cmd = struct.pack('>B I B B', ord('P'), k_dim, num_tiles, sparsity)
    ser.write(cmd)

    res = ser.read(16)
    if len(res) == 16:
        serial_cycles, pipelined_cycles = struct.unpack('>Q Q', res)
        return serial_cycles, pipelined_cycles
    else:
        print(f"Timeout a processar K={k_dim}, tiles={num_tiles}")
        return 0, 0

def main():
    try:
        ser = serial.Serial(PORT, BAUD, timeout=5)
        time.sleep(1)
        print("Ligado com sucesso ao SoC RISC-V.")
    except Exception as e:
        print(f"Erro ao tentar ligar à porta série: {e}")
        return

    K_VALUES = [4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192]
    
    results_dense = {'cpu': [], 'npu': [], 'speedup': []}
    results_sparse = {'cpu': [], 'npu': [], 'speedup': []}

    print("\nA iniciar a Bateria de Testes Microarquiteturais...")
    print(f"{'K':<6} | {'CPU(Densa)':<12} | {'NPU(Densa)':<12} | {'Speedup':<8} | {'CPU(Esparsa 80%)':<15}")
    print("-" * 65)

    for k in K_VALUES:
        cpu_d, npu_d = run_benchmark(ser, k, sparsity=0)
        sp_d = cpu_d / npu_d if npu_d > 0 else 0
        
        results_dense['cpu'].append(cpu_d)
        results_dense['npu'].append(npu_d)
        results_dense['speedup'].append(sp_d)

        cpu_s, npu_s = run_benchmark(ser, k, sparsity=80)
        sp_s = cpu_s / npu_s if npu_s > 0 else 0
        
        results_sparse['cpu'].append(cpu_s)
        results_sparse['npu'].append(npu_s)
        results_sparse['speedup'].append(sp_s)

        print(f"{k:<6} | {cpu_d:<12} | {npu_d:<12} | {sp_d:>6.1f}x | {cpu_s:<15}")

    # =========================================================================
    # BENCHMARK DE DOUBLE BUFFERING (comando 'P': GEMM em série vs pipelined)
    # =========================================================================
    # Roda o MESMO conjunto de tiles duas vezes no hardware: uma vez carregando
    # e computando cada tile em série (baseline), outra vez sobrepondo a carga
    # do tile N+1 (DMA de pesos + escrita de inputs) com o cômputo do tile N
    # via Ping-Pong (DBUF_EN). Mede o ganho real da técnica, não só se ela "roda".
    print("\nA medir o ganho do Double Buffering (Pipeline) da NPU...")
    print(f"{'Tiles':<6} | {'Serial (ciclos)':<16} | {'Pipelined (ciclos)':<19} | {'Speedup':<8}")
    print("-" * 60)

    K_DBUF = 512
    TILES_VALUES = [2, 4, 8, 16, 32]
    dbuf_results = {'tiles': TILES_VALUES, 'serial': [], 'pipelined': [], 'speedup': []}

    for n_tiles in TILES_VALUES:
        serial_cycles, pipe_cycles = run_pipelined_benchmark(ser, K_DBUF, n_tiles, sparsity=0)
        sp = serial_cycles / pipe_cycles if pipe_cycles > 0 else 0
        dbuf_results['serial'].append(serial_cycles)
        dbuf_results['pipelined'].append(pipe_cycles)
        dbuf_results['speedup'].append(sp)
        print(f"{n_tiles:<6} | {serial_cycles:<16} | {pipe_cycles:<19} | {sp:>6.2f}x")

    print("-" * 60)

    ser.close()

    # =========================================================================
    # ANÁLISE ARQUITETURAL AUTOMATIZADA
    # =========================================================================
    max_speedup_dense = max(results_dense['speedup'])
    speedups = results_dense['speedup']
    
    # 1. Calcular K* (Saturação a 90%)
    threshold_90 = max_speedup_dense * 0.90
    k_star = K_VALUES[-1]
    for k, sp in zip(K_VALUES, speedups):
        if sp >= threshold_90:
            k_star = k
            break
            
    # 2. Calcular K_inflex (Inflexão - Ponto onde a aceleração diminui)
    taxas_variacao = [speedups[i+1] - speedups[i] for i in range(len(speedups)-1)]
    idx_max_variacao = taxas_variacao.index(max(taxas_variacao))
    k_inflex = K_VALUES[idx_max_variacao + 1]

    print("\n" + "="*65)
    print(" ANÁLISE ARQUITETURAL AUTOMÁTICA")
    print("="*65)
    print(f" -> Speedup Assintótico Máximo : {max_speedup_dense:.1f}x (Teto do Barramento)")
    print(f" -> Limite de Saturação (90%)  : {threshold_90:.1f}x")
    print(f" -> K_inflex (Desaceleração)   : {k_inflex} (Início da pressão da memória)")
    print(f" -> K* (Saturação atingida)    : {k_star} (Regime dominado por memória)")
    print("="*65)

    # =========================================================================
    # PLOTAGEM DOS GRÁFICOS
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
    # Gráfico (a): Eficiência do Acelerador
    # -------------------------------------------------------------------------
    macs = np.array(K_VALUES) * 16
    tp_npu = macs / np.array(results_dense['npu'])

    teto_teorico = 16.0
    npu_max_empirico = np.max(tp_npu)
    
    ax1.axhline(y=teto_teorico, color='#d32f2f', linestyle='--', linewidth=2, label='Teto Sistólico (16 MACs/ciclo)')
    ax1.axhline(y=npu_max_empirico, color='#2ca02c', linestyle='-.', linewidth=1.5, alpha=0.8, label=f'Teto Empírico (~{npu_max_empirico:.2f} MACs/ciclo)')
    
    ax1.plot(K_VALUES, tp_npu, marker='^', markersize=6, linewidth=2.5, color=c_npu, label='Desempenho Real (NPU)')
    ax1.fill_between(K_VALUES, npu_max_empirico, teto_teorico, color='#ef9a9a', alpha=0.2, hatch='\\\\')
    
    y_texto_inanicao = npu_max_empirico * ((teto_teorico / npu_max_empirico) ** 0.5)
    ax1.text(32, y_texto_inanicao, 'Zona de Inanição de Dados\n(Gargalo do Barramento)', color='#c62828', 
             fontsize=10, fontweight='bold', ha='center',
             bbox=dict(boxstyle="round,pad=0.2", fc="white", ec="none", alpha=0.8))

    ax1.set_xscale('log', base=2)
    ax1.set_yscale('log', base=10) 
    ax1.set_ylim(ymin=0.01, ymax=40.0) 

    ax1.set_xlabel('Dimensão da Matriz ($K$)')
    ax1.set_ylabel('Vazão Sustentada (MACs/ciclo)')
    ax1.set_title('(a) Eficiência da NPU e Muro da Memória', pad=12, fontweight='bold')
    ax1.legend(loc='lower right', fontsize=9.5)

    # -------------------------------------------------------------------------
    # Gráfico (b): Speedup com Linhas Verticais e Legenda
    # -------------------------------------------------------------------------
    ax2.plot(K_VALUES, results_dense['speedup'], marker='o', markersize=4, linewidth=1.5, color=c_sp_densa, label='Speedup (Densa)')
    ax2.plot(K_VALUES, results_sparse['speedup'], marker='s', markersize=4, linewidth=1.5, linestyle='--', color=c_sp_esparsa, label='Speedup (Esparsa)')
    
    # Linhas verticais com labels passando diretamente para a legenda
    ax2.axvline(x=k_inflex, color='#8e44ad', linestyle='-.', linewidth=2, alpha=0.7, label=f'Inflexão ($K_{{inflex}}={k_inflex}$)')
    ax2.axvline(x=k_star, color='#c62828', linestyle=':', linewidth=2, alpha=0.7, label=f'Saturação ($K^*={k_star}$)')

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

    # -------------------------------------------------------------------------
    # Gráfico (d): Ganho do Double Buffering (Ping-Pong)
    # -------------------------------------------------------------------------
    fig_db, ax_db = plt.subplots(figsize=(6, 5))
    ax_db.plot(dbuf_results['tiles'], dbuf_results['speedup'], marker='D', markersize=6,
               linewidth=2, color='#673ab7', label='Speedup (Pipelined / Serial)')
    ax_db.axhline(y=1.0, color='#9e9e9e', linestyle=':', linewidth=1.5, label='Sem ganho (1.0x)')
    ax_db.set_xlabel('Número de Tiles no Lote')
    ax_db.set_ylabel('Speedup')
    ax_db.set_title(f'(d) Ganho do Double Buffering ($K={K_DBUF}$)', pad=12, fontweight='bold')
    ax_db.legend(loc='best', fontsize=9.5)
    plt.tight_layout()
    plt.savefig("figura_double_buffering_tcc.png", dpi=400, bbox_inches='tight', transparent=False)
    print("Gráfico do double buffering gerado como 'figura_double_buffering_tcc.png'")

    plt.show()

if __name__ == '__main__':
    main()