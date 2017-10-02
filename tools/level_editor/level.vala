/*
 * Copyright (c) 2012-2017 Daniele Bartolini and individual contributors.
 * License: https://github.com/dbartolini/crown/blob/master/LICENSE
 */

using GLib;
using Gee;

namespace Crown
{
	/// Manages objects in a level.
	public class Level
	{
		// Project paths
		private string _source_dir;
		private string _toolchain_dir;

		// Engine connections
		private ConsoleClient _client;

		// Data
		private Database _db;
		private Database _prefabs;
		private Gee.HashSet<string> _loaded_prefabs;
		private Gee.ArrayList<Guid?> _selection;

		private uint _num_units;
		private uint _num_sounds;

		// Signals
		public signal void selection_changed(Gee.ArrayList<Guid?> selection);
		public signal void object_editor_name_changed(Guid object_id, string name);

		public Level(Database db, ConsoleClient client, string source_dir, string toolchain_dir)
		{
			// Project paths
			_source_dir = source_dir;
			_toolchain_dir = toolchain_dir;

			// Engine connections
			_client = client;

			// Data
			_db = db;
			_db.undo_redo.connect(undo_redo_action);

			_prefabs = new Database();
			_loaded_prefabs = new Gee.HashSet<string>();
			_selection = new Gee.ArrayList<Guid?>();

			reset();
		}

		/// Resets the level
		public void reset()
		{
			_db.reset();
			_prefabs.reset();
			_loaded_prefabs.clear();

			_selection.clear();
			selection_changed(_selection);

			_num_units = 0;
			_num_sounds = 0;
		}

		/// Loads the level from @a path.
		public void load(string path)
		{
			reset();
			_db.load(path);
		}

		/// Saves the level to @a path.
		public void save(string path)
		{
			_db.save(path);
		}

		/// Loads the empty level template.
		public void load_empty_level()
		{
			load(_toolchain_dir + "/" + "core/editors/levels/empty.level");
		}

		public void spawn_unit(Guid id, string name, Vector3 pos, Quaternion rot, Vector3 scl)
		{
			on_unit_spawned(id, name, pos, rot, scl);
			send_spawn_units(new Guid[] { id });
		}

		public void destroy_objects(Guid[] ids)
		{
			Guid[] units = {};
			Guid[] sounds = {};

			foreach (Guid id in ids)
			{
				if (is_unit(id))
					units += id;
				else if (is_sound(id))
					sounds += id;
			}

			if (units.length > 0)
			{
				_db.add_restore_point((int)ActionType.DESTROY_UNIT, units);
				foreach (Guid id in units)
				{
					_db.remove_from_set(GUID_ZERO, "units", id);
					_db.destroy(id);
				}
			}

			if (sounds.length > 0)
			{
				_db.add_restore_point((int)ActionType.DESTROY_SOUND, sounds);
				foreach (Guid id in sounds)
				{
					_db.remove_from_set(GUID_ZERO, "sounds", id);
					_db.destroy(id);
				}
			}

			send_destroy_objects(ids);
		}

		public void move_selected_objects(Vector3 pos, Quaternion rot, Vector3 scl)
		{
			if (_selection.size == 0)
				return;

			Guid id = _selection.last();
			on_move_objects(new Guid[] { id }, new Vector3[] { pos }, new Quaternion[] { rot }, new Vector3[] { scl });
			send_move_objects(new Guid[] { id }, new Vector3[] { pos }, new Quaternion[] { rot }, new Vector3[] { scl });
		}

		public void duplicate_selected_objects()
		{
			if (_selection.size > 0)
			{
				Guid[] ids = new Guid[_selection.size];
				// FIXME
				{
					Guid?[] tmp = _selection.to_array();
					for (int i = 0; i < tmp.length; ++i)
						ids[i] = tmp[i];
				}
				Guid[] new_ids = new Guid[ids.length];

				for (int i = 0; i < new_ids.length; ++i)
					new_ids[i] = Guid.new_guid();

				duplicate_objects(ids, new_ids);
			}
		}

		public void destroy_selected_objects()
		{
			Guid[] ids = new Guid[_selection.size];
			// FIXME
			{
				Guid?[] tmp = _selection.to_array();
				for (int i = 0; i < tmp.length; ++i)
					ids[i] = tmp[i];
			}
			_selection.clear();

			destroy_objects(ids);
		}

		public void duplicate_objects(Guid[] ids, Guid[] new_ids)
		{
			_db.add_restore_point((int)ActionType.DUPLICATE_OBJECTS, new_ids);
			for (int i = 0; i < ids.length; ++i)
			{
				_db.duplicate(ids[i], new_ids[i]);

				if (is_unit(ids[i]))
				{
					_db.add_to_set(GUID_ZERO, "units", new_ids[i]);
				}
				else if (is_sound(ids[i]))
				{
					_db.add_to_set(GUID_ZERO, "sounds", new_ids[i]);
				}
			}
			send_spawn_objects(new_ids);
		}

		public void on_unit_spawned(Guid id, string name, Vector3 pos, Quaternion rot, Vector3 scl)
		{
			load_prefab(name);

			_db.add_restore_point((int)ActionType.SPAWN_UNIT, new Guid[] { id });
			_db.create(id);
			_db.set_property(id, "editor.name", "unit_%04u".printf(_num_units++));
			_db.set_property(id, "prefab", name);

			Guid transform_id = GUID_ZERO;
			if (has_component(id, "transform", ref transform_id))
			{
				set_component_property(id, transform_id, "data.position", pos);
				set_component_property(id, transform_id, "data.rotation", rot);
				set_component_property(id, transform_id, "data.scale", scl);
				set_component_property(id, transform_id, "type", "transform");
			}
			else
			{
				_db.set_property(id, "position", pos);
				_db.set_property(id, "rotation", rot);
				_db.set_property(id, "scale", scl);
			}
			_db.add_to_set(GUID_ZERO, "units", id);
		}

		public void on_sound_spawned(Guid id, string name, Vector3 pos, Quaternion rot, Vector3 scl, double range, double volume, bool loop)
		{
			_db.add_restore_point((int)ActionType.SPAWN_SOUND, new Guid[] { id });
			_db.create(id);
			_db.set_property(id, "editor.name", "sound_%04u".printf(_num_sounds++));
			_db.set_property(id, "position", pos);
			_db.set_property(id, "rotation", rot);
			_db.set_property(id, "name", name);
			_db.set_property(id, "range", range);
			_db.set_property(id, "volume", volume);
			_db.set_property(id, "loop", loop);
			_db.add_to_set(GUID_ZERO, "sounds", id);
		}

		public void on_move_objects(Guid[] ids, Vector3[] positions, Quaternion[] rotations, Vector3[] scales)
		{
			_db.add_restore_point((int)ActionType.MOVE_OBJECTS, ids);

			for (int i = 0; i < ids.length; ++i)
			{
				Guid id = ids[i];
				Vector3 pos = positions[i];
				Quaternion rot = rotations[i];
				Vector3 scl = scales[i];

				if (is_unit(id))
				{
					Guid transform_id = GUID_ZERO;

					if (has_component(id, "transform", ref transform_id))
					{
						set_component_property(id, transform_id, "data.position", pos);
						set_component_property(id, transform_id, "data.rotation", rot);
						set_component_property(id, transform_id, "data.scale", scl);
					}
					else
					{
						_db.set_property(id, "position", pos);
						_db.set_property(id, "rotation", rot);
						_db.set_property(id, "scale", scl);
					}
				}
				else if (is_sound(id))
				{
					_db.set_property(id, "position", pos);
					_db.set_property(id, "rotation", rot);
				}
			}
			// FIXME: Hack to force update the component view
			selection_changed(_selection);
		}

		public void on_selection(Guid[] ids)
		{
			_selection.clear();
			foreach (Guid id in ids)
				_selection.add(id);

			selection_changed(_selection);
		}

		public void selection_set(Guid[] ids)
		{
			_selection.clear();
			for (int i = 0; i < ids.length; ++i)
				_selection.add(ids[i]);
			_client.send_script(LevelEditorApi.selection_set(ids));

			selection_changed(_selection);
		}

		public void set_light(Guid unit_id, Guid component_id, string type, double range, double intensity, double spot_angle, Vector3 color)
		{
			set_component_property(unit_id, component_id, "data.type",       type);
			set_component_property(unit_id, component_id, "data.range",      range);
			set_component_property(unit_id, component_id, "data.intensity",  intensity);
			set_component_property(unit_id, component_id, "data.spot_angle", spot_angle);
			set_component_property(unit_id, component_id, "data.color",      color);
			set_component_property(unit_id, component_id, "type", "light");

			_client.send_script(LevelEditorApi.set_light(unit_id, type, range, intensity, spot_angle, color));
		}

		public void set_sprite(Guid unit_id, Guid component_id, double layer, double depth)
		{
			set_component_property(unit_id, component_id, "data.layer", layer);
			set_component_property(unit_id, component_id, "data.depth", depth);

			_client.send_script(LevelEditorApi.set_sprite(unit_id, layer, depth));
		}

		public void set_sound(Guid sound_id, string name, double range, double volume, bool loop)
		{
			_db.set_property(sound_id, "name", name);
			_db.set_property(sound_id, "range", range);
			_db.set_property(sound_id, "volume", volume);
			_db.set_property(sound_id, "loop", loop);

			_client.send_script(LevelEditorApi.set_sound_range(sound_id, range));
		}

		public string object_editor_name(Guid object_id)
		{
			Value? name = _db.get_property(object_id, "editor.name");
			return name != null ? (string)name : "<unnamed>";
		}

		public void object_set_editor_name(Guid object_id, string name)
		{
			_db.add_restore_point((int)ActionType.OBJECT_SET_EDITOR_NAME, new Guid[] { object_id });
			_db.set_property(object_id, "editor.name", name);

			object_editor_name_changed(object_id, name);
		}

		private void send_spawn_units(Guid[] ids)
		{
			StringBuilder sb = new StringBuilder();
			generate_spawn_unit_commands(ids, sb);
			_client.send_script(sb.str);
		}

		private void send_spawn_sounds(Guid[] ids)
		{
			StringBuilder sb = new StringBuilder();
			generate_spawn_sound_commands(ids, sb);
			_client.send_script(sb.str);
		}

		private void send_spawn_objects(Guid[] ids)
		{
			StringBuilder sb = new StringBuilder();
			for (int i = 0; i < ids.length; ++i)
			{
				if (is_unit(ids[i]))
				{
					generate_spawn_unit_commands(new Guid[] { ids[i] }, sb);
				}
				else if (is_sound(ids[i]))
				{
					generate_spawn_sound_commands(new Guid[] { ids[i] }, sb);
				}
			}
			_client.send_script(sb.str);
		}

		private void send_destroy_objects(Guid[] ids)
		{
			StringBuilder sb = new StringBuilder();
			foreach (Guid id in ids)
				sb.append(LevelEditorApi.destroy(id));

			_client.send_script(sb.str);
		}

		private void send_move_objects(Guid[] ids, Vector3[] positions, Quaternion[] rotations, Vector3[] scales)
		{
			StringBuilder sb = new StringBuilder();
			for (int i = 0; i < ids.length; ++i)
				sb.append(LevelEditorApi.move_object(ids[i], positions[i], rotations[i], scales[i]));

			_client.send_script(sb.str);
		}

		public void send_level()
		{
			HashSet<Guid?> units = _db.get_property(GUID_ZERO, "units") as HashSet<Guid?>;
			HashSet<Guid?> sounds = _db.get_property(GUID_ZERO, "sounds") as HashSet<Guid?>;

			Guid[] unit_ids = new Guid[units.size];
			Guid[] sound_ids = new Guid[sounds.size];

			// FIXME
			{
				Guid?[] tmp = units.to_array();
				for (int i = 0; i < tmp.length; ++i)
					unit_ids[i] = tmp[i];
			}
			// FIXME
			{
				Guid?[] tmp = sounds.to_array();
				for (int i = 0; i < tmp.length; ++i)
					sound_ids[i] = tmp[i];
			}

			StringBuilder sb = new StringBuilder();
			sb.append(LevelEditorApi.reset());
			generate_spawn_unit_commands(unit_ids, sb);
			generate_spawn_sound_commands(sound_ids, sb);
			_client.send_script(sb.str);
		}

		/// <summary>
		/// Loads the prefab name into the database of prefabs.
		/// </summary>
		private void load_prefab(string name)
		{
			if (_loaded_prefabs.contains(name))
				return;

			Database prefab_db = new Database();

			File file = File.new_for_path(_toolchain_dir + "/" + name + ".unit");
			if (file.query_exists())
				prefab_db.load(file.get_path());
			else
				prefab_db.load(_source_dir + "/" + name + ".unit");

			Value? prefab = prefab_db.get_property(GUID_ZERO, "prefab");
			if (prefab != null)
				load_prefab((string)prefab);

			prefab_db.copy_to(_prefabs, name);
			_loaded_prefabs.add(name);
		}

		private void generate_spawn_unit_commands(Guid[] unit_ids, StringBuilder sb)
		{
			foreach (Guid unit_id in unit_ids)
			{
				if (has_prefab(unit_id))
					load_prefab((string)_db.get_property(unit_id, "prefab"));

				sb.append(LevelEditorApi.spawn_empty_unit(unit_id));

				Guid component_id = GUID_ZERO;

				if (has_component(unit_id, "transform", ref component_id))
				{
					string s = LevelEditorApi.add_tranform_component(unit_id
						, component_id
						, (Vector3)   get_component_property(unit_id, component_id, "data.position")
						, (Quaternion)get_component_property(unit_id, component_id, "data.rotation")
						, (Vector3)   get_component_property(unit_id, component_id, "data.scale")
						);
					sb.append(s);
				}
				if (has_component(unit_id, "mesh_renderer", ref component_id))
				{
					string s = LevelEditorApi.add_mesh_component(unit_id
						, component_id
						, (string)get_component_property(unit_id, component_id, "data.mesh_resource")
						, (string)get_component_property(unit_id, component_id, "data.geometry_name")
						, (string)get_component_property(unit_id, component_id, "data.material")
						, (bool)  get_component_property(unit_id, component_id, "data.visible")
						);
					sb.append(s);
				}
				if (has_component(unit_id, "sprite_renderer", ref component_id))
				{
					string s = LevelEditorApi.add_sprite_component(unit_id
						, component_id
						, (string)get_component_property(unit_id, component_id, "data.sprite_resource")
						, (string)get_component_property(unit_id, component_id, "data.material")
						, (double)get_component_property(unit_id, component_id, "data.layer")
						, (double)get_component_property(unit_id, component_id, "data.depth")
						, (bool)  get_component_property(unit_id, component_id, "data.visible")
						);
					sb.append(s);
				}
				if (has_component(unit_id, "light", ref component_id))
				{
					string s = LevelEditorApi.add_light_component(unit_id
						, component_id
						, (string) get_component_property(unit_id, component_id, "data.type")
						, (double) get_component_property(unit_id, component_id, "data.range")
						, (double) get_component_property(unit_id, component_id, "data.intensity")
						, (double) get_component_property(unit_id, component_id, "data.spot_angle")
						, (Vector3)get_component_property(unit_id, component_id, "data.color")
						);
					sb.append(s);
				}
				if (has_component(unit_id, "camera", ref component_id))
				{
					string s = LevelEditorApi.add_camera_component(unit_id
						, component_id
						, (string)get_component_property(unit_id, component_id, "data.projection")
						, (double)get_component_property(unit_id, component_id, "data.fov")
						, (double)get_component_property(unit_id, component_id, "data.far_range")
						, (double)get_component_property(unit_id, component_id, "data.near_range")
						);
					sb.append(s);
				}
			}
		}

		private void generate_spawn_sound_commands(Guid[] sound_ids, StringBuilder sb)
		{
			foreach (Guid sound_id in sound_ids)
			{
				string s = LevelEditorApi.spawn_sound(sound_id
					, (string)    _db.get_property(sound_id, "name")
					, (Vector3)   _db.get_property(sound_id, "position")
					, (Quaternion)_db.get_property(sound_id, "rotation")
					, (double)    _db.get_property(sound_id, "range")
					, (double)    _db.get_property(sound_id, "volume")
					, (bool)      _db.get_property(sound_id, "loop")
					);
				sb.append(s);
			}
		}

		private void undo_redo_action(bool undo, int id, Guid[] data)
		{
			switch (id)
			{
			case (int)ActionType.SPAWN_UNIT:
				{
					if (undo)
						send_destroy_objects(data);
					else
						send_spawn_units(data);
				}
				break;

			case (int)ActionType.DESTROY_UNIT:
				{
					if (undo)
						send_spawn_units(data);
					else
						send_destroy_objects(data);
				}
				break;

			case (int)ActionType.SPAWN_SOUND:
				{
					if (undo)
						send_destroy_objects(data);
					else
						send_spawn_sounds(data);
				}
				break;

			case (int)ActionType.DESTROY_SOUND:
				{
					if (undo)
						send_spawn_sounds(data);
					else
						send_destroy_objects(data);
				}
				break;

			case (int)ActionType.MOVE_OBJECTS:
				{
					Guid[] ids = data;

					Vector3[] positions = new Vector3[ids.length];
					Quaternion[] rotations = new Quaternion[ids.length];
					Vector3[] scales = new Vector3[ids.length];

					for (int i = 0; i < ids.length; ++i)
					{
						if (is_unit(ids[i]))
						{
							Guid unit_id = ids[i];
							Guid transform_id = GUID_ZERO;

							if (has_component(unit_id, "transform", ref transform_id))
							{
								positions[i] = (Vector3)   get_component_property(unit_id, transform_id, "data.position");
								rotations[i] = (Quaternion)get_component_property(unit_id, transform_id, "data.rotation");
								scales[i]    = (Vector3)   get_component_property(unit_id, transform_id, "data.scale");
							}
							else
							{
								positions[i] = (Vector3)   _db.get_property(unit_id, "position");
								rotations[i] = (Quaternion)_db.get_property(unit_id, "rotation");
								scales[i]    = (Vector3)   _db.get_property(unit_id, "scale");
							}
						}
						else if (is_sound(ids[i]))
						{
							Guid sound_id = ids[i];
							positions[i] = (Vector3)   _db.get_property(sound_id, "position");
							rotations[i] = (Quaternion)_db.get_property(sound_id, "rotation");
							scales[i]    = Vector3(1.0, 1.0, 1.0);
						}
						else
						{
							assert(false);
						}
					}

					send_move_objects(ids, positions, rotations, scales);
					// FIXME: Hack to force update the component view
					selection_changed(_selection);
				}
				break;

			case (int)ActionType.DUPLICATE_OBJECTS:
				{
					Guid[] new_ids = data;
					if (undo)
						send_destroy_objects(new_ids);
					else
						send_spawn_objects(new_ids);
				}
				break;

			case (int)ActionType.OBJECT_SET_EDITOR_NAME:
				object_editor_name_changed(data[0], object_editor_name(data[0]));
				break;

			default:
				assert(false);
				break;
			}
		}

		public Value? get_property(Guid id, string key)
		{
			return _db.get_property(id, key);
		}

		public void set_property(Guid id, string key, Value? value)
		{
			_db.set_property(id, key, value);
		}

		public Value? get_component_property(Guid unit_id, Guid component_id, string key)
		{
			// Search in components
			{
				Value? components = _db.get_property(unit_id, "components");
				if (components != null && ((HashSet<Guid?>)components).contains(component_id))
					return _db.get_property(component_id, key);
			}

			// Search in modified components
			{
				Value? value = _db.get_property(unit_id, "modified_components.#" + component_id.to_string() + "." + key);
				if (value != null)
					return value;
			}

			// Search in prefab's components
			{
				Value? value = _db.get_property(unit_id, "prefab");
				if (value != null)
				{
					string prefab = (string)value;
					Value? pcvalue = _prefabs.get_property(GUID_ZERO, prefab + ".components");
					if (pcvalue != null)
					{
						HashSet<Guid?> prefab_components = (HashSet<Guid?>)pcvalue;
						if (prefab_components.contains(component_id))
							return _prefabs.get_property(component_id, key);
					}
				}
			}

			assert(false);
			return null;
		}

		public void set_component_property(Guid unit_id, Guid component_id, string key, Value? value)
		{
			// Search in components
			{
				Value? components = _db.get_property(unit_id, "components");
				if (components != null && ((HashSet<Guid?>)components).contains(component_id))
				{
					_db.set_property(component_id, key, value);
					return;
				}
			}

			// Search in modified components
			{
				Value? val = _db.get_property(unit_id, "modified_components.#" + component_id.to_string() + "." + key);
				if (val != null)
				{
					_db.set_property(unit_id, "modified_components.#" + component_id.to_string() + "." + key, value);
					return;
				}
			}

			// Create new entry
			{
				_db.set_property(unit_id, "modified_components.#" + component_id.to_string() + "." + key, value);
				return;
			}
		}

		private static bool has_component_static(Database db, Database prefabs_db, Guid unit_id, string component_type, ref Guid ref_component_id)
		{
			// Search in components
			{
				Value? value = db.get_property(unit_id, "components");
				if (value != null)
				{
					HashSet<Guid?> components = (HashSet<Guid?>)value;
					foreach (Guid component_id in components)
					{
						if((string)db.get_property(component_id, "type") == component_type)
						{
							ref_component_id = component_id;
							return true;
						}
					}
				}
			}

			{
				string[] keys = db.get_keys(unit_id);
				foreach (string m in keys)
				{
					if (!m.has_prefix("modified_components.#"))
						continue;

					// 0                   21                                   58  62
					// |                    |                                    |   |
					// modified_components.#f56420ad-7f9c-4cca-aca5-350f366e0dc0.type
					string id = m[21:57];
					string type_or_name = m[58:62];

					if (!type_or_name.has_prefix("type"))
						continue;

					if ((string)db.get_property(unit_id, m) == component_type)
					{
						ref_component_id = Guid.parse(id);
						return true;
					}
				}
			}

			{
				Value? value = db.get_property(unit_id, "prefab");
				if (value != null)
				{
					string prefab = (string)value;
					Value? pcvalue = prefabs_db.get_property(GUID_ZERO, prefab + ".components");
					if (pcvalue != null)
					{
						HashSet<Guid?> prefab_components = (HashSet<Guid?>)pcvalue;
						foreach (Guid component_id in prefab_components)
						{
							if((string)prefabs_db.get_property(component_id, "type") == component_type)
							{
								ref_component_id = component_id;
								return true;
							}
						}
					}
				}
			}

			return false;
		}

		public bool has_component(Guid unit_id, string component_type, ref Guid ref_component_id)
		{
			return Level.has_component_static(_db, _prefabs, unit_id, component_type, ref ref_component_id);
		}

		public bool has_prefab(Guid unit_id)
		{
			return _db.get_property(unit_id, "prefab") != null;
		}

		public bool is_unit(Guid id)
		{
			return (_db.get_property(GUID_ZERO, "units") as HashSet<Guid?>).contains(id);
		}

		public bool is_light(Guid id)
		{
			return has_prefab(id)
				&& (string)_db.get_property(id, "prefab") == "core/units/light";
		}

		public bool is_sound(Guid id)
		{
			return (_db.get_property(GUID_ZERO, "sounds") as HashSet<Guid?>).contains(id);
		}
	}
}
