class_name Enums
extends RefCounted
## 全局常量与小型工具。规则层不依赖任何 UI / 场景。

const ZONE_DECK := "deck"
const ZONE_HAND := "hand"
const ZONE_BOARD := "board"
const ZONE_GRAVE := "grave"

const SIDE_PLAYER := 0
const SIDE_ENEMY := 1

const PHASE_MULLIGAN := "mulligan"
const PHASE_PLAYING := "playing"
const PHASE_OVER := "over"

## 英雄用负数 id 表示：玩家英雄 -1，对手英雄 -2。随从实例 id 从 1 开始。
static func hero_id(owner: int) -> int:
	return -1 - owner


static func is_hero(target_id: int) -> bool:
	return target_id < 0


static func hero_owner(target_id: int) -> int:
	return -1 - target_id
