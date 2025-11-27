import os
import re

# Configuration
envoy_config_path = 'configs/envoy.yaml'
output_dir = 'configs/routes'

if not os.path.exists(output_dir):
    os.makedirs(output_dir)

with open(envoy_config_path, 'r') as f:
    lines = f.readlines()

# Helpers
def get_indent(line):
    return len(line) - len(line.lstrip())

# Step 1: Parse Clusters
clusters = {}
in_clusters_section = False
current_cluster_name = None
current_cluster_lines = []
clusters_indent = 0

cluster_name_regex = re.compile(r'^\s*-\s*name:\s*(\S+)')

for i, line in enumerate(lines):
    stripped = line.strip()
    indent = get_indent(line)
    
    # Detect start of clusters section
    if stripped.startswith('clusters:'):
        in_clusters_section = True
        clusters_indent = indent
        continue
    
    if in_clusters_section:
        # Check if we are still in clusters section
        # The contents of clusters usually start with "- name:" which might have same indent as "clusters:"
        # So we only exit if indent is strictly less than clusters_indent
        # Update: If indent drops, we exit, even if it is a comment (it belongs to next section)
        if indent < clusters_indent and stripped:
            in_clusters_section = False
            # Save last cluster
            if current_cluster_name:
                clusters[current_cluster_name] = current_cluster_lines
            current_cluster_name = None
            current_cluster_lines = []
            continue
        
        # Check for new cluster definition "- name: ..."
        match = cluster_name_regex.match(line)
        if match:
            # Save previous cluster
            if current_cluster_name:
                clusters[current_cluster_name] = current_cluster_lines
            
            current_cluster_name = match.group(1)
            current_cluster_lines = [line]
        else:
            if current_cluster_name:
                current_cluster_lines.append(line)

# Save the very last cluster if file ended
if current_cluster_name:
    clusters[current_cluster_name] = current_cluster_lines

# Step 2: Parse Routes and Generate Files
in_routes_section = False
current_route_lines = []
route_count = 0
routes_indent = 0

match_regex = re.compile(r'^\s*-\s*match:')
cluster_ref_regex = re.compile(r'cluster:\s*"?([\w-]+)"?')
prefix_regex = re.compile(r'prefix:\s*"([^"]+)"')

processed_routes = []

for i, line in enumerate(lines):
    stripped = line.strip()
    indent = get_indent(line)
    
    # Detect start of routes section (under virtual_hosts)
    # This is a bit loose, assuming only one main routes section we care about
    if stripped.startswith('routes:'):
        # We assume this is the routes section if it's indented
        in_routes_section = True
        routes_indent = indent
        continue

    if in_routes_section:
        # Check if we left routes section
        # Similarly, list items might align with "routes:"
        # Update: If indent drops below start of routes block, we are done.
        if indent < routes_indent and stripped:
            in_routes_section = False
            if current_route_lines:
                processed_routes.append(current_route_lines)
            current_route_lines = []
            continue
        
        match = match_regex.match(line)
        if match:
            if current_route_lines:
                processed_routes.append(current_route_lines)
            current_route_lines = [line]
        else:
            if current_route_lines:
                current_route_lines.append(line)

if current_route_lines:
    processed_routes.append(current_route_lines)

# Step 3: Write files
route_count = 0
for route_lines in processed_routes:
    # Filter out comments for cluster detection
    clean_route_text = "\n".join([l for l in route_lines if not l.strip().startswith('#')])
    route_text = "".join(route_lines)
    
    # Find cluster reference
    cluster_match = cluster_ref_regex.search(clean_route_text)
    cluster_name = cluster_match.group(1) if cluster_match else None
    
    # Find prefix for naming
    prefix_match = prefix_regex.search(route_text)
    if prefix_match:
        name_part = prefix_match.group(1).strip('/').replace('/', '_').replace('-', '_')
    else:
        route_count += 1
        name_part = f"route_{route_count}"
        
    route_count += 1
    filename = f"{route_count:02d}_{name_part}.yaml"
    filepath = os.path.join(output_dir, filename)
    
    content = "routes:\n"
    # Re-indent route lines to look nice under 'routes:'? 
    # The lines already have indentation from the original file (e.g. 14 spaces).
    # If we want to make it valid standalone YAML, we might want to adjust indent.
    # But for simple concatenation, keeping original indent might be easier if we strip later.
    # However, to make the snippet valid YAML structure as requested (routes: ..., clusters: ...), we should probably normalize indentation.
    # Let's try to normalize to standard 2-space indent.
    
    # Calculate base indent of the route block (indent of the first line "- match:")
    if route_lines:
        base_indent = get_indent(route_lines[0])
        normalized_route = []
        for rl in route_lines:
            # remove base_indent
            if len(rl.strip()) > 0:
                normalized_route.append("  " + rl[base_indent:]) # Add 2 spaces indent under 'routes:'
            else:
                normalized_route.append(rl)
        route_text = "".join(normalized_route)
    
    content += route_text
    
    if cluster_name and cluster_name in clusters:
        content += "\nclusters:\n"
        cluster_lines = clusters[cluster_name]
        # Normalize cluster indent
        if cluster_lines:
            base_cluster_indent = get_indent(cluster_lines[0])
            for cl in cluster_lines:
                 if len(cl.strip()) > 0:
                     content += "  " + cl[base_cluster_indent:]
                 else:
                     content += cl
    else:
        if cluster_name:
            print(f"Warning: Cluster '{cluster_name}' referenced in {filename} not found in clusters definition.")
    
    with open(filepath, 'w') as out:
        out.write(content)
    print(f"Created {filename}")
