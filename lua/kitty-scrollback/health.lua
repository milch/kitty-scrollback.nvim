---@mod kitty-scrollback.health
local M = {}

---@type KsbPrivate
local p

---@type KsbOpts
local opts ---@diagnostic disable-line: unused-local

M.setup = function(private, options)
  p = private
  opts = options ---@diagnostic disable-line: unused-local
end

local function check_kitty_remote_control()
  vim.health.start('kitty-scrollback: Kitty remote control')
  local cmd = {
    -- fallback to 'kitty' because checkhealth can be called outside of standard setup flow
    (p and p.kitty_data and p.kitty_data.kitty_path) and p.kitty_data.kitty_path or 'kitty',
    '@',
    'ls',
  }
  local sys_opts = {}
  local proc = vim.system(cmd, sys_opts or {})
  local result = proc:wait()
  local ok = result.code == 0
  local code_msg = '`kitty @ ls` exited with code *' .. result.code .. '*'
  if ok then
    vim.health.ok(code_msg)
    return true
  else
    local stderr = result.stderr:gsub('\n', '') or ''
    local msg = {}
    if stderr:match('.*/dev/tty.*') then
      msg = M.advice().listen_on
    end
    if stderr:match('.*allow_remote_control.*') then
      msg = M.advice().allow_remote_control
    end
    local advice = {
      table.concat(msg, '\n'),
    }
    local kitty_opts = {}
    if type(p) == 'table' and next(p.kitty_data) then
      kitty_opts = p.kitty_data.kitty_opts
      table.insert(
        advice,
        table.concat({
          '*allow_remote_control* and *listen_on* are currently configured as:',
          '  `allow_remote_control ' .. kitty_opts.allow_remote_control .. '`',
          '  `listen_on ' .. kitty_opts.listen_on .. '`',
        }, '\n')
      )
    else
      table.insert(advice, 'ERROR Failed to read `allow_remote_control` and `listen_on`')
    end
    vim.health.error(code_msg .. '\n      `' .. stderr .. '` ', advice)
  end
  return false
end

local function check_has_kitty_data()
  vim.health.start('kitty-scrollback: Kitty data')
  if type(p) == 'table' and next(p.kitty_data) then
    vim.health.ok('Kitty data available\n>lua\n' .. vim.inspect(p.kitty_data) .. '\n')
    return true
  else
    local kitty_scrollback_kitten =
      vim.api.nvim_get_runtime_file('python/kitty_scrollback_nvim.py', false)[1]
    local checkhealth_command = '`kitty @ kitten '
      .. kitty_scrollback_kitten
      .. ' --config ksb_builtin_checkhealth`'
    vim.health.warn('No Kitty data available unable to perform a complete healthcheck', {
      'Execute the command `:KittyScrollbackCheckHealth` or add the config options `checkhealth = true` to your *config* '
        .. 'to run `checkhealth` within the context of a Kitten',
      checkhealth_command,
    })
  end
  return false
end

local function check_clipboard()
  local function is_blank(s)
    return s:find('^%s*$') ~= nil
  end
  vim.health.start('kitty-scrollback: clipboard')
  local clipboard_tool = vim.fn['provider#clipboard#Executable']() -- copied from health.lua
  if vim.fn.has('clipboard') > 0 and not is_blank(clipboard_tool) then
    vim.health.ok('Clipboard tool found: *' .. clipboard_tool .. '*')
  else
    vim.health.warn(
      'Neovim does not have a clipboard provider.\n        Some functionality will not work when there is no clipboard '
        .. 'provider, such as copying Kitty scrollback buffer text to the system clipboard.',
      'See `:help` |provider-clipboard| for more information on enabling system clipboard integration.'
    )
  end
end

local function check_sed()
  vim.health.start('kitty-scrollback: sed')
  local sed_path = vim.fn.exepath('sed')
  if not sed_path or sed_path == '' then
    vim.health.error('*sed* : command not found\n')
    return
  end

  local esc = vim.fn.eval([["\e"]])
  local cmd = {
    'sed',
    '-E',
    '-e',
    's/$/' .. esc .. '[0m/g',
    '-e',
    's/' .. esc .. '\\[\\?25.' .. esc .. '\\[.*;.*H' .. esc .. '\\[.*//g',
  }
  local ok, sed_proc = pcall(vim.system, cmd, {
    stdin = 'expected' .. esc .. '[?25h' .. esc .. '[1;1H' .. esc .. '[notexpected',
  })
  local result = {}
  if ok then
    result = sed_proc:wait()
  else
    result.code = -999
    result.stdout = ''
    result.stderr = sed_proc
  end
  ok = ok and result.code == 0 and result.stdout == 'expected'
  if ok then
    vim.health.ok(
      '`'
        .. table.concat(cmd, ' ')
        .. '` exited with code *'
        .. result.code
        .. '* and stdout `'
        .. result.stdout
        .. '`\n'
        .. '   `sed: '
        .. sed_path
        .. '`'
    )
  else
    local result_err = result.stderr:gsub('\n', '')
    if result_err ~= '' then
      result_err = '      `' .. result_err .. '`'
    end
    vim.health.error(
      '`'
        .. table.concat(cmd, ' ')
        .. '` exited with code *'
        .. result.code
        .. '* and stdout `'
        .. result.stdout
        .. '` (should be `expected`)\n'
        .. result_err
        .. '`\n'
        .. '   `sed: '
        .. sed_path
        .. '`'
    )
  end
end

M.check_nvim_version = function(version, check_only)
  if not check_only then
    vim.health.start('kitty-scrollback: Neovim version 0.9+')
  end
  local nvim_version = 'NVIM ' .. tostring(vim.version())
  if vim.fn.has(version) > 0 then
    if not check_only then
      vim.health.ok(nvim_version)
      if vim.fn.has('nvim-0.10') <= 0 then
        vim.health.info(
          'If you are using a version of nvim that is less than 0.10, then formatting on this checkhealth may be malformed'
        )
      end
    end
    return true
  else
    if not check_only then
      vim.health.error(nvim_version, M.advice().nvim_version)
    end
  end
  return false
end

M.check_kitty_version = function(check_only)
  if not check_only then
    vim.health.start('kitty-scrollback: Kitty version 0.29+')
  end
  local kitty_version = p.kitty_data.kitty_version
  local kitty_version_str = 'kitty ' .. table.concat(kitty_version, '.')
  if vim.version.cmp(kitty_version, { 0, 29, 0 }) >= 0 then
    if not check_only then
      vim.health.ok(kitty_version_str)
    end
    return true
  else
    if not check_only then
      vim.health.error(kitty_version_str, M.advice().kitty_version)
    end
  end
  return false
end

local function check_kitty_debug_config()
  vim.health.start('kitty-scrollback: Kitty debug config')
  local kitty_debug_config_kitten =
    vim.api.nvim_get_runtime_file('python/kitty_debug_config.py', false)[1]
  local debug_config_log = vim.fn.stdpath('data') .. '/kitty-scrollback.nvim/debug_config.log'
  local result = vim
    .system({ p.kitty_data.kitty_path, '@', 'kitten', kitty_debug_config_kitten, debug_config_log })
    :wait()
  if result.code == 0 then
    if vim.fn.filereadable(debug_config_log) then
      vim.health.ok(table.concat(vim.fn.readfile(debug_config_log), '\n   '))
    else
      vim.health.error('cannot read ' .. debug_config_log)
    end
  else
    local stderr = result.stderr:gsub('\n', '') or ''
    vim.health.error(stderr)
  end
end

local function check_kitty_scrollback_nvim_version()
  local current_version = nil
  local tag_cmd = { 'git', 'describe', '--exact-match', '--tags' }
  local ksb_dir =
    vim.fn.fnamemodify(vim.api.nvim_get_runtime_file('lua/kitty-scrollback', false)[1], ':h:h')
  local tag_cmd_result = vim.system(tag_cmd, { cwd = ksb_dir }):wait()
  if tag_cmd_result.code == 0 then
    current_version = tag_cmd_result.stdout
  else
    local commit_cmd = { 'git', 'rev-parse', '--short', 'HEAD' }
    local commit_cmd_result = vim.system(commit_cmd, { cwd = ksb_dir }):wait()
    if commit_cmd_result.code == 0 then
      current_version = commit_cmd_result.stdout
    end
  end
  local version_found = current_version and current_version ~= ''
  local header = '*kitty-scrollback.nvim* @ '
    .. (
      version_found and '`' .. current_version:gsub('%s$', '`\n') ---@diagnostic disable-line: need-check-nil
      or 'ERROR failed to determine version\n'
    )
  local health_fn = not version_found and vim.health.warn
    or function(msg)
      vim.health.ok('     ' .. msg)
    end
  vim.health.start('kitty-scrollback: kitty-scrollback.nvim version')
  health_fn([[  `|`\___/`|`       ]] .. header .. [[
         =) `^`Y`^` (=
          \  *^*  /       If you have any issues or questions using *kitty-scrollback.nvim* then     
          ` )=*=( `       please create an issue at                                                    
          /     \       https://github.com/mikesmithgh/kitty-scrollback.nvim/issues and              
          |     |       provide the `KittyScrollbackCheckHealth` report.                               
         /| | | |\                                                                                    
         \| | `|`_`|`/\
          /_// ___/     *Bonus* *points* *for* *cat* *memes*
             \_)       ]])

  -- Always consider true even if git version is not found to provide additional health checks
  return true
end

M.check = function()
  require('kitty-scrollback.backport').setup()
  if
    M.check_nvim_version('nvim-0.9')
    and check_kitty_scrollback_nvim_version()
    and check_kitty_remote_control()
    and check_has_kitty_data()
    and M.check_kitty_version()
  then
    check_clipboard()
    check_sed()
    check_kitty_debug_config()
  end
end

---@class KsbAdvice
---@field allow_remote_control table
---@field listen_on table
---@field kitty_shell_integration table
---@field nvim_version table
---@field kitty_version table

---@return KsbAdvice
M.advice = function()
  local extent = 'nil'
  local ansi = 'nil'
  local clear_selection = 'nil'
  if opts then
    extent = opts.kitty_get_text.extent
    ansi = tostring(opts.kitty_get_text.ansi)
    clear_selection = tostring(opts.kitty_get_text.clear_selection)
  end

  local shell_integration = 'nil'
  if p then
    shell_integration = table.concat(p.kitty_data.kitty_opts.shell_integration, ' ')
  end
  return {
    nvim_version = {
      'Neovim version 0.9 or greater is required to work with kitty-scrollback.nvim',
    },
    kitty_version = {
      'Kitty version 0.29 or greater is required to work with kitty-scrollback.nvim',
    },
    allow_remote_control = {
      'Kitty must be configured to allow remote control connections. Add the configuration',
      '*allow_remote_control* to Kitty. For example, `allow_remote_control socket-only`',
      'Changing *allow_remote_control* by reloading the config is not supported so you must ',
      'completely close and reopen Kitty for the change to take effect.',
      '',
      'Compatible values with kitty-scrollback.nvim for the option *allow_remote_control* are',
      '`yes`, `socket`, or `socket-only`.',
      '',
      'See https://sw.kovidgoyal.net/kitty/conf/#opt-kitty.allow_remote_control for additional',
      'information on configuring the *allow_remote_control* option.',
      '',
    },
    listen_on = {
      'Kitty must be configured to listen on a Unix socket for remote control connections.',
      'Add the configuration *listen_on* to Kitty. For example, `listen_on unix:/tmp/mykitty`',
      'Changing *listen_on* by reloading the config is not supported so you must completely',
      'close and reopen Kitty for the change to take effect.',
      '',
      'See https://sw.kovidgoyal.net/kitty/conf/#opt-kitty.listen_on for additional information',
      'on configuring the *listen_on* option.',
      '',
      'If *listen_on* is properly configured, check that the option *allow_remote_control* is',
      'set to either `yes`, `socket`, or `socket-only`.',
      '',
      'See https://sw.kovidgoyal.net/kitty/conf/#opt-kitty.allow_remote_control for additional',
      'information on configuring the *allow_remote_control* option.',
      '',
    },
    kitty_shell_integration = {
      'Remove `disabled` and `no-prompt-mark` from *shell_integration* if present in your Kitty configuration.',
      '',
      'Current *kitty_get_text* options:',
      '`    opts = {`',
      '`        kitty_get_text = {`',
      [[`            extent = ']] .. extent .. [[',`]],
      [[`            ansi = ]] .. ansi .. [[,`]],
      [[`            clear_selection = ]] .. clear_selection .. [[,`]],
      '`        },`',
      '`    }`',
      '',
      'See https://sw.kovidgoyal.net/kitty/remote-control/#cmdoption-kitty-get-text-extent for',
      'more information on *extent* or run `kitty @ get-text --help`',
      '',
      'Current *shell_integration* options:',
      [[`    KITTY_SHELL_INTEGRATION=']] .. shell_integration .. [['`]],
      '',
      'See https://sw.kovidgoyal.net/kitty/conf/#opt-kitty.shell_integration for more information',
      'on *shell_integration*',
    },
  }
end

return M
