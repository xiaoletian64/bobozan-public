class_name SkinActivationProvider
extends RefCounted
# Future backend boundary. No URL, credentials, unsigned-grant importer or fake activation.
# Replace this provider with authenticated account sync and verified entitlements.
# Keep server ownership separate from SkinProfile's offline check-in days.
func is_available() -> bool:
	return false
func sync_entitlements() -> Dictionary:
	return {"ok":false,"code":"not_configured","message":"服务器激活暂未开放"}
