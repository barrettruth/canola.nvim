local TmpDir = require('spec.tmpdir')
local config = require('canola.config')
local permissions = require('canola.adapters.files.permissions')
local test_util = require('spec.test_util')

describe('column highlights', function()
  after_each(function()
    test_util.reset_editor()
  end)

  describe('config backward compat', function()
    it('wraps array highlights into filename key', function()
      vim.g.canola = { highlights = { { '%.lua$', 'Special' } } }
      config.init()
      assert.same({ { '%.lua$', 'Special' } }, config.highlights.filename)
      assert.is_true(config.highlights.columns)
    end)

    it('passes table highlights through unchanged', function()
      vim.g.canola = { highlights = { filename = { { '%.md$', 'Title' } }, columns = false } }
      config.init()
      assert.same({ { '%.md$', 'Title' } }, config.highlights.filename)
      assert.is_false(config.highlights.columns)
    end)

    it('defaults columns to true', function()
      vim.g.canola = nil
      config.init()
      assert.is_true(config.highlights.columns)
      assert.same({}, config.highlights.filename)
    end)
  end)

  describe('permissions.mode_to_highlighted', function()
    it('highlights 0755 (rwxr-xr-x)', function()
      local result = permissions.mode_to_highlighted(tonumber('755', 8))
      assert.equals('.rwxr-xr-x', result[1])
      assert.same({
        { 'CanolaPermNone', 0, 1 },
        { 'CanolaPermUserRead', 1, 2 },
        { 'CanolaPermUserWrite', 2, 3 },
        { 'CanolaPermUserExec', 3, 4 },
        { 'CanolaPermGroupRead', 4, 5 },
        { 'CanolaPermNone', 5, 6 },
        { 'CanolaPermGroupExec', 6, 7 },
        { 'CanolaPermOtherRead', 7, 8 },
        { 'CanolaPermNone', 8, 9 },
        { 'CanolaPermOtherExec', 9, 10 },
      }, result[2])
    end)

    it('highlights 0644 (rw-r--r--)', function()
      local result = permissions.mode_to_highlighted(tonumber('644', 8))
      assert.equals('.rw-r--r--', result[1])
      assert.same({
        { 'CanolaPermNone', 0, 1 },
        { 'CanolaPermUserRead', 1, 2 },
        { 'CanolaPermUserWrite', 2, 3 },
        { 'CanolaPermNone', 3, 4 },
        { 'CanolaPermGroupRead', 4, 5 },
        { 'CanolaPermNone', 5, 6 },
        { 'CanolaPermNone', 6, 7 },
        { 'CanolaPermOtherRead', 7, 8 },
        { 'CanolaPermNone', 8, 9 },
        { 'CanolaPermNone', 9, 10 },
      }, result[2])
    end)

    it('highlights setuid 4755 (rwsr-xr-x)', function()
      local result = permissions.mode_to_highlighted(tonumber('4755', 8))
      assert.equals('.rwsr-xr-x', result[1])
      assert.same({
        { 'CanolaPermNone', 0, 1 },
        { 'CanolaPermUserRead', 1, 2 },
        { 'CanolaPermUserWrite', 2, 3 },
        { 'CanolaPermSpecial', 3, 4 },
        { 'CanolaPermGroupRead', 4, 5 },
        { 'CanolaPermNone', 5, 6 },
        { 'CanolaPermGroupExec', 6, 7 },
        { 'CanolaPermOtherRead', 7, 8 },
        { 'CanolaPermNone', 8, 9 },
        { 'CanolaPermOtherExec', 9, 10 },
      }, result[2])
    end)

    it('highlights sticky 1777 (rwxrwxrwt)', function()
      local result = permissions.mode_to_highlighted(tonumber('1777', 8))
      assert.equals('.rwxrwxrwt', result[1])
      assert.same({
        { 'CanolaPermNone', 0, 1 },
        { 'CanolaPermUserRead', 1, 2 },
        { 'CanolaPermUserWrite', 2, 3 },
        { 'CanolaPermUserExec', 3, 4 },
        { 'CanolaPermGroupRead', 4, 5 },
        { 'CanolaPermGroupWrite', 5, 6 },
        { 'CanolaPermGroupExec', 6, 7 },
        { 'CanolaPermOtherRead', 7, 8 },
        { 'CanolaPermOtherWrite', 8, 9 },
        { 'CanolaPermSpecial', 9, 10 },
      }, result[2])
    end)

    it('highlights no permissions 0000 (---------)', function()
      local result = permissions.mode_to_highlighted(0)
      assert.equals('.---------', result[1])
      for _, range in ipairs(result[2]) do
        assert.equals('CanolaPermNone', range[1])
      end
    end)
  end)

  describe('size highlight selection', function()
    it('uses CanolaSizeGiga for >= 1GB', function()
      local constants = require('canola.constants')
      vim.g.canola = { highlights = { filename = {}, columns = true } }
      config.init()
      local files = require('canola.adapters.files')
      local col = files.get_column('size')
      local entry = {
        [constants.FIELD_ID] = 1,
        [constants.FIELD_NAME] = 'big.bin',
        [constants.FIELD_TYPE] = 'file',
        [constants.FIELD_META] = { stat = { size = 2e9 } },
      }
      local result = col.render(entry, nil)
      assert.equals('table', type(result))
      assert.truthy(result[1]:match('G$'))
      assert.equals('CanolaSizeGiga', result[2][1][1])
    end)

    it('uses CanolaSizeMega for >= 1MB', function()
      local constants = require('canola.constants')
      vim.g.canola = { highlights = { filename = {}, columns = true } }
      config.init()
      local files = require('canola.adapters.files')
      local col = files.get_column('size')
      local entry = {
        [constants.FIELD_ID] = 1,
        [constants.FIELD_NAME] = 'med.bin',
        [constants.FIELD_TYPE] = 'file',
        [constants.FIELD_META] = { stat = { size = 5e6 } },
      }
      local result = col.render(entry, nil)
      assert.equals('table', type(result))
      assert.truthy(result[1]:match('M$'))
      assert.equals('CanolaSizeMega', result[2][1][1])
    end)

    it('uses CanolaSizeKilo for >= 1KB', function()
      local constants = require('canola.constants')
      vim.g.canola = { highlights = { filename = {}, columns = true } }
      config.init()
      local files = require('canola.adapters.files')
      local col = files.get_column('size')
      local entry = {
        [constants.FIELD_ID] = 1,
        [constants.FIELD_NAME] = 'small.txt',
        [constants.FIELD_TYPE] = 'file',
        [constants.FIELD_META] = { stat = { size = 4096 } },
      }
      local result = col.render(entry, nil)
      assert.equals('table', type(result))
      assert.truthy(result[1]:match('k$'))
      assert.equals('CanolaSizeKilo', result[2][1][1])
    end)

    it('uses CanolaSizeBytes for < 1KB', function()
      local constants = require('canola.constants')
      vim.g.canola = { highlights = { filename = {}, columns = true } }
      config.init()
      local files = require('canola.adapters.files')
      local col = files.get_column('size')
      local entry = {
        [constants.FIELD_ID] = 1,
        [constants.FIELD_NAME] = 'tiny.txt',
        [constants.FIELD_TYPE] = 'file',
        [constants.FIELD_META] = { stat = { size = 42 } },
      }
      local result = col.render(entry, nil)
      assert.equals('table', type(result))
      assert.equals('42', result[1])
      assert.equals('CanolaSizeBytes', result[2][1][1])
    end)

    it('returns plain string when columns highlighting disabled', function()
      local constants = require('canola.constants')
      vim.g.canola = { highlights = { filename = {}, columns = false } }
      config.init()
      local files = require('canola.adapters.files')
      local col = files.get_column('size')
      local entry = {
        [constants.FIELD_ID] = 1,
        [constants.FIELD_NAME] = 'test.txt',
        [constants.FIELD_TYPE] = 'file',
        [constants.FIELD_META] = { stat = { size = 42 } },
      }
      local result = col.render(entry, nil)
      assert.equals('string', type(result))
      assert.equals('42', result)
    end)
  end)

  describe('owner/group highlight selection', function()
    it('uses CanolaOwnerSelf for current uid', function()
      local constants = require('canola.constants')
      vim.g.canola = { highlights = { filename = {}, columns = true } }
      config.init()
      local files = require('canola.adapters.files')
      local col = files.get_column('owner')
      if not col then
        pending('owner column not available on this platform')
        return
      end
      local entry = {
        [constants.FIELD_ID] = 1,
        [constants.FIELD_NAME] = 'mine.txt',
        [constants.FIELD_TYPE] = 'file',
        [constants.FIELD_META] = { stat = { uid = vim.uv.getuid(), gid = 0 } },
      }
      local result = col.render(entry, nil)
      assert.equals('table', type(result))
      assert.equals('CanolaOwnerSelf', result[2][1][1])
    end)

    it('uses CanolaOwnerOther for different uid', function()
      local constants = require('canola.constants')
      vim.g.canola = { highlights = { filename = {}, columns = true } }
      config.init()
      local files = require('canola.adapters.files')
      local col = files.get_column('owner')
      if not col then
        pending('owner column not available on this platform')
        return
      end
      local entry = {
        [constants.FIELD_ID] = 1,
        [constants.FIELD_NAME] = 'other.txt',
        [constants.FIELD_TYPE] = 'file',
        [constants.FIELD_META] = { stat = { uid = 99999, gid = 0 } },
      }
      local result = col.render(entry, nil)
      assert.equals('table', type(result))
      assert.equals('CanolaOwnerOther', result[2][1][1])
    end)

    it('uses CanolaGroupSelf for current gid', function()
      local constants = require('canola.constants')
      vim.g.canola = { highlights = { filename = {}, columns = true } }
      config.init()
      local files = require('canola.adapters.files')
      local col = files.get_column('group')
      if not col then
        pending('group column not available on this platform')
        return
      end
      local entry = {
        [constants.FIELD_ID] = 1,
        [constants.FIELD_NAME] = 'mine.txt',
        [constants.FIELD_TYPE] = 'file',
        [constants.FIELD_META] = { stat = { uid = 0, gid = vim.uv.getgid() } },
      }
      local result = col.render(entry, nil)
      assert.equals('table', type(result))
      assert.equals('CanolaGroupSelf', result[2][1][1])
    end)

    it('uses CanolaGroupOther for different gid', function()
      local constants = require('canola.constants')
      vim.g.canola = { highlights = { filename = {}, columns = true } }
      config.init()
      local files = require('canola.adapters.files')
      local col = files.get_column('group')
      if not col then
        pending('group column not available on this platform')
        return
      end
      local entry = {
        [constants.FIELD_ID] = 1,
        [constants.FIELD_NAME] = 'other.txt',
        [constants.FIELD_TYPE] = 'file',
        [constants.FIELD_META] = { stat = { uid = 0, gid = 99999 } },
      }
      local result = col.render(entry, nil)
      assert.equals('table', type(result))
      assert.equals('CanolaGroupOther', result[2][1][1])
    end)
  end)

  describe('permissions column highlighting', function()
    it('returns highlighted tuple when columns enabled', function()
      local constants = require('canola.constants')
      vim.g.canola = { highlights = { filename = {}, columns = true } }
      config.init()
      local files = require('canola.adapters.files')
      local col = files.get_column('permissions')
      if not col then
        pending('permissions column not available on this platform')
        return
      end
      local entry = {
        [constants.FIELD_ID] = 1,
        [constants.FIELD_NAME] = 'test.txt',
        [constants.FIELD_TYPE] = 'file',
        [constants.FIELD_META] = { stat = { mode = tonumber('100644', 8) } },
      }
      local result = col.render(entry, nil)
      assert.equals('table', type(result))
      assert.equals('.rw-r--r--', result[1])
      assert.equals(10, #result[2])
    end)

    it('returns plain string when columns disabled', function()
      local constants = require('canola.constants')
      vim.g.canola = { highlights = { filename = {}, columns = false } }
      config.init()
      local files = require('canola.adapters.files')
      local col = files.get_column('permissions')
      if not col then
        pending('permissions column not available on this platform')
        return
      end
      local entry = {
        [constants.FIELD_ID] = 1,
        [constants.FIELD_NAME] = 'test.txt',
        [constants.FIELD_TYPE] = 'file',
        [constants.FIELD_META] = { stat = { mode = tonumber('100644', 8) } },
      }
      local result = col.render(entry, nil)
      assert.equals('string', type(result))
      assert.equals('.rw-r--r--', result)
    end)
  end)

  describe('executable filename highlighting', function()
    local tmpdir

    before_each(function()
      tmpdir = TmpDir.new()
    end)

    after_each(function()
      if tmpdir then
        tmpdir:dispose()
        tmpdir = nil
      end
    end)

    local function list_entries(url, column_defs)
      local done = false
      local err
      local all_entries = {}
      local files = require('canola.adapters.files')

      files.list(url, column_defs, function(list_err, entries, fetch_more)
        if list_err then
          err = list_err
          done = true
          return
        end

        if entries then
          vim.list_extend(all_entries, entries)
        end

        if fetch_more then
          fetch_more()
        else
          done = true
        end
      end)

      vim.wait(10000, function()
        return done
      end, 10)

      if not done then
        error('Timed out waiting for files.list')
      end
      if err then
        error(err)
      end

      return all_entries
    end

    local function find_entry(entries, name)
      local constants = require('canola.constants')
      for _, entry in ipairs(entries) do
        if entry[constants.FIELD_NAME] == name then
          return entry
        end
      end
      error('Missing entry: ' .. name)
    end

    local function filename_highlight(entry)
      local entry_format = require('canola.entry_format')
      local files = require('canola.adapters.files')
      local constants = require('canola.constants')
      for _, chunk in ipairs(entry_format.format_entry_line(entry, files, false, 0)) do
        if type(chunk) == 'table' and chunk[1] == entry[constants.FIELD_NAME] then
          return chunk[2]
        end
      end
    end

    it('detects executable files without a stat-backed column', function()
      local constants = require('canola.constants')
      if require('canola.fs').is_windows then
        pending('POSIX executable mode bits are not used on Windows')
        return
      end

      vim.g.canola = { columns = {}, highlights = { filename = {}, columns = true } }
      config.init()

      tmpdir:create({ 'runs' })
      assert(vim.uv.fs_chmod(tmpdir.path .. '/runs', tonumber('755', 8)))

      local url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. '/'
      local entry = find_entry(list_entries(url, { 'type', 'name' }), 'runs')
      entry[constants.FIELD_ID] = entry[constants.FIELD_ID] or 1

      assert.truthy(entry[constants.FIELD_META] and entry[constants.FIELD_META].stat)
      assert.equals('CanolaExecutable', filename_highlight(entry))
    end)
  end)
end)
