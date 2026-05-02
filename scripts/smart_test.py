#!/usr/bin/env python3
import subprocess
import sys
import os
import yaml

CONFIG_FILE = "soc_deps.yml"

def get_changed_files():
    """Obtém a lista de arquivos alterados, adaptando-se ao ambiente (Local vs CI vs PR)."""
    
    is_ci = os.environ.get('GITHUB_ACTIONS') == 'true'
    event_name = os.environ.get('GITHUB_EVENT_NAME')
    base_ref = os.environ.get('GITHUB_BASE_REF') # Ex: 'main' em um PR
    
    if is_ci:
        if event_name == 'pull_request' and base_ref:
            # Em um PR, compara a branch alvo inteira com o código atual do PR
            cmd = ["git", "diff", "--name-only", f"origin/{base_ref}", "HEAD"]
            print(f"==> Modo PR detectado: Comparando origin/{base_ref} com HEAD")
        else:
            # Em um push direto para a main, compara com o commit imediatamente anterior
            cmd = ["git", "diff", "--name-only", "HEAD~1", "HEAD"]
            print("==> Modo Push detectado: Comparando HEAD~1 com HEAD")
    else:
        # Localmente, olha para o 'stage' (arquivos adicionados com git add)
        cmd = ["git", "diff", "--cached", "--name-only"]
        print("==> Modo Local detectado: Analisando arquivos em stage")
        
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"❌ Erro ao executar git diff: {result.stderr}", file=sys.stderr)
        sys.exit(1)
        
    return [f for f in result.stdout.strip().split('\n') if f]

def main():
    print("==> Analisando modificações do Git...")
    changed_files = get_changed_files()
    
    if not changed_files:
        print("==> Nenhuma alteração detectada no stage/commit. Pulando testes.")
        return 0

    # 1. Carrega a matriz de dependências do arquivo YAML
    try:
        with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
    except FileNotFoundError:
        print(f"❌ Erro fatal: O arquivo '{CONFIG_FILE}' não foi encontrado na raiz do projeto.")
        return 1
    except yaml.YAMLError as exc:
        print(f"❌ Erro de sintaxe no YAML: {exc}")
        return 1

    targets_dict = config.get("targets", {})
    targets_to_run = set()

    # 2. Cruza os arquivos alterados com a matriz do YAML
    for changed_file in changed_files:
        for target_name, dependencies in targets_dict.items():
            if changed_file in dependencies:
                targets_to_run.add(target_name)

    if not targets_to_run:
        print("==> As alterações não afetam nenhum módulo mapeado no YAML. Pulando testes.")
        return 0
        
    print(f"==> Alvos identificados para teste: {', '.join(targets_to_run)}")
    
    # 3. Executa os testes identificados
    for target in targets_to_run:
        # Usa a regra mágica que criamos no Makefile minimalista
        cmd = f"make test-unit-{target}"
        
        print(f"\n--- Executando {cmd} ---")
        result = subprocess.run(cmd, shell=True)
        
        if result.returncode != 0:
            print(f"\n❌ Falha no teste: {target}")
            return 1
            
    print("\n✅ Todos os testes condicionais passaram!")
    return 0

if __name__ == "__main__":
    sys.exit(main())