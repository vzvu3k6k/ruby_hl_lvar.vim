let s:self_path=expand("<sfile>")

execute 'rubyfile '.s:self_path.'.rb'

let s:hl_version = 0

function! ruby_hl_lvar#redraw() abort
	let curwinnr=winnr()
	let prevwinnr=winnr('#')

	let nr = 1
	let lastnr = winnr('$')
	while nr <= lastnr
		execute nr . "wincmd w"
		call s:redraw_window()
		let nr += 1
	endwhile

	if prevwinnr > 0
		execute prevwinnr . "wincmd w"
	endif
	execute curwinnr . "wincmd w"
endfunction

function! s:redraw_window()
	let wv = get(w:, 'ruby_hl_lvar_hl_version', 0)
	let bv = get(b:, 'ruby_hl_lvar_hl_version', 0)

	" Remove current match if exists and its not for current buffer
	if wv
		if bv && (wv == bv)
			return
		else
			call s:try_matchdelete(w:ruby_hl_lvar_match_id)
			let w:ruby_hl_lvar_hl_version = 0
		endif
	endif

	" Set match if exists
	if get(b:, 'ruby_hl_lvar_enabled', 1) && get(b:, 'ruby_hl_lvar_match_pattern', '') != ''
		let w:ruby_hl_lvar_match_id = matchadd(g:ruby_hl_lvar_hl_group, b:ruby_hl_lvar_match_pattern, 0)
		let w:ruby_hl_lvar_hl_version = bv
	endif
endfunction

" return: [[var_name, row, col_start, col_end]...]
function! ruby_hl_lvar#extract_lvars(buffer) abort
  let bufnr = bufnr(a:buffer)
  if exists('s:ret')
    unlet s:ret
  endif
  let t = reltime()
  execute 'ruby RubyHlLvar::Vim.extract_lvars_from '.bufnr
  let b:ruby_hl_lvar_time = str2float(reltimestr(reltime(t)))
  let ret = s:ret
  unlet s:ret
  return ret
endfunction

function! ruby_hl_lvar#disable(force) abort
	if exists('b:ruby_hl_lvar_match_pattern')
		unlet b:ruby_hl_lvar_match_pattern
		unlet b:ruby_hl_lvar_hl_version
	endif
	if a:force
		let b:ruby_hl_lvar_enabled = 0
	endif
	call ruby_hl_lvar#redraw()
endfunction

function! s:try_matchdelete(id)
	if a:id < 0
		return
	endif
	try
		call matchdelete(a:id)
	catch /E803:/
	endtry
endfunction

function! ruby_hl_lvar#enable(force) abort
	if !a:force && exists('b:ruby_hl_lvar_enabled') && !b:ruby_hl_lvar_enabled
		return
	endif
	call ruby_hl_lvar#disable(a:force)
	if !exists('b:ruby_hl_lvar_match_pattern')
		call ruby_hl_lvar#update_match_pattern('%')
	endif
	if a:force
		let b:ruby_hl_lvar_enabled = 1
	endif

	call ruby_hl_lvar#redraw()
endfunction

function! ruby_hl_lvar#refresh(force) abort
	if !a:force && exists('b:ruby_hl_lvar_enabled') && !b:ruby_hl_lvar_enabled
		return
	endif

	" https://github.com/todesking/ruby_hl_lvar.vim/pull/3
	" Auto refreshing function triggered by TextChanged event is disabling
	" https://github.com/t9md/vim-textmanip that continuously reselect previous selection.
	" This code will check if in visual mode, and if so, it won't refresh (redraw) buffer.
	if mode() =~# "^[vV\<C-v>]"
		return
	endif

	if exists('b:ruby_hl_lvar_match_pattern')
		unlet b:ruby_hl_lvar_match_pattern
	endif
	call ruby_hl_lvar#enable(a:force)
endfunction

function! ruby_hl_lvar#update_match_pattern(buffer) abort
	let matches = map(ruby_hl_lvar#extract_lvars(a:buffer), '
		\ ''\%''.v:val[1].''l''.''\%''.v:val[2].''c''.repeat(''.'', strchars(v:val[0]))
		\ ')
	let b:ruby_hl_lvar_match_pattern = join(matches, '\|')
	let s:hl_version += 1
	let b:ruby_hl_lvar_hl_version = s:hl_version
endfunction

