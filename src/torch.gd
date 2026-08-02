extends Node3D
class_name TorchTool

## Torch has no activated gameplay action. Its light and flame are persistent
## scene children and are therefore visible whenever Player selects this tool,
## including on remote player proxies.
@export var tool_owner := ""
