#!/usr/bin/env python3
import subprocess
import sys
import os
import yaml
import argparse

CONFIG_FILE = "soc_deps.yml"

def get_changed_files():
    """Obtém a lista de arquivos alterados, incluindo staged e unstaged."""
    is_ci = os.environ.get('GITHUB_ACTIONS') == 'true'
    event_name = os.environ.get('GITHUB_EVENT_NAME')
    base_ref = os.environ.get('GITHUB_BASE_REF')
    
    if is_ci:
        if event_name == 'pull_request' and base_ref:
            cmd = ["git", "diff", "--name-only", f"origin/{base_ref}", "HEAD"]
        else:
            cmd = ["git", "diff", "--name-only", "HEAD~1", "HEAD"]
    else:
        # HEAD compara o estado atual (staged ou não) com o último commit
        cmd = ["git", "diff", "HEAD", "--name-only"]
        print("==> Modo Local detectado: Analisando workspace e stage")
        
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        return []
        
    # Filtra linhas vazias e remove duplicatas
    return list(set(f for f in result.stdout.strip().split('\n') if f))

def main():
    parser = argparse.ArgumentParser(description="CI/CD Test Runner para SuperNova-RV")
    parser.add_argument("--regression", action="store_true", help="Executa todos os testes para single e multi cycle")
    args = parser.parse_args()

    try:
        with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
    except Exception as e:
        print(f"❌ Erro ao ler YAML: {e}")
        return 1

    targets_dict = config.get("targets", {})
    targets_to_run = set()

    if args.regression:
        print("==> 🛠️  MODO REGRESSÃO ATIVADO: Selecionando todos os testes...")
        # Define as arquiteturas alvo para a regressão
        regression_archs = ["single_cycle", "multi_cycle"]
        
        for arch in regression_archs:
            if arch in targets_dict:
                for target_name in targets_dict[arch].keys():
                    targets_to_run.add((arch, target_name))
            else:
                print(f"⚠️  Aviso: Arquitetura '{arch}' não encontrada no YAML.")
    else:
        print("==> Analisando modificações do Git...")
        changed_files = get_changed_files()
        
        if not changed_files:
            print("==> Nenhuma alteração detectada. Pulando testes.")
            return 0

        # Cruza arquivos alterados com a matriz (comportamento original)
        for changed_file in changed_files:
            for arch, modules in targets_dict.items():
                for target_name, target_data in modules.items():
                    deps = target_data if isinstance(target_data, list) else target_data.get("deps", [])
                    if changed_file in deps:
                        targets_to_run.add((arch, target_name))

    if not targets_to_run:
        print("==> Nenhum alvo identificado. Finalizando.")
        return 0
        
    print(f"==> Total de alvos para execução: {len(targets_to_run)}")
    
    # Execução dos testes
    for arch, target in targets_to_run:
        target_data = targets_dict[arch][target]
        deps = target_data if isinstance(target_data, list) else target_data.get("deps", [])

        if any("/e2e/" in f for f in deps):
            make_prefix = "test-e2e"
        elif any("/integration/" in f for f in deps):
            make_prefix = "test-int"
        else:
            make_prefix = "test-unit"
        
        cmd = f"make {make_prefix}-{target} CORE_ARCH={arch}"
        print(f"\n--- 🚀 Executando: {cmd} ---")
        
        result = subprocess.run(cmd, shell=True)
        if result.returncode != 0:
            print(f"\n❌ Falha crítica no alvo: {target} ({arch})")
            return 1
            
    print("\n✅ Sucesso: Todos os testes selecionados passaram!")
    return 0

if __name__ == "__main__":
    sys.exit(main())