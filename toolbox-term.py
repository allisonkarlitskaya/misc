#!/usr/bin/python3

import ast
import errno
import io
import os.path
import sys
import uuid

name = sys.argv[1]

shortname = sys.argv[1]
dns = f'ca.desrt.toolbox-terminal.{name}'

localdir = os.path.expanduser('~/.local')
libexec = '/usr/libexec'
icon = 'debian'
profile = str(uuid.uuid5(uuid.NAMESPACE_DNS, '.'.join(dns.split('.')[::-1])))

files = {
    f'share/systemd/user/{dns}.service':
    f"""
    [Unit]
    Description=GNOME Terminal Server ({shortname} Toolbox)

    [Service]
    Slice=apps-{dns}.slice
    Type=dbus
    BusName={dns}
    ExecStart={libexec}/gnome-terminal-server --app-id={dns}
    """,

    f'share/applications/{dns}.desktop':
    f"""
    [Desktop Entry]
    Type=Application
    Name={shortname} Toolbox
    Icon={icon}
    StartupNotify=true
    Exec=gnome-terminal --profile=sid --app-id={dns}
    """,

    f'share/dbus-1/services/{dns}.service':
    f"""
    [D-BUS Service]
    Name={dns}
    SystemdService={dns}.service
    """,

    f'share/dconf-fragments/org/gnome/terminal/legacy/profiles:/:{profile}':
    f"""
    [/]
    use-custom-command=True
    custom-command='toolbox enter {shortname}'
    visible-name='Toolbox ({shortname})'
    """,
    }

def create_parent_directories(filename):
    parent = os.path.basename(filename)
    os.makedirs(parent, exist_ok=True)
    return parent

def rmdirs(filename):
    "Small wrapper to os.removedirs() which allows @filename to be non-empty"
    try:
        os.removedirs(filename)
    except OSError as e:
        if e.errno != errno.ENOTEMPTY:
            raise

def create_file(filename, content):
    parent = create_parent_directories(filename)
    fd = os.open(parent, os.O_CREAT | os.O_TMPFILE, 0o666)
    os.write(fd, content)
    os.fdatasync()
    # re: src_dir_fd, see https://bugs.python.org/issue41355
    os.link(f'/proc/self/fd/{fd}', filename, src_dir_fd=fd)
    os.close(fd)

def install_package(packagedir, targetdir):
    for root, dirs, files in os.walk(packagedir):
        for f in files:
            filename = os.path.relpath(root + f, packagedir)

        targetfile = os.path.join(targetdir)

    parent = os.path.basename(filename)
    os.makedirs(parent, exist_ok=True)
    os.symlink(os.path.relpath(target, parent), filename)

def uninstall_file(filename, target):
    parent = os.path.basename(filename)
    content = os.readlink(filename)
    if content == os.path.relpath(target, parent):
        os.unlink(parent)
    rmdirs(parent)

def to_binary(content):
    lines = content.encode('utf-8').splitlines()
    assert lines.pop(0) == b''
    return b'\n'.join(l.strip() for l in lines)

stowdir = os.path.join(datadir, 'stow')
stowrc = os.path.join(stowdir, '.stowrc')

if not os.path.exists(stowrc):
    GLib.mkdir_with_parents(stowdir, 0o777)
    GLib.file_set_contents(stowrc, b'--no-folding\n')

# files
for name in files:
    print(os.path.join(datadir, 'stow', dns, name))

    filename = os.path.join(stowdir, dns, name)
    GLib.mkdir_with_parents(os.path.dirname(filename), 0o777)
    GLib.file_set_contents(filename, to_binary(files[name]))

# GSettings
"""
path = f'/org/gnome/terminal/legacy/profiles:/:{profile}/'
profile_settings = Gio.Settings.new_with_path('org.gnome.Terminal.Legacy.Profile', path)
profile_settings.set_string('custom-command', f'toolbox enter {shortname}')
profile_settings.set_string('visible-name', f'Toolbox ({shortname})')
profile_settings.set_boolean('use-custom-command', True)

profiles_settings = Gio.Settings.new('org.gnome.Terminal.ProfilesList')
profile_list = profiles_settings.get_strv('list')
if profile not in profile_list:
    profile_list.append(profile)
profiles_settings.set_strv('list', profile_list)
"""
