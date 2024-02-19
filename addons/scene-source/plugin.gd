@tool
extends EditorPlugin

var inspectors = []


func _enter_tree():
	inspectors.append(SceneSourceInspector.new())
	for ins in inspectors:
		add_inspector_plugin(ins)


func _exit_tree():
	for ins in inspectors:
		remove_inspector_plugin(ins)


class SceneSourceInspector extends EditorInspectorPlugin:
	func _can_handle(object):
		return object is SceneSource

	func _parse_begin(object):
		var refresh_btn = Button.new()
		refresh_btn.text = "Reload Properties"
		refresh_btn.pressed.connect(func():
			object._reload_properties()
		)
		add_custom_control(refresh_btn)
