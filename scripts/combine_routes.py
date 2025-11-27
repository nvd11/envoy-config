import os
import sys

# Configuration
envoy_template_path = 'configs/envoy.yaml'
routes_dir = 'configs/routes'
output_path = 'configs/envoy_generated.yaml'

def get_indent(line):
    return len(line) - len(line.lstrip())

def main():
    if not os.path.exists(routes_dir):
        print(f"Error: {routes_dir} does not exist.")
        sys.exit(1)

    # Read template
    with open(envoy_template_path, 'r') as f:
        template_lines = f.readlines()

    # Read all route files
    route_files = sorted([f for f in os.listdir(routes_dir) if f.endswith('.yaml')])
    
    all_routes = []
    all_clusters = []

    for r_file in route_files:
        path = os.path.join(routes_dir, r_file)
        with open(path, 'r') as f:
            lines = f.readlines()
        
        current_section = None
        current_routes = []
        current_clusters = []
        
        for line in lines:
            stripped = line.strip()
            if stripped.startswith('routes:'):
                current_section = 'routes'
                continue
            elif stripped.startswith('clusters:'):
                current_section = 'clusters'
                continue
            
            if current_section == 'routes':
                # Skip empty lines or just comments at the start if necessary?
                # Actually, the file content we generated has indentation already relative to "routes:" (2 spaces)
                # We need to preserve content lines.
                if line.strip():
                    current_routes.append(line)
            elif current_section == 'clusters':
                if line.strip():
                    current_clusters.append(line)
        
        all_routes.extend(current_routes)
        all_clusters.extend(current_clusters)

    # Inject into template
    final_lines = []
    
    # We need to determine the base indent for injection from the template context
    # But usually we just follow the indentation of the placeholder line.
    
    for line in template_lines:
        if '# INJECT_ROUTES_HERE' in line:
            indent = get_indent(line)
            prefix = ' ' * indent
            # In our generated files, lines under "routes:" have 2 spaces indent.
            # In envoy.yaml, "routes:" is at some indent, and "- match" should be at that indent.
            # Wait, in the original file:
            #               routes:
            #               - match:
            # The indent of "- match" is SAME as "routes:"? No, usually not in valid YAML but here it seems so or slightly different.
            # Let's check the generated files.
            # Generated file:
            # routes:
            #   - match: ...
            # The "- match" has 2 spaces indent.
            
            # In template:
            #               routes:
            #               # INJECT_ROUTES_HERE
            # The placeholder has same indent as "routes:" + 2 (usually) or just aligned.
            # Let's assume the placeholder indentation is the correct indentation for the list items.
            
            # Since our extracted lines already have 2 spaces relative to "routes:", 
            # and if we assume the placeholder is where the list item starts.
            # But wait, in the generated file `routes:` is at root. 
            # In extracted list `  - match:`, there are 2 spaces.
            
            # If the placeholder is at 14 spaces.
            # And we want the result to be:
            #               - match: ...
            # Then we need to add 12 spaces to our `  - match:` line? No.
            # If `  - match:` (2 spaces) needs to become 14 spaces. We add 12 spaces.
            
            # Let's adjust based on the difference.
            # But the extracted lines might have varying indent.
            # We should probably strip the common indent from extracted lines and add the template indent.
            
            # Simplified approach:
            # The lines in `all_routes` start with 2 spaces (because of how we generated them).
            # The placeholder line has `indent` spaces.
            # We want the content to start at `indent`.
            # So we strip 2 spaces from start of `all_routes` lines (if possible) and add `indent` spaces.
            
            for r_line in all_routes:
                # Remove first 2 spaces if present
                if r_line.startswith('  '):
                    content = r_line[2:]
                else:
                    content = r_line.lstrip() # Fallback
                
                final_lines.append((' ' * indent) + content)
                
        elif '# INJECT_CLUSTERS_HERE' in line:
            indent = get_indent(line)
            # Similar logic for clusters
            for c_line in all_clusters:
                if c_line.startswith('  '):
                    content = c_line[2:]
                else:
                    content = c_line.lstrip()
                final_lines.append((' ' * indent) + content)
        else:
            final_lines.append(line)

    with open(output_path, 'w') as f:
        f.writelines(final_lines)
    
    print(f"Generated {output_path}")

if __name__ == "__main__":
    main()
