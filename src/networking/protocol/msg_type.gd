class_name MsgType
extends RefCounted
## Message type ids (first byte of every packet) and the protocol version
## (architecture.md §8.2). Bump PROTOCOL_VERSION on any layout change.

const PROTOCOL_VERSION: int = 9  # v9: hero pick in Hello; v8: M1 hero index per entity, Wardling tier (v7: E14 Plant/Breach task state in the hardpoint block; v6: E13/E15)

const HELLO: int = 1        ## C->S ch0: u16 protocol_version
const WELCOME: int = 2      ## S->C ch0: u16 own net id, u32 server tick, u16 tick rate
const REJECT: int = 3       ## S->C ch0: u8 reason
const INPUT_BATCH: int = 4  ## C->S ch3: u32 ack tick, u8 count, count x InputCommand
const SNAPSHOT: int = 5     ## S->C ch2: see SnapshotCodec
const EVENT: int = 6        ## S->C ch1: see EventCodec (hit confirms, kills)

const REJECT_PROTOCOL_MISMATCH: int = 1
const REJECT_SERVER_FULL: int = 2
