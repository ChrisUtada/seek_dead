class_name SymbolWeight
extends Resource

# 武器持有的「符号 + 权重」关联。直接引用 SymbolData（资源化、零注册表）。
# 武器用 Array[SymbolWeight] 持有多个符号及其各自权重，保留原多符号转轮手感。

@export var symbol: SymbolData
@export var weight: float = 1.0
