#!/usr/bin/python3

from gi.repository import GLib
from gi.repository import Gio
import configparser
import sys
import os

# gsettingslist add/remove org.gnome.Terminal.ProfilesList /path/to/file
command, list_schema_id, filename = sys.argv[1:]

if command not in ['add', 'remove']:
    sys.exit(f"invalid command {command}: must be 'add' or 'remove'")

schemas = Gio.settings_schema_source_get_default()
list_schema = schemas.lookup(list_schema_id, True)

if not list_schema:
    sys.exit(f"{list_schema_id} doesn't exist")

list_path = list_schema.get_path()

if list_path is None or \
   not list_path.endswith(':/') or \
   not list_schema.has_key('list') or \
   list_schema.get_key('list').get_value_type().dup_string() != 'as':
    sys.exit(f"{list_schema_id} is not a GSettingsList")

list_settings = Gio.Settings(settings_schema=list_schema, path=list_path)
children = list_settings.get_strv('list')
item = os.path.basename(filename)
item_path = list_path + ':' + item + '/'

if command == 'remove':
    try:
        children.remove(item)
        list_settings.set_strv('list', children)
    except ValueError:
        pass

    list_settings.reset(item + '/')

elif command == 'add':
    try:
        config = configparser.ConfigParser(interpolation=None, default_section=None)
        if not config.read(filename):
            sys.exit(f'{filename} does not exist')
    except configparser.Error as e:
        sys.exit(e)

    if len(config[None]):
        sys.exit('keyfile may not contain items outside of sections')

    for section_name in config:
        if section_name is not None:
            section = config[section_name]
            item_schema = schemas.lookup(section_name, True)
            if not item_schema or item_schema.get_path():
                sys.exit(f'{section_name} is not a relocatable GSettings schema')

            item_settings = Gio.Settings(settings_schema=item_schema, path=item_path)
            # apply all changes together (which allows backing out in case of errors)
            # TODO: all sections at once
            item_settings.delay()

            for key_name in section:
                if not item_schema.has_key(key_name):
                    sys.exit(f'GSettings schema f{section_name} has no key f{key_name}')

                key = item_schema.get_key(key_name)
                value_str = section[key_name]
                try:
                    value = GLib.Variant.parse(key.get_value_type(), value_str)
                except GLib.Error as e:
                    sys.exit(f'key `{key_name}` with value `{value_str}`: {e.message}')

                item_settings.set_value(key_name, value)

            item_settings.apply()

    if item not in children:
        children.append(item)
        list_settings.set_strv('list', children)

else:
    os.abort('should not be here')
