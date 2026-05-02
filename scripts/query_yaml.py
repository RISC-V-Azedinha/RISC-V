#!/usr/bin/env python3
import yaml
import sys

def main():
    if len(sys.argv) < 3:
        return
    
    target, key = sys.argv[1], sys.argv[2]
    
    try:
        with open("soc_deps.yml", 'r') as f:
            config = yaml.safe_load(f)
            
        target_data = config.get("targets", {}).get(target, {})
        
        # Se for um dicionário (tem wrapper), pega a chave solicitada
        if isinstance(target_data, dict):
            value = target_data.get(key, "")
            if value:
                print(value)
    except Exception:
        pass

if __name__ == "__main__":
    main()