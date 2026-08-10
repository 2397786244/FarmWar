extends Node3D
class_name CashPickupVisual

## 该值由通用 PickupItem 在生成现金掉落物视觉时写入。
## 真正的拾取结算仍以服务端 PickupItem.item_data 为准。
@export_range(0, 1000000, 1)
var money_value: int = 0


func set_money_value(value: int) -> void:
	money_value = maxi(0, value)
