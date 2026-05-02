import os
import re
import yaml

# Configurações de diretórios
RTL_DIR = 'rtl'
SIM_DIR = 'sim'
OUTPUT_YAML = 'soc_deps.yml'

def parse_vhdl_dependencies(filepath):
    """Extrai entidades/pacotes providos e dependências de um arquivo VHDL."""
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
        content = re.sub(r'--.*', '', content) # Remove comentários
        
        provides = re.findall(r'(?i)^\s*(?:entity|package)\s+(\w+)\s+is', content, re.MULTILINE)
        
        depends = re.findall(r'(?i)use\s+work\.(\w+)', content)
        depends.extend(re.findall(r'(?i):\s*entity\s+work\.(\w+)', content))
        depends.extend(re.findall(r'(?i)^\s*component\s+(\w+)\s+(?:is)?', content, re.MULTILINE))

    return [p.lower() for p in provides], list(set(d.lower() for d in depends))

def scan_rtl():
    """Varre o diretório RTL e cria um banco de dados de módulos."""
    db = {}
    for root, _, files in os.walk(RTL_DIR):
        for file in files:
            if file.endswith('.vhd'):
                filepath = os.path.join(root, file).replace('\\', '/')
                # Infere a arquitetura pela pasta (ex: rtl/single_cycle/...)
                parts = filepath.split('/')
                arch = parts[1] if len(parts) > 1 else 'common'
                
                provides, depends = parse_vhdl_dependencies(filepath)
                for p in provides:
                    db[(arch, p)] = {'file': filepath, 'depends': depends}
    return db

def resolve_dependencies(arch, module_name, rtl_db, resolved=None, visiting=None):
    """Resolve dependências recursivamente para garantir a ordem de compilação (Bottom-Up)."""
    if resolved is None: resolved = []
    if visiting is None: visiting = set()

    # Tenta achar o módulo na arquitetura específica, ou no 'common' se for compartilhado
    node = rtl_db.get((arch, module_name)) or rtl_db.get(('common', module_name))
    
    if not node or module_name in resolved:
        return resolved

    visiting.add(module_name)
    
    for dep in node['depends']:
        if dep not in visiting and dep not in resolved:
            resolve_dependencies(arch, dep, rtl_db, resolved, visiting)
            
    visiting.remove(module_name)
    if node['file'] not in resolved:
        resolved.append(node['file'])
        
    return resolved

def main():
    rtl_db = scan_rtl()
    manifest = {'targets': {}}

    print("Gerando manifesto de build...")
    
    # Varre a pasta de simulação para descobrir os targets
    for root, _, files in os.walk(SIM_DIR):
        for file in files:
            if file.startswith('test_') and file.endswith('.py'):
                # Exemplo: sim/single_cycle/unit/test_alu.py
                filepath = os.path.join(root, file).replace('\\', '/')
                parts = filepath.split('/')
                if len(parts) < 3: continue
                
                arch = parts[1] # single_cycle ou multi_cycle
                target_name = file.replace('test_', '').replace('.py', '')
                
                if arch not in manifest['targets']:
                    manifest['targets'][arch] = {}

                # 1. Resolve dependências VHDL na ordem correta
                vhdl_files = resolve_dependencies(arch, target_name, rtl_db)
                
                # 2. Verifica se existe um wrapper
                wrapper_name = f"{target_name}_wrapper"
                wrapper_node = rtl_db.get((arch, wrapper_name))
                
                # 3. Adiciona os scripts Python (test_utils e o próprio teste)
                # Ajuste o caminho do test_utils conforme a estrutura real do seu repositório
                test_utils_path = f"{SIM_DIR}/{arch}/include/test_utils.py"
                python_files = []
                if os.path.exists(test_utils_path):
                    python_files.append(test_utils_path)
                python_files.append(filepath)

                # 4. Monta a estrutura do YAML
                if wrapper_node:
                    wrapper_file = wrapper_node['file']
                    deps_list = vhdl_files + [wrapper_file] + python_files
                    manifest['targets'][arch][target_name] = {
                        'deps': deps_list,
                        'wrapper_top': wrapper_name,
                        'wrapper_src': wrapper_file
                    }
                else:
                    manifest['targets'][arch][target_name] = vhdl_files + python_files

    # Adicionando o processor_top manualmente ou por regra caso ele fuja do padrão de testes unitários
    # (Como o processor_top tem um script de e2e, a lógica acima pode ser adaptada para cobri-lo)

    with open(OUTPUT_YAML, 'w', encoding='utf-8') as f:
        yaml.dump(manifest, f, default_flow_style=False, sort_keys=False)
        
    print(f"Sucesso! Manifesto formatado e salvo em '{OUTPUT_YAML}'.")

if __name__ == '__main__':
    main()