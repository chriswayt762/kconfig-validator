import os
import re

# Path to the kernel source
kconfig_path = "/home/chris/work/linux-6.12.1"

# List to store metadata for all config options
metadata = []

# Function to parse each Kconfig file
def parse_kconfig_file(file_path):
    with open(file_path, 'r') as f:
        content = f.read()
        
        # Find all config options, help text, and dependencies
        config_matches = re.findall(r"config\s+(\S+)(.*?)\n\n", content, re.DOTALL)
        for option, metadata_block in config_matches:
            option_metadata = {
                "option": option,
                "help_text": None,
                "depends_on": [],
                "selects": []
            }

            # Extract help text
            help_match = re.search(r"help\s+(.*)", metadata_block)
            if help_match:
                option_metadata["help_text"] = help_match.group(1).strip()

            # Extract dependencies
            depends_match = re.findall(r"depends on\s+(\S+)", metadata_block)
            option_metadata["depends_on"] = depends_match

            # Extract 'select' dependencies
            select_match = re.findall(r"select\s+(\S+)", metadata_block)
            option_metadata["selects"] = select_match

            metadata.append(option_metadata)

# Walk through all Kconfig files and parse them
for root, dirs, files in os.walk(kconfig_path):
    for file in files:
        if file == "Kconfig":
            parse_kconfig_file(os.path.join(root, file))

# Save metadata to a text file
output_path = "/home/chris/work/kconfig-metadata.txt"
with open(output_path, 'w') as f:
    for entry in metadata:
        f.write(f"Option: {entry['option']}\n")
        f.write(f"Help Text: {entry['help_text']}\n")
        f.write(f"Depends on: {', '.join(entry['depends_on'])}\n")
        f.write(f"Selects: {', '.join(entry['selects'])}\n")
        f.write("\n")

print(f"Metadata saved to {output_path}")
