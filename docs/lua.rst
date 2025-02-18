lua
===

.. dfhack-tool::
    :summary: Run Lua script commands.
    :tags: dev

Usage
-----

``lua``
   Start an interactive lua interpreter.
``lua -f <filename>``, ``lua --file <filename>``
   Load the specified file and run the lua script within. The filename is
   interpreted relative to the Dwarf Fortress game directory.
``lua -s [<filename>]``, ``lua --save [<filename>]``
   Load the specified file and run the lua script within. The filename is
   interpreted relative to the current save directory. If the filename is not
   supplied, it loads :file:`dfhack.lua`.
``:lua <lua statement>``
   Parses and executes the given lua statement like the interactive interpreter
   would.

The last form recognizes shortcut characters from the interactive interpreter
for easy inspection of values::

    '! foo' => 'print(foo)'
    '~ foo' => 'printall(foo)'
    '^ foo' => 'printall_recurse(foo)'
    '@ foo' => 'printall_ipairs(foo)'

Examples
--------

``:lua !df.global.window_z``
   Print out the current z-level.
