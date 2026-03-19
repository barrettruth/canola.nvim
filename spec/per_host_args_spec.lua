local config = require('canola.config')
local test_util = require('spec.test_util')

describe('per-host/bucket arg overrides', function()
  after_each(function()
    test_util.reset_editor()
  end)

  describe('ssh_hosts', function()
    it('stores ssh_hosts from vim.g.canola', function()
      vim.g.canola = { ssh_hosts = { ['myserver.com'] = { extra_scp_args = { '-O' } } } }
      config.init()
      assert.are.equal('-O', config.ssh_hosts['myserver.com'].extra_scp_args[1])
    end)

    it('defaults to empty table when not set', function()
      vim.g.canola = {}
      config.init()
      assert.are.same({}, config.ssh_hosts)
    end)

    it('returns nil for unknown host', function()
      vim.g.canola = { ssh_hosts = { ['known.host'] = { extra_scp_args = { '-O' } } } }
      config.init()
      assert.is_nil(config.ssh_hosts['unknown.host'])
    end)
  end)

  describe('s3_buckets', function()
    it('stores s3_buckets from vim.g.canola', function()
      vim.g.canola = {
        s3_buckets = {
          ['my-r2-bucket'] = { extra_s3_args = { '--endpoint-url', 'https://r2.example.com' } },
        },
      }
      config.init()
      assert.are.equal('--endpoint-url', config.s3_buckets['my-r2-bucket'].extra_s3_args[1])
      assert.are.equal('https://r2.example.com', config.s3_buckets['my-r2-bucket'].extra_s3_args[2])
    end)

    it('defaults to empty table when not set', function()
      vim.g.canola = {}
      config.init()
      assert.are.same({}, config.s3_buckets)
    end)

    it('returns nil for unknown bucket', function()
      vim.g.canola = {
        s3_buckets = { ['known-bucket'] = { extra_s3_args = { '--no-sign-request' } } },
      }
      config.init()
      assert.is_nil(config.s3_buckets['unknown-bucket'])
    end)
  end)

  describe('ftp_hosts', function()
    it('stores ftp_hosts from vim.g.canola', function()
      vim.g.canola =
        { ftp_hosts = { ['ftp.internal.com'] = { extra_curl_args = { '--insecure' } } } }
      config.init()
      assert.are.equal('--insecure', config.ftp_hosts['ftp.internal.com'].extra_curl_args[1])
    end)

    it('defaults to empty table when not set', function()
      vim.g.canola = {}
      config.init()
      assert.are.same({}, config.ftp_hosts)
    end)

    it('returns nil for unknown host', function()
      vim.g.canola = { ftp_hosts = { ['known.host'] = { extra_curl_args = { '--insecure' } } } }
      config.init()
      assert.is_nil(config.ftp_hosts['unknown.host'])
    end)

    it('reflects --insecure in per-host curl args', function()
      vim.g.canola =
        { ftp_hosts = { ['ftp.internal.com'] = { extra_curl_args = { '--insecure' } } } }
      config.init()
      local host_cfg = config.ftp_hosts['ftp.internal.com']
      assert.is_truthy(vim.tbl_contains(host_cfg.extra_curl_args, '--insecure'))
    end)
  end)

  describe('merge semantics', function()
    it('per-host ssh args supplement global args', function()
      vim.g.canola = {
        extra_scp_args = { '-C' },
        ssh_hosts = { ['myserver.com'] = { extra_scp_args = { '-O' } } },
      }
      config.init()
      assert.are.same({ '-C' }, config.extra_scp_args)
      assert.are.same({ '-O' }, config.ssh_hosts['myserver.com'].extra_scp_args)
    end)

    it('per-bucket s3 args supplement global args', function()
      vim.g.canola = {
        extra_s3_args = { '--sse', 'aws:kms' },
        s3_buckets = {
          ['special-bucket'] = { extra_s3_args = { '--endpoint-url', 'https://...' } },
        },
      }
      config.init()
      assert.are.same({ '--sse', 'aws:kms' }, config.extra_s3_args)
      assert.are.same(
        { '--endpoint-url', 'https://...' },
        config.s3_buckets['special-bucket'].extra_s3_args
      )
    end)
  end)
end)
