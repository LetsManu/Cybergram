class_name MsgType
extends RefCounted
## Message type ids (first byte of every packet) and the protocol version
## (architecture.md §8.2). Bump PROTOCOL_VERSION on any layout change.

const PROTOCOL_VERSION: int = 16  # v16: W16-NET quantised snapshot records, delta against the acked snapshot (keyed sections, change masks, stale bits), match clock outside the match blob, byte budget; v15: AccountCodec launch token (OP_LAUNCH_TOKEN / OP_REDEEM), crash report chunks, party ops, E_RATE; v14: per-hero Fork/Mastery state (1 B base-6 per entity), GameEvent SKILL_CAST (id 6) for remote casts; v13: Fork choice in ACTION_LEARN arg, hero bolts in the snapshot bolts block, PLAYER_STAT match-end events; v12: server accounts (ACCOUNT_REQ/RESULT, DTLS), identity from the session, LOBBY_JOIN without profile, presence via FRIENDS; v11: profiles (name/emblem/accent/id) in the lobby, chat, team switch, presence, player names in the match; v10: lobby + slot token in Hello; v9: hero pick in Hello; v8: M1 hero index per entity, Wardling tier (v7: E14 Plant/Breach task state in the hardpoint block; v6: E13/E15)

const HELLO: int = 1        ## C->S ch0: u16 protocol_version
const WELCOME: int = 2      ## S->C ch0: u16 own net id, u32 server tick, u16 tick rate
const REJECT: int = 3       ## S->C ch0: u8 reason
const INPUT_BATCH: int = 4  ## C->S ch3: u32 ack tick, u8 count, count x InputCommand
const SNAPSHOT: int = 5     ## S->C ch2: see SnapshotCodec
const EVENT: int = 6        ## S->C ch1: see EventCodec (hit confirms, kills)
## Lobby (ch0, see LobbyCodec for the exact layouts). The online server runs a
## lobby before each match. str8 = u8 byte length + UTF-8 bytes; id = 16 bytes.
const LOBBY_JOIN: int = 20   ## C->S: u16 protocol_version, u16 hero, party id (zeros = none); identity = the logged-in session
const LOBBY_PICK: int = 21   ## C->S: u16 hero index, u8 ready
const LOBBY_STATE: int = 22  ## S->C: u8 phase, u8 countdown s, u8 your slot, u8 team size, u8 n, n x slot (team, hero, flags, emblem, accent, id, str8 name)
const LOBBY_START: int = 23  ## S->C: u16 slot token (0 = join the running match), u8 team, u16 hero index
const LOBBY_CHAT_SEND: int = 24  ## C->S: str8 text (<= 240 bytes)
const LOBBY_CHAT: int = 25       ## S->C: u8 kind, u8 system code, u8 team, u8 accent, id, str8 name, str8 text
const LOBBY_TEAM: int = 26       ## C->S: u8 wanted team
## 27, 28: v11 PRESENCE_QUERY / PRESENCE, replaced by AccountCodec.OP_FRIENDS in v12 (do not reuse).
## Match: display names of the human players (S->C ch0).
const PLAYER_NAMES: int = 29     ## S->C: u8 n, n x (u16 net id, u8 accent, str8 name)
## Accounts (v12, ch0, see AccountCodec). Passwords only on a DTLS link.
const ACCOUNT_REQ: int = 30      ## C->S: u8 op, op fields
const ACCOUNT_RESULT: int = 31   ## S->C: u8 op, u8 code, op fields when code == OK

const REJECT_PROTOCOL_MISMATCH: int = 1
const REJECT_SERVER_FULL: int = 2
## v11: another player already holds this profile id (different key).
const REJECT_ID_TAKEN: int = 3
## v11: the profile in LOBBY_JOIN is invalid (name / emblem / accent / id).
const REJECT_BAD_PROFILE: int = 4
## v12: LOBBY_JOIN before a login / guest session on this connection.
const REJECT_NOT_LOGGED_IN: int = 5
