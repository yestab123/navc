" Copyright 2015 Google Inc. All Rights Reserved.
"
" Licensed under the Apache License, Version 2.0 (the "License");
" you may not use this file except in compliance with the License.
" You may obtain a copy of the License at
"
"    http://www.apache.org/licenses/LICENSE-2.0
"
" Unless required by applicable law or agreed to in writing, software
" distributed under the License is distributed on an "AS IS" BASIS,
" WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
" See the License for the specific language governing permissions and
" limitations under the License.

" Very simple plugin that takes the symbol in the current cursor, query navc
" daemon and point the cursor to the disered location. For this to run
" properly, the PYTHONPATH has to be set. From the root of the project
" directory: PYTHONPATH=third_party/jsonrpc/ vim
"
" To use, simply source this file in vim, put the cursor on top of the symbol
" of interest, and call the function FindCursorSymbolDecl(). In vim :source
" editor/vim/navc.vim (move cursor to symbol) :call FindCursorSymbolDecl()

if !has('python')
	echo "Error: Required vim compiled with +python"
	finish
endif

python << EOF
import vim
import re
import os
import sys
sys.path.append(os.path.expanduser('~/.vim/plugin/navc/'))
import jsonrpc

fname_char = re.compile('[a-zA-Z_]')

prev_locs = []

def find_start_cur_symbol():
	row, col = vim.current.window.cursor
	while fname_char.match(vim.current.buffer[row - 1][col - 1]):
		col -= 1
	return (row, col + 1)

def get_choice():
	vim.command("call inputsave()")
	vim.command("let choice = input('Input Choice<empty to cancel>: ')")
	vim.command("call inputrestore()")
	return vim.eval("choice")

def get_choice_int():
	# TODO: we need to make sure that a number was given and that it is
	# within boundaries.
	ch = get_choice()
	if not ch:
		raise ValueError('No choice')
	return int(ch)

def conn():
	return jsonrpc.ServerProxy(jsonrpc.JsonRpc10(),
			jsonrpc.TransportUnixSocket(addr='.navc.sock'))

def get_cursor_input():
	line, col = find_start_cur_symbol()
	fname = os.path.relpath(vim.current.buffer.name)

	args = {
		"File": fname,
		"Line": line,
		"Col": col,
	}

	return args

def _move_cursor(fname, line, col):
	vim.command('edit %s' % fname)
	vim.current.window.cursor = (line, col)

def move_cursor(fname, line, col):
	prow, pcol = vim.current.window.cursor
	pfname = vim.current.buffer.name
	prev_locs.append((pfname, prow, pcol))
	_move_cursor(fname, line, col)

def get_file_line(fname, line):
	# TODO: this is less than optimal, but it does the trick. A vim
	# implementation may be more efficient.
	with open(fname, 'r') as f:
		return f.readlines()[line - 1].strip()

def print_error(s):
	vim.command(':echohl Error | echo "'+s+'" | echohl None')

def print_warn(s):
	vim.command(':echohl WarningMsg | echo "'+s+'" | echohl None')

def get_multi_choice(options):
	if len(options) > 1:
		num = 1
		for op in options:
			line = get_file_line(op['File'], op['Line'])
			print "(%2d) %s %d\n     %s" % \
				(num, op['File'], op['Line'], line)
			num += 1
		ch = get_choice_int()
		ch -= 1
	else:
		ch = 0

	return ch

EOF

" This function will find the declaration of the symbol currently under the
" cursor.
function! FindCursorSymbolDecls()
python << EOF

try:
	ret = conn().RequestHandler.GetSymbolDecls(get_cursor_input())
	ch = get_multi_choice(ret)
	move_cursor(ret[ch]['File'], ret[ch]['Line'], ret[ch]['Col'] - 1)
except jsonrpc.RPCFault as e:
	print_error(e.error_data)

EOF
endfunction

" This function will find all the uses of symbol declaration. This should work
" well to find all symbols use of a declaration in a header file.
function! FindCursorSymbolUses()
python << EOF
try:
	ret = conn().RequestHandler.GetSymbolUses(get_cursor_input())
	ch = get_multi_choice(ret)
	move_cursor(ret[ch]['File'], ret[ch]['Line'], ret[ch]['Col'] - 1)
except jsonrpc.RPCFault as e:
	print_error(e.error_data)
except ValueError:
	pass
EOF
endfunction

function! FindCursorSymbolDef()
python << EOF
try:
	ret = conn().RequestHandler.GetSymbolDef(get_cursor_input())
	ch = get_multi_choice(ret)
	move_cursor(ret[ch]['File'], ret[ch]['Line'], ret[ch]['Col'] - 1)
except jsonrpc.RPCFault as e:
	print_error(e.error_data)
except ValueError:
	pass
EOF
endfunction

function! MoveCursorToPrev()
python << EOF
if len(prev_locs) > 0:
	pfname, prow, pcol = prev_locs.pop()
	_move_cursor(pfname, prow, pcol)
EOF
endfunction

nnoremap <C-z>e :call FindCursorSymbolDecls()<ENTER>
nnoremap <C-z>b :call MoveCursorToPrev()<ENTER>
nnoremap <C-z>u :call FindCursorSymbolUses()<ENTER>
nnoremap <C-z>d :call FindCursorSymbolDef()<ENTER>
