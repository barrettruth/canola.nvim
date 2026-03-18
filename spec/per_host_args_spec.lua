local config = require('oil.config')
local test_util = require('spec.test_util')

describe('per-host/bucket arg overrides', function()
  after_each(function()
    test_util.reset_editor()
  end)

  describe('ssh_hosts', function()
    it('stores ssh_hosts from setup', function()
      config.setup({ ssh_hosts = { ['myserver.com'] = { extra_scp_args = { '-O' } } } })
      assert.are.equal('-O', config.ssh_hosts['myserver.com'].extra_scp_args[1])
    end)

    it('defaults to empty table when not set', function()
      config.setup({})
      assert.are.same({}, config.ssh_hosts)
    end)

    it('returns nil for unknown host', function()
      config.setup({ ssh_hosts = { ['known.host'] = { extra_scp_args = { '-O' } } } })
      assert.is_nil(config.ssh_hosts['unknown.host'])
    end)
  end)

  describe('s3_buckets', function()
    it('stores s3_buckets from setup', function()
      config.setup({
        s3_buckets = {
          ['my-r2-bucket'] = { extra_s3_args = { '--endpoint-url', 'https://r2.example.com' } },
        },
      })
      assert.are.equal('--endpoint-url', config.s3_buckets['my-r2-bucket'].extra_s3_args[1])
      assert.are.equal('https://r2.example.com', config.s3_buckets['my-r2-bucket'].extra_s3_args[2])
    end)

    it('defaults to empty table when not set', function()
      config.setup({})
      assert.are.same({}, config.s3_buckets)
    end)

    it('returns nil for unknown bucket', function()
      config.setup({
        s3_buckets = { ['known-bucket'] = { extra_s3_args = { '--no-sign-request' } } },
      })
      assert.is_nil(config.s3_buckets['unknown-bucket'])
    end)
  end)

  describe('ftp_hosts', function()
    it('stores ftp_hosts from setup', function()
      config.setup({ ftp_hosts = { ['ftp.internal.com'] = { extra_curl_args = { '--insecure' } } } })
      assert.are.equal('--insecure', config.ftp_hosts['ftp.internal.com'].extra_curl_args[1])
    end)

    it('defaults to empty table when not set', function()
      config.setup({})
      assert.are.same({}, config.ftp_hosts)
    end)

    it('returns nil for unknown host', function()
      config.setup({ ftp_hosts = { ['known.host'] = { extra_curl_args = { '--insecure' } } } })
      assert.is_nil(config.ftp_hosts['unknown.host'])
    end)

    it('reflects --insecure in per-host curl args', function()
      config.setup({ ftp_hosts = { ['ftp.internal.com'] = { extra_curl_args = { '--insecure' } } } })
      local host_cfg = config.ftp_hosts['ftp.internal.com']
      assert.is_truthy(vim.tbl_contains(host_cfg.extra_curl_args, '--insecure'))
    end)
  end)

  describe('merge semantics', function()
    it('per-host ssh args supplement global args', function()
      config.setup({
        extra_scp_args = { '-C' },
        ssh_hosts = { ['myserver.com'] = { extra_scp_args = { '-O' } } },
      })
      assert.are.same({ '-C' }, config.extra_scp_args)
      assert.are.same({ '-O' }, config.ssh_hosts['myserver.com'].extra_scp_args)
    end)

    it('per-bucket s3 args supplement global args', function()
      config.setup({
        extra_s3_args = { '--sse', 'aws:kms' },
        s3_buckets = {
          ['special-bucket'] = { extra_s3_args = { '--endpoint-url', 'https://...' } },
        },
      })
      assert.are.same({ '--sse', 'aws:kms' }, config.extra_s3_args)
      assert.are.same(
        { '--endpoint-url', 'https://...' },
        config.s3_buckets['special-bucket'].extra_s3_args
      )
    end)
  end)
end)
