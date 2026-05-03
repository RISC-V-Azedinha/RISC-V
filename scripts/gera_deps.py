import os
import re
import yaml

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
                parts = filepath.split('/')
                
                # CORREÇÃO AQUI: Refletindo a nova estrutura de pastas
                # Ex: rtl/core/single_cycle/alu.vhd -> arch_identifier = 'single_cycle'
                if len(parts) > 2 and parts[1] == 'core':
                    arch_identifier = parts[2]
                elif len(parts) > 1:
                    arch_identifier = parts[1] # perips ou soc
                else:
                    arch_identifier = 'common'
                
                provides, depends = parse_vhdl_dependencies(filepath)
                for p in provides:
                    db[(arch_identifier, p)] = {'file': filepath, 'depends': depends}
    return db

def resolve_dependencies(arch, module_name, rtl_db, resolved=None, visiting=None):
    """Resolve dependências recursivamente para garantir a ordem de compilação (Bottom-Up)."""
    if resolved is None: resolved = []
    if visiting is None: visiting = set()

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
    manifest = {'targets': {'core': {'single_cycle': {}, 'multi_cycle': {}}, 'perips': {}, 'soc': {}}}

    print("Gerando manifesto de build...")
    
    for root, _, files in os.walk(SIM_DIR):
        for file in files:
            if file.startswith('test_') and file.endswith('.py'):
                if 'include' in root.split('/'):
                    continue

                filepath = os.path.join(root, file).replace('\\', '/')
                parts = filepath.split('/')
                if len(parts) < 3: continue
                
                domain = parts[1] # 'core', 'perips' ou 'soc'
                
                if domain == 'core':
                    subdomain = parts[2]
                    arch_identifier = subdomain
                else:
                    subdomain = None
                    arch_identifier = domain

                target_name = file.replace('test_', '').replace('.py', '')
                
                # 1. Resolve os VHDLs na ordem correta
                vhdl_files = resolve_dependencies(arch_identifier, target_name, rtl_db)
                
                # 2. Tratamento do Wrapper
                wrapper_name = f"{target_name}_wrapper"
                wrapper_node = rtl_db.get((arch_identifier, wrapper_name))
                
                # 3. Adiciona arquivos Python
                test_utils_path = f"{SIM_DIR}/{domain}/{subdomain}/include/test_utils.py" if subdomain else f"{SIM_DIR}/{domain}/include/test_utils.py"
                python_files = [test_utils_path, filepath] if os.path.exists(test_utils_path) else [filepath]

                # 4. Formatação final (Se tiver wrapper cria dicionário, senão, lista)
                if wrapper_node:
                    wrapper_file = wrapper_node['file']
                    target_data = {
                        'deps': vhdl_files + [wrapper_file] + python_files,
                        'wrapper_top': wrapper_name,
                        'wrapper_src': wrapper_file
                    }
                else:
                    target_data = vhdl_files + python_files

                # 5. Salva no dicionário final
                if domain == 'core':
                    manifest['targets']['core'][subdomain][target_name] = target_data
                else:
                    if domain not in manifest['targets']:
                        manifest['targets'][domain] = {}
                    manifest['targets'][domain][target_name] = target_data

    with open(OUTPUT_YAML, 'w', encoding='utf-8') as f:
        yaml.dump(manifest, f, default_flow_style=False, sort_keys=False)
        
    print(f"Sucesso! Manifesto formatado e salvo em '{OUTPUT_YAML}'.")

if __name__ == '__main__':
    main()