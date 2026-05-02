#!/usr/bin/env python3
import yaml
import sys

def main():
    if len(sys.argv) < 4:
        return
    
    # Agora recebe a arquitetura também
    arch, target, key = sys.argv[1], sys.argv[2], sys.argv[3]
    
    try:
        with open("soc_deps.yml", 'r') as f:
            config = yaml.safe_load(f)
            
        # Busca no nível da arquitetura e depois no alvo
        target_data = config.get("targets", {}).get(arch, {}).get(target, {})
        
        if isinstance(target_data, dict):
            value = target_data.get(key, "")
            if value:
                print(value)
    except Exception:
        pass

if __name__ == "__main__":
    main()