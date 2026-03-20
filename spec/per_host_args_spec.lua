local test_util = require('spec.test_util')

describe('per-adapter vim.g config', function()
  after_each(function()
    vim.g.canola_ssh = nil
    vim.g.canola_s3 = nil
    vim.g.canola_ftp = nil
    test_util.reset_editor()
  end)

  describe('vim.g.canola_ssh', function()
    it('stores per-host overrides', function()
      vim.g.canola_ssh = { hosts = { ['myserver.com'] = { extra_args = { '-O' } } } }
      local cfg = vim.g.canola_ssh
      assert.are.equal('-O', cfg.hosts['myserver.com'].extra_args[1])
    end)

    it('defaults to nil when not set', function()
      assert.is_nil(vim.g.canola_ssh)
    end)

    it('returns nil for unknown host', function()
      vim.g.canola_ssh = { hosts = { ['known.host'] = { extra_args = { '-O' } } } }
      local cfg = vim.g.canola_ssh
      assert.is_nil(cfg.hosts['unknown.host'])
    end)
  end)

  describe('vim.g.canola_s3', function()
    it('stores per-bucket overrides', function()
      vim.g.canola_s3 = {
        buckets = {
          ['my-r2-bucket'] = { extra_args = { '--endpoint-url', 'https://r2.example.com' } },
        },
      }
      local cfg = vim.g.canola_s3
      assert.are.equal('--endpoint-url', cfg.buckets['my-r2-bucket'].extra_args[1])
      assert.are.equal('https://r2.example.com', cfg.buckets['my-r2-bucket'].extra_args[2])
    end)

    it('defaults to nil when not set', function()
      assert.is_nil(vim.g.canola_s3)
    end)

    it('returns nil for unknown bucket', function()
      vim.g.canola_s3 = {
        buckets = { ['known-bucket'] = { extra_args = { '--no-sign-request' } } },
      }
      local cfg = vim.g.canola_s3
      assert.is_nil(cfg.buckets['unknown-bucket'])
    end)
  end)

  describe('vim.g.canola_ftp', function()
    it('stores per-host overrides', function()
      vim.g.canola_ftp = {
        hosts = { ['ftp.internal.com'] = { extra_args = { '--insecure' } } },
      }
      local cfg = vim.g.canola_ftp
      assert.are.equal('--insecure', cfg.hosts['ftp.internal.com'].extra_args[1])
    end)

    it('defaults to nil when not set', function()
      assert.is_nil(vim.g.canola_ftp)
    end)

    it('returns nil for unknown host', function()
      vim.g.canola_ftp = {
        hosts = { ['known.host'] = { extra_args = { '--insecure' } } },
      }
      local cfg = vim.g.canola_ftp
      assert.is_nil(cfg.hosts['unknown.host'])
    end)

    it('reflects --insecure in per-host config', function()
      vim.g.canola_ftp = {
        hosts = { ['ftp.internal.com'] = { extra_args = { '--insecure' } } },
      }
      local cfg = vim.g.canola_ftp
      local host_cfg = cfg.hosts['ftp.internal.com']
      assert.is_truthy(vim.tbl_contains(host_cfg.extra_args, '--insecure'))
    end)
  end)

  describe('merge semantics', function()
    it('per-host ssh args are separate from global args', function()
      vim.g.canola_ssh = {
        extra_args = { '-C' },
        hosts = { ['myserver.com'] = { extra_args = { '-O' } } },
      }
      local cfg = vim.g.canola_ssh
      assert.are.same({ '-C' }, cfg.extra_args)
      assert.are.same({ '-O' }, cfg.hosts['myserver.com'].extra_args)
    end)

    it('per-bucket s3 args are separate from global args', function()
      vim.g.canola_s3 = {
        extra_args = { '--sse', 'aws:kms' },
        buckets = {
          ['special-bucket'] = { extra_args = { '--endpoint-url', 'https://...' } },
        },
      }
      local cfg = vim.g.canola_s3
      assert.are.same({ '--sse', 'aws:kms' }, cfg.extra_args)
      assert.are.same({ '--endpoint-url', 'https://...' }, cfg.buckets['special-bucket'].extra_args)
    end)
  end)
end)
