import os
import re

# Define the source file and output directory
envoy_config_path = 'configs/envoy.yaml'
routes_dir = 'configs/routes'

# Create the output directory if it doesn't exist
if not os.path.exists(routes_dir):
    os.makedirs(routes_dir)

# Read the envoy.yaml file
with open(envoy_config_path, 'r') as f:
    lines = f.readlines()

# Initialize variables
routes_content = []
in_routes_section = False
route_indent = 0
current_route = []
route_count = 0

# Regex to detect the start of a route match
# Assuming standard indentation from the provided file: "              - match:"
match_pattern = re.compile(r'^(\s+)- match:')

for line in lines:
    # Check if we are entering the routes section of multi_service_host
    if 'virtual_hosts:' in line:
        pass # Just tracking context
    if '- name: multi_service_host' in line:
        pass
    if 'routes:' in line and not in_routes_section:
        # We found the routes section. 
        # Note: We need to be careful if there are other routes sections, but based on the file, there's only one relevant one.
        in_routes_section = True
        continue
    
    if in_routes_section:
        # Check if we hit the end of the routes section (dedent or next section)
        # The routes are indented. If we hit something with less indentation that is not a comment/empty line, we are done.
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            if current_route:
                current_route.append(line)
            continue
            
        indent = len(line) - len(line.lstrip())
        
        # Check for new route match
        match = match_pattern.match(line)
        if match:
            # If we have a current route accumulating, save it
            if current_route:
                route_count += 1
                # Determine filename based on content (prefix)
                route_text = "".join(current_route)
                prefix_match = re.search(r'prefix: "([^"]+)"', route_text)
                if prefix_match:
                    name = prefix_match.group(1).strip('/').replace('/', '_').replace('-', '_')
                else:
                    name = f"route_{route_count}"
                
                filename = f"{route_count:02d}_{name}.yaml"
                with open(os.path.join(routes_dir, filename), 'w') as out:
                    out.write(route_text)
                print(f"Created {filename}")
                current_route = []
            
            current_route.append(line)
        else:
            # If indent is significantly less than the match indent, we might be out of routes
            # The match line had some indent. Let's assume indent < 14 means we are out (based on visual inspection of file)
            # "              - match:" is 14 spaces.
            if indent < 14:
                in_routes_section = False
                # Process the last route if exists
                if current_route:
                    route_count += 1
                    route_text = "".join(current_route)
                    prefix_match = re.search(r'prefix: "([^"]+)"', route_text)
                    if prefix_match:
                        name = prefix_match.group(1).strip('/').replace('/', '_').replace('-', '_')
                    else:
                        name = f"route_{route_count}"
                    
                    filename = f"{route_count:02d}_{name}.yaml"
                    with open(os.path.join(routes_dir, filename), 'w') as out:
                        out.write(route_text)
                    print(f"Created {filename}")
                    current_route = []
            else:
                current_route.append(line)

# Handle the very last route if file ended inside routes section (unlikely for valid yaml but good for safety)
if in_routes_section and current_route:
    route_count += 1
    route_text = "".join(current_route)
    prefix_match = re.search(r'prefix: "([^"]+)"', route_text)
    if prefix_match:
        name = prefix_match.group(1).strip('/').replace('/', '_').replace('-', '_')
    else:
        name = f"route_{route_count}"
    
    filename = f"{route_count:02d}_{name}.yaml"
    with open(os.path.join(routes_dir, filename), 'w') as out:
        out.write(route_text)
    print(f"Created {filename}")
