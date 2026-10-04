class_name SkillStatusBits
extends RefCounted
## Replicated visual status bits owned by SkillEntities (heroes.md §3.6 Silence /
## Blind, Sable's stealth). They share the u16 EntityState.status with
## StatusComponent.BIT_* (bits 0-8) and start above them.

const STEALTH: int = 512
const SILENCE: int = 1024
const BLIND: int = 2048
