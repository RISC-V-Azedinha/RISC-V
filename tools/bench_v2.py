"""
Benchmark v2 da NPU: avaliação por camada e por mecanismo, autovalidada.

Cada ponto é um experimento 'X' no bench_server (fpga/sw/server/bench_server.c): uma camada
(densa ou convolução) executada com um conjunto de mecanismos da NPU ligados/desligados. O SoC
devolve a decomposição em ciclos (pesos, entradas, execução), as palavras que atravessaram o
barramento, os MACs úteis e dos PEs, e o número de saídas que divergem da referência na CPU.

Experimentos (ver MEMORIAL_BENCH_V2.md):
  E1  Validação: todas as configurações, 0 divergências exigidas
  E2  Varredura de intensidade operacional (roofline): densa e convolução, pesos via DMA x residentes
  E3  Ablação na CNN do MNIST (Conv 28x28/3x3/2 e Densa 676->12): cumulativa e "deixa um de fora"
  E4  Independência de dados e esparsidade: NPU x CPU em função da fração de zeros
  E5  CNN completa (Conv + densa encadeadas): streaming, tiles encadeados, fusão e DMA da saída
  E6  Varredura de K no GEMM 4x4 (o cenário do benchmark original), NPU original x otimizada
  E7  Por tipo de operação: Conv2D (tamanho da imagem) e densa lote 1 (K), NPU base x otimizada

Uso:
  python3 tools/bench_v2.py --upload build/fpga/bin/bench_server.bin --port /dev/ttyUSB1
  python3 tools/bench_v2.py --quick            (menos pontos e repetições)
"""
import argparse
import csv
import os
import statistics
import struct
import sys
import time

import serial

KIND_DENSE, KIND_CONV, KIND_CNN = 0, 1, 2
(F_RESIDENT, F_SEQ, F_OUT_DMA, F_GEMV, F_IM2COL, F_BATCH4, F_CPU_REF,
 F_STREAM, F_OVERLAP, F_FUSE, F_RBIAS, F_DESC) = (1 << i for i in range(12))
FLAG_NAMES = [(F_RESIDENT, "resid"), (F_SEQ, "seq"), (F_OUT_DMA, "outdma"), (F_GEMV, "gemv"),
              (F_IM2COL, "im2col"), (F_BATCH4, "lote4"), (F_OVERLAP, "encad"), (F_STREAM, "stream"),
              (F_FUSE, "fusao"), (F_RBIAS, "rbias"), (F_DESC, "desc")]

# Mecanismos que dependem de outro: removê-lo na ablação remove também os dependentes
DEPENDENTS = {F_SEQ: F_OUT_DMA | F_STREAM, F_FUSE: F_DESC}
FIELDS = ["status", "cyc_w", "cyc_in", "cyc_exec", "cyc_total", "cyc_cpu", "mismatches",
          "macs_useful", "macs_pe", "words_w", "words_in", "words_out", "timer_ovh"]
PE_PEAK = 16


def flag_str(flags):
    return "+".join(n for f, n in FLAG_NAMES if flags & f) or "base"


class Bench:
    def __init__(self, port, baud=921600):
        self.ser = serial.Serial(port, baud, timeout=30)

    def upload(self, path):
        repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        sys.path.insert(0, os.path.join(repo, "fpga"))
        import upload as up
        self.ser.rts = True
        up.auto_reset(self.ser)
        up.wait_for_bootloader(self.ser)
        up.perform_handshake(self.ser, os.path.getsize(path))
        up.upload_file(self.ser, path)
        time.sleep(0.3)
        self.ser.reset_input_buffer()

    def run(self, kind, flags, k=0, n=0, in_w=0, in_h=0, ksz=0, stride=0, sparsity=0, seed=1):
        self.ser.write(struct.pack(">cBHBBIBBBB", b"X", kind, flags, sparsity, seed,
                                   (k << 16) | n, in_w, in_h, ksz, stride))
        raw = self.ser.read(4 * len(FIELDS))
        if len(raw) != 4 * len(FIELDS):
            raise RuntimeError("timeout esperando o resultado do experimento")
        r = dict(zip(FIELDS, struct.unpack(">" + "I" * len(FIELDS), raw)))
        if r["status"] != 0:
            raise ValueError(f"parâmetros rejeitados pelo SoC: kind={kind} flags={flag_str(flags)} k={k} n={n}")
        return r


def measure(b, reps, label, layer, **kw):
    """ Repete o experimento e devolve uma linha com medianas e dispersão. """
    runs = [b.run(**kw, seed=1 + i) for i in range(reps)]
    tot = [r["cyc_total"] for r in runs]
    r0 = runs[0]
    med = statistics.median(tot)
    words_bus = r0["words_w"] + r0["words_in"] + r0["words_out"]
    row = {
        "experimento": label, "camada": layer, "mecanismos": flag_str(kw["flags"]),
        "k": kw.get("k", 0), "n": kw.get("n", 0), "in_w": kw.get("in_w", 0), "ksz": kw.get("ksz", 0),
        "stride": kw.get("stride", 0), "esparsidade": kw.get("sparsity", 0), "reps": reps,
        "ciclos_med": med, "ciclos_min": min(tot), "ciclos_max": max(tot),
        "ciclos_pesos": statistics.median(r["cyc_w"] for r in runs),
        "ciclos_entradas": statistics.median(r["cyc_in"] for r in runs),
        "ciclos_exec": statistics.median(r["cyc_exec"] for r in runs),
        "ciclos_cpu": statistics.median(r["cyc_cpu"] for r in runs) if kw["flags"] & F_CPU_REF else 0,
        "divergencias": sum(r["mismatches"] for r in runs),
        "macs_uteis": r0["macs_useful"], "macs_pe": r0["macs_pe"],
        "palavras_pesos": r0["words_w"], "palavras_entradas": r0["words_in"], "palavras_saida": r0["words_out"],
        "palavras_barramento": words_bus,
        "intensidade": r0["macs_useful"] / words_bus if words_bus else 0,
        "macs_uteis_ciclo": r0["macs_useful"] / med, "macs_pe_ciclo": r0["macs_pe"] / med,
        "utilizacao": r0["macs_useful"] / (PE_PEAK * med),
        "timer_ovh": r0["timer_ovh"],
    }
    if row["ciclos_cpu"]:
        row["speedup_cpu"] = row["ciclos_cpu"] / med
    status = "OK" if row["divergencias"] == 0 else f"{row['divergencias']} DIVERGÊNCIAS"
    print(f"  {label:<10} {layer:<26} {row['mecanismos']:<34} {med:>9.0f} ciclos "
          f"[{min(tot)}..{max(tot)}]  {row['macs_uteis_ciclo']:6.2f} MAC/c  I={row['intensidade']:7.2f}  {status}")
    return row


# =============================================================================================
# EXPERIMENTOS
# =============================================================================================

CNN_CONV = dict(kind=KIND_CONV, in_w=28, in_h=28, ksz=3, stride=2)
CNN_DENSE = dict(kind=KIND_DENSE, k=676, n=12)


def e1_validation(b, reps):
    print("\n[E1] Validação: todas as combinações de mecanismos (0 divergências exigidas)")
    rows = []
    for f in [0, F_RESIDENT, F_SEQ, F_SEQ | F_OUT_DMA, F_RESIDENT | F_SEQ | F_OUT_DMA,
              F_SEQ | F_OVERLAP, F_SEQ | F_STREAM, F_RESIDENT | F_SEQ | F_OUT_DMA | F_OVERLAP | F_STREAM]:
        rows.append(measure(b, reps, "E1", "densa 64->8 (lote 1)", flags=f, kind=KIND_DENSE, k=64, n=8))
        rows.append(measure(b, reps, "E1", "densa 64->8 (lote 1)", flags=f | F_GEMV, kind=KIND_DENSE, k=64, n=8))
        rows.append(measure(b, reps, "E1", "densa 64->8 (lote 4)", flags=f | F_BATCH4, kind=KIND_DENSE, k=64, n=8))
        rows.append(measure(b, reps, "E1", "conv 16x12/3x3/1", flags=f, kind=KIND_CONV, in_w=16, in_h=12, ksz=3, stride=1))
        rows.append(measure(b, reps, "E1", "conv 16x12/3x3/1", flags=f | F_IM2COL, kind=KIND_CONV, in_w=16, in_h=12, ksz=3, stride=1))
    return rows


def e2_roofline(b, reps, quick):
    print("\n[E2] Varredura de intensidade operacional (roofline)")
    rows = []
    ks = [16, 64, 256, 1024, 2048] if not quick else [64, 512, 2048]
    full = F_SEQ | F_OUT_DMA | F_OVERLAP | F_STREAM
    for k in ks:
        for res in (0, F_RESIDENT):
            rows.append(measure(b, reps, "E2", f"densa {k}->4 (lote 4)", flags=full | res | F_BATCH4, kind=KIND_DENSE, k=k, n=4))
            rows.append(measure(b, reps, "E2", f"densa {k}->4 (lote 1)", flags=full | res, kind=KIND_DENSE, k=k, n=4))
            rows.append(measure(b, reps, "E2", f"densa {k}->4 (lote 1)", flags=full | res | F_GEMV, kind=KIND_DENSE, k=k, n=4))
    convs = [(28, 28, 3, 2), (28, 28, 3, 1), (32, 32, 5, 1), (20, 20, 7, 1)] if not quick else [(28, 28, 3, 2), (28, 28, 3, 1)]
    for (w, h, ks_, s) in convs:
        for res in (0, F_RESIDENT):
            for i2c in (0, F_IM2COL):
                try:
                    rows.append(measure(b, reps, "E2", f"conv {w}x{h}/{ks_}x{ks_}/{s}", flags=full | res | i2c,
                                        kind=KIND_CONV, in_w=w, in_h=h, ksz=ks_, stride=s))
                except ValueError as e:
                    print(f"  (pulado: {e})")
    return rows


def ablation(b, reps, label, base, all_flags, mandatory=0):
    """ Cumulativa (liga um mecanismo por vez, na ordem dada) e "deixa um de fora" (tudo menos um). """
    rows = []
    acc = mandatory
    rows.append(measure(b, reps, label, base["_name"], flags=acc | F_CPU_REF, **_k(base)))
    for f in all_flags:
        acc |= f
        rows.append(measure(b, reps, label, base["_name"], flags=acc | F_CPU_REF, **_k(base)))
    full = acc
    for f in all_flags:
        if f == F_OUT_DMA:
            continue
        flags = full & ~f & ~DEPENDENTS.get(f, 0)
        row = measure(b, reps, label + "-loo", base["_name"], flags=flags | F_CPU_REF, **_k(base))
        row["removido"] = flag_str(f | (full & DEPENDENTS.get(f, 0)))
        rows.append(row)
    return rows


def _k(d):
    return {k: v for k, v in d.items() if not k.startswith("_")}


def e3_ablation(b, reps):
    print("\n[E3] Ablação na CNN do MNIST (camadas reais)")
    rows = []
    conv = dict(CNN_CONV, _name="conv 28x28/3x3/2 (CNN)")
    dense = dict(CNN_DENSE, _name="densa 676->12 (CNN)")
    rows += ablation(b, reps, "E3", conv, [F_RESIDENT, F_IM2COL, F_SEQ, F_OUT_DMA, F_OVERLAP, F_STREAM])
    rows += ablation(b, reps, "E3", dense, [F_RESIDENT, F_SEQ, F_OUT_DMA, F_GEMV, F_OVERLAP, F_STREAM])
    return rows


def e5_cnn(b, reps):
    """ CNN de duas camadas (Conv 28x28/3x3/2 + densa 676->12), com pesos residentes, im2col e
    GEMV sempre ligados: mede as otimizações de movimentação de dados entre e dentro das camadas. """
    print("\n[E5] CNN completa: Conv + densa encadeadas")
    cnn = dict(kind=KIND_CNN, in_w=28, in_h=28, ksz=3, stride=2, n=12, _name="CNN conv 28x28/3x3/2 + densa 676->12")
    return ablation(b, reps, "E5", cnn, [F_OUT_DMA, F_OVERLAP, F_STREAM, F_FUSE, F_RBIAS, F_DESC])


def e4_sparsity(b, reps):
    print("\n[E4] Independência de dados e esparsidade (NPU x CPU)")
    rows = []
    for sp in (0, 50, 80, 95):
        rows.append(measure(b, reps, "E4", "densa 256->16 (lote 1)", flags=F_RESIDENT | F_SEQ | F_OUT_DMA | F_GEMV | F_CPU_REF,
                            kind=KIND_DENSE, k=256, n=16, sparsity=sp))
        rows.append(measure(b, reps, "E4", "conv 28x28/3x3/2", flags=F_RESIDENT | F_SEQ | F_OUT_DMA | F_IM2COL | F_CPU_REF,
                            sparsity=sp, **CNN_CONV))
    return rows


# =============================================================================================
# FIGURAS
# =============================================================================================

def plot(rows, out_dir, bw):
    """ Figuras detalhadas (todas as séries e a ablação completa), em out_dir/detalhes. """
    out_dir = os.path.join(out_dir, "detalhes")
    os.makedirs(out_dir, exist_ok=True)
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    plt.rcParams.update({"font.size": 10, "font.family": "serif", "axes.grid": True,
                         "grid.linestyle": ":", "grid.alpha": 0.5,
                         "axes.spines.top": False, "axes.spines.right": False})

    # ---------------------------------------------------------------- Roofline (E2)
    e2 = [r for r in rows if r["experimento"] == "E2"]
    fig, ax = plt.subplots(figsize=(7, 5))
    xs = np.logspace(-1, 3, 200)
    ax.plot(xs, np.minimum(PE_PEAK, bw * xs), color="#424242", lw=1.5, label=f"Teto: min(16, {bw:.2f} pal/ciclo × I)")
    ax.axhline(4, color="#9e9e9e", ls="--", lw=1, label="Teto da densa lote 1 no modo normal (4)")
    # Carga e cômputo em série (a NPU não sobrepõe o DMA com o cômputo): 1/P = 1/(B·I) + 1/16
    ax.plot(xs, 1.0 / (1.0 / (bw * xs) + 1.0 / PE_PEAK), color="#424242", lw=1, ls=":",
            label="Modelo sem sobreposição carga/cômputo")
    series = [
        ("lote 4", lambda r: "lote 4" in r["camada"], "o", "#1f77b4"),
        ("lote 1 normal", lambda r: "lote 1" in r["camada"] and "gemv" not in r["mecanismos"], "s", "#ff7f0e"),
        ("lote 1 GEMV", lambda r: "gemv" in r["mecanismos"], "^", "#2ca02c"),
        ("conv im2col CPU", lambda r: r["camada"].startswith("conv") and "im2col" not in r["mecanismos"], "v", "#9467bd"),
        ("conv im2col HW", lambda r: r["camada"].startswith("conv") and "im2col" in r["mecanismos"], "D", "#d62728"),
    ]
    for name, pred, mk, col in series:
        for resid, fill in ((False, "none"), (True, col)):
            pts = [r for r in e2 if pred(r) and (("resid" in r["mecanismos"]) == resid)]
            if pts:
                ax.scatter([p["intensidade"] for p in pts], [p["macs_uteis_ciclo"] for p in pts], marker=mk,
                           facecolors=fill, edgecolors=col, s=40,
                           label=f"{name} ({'pesos residentes' if resid else 'pesos via DMA'})")
    ax.set_xscale("log"); ax.set_yscale("log")
    ax.set_xlabel("Intensidade operacional I (MACs úteis / palavra no barramento)")
    ax.set_ylabel("MACs úteis / ciclo")
    ax.set_title("Roofline da NPU (medido na placa)")
    ax.legend(fontsize=7.5, loc="lower right")
    fig.tight_layout(); fig.savefig(os.path.join(out_dir, "fig_roofline.png"), dpi=300)

    # ---------------------------------------------------------------- Ablação (E3)
    for layer in ("conv 28x28/3x3/2 (CNN)", "densa 676->12 (CNN)", "CNN conv 28x28/3x3/2 + densa 676->12"):
        pts = [r for r in rows if r["experimento"] in ("E3", "E3-loo", "E5", "E5-loo") and r["camada"] == layer]
        if not pts:
            continue
        fig, ax = plt.subplots(figsize=(8, 4))
        labels = [f"tudo, sem {r['removido']}" if r["experimento"].endswith("-loo") else
                  ("base" if r["mecanismos"] == "base" else "+ " + r["mecanismos"]) for r in pts]
        y = np.arange(len(pts))
        left = np.zeros(len(pts))
        cnn = layer.startswith("CNN")
        parts = ((("ciclos_entradas", "#90caf9", "Conv"), ("ciclos_exec", "#a5d6a7", "densa")) if cnn else
                 (("ciclos_pesos", "#ef9a9a", "pesos"), ("ciclos_entradas", "#90caf9", "entradas"),
                  ("ciclos_exec", "#a5d6a7", "execução")))
        for key, col, name in parts:
            vals = np.array([r[key] for r in pts], dtype=float)
            ax.barh(y, vals, left=left, color=col, label=name)
            left += vals
        for i, r in enumerate(pts):
            ax.text(left[i], i, f"  {r['macs_uteis_ciclo']:.2f} MAC/c", va="center", fontsize=7.5)
        ax.set_yticks(y); ax.set_yticklabels(labels, fontsize=7.5); ax.invert_yaxis()
        ax.set_xlabel("Ciclos (mediana; tempo determinístico, sem dispersão entre repetições)")
        ax.set_title(f"Ablação: {layer}")
        ax.legend(fontsize=8, loc="upper center", bbox_to_anchor=(0.5, -0.18), ncol=3, frameon=False)
        fig.tight_layout()
        tag = "cnn" if cnn else ("conv" if layer.startswith("conv") else "densa")
        fig.savefig(os.path.join(out_dir, f"fig_ablacao_{tag}.png"), dpi=300)

    # ---------------------------------------------------------------- Esparsidade (E4)
    e4 = [r for r in rows if r["experimento"] == "E4"]
    if e4:
        fig, ax = plt.subplots(figsize=(7, 4))
        for layer, col in (("densa 256->16 (lote 1)", "#2ca02c"), ("conv 28x28/3x3/2", "#d62728")):
            pts = [r for r in e4 if r["camada"] == layer]
            sp = [p["esparsidade"] for p in pts]
            ax.plot(sp, [p["ciclos_cpu"] for p in pts], marker="o", color=col, ls="--", label=f"CPU: {layer}")
            ax.plot(sp, [p["ciclos_med"] for p in pts], marker="s", color=col, label=f"NPU: {layer}")
        ax.set_yscale("log"); ax.set_xlabel("Fração de ativações nulas (%)"); ax.set_ylabel("Ciclos")
        ax.set_title("Dependência dos dados: NPU (tempo fixo) x CPU")
        ax.legend(fontsize=8)
        fig.tight_layout(); fig.savefig(os.path.join(out_dir, "fig_esparsidade.png"), dpi=300)


# Configurações comparadas na varredura de K (E6): o GEMM 4x4 do benchmark original
E6_BASE = F_BATCH4                                                  # pesos via DMA, um START, CPU lê
E6_OPT  = F_BATCH4 | F_RESIDENT | F_SEQ | F_OUT_DMA | F_OVERLAP | F_STREAM
E6_KS   = [4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048]            # 2048 = capacidade da RAM da NPU


def e6_sweep(b, reps):
    print("\n[E6] Varredura de K no GEMM 4x4: NPU original x otimizada")
    rows = []
    for k in E6_KS:
        for name, f in (("original", E6_BASE), ("otimizada", E6_OPT)):
            rows.append(measure(b, reps, "E6", f"GEMM 4x4 ({name})", flags=f | F_CPU_REF, kind=KIND_DENSE, k=k, n=4))
    for name, f in (("original", E6_BASE), ("otimizada", E6_OPT)):
        rows.append(measure(b, reps, "E6", f"GEMM 4x4 ({name})", flags=f | F_CPU_REF, kind=KIND_DENSE,
                            k=E6_KS[-1], n=4, sparsity=80))
    return rows


# Comparação por tipo de operação (E7): base = sem os mecanismos de movimentação de dados
E7_CONV_BASE = 0                                                    # pesos via DMA, im2col na CPU, START por tile
E7_CONV_OPT  = F_RESIDENT | F_IM2COL | F_SEQ | F_OUT_DMA | F_OVERLAP | F_STREAM
E7_CONV_NS   = [8, 12, 16, 20, 24, 28, 32]                          # imagem N x N (32x32 = limite do im2col)
E7_DENSE_BASE = 0                                                   # modo normal: 1 linha do array útil
E7_DENSE_OPT  = F_RESIDENT | F_SEQ | F_OUT_DMA | F_GEMV | F_OVERLAP | F_STREAM
E7_DENSE_KS   = [16, 32, 64, 128, 256, 512, 1024, 2048]


def e7_ops(b, reps):
    print("\n[E7] Por tipo de operação: Conv2D e densa, NPU base x otimizada")
    rows = []
    for n in E7_CONV_NS:
        for name, f in (("base", E7_CONV_BASE), ("otimizada", E7_CONV_OPT)):
            rows.append(measure(b, reps, "E7", f"Conv2D 3x3 ({name})", flags=f | F_CPU_REF, kind=KIND_CONV,
                                in_w=n, in_h=n, ksz=3, stride=1))
    for k in E7_DENSE_KS:
        for name, f in (("base", E7_DENSE_BASE), ("otimizada", E7_DENSE_OPT)):
            rows.append(measure(b, reps, "E7", f"Densa lote 1 ({name})", flags=f | F_CPU_REF, kind=KIND_DENSE, k=k, n=4))
    # Esparsidade (80% de ativações nulas) no maior tamanho de cada operação
    for name, fc, fd in (("base", E7_CONV_BASE, E7_DENSE_BASE), ("otimizada", E7_CONV_OPT, E7_DENSE_OPT)):
        rows.append(measure(b, reps, "E7", f"Conv2D 3x3 ({name})", flags=fc | F_CPU_REF, kind=KIND_CONV,
                            in_w=E7_CONV_NS[-1], in_h=E7_CONV_NS[-1], ksz=3, stride=1, sparsity=80))
        rows.append(measure(b, reps, "E7", f"Densa lote 1 ({name})", flags=fd | F_CPU_REF, kind=KIND_DENSE,
                            k=E7_DENSE_KS[-1], n=4, sparsity=80))
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", default="/dev/ttyUSB1")
    ap.add_argument("--upload", help="sobe este binário do bench_server antes de medir")
    ap.add_argument("--reps", type=int, default=5)
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--out", default="build/bench_v2")
    ap.add_argument("--only", help="lista de experimentos, ex.: E1,E3")
    ap.add_argument("--replot", action="store_true", help="só refaz as figuras a partir do CSV de --out")
    ap.add_argument("--append", action="store_true",
                    help="mescla com o CSV existente em --out, substituindo só os experimentos refeitos")
    a = ap.parse_args()
    if a.replot:
        num = lambda v: float(v) if v.replace('.', '', 1).replace('-', '', 1).isdigit() else v
        rows = [{k: num(v) for k, v in r.items()} for r in csv.DictReader(open(os.path.join(a.out, "bench_v2.csv")))]
        finish(rows, a.out)
        return
    reps = 3 if a.quick else a.reps
    os.makedirs(a.out, exist_ok=True)

    b = Bench(a.port)
    if a.upload:
        b.upload(a.upload)

    only = set(a.only.split(",")) if a.only else {"E1", "E2", "E3", "E4", "E5", "E6", "E7"}
    rows = []
    if "E1" in only: rows += e1_validation(b, reps)
    if "E2" in only: rows += e2_roofline(b, reps, a.quick)
    if "E3" in only: rows += e3_ablation(b, reps)
    if "E4" in only: rows += e4_sparsity(b, reps)
    if "E5" in only: rows += e5_cnn(b, reps)
    if "E6" in only: rows += e6_sweep(b, reps)
    if "E7" in only: rows += e7_ops(b, reps)

    path = os.path.join(a.out, "bench_v2.csv")
    if a.append and os.path.exists(path):
        redone = {r["experimento"].split("-")[0] for r in rows}
        num = lambda v: float(v) if v.replace('.', '', 1).replace('-', '', 1).isdigit() else v
        old = [{k: num(v) for k, v in r.items()} for r in csv.DictReader(open(path))]
        rows = [r for r in old if r["experimento"].split("-")[0] not in redone] + rows

    keys = list(dict.fromkeys(k for r in rows for k in r))
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader(); w.writerows(rows)
    print(f"\nResultados: {path}")

    bad = sum(r["divergencias"] for r in rows)
    print(f"Divergências contra a referência na CPU: {bad}")

    finish(rows, a.out)
    sys.exit(1 if bad else 0)


def dma_bandwidth(rows):
    """ Banda efetiva do DMA RAM -> NPU: palavras de pesos / ciclos da fase de pesos, só em pontos
    sem streaming (com streaming a carga corre em paralelo e a fase de pesos não a mede). """
    bws = [float(r["palavras_pesos"]) / float(r["ciclos_pesos"]) for r in rows
           if "stream" not in r["mecanismos"] and float(r["palavras_pesos"]) >= 256 and float(r["ciclos_pesos"]) > 0]
    return statistics.median(bws) if bws else 0.5


def finish(rows, out_dir):
    bw = dma_bandwidth(rows)
    print(f"Banda efetiva do DMA (mediana): {bw:.3f} palavras/ciclo")
    plot(rows, out_dir, bw)
    plot_article(rows, out_dir, bw)
    print(f"Figuras em {out_dir}/")




# =============================================================================================
# FIGURAS PARA O ARTIGO (estilo do bench_client.py original: simples e ilustrativas)
# =============================================================================================

STEP_LABELS = {
    "base": "Base", "resid": "Pesos\nresidentes", "im2col": "im2col\nem HW", "seq": "Sequenciador\nde tiles",
    "outdma": "Saída\npor DMA", "gemv": "Modo\nGEMV", "encad": "Tiles\nencadeados", "stream": "Streaming",
    "fusao": "Fusão\nConv→densa", "rbias": "Biases\nresidentes", "desc": "Descritores\nde camada",
}


def _style():
    import matplotlib.pyplot as plt
    plt.rcParams.update({
        "font.size": 11, "font.family": "serif", "mathtext.fontset": "cm",
        "axes.spines.top": False, "axes.spines.right": False,
        "axes.grid": True, "grid.linestyle": ":", "grid.alpha": 0.5,
        "legend.framealpha": 1.0, "legend.edgecolor": "#e0e0e0",
    })
    return plt


def _cumulative(rows, exp, layer):
    """ Passos da ablação cumulativa: (rótulo do mecanismo acrescentado, linha). """
    pts = [r for r in rows if r["experimento"] == exp and r["camada"] == layer]
    out, prev = [], set()
    for r in pts:
        cur = set(r["mecanismos"].split("+")) - {"base"}
        new = [m for m in cur - prev]
        out.append((STEP_LABELS[new[0]] if new else "Base", r))
        prev = cur
    return out


def _ablation_bars(ax, steps, title, color_from, color_to):
    import numpy as np
    from matplotlib.colors import to_rgb
    n = len(steps)
    c0, c1 = np.array(to_rgb(color_from)), np.array(to_rgb(color_to))
    cols = [tuple(c0 + (c1 - c0) * i / max(n - 1, 1)) for i in range(n)]
    vals = [float(r["macs_uteis_ciclo"]) for _, r in steps]
    base_cyc = float(steps[0][1]["ciclos_med"])
    x = np.arange(n)
    bars = ax.bar(x, vals, color=cols, edgecolor="#2c3e50", linewidth=1.0, width=0.7)
    for b, (_, r) in zip(bars, steps):
        sp = base_cyc / float(r["ciclos_med"])
        ax.annotate(f"{b.get_height():.2f}\n({sp:.0f}×)" if sp >= 1.5 else f"{b.get_height():.2f}",
                    xy=(b.get_x() + b.get_width() / 2, b.get_height()), xytext=(0, 4),
                    textcoords="offset points", ha="center", va="bottom", fontsize=8.5, fontweight="bold")
    ax.axhline(PE_PEAK, color="#d32f2f", ls="--", lw=1.5, label="Teto sistólico (16 MACs/ciclo)")
    ax.set_xticks(x)
    labels = [("+ " if i else "") + lab.replace("\n", " ") if n > 6 else ("+ " if i else "") + lab
              for i, (lab, _) in enumerate(steps)]
    if n > 6:                                                       # muitos passos: rótulos inclinados
        ax.set_xticklabels(labels, fontsize=8.5, rotation=30, ha="right", rotation_mode="anchor")
    else:
        ax.set_xticklabels(labels, fontsize=8.5)
    ax.set_ylim(0, PE_PEAK * 1.15)
    ax.set_ylabel("Vazão útil (MACs/ciclo)")
    ax.set_title(title, pad=12, fontweight="bold")
    ax.legend(loc="upper left", fontsize=9)


def plot_article(rows, out_dir, bw):
    import numpy as np
    plt = _style()
    full = "seq+outdma"                                              # E2 usa a configuração completa

    # ================================================================ Figura 1: visão geral
    fig, (ax1, ax2, ax3) = plt.subplots(1, 3, figsize=(18, 5.5))

    # (a) Roofline simplificado: só pesos residentes e configuração completa
    e2 = [r for r in rows if r["experimento"] == "E2" and "resid" in r["mecanismos"] and full in r["mecanismos"]]
    xs = np.logspace(0, 2.5, 200)
    roof = np.minimum(PE_PEAK, bw * xs)
    knee = PE_PEAK / bw
    ax1.plot(xs, roof, color="#424242", lw=2.5, label=f"Teto (cômputo: 16; memória: {bw:.2f} pal/ciclo)")
    ax1.fill_between(xs[xs <= knee], 0.05, roof[xs <= knee], color="#90caf9", alpha=0.25)
    ax1.fill_between(xs[xs >= knee], 0.05, roof[xs >= knee], color="#a5d6a7", alpha=0.25)
    ax1.text(knee / 3.2, 0.12, "Limitado pela\nmemória", ha="center", fontsize=10, fontweight="bold", color="#1565c0")
    ax1.text(knee * 3.5, 0.12, "Limitado pelo\ncômputo", ha="center", fontsize=10, fontweight="bold", color="#2e7d32")
    # Um ponto por família (o maior problema medido), sem linhas: o roofline compara famílias,
    # não tamanhos (a variação com o tamanho está nas figuras detalhadas)
    kmax = max((int(float(r["k"])) for r in e2 if r["camada"].startswith("densa")), default=0)
    series = [
        ("Densa, lote 1 (GEMV)", lambda r: "gemv" in r["mecanismos"] and int(float(r["k"])) == kmax, "^", "#2ca02c"),
        ("Densa, lote 4", lambda r: "lote 4" in r["camada"] and int(float(r["k"])) == kmax, "o", "#1f77b4"),
        ("Convolução (im2col HW, 4 geometrias)", lambda r: r["camada"].startswith("conv") and "im2col" in r["mecanismos"], "D", "#d62728"),
    ]
    for name, pred, mk, col in series:
        pts = [r for r in e2 if pred(r)]
        ax1.scatter([float(p["intensidade"]) for p in pts], [float(p["macs_uteis_ciclo"]) for p in pts],
                    marker=mk, s=70, color=col, edgecolor="black", linewidth=0.6, label=name, zorder=4)
    # Camadas da CNN real (E3, configuração completa)
    for layer, txt, col in (("conv 28x28/3x3/2 (CNN)", "Conv da CNN", "#d62728"), ("densa 676->12 (CNN)", "Densa da CNN", "#2ca02c")):
        pts = [r for r in rows if r["experimento"] == "E3" and r["camada"] == layer]
        if pts:
            best = max(pts, key=lambda r: float(r["macs_uteis_ciclo"]))
            xp, yp = float(best["intensidade"]), float(best["macs_uteis_ciclo"])
            ax1.scatter([xp], [yp], s=160, marker="*", color=col, edgecolor="black", zorder=5)
            ax1.annotate(txt, xy=(xp, yp), xytext=(8, -14), textcoords="offset points", fontsize=9, fontweight="bold")
    ax1.set_xscale("log"); ax1.set_yscale("log")
    ax1.set_ylim(0.1, 40); ax1.set_xlim(1, 10 ** 2.5)
    ax1.set_xlabel("Intensidade operacional $I$ (MACs úteis / palavra no barramento)")
    ax1.set_ylabel("Vazão útil (MACs/ciclo)")
    ax1.set_title("(a) Roofline da NPU (medido na placa)", pad=12, fontweight="bold")
    ax1.legend(loc="upper left", fontsize=8.5)

    # (b) Ganho acumulado de cada mecanismo na CNN completa (E5)
    steps = _cumulative(rows, "E5", "CNN conv 28x28/3x3/2 + densa 676->12")
    if steps:
        _ablation_bars(ax2, steps, "(b) CNN completa: ganho por mecanismo", "#cfd8dc", "#673ab7")

    # (c) CPU x NPU por camada (configuração completa)
    cases = []
    for layer, lab in (("conv 28x28/3x3/2 (CNN)", "Conv 3×3"), ("densa 676->12 (CNN)", "Densa 676→12")):
        pts = [r for r in rows if r["experimento"] == "E3" and r["camada"] == layer and float(r["ciclos_cpu"])]
        if pts: cases.append((lab, min(pts, key=lambda r: float(r["ciclos_med"]))))
    pts = [r for r in rows if r["experimento"] == "E5" and float(r["ciclos_cpu"])]
    if pts: cases.append(("CNN completa", min(pts, key=lambda r: float(r["ciclos_med"]))))
    if cases:
        x = np.arange(len(cases)); w = 0.35
        cpu = [float(r["ciclos_cpu"]) for _, r in cases]; npu = [float(r["ciclos_med"]) for _, r in cases]
        r1 = ax3.bar(x - w / 2, cpu, w, label="CPU escalar (RV32I, -O2)", color="#9eaebf", edgecolor="#2c3e50", lw=1.2, hatch="///")
        r2 = ax3.bar(x + w / 2, npu, w, label="NPU sistólica", color="#a5d6a7", edgecolor="#2e7d32", lw=1.2, hatch="\\\\\\")
        for rect in list(r1) + list(r2):
            ax3.annotate(f"{int(rect.get_height()):,}".replace(",", "."), xy=(rect.get_x() + rect.get_width() / 2, rect.get_height()),
                         xytext=(0, 4), textcoords="offset points", ha="center", va="bottom", fontsize=8.5, fontweight="bold")
        for i, (c, n_) in enumerate(zip(cpu, npu)):
            ax3.text(i, max(c, n_) * 6, f"{c / n_:,.0f}×".replace(",", "."), ha="center", fontsize=11, fontweight="bold", color="#673ab7")
        ax3.set_yscale("log"); ax3.set_ylim(top=max(cpu) * 40)
        ax3.set_xticks(x); ax3.set_xticklabels([c for c, _ in cases])
        ax3.set_ylabel("Ciclos de clock")
        ax3.set_title("(c) Aceleração sobre a CPU", pad=12, fontweight="bold")
        ax3.legend(loc="upper center", bbox_to_anchor=(0.5, -0.1), ncol=2, fontsize=9, frameon=False)

    fig.tight_layout(); fig.subplots_adjust(wspace=0.25)
    fig.savefig(os.path.join(out_dir, "figura_v2_desempenho.png"), dpi=400, bbox_inches="tight")

    # ================================================================ Figura 2: ganho por camada
    fig, axes = plt.subplots(1, 2, figsize=(15, 5))
    for ax, layer, title, c1 in ((axes[0], "conv 28x28/3x3/2 (CNN)", "(a) Convolução 3×3, passo 2", "#d62728"),
                                 (axes[1], "densa 676->12 (CNN)", "(b) Densa 676→12, lote 1", "#2ca02c")):
        steps = _cumulative(rows, "E3", layer)
        if steps: _ablation_bars(ax, steps, title, "#eceff1", c1)
    fig.tight_layout(); fig.subplots_adjust(wspace=0.2)
    fig.savefig(os.path.join(out_dir, "figura_v2_camadas.png"), dpi=400, bbox_inches="tight")

    # ================================================================ Figura 3: dependência de dados
    e4 = [r for r in rows if r["experimento"] == "E4"]
    if e4:
        fig, ax = plt.subplots(figsize=(7, 4.8))
        for layer, lab, col in (("conv 28x28/3x3/2", "Convolução", "#d62728"), ("densa 256->16 (lote 1)", "Densa (GEMV)", "#2ca02c")):
            pts = sorted([r for r in e4 if r["camada"] == layer], key=lambda r: float(r["esparsidade"]))
            sp = [float(p["esparsidade"]) for p in pts]
            ax.plot(sp, [float(p["ciclos_cpu"]) for p in pts], marker="o", ls="--", lw=2, color=col, label=f"CPU: {lab}")
            ax.plot(sp, [float(p["ciclos_med"]) for p in pts], marker="s", lw=2.5, color=col, label=f"NPU: {lab}")
        ax.set_yscale("log"); ax.set_xticks([0, 50, 80, 95])
        ax.set_xlabel("Fração de ativações nulas (%)"); ax.set_ylabel("Ciclos de clock")
        ax.set_title("Tempo da NPU independe dos dados", pad=12, fontweight="bold")
        ax.legend(fontsize=9, loc="center right")
        fig.tight_layout(); fig.savefig(os.path.join(out_dir, "figura_v2_esparsidade.png"), dpi=400, bbox_inches="tight")

    plot_efficiency(rows, out_dir)
    print(f"Figuras do artigo: {out_dir}/figura_v2_*.png")


def _triplet(path, x_b, tp_b, sp_b, x_o, tp_o, sp_o, xlabel, xlog2, sparse, sparse_label,
             titles, extra_ceiling=None, xticks=None, gain_pos=None):
    """ Três painéis no formato do bench_client.py original: (a) eficiência e muro da memória,
    (b) speedup em função do tamanho, (c) esparsidade. Compara a NPU base com a otimizada. """
    import numpy as np
    plt = _style()
    c_base, c_opt = "#ff9800", "#2ca02c"
    teto = float(PE_PEAK)
    emp_b, emp_o = tp_b.max(), tp_o.max()
    fig, (ax1, ax2, ax3) = plt.subplots(1, 3, figsize=(18, 5.5))

    # ------------------------------------------------------------- (a) Eficiência e muro da memória
    ax1.axhline(y=teto, color="#d32f2f", linestyle="--", linewidth=2, label="Teto Sistólico (16 MACs/ciclo)")
    if extra_ceiling:
        ax1.axhline(y=extra_ceiling[0], color="#757575", linestyle=":", linewidth=1.8, label=extra_ceiling[1])
    ax1.axhline(y=emp_o, color=c_opt, linestyle="-.", linewidth=1.5, alpha=0.8, label=f"Teto Empírico Otimizado (~{emp_o:.2f})")
    ax1.axhline(y=emp_b, color=c_base, linestyle="-.", linewidth=1.5, alpha=0.8, label=f"Teto Empírico Base (~{emp_b:.2f})")
    ax1.fill_between(x_o, emp_o, teto, color="#ef9a9a", alpha=0.2, hatch="\\\\")
    ax1.fill_between(x_o, emp_b, emp_o, color="#a5d6a7", alpha=0.25)
    ax1.plot(x_b, tp_b, marker="s", markersize=6, linewidth=2, linestyle="--", color=c_base, label="NPU Base")
    ax1.plot(x_o, tp_o, marker="^", markersize=6, linewidth=2.5, color=c_opt, label="NPU Otimizada")
    xm = x_o[len(x_o) // 2 - 1]
    ax1.text(xm, (emp_o + teto) / 2, "Inanição Restante", color="#c62828", fontsize=10, fontweight="bold",
             ha="center", va="center", bbox=dict(boxstyle="round,pad=0.2", fc="white", ec="none", alpha=0.8))
    gx, gfrac = gain_pos if gain_pos else (xm, 0.5)                 # posição do rótulo, livre da curva
    ax1.text(gx, emp_b + (emp_o - emp_b) * gfrac, f"Ganho das Otimizações ({emp_o / emp_b:.1f}×)", color="#2e7d32",
             fontsize=10, fontweight="bold", ha="center", va="center",
             bbox=dict(boxstyle="round,pad=0.2", fc="white", ec="none", alpha=0.8))
    if xlog2: ax1.set_xscale("log", base=2)
    if xticks is not None: ax1.set_xticks(xticks); ax1.set_xticklabels([str(int(t)) for t in xticks])
    ax1.set_ylim(0, teto * 1.1)
    ax1.set_xlabel(xlabel)
    ax1.set_ylabel("Vazão Sustentada (MACs úteis/ciclo)")
    ax1.set_title(titles[0], pad=12, fontweight="bold")
    ax1.legend(loc="upper center", bbox_to_anchor=(0.5, -0.14), ncol=2, fontsize=8.5, frameon=False)

    # ------------------------------------------------------------- (b) Aceleração arquitetural
    ax2.plot(x_o, sp_o, marker="o", markersize=4, linewidth=1.8, color="#673ab7", label="Speedup (NPU Otimizada)")
    ax2.plot(x_b, sp_b, marker="s", markersize=4, linewidth=1.5, linestyle="--", color=c_base, label="Speedup (NPU Base)")
    for xx, sp, col, dy in ((x_o[-1], sp_o[-1], "#673ab7", 0), (x_b[-1], sp_b[-1], c_base, 12)):
        ax2.annotate(f"{sp:,.0f}×".replace(",", "."), xy=(xx, sp), xytext=(-8, dy), textcoords="offset points",
                     ha="right", va="center", fontsize=10, fontweight="bold", color=col)
    if xlog2: ax2.set_xscale("log", base=2)
    if xticks is not None: ax2.set_xticks(xticks); ax2.set_xticklabels([str(int(t)) for t in xticks])
    ax2.set_xlabel(xlabel)
    ax2.set_ylabel("Ganho Relativo ($Speedup$)")
    ax2.set_title(titles[1], pad=12, fontweight="bold")
    ax2.legend(loc="upper left", fontsize=9.5)

    # ------------------------------------------------------------- (c) Impacto da esparsidade
    labels = ["CPU Escalar", "NPU Base", "NPU Otimizada"]
    dense = [sparse["cpu"][0], sparse["base"][0], sparse["opt"][0]]
    spars = [sparse["cpu"][1], sparse["base"][1], sparse["opt"][1]]
    x = np.arange(len(labels)); width = 0.35
    r1 = ax3.bar(x - width / 2, dense, width, label="Densa (0% Zeros)", color="#9eaebf", edgecolor="#2c3e50", linewidth=1.2, hatch="///")
    r2 = ax3.bar(x + width / 2, spars, width, label="Esparsa (80% Zeros)", color="#f5cba7", edgecolor="#e67e22", linewidth=1.2, hatch="\\\\\\")
    for rect in list(r1) + list(r2):
        h = rect.get_height()
        txt = (f"{h / 1e6:.1f} M" if h >= 1e6 else f"{h / 1e3:.1f} k" if h >= 1e4 else f"{int(h):,}").replace(",", ".")
        txt = txt.replace(".", ",") if ("M" in txt or "k" in txt) else txt
        ax3.annotate(txt, xy=(rect.get_x() + rect.get_width() / 2, h), xytext=(0, 4), textcoords="offset points",
                     ha="center", va="bottom", fontsize=9, fontweight="bold")
    ax3.set_yscale("log"); ax3.set_ylim(top=max(dense + spars) * 10)
    ax3.set_ylabel("Ciclos de Clock")
    ax3.set_title(f"{titles[2]} ({sparse_label})", pad=12, fontweight="bold")
    ax3.set_xticks(x); ax3.set_xticklabels(labels)
    ax3.legend(loc="upper right", fontsize=9.5)

    fig.tight_layout(); fig.subplots_adjust(wspace=0.25)
    fig.savefig(path, dpi=400, bbox_inches="tight")


def _sweep(rows, exp, layer, xkey, sparsity=0):
    import numpy as np
    pts = sorted([r for r in rows if r["experimento"] == exp and r["camada"] == layer and float(r["esparsidade"]) == sparsity],
                 key=lambda r: float(r[xkey]))
    return (np.array([float(r[xkey]) for r in pts]), np.array([float(r["macs_uteis_ciclo"]) for r in pts]),
            np.array([float(r["ciclos_cpu"]) / float(r["ciclos_med"]) for r in pts]), pts)


def _sparse_at(rows, exp, base_layer, opt_layer, xkey, xval):
    def at(layer, sp):
        return next(r for r in rows if r["experimento"] == exp and r["camada"] == layer and
                    float(r["esparsidade"]) == sp and float(r[xkey]) == xval)
    return {"cpu": (float(at(opt_layer, 0)["ciclos_cpu"]), float(at(opt_layer, 80)["ciclos_cpu"])),
            "base": (float(at(base_layer, 0)["ciclos_med"]), float(at(base_layer, 80)["ciclos_med"])),
            "opt": (float(at(opt_layer, 0)["ciclos_med"]), float(at(opt_layer, 80)["ciclos_med"]))}


def plot_efficiency(rows, out_dir):
    """ Figuras no formato do bench_client.py original: GEMM 4x4 (E6) e por tipo de operação (E7). """
    # ---------------------------------------------------------------- GEMM 4x4 (E6)
    xb, tb, sb, _ = _sweep(rows, "E6", "GEMM 4x4 (original)", "k")
    xo, to, so, _ = _sweep(rows, "E6", "GEMM 4x4 (otimizada)", "k")
    if len(xb) and len(xo):
        sparse = _sparse_at(rows, "E6", "GEMM 4x4 (original)", "GEMM 4x4 (otimizada)", "k", xo[-1])
        _triplet(os.path.join(out_dir, "figura_v2_eficiencia.png"), xb, tb, sb, xo, to, so,
                 "Dimensão da Matriz ($K$)", True, sparse, f"$K={int(xo[-1])}$",
                 ("(a) Eficiência da NPU e Muro da Memória", "(b) Aceleração Arquitetural", "(c) Impacto da Esparsidade"))

    # ---------------------------------------------------------------- Conv2D 3x3 (E7)
    xb, tb, sb, _ = _sweep(rows, "E7", "Conv2D 3x3 (base)", "in_w")
    xo, to, so, _ = _sweep(rows, "E7", "Conv2D 3x3 (otimizada)", "in_w")
    if len(xb) and len(xo):
        sparse = _sparse_at(rows, "E7", "Conv2D 3x3 (base)", "Conv2D 3x3 (otimizada)", "in_w", xo[-1])
        _triplet(os.path.join(out_dir, "figura_v2_conv2d.png"), xb, tb, sb, xo, to, so,
                 "Dimensão da Imagem ($N \\times N$)", False, sparse, f"${int(xo[-1])}\\times{int(xo[-1])}$",
                 ("(a) Conv2D 3×3: Eficiência da NPU", "(b) Conv2D 3×3: Aceleração", "(c) Conv2D: Esparsidade"),
                 xticks=xo, gain_pos=(xo[len(xo) * 2 // 3], 0.3))

    # ---------------------------------------------------------------- Densa lote 1 (E7)
    xb, tb, sb, _ = _sweep(rows, "E7", "Densa lote 1 (base)", "k")
    xo, to, so, _ = _sweep(rows, "E7", "Densa lote 1 (otimizada)", "k")
    if len(xb) and len(xo):
        sparse = _sparse_at(rows, "E7", "Densa lote 1 (base)", "Densa lote 1 (otimizada)", "k", xo[-1])
        _triplet(os.path.join(out_dir, "figura_v2_densa.png"), xb, tb, sb, xo, to, so,
                 "Entradas da Camada ($K$)", True, sparse, f"$K={int(xo[-1])}$",
                 ("(a) Densa (lote 1): Eficiência da NPU", "(b) Densa (lote 1): Aceleração", "(c) Densa: Esparsidade"),
                 extra_ceiling=(4.0, "Teto do Modo Normal (1 linha útil: 4 MACs/ciclo)"))


if __name__ == "__main__":
    main()
