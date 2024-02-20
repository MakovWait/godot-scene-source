@tool
class_name SceneSource
extends Resource


@export var _origin_scene: PackedScene:
	set(value):
		_origin_scene = value
		if Engine.is_editor_hint():
			_overrides = _parse_origin_scene()
			notify_property_list_changed()


var _overrides = _OverriddenProperties.new()
var _deserialized = {}


func instantiate() -> Node:
	var node = _origin_scene.instantiate()
	for name in _deserialized.keys():
		node.set(name, _deserialized[name])
	return node


func _get(property: StringName):
	if not Engine.is_editor_hint(): return null
	var value = _overrides\
		.named(property)\
		.map(func(x: _OverriddenProperty): return x.value())\
		.unwrap_or(null)
	return value


func _set(property: StringName, value: Variant) -> bool:
	if Engine.is_editor_hint():
		_overrides\
			.named(property)\
			.inspect(func(x: _OverriddenProperty):
				x.value_set(value)\
			)
	else:
		_deserialized[property] = value
	return true


func _property_can_revert(property) -> bool:
	if not Engine.is_editor_hint(): return false
	return _overrides\
		.named(property)\
		.map(func(x: _OverriddenProperty):
			return x.has_default()\
		).unwrap_or(false)


func _property_get_revert(property) -> Variant:
	if not Engine.is_editor_hint(): return null
	return _overrides\
		.named(property)\
		.map(func(x: _OverriddenProperty):
			return x.default()\
		).unwrap_or(null)


func _get_property_list():
	if not Engine.is_editor_hint(): return []
	return _overrides.all().map(func(x: _OverriddenProperty): return x.to_gd_property_schema())


func _reload_properties():
	if not Engine.is_editor_hint(): return
	var current = _overrides
	_overrides = _parse_origin_scene()
	for prop in _overrides.all():
		current.named(prop.name()).inspect(func(x):
			prop.value_set(x.value())
		)
	notify_property_list_changed()


func _parse_origin_scene() -> _OverriddenProperties:
	var result: Array[_OverriddenProperty]
	var origin_state = _Opt.new(_origin_scene).map(_SceneStateSmart.from_packed_scene)
	var scene_properties = origin_state.map(func(state: _SceneStateSmart):
		var scene_root = state.nodes().root()
		return scene_root.node_script().map(func(script: Script):
			var scene_root_script = _ScriptSmart.new(script)
			return scene_root_script.props().all().map(func(script_prop: _ScriptPropertySmart):
				var overriden_prop = _OverriddenProperty.new(
					script_prop.to_gd_property(),
					scene_root.props().named(script_prop.name())\
						.map(func(scene_prop: _SceneNodeProperty):
							return scene_prop.value()\
						)\
						.instead_else(_Opt.lazy(script_prop.default_value))
						.unwrap_or(null)
				)
				return overriden_prop
			)
		).unwrap_or([])
	).unwrap_or([])
	result.append_array(scene_properties)
	return _OverriddenProperties.new(result)


class _OverriddenProperties:
	var _props: Array[_OverriddenProperty]
	
	func _init(props: Array[_OverriddenProperty] = []):
		_props = props
	
	func all() -> Array[_OverriddenProperty]:
		return _props
	
	func named(name: StringName) -> _Opt:
		for prop in _props:
			if prop.name() == name:
				return _Opt.new(prop)
		return _Opt.new()


class _OverriddenProperty:
	var _raw_property: Dictionary
	var _default_value: Variant
	var _value: Variant
	
	func _init(raw: Dictionary, default_value: Variant):
		_raw_property = raw
		_value = default_value
		_default_value = default_value
	
	func name() -> StringName:
		return _raw_property['name']
	
	func value() -> Variant:
		return _value
	
	func value_set(new_value: Variant):
		_value = new_value
	
	func has_default() -> bool:
		return true
	
	func default() -> Variant:
		return _default_value
	
	func to_gd_property_schema() -> Dictionary:
		var schema = _raw_property
		if default() == value():
			schema = _raw_property.duplicate()
			schema['usage'] = schema['usage'] & ~PROPERTY_USAGE_STORAGE
		return schema


class _SceneStateSmart:
	var _state: SceneState
	var _nodes: _SceneNodes
	
	func _init(state: SceneState):
		_state = state
		_nodes = _SceneNodes.new(state)
	
	func nodes() -> _SceneNodes:
		return _nodes
	
	static func from_packed_scene(s: PackedScene):
		return _SceneStateSmart.new(s.get_state())


class _ScriptPropertySmart:
	var _script: Script
	var _data: Dictionary
	
	func _init(data: Dictionary, script: Script):
		_data = data
		_script = script
	
	func name() -> StringName:
		return _data['name']
	
	func hint() -> PropertyHint:
		return _data['hint']
	
	func to_gd_property() -> Dictionary:
		return _data
	
	func default_value() -> Variant:
		return _script.get_property_default_value(name())


class _ScriptPropertiesSmart:
	var _props: Array[_ScriptPropertySmart]
	
	func _init(script: Script):
		for raw_property in script.get_script_property_list():
			_props.append(_ScriptPropertySmart.new(raw_property, script))
	
	func all() -> Array[_ScriptPropertySmart]:
		return _props


class _ScriptSmart:
	var _script: Script
	var _props: _ScriptPropertiesSmart
	
	func _init(script: Script):
		_script = script
		_props = _ScriptPropertiesSmart.new(script)
	
	func props() -> _ScriptPropertiesSmart:
		return _props


class _SceneNodes:
	var _data: Array[_SceneNode]
	
	func _init(state: SceneState):
		for idx in state.get_node_count():
			_data.append(_SceneNode.new(idx, state))
	
	func root() -> _SceneNode:
		return _data[0]
	
	func all() -> Array[_SceneNode]:
		return _data


class _SceneNode:
	var _idx: int
	var _state: SceneState
	var _properties: _SceneNodeProperties
	
	func _init(idx: int, state: SceneState):
		self._idx = idx
		self._state = state
		self._properties = _SceneNodeProperties.new(idx, state)
	
	func node_script() -> _Opt:
		var script_prop = props().named("script")
		return script_prop.map(func(x): return x.value())
	
	func name() -> StringName:
		return _state.get_node_name(_idx)
	
	func type() -> StringName:
		return _state.get_node_type(_idx)
	
	func props() -> _SceneNodeProperties:
		return _properties


class _SceneNodeProperties:
	var _data: Array[_SceneNodeProperty]
	
	func _init(node_idx: int, state: SceneState):
		for prop_idx in state.get_node_property_count(node_idx):
			_data.append(_SceneNodeProperty.new(node_idx, prop_idx, state))
	
	func named(prop_name: StringName) -> _Opt:
		for prop in all():
			if prop.name() == prop_name:
				return _Opt.new(prop)
		return _Opt.new()
	
	func all() -> Array[_SceneNodeProperty]:
		return _data


class _SceneNodeProperty:
	var _node_idx: int
	var _prop_idx: int
	var _state: SceneState
	
	func _init(node_idx: int, prop_idx: int, state: SceneState):
		self._node_idx = node_idx 
		self._prop_idx = prop_idx 
		self._state = state
	
	func name() -> StringName:
		return _state.get_node_property_name(_node_idx, _prop_idx)
	
	func value() -> Variant:
		return _state.get_node_property_value(_node_idx, _prop_idx)


class _Opt:
	var _data
	
	func _init(data=null):
		_data = data
	
	func is_null() -> bool:
		return _data == null
	
	func unwrap() -> Variant:
		assert(not is_null())
		return _data

	func unwrap_or(default: Variant) -> Variant:
		if is_null():
			return default
		else:
			return _data

	func unwrap_or_else(default: Callable) -> Variant:
		if is_null():
			return default.call()
		else:
			return _data

	func map(f: Callable) -> _Opt:
		if is_null():
			return _Opt.new()
		return _Opt.new(f.call(_data))
	
	func instead_else(f: Callable) -> _Opt:
		if is_null():
			return f.call()
		return self

	func inspect(f: Callable) -> _Opt:
		if not is_null():
			f.call(_data)
		return self
	
	func _to_string():
		if is_null():
			return "Null[]"
		else:
			return "Opt[%s]" % _data
	
	static func lazy(f: Callable) -> Callable:
		return func(): return _Opt.new(f.call())
