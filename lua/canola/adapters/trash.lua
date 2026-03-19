local fs = require('canola.fs')

if fs.is_mac then
  return require('canola.adapters.trash.mac')
elseif fs.is_windows then
  return require('canola.adapters.trash.windows')
else
  return require('canola.adapters.trash.freedesktop')
end
