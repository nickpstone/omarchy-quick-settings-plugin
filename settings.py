#!/usr/bin/env python3
"""Discover installed plugin panels and persist a user's quick settings selection."""
from concurrent.futures import ThreadPoolExecutor
import time
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ID = 'nick.quick-settings'
STATE = Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state'))) / 'quick-settings'
STATE.mkdir(parents=True, exist_ok=True)
PREFS = STATE / 'settings.json'
DEFAULTS = ['omarchy.audio', 'omarchy.network', 'omarchy.bluetooth', 'omarchy.power', 'nick.abc-radio']
ICONS = {'omarchy.audio': '󰕾', 'omarchy.network': '󰖩', 'omarchy.bluetooth': '󰂯',
         'omarchy.power': '󰁹', 'nick.abc-radio': '󰐹', 'nick.wayvnc': '󰢽',
         'omarchy.tailscale': '󰒍', 'omaplug': '󰏗', 'omarchy-google-tasks': '󰄬',
         'io.github.calebhat.weather': '󰖐'}

def command(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=20,
                            env=dict(os.environ, OMARCHY_SHELL_IPC_TIMEOUT="10s"))
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or 'Command failed')
    return result.stdout


def catalog():
    return json.loads(command(['omarchy-plugin-catalog']))


def supported(plugin):
    if plugin['id'] in [ID, 'omarchy.tray', 'nick.tray'] or 'bar' in plugin.get('kinds', []):
        return False
    kinds = plugin.get('kinds', [])
    if 'bar-widget' in kinds:
        path = plugin.get('barWidgetPath')
        if not path:
            return False
        try:
            text = Path(path).read_text()
            return any(token in text for token in ('Panel {', 'PopupCard {', 'function open(', 'function togglePanel(', 'KeyboardPanel {'))
        except OSError:
            return False
    return any(k in kinds for k in ['panel', 'overlay', 'menu']) and plugin['id'] not in ['omarchy.lock', 'omarchy.polkit', 'omarchy.osd', 'omarchy.image-picker', 'omarchy.dev-gallery']


def read_preferences():
    try:
        prefs = json.loads(PREFS.read_text())
        return prefs['selected']
    except (OSError, ValueError, KeyError):
        return DEFAULTS[:]


def native_icon(pid):
    """Render the actual bar icon, preserving custom artwork and live state."""
    directory = STATE/'icons'
    directory.mkdir(exist_ok=True)
    path = directory/(pid + '.png')
    try:
        old_stamp = path.stat().st_mtime_ns if path.exists() else 0
        result = command(['omarchy-shell', 'nick.quick-settings-host.' + pid,
                          'exportIcon', str(path)]).strip()
        if result != 'true': return ''
        deadline = time.monotonic() + 0.5
        while time.monotonic() < deadline:
            if path.exists() and path.stat().st_mtime_ns != old_stamp:
                return path.as_uri() + '?v=' + str(path.stat().st_mtime_ns)
            time.sleep(0.02)
    except (OSError, RuntimeError, subprocess.TimeoutExpired):
        pass
    return ''


def data():
    enabled = {p['id']: p.get('enabled', False) for p in json.loads(command(['omarchy', 'plugin', 'list', '--json']))}
    rows = [p for p in catalog() if supported(p)]
    bar_ids = {p['id'] for p in rows if 'bar-widget' in p.get('kinds', [])}
    plugins = [{'id': p['id'], 'name': p['name'], 'description': p.get('description', ''),
                'enabled': enabled.get(p['id'], False), 'icon': ICONS.get(p['id'], '󰒓')}
               for p in rows]
    selected = read_preferences()
    native = [p for p in plugins if p['id'] in selected and p['enabled'] and p['id'] in bar_ids]
    with ThreadPoolExecutor(max_workers=6) as pool:
        for plugin, source in zip(native, pool.map(native_icon, [p['id'] for p in native])):
            plugin['iconSource'] = source
    plugins.sort(key=lambda p: p['name'].casefold())
    return {'plugins': plugins, 'selected': read_preferences(), 'error': ''}


def save(ids):
    if not isinstance(ids, list) or any(not isinstance(p, str) for p in ids):
        raise ValueError('Selection must be a list of plugin IDs')
    valid = {p['id'] for p in catalog() if supported(p)}
    if any(p not in valid for p in ids):
        raise ValueError('An unsupported or removed plugin was selected; refresh the list')
    ids = list(dict.fromkeys(ids))
    with (STATE/'settings.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with tempfile.NamedTemporaryFile(mode='w', dir=STATE, delete=False) as out:
            json.dump({'selected': ids}, out)
            temp = Path(out.name)
        synchronize(ids)
        temp.replace(PREFS)


def write_if_changed(path, content):
    if not path.exists() or path.read_text() != content:
        path.write_text(content)


def atomic_json(path, content):
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as out:
        json.dump(content, out, indent=2)
        out.write('\n')
        temp = Path(out.name)
    temp.replace(path)


def synchronize(ids):
    """Hide selected widgets without disabling their native panel or service."""
    base = Path(__file__).resolve().parent
    config_path = Path.home()/'.config/omarchy/shell.json'
    config = json.loads(config_path.read_text())
    original_config = json.dumps(config, sort_keys=True)
    rows = {p['id']: p for p in catalog()}
    layout = config.setdefault('bar', {}).setdefault('layout', {})
    present = {e if isinstance(e, str) else e.get('id')
               for entries in layout.values() for e in entries}
    for pid in ids:
        plugin = rows.get(pid)
        if not plugin:
            continue
        if 'bar-widget' in plugin['kinds'] and pid not in present:
            section = (plugin.get('barWidget') or {}).get('defaultSection', 'right')
            if section not in ['left', 'center', 'right']: section = 'right'
            layout.setdefault(section, []).append({'id': pid})
            present.add(pid)
        elif 'bar-widget' not in plugin['kinds'] and not plugin.get('firstParty'):
            entries = config.setdefault('plugins', [])
            if not any(e.get('id') == pid for e in entries): entries.append({'id': pid})
        if pid in config.get('disabledPlugins', []):
            config['disabledPlugins'].remove(pid)

    hosts_path = STATE/'hosts.json'
    try:
        hosts = json.loads(hosts_path.read_text())
    except (OSError, ValueError):
        hosts = {}
    wrappers = base/'wrappers'
    wrappers.mkdir(exist_ok=True)
    backups = STATE/'backups'
    backups.mkdir(exist_ok=True)
    template = (base/'WidgetHost.qml').read_text()
    for section, entries in config.get('bar', {}).get('layout', {}).items():
        for index, entry in enumerate(entries):
            pid = entry if isinstance(entry, str) else entry.get('id')
            plugin = rows.get(pid)
            if not plugin or 'bar-widget' not in plugin['kinds'] or pid == ID:
                continue
            chosen = pid in ids
            # Deselecting restores the original custom-module source exactly.
            if not chosen:
                if isinstance(entry, dict) and entry.get('quickSettingsHidden'):
                    entry.pop('quickSettingsHidden', None)
                    restore = entry.pop('quickSettingsRestore', None)
                    if restore is not None:
                        for key in ['type', 'source']:
                            if key in restore: entry[key] = restore[key]
                            else: entry.pop(key, None)
                continue
            if isinstance(entry, str):
                entry = {'id': entry}
                entries[index] = entry
            if plugin.get('firstParty'):
                host_file = wrappers/(pid+'.qml')
                if 'quickSettingsRestore' not in entry:
                    entry['quickSettingsRestore'] = {k: entry[k] for k in ['type', 'source'] if k in entry}
                native_path = plugin['barWidgetPath']
                if entry['quickSettingsRestore'].get('source'):
                    native_path = os.path.expanduser(entry['quickSettingsRestore']['source'])
                write_if_changed(host_file, template.replace('property string nativeSource: ""',
                                    'property string nativeSource: ' + json.dumps(Path(native_path).as_uri())))
                entry['type'] = 'qml'
                entry['source'] = str(host_file)
            else:
                # A native registered user widget retains its own service facade.
                # Only its entry point changes; the original QML stays untouched.
                manifest_path = Path(plugin['manifestPath'])
                manifest = json.loads(manifest_path.read_text())
                wrapper_name = '_QuickSettingsHost.qml'
                current = manifest['entryPoints']['barWidget']
                if current != wrapper_name:
                    hosts[pid] = {'original': current, 'manifest': str(manifest_path)}
                    backup = backups/(pid+'.manifest.json')
                    if not backup.exists(): backup.write_text(manifest_path.read_text())
                if pid not in hosts:
                    raise RuntimeError('Missing original entry point for ' + pid)
                native_file = manifest_path.parent/hosts[pid]['original']
                if not native_file.exists():
                    raise RuntimeError('Original widget file missing: ' + str(native_file))
                host_file = manifest_path.parent/wrapper_name
                write_if_changed(host_file, template.replace('property string nativeSource: ""',
                                    'property string nativeSource: ' + json.dumps(native_file.as_uri())))
                if current != wrapper_name:
                    manifest['entryPoints']['barWidget'] = wrapper_name
                    atomic_json(manifest_path, manifest)
            entry['quickSettingsHidden'] = True
    atomic_json(hosts_path, hosts)
    if json.dumps(config, sort_keys=True) != original_config:
        backup = backups/'shell-before-grouping.json'
        if not backup.exists(): backup.write_text(config_path.read_text())
        atomic_json(config_path, config)


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else 'status'
    if action == 'save':
        save(json.loads(sys.argv[2]))
    elif action == 'sync':
        with (STATE/'settings.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            synchronize(read_preferences())
    elif action == 'open':
        target = sys.argv[2]
        if target not in {p['id'] for p in catalog() if supported(p)}:
            raise ValueError('Plugin has no supported controls panel')
        reply = command(['omarchy-shell', 'shell', 'summon', target, '']).strip()
        if reply not in ['ok', 'true']:
            raise RuntimeError('Unable to open plugin. Enable its bar widget in the Plugin Manager first.')
        print(json.dumps({'opened': target, 'error': ''}))
        return
    elif action == 'enable':
        target = sys.argv[2]
        if target not in {p['id'] for p in catalog() if supported(p)}:
            raise ValueError('Unknown plugin')
        command(['omarchy', 'plugin', 'enable', target])
        synchronize(read_preferences())
    elif action != 'status':
        raise ValueError('Unknown command')
    print(json.dumps(data()))

if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(json.dumps({'error': str(exc)}))
        sys.exit(1)
