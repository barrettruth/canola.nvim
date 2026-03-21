local cache = require('canola.cache')
local constants = require('canola.constants')
local mutator = require('canola.mutator')
local test_adapter = require('canola.adapters.test')
local test_util = require('spec.test_util')

local FIELD_ID = constants.FIELD_ID
local FIELD_NAME = constants.FIELD_NAME
local FIELD_TYPE = constants.FIELD_TYPE

describe('mutator', function()
  after_each(function()
    test_util.reset_editor()
  end)

  describe('build actions', function()
    it('empty diffs produce no actions', function()
      vim.cmd.edit({ args = { 'canola-test:///foo/' } })
      local bufnr = vim.api.nvim_get_current_buf()
      local actions = mutator.create_actions_from_diffs({
        [bufnr] = {},
      })
      assert.are.same({}, actions)
    end)

    it('constructs CREATE actions', function()
      vim.cmd.edit({ args = { 'canola-test:///foo/' } })
      local bufnr = vim.api.nvim_get_current_buf()
      local diffs = {
        { type = 'new', name = 'a.txt', entry_type = 'file' },
      }
      local actions = mutator.create_actions_from_diffs({
        [bufnr] = diffs,
      })
      assert.are.same({
        {
          type = 'create',
          entry_type = 'file',
          url = 'canola-test:///foo/a.txt',
        },
      }, actions)
    end)

    it('constructs DELETE actions', function()
      local file = test_adapter.test_set('/foo/a.txt', 'file')
      vim.cmd.edit({ args = { 'canola-test:///foo/' } })
      local bufnr = vim.api.nvim_get_current_buf()
      local diffs = {
        { type = 'delete', name = 'a.txt', id = file[FIELD_ID] },
      }
      local actions = mutator.create_actions_from_diffs({
        [bufnr] = diffs,
      })
      assert.are.same({
        {
          type = 'delete',
          entry_type = 'file',
          url = 'canola-test:///foo/a.txt',
        },
      }, actions)
    end)

    it('constructs COPY actions', function()
      local file = test_adapter.test_set('/foo/a.txt', 'file')
      vim.cmd.edit({ args = { 'canola-test:///foo/' } })
      local bufnr = vim.api.nvim_get_current_buf()
      local diffs = {
        { type = 'new', name = 'b.txt', entry_type = 'file', id = file[FIELD_ID] },
      }
      local actions = mutator.create_actions_from_diffs({
        [bufnr] = diffs,
      })
      assert.are.same({
        {
          type = 'copy',
          entry_type = 'file',
          src_url = 'canola-test:///foo/a.txt',
          dest_url = 'canola-test:///foo/b.txt',
        },
      }, actions)
    end)

    it('constructs MOVE actions', function()
      local file = test_adapter.test_set('/foo/a.txt', 'file')
      vim.cmd.edit({ args = { 'canola-test:///foo/' } })
      local bufnr = vim.api.nvim_get_current_buf()
      local diffs = {
        { type = 'delete', name = 'a.txt', id = file[FIELD_ID] },
        { type = 'new', name = 'b.txt', entry_type = 'file', id = file[FIELD_ID] },
      }
      local actions = mutator.create_actions_from_diffs({
        [bufnr] = diffs,
      })
      assert.are.same({
        {
          type = 'move',
          entry_type = 'file',
          src_url = 'canola-test:///foo/a.txt',
          dest_url = 'canola-test:///foo/b.txt',
        },
      }, actions)
    end)

    it('correctly orders MOVE + CREATE', function()
      local file = test_adapter.test_set('/a.txt', 'file')
      vim.cmd.edit({ args = { 'canola-test:///' } })
      local bufnr = vim.api.nvim_get_current_buf()
      local diffs = {
        { type = 'delete', name = 'a.txt', id = file[FIELD_ID] },
        { type = 'new', name = 'b.txt', entry_type = 'file', id = file[FIELD_ID] },
        { type = 'new', name = 'a.txt', entry_type = 'file' },
      }
      local actions = mutator.create_actions_from_diffs({
        [bufnr] = diffs,
      })
      assert.are.same({
        {
          type = 'move',
          entry_type = 'file',
          src_url = 'canola-test:///a.txt',
          dest_url = 'canola-test:///b.txt',
        },
        {
          type = 'create',
          entry_type = 'file',
          url = 'canola-test:///a.txt',
        },
      }, actions)
    end)

    it('resolves MOVE loops', function()
      local afile = test_adapter.test_set('/a.txt', 'file')
      local bfile = test_adapter.test_set('/b.txt', 'file')
      vim.cmd.edit({ args = { 'canola-test:///' } })
      local bufnr = vim.api.nvim_get_current_buf()
      local diffs = {
        { type = 'delete', name = 'a.txt', id = afile[FIELD_ID] },
        { type = 'new', name = 'b.txt', entry_type = 'file', id = afile[FIELD_ID] },
        { type = 'delete', name = 'b.txt', id = bfile[FIELD_ID] },
        { type = 'new', name = 'a.txt', entry_type = 'file', id = bfile[FIELD_ID] },
      }
      math.randomseed(2983982)
      local actions = mutator.create_actions_from_diffs({
        [bufnr] = diffs,
      })
      local tmp_url = 'canola-test:///a.txt__oil_tmp_510852'
      assert.are.same({
        {
          type = 'move',
          entry_type = 'file',
          src_url = 'canola-test:///a.txt',
          dest_url = tmp_url,
        },
        {
          type = 'move',
          entry_type = 'file',
          src_url = 'canola-test:///b.txt',
          dest_url = 'canola-test:///a.txt',
        },
        {
          type = 'move',
          entry_type = 'file',
          src_url = tmp_url,
          dest_url = 'canola-test:///b.txt',
        },
      }, actions)
    end)

    describe('extglob', function()
      before_each(function()
        vim.g.canola = vim.tbl_deep_extend('force', vim.g.canola, { extglob = 1000 })
        require('canola').init()
      end)

      it('expands simple alternation on new file', function()
        vim.cmd.edit({ args = { 'canola-test:///foo/' } })
        local bufnr = vim.api.nvim_get_current_buf()
        local diffs = {
          { type = 'new', name = 'bar.{js,ts}', entry_type = 'file' },
        }
        local actions = mutator.create_actions_from_diffs({
          [bufnr] = diffs,
        })
        assert.are.same({
          { type = 'create', entry_type = 'file', url = 'canola-test:///foo/bar.js' },
          { type = 'create', entry_type = 'file', url = 'canola-test:///foo/bar.ts' },
        }, actions)
      end)

      it('expands braces on non-last path segment', function()
        vim.cmd.edit({ args = { 'canola-test:///foo/' } })
        local bufnr = vim.api.nvim_get_current_buf()
        local diffs = {
          { type = 'new', name = '{src,test}/main.lua', entry_type = 'file' },
        }
        local actions = mutator.create_actions_from_diffs({
          [bufnr] = diffs,
        })
        assert.are.same({
          { type = 'create', entry_type = 'directory', url = 'canola-test:///foo/src' },
          { type = 'create', entry_type = 'file', url = 'canola-test:///foo/src/main.lua' },
          { type = 'create', entry_type = 'directory', url = 'canola-test:///foo/test' },
          { type = 'create', entry_type = 'file', url = 'canola-test:///foo/test/main.lua' },
        }, actions)
      end)

      it('expands numeric range', function()
        vim.cmd.edit({ args = { 'canola-test:///foo/' } })
        local bufnr = vim.api.nvim_get_current_buf()
        local diffs = {
          { type = 'new', name = 'file{1..3}.txt', entry_type = 'file' },
        }
        local actions = mutator.create_actions_from_diffs({
          [bufnr] = diffs,
        })
        assert.are.same({
          { type = 'create', entry_type = 'file', url = 'canola-test:///foo/file1.txt' },
          { type = 'create', entry_type = 'file', url = 'canola-test:///foo/file2.txt' },
          { type = 'create', entry_type = 'file', url = 'canola-test:///foo/file3.txt' },
        }, actions)
      end)

      it('expands cartesian product across segments', function()
        vim.cmd.edit({ args = { 'canola-test:///foo/' } })
        local bufnr = vim.api.nvim_get_current_buf()
        local diffs = {
          { type = 'new', name = '{a,b}/{x,y}.txt', entry_type = 'file' },
        }
        local actions = mutator.create_actions_from_diffs({
          [bufnr] = diffs,
        })
        assert.are.same({
          { type = 'create', entry_type = 'directory', url = 'canola-test:///foo/a' },
          { type = 'create', entry_type = 'file', url = 'canola-test:///foo/a/x.txt' },
          { type = 'create', entry_type = 'file', url = 'canola-test:///foo/a/y.txt' },
          { type = 'create', entry_type = 'directory', url = 'canola-test:///foo/b' },
          { type = 'create', entry_type = 'file', url = 'canola-test:///foo/b/x.txt' },
          { type = 'create', entry_type = 'file', url = 'canola-test:///foo/b/y.txt' },
        }, actions)
      end)

      it('treats braces as literal when extglob is false', function()
        vim.g.canola = vim.tbl_deep_extend('force', vim.g.canola, { extglob = false })
        require('canola').init()
        vim.cmd.edit({ args = { 'canola-test:///foo/' } })
        local bufnr = vim.api.nvim_get_current_buf()
        local diffs = {
          { type = 'new', name = '{a,b}.txt', entry_type = 'file' },
        }
        local actions = mutator.create_actions_from_diffs({
          [bufnr] = diffs,
        })
        assert.are.same({
          { type = 'create', entry_type = 'file', url = 'canola-test:///foo/{a,b}.txt' },
        }, actions)
      end)

      it('expands braces on rename to produce move + copies', function()
        local file = test_adapter.test_set('/foo/a.txt', 'file')
        vim.cmd.edit({ args = { 'canola-test:///foo/' } })
        local bufnr = vim.api.nvim_get_current_buf()
        local diffs = {
          { type = 'delete', name = 'a.txt', id = file[FIELD_ID] },
          { type = 'new', name = 'b.{js,ts}', entry_type = 'file', id = file[FIELD_ID] },
        }
        local actions = mutator.create_actions_from_diffs({
          [bufnr] = diffs,
        })
        assert.are.same({
          {
            type = 'copy',
            entry_type = 'file',
            src_url = 'canola-test:///foo/a.txt',
            dest_url = 'canola-test:///foo/b.js',
          },
          {
            type = 'move',
            entry_type = 'file',
            src_url = 'canola-test:///foo/a.txt',
            dest_url = 'canola-test:///foo/b.ts',
          },
        }, actions)
      end)

      it('deduplicates directory creates from expansion', function()
        vim.cmd.edit({ args = { 'canola-test:///foo/' } })
        local bufnr = vim.api.nvim_get_current_buf()
        local diffs = {
          { type = 'new', name = 'dir/{a,b}.txt', entry_type = 'file' },
        }
        local actions = mutator.create_actions_from_diffs({
          [bufnr] = diffs,
        })
        assert.are.same({
          { type = 'create', entry_type = 'directory', url = 'canola-test:///foo/dir' },
          { type = 'create', entry_type = 'file', url = 'canola-test:///foo/dir/a.txt' },
          { type = 'create', entry_type = 'file', url = 'canola-test:///foo/dir/b.txt' },
        }, actions)
      end)

      it('treats single-item braces as literal', function()
        vim.cmd.edit({ args = { 'canola-test:///foo/' } })
        local bufnr = vim.api.nvim_get_current_buf()
        local diffs = {
          { type = 'new', name = '{single}.txt', entry_type = 'file' },
        }
        local actions = mutator.create_actions_from_diffs({
          [bufnr] = diffs,
        })
        assert.are.same({
          { type = 'create', entry_type = 'file', url = 'canola-test:///foo/{single}.txt' },
        }, actions)
      end)
    end)

    it('creates intermediate dir when moving into new subdir', function()
      local file = test_adapter.test_set('/foo/a.txt', 'file')
      vim.cmd.edit({ args = { 'canola-test:///foo/' } })
      local bufnr = vim.api.nvim_get_current_buf()
      local diffs = {
        { type = 'delete', name = 'a.txt', id = file[FIELD_ID] },
        { type = 'new', name = 'sub/a.txt', entry_type = 'file', id = file[FIELD_ID] },
      }
      local actions = mutator.create_actions_from_diffs({
        [bufnr] = diffs,
      })
      assert.are.same({
        { type = 'create', entry_type = 'directory', url = 'canola-test:///foo/sub' },
        {
          type = 'move',
          entry_type = 'file',
          src_url = 'canola-test:///foo/a.txt',
          dest_url = 'canola-test:///foo/sub/a.txt',
        },
      }, actions)
    end)

    it('creates all intermediate dirs for deeply nested move', function()
      local file = test_adapter.test_set('/foo/a.txt', 'file')
      vim.cmd.edit({ args = { 'canola-test:///foo/' } })
      local bufnr = vim.api.nvim_get_current_buf()
      local diffs = {
        { type = 'delete', name = 'a.txt', id = file[FIELD_ID] },
        { type = 'new', name = 'a/b/c/a.txt', entry_type = 'file', id = file[FIELD_ID] },
      }
      local actions = mutator.create_actions_from_diffs({
        [bufnr] = diffs,
      })
      assert.are.same({
        { type = 'create', entry_type = 'directory', url = 'canola-test:///foo/a' },
        { type = 'create', entry_type = 'directory', url = 'canola-test:///foo/a/b' },
        { type = 'create', entry_type = 'directory', url = 'canola-test:///foo/a/b/c' },
        {
          type = 'move',
          entry_type = 'file',
          src_url = 'canola-test:///foo/a.txt',
          dest_url = 'canola-test:///foo/a/b/c/a.txt',
        },
      }, actions)
    end)

    it('creates intermediate dir when copying into new subdir', function()
      local file = test_adapter.test_set('/foo/a.txt', 'file')
      vim.cmd.edit({ args = { 'canola-test:///foo/' } })
      local bufnr = vim.api.nvim_get_current_buf()
      local diffs = {
        { type = 'new', name = 'sub/a.txt', entry_type = 'file', id = file[FIELD_ID] },
      }
      local actions = mutator.create_actions_from_diffs({
        [bufnr] = diffs,
      })
      assert.are.same({
        { type = 'create', entry_type = 'directory', url = 'canola-test:///foo/sub' },
        {
          type = 'copy',
          entry_type = 'file',
          src_url = 'canola-test:///foo/a.txt',
          dest_url = 'canola-test:///foo/sub/a.txt',
        },
      }, actions)
    end)

    it('deduplicates directory creates when two files move into same new subdir', function()
      local afile = test_adapter.test_set('/foo/a.txt', 'file')
      local bfile = test_adapter.test_set('/foo/b.txt', 'file')
      vim.cmd.edit({ args = { 'canola-test:///foo/' } })
      local bufnr = vim.api.nvim_get_current_buf()
      local diffs = {
        { type = 'delete', name = 'a.txt', id = afile[FIELD_ID] },
        { type = 'new', name = 'sub/a.txt', entry_type = 'file', id = afile[FIELD_ID] },
        { type = 'delete', name = 'b.txt', id = bfile[FIELD_ID] },
        { type = 'new', name = 'sub/b.txt', entry_type = 'file', id = bfile[FIELD_ID] },
      }
      local actions = mutator.create_actions_from_diffs({
        [bufnr] = diffs,
      })
      local create_count = 0
      for _, action in ipairs(actions) do
        if action.type == 'create' and action.url == 'canola-test:///foo/sub' then
          create_count = create_count + 1
        end
      end
      assert.equals(1, create_count)
    end)
  end)

  describe('order actions', function()
    it('Creates files inside dir before move', function()
      local move = {
        type = 'move',
        src_url = 'canola-test:///a',
        dest_url = 'canola-test:///b',
        entry_type = 'directory',
      }
      local create = { type = 'create', url = 'canola-test:///a/hi.txt', entry_type = 'file' }
      local actions = { move, create }
      local ordered_actions = mutator.enforce_action_order(actions)
      assert.are.same({ create, move }, ordered_actions)
    end)

    it('Moves file out of parent before deleting parent', function()
      local move = {
        type = 'move',
        src_url = 'canola-test:///a/b.txt',
        dest_url = 'canola-test:///b.txt',
        entry_type = 'file',
      }
      local delete = { type = 'delete', url = 'canola-test:///a', entry_type = 'directory' }
      local actions = { delete, move }
      local ordered_actions = mutator.enforce_action_order(actions)
      assert.are.same({ move, delete }, ordered_actions)
    end)

    it('Handles parent child move ordering', function()
      local move1 = {
        type = 'move',
        src_url = 'canola-test:///a/b',
        dest_url = 'canola-test:///b',
        entry_type = 'directory',
      }
      local move2 = {
        type = 'move',
        src_url = 'canola-test:///a',
        dest_url = 'canola-test:///b/a',
        entry_type = 'directory',
      }
      local actions = { move2, move1 }
      local ordered_actions = mutator.enforce_action_order(actions)
      assert.are.same({ move1, move2 }, ordered_actions)
    end)

    it('Handles a delete inside a moved folder', function()
      local del = {
        type = 'delete',
        url = 'canola-test:///a/b.txt',
        entry_type = 'file',
      }
      local move = {
        type = 'move',
        src_url = 'canola-test:///a',
        dest_url = 'canola-test:///b',
        entry_type = 'directory',
      }
      local actions = { move, del }
      local ordered_actions = mutator.enforce_action_order(actions)
      assert.are.same({ del, move }, ordered_actions)
    end)

    it('Detects move directory loops', function()
      local move = {
        type = 'move',
        src_url = 'canola-test:///a',
        dest_url = 'canola-test:///a/b',
        entry_type = 'directory',
      }
      assert.has_error(function()
        mutator.enforce_action_order({ move })
      end)
    end)

    it('Detects copy directory loops', function()
      local move = {
        type = 'copy',
        src_url = 'canola-test:///a',
        dest_url = 'canola-test:///a/b',
        entry_type = 'directory',
      }
      assert.has_error(function()
        mutator.enforce_action_order({ move })
      end)
    end)

    it('Detects nested copy directory loops', function()
      local move = {
        type = 'copy',
        src_url = 'canola-test:///a',
        dest_url = 'canola-test:///a/b/a',
        entry_type = 'directory',
      }
      assert.has_error(function()
        mutator.enforce_action_order({ move })
      end)
    end)

    describe('change', function()
      it('applies CHANGE after CREATE', function()
        local create = { type = 'create', url = 'canola-test:///a/hi.txt', entry_type = 'file' }
        local change = {
          type = 'change',
          url = 'canola-test:///a/hi.txt',
          entry_type = 'file',
          column = 'TEST',
          value = 'TEST',
        }
        local actions = { change, create }
        local ordered_actions = mutator.enforce_action_order(actions)
        assert.are.same({ create, change }, ordered_actions)
      end)

      it('applies CHANGE after COPY src', function()
        local copy = {
          type = 'copy',
          src_url = 'canola-test:///a/hi.txt',
          dest_url = 'canola-test:///b.txt',
          entry_type = 'file',
        }
        local change = {
          type = 'change',
          url = 'canola-test:///a/hi.txt',
          entry_type = 'file',
          column = 'TEST',
          value = 'TEST',
        }
        local actions = { change, copy }
        local ordered_actions = mutator.enforce_action_order(actions)
        assert.are.same({ copy, change }, ordered_actions)
      end)

      it('applies CHANGE after COPY dest', function()
        local copy = {
          type = 'copy',
          src_url = 'canola-test:///b.txt',
          dest_url = 'canola-test:///a/hi.txt',
          entry_type = 'file',
        }
        local change = {
          type = 'change',
          url = 'canola-test:///a/hi.txt',
          entry_type = 'file',
          column = 'TEST',
          value = 'TEST',
        }
        local actions = { change, copy }
        local ordered_actions = mutator.enforce_action_order(actions)
        assert.are.same({ copy, change }, ordered_actions)
      end)

      it('applies CHANGE after MOVE dest', function()
        local move = {
          type = 'move',
          src_url = 'canola-test:///b.txt',
          dest_url = 'canola-test:///a/hi.txt',
          entry_type = 'file',
        }
        local change = {
          type = 'change',
          url = 'canola-test:///a/hi.txt',
          entry_type = 'file',
          column = 'TEST',
          value = 'TEST',
        }
        local actions = { change, move }
        local ordered_actions = mutator.enforce_action_order(actions)
        assert.are.same({ move, change }, ordered_actions)
      end)
    end)
  end)

  describe('perform actions', function()
    it('creates new entries', function()
      local actions = {
        { type = 'create', url = 'canola-test:///a.txt', entry_type = 'file' },
      }
      test_util.await(mutator.process_actions, 2, actions)
      local files = cache.list_url('canola-test:///')
      assert.is_not_nil(files['a.txt'])
      assert.equals('a.txt', files['a.txt'][FIELD_NAME])
      assert.equals('file', files['a.txt'][FIELD_TYPE])
    end)

    it('deletes entries', function()
      local file = test_adapter.test_set('/a.txt', 'file')
      local actions = {
        { type = 'delete', url = 'canola-test:///a.txt', entry_type = 'file' },
      }
      test_util.await(mutator.process_actions, 2, actions)
      local files = cache.list_url('canola-test:///')
      assert.are.same({}, files)
      assert.is_nil(cache.get_entry_by_id(file[FIELD_ID]))
      assert.has_error(function()
        cache.get_parent_url(file[FIELD_ID])
      end)
    end)

    it('moves entries', function()
      local file = test_adapter.test_set('/a.txt', 'file')
      local actions = {
        {
          type = 'move',
          src_url = 'canola-test:///a.txt',
          dest_url = 'canola-test:///b.txt',
          entry_type = 'file',
        },
      }
      test_util.await(mutator.process_actions, 2, actions)
      local files = cache.list_url('canola-test:///')
      assert.is_nil(files['a.txt'])
      assert.is_not_nil(files['b.txt'])
      assert.equals(file[FIELD_ID], files['b.txt'][FIELD_ID])
      assert.equals('b.txt', files['b.txt'][FIELD_NAME])
      assert.are.same(files['b.txt'], cache.get_entry_by_id(file[FIELD_ID]))
      assert.equals('canola-test:///', cache.get_parent_url(file[FIELD_ID]))
    end)

    it('copies entries', function()
      local file = test_adapter.test_set('/a.txt', 'file')
      local actions = {
        {
          type = 'copy',
          src_url = 'canola-test:///a.txt',
          dest_url = 'canola-test:///b.txt',
          entry_type = 'file',
        },
      }
      test_util.await(mutator.process_actions, 2, actions)
      local files = cache.list_url('canola-test:///')
      assert.is_not_nil(files['a.txt'])
      assert.is_not_nil(files['b.txt'])
      assert.equals(file[FIELD_ID], files['a.txt'][FIELD_ID])
      assert.equals('b.txt', files['b.txt'][FIELD_NAME])
      assert.equals('file', files['b.txt'][FIELD_TYPE])
      assert.not_equals(file[FIELD_ID], files['b.txt'][FIELD_ID])
    end)
  end)
end)
