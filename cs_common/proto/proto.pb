
�
base/scene.protobase"e
PosInfo	
v (
x (
y (
z (
face_x (
face_y (
face_z ("^
	PlayerAoi#
block (2.base.PlayerAoiBlock
pos_info (2
pid (
PlayerAoiBlock
mask (
X
base/role.protobase"

SimpleRole
pid (
Role
account (	
pid (
h
client/login.proto"#
C2GSLoginAccount
account (	"-

account (	
pid (
?
client/other.proto"

	C2GSGMCmd
cmd (	
u
client/scene.protobase/scene.proto"M
C2GSSyncPos
scene_id (
eid (
pos_info (2
�
server/login.protobase/role.proto"
	GS2CHello
time (
GS2CLoginError
pid (
errcode (
GS2CLoginAccount
account (	#
	role_list (2.base.SimpleRole")

role (2
.base.Role
3
server/other.proto"

time (
�
server/scene.protobase/scene.proto"1

scene_id (
map_id (
GS2CEnterScene
scene_id (
eid (
pos_info (2
GS2CEnterAoi
scene_id (
eid (
type (

aoi_player (2.base.PlayerAoi"-
GS2CLeaveAoi
scene_id (
eid (
GS2CSyncAoi
scene_id (
eid (
block_player (2.base.PlayerAoiBlock"M
GS2CSyncPos
scene_id (
eid (
pos_info (2