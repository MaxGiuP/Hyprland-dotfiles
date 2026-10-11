import gi
from pathlib import Path
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk
w = Gtk.Window(title='Agent Desktop Verification')
w.set_default_size(520, 220)
w.move(600, 100)
box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
box.set_border_width(20)
box.pack_start(Gtk.Label(label='This window belongs only to the isolated agent desktop.'), False, False, 0)
entry = Gtk.Entry()
entry.set_placeholder_text('Agent verification text')
box.pack_start(entry, False, False, 0)
button = Gtk.Button(label='Save verification')
def save(_):
    Path.home().joinpath('.local/share/agent-desktop/input-result.txt').write_text(entry.get_text())
    button.set_label('Saved successfully')
button.connect('clicked', save)
box.pack_start(button, False, False, 0)
w.add(box)
w.connect('destroy', Gtk.main_quit)
w.show_all()
Gtk.main()
