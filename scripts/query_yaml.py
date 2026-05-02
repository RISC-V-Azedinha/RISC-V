#!/usr/bin/env python3
import yaml
import sys

def main():
    if len(sys.argv) < 4:
        return
    
    # Recebe a arquitetura (ou domínio), alvo e chave
    arch, target, key = sys.argv[1], sys.argv[2], sys.argv[3]
    
    try:
        with open("soc_deps.yml", 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
            
        targets_dict = config.get("targets", {})
        
        # Desvio para a estrutura assimétrica:
        # Se for do core, desce um nível a mais. Se não, busca direto na raiz.
        if arch in ['single_cycle', 'multi_cycle']:
            target_data = targets_dict.get("core", {}).get(arch, {}).get(target, {})
        else:
            target_data = targets_dict.get(arch, {}).get(target, {})
        
        if isinstance(target_data, dict):
            value = target_data.get(key, "")
            if value:
                print(value)
    except Exception:
        pass

if __name__ == "__main__":
    main()