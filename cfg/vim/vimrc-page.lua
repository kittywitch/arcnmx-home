local modname = 'arc-config'
local repeated = package.loaded[modname] ~= nil
local mod
if not repeated then
	mod = {}
	package.loaded[modname] = mod
else
	mod = package.loaded[modname]
end
mod.page = {}

local manpager_name = os.getenv('MAN_PN')
local is_page = os.getenv('PAGE_NVIM') ~= nil

function mod.page.close(page_alternate_bufnr)
	vim.cmd('bd!')
	if vim.fn.bufnr('%') == page_alternate_bufnr and vim.fn.mode('%') == 'n' then
		vim.cmd('norm a')
	end
end

function mod.page.move_to_buf()
	vim.cmd('%y p')
	vim.cmd('enew!')
	-- vim.cmd('bd! #')
	-- vim.cmd('bunload! #')
	vim.cmd('pu p')
	vim.fn.cursor(1, 1)
	vim.cmd('d')
end

function mod.page.apply()
	if manpager_name ~= nil then
		mod.page.move_to_buf()
	elseif is_file then
		vim.cmd('bd!')
	end

	if manpager_name ~= nil then
		vim.bo.filetype = 'man'
		vim.fn.cursor(3, 1)
	else
		vim.fn.cursor(1, 1)
	end

	vim.wo.number = true
	vim.wo.scrolloff = 999
	if vim.bo.buftype ~= 'terminal' then
		vim.bo.buftype = 'nofile'
	end
	vim.bo.modifiable = false
	vim.fn.cursor(1, 1)

	for _, mode in pairs({''}) do -- 't'?
		--vim.api.nvim_buf_set_keymap(0, mode, 'q', [[:call luaeval('require("arc-config").page.close')(b:page_alternate_bufnr)<CR>]], {})
		vim.api.nvim_buf_set_keymap(0, mode, 'q', ':quit<CR>', {})
		vim.api.nvim_buf_set_keymap(0, mode, '<space>', '<C-d>', {})
	end
	if vim.bo.buftype == 'terminal' then
		for _, key in pairs({'i', 'I', 'a', 'A'}) do
			vim.api.nvim_buf_set_keymap(0, 'n', key, '<nop>', {})
		end
	end
end

function mod.page.on_open()
	if vim.fn.exists(':CocDisable') ~= 0 then
		vim.cmd('silent! CocDisable')
	end
	if vim.fn.exists(':HexokinaseTurnOff') ~= 0 then
		vim.cmd('silent! HexokinaseTurnOff')
	end

	-- remove default page bindings
	local function unmap_page()
		vim.api.nvim_buf_del_keymap(0, '', 'I')
		vim.api.nvim_buf_del_keymap(0, '', 'A')
		vim.api.nvim_buf_del_keymap(0, '', 'i')
		vim.api.nvim_buf_del_keymap(0, '', 'a')
		vim.api.nvim_buf_del_keymap(0, '', 'u')
		vim.api.nvim_buf_del_keymap(0, '', 'd')
	end
	pcall(unmap_page) -- don't fail if they don't exist

	if manpager_name ~= nil then
		vim.defer_fn(mod.page.apply, 128)
	else
		vim.defer_fn(mod.page.apply, 48)
	end
end

function mod.page.on_disconnect()
	if manpager_name ~= nil then
		-- suggested by readme but I'm not really sure why?
		-- vim.cmd('sleep 100m')
	end
end

if not repeated then
	vim.cmd("autocmd User PageOpen lua require('arc-config').page.on_open()")
	vim.cmd("autocmd User PageDisconnect lua require('arc-config').page.on_disconnect()")

	if is_page then
		vim.g.surround_no_mappings = 1
		vim.g.Hexokinase_ftEnabled = {}
	end
end
