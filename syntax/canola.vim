if exists("b:current_syntax")
  finish
endif

syn match canolaId /^\/\d* / conceal

let b:current_syntax = "canola"
